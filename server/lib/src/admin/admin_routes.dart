import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:server/src/auth/auth_middleware.dart';
import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/storage.dart';

Response _json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

Response _error(int status, String message) => _json({'error': message}, status: status);

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

/// Instance administration: managing the household's accounts.
///
/// Mounted behind `requireAuth` + `requireAdmin`, so every handler here can
/// assume an authenticated administrator. This replaces the old CLI-only
/// provisioning; `bin/create_user.dart` remains as the operator's rescue path
/// for a forgotten administrator password.
Router buildAdminRouter(AuthService authService, String dataDir) {
  final router = Router();

  router.get('/users', (Request request) {
    return _json({
      'users': authService.listUsers().map((u) => u.toJson()).toList(),
    });
  });

  /// Creates an account and returns a generated temporary password. That
  /// password is shown exactly once and never stored in plaintext -- if it is
  /// lost, the administrator issues a new one via the reset route below.
  router.post('/users', (Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final email = _trimmedString(body['email']);
    final name = _trimmedString(body['name']) ?? '';
    if (email == null) return _error(400, 'email is required');

    final temporaryPassword = authService.generateTemporaryPassword();
    try {
      final id = authService.createUser(
        email,
        temporaryPassword,
        name: name,
        isAdmin: body['isAdmin'] == true,
      );
      return _json({
        'user': authService.requireUserById(id).toJson(),
        'temporaryPassword': temporaryPassword,
      }, status: 201);
    } on EmailInUseException {
      return _error(409, 'that email is already registered');
    }
  });

  router.post('/users/<id>/password', (Request request, String id) {
    final userId = int.tryParse(id);
    if (userId == null) return _error(400, 'invalid user id');
    final temporaryPassword = authService.generateTemporaryPassword();
    try {
      // Also signs that user's devices out -- a reset that left old sessions
      // alive would not actually take the account back.
      authService.setPassword(userId, temporaryPassword);
      return _json({'temporaryPassword': temporaryPassword});
    } on UserNotFoundException {
      return _error(404, 'user not found');
    }
  });

  router.patch('/users/<id>', (Request request, String id) async {
    final userId = int.tryParse(id);
    if (userId == null) return _error(400, 'invalid user id');
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final isAdmin = body['isAdmin'];
    if (isAdmin is! bool) return _error(400, 'isAdmin (boolean) is required');
    try {
      return _json(authService.setAdmin(userId, isAdmin).toJson());
    } on LastAdminException {
      return _error(409, 'cannot remove the last administrator');
    } on UserNotFoundException {
      return _error(404, 'user not found');
    }
  });

  router.delete('/users/<id>', (Request request, String id) {
    final userId = int.tryParse(id);
    if (userId == null) return _error(400, 'invalid user id');
    if (userId == currentUser(request).id) {
      // Deleting yourself would drop you out of the only session that can undo
      // it. Demote-then-delete from another admin account is the way.
      return _error(409, 'you cannot delete your own account');
    }
    try {
      authService.deleteUser(userId);
    } on LastAdminException {
      return _error(409, 'cannot remove the last administrator');
    } on UserNotFoundException {
      return _error(404, 'user not found');
    }
    // Sessions cascade via the foreign key; stored files do not, so clear both
    // namespaces explicitly. Done after the delete succeeds so a refused
    // deletion never destroys data.
    UserFileStore(dataDir, 'sync', userId).deleteAll();
    UserFileStore(dataDir, 'backup', userId).deleteAll();
    return Response.ok('');
  });

  return router;
}
