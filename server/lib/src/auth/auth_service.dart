import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// Sessions use opaque random tokens, not JWTs -- simpler to revoke/audit
/// at household scale, no signing-key management. See specs/03-stage-1-kill-google.md.
const sessionDuration = Duration(days: 30);

/// Enforced everywhere a password is set. Deliberately modest: this is a
/// household server with a known set of users, and a rule strict enough to push
/// people towards reused passwords would make things worse, not better.
const minPasswordLength = 8;

class AuthUser {
  final int id;
  final String email;
  final String name;
  final bool isAdmin;
  AuthUser(this.id, this.email, {this.name = '', this.isAdmin = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'isAdmin': isAdmin,
      };
}

/// A user as seen by an administrator listing the instance's accounts.
class UserRecord {
  final int id;
  final String email;
  final String name;
  final bool isAdmin;
  final DateTime createdAt;
  UserRecord(this.id, this.email, this.name, this.isAdmin, this.createdAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'isAdmin': isAdmin,
        'createdAt': createdAt.toIso8601String(),
      };
}

class Session {
  final String token;
  final DateTime expiresAt;
  Session(this.token, this.expiresAt);
}

class InvalidCredentialsException implements Exception {}

class InvalidSessionException implements Exception {}

class EmailInUseException implements Exception {}

class UserNotFoundException implements Exception {}

class WeakPasswordException implements Exception {}

/// Raised when an operation would leave the instance with no administrator --
/// which would make every admin-only endpoint permanently unreachable,
/// including the one that grants admin.
class LastAdminException implements Exception {}

/// Raised when the first-run setup endpoint is called on an instance that
/// already has users. Setup closes permanently after the first account.
class SetupAlreadyCompletedException implements Exception {}

/// SQLITE_CONSTRAINT. `SqliteException.resultCode` is the extended code masked
/// to its low byte, so the more specific SQLITE_CONSTRAINT_UNIQUE (2067)
/// arrives here as 19 -- checking for 2067 on `resultCode` would never match.
const _sqliteConstraint = 19;

bool _isUniqueViolation(SqliteException e) =>
    e.resultCode == _sqliteConstraint || e.extendedResultCode == 2067;

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

  void _requireStrongEnough(String password) {
    if (password.length < minPasswordLength) throw WeakPasswordException();
  }

  String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

