import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

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
  return db;
}
