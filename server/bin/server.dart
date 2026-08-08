import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:sqlite3/sqlite3.dart';

import 'package:server/src/auth/auth_middleware.dart';
import 'package:server/src/auth/auth_routes.dart';
import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/backup/backup_routes.dart';
import 'package:server/src/database.dart';
import 'package:server/src/sync/sync_routes.dart';
import 'package:server/src/sync/sync_stream_routes.dart';
import 'package:server/src/web_handler.dart';

Router _buildApiRouter(AuthService authService, Database db, String dataDir) {
  final router = Router();

  router.get('/health', (Request request) {
    return Response.ok('{"status":"ok"}', headers: {'content-type': 'application/json'});
  });

  router.mount('/auth', buildAuthRouter(authService).call);

  final authMiddleware = requireAuth(authService);
  router.mount(
    '/sync',
    const Pipeline().addMiddleware(authMiddleware).addHandler(buildSyncRouter(dataDir, db).call),
  );
  router.mount(
    '/backup',
    const Pipeline().addMiddleware(authMiddleware).addHandler(buildBackupRouter(dataDir).call),
  );
  // Not behind authMiddleware -- a WebSocket handshake can't carry a Bearer
  // header, so this authenticates itself via its first message instead.
  // Registered directly (not via .mount()) -- see the comment on
  // buildSyncStreamHandler for why a mount doesn't reliably match here.
  // See specs/04-stage-2-instant-sync.md.
  router.get('/sync-stream', buildSyncStreamHandler(authService));

  return router;
}

Future<void> main(List<String> args) async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final dataDir = Platform.environment['DATA_DIR'] ?? './data';
  // Unset in local API-only dev; set (by the Dockerfile) to the compiled
  // Flutter web build so one server serves both the UI and the API from
  // the same origin -- no separate web container, no CORS needed.
  final webDir = Platform.environment['WEB_DIR'];

  final db = openDatabase(dataDir);
  final authService = AuthService(db);

  final apiHandler = _buildApiRouter(authService, db, dataDir).call;
  final rootHandler = webDir == null
      ? apiHandler
      : Cascade().add(apiHandler).add(buildWebHandler(webDir)).handler;

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(rootHandler);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Server listening on port ${server.port}');
}
