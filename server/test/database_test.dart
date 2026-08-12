import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Recreates the pre-versioning schema exactly as it shipped, so the upgrade
/// path can be tested against what is actually on the operator's server rather
/// than against a fresh file.
Database _openLegacyV1Database() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys=ON;');
  db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE sessions (
      token_hash TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    );
  ''');
  // Deployed before versioning existed, so it reports version 0 despite
  // already having the v1 tables.
  expect(db.select('PRAGMA user_version').first.columnAt(0), 0);
  return db;
}

/// Recreates the v2 schema -- accounts with roles, and the Stage 2 change feed
/// still keyed by user -- as it shipped before datasets existed. This is what a
/// live instance looks like on the way into v3/v4.
Database _openLegacyV2Database() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys=ON;');
  db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      name TEXT NOT NULL DEFAULT '',
      is_admin INTEGER NOT NULL DEFAULT 0
    );
  ''');
  db.execute('''
    CREATE TABLE sessions (
      token_hash TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE sync_records (
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
  db.execute('CREATE INDEX idx_sync_records_feed ON sync_records(user_id, seq);');
  db.execute('''
    CREATE TABLE sync_state (
      user_id          INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      next_seq         INTEGER NOT NULL DEFAULT 1,
      min_retained_seq INTEGER NOT NULL DEFAULT 0
    );
  ''');
  db.execute('PRAGMA user_version = 2');
  return db;
}

void _insertUser(Database db, String email, {int createdAt = 1000}) {
  db.execute(
    'INSERT INTO users (email, password_hash, created_at, name, is_admin) '
    'VALUES (?, ?, ?, ?, 0)',
    [email, 'hash', createdAt, ''],
  );
}

Set<String> _columnsOf(Database db, String table) => db
    .select('PRAGMA table_info($table)')
    .map((row) => row['name'] as String)
    .toSet();

/// The table each foreign key on [table] points at.
Set<String> _foreignKeyTargetsOf(Database db, String table) => db
    .select('PRAGMA foreign_key_list($table)')
    .map((row) => row['table'] as String)
    .toSet();

void main() {
  group('migrate', () {
    test('creates the full schema on an empty database', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);

      migrate(db);

      expect(_columnsOf(db, 'users'),
          containsAll(['id', 'email', 'password_hash', 'created_at', 'name', 'is_admin']));
      expect(_columnsOf(db, 'sessions'),
          containsAll(['token_hash', 'user_id', 'created_at', 'expires_at']));
      expect(db.select('PRAGMA user_version').first.columnAt(0), currentSchemaVersion);
    });

    test('upgrades a deployed v1 database without touching existing rows', () {
      final db = _openLegacyV1Database();
      addTearDown(db.dispose);
      db.execute(
        'INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)',
        ['owner@example.com', 'hash-owner', 1000],
      );

      migrate(db);

      final user = db.select('SELECT * FROM users').single;
      expect(user['email'], 'owner@example.com');
      expect(user['password_hash'], 'hash-owner', reason: 'existing credentials must survive');
      expect(user['name'], '');
      expect(db.select('PRAGMA user_version').first.columnAt(0), currentSchemaVersion);
    });

    test('promotes the earliest existing user to admin so the instance stays administrable', () {
      final db = _openLegacyV1Database();
      addTearDown(db.dispose);
      for (final email in ['owner@example.com', 'spouse@example.com']) {
        db.execute(
          'INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)',
          [email, 'hash', 1000],
        );
      }

      migrate(db);

      final admins = db.select('SELECT email FROM users WHERE is_admin = 1');
      expect(admins.map((r) => r['email']), ['owner@example.com'],
          reason: 'exactly the first-created account is promoted, not everyone');
    });

    test('leaves no admin on a fresh install (the setup endpoint creates one)', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);

      migrate(db);

      expect(db.select('SELECT COUNT(*) AS c FROM users').first['c'], 0);
    });

    test('is idempotent across repeated runs', () {
      final db = _openLegacyV1Database();
      addTearDown(db.dispose);
      db.execute(
        'INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)',
        ['owner@example.com', 'hash', 1000],
      );

      migrate(db);
      migrate(db);
      migrate(db);

      expect(db.select('SELECT COUNT(*) AS c FROM users').first['c'], 1);
      expect(db.select('PRAGMA user_version').first.columnAt(0), currentSchemaVersion);
    });
  });

  group('datasets', () {
    test('a fresh database has datasets and a dataset-keyed feed', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);

      migrate(db);

      expect(_columnsOf(db, 'datasets'), containsAll(['id', 'name', 'created_at']));
      expect(_columnsOf(db, 'dataset_members'),
          containsAll(['user_id', 'dataset_id', 'joined_at']));
      expect(_columnsOf(db, 'sync_records'), contains('dataset_id'));
      expect(_columnsOf(db, 'sync_records'), isNot(contains('user_id')),
          reason: 'a missed reader must fail loudly, not read the wrong scope');
      expect(_columnsOf(db, 'sync_state'), contains('dataset_id'));
      expect(
        db
            .select("SELECT name FROM sqlite_master "
                "WHERE type = 'index' AND tbl_name = 'sync_records'")
            .map((r) => r['name']),
        contains('idx_sync_records_feed'),
        reason: 'the feed index must survive the rebuild under its own name',
      );
    });

    test('the feed points at datasets, not users', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);

      migrate(db);

      // The whole reason both tables are rebuilt rather than having the column
      // renamed in place: RENAME COLUMN keeps the old foreign key, and then
      // deleting one member of a shared household cascades away the entire
      // household's feed.
      expect(_foreignKeyTargetsOf(db, 'sync_records'), ['datasets']);
      expect(_foreignKeyTargetsOf(db, 'sync_state'), ['datasets']);
    });

    test('every existing user is seeded a dataset whose id is their user id', () {
      final db = _openLegacyV2Database();
      addTearDown(db.dispose);
      _insertUser(db, 'one@example.com');
      _insertUser(db, 'two@example.com');
      _insertUser(db, 'three@example.com');

      migrate(db);

      final memberships = db.select(
          'SELECT user_id, dataset_id FROM dataset_members ORDER BY user_id');
      expect(memberships.map((r) => [r['user_id'], r['dataset_id']]),
          [[1, 1], [2, 2], [3, 3]]);
      // This equality is load-bearing, not cosmetic: it is what makes
      // data/sync/<userId> already correct as data/<ns>/<datasetId>, so no
      // files move and no sync_records rows are rewritten.
    });

    test('feed rows survive the rebuild verbatim', () {
      final db = _openLegacyV2Database();
      addTearDown(db.dispose);
      _insertUser(db, 'one@example.com');
      _insertUser(db, 'two@example.com');
      db.execute(
        'INSERT INTO sync_records '
        '(user_id, table_name, pk, seq, deleted, modified_at, device_id, payload) '
        'VALUES (1, ?, ?, 7, 0, 1234, ?, ?), (2, ?, ?, 3, 1, 99, ?, NULL)',
        ['wallets', 'w1', 'phone-1', '{"name":"Cash"}', 'budgets', 'b1', 'phone-2'],
      );
      db.execute(
        'INSERT INTO sync_state (user_id, next_seq, min_retained_seq) '
        'VALUES (1, 8, 2), (2, 4, 0)',
      );

      migrate(db);

      final records = db.select(
          'SELECT * FROM sync_records ORDER BY dataset_id');
      expect(records.length, 2);
      expect(records.first['dataset_id'], 1);
      expect(records.first['seq'], 7);
      expect(records.first['payload'], '{"name":"Cash"}');
      expect(records.first['device_id'], 'phone-1');
      expect(records.last['dataset_id'], 2);
      expect(records.last['deleted'], 1);

      final state = db.select('SELECT * FROM sync_state ORDER BY dataset_id');
      expect(state.map((r) => [r['dataset_id'], r['next_seq'], r['min_retained_seq']]),
          [[1, 8, 2], [2, 4, 0]]);
    });

    test('a dataset created after the migration does not reuse a seeded id', () {
      final db = _openLegacyV2Database();
      addTearDown(db.dispose);
      _insertUser(db, 'one@example.com');
      _insertUser(db, 'two@example.com');
      _insertUser(db, 'three@example.com');

      migrate(db);
      db.execute("INSERT INTO datasets (name, created_at) VALUES ('', 0)");

      // sqlite raises sqlite_sequence to the largest rowid ever inserted,
      // including the explicitly supplied ones the seed uses, so allocation
      // continues above the seeded block instead of colliding with it.
      expect(db.lastInsertRowId, 4);
    });

    test('feed rows orphaned by a deleted user are dropped, not fatal', () {
      final db = _openLegacyV2Database();
      addTearDown(db.dispose);
      _insertUser(db, 'one@example.com');
      // Written while foreign keys happened to be off, then the user went.
      db.execute('PRAGMA foreign_keys=OFF');
      db.execute(
        'INSERT INTO sync_records '
        '(user_id, table_name, pk, seq, deleted, modified_at, device_id, payload) '
        'VALUES (1, ?, ?, 1, 0, 1, ?, NULL), (99, ?, ?, 1, 0, 1, ?, NULL)',
        ['wallets', 'w1', 'phone', 'wallets', 'ghost', 'gone'],
      );
      db.execute('PRAGMA foreign_keys=ON');

      migrate(db);

      expect(db.select('SELECT pk FROM sync_records').map((r) => r['pk']), ['w1'],
          reason: 'copying a row that belongs to nobody would leave the table '
              'failing foreign_key_check, and the server refusing to start');
    });

    test('leaves the caller\'s foreign_keys setting as it found it', () {
      final on = _openLegacyV2Database();
      addTearDown(on.dispose);
      _insertUser(on, 'one@example.com');
      migrate(on);
      // A regression here silently disables every cascade for the lifetime of
      // the process, not just during the migration.
      expect(on.select('PRAGMA foreign_keys').first.columnAt(0), 1);

      final off = sqlite3.openInMemory();
      addTearDown(off.dispose);
      migrate(off);
      expect(off.select('PRAGMA foreign_keys').first.columnAt(0), 0);
    });

    test('deleting a user drops their membership but never the feed', () {
      final db = _openLegacyV2Database();
      addTearDown(db.dispose);
      _insertUser(db, 'one@example.com');
      db.execute(
        'INSERT INTO sync_records '
        '(user_id, table_name, pk, seq, deleted, modified_at, device_id, payload) '
        'VALUES (1, ?, ?, 1, 0, 1, ?, NULL)',
        ['wallets', 'w1', 'phone'],
      );

      migrate(db);
      db.execute('DELETE FROM users WHERE id = 1');

      expect(db.select('SELECT COUNT(*) AS c FROM dataset_members').first['c'], 0);
      // The feed outliving its last member is the point: a household's data
      // must not vanish because one of its accounts was removed. Reaping an
      // emptied dataset is the delete handler's job, not a cascade's.
      expect(db.select('SELECT COUNT(*) AS c FROM sync_records').first['c'], 1);
    });

    test('is idempotent across repeated runs', () {
      final db = _openLegacyV2Database();
      addTearDown(db.dispose);
      _insertUser(db, 'one@example.com');

      migrate(db);
      migrate(db);
      migrate(db);

      expect(db.select('SELECT COUNT(*) AS c FROM datasets').first['c'], 1);
      expect(db.select('SELECT COUNT(*) AS c FROM dataset_members').first['c'], 1);
      expect(db.select('PRAGMA user_version').first.columnAt(0), currentSchemaVersion);
    });
  });
}
