import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'auth_service.dart';

const authenticatedUserContextKey = 'authenticatedUser';

/// Extracts a session token from either `Authorization: Bearer <token>` or
/// `Cookie: session_token=<token>`. Browser navigations carry cookies but not
/// custom headers, so both paths must work for direct attachment link access.
String? _extractToken(Request request) {
  // Prefer explicit Bearer header (mobile app, API clients).
  final header = request.headers['authorization'];
  if (header != null && header.startsWith('Bearer ')) {
    return header.substring('Bearer '.length).trim();
  }
  // Fall back to session cookie (browser navigation).
  final cookieHeader = request.headers['cookie'];
  if (cookieHeader != null) {
    final cookies = _parseCookies(cookieHeader);
    final sessionToken = cookies['session_token'];
    if (sessionToken != null && sessionToken.isNotEmpty) {
      return sessionToken;
    }
  }
  return null;
}

/// Returns [response] with a session cookie attached when the request was
/// authenticated by a Bearer header but did not already carry a matching
/// `session_token` cookie. Sessions restored from client storage (signed in
/// before cookies existed, or after a cookie expired) would otherwise never
/// have a cookie, and a browser navigating straight to an attachment link
/// would be bounced to the home page.
Response _withSessionCookie(Request request, Response response, String token) {
  final cookieHeader = request.headers['cookie'];
  final existing = cookieHeader == null ? null : _parseCookies(cookieHeader)['session_token'];
  if (existing == token) return response;
  return response.change(headers: {
    'set-cookie': 'session_token=$token; Path=/; SameSite=Lax; HttpOnly',
  });
}

/// Parses a `Cookie` header value into a map of name -> value.
Map<String, String> _parseCookies(String cookieHeader) {
  final map = <String, String>{};
  for (final pair in cookieHeader.split(';')) {
    final parts = pair.split('=');
    if (parts.length >= 2) {
      final key = parts[0].trim();
      final value = parts.sublist(1).join('=').trim();
      map[key] = value;
    }
  }
  return map;
}

/// Resolves the session token from `Authorization: Bearer <token>` or
/// `Cookie: session_token=<token>` and attaches the authenticated user to
/// the request context. Every downstream handler reads the user id from there
/// -- never from a client-supplied field in the URL or body.
Middleware requireAuth(AuthService authService) {
  return (Handler innerHandler) {
    return (Request request) async {
      final token = _extractToken(request);
      if (token == null || token.isEmpty) {
        return Response(401, body: 'Missing or invalid Authorization header');
      }
      try {
        final user = authService.authenticate(token);
        final updatedRequest = request.change(context: {authenticatedUserContextKey: user});
        final response = await innerHandler(updatedRequest);
        return _withSessionCookie(request, response, token);
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

/// Like [requireAuth], but redirects unauthenticated requests to `/` (the web
/// login page) with HTTP 302 instead of returning 401. Used for attachment
/// routes so a browser that follows a direct link is guided to sign in rather
/// than seeing a raw 401 error.
Middleware requireAuthWithRedirect(AuthService authService) {
  return (Handler innerHandler) {
    return (Request request) async {
      // Only a browser navigation (GET/HEAD) can usefully follow a redirect to
      // the login page. An API call such as the attachment upload (PUT) must
      // get a real 401: a followed redirect lands on index.html with a 200,
      // which the client would otherwise read as a successful upload.
      Response unauthenticated() => request.method == 'GET' || request.method == 'HEAD'
          ? Response(302, headers: {'location': '/'})
          : Response(401, body: 'Session expired or invalid');
      final token = _extractToken(request);
      if (token == null || token.isEmpty) {
        return unauthenticated();
      }
      try {
        final user = authService.authenticate(token);
        final updatedRequest = request.change(context: {authenticatedUserContextKey: user});
        final response = await innerHandler(updatedRequest);
        return _withSessionCookie(request, response, token);
      } on InvalidSessionException {
        return unauthenticated();
      }
    };
  };
}
