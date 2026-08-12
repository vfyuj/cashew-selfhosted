import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'auth_service.dart';

const authenticatedUserContextKey = 'authenticatedUser';

/// Resolves the `Authorization: Bearer <token>` header to a user and attaches
/// it to the request context. Every downstream handler reads the user id
/// from there -- never from a client-supplied field in the URL or body.
Middleware requireAuth(AuthService authService) {
  return (Handler innerHandler) {
    return (Request request) async {
      final header = request.headers['authorization'];
      if (header == null || !header.startsWith('Bearer ')) {
        return Response(401, body: 'Missing or invalid Authorization header');
      }
      final token = header.substring('Bearer '.length).trim();
      try {
        final user = authService.authenticate(token);
        final updatedRequest = request.change(context: {authenticatedUserContextKey: user});
        return await innerHandler(updatedRequest);
      } on InvalidSessionException {
        return Response(401, body: 'Session expired or invalid');
      }
    };
  };
}

/// Gates administrator-only routes. Must be composed *after* [requireAuth] --
/// it reads the user that middleware put in the request context, and the role
/// is re-read from the session on every request rather than trusted from the
/// client, so a demotion takes effect immediately.
Middleware requireAdmin() {
  return (Handler innerHandler) {
    return (Request request) async {
      final user = request.context[authenticatedUserContextKey] as AuthUser?;
      if (user == null) {
        // requireAuth was not applied ahead of this middleware. Fail closed
        // rather than letting an unauthenticated request through.
        return Response(401, body: 'Missing or invalid Authorization header');
      }
      if (!user.isAdmin) {
        return Response(
          403,
          body: jsonEncode({'error': 'administrator access required'}),
          headers: {'content-type': 'application/json'},
        );
      }
      return innerHandler(request);
    };
  };
}

AuthUser currentUser(Request request) {
  return request.context[authenticatedUserContextKey] as AuthUser;
}
