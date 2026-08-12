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

  /// Which set of synced data this request is scoped to.
  ///
  /// Distinct from [isAdmin] on purpose. `isAdmin` says who may provision
  /// accounts and reset passwords; this says whose transactions and budgets
  /// you see. Two accounts sharing a household have the same [datasetId] and
  /// may differ on [isAdmin], and vice versa -- collapsing the two would mean
  /// granting somebody administration silently merged their finances into the
  /// household's.
  final int datasetId;

  /// How many accounts share [datasetId], including this one.
  ///
  /// Sent to the client so it can tell a solo account from a shared one
  /// without a second round trip -- restore and reset-sync both need to warn
  /// differently when the action reaches somebody else's devices.
  final int householdSize;

  AuthUser(
    this.id,
    this.email, {
    this.name = '',
    this.isAdmin = false,
    required this.datasetId,
    required this.householdSize,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'isAdmin': isAdmin,
        'datasetId': datasetId,
        'householdSize': householdSize,
      };
}

/// A user as seen by an administrator listing the instance's accounts.
class UserRecord {
  final int id;
  final String email;
  final String name;
  final bool isAdmin;
  final DateTime createdAt;

  /// Lets the admin UI show which accounts share the caller's household:
  /// the ones whose datasetId matches their own.
  final int datasetId;

