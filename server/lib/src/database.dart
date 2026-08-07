import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

Database openDatabase(String dataDir) {
  Directory(dataDir).createSync(recursive: true);
  final db = sqlite3.open(p.join(dataDir, 'db.sqlite'));
  db.execute('PRAGMA journal_mode=WAL;');
  db.execute('PRAGMA foreign_keys=ON;');
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
  return db;
}
