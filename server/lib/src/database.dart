import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Bump this whenever a migration is appended to [_migrations].
const currentSchemaVersion = 2;

/// Ordered schema migrations, indexed by the version they upgrade *to*.
///
/// Versioning uses sqlite's own `PRAGMA user_version`, so no bookkeeping table
/// is needed. Every migration must be safe to run against a database that
/// already has the shape it is trying to create: instances deployed before
/// versioning existed report `user_version = 0` while already having the v1
/// tables, so v1 has to be idempotent rather than assume an empty file.
///
/// Note this is the *server's* database -- accounts, sessions and the sync
/// change feed. It has no relationship to the app's Drift database
/// (transactions, budgets, wallets), which is what a Cashew backup file
/// contains. Changing anything here cannot affect a backup's restorability.
final Map<int, void Function(Database db)> _migrations = {
  1: _migrateToV1,
  2: _migrateToV2,
};

/// Everything that existed before schema versioning was introduced, including
/// the Stage 2 change feed.
///
/// A deployment created by an earlier build already has all of this and reports
/// `user_version = 0`, so every statement here is `IF NOT EXISTS` and safe to
/// re-run against a live database.
void _migrateToV1(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
  ''');
  // Row-level change feed (Stage 2 -- see specs/04-stage-2-instant-sync.md).
  // One row per record, not per change: applying only the newest version of
  // a row is equivalent to replaying its whole history under last-write-wins,
  // so this table's size is bounded by data size, never by sync history.
  db.execute('''
    CREATE TABLE IF NOT EXISTS sync_records (
      user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      table_name  TEXT    NOT NULL,
      pk          TEXT    NOT NULL,
      seq         INTEGER NOT NULL,
      deleted     INTEGER NOT NULL DEFAULT 0,
      modified_at INTEGER NOT NULL,
      device_id   TEXT    NOT NULL,
      payload     TEXT,
      PRIMARY KEY (user_id, table_name, pk)
    );
  ''');
  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_sync_records_feed ON sync_records(user_id, seq);
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS sync_state (
      user_id          INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      next_seq         INTEGER NOT NULL DEFAULT 1,
      min_retained_seq INTEGER NOT NULL DEFAULT 0
    );
  ''');
}

/// Adds the display name and the admin role.
///
/// The `UPDATE` matters: an instance provisioned before roles existed has users
/// but no admin, and every admin-only endpoint would be unreachable on it --
/// including the one that grants admin. Promoting the earliest account (the
/// operator, in practice) keeps an existing deployment administrable.
void _migrateToV2(Database db) {
  final columns = db
      .select('PRAGMA table_info(users)')
      .map((row) => row['name'] as String)
      .toSet();
  if (!columns.contains('name')) {
    db.execute("ALTER TABLE users ADD COLUMN name TEXT NOT NULL DEFAULT ''");
  }
  if (!columns.contains('is_admin')) {
    db.execute('ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0');
  }
  db.execute(
    'UPDATE users SET is_admin = 1 '
    'WHERE id = (SELECT id FROM users ORDER BY id LIMIT 1)',
  );
}

/// Applies every migration newer than the database's recorded version.
void migrate(Database db) {
  var version = db.select('PRAGMA user_version').first.columnAt(0) as int;
  if (version >= currentSchemaVersion) return;

  while (version < currentSchemaVersion) {
    final next = version + 1;
    final migration = _migrations[next];
    if (migration == null) {
      throw StateError('Missing migration to schema version $next');
    }
    migration(db);
    version = next;
    // Stamped per step rather than once at the end, so a failure part-way
    // through a multi-version upgrade doesn't re-run migrations that already
    // committed. PRAGMA doesn't accept parameter binding.
    db.execute('PRAGMA user_version = $version');
  }
}

Database openDatabase(String dataDir) {
  Directory(dataDir).createSync(recursive: true);
  final db = sqlite3.open(p.join(dataDir, 'db.sqlite'));
  db.execute('PRAGMA journal_mode=WAL;');
  db.execute('PRAGMA foreign_keys=ON;');
  // Without this, any lock contention fails the statement instantly rather
  // than waiting, surfacing as a 500 with "database is locked" -- observed once
  // on /auth/refresh under load. The server itself uses a single connection on
  // a single-threaded event loop, so it should not contend with itself; this
  // covers anything else touching the file (an operator running sqlite3, a
  // backup tool, WAL checkpointing) by degrading into a short wait.
  db.execute('PRAGMA busy_timeout=5000;');
  migrate(db);
  return db;
}
