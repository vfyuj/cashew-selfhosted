import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../storage.dart';

/// Own-server backup storage: same shape as sync storage, separate
/// namespace. Nextcloud/WebDAV backup is configured and spoken entirely
/// client-side -- this server never proxies or knows about that path.
/// See specs/03-stage-1-kill-google.md.
Router buildBackupRouter(String dataDir) {
  final router = Router();

  UserFileStore storeFor(Request request) => UserFileStore(dataDir, 'backup', currentUser(request).id);

  router.get('/list', (Request request) {
    final files = storeFor(request).list();
    return Response.ok(
      jsonEncode(files.map((f) => f.toJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  });

  router.put('/<filename>', (Request request, String filename) async {
    final bytes = await request.read().expand((chunk) => chunk).toList();
    try {
      storeFor(request).write(filename, bytes);
      return Response.ok('');
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  router.get('/<filename>', (Request request, String filename) {
    try {
      final bytes = storeFor(request).read(filename);
      if (bytes == null) return Response.notFound('not found');
      return Response.ok(bytes, headers: {'content-type': 'application/octet-stream'});
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  router.delete('/<filename>', (Request request, String filename) {
    try {
      storeFor(request).delete(filename);
      return Response.ok('');
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  return router;
}
