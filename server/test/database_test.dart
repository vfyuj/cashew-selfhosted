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

Set<String> _columnsOf(Database db, String table) => db
    .select('PRAGMA table_info($table)')
    .map((row) => row['name'] as String)
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
}