  UserRecord(this.id, this.email, this.name, this.isAdmin, this.createdAt,
      this.datasetId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'isAdmin': isAdmin,
        'createdAt': createdAt.toIso8601String(),
        'datasetId': datasetId,
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
/// exhaustion -- worse on a small server, and worse still under the 512 MB
/// container cap in docker-compose.yml. Queued callers cost a closure each, not an isolate.
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

/// Four at a time: enough to keep a multi-core server busy without letting a
/// burst of sign-ins turn into a pile of live isolates.
final _passwordHashingGate = _ConcurrencyGate(4);

class AuthService {
  final Database db;
  AuthService(this.db);

  /// bcrypt, on a worker isolate.
  ///
  /// The cost is the point of bcrypt -- a few hundred milliseconds on a
  /// modest server -- but this server is one Dart process on one event loop,
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

  /// The columns every query feeding [_userFromRow] must select.
  ///
  /// The join is a LEFT join and the membership is resolved per request rather
  /// than cached on the session: a user with no membership row would drop out
  /// of an inner join entirely, which surfaces as a 401 and an account that can
  /// never sign in again. [_userFromRow] heals that case instead.
  static const _datasetColumns =
      'dm.dataset_id AS dataset_id, '
      '(SELECT COUNT(*) FROM dataset_members WHERE dataset_id = dm.dataset_id) '
      'AS household_size';

  AuthUser _userFromRow(Row row) {
    final id = row['id'] as int;
    final datasetId = row['dataset_id'] as int?;
    return AuthUser(
      id,
      row['email'] as String,
      name: (row['name'] as String?) ?? '',
      isAdmin: (row['is_admin'] as int? ?? 0) == 1,
      // Self-heals rather than throwing. This should be unreachable -- every
      // path that creates a user also creates their membership -- but the cost
      // of being wrong is a permanently locked-out account, and the repair is
      // one insert.
      datasetId: datasetId ?? createDatasetFor(id),
      householdSize: datasetId == null ? 1 : (row['household_size'] as int? ?? 1),
    );
  }

  /// Creates a dataset with [userId] as its only member. Returns its id.
  int createDatasetFor(int userId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO datasets (name, created_at) VALUES (?, ?)',
      ['', now],
    );
    final datasetId = db.lastInsertRowId;
    joinDataset(userId, datasetId);
    return datasetId;
  }

  /// Moves [userId] into [datasetId]. `INSERT OR REPLACE` because
  /// dataset_members is keyed by user_id alone -- one membership per user.
  void joinDataset(int userId, int datasetId) {
    db.execute(
      'INSERT OR REPLACE INTO dataset_members (user_id, dataset_id, joined_at) '
      'VALUES (?, ?, ?)',
      [userId, datasetId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  int countDatasetMembers(int datasetId) => db.select(
        'SELECT COUNT(*) AS c FROM dataset_members WHERE dataset_id = ?',
        [datasetId],
      ).first['c'] as int;

  /// Drops a dataset once its last member is gone, which is what cascades its
  /// sync_records and sync_state away -- those no longer hang off `users`.
  void deleteDataset(int datasetId) {
    db.execute('DELETE FROM datasets WHERE id = ?', [datasetId]);
  }

  /// Creates a user record. Returns the new user's id.
  ///
  /// With [joinDatasetId] the account shares that dataset -- the whole point of
  /// a household. Without it the account gets a fresh, empty dataset of its
  /// own, which is the isolated behaviour every account had before datasets
  /// existed and is the right default.
  Future<int> createUser(
    String email,
    String password, {
    String name = '',
    bool isAdmin = false,
    int? joinDatasetId,
  }) async {
    _requireStrongEnough(password);
    // Hashed before any database work starts, so the transaction below stays a
    // single synchronous run -- see the note on [hashPassword].
    final passwordHash = await hashPassword(password);
    late int userId;
    // The user and their membership go in together. A user with no membership
    // is the one state [_userFromRow] has to paper over, so don't manufacture
    // it by letting the second insert fail on its own.
    db.execute('BEGIN IMMEDIATE');
    try {
      userId = _insertUser(email, passwordHash, name: name, isAdmin: isAdmin);
      if (joinDatasetId == null) {
        createDatasetFor(userId);
      } else {
        joinDataset(userId, joinDatasetId);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return userId;
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
      'SELECT u.id AS id, u.email AS email, u.name AS name, '
      'u.is_admin AS is_admin, $_datasetColumns '
      'FROM users u LEFT JOIN dataset_members dm ON dm.user_id = u.id '
      'WHERE u.id = ?',
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
      'SELECT u.id AS id, u.email AS email, u.name AS name, '
      'u.is_admin AS is_admin, u.password_hash AS password_hash, '
      '$_datasetColumns '
      'FROM users u LEFT JOIN dataset_members dm ON dm.user_id = u.id '
      'WHERE u.email = ?',
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
      createDatasetFor(userId);
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
      'users.email AS email, users.name AS name, users.is_admin AS is_admin, '
      '$_datasetColumns '
      'FROM sessions JOIN users ON users.id = sessions.user_id '
      'LEFT JOIN dataset_members dm ON dm.user_id = sessions.user_id '
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
        .select('SELECT u.id AS id, u.email AS email, u.name AS name, '
            'u.is_admin AS is_admin, u.created_at AS created_at, '
            'dm.dataset_id AS dataset_id '
            'FROM users u LEFT JOIN dataset_members dm ON dm.user_id = u.id '
            'ORDER BY u.id')
        .map((row) => UserRecord(
              row['id'] as int,
              row['email'] as String,
              (row['name'] as String?) ?? '',
              (row['is_admin'] as int? ?? 0) == 1,
              DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
              // 0 rather than a heal: this is a read-only listing and a write
              // from here would be a surprise. A membership-less account shows
              // as sharing nothing, and signing in repairs it.
              (row['dataset_id'] as int?) ?? 0,
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

  /// Deletes a user and, by foreign-key cascade, their sessions and their
  /// dataset membership. Refuses to remove the last administrator.
  ///
  /// Note what does **not** go with them: the dataset itself, and therefore its
  /// sync_records and sync_state. That is deliberate -- the dataset may still
  /// have other members, and dropping it here would delete a household's data
  /// because one of its accounts was removed. Reaping an emptied dataset, and
  /// removing stored files, are the caller's responsibility; the service layer
  /// doesn't know about disk. See the delete handler in admin_routes.dart.
  void deleteUser(int userId) {
    final user = requireUserById(userId);
    if (user.isAdmin && countAdmins() <= 1) throw LastAdminException();
    db.execute('DELETE FROM users WHERE id = ?', [userId]);
  }
}
