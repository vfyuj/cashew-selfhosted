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

  // Scoped by USER, not by dataset -- deliberately, and not an oversight left
  // over from before datasets existed. Sync and attachments are dataset-scoped
  // because the household shares that data; backups are one device's manual
  // snapshots of it, and sharing the directory breaks two things:
  //
  //  - Filenames collide. createBackup names a file db-v<schema>-<deviceName>,
  //    and getCurrentDeviceName() strips clientID's millisecond suffix down to
  //    the device model. Two same-model phones in one household would silently
  //    overwrite each other's backups. (Sync snapshots keep the suffix, which
  //    is why sync/ can be shared safely.)
  //  - Retention crosses over. deleteRecentBackups prunes to backupLimit over
  //    the whole listing, so one member's automatic backup would evict
  //    another's.
  //
  // Each member keeping their own history costs nothing: they are snapshots of
  // the same shared database, so either member's restores the household.
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
