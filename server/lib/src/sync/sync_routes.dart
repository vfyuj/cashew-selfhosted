import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../storage.dart';

/// Snapshot-diff sync transport (Stage 1): mirrors the shape of the old
/// `driveApi.files.list/.get/.create/.delete` calls against appDataFolder,
/// so the existing SyncLog/processSyncLogs/DeleteLog merge logic on the
/// client needs no changes -- only the transport. See specs/03-stage-1-kill-google.md.
Router buildSyncRouter(String dataDir) {
  final router = Router();

  UserFileStore storeFor(Request request) => UserFileStore(dataDir, 'sync', currentUser(request).id);

  router.get('/files', (Request request) {
    final files = storeFor(request).list();
    final json = files
        .map((f) => {
              'deviceId': p.basenameWithoutExtension(f.filename),
              ...f.toJson(),
            })
        .toList();
    return Response.ok(jsonEncode(json), headers: {'content-type': 'application/json'});
  });

  router.put('/files/<filename>', (Request request, String filename) async {
    final bytes = await request.read().expand((chunk) => chunk).toList();
    try {
      storeFor(request).write(filename, bytes);
      return Response.ok('');
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  router.get('/files/<filename>', (Request request, String filename) {
    try {
      final bytes = storeFor(request).read(filename);
      if (bytes == null) return Response.notFound('not found');
      return Response.ok(bytes, headers: {'content-type': 'application/octet-stream'});
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  router.delete('/files/<filename>', (Request request, String filename) {
    try {
      storeFor(request).delete(filename);
      return Response.ok('');
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  return router;
}
