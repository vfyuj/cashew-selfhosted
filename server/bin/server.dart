import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:server/src/auth/auth_middleware.dart';
import 'package:server/src/auth/auth_routes.dart';
import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/backup/backup_routes.dart';
import 'package:server/src/database.dart';
import 'package:server/src/sync/sync_routes.dart';

Router _buildRouter(AuthService authService, String dataDir) {
  final router = Router();

  router.get('/health', (Request request) {
    return Response.ok('{"status":"ok"}', headers: {'content-type': 'application/json'});
  });

  router.mount('/auth', buildAuthRouter(authService).call);

  final authMiddleware = requireAuth(authService);
  router.mount(
    '/sync',
    const Pipeline().addMiddleware(authMiddleware).addHandler(buildSyncRouter(dataDir).call),
  );
  router.mount(
    '/backup',
    const Pipeline().addMiddleware(authMiddleware).addHandler(buildBackupRouter(dataDir).call),
  );

  return router;
}

Future<void> main(List<String> args) async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final dataDir = Platform.environment['DATA_DIR'] ?? './data';

  final db = openDatabase(dataDir);
  final authService = AuthService(db);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_buildRouter(authService, dataDir).call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Server listening on port ${server.port}');
}
