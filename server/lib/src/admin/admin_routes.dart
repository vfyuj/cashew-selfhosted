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
  ///
  /// `shareHousehold` puts the new account in the caller's dataset, so both see
  /// the same transactions, budgets and wallets. Without it the account gets an
  /// empty dataset of its own and is invisible to everyone else, which is what
  /// every account was before datasets existed and remains the default.
  ///
  /// Only settable here, at creation. Moving an account that already holds data
  /// into a household would merge two sets of rows that share no primary keys,
  /// duplicating every wallet, category and transaction -- so that is not
  /// offered rather than offered with a warning.
  router.post('/users', (Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error(400, 'expected a JSON object body');
    final email = _trimmedString(body['email']);
    final name = _trimmedString(body['name']) ?? '';
    if (email == null) return _error(400, 'email is required');

    final temporaryPassword = authService.generateTemporaryPassword();
    try {
      final id = await authService.createUser(
        email,
        temporaryPassword,
        name: name,
        isAdmin: body['isAdmin'] == true,
        joinDatasetId: body['shareHousehold'] == true
            ? currentUser(request).datasetId
            : null,
      );
      return _json({
        'user': authService.requireUserById(id).toJson(),
        'temporaryPassword': temporaryPassword,
      }, status: 201);
    } on EmailInUseException {
      return _error(409, 'that email is already registered');
    }
  });

  router.post('/users/<id>/password', (Request request, String id) async {
    final userId = int.tryParse(id);
    if (userId == null) return _error(400, 'invalid user id');
    final temporaryPassword = authService.generateTemporaryPassword();
    try {
      // Also signs that user's devices out -- a reset that left old sessions
      // alive would not actually take the account back.
      await authService.setPassword(userId, temporaryPassword);
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
    // Resolved before the delete: the membership row cascades away with the
    // user, so afterwards there is no way back to which dataset they were in.
    final int? datasetId = authService.findUserById(userId)?.datasetId;
    try {
      authService.deleteUser(userId);
    } on LastAdminException {
      return _error(409, 'cannot remove the last administrator');
    } on UserNotFoundException {
      return _error(404, 'user not found');
    }
    // Sessions and the dataset membership cascade via foreign keys; stored
    // files do not. Done after the delete succeeds so a refused deletion never
    // destroys data.
    //
    // Backups are per-user, so they always go with the account.
    UserFileStore(dataDir, 'backup', userId).deleteAll();
    // Sync and attachments belong to the dataset, which may still have other
    // members -- deleting one member of a household must not delete the
    // household's data. Only once the last member is gone is any of it
    // unreachable. Dropping the datasets row is also what cascades away
    // sync_records and sync_state, which no longer hang off users.
    if (datasetId != null && authService.countDatasetMembers(datasetId) == 0) {
      authService.deleteDataset(datasetId);
      UserFileStore(dataDir, 'sync', datasetId).deleteAll();
      UserFileStore(dataDir, 'attachments', datasetId).deleteAll();
    }
    return Response.ok('');
  });

  return router;
}
