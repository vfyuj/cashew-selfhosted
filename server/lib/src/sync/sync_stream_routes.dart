import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/auth_service.dart';
import 'sync_hub.dart';

/// The live-sync wake-up socket (specs/04-stage-2-instant-sync.md). Mounted
/// at a top-level path (`/sync-stream`), separate from the `Authorization`
/// header-authenticated `/sync` router: a browser WebSocket handshake can't
/// carry custom headers, so this endpoint is unauthenticated at the HTTP
/// layer and instead requires an `{"type":"auth","token":...}` first message
/// -- never a URL query param, so a token can't land in reverse-proxy logs.
///
/// Returned as a raw [Handler], registered directly with `router.get(...)`
/// in bin/server.dart rather than via `Router.mount()`. A single-segment
/// mount prefix with no sub-path (`mount('/sync-stream', ...)` matched by a
/// sub-router's `get('/', ...)`) does not reliably match the mount root
/// itself in shelf_router 1.1.4 -- it silently fell through to the web
/// handler's SPA catch-all instead of ever reaching this handler. Registering
/// the exact literal path directly sidesteps that path-rewriting subtlety
/// entirely.
Handler buildSyncStreamHandler(AuthService authService) {
  return webSocketHandler((WebSocketChannel channel, String? protocol) {
    AuthUser? user;

    channel.stream.listen(
      (message) {
        if (user != null) return; // only the auth handshake is handled; live pushes are one-way.
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] != 'auth') throw const FormatException('expected auth first');
          user = authService.authenticate(data['token'] as String);
          // Registered by dataset, matching syncHub.notify's key in the push
          // handler. Keying this by user id instead would still compile and
          // still work for a solo account -- it would just silently stop
          // waking the other members of a household, leaving them on the
          // 45s/5min poll and looking like "sync is slow" rather than broken.
          syncHub.add(user!.datasetId, channel);
          channel.sink.add(jsonEncode({'type': 'ready'}));
        } catch (_) {
          channel.sink.close(4001, 'auth failed');
        }
      },
      onDone: () {
        if (user != null) syncHub.remove(user!.datasetId, channel);
      },
      cancelOnError: true,
    );
  }, pingInterval: const Duration(seconds: 30));
}
