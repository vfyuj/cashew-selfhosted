import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

/// The version of the compiled Flutter web build in [webDir], read from the
/// `version.json` that `flutter build web` emits beside it.
///
/// Read from the deployed build rather than hardcoded in the server, so the
/// version `/health` reports is by construction the version the browser will
/// load -- the two cannot drift. Returns null if the file is missing or
/// malformed, which is the normal state for API-only local dev.
String? readWebBuildVersion(String webDir) {
  try {
    final file = File(p.join(webDir, 'version.json'));
    if (!file.existsSync()) return null;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map && decoded['version'] is String) {
      return decoded['version'] as String;
    }
  } catch (_) {
    // Not worth refusing to start over; /health just omits the version.
  }
  return null;
}

/// Serves the compiled Flutter web build from [webDir]. Falls back to
/// index.html for any path that isn't a real file, so a hard refresh on a
/// client-side route still loads the app instead of a 404.
Handler buildWebHandler(String webDir) {
  final staticHandler = createStaticHandler(webDir, defaultDocument: 'index.html');
  final indexFile = File(p.join(webDir, 'index.html'));

  return (Request request) async {
    final response = await staticHandler(request);
    if (response.statusCode == 404 && await indexFile.exists()) {
      return Response.ok(await indexFile.readAsString(),
          headers: {'content-type': 'text/html', 'cache-control': 'no-cache'});
    }

    final path = request.url.path;
    if (path.isEmpty || path == 'index.html' || path == 'flutter_service_worker.js') {
      return response.change(headers: {'cache-control': 'no-cache'});
    }
    return response;
  };
}
