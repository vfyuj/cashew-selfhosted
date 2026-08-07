import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// Sessions use opaque random tokens, not JWTs -- simpler to revoke/audit
/// at household scale, no signing-key management. See specs/03-stage-1-kill-google.md.
const sessionDuration = Duration(days: 30);

class AuthUser {
  final int id;
  final String email;
  AuthUser(this.id, this.email);
}

class Session {
  final String token;
  final DateTime expiresAt;
  Session(this.token, this.expiresAt);
}

class InvalidCredentialsException implements Exception {}

class InvalidSessionException implements Exception {}

class AuthService {
  final Database db;
  AuthService(this.db);

  String hashPassword(String password) => BCrypt.hashpw(password, BCrypt.gensalt());

  bool _verifyPassword(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (_) {
      return false;
    }
  }

  String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

  /// Creates a user record. Returns the new user's id.
  int createUser(String email, String password) {
    final passwordHash = hashPassword(password);
    db.execute(
      'INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)',
      [email, passwordHash, DateTime.now().millisecondsSinceEpoch],
    );
    return db.lastInsertRowId;
  }

  Session _issueSession(int userId) {
    final token = _generateToken();
    final now = DateTime.now();
    final expiresAt = now.add(sessionDuration);
    db.execute(
      'INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
      [_hashToken(token), userId, now.millisecondsSinceEpoch, expiresAt.millisecondsSinceEpoch],
    );
    return Session(token, expiresAt);
  }

  /// Verifies email/password and issues a new session.
  Session login(String email, String password) {
    final rows = db.select('SELECT id, password_hash FROM users WHERE email = ?', [email]);
    if (rows.isEmpty) throw InvalidCredentialsException();
    final userId = rows.first['id'] as int;
    final passwordHash = rows.first['password_hash'] as String;
    if (!_verifyPassword(password, passwordHash)) throw InvalidCredentialsException();
    return _issueSession(userId);
  }

  /// Validates a session token and returns the associated user, or throws.
  AuthUser authenticate(String token) {
    final tokenHash = _hashToken(token);
    final rows = db.select(
      'SELECT sessions.user_id AS user_id, sessions.expires_at AS expires_at, users.email AS email '
      'FROM sessions JOIN users ON users.id = sessions.user_id '
      'WHERE sessions.token_hash = ?',
      [tokenHash],
    );
    if (rows.isEmpty) throw InvalidSessionException();
    final expiresAt = rows.first['expires_at'] as int;
    if (DateTime.fromMillisecondsSinceEpoch(expiresAt).isBefore(DateTime.now())) {
      db.execute('DELETE FROM sessions WHERE token_hash = ?', [tokenHash]);
      throw InvalidSessionException();
    }
    return AuthUser(rows.first['user_id'] as int, rows.first['email'] as String);
  }

  /// Rotates a valid session token for a fresh one with extended (sliding) expiry.
  Session refresh(String token) {
    final user = authenticate(token);
    db.execute('DELETE FROM sessions WHERE token_hash = ?', [_hashToken(token)]);
    return _issueSession(user.id);
  }

  void logout(String token) {
    db.execute('DELETE FROM sessions WHERE token_hash = ?', [_hashToken(token)]);
  }
}
