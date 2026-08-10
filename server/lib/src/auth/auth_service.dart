import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
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

/// Runs at most [_limit] tasks at once, queueing the rest.
///
/// Guards the bcrypt isolates. Moving hashing off the event loop fixed one
/// problem (a login freezing every other request) and would have opened
/// another if left unbounded: each concurrent hash is a whole isolate, so
/// enough simultaneous attempts would trade a stalled event loop for memory
/// exhaustion -- worse on a Pi, and worse still under the 512 MB container cap
/// in docker-compose.yml. Queued callers cost a closure each, not an isolate.
///
/// The rate limiter in rate_limiter.dart bounds the *arrival* rate; this
/// bounds what is in flight regardless of how they arrive.
class _ConcurrencyGate {
  final int _limit;
  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  _ConcurrencyGate(this._limit);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= _limit) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future; // a finishing task hands its slot over directly
    } else {
      _active++;
    }
    try {
      return await task();
    } finally {
      // Pass the slot straight to the next in line rather than releasing and
      // letting them re-take it; that keeps the active count exact and stops
      // a burst from slipping past the limit between the two steps.
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}

/// Four at a time: enough to keep a multi-core Pi busy without letting a burst
/// of sign-ins turn into a pile of live isolates.
final _passwordHashingGate = _ConcurrencyGate(4);

class AuthService {
  final Database db;
  AuthService(this.db);

  /// bcrypt, on a worker isolate.
  ///
  /// The cost is the point of bcrypt -- a few hundred milliseconds on a
  /// Raspberry Pi -- but this server is one Dart process on one event loop,
  /// and the whole sync fleet is queued behind whatever is running on it. Done
  /// inline, a single login froze every other request for the duration, and a
  /// handful of login attempts per second was enough to stall the instance
  /// outright. `Isolate.run` moves that off the loop; spawning the isolate
  /// costs a few milliseconds against bcrypt's few hundred.
  ///
  /// **Callers must not hold a SQLite transaction open across these awaits.**
  /// Everything else here relies on sqlite3's synchronous API plus the single
  /// event loop to be race-free (the same property `_nextSeq` in
  /// sync_routes.dart depends on); an `await` inside `BEGIN`/`COMMIT` would let
  /// unrelated handlers interleave into the open transaction. Hash first, then
  /// do the database work synchronously -- that is why [setupFirstUser] takes
  /// the hash as a parameter rather than calling this mid-transaction.
  Future<String> hashPassword(String password) => _passwordHashingGate
      .run(() => Isolate.run(() => BCrypt.hashpw(password, BCrypt.gensalt())));

  Future<bool> _verifyPassword(String password, String hash) async {
    try {
      return await _passwordHashingGate
          .run(() => Isolate.run(() => BCrypt.checkpw(password, hash)));
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
  Future<int> createUser(
    String email,
    String password, {
    String name = '',
    bool isAdmin = false,
  }) async {
    _requireStrongEnough(password);
    // Hashed before any database work starts, so the insert below stays a
    // single synchronous step -- see the note on [hashPassword].
    final passwordHash = await hashPassword(password);
    return _insertUser(email, passwordHash, name: name, isAdmin: isAdmin);
  }

  /// The synchronous half of [createUser], taking an already-computed hash.
  /// Split out so a caller that needs the insert inside a transaction can hash
  /// first and keep the transaction free of awaits.
  int _insertUser(
    String email,
    String passwordHash, {
    String name = '',
    bool isAdmin = false,
  }) {
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

  /// Drops sessions that expired without ever being presented again, and
  /// returns how many went.
  ///
  /// [authenticate] only ever clears the one token in front of it, so a
  /// session belonging to a device that was wiped, reinstalled or simply never
  /// opened again is never reached and stays in the table for good. Called at
  /// startup: cheap, and the table is otherwise append-mostly.
  int pruneExpiredSessions() {
    db.execute(
      'DELETE FROM sessions WHERE expires_at < ?',
      [DateTime.now().millisecondsSinceEpoch],
    );
    return db.updatedRows;
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
  Future<(Session, AuthUser)> login(String email, String password) async {
    final rows = db.select(
      'SELECT id, email, name, is_admin, password_hash FROM users WHERE email = ?',
      [email],
    );
    if (rows.isEmpty) throw InvalidCredentialsException();
    final passwordHash = rows.first['password_hash'] as String;
    if (!await _verifyPassword(password, passwordHash)) {
      throw InvalidCredentialsException();
    }
    final user = _userFromRow(rows.first);
    return (_issueSession(user.id), user);
  }

  /// Creates the instance's first account, which becomes its administrator.
  ///
  /// Open to anyone while the instance has no users and closed permanently
  /// afterwards -- the same bootstrap model Nextcloud and Immich use. The
  /// count check and the insert are one transaction so two simultaneous
  /// requests can't both believe they are first.
  Future<(Session, AuthUser)> setupFirstUser({
    required String email,
    required String name,
    required String password,
  }) async {
    _requireStrongEnough(password);
    // Hashed before BEGIN, deliberately. The count-then-insert below is only
    // atomic because it is one uninterrupted synchronous run on the event
    // loop; an `await` between them would reopen exactly the race this
    // transaction exists to close. See the note on [hashPassword].
    final passwordHash = await hashPassword(password);
    late int userId;
    db.execute('BEGIN IMMEDIATE');
    try {
      if (countUsers() > 0) throw SetupAlreadyCompletedException();
      userId = _insertUser(email, passwordHash, name: name, isAdmin: true);
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
  Future<Session> changePassword(
      int userId, String currentPassword, String newPassword) async {
    final rows = db.select('SELECT password_hash FROM users WHERE id = ?', [userId]);
    if (rows.isEmpty) throw UserNotFoundException();
    if (!await _verifyPassword(
        currentPassword, rows.first['password_hash'] as String)) {
      throw InvalidCredentialsException();
    }
    _requireStrongEnough(newPassword);
    final newHash = await hashPassword(newPassword);
    db.execute(
      'UPDATE users SET password_hash = ? WHERE id = ?',
      [newHash, userId],
    );
    revokeAllSessions(userId);
    return _issueSession(userId);
  }

  /// Sets a password without knowing the old one. For the admin reset endpoint
  /// and the operator's rescue CLI -- never reachable by the account's own
  /// holder, who must go through [changePassword].
  Future<void> setPassword(int userId, String newPassword) async {
    _requireStrongEnough(newPassword);
    requireUserById(userId);
    final newHash = await hashPassword(newPassword);
    db.execute(
      'UPDATE users SET password_hash = ? WHERE id = ?',
      [newHash, userId],
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
