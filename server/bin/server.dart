import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:server/src/api.dart';
import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/database.dart';
import 'package:server/src/web_handler.dart';

Future<void> main(List<String> args) async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final dataDir = Platform.environment['DATA_DIR'] ?? './data';
  // Unset in local API-only dev; set (by the Dockerfile) to the compiled
  // Flutter web build so one server serves both the UI and the API from
  // the same origin -- no separate web container, no CORS needed.
  final webDir = Platform.environment['WEB_DIR'];

  final db = openDatabase(dataDir);
  final authService = AuthService(db);

  final apiHandler = buildApiRouter(authService, db, dataDir,
          appVersion: webDir == null ? null : readWebBuildVersion(webDir))
      .call;
  final rootHandler = webDir == null
      ? apiHandler
      : Cascade().add(apiHandler).add(buildWebHandler(webDir)).handler;

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(rootHandler);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Server listening on port ${server.port}');
  if (authService.countUsers() == 0) {
    print('This instance has no accounts yet -- open it in a browser to create');
    print('the administrator account.');
  }
}
