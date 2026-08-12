import 'dart:convert';
import 'dart:io';

import 'package:server/src/web_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Covers the pre-compressed-asset path added for low-powered deployments:
/// the image gzips the web build at image-build time (see /Dockerfile) and
/// this handler picks the .gz when the request allows it. The saving is the
/// whole point (7.6 MB -> 2.0 MB on main.dart.js), so a silent regression back
/// to serving everything raw is worth a test.
void main() {
  late Directory webDir;
  late Handler handler;

  /// The plain file every test asserts against, plus a .gz beside it whose
  /// contents are deliberately *distinguishable* from a real gzip of the
  /// original -- that's how each test can tell which of the two was served.
  setUp(() {
    webDir = Directory.systemTemp.createTempSync('cashew-web-test');
    File('${webDir.path}/main.dart.js').writeAsStringSync('RAW_JS_BODY');
    File('${webDir.path}/main.dart.js.gz')
        .writeAsBytesSync(gzip.encode(utf8.encode('GZIPPED_JS_BODY')));
    File('${webDir.path}/index.html').writeAsStringSync('<html>raw index</html>');
    File('${webDir.path}/index.html.gz')
        .writeAsBytesSync(gzip.encode(utf8.encode('<html>gzipped index</html>')));
    // No .gz beside this one -- the fallback-to-raw case.
    File('${webDir.path}/favicon.png').writeAsBytesSync([1, 2, 3, 4]);
    handler = buildWebHandler(webDir.path);
  });

  tearDown(() => webDir.deleteSync(recursive: true));

  Future<Response> get(String path, {String? acceptEncoding}) {
    return Future.value(handler(Request(
      'GET',
      Uri.parse('http://localhost/$path'),
      headers: {if (acceptEncoding != null) 'accept-encoding': acceptEncoding},
    )));
  }

  group('pre-compressed assets', () {
    test('serves the .gz when the client accepts gzip', () async {
      final response = await get('main.dart.js', acceptEncoding: 'gzip, deflate, br');

      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], 'gzip');
      expect(response.headers['content-type'], 'application/javascript');
      expect(response.headers['vary'], contains('Accept-Encoding'));
      expect(utf8.decode(gzip.decode(await response.read().expand((c) => c).toList())),
          'GZIPPED_JS_BODY');
    });

    test('serves the raw file when the client says nothing', () async {
      final response = await get('main.dart.js');

      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], isNull);
      expect(await response.readAsString(), 'RAW_JS_BODY');
    });

    test('honours gzip;q=0 as a refusal rather than an offer', () async {
      final response = await get('main.dart.js', acceptEncoding: 'gzip;q=0, identity');

      expect(response.headers['content-encoding'], isNull);
      expect(await response.readAsString(), 'RAW_JS_BODY');
    });

    test('compresses NOTICES, which has no extension to match on', () async {
      File('${webDir.path}/NOTICES').writeAsStringSync('raw notices');
      File('${webDir.path}/NOTICES.gz')
          .writeAsBytesSync(gzip.encode(utf8.encode('gzipped notices')));

      final response = await get('NOTICES', acceptEncoding: 'gzip');

      expect(response.headers['content-encoding'], 'gzip');
      expect(response.headers['content-type'], 'text/plain');
    });

    test('falls back to the raw file when no .gz was built', () async {
      final response = await get('favicon.png', acceptEncoding: 'gzip');

      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], isNull);
    });

    test('advertises Vary on the uncompressed path too', () async {
      // Otherwise a shared cache that first saw an identity request will hand
      // that same body to every gzip-capable client, and vice versa.
      final response = await get('favicon.png');

      expect(response.headers['vary'], contains('Accept-Encoding'));
    });
  });

  group('cache headers survive compression', () {
    test('a gzipped index.html is still no-cache', () async {
      final response = await get('', acceptEncoding: 'gzip');

      expect(response.headers['content-encoding'], 'gzip');
      expect(response.headers['content-type'], 'text/html');
      expect(response.headers['cache-control'], 'no-cache');
    });

    test('a raw index.html is still no-cache', () async {
      final response = await get('');

      expect(response.headers['cache-control'], 'no-cache');
    });
  });

  group('safety', () {
    test('a traversal path cannot escape the web directory', () async {
      final secret = File('${webDir.parent.path}/outside-the-webroot.js')
        ..writeAsStringSync('SHOULD_NOT_BE_SERVED');
      addTearDown(() => secret.deleteSync());

      final response =
          await get('../outside-the-webroot.js', acceptEncoding: 'gzip');

      expect(response.headers['content-encoding'], isNull);
      expect(await response.readAsString(), isNot(contains('SHOULD_NOT_BE_SERVED')));
    });

    test('an unknown route still falls back to index.html', () async {
      final response = await get('budgets/some-client-side-route');

      expect(response.statusCode, 200);
      expect(await response.readAsString(), contains('raw index'));
    });
  });
}