  /// Human-transcribable temporary password: no characters that are ambiguous
  /// when read off a screen and typed on a phone (no O/0, I/l/1).
  String generateTemporaryPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
  }

  AuthUser _userFromRow(Row row) => AuthUser(
        row['id'] as int,
        row['email'] as String,
        name: (row['name'] as String?) ?? '',
        isAdmin: (row['is_admin'] as int? ?? 0) == 1,
      );

  /// Creates a user record. Returns the new user's id.
  int createUser(
    String email,
    String password, {
    String name = '',
    bool isAdmin = false,
  }) {
    _requireStrongEnough(password);
    final passwordHash = hashPassword(password);
    try {
      db.execute(
        'INSERT INTO users (email, password_hash, created_at, name, is_admin) VALUES (?, ?, ?, ?, ?)',
        [email, passwordHash, DateTime.now().millisecondsSinceEpoch, name, isAdmin ? 1 : 0],
      );
    } on SqliteException catch (e) {
      if (_isUniqueViolation(e)) throw EmailInUseException();
      rethrow;
    }
    return db.lastInsertRowId;
  }

  int countUsers() => db.select('SELECT COUNT(*) AS c FROM users').first['c'] as int;

  int countAdmins() =>
      db.select('SELECT COUNT(*) AS c FROM users WHERE is_admin = 1').first['c'] as int;

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

  /// Signs every device out of an account. Used after a password change or an
  /// admin-initiated reset -- a changed password that left old sessions alive
  /// would not actually revoke access.
  void revokeAllSessions(int userId) {
    db.execute('DELETE FROM sessions WHERE user_id = ?', [userId]);
  }

  AuthUser? findUserById(int userId) {
    final rows = db.select(
      'SELECT id, email, name, is_admin FROM users WHERE id = ?',
      [userId],
    );
    if (rows.isEmpty) return null;
    return _userFromRow(rows.first);
  }

  AuthUser requireUserById(int userId) {
    final user = findUserById(userId);
    if (user == null) throw UserNotFoundException();
    return user;
  }

  /// Verifies email/password and issues a new session.
  ///
  /// Returns the user alongside the session so callers can hand the client its
  /// profile without a second round trip.
  (Session, AuthUser) login(String email, String password) {
    final rows = db.select(
      'SELECT id, email, name, is_admin, password_hash FROM users WHERE email = ?',
      [email],
    );
    if (rows.isEmpty) throw InvalidCredentialsException();
    final passwordHash = rows.first['password_hash'] as String;
    if (!_verifyPassword(password, passwordHash)) throw InvalidCredentialsException();
    final user = _userFromRow(rows.first);
    return (_issueSession(user.id), user);
  }

  /// Creates the instance's first account, which becomes its administrator.
  ///
  /// Open to anyone while the instance has no users and closed permanently
  /// afterwards -- the same bootstrap model Nextcloud and Immich use. The
  /// count check and the insert are one transaction so two simultaneous
  /// requests can't both believe they are first.
  (Session, AuthUser) setupFirstUser({
    required String email,
    required String name,
    required String password,
  }) {
    _requireStrongEnough(password);
    late int userId;
    db.execute('BEGIN IMMEDIATE');
    try {
      if (countUsers() > 0) throw SetupAlreadyCompletedException();
      userId = createUser(email, password, name: name, isAdmin: true);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return (_issueSession(userId), requireUserById(userId));
  }

  /// Validates a session token and returns the associated user, or throws.
  AuthUser authenticate(String token) {
    final tokenHash = _hashToken(token);
    final rows = db.select(
      'SELECT sessions.user_id AS id, sessions.expires_at AS expires_at, '
      'users.email AS email, users.name AS name, users.is_admin AS is_admin '
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
    return _userFromRow(rows.first);
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

  /// Updates display name and/or email. Omitted fields are left alone.
  AuthUser updateProfile(int userId, {String? name, String? email}) {
    requireUserById(userId);
    if (name != null) {
      db.execute('UPDATE users SET name = ? WHERE id = ?', [name, userId]);
    }
    if (email != null) {
      try {
        db.execute('UPDATE users SET email = ? WHERE id = ?', [email, userId]);
      } on SqliteException catch (e) {
        if (_isUniqueViolation(e)) throw EmailInUseException();
        rethrow;
      }
    }
    return requireUserById(userId);
  }

  /// Verifies the current password, sets a new one, and signs every device out
  /// of the account -- then issues one fresh session so the caller's own device
  /// stays signed in.
  Session changePassword(int userId, String currentPassword, String newPassword) {
    final rows = db.select('SELECT password_hash FROM users WHERE id = ?', [userId]);
    if (rows.isEmpty) throw UserNotFoundException();
    if (!_verifyPassword(currentPassword, rows.first['password_hash'] as String)) {
      throw InvalidCredentialsException();
    }
    _requireStrongEnough(newPassword);
    db.execute(
      'UPDATE users SET password_hash = ? WHERE id = ?',
      [hashPassword(newPassword), userId],
    );
    revokeAllSessions(userId);
    return _issueSession(userId);
  }

  /// Sets a password without knowing the old one. For the admin reset endpoint
  /// and the operator's rescue CLI -- never reachable by the account's own
  /// holder, who must go through [changePassword].
  void setPassword(int userId, String newPassword) {
    _requireStrongEnough(newPassword);
    requireUserById(userId);
    db.execute(
      'UPDATE users SET password_hash = ? WHERE id = ?',
      [hashPassword(newPassword), userId],
    );
    revokeAllSessions(userId);
  }

  List<UserRecord> listUsers() {
    return db
        .select('SELECT id, email, name, is_admin, created_at FROM users ORDER BY id')
        .map((row) => UserRecord(
              row['id'] as int,
              row['email'] as String,
              (row['name'] as String?) ?? '',
              (row['is_admin'] as int? ?? 0) == 1,
              DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
            ))
        .toList();
  }

  /// Grants or revokes admin. Refuses to remove the last administrator.
  AuthUser setAdmin(int userId, bool isAdmin) {
    final user = requireUserById(userId);
    if (!isAdmin && user.isAdmin && countAdmins() <= 1) throw LastAdminException();
    db.execute('UPDATE users SET is_admin = ? WHERE id = ?', [isAdmin ? 1 : 0, userId]);
    return requireUserById(userId);
  }

  /// Deletes a user and, by foreign-key cascade, their sessions. Refuses to
  /// remove the last administrator. Their stored sync/backup files are the
  /// caller's responsibility -- the service layer doesn't know about disk.
  void deleteUser(int userId) {
    final user = requireUserById(userId);
    if (user.isAdmin && countAdmins() <= 1) throw LastAdminException();
    db.execute('DELETE FROM users WHERE id = ?', [userId]);
  }
}
