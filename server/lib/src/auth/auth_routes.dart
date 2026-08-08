import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_service.dart';

Router buildAuthRouter(AuthService authService) {
  final router = Router();

  router.post('/login', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final email = body['email'] as String?;
    final password = body['password'] as String?;
    if (email == null || password == null) {
      return Response(400, body: jsonEncode({'error': 'email and password are required'}));
    }
    try {
      final session = authService.login(email, password);
      return Response.ok(jsonEncode({
        'sessionToken': session.token,
        'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      }), headers: {'content-type': 'application/json'});
    } on InvalidCredentialsException {
      return Response(401, body: jsonEncode({'error': 'invalid email or password'}));
    }
  });

  router.post('/refresh', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final sessionToken = body['sessionToken'] as String?;
    if (sessionToken == null) {
      return Response(400, body: jsonEncode({'error': 'sessionToken is required'}));
    }
    try {
      final session = authService.refresh(sessionToken);
      return Response.ok(jsonEncode({
        'sessionToken': session.token,
        'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      }), headers: {'content-type': 'application/json'});
    } on InvalidSessionException {
      return Response(401, body: jsonEncode({'error': 'invalid or expired session'}));
    }
  });

  router.post('/logout', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final sessionToken = body['sessionToken'] as String?;
    if (sessionToken == null) {
      return Response(400, body: jsonEncode({'error': 'sessionToken is required'}));
    }
    authService.logout(sessionToken);
    return Response.ok('');
  });

  return router;
}
