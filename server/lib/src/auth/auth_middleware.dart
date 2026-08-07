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
        return innerHandler(updatedRequest);
      } on InvalidSessionException {
        return Response(401, body: 'Session expired or invalid');
      }
    };
  };
}

AuthUser currentUser(Request request) {
  return request.context[authenticatedUserContextKey] as AuthUser;
}
