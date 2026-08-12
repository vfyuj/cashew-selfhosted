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

/// Content types for the file kinds the image pre-compresses (see the gzip
/// step in /Dockerfile). Hand-rolled rather than pulled in from a mime
/// package: this only has to cover what `flutter build web` actually emits,
/// and being explicit stops the gzip path from ever mislabelling a response.
///
/// A file kind absent from this map is simply served uncompressed, so adding
/// a new extension to the Dockerfile's find without adding it here degrades
/// to the old behaviour rather than breaking.
const _compressibleContentTypes = <String, String>{
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.css': 'text/css',
  '.html': 'text/html',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.svg': 'image/svg+xml',
  '.map': 'application/json',
  '.symbols': 'text/plain',
};

/// Same idea, for the build's one meaningful extensionless file. `NOTICES` is
/// ~1.9 MB of plain text -- worth compressing, and matched by name because
/// there is no extension to match on.
const _compressibleFileNames = <String, String>{
  'NOTICES': 'text/plain',
};

String? _compressibleContentTypeFor(String filePath) =>
    _compressibleContentTypes[p.extension(filePath)] ??
    _compressibleFileNames[p.basename(filePath)];

/// True when the client actually advertised gzip. Parsed properly rather than
/// with a `contains('gzip')`, so `gzip;q=0` (a client asking us *not* to gzip)
/// isn't read as consent.
bool _acceptsGzip(Request request) {
  final header = request.headers['accept-encoding'];
  if (header == null) return false;
  for (final part in header.split(',')) {
    final pieces = part.split(';');
    if (pieces.first.trim().toLowerCase() != 'gzip') continue;
    for (final param in pieces.skip(1)) {
      final trimmed = param.trim().toLowerCase();
      if (trimmed.startsWith('q=')) {
        final q = double.tryParse(trimmed.substring(2));
        if (q != null && q == 0) return false;
      }
    }
    return true;
  }
  return false;
}

/// These must never be cached by the browser: `index.html` names the current
/// `main.dart.js` and the service worker carries the resource manifest, so a
/// stale copy of either pins the user to an old build (the exact symptom
/// DEPLOYMENT.md tells the operator to hard-refresh away).
bool _isNoCache(String path) =>
    path.isEmpty || path == 'index.html' || path == 'flutter_service_worker.js';

/// Resolves a request path to a real file inside [webDir], or null if it
/// escapes the directory or doesn't exist.
///
/// The containment check is the important half: this handler joins a
/// client-controlled path onto a server directory, so without it a
/// `..`-laden request could address any file the process can read.
/// `shelf_static` does its own equivalent check; this path bypasses
/// `shelf_static` entirely and therefore has to repeat it.
File? _resolveWithinWebDir(String webDir, String relativePath) {
  final rootPath = p.normalize(p.absolute(webDir));
  final candidate = p.normalize(p.join(rootPath, relativePath));
  if (candidate != rootPath && !p.isWithin(rootPath, candidate)) return null;
  final file = File(candidate);
  return file.existsSync() ? file : null;
}

/// Serves the compiled Flutter web build from [webDir].
///
/// Two things beyond plain static serving:
///
/// * **Pre-compressed variants.** The image gzips every compressible file at
///   build time (see /Dockerfile); when the client accepts gzip and a
///   `<file>.gz` exists, that is what gets sent. Pre-compressing rather than
///   compressing per request is deliberate -- this runs on a modest home
///   server, and gzipping a 7.6 MB `main.dart.js` on every request would trade a bandwidth
///   problem for a worse CPU one. The saving is large: the whole build is
///   ~39 MB raw against ~12 MB gzipped, and `main.dart.js` alone is 7.6 MB
///   against 2.0 MB.
/// * **SPA fallback.** Any path that isn't a real file returns index.html, so
///   a hard refresh on a client-side route loads the app instead of a 404.
Handler buildWebHandler(String webDir) {
  final staticHandler = createStaticHandler(webDir, defaultDocument: 'index.html');
  final indexFile = File(p.join(webDir, 'index.html'));

  return (Request request) async {
    final path = request.url.path;
    // A directory request ("" or "some/dir/") is the default document; that is
    // what shelf_static would resolve it to, and it's what we must look for a
    // .gz beside.
    final filePath = path.isEmpty || path.endsWith('/')
        ? p.join(path, 'index.html')
        : path;

    final gzipped = _acceptsGzip(request)
        ? _resolveWithinWebDir(webDir, '$filePath.gz')
        : null;

    if (gzipped != null) {
      final contentType = _compressibleContentTypeFor(filePath);
      if (contentType != null) {
        final bytes = await gzipped.readAsBytes();
        return Response.ok(bytes, headers: {
          'content-type': contentType,
          'content-encoding': 'gzip',
          'content-length': '${bytes.length}',
          // Without this a shared cache (the operator's reverse proxy) can
          // hand a gzipped body to a client that never asked for one.
          'vary': 'Accept-Encoding',
          if (_isNoCache(path)) 'cache-control': 'no-cache',
        });
      }
    }

    final response = await staticHandler(request);
    if (response.statusCode == 404 && await indexFile.exists()) {
      return Response.ok(await indexFile.readAsString(),
          headers: {'content-type': 'text/html', 'cache-control': 'no-cache'});
    }

    // Advertised on the uncompressed path too: the same URL can legitimately
    // answer with or without gzip depending on the request, and a cache that
    // hasn't been told that will serve whichever it saw first to everyone.
    if (_isNoCache(path)) {
      return response
          .change(headers: {'cache-control': 'no-cache', 'vary': 'Accept-Encoding'});
    }
    return response.change(headers: {'vary': 'Accept-Encoding'});
  };
}
