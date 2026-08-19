import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:server/src/admin/admin_routes.dart';
import 'package:server/src/auth/auth_middleware.dart';
import 'package:server/src/auth/auth_routes.dart';
import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/attachments/attachment_routes.dart';
import 'package:server/src/backup/backup_routes.dart';
import 'package:server/src/rates/rate_admin_routes.dart';
import 'package:server/src/rates/rate_routes.dart';
import 'package:server/src/sync/sync_routes.dart';
import 'package:server/src/sync/sync_stream_routes.dart';

/// The complete API surface, independent of how it is served.
///
/// Kept in `lib/` rather than inline in `bin/server.dart` so tests can exercise
/// the real routing and middleware composition against an in-memory database,
/// without binding a port.
Router buildApiRouter(AuthService authService, Database db, String dataDir,
    {String? appVersion,
    Future<Map<String, double>?> Function()? fetchExchangeRates,
    Duration rateRefreshInterval = defaultRateRefreshInterval}) {
  final router = Router();

  // Reports the version of the web build being served alongside liveness, so
  // `curl .../health` confirms which build a deploy actually landed without
  // opening a browser -- see DEPLOYMENT.md and specs/07-versioning.md.
  // Unauthenticated and precomputed: this is a smoke test, on the hot path of
  // every uptime check.
  final healthBody = appVersion == null
      ? '{"status":"ok"}'
      : jsonEncode({'status': 'ok', 'version': appVersion});
  router.get('/health', (Request request) {
    return Response.ok(healthBody, headers: {'content-type': 'application/json'});
  });

  final authMiddleware = requireAuth(authService);

  // Two routers share the /auth prefix, and the order matters. The public one
  // is tried first (login, refresh, logout, and the first-run setup probe --
  // none of which can require a session). Anything it doesn't recognise falls
  // through to the authenticated "my own account" router, because a nested
  // Router returns Router.routeNotFound rather than a 404 when nothing matches.
  router.mount('/auth', buildAuthRouter(authService).call);
  router.mount(
    '/auth',
    const Pipeline()
        .addMiddleware(authMiddleware)
        .addHandler(buildAccountRouter(authService).call),
  );

  router.mount(
    '/sync',
    const Pipeline()
        .addMiddleware(authMiddleware)
        .addHandler(buildSyncRouter(dataDir, db).call),
  );
  router.mount(
    '/backup',
    const Pipeline().addMiddleware(authMiddleware).addHandler(buildBackupRouter(dataDir).call),
  );
  router.mount(
    '/attachments',
    const Pipeline()
        .addMiddleware(authMiddleware)
        .addHandler(buildAttachmentRouter(dataDir).call),
  );
  // Everyone reads the rate table, only an administrator edits it. The two are
  // mounted at *distinct* prefixes rather than layered on one: mount
  // middleware runs before the nested router decides whether the path is even
  // its own, so an admin-gated mount sharing the /rates prefix would answer a
  // household member's ordinary read with 403. The longer prefix is registered
  // first, because the first match wins. See docs/server/rates.md.
  router.mount(
    '/rates/overrides',
    const Pipeline()
        .addMiddleware(authMiddleware)
        .addMiddleware(requireAdmin())
        .addHandler(buildRatesAdminRouter(db).call),
  );
  router.mount(
    '/rates',
    const Pipeline().addMiddleware(authMiddleware).addHandler(buildRatesRouter(
          db,
          fetchRates: fetchExchangeRates,
          refreshInterval: rateRefreshInterval,
        ).call),
  );
  router.mount(
    '/admin',
    const Pipeline()
        .addMiddleware(authMiddleware)
        .addMiddleware(requireAdmin())
        .addHandler(buildAdminRouter(authService, dataDir).call),
  );
  // Not behind authMiddleware -- a WebSocket handshake can't carry a Bearer
  // header, so this authenticates itself via its first message instead.
  // Registered directly (not via .mount()) -- see the comment on
  // buildSyncStreamHandler for why a mount doesn't reliably match here.
  // Kept after the /sync mount, matching the order this shipped in.
  // See specs/04-stage-2-instant-sync.md.
  router.get('/sync-stream', buildSyncStreamHandler(authService));

  return router;
}
