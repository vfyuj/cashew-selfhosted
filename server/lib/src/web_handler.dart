import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

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
