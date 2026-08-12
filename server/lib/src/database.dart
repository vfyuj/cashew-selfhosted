import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Bump this whenever a migration is appended to [_migrations].
const currentSchemaVersion = 4;

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
  3: _migrateToV3,
  4: _migrateToV4,
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

/// Introduces datasets: the unit that sync storage is scoped to, so that more
/// than one account can share one set of transactions, budgets and wallets.
///
/// Behaviour is unchanged by this step alone. Every existing user gets their
/// own dataset and nothing yet reads the new tables.
///
/// The seed deliberately gives each dataset **the same id as its only member's
/// user id**. That is what makes this migration free: `data/sync/<userId>` and
/// `data/attachments/<userId>` are already the right directories once they are
/// read as `data/<ns>/<datasetId>`, so no files move, and the values already
/// stored in `sync_records.user_id` are already valid dataset ids, so no rows
/// are rewritten. sqlite raises `sqlite_sequence` to the largest rowid ever
/// inserted including explicitly supplied ones, so datasets allocated later
/// start above the seeded block and can never collide with it.
void _migrateToV3(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS datasets (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT    NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL
    );
  ''');
  // user_id is the primary key, not part of a composite one: a user belongs to
  // exactly one dataset, so resolving a request's storage scope is never
  // ambiguous and never needs a tie-break.
  db.execute('''
    CREATE TABLE IF NOT EXISTS dataset_members (
      user_id    INTEGER PRIMARY KEY REFERENCES users(id)    ON DELETE CASCADE,
      dataset_id INTEGER NOT NULL    REFERENCES datasets(id) ON DELETE CASCADE,
      joined_at  INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_dataset_members_dataset
      ON dataset_members(dataset_id);
  ''');
  db.execute('''
    INSERT OR IGNORE INTO datasets (id, name, created_at)
      SELECT id, '', created_at FROM users;
  ''');
  db.execute('''
    INSERT OR IGNORE INTO dataset_members (user_id, dataset_id, joined_at)
      SELECT id, id, created_at FROM users;
  ''');
}

/// Re-keys the change feed from a user to a dataset.
///
/// The tables are rebuilt rather than having the column renamed in place.
/// `ALTER TABLE ... RENAME COLUMN` keeps the old foreign key, which would leave
/// `dataset_id` pointing at `users` -- and then deleting one member of a shared
/// household would cascade the whole household's feed away. Rebuilding also
/// means every reader that still says `user_id` fails loudly with "no such
/// column" instead of silently serving somebody else's rows.
///
/// v3's seed is what makes the copy a straight one: the existing `user_id`
/// values are already the correct dataset ids.
void _migrateToV4(Database db) {
  final columns = db
      .select('PRAGMA table_info(sync_records)')
      .map((row) => row['name'] as String)
      .toSet();
  if (columns.contains('dataset_id')) return;

  // PRAGMA foreign_keys is a no-op inside a transaction, so it has to be
  // toggled out here; migrate() runs each step unwrapped, which is what makes
  // that possible. The caller's original setting is restored rather than
  // forced on -- tests open connections without it.
  final foreignKeysWereOn =
      (db.select('PRAGMA foreign_keys').first.columnAt(0) as int) == 1;
  db.execute('PRAGMA foreign_keys=OFF');
  db.execute('BEGIN');
  try {
    db.execute('''
      CREATE TABLE sync_records_new (
        dataset_id  INTEGER NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
        table_name  TEXT    NOT NULL,
        pk          TEXT    NOT NULL,
        seq         INTEGER NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        modified_at INTEGER NOT NULL,
        device_id   TEXT    NOT NULL,
        payload     TEXT,
        PRIMARY KEY (dataset_id, table_name, pk)
      );
    ''');
    // Rows whose owner no longer exists are dropped rather than carried over.
    // They belong to nobody and no longer have a dataset to point at; copying
    // them would leave the table failing a foreign_key_check, which on a
    // strict connection means the server refuses to start.
    db.execute('''
      INSERT INTO sync_records_new
        SELECT user_id, table_name, pk, seq, deleted, modified_at, device_id, payload
        FROM sync_records WHERE user_id IN (SELECT id FROM datasets);
    ''');
    db.execute('DROP TABLE sync_records');
    db.execute('ALTER TABLE sync_records_new RENAME TO sync_records');
    // Recreated after the rename so it keeps its canonical name rather than
    // one derived from the temporary table.
    db.execute(
      'CREATE INDEX idx_sync_records_feed ON sync_records(dataset_id, seq)',
    );

    db.execute('''
      CREATE TABLE sync_state_new (
        dataset_id       INTEGER PRIMARY KEY REFERENCES datasets(id) ON DELETE CASCADE,
        next_seq         INTEGER NOT NULL DEFAULT 1,
        min_retained_seq INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('''
      INSERT INTO sync_state_new
        SELECT user_id, next_seq, min_retained_seq
        FROM sync_state WHERE user_id IN (SELECT id FROM datasets);
    ''');
    db.execute('DROP TABLE sync_state');
    db.execute('ALTER TABLE sync_state_new RENAME TO sync_state');
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  } finally {
    if (foreignKeysWereOn) db.execute('PRAGMA foreign_keys=ON');
  }
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
