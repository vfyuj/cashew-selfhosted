import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'auth_service.dart';
import 'rate_limiter.dart';

Response _json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

Response _error(int status, String message) => _json({'error': message}, status: status);

/// Reads a JSON object body, or null when it isn't one.
Future<Map<String, dynamic>?> _readJson(Request request) async {
  try {
    final decoded = jsonDecode(await request.readAsString());
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String? _trimmedString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Every timestamp leaving this server is serialized via `.toUtc()` first, so
/// the string carries a `Z` and the client's `.toLocal()` has a correctly
/// marked instant to convert. Dropping it makes the client read the timestamp
/// as local time and mis-order things by the timezone offset. Regression-tested
/// in test/api_test.dart -- do not "simplify" it away.
Response _sessionResponse(Session session, AuthUser user) => _json({
      'sessionToken': session.token,
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      'user': user.toJson(),
    });

/// Unauthenticated auth surface: login, session lifecycle, and first-run setup.
///
/// [passwordAttemptLimiter] guards the two endpoints that run bcrypt. Ten
/// attempts per five minutes is far above what a household typing a password
/// wrong needs, and far below what it takes to keep a modest server's CPU busy.
/// Injectable so tests can drive the limit without waiting out a real window.
Router buildAuthRouter(AuthService authService, {RateLimiter? passwordAttemptLimiter}) {
  final router = Router();
  final limiter = passwordAttemptLimiter ??
      RateLimiter(limit: 10, window: const Duration(minutes: 5));

  /// Tells a client whether this instance still needs its first account, so it
  /// can show "set up this server" instead of a sign-in form. Deliberately
  /// unauthenticated -- there is no one to authenticate as yet. It discloses
  /// only whether the instance has any users, matching Nextcloud and Immich.
  router.get('/setup-state', (Request request) {
    return _json({'needsSetup': authService.countUsers() == 0});
  });

  /// Creates the instance's first account, which becomes its administrator.
  /// Open to anyone until that account exists, then closed permanently.
  router.post('/setup', rateLimited(limiter, (Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final email = _trimmedString(body['email']);
    final name = _trimmedString(body['name']) ?? '';
    final password = body['password'];
    if (email == null || password is! String) {
      return _error(400, 'email and password are required');
    }
    try {
      final (session, user) = await authService.setupFirstUser(
        email: email,
        name: name,
        password: password,
      );
      return _sessionResponse(session, user);
    } on SetupAlreadyCompletedException {
      return _error(409, 'this server has already been set up');
    } on WeakPasswordException {
      return _error(400, 'password must be at least $minPasswordLength characters');
    } on EmailInUseException {
      return _error(409, 'that email is already registered');
    }
  }));

  router.post('/login', rateLimited(limiter, (Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final email = _trimmedString(body['email']);
    final password = body['password'];
    if (email == null || password is! String) {
      return _error(400, 'email and password are required');
    }
    try {
      final (session, user) = await authService.login(email, password);
      return _sessionResponse(session, user);
    } on InvalidCredentialsException {
      return _error(401, 'invalid email or password');
    }
  }));

  router.post('/refresh', (Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final sessionToken = body['sessionToken'] as String?;
    if (sessionToken == null) return _error(400, 'sessionToken is required');
    try {
      final session = authService.refresh(sessionToken);
      return _json({
        'sessionToken': session.token,
        'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      });
    } on InvalidSessionException {
      return _error(401, 'invalid or expired session');
    }
  });

  router.post('/logout', (Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final sessionToken = body['sessionToken'] as String?;
    if (sessionToken == null) return _error(400, 'sessionToken is required');
    authService.logout(sessionToken);
    return Response.ok('');
  });

  return router;
}

/// Authenticated "my own account" surface. Mounted behind [requireAuth], so
/// every handler acts on `currentUser(request)` and can never be pointed at
/// somebody else's account by a client-supplied id.
Router buildAccountRouter(AuthService authService) {
  final router = Router();

  router.get('/me', (Request request) {
    return _json(currentUser(request).toJson());
  });

  router.patch('/me', (Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final name = body.containsKey('name') ? (body['name'] as String?)?.trim() : null;
    final email = body.containsKey('email') ? _trimmedString(body['email']) : null;
    if (name == null && email == null) {
      return _error(400, 'nothing to update');
    }
    try {
      final updated = authService.updateProfile(
        currentUser(request).id,
        name: name,
        email: email,
      );
      return _json(updated.toJson());
    } on EmailInUseException {
      return _error(409, 'that email is already registered');
    } on UserNotFoundException {
      return _error(404, 'user not found');
    }
  });

  /// Changing a password signs every device out of the account and hands the
  /// caller a fresh token, so the device making the change stays signed in
  /// while any others are genuinely revoked.
  router.post('/me/password', (Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final currentPassword = body['currentPassword'];
    final newPassword = body['newPassword'];
    if (currentPassword is! String || newPassword is! String) {
      return _error(400, 'currentPassword and newPassword are required');
    }
    try {
      final session = await authService.changePassword(
        currentUser(request).id,
        currentPassword,
        newPassword,
      );
      return _json({
        'sessionToken': session.token,
        'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      });
    } on InvalidCredentialsException {
      // Deliberately not 401. The auth middleware already uses 401 to mean
      // "your session is gone", and a client that saw the same status for both
      // could not tell "you typed the wrong current password" from "you were
      // signed out" -- and would pointlessly retry after refreshing its token.
      return _error(422, 'current password is incorrect');
    } on WeakPasswordException {
      return _error(400, 'password must be at least $minPasswordLength characters');
    } on UserNotFoundException {
      return _error(404, 'user not found');
    }
  });

  return router;
}
