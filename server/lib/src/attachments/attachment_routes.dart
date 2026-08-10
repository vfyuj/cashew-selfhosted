import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../storage.dart';

/// Transaction attachments (receipt photos and picked files), stored in the
/// user's own namespace on this server. Replaces the Google Drive upload the
/// fork inherited from upstream -- see specs/03-stage-1-kill-google.md.
///
/// Deliberately the same shape as the sync and backup routers so it reuses
/// [UserFileStore] unchanged: same per-user scoping, same filename validation.
/// A third namespace directory keeps attachments out of the way of the sync
/// snapshot diff (which lists every file in its namespace and would otherwise
/// treat a receipt photo as a peer device's database).
Router buildAttachmentRouter(String dataDir) {
  final router = Router();

  UserFileStore storeFor(Request request) =>
      UserFileStore(dataDir, 'attachments', currentUser(request).id);

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
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
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
