import 'dart:convert';

import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Optional WebDAV backup target (e.g. Nextcloud), configured entirely
/// client-side per specs/03-stage-1-kill-google.md. This talks directly to
/// the WebDAV server -- the self-hosted server (selfHostedClient.dart) never
/// proxies or knows about this path.
class WebDavConfig {
  final String url;
  final String username;
  final String password;
  final String folder;

  WebDavConfig({
    required this.url,
    required this.username,
    required this.password,
    required this.folder,
  });

  bool get isConfigured => url.trim().isNotEmpty && username.trim().isNotEmpty;
}

class WebDavException implements Exception {
  final String message;
  WebDavException(this.message);
  @override
  String toString() => message;
}

/// Minimal WebDAV client (PROPFIND/GET/PUT/DELETE/MKCOL) covering just what
/// backup storage needs. Hand-rolled instead of pulling in a WebDAV package
/// since the surface area is tiny and this avoids a new dependency of
/// uncertain compatibility with the pinned Flutter 3.19.6 toolchain.
///
/// Known limitation: on Flutter web, PROPFIND/MKCOL are non-simple CORS
/// requests, so the WebDAV server must allow them (and the Authorization
/// header) via CORS for this to work from a browser tab. Nextcloud does not
/// do this by default. Native (Android) builds are unaffected.
class WebDavClient implements BackupTransport {
  final WebDavConfig config;
  WebDavClient(this.config);

  String get _base {
    String url = config.url.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    String folder = config.folder.trim();
    folder = folder.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    return folder.isEmpty ? url : '$url/$folder';
  }

  Map<String, String> get _authHeader => {
        'authorization':
            'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
      };

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final request = http.Request(method, uri);
    request.headers.addAll(_authHeader);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    final streamed =
        await request.send().timeout(const Duration(seconds: 60));
    return http.Response.fromStream(streamed);
  }

  /// Creates the backup folder if missing. Ignores "already exists"
  /// responses -- 405 (Apache/sabre) or 409/301 depending on server.
  Future<void> _ensureFolder() async {
    try {
      await _send('MKCOL', Uri.parse(_base));
    } catch (e) {
      // Best-effort: if the folder already exists or the server rejects
      // MKCOL for another reason, the subsequent PUT/PROPFIND call will
      // surface a clearer error if the folder genuinely isn't usable.
    }
  }

  @override
  Future<List<SyncFile>> listFiles() async {
    await _ensureFolder();
    final response = await _send('PROPFIND', Uri.parse(_base), headers: {
      'Depth': '1',
      'Content-Type': 'application/xml; charset=utf-8',
    }, body: utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getlastmodified/>
    <d:getcontentlength/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>'''));
    if (response.statusCode != 207) {
      throw WebDavException(
          'WebDAV listing failed (HTTP ${response.statusCode})');
    }
    return _parseListing(response.body);
  }

  @override
  Future<List<int>> getFile(String filename) async {
    final response = await _send(
        'GET', Uri.parse('$_base/${Uri.encodeComponent(filename)}'));
    if (response.statusCode != 200) {
      throw WebDavException(
          'WebDAV download failed (HTTP ${response.statusCode})');
    }
    return response.bodyBytes;
  }

  @override
  Future<void> putFile(String filename, List<int> bytes) async {
    await _ensureFolder();
    final response = await _send(
        'PUT', Uri.parse('$_base/${Uri.encodeComponent(filename)}'),
        body: bytes);
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw WebDavException(
          'WebDAV upload failed (HTTP ${response.statusCode})');
    }
  }

  @override
  Future<void> deleteFile(String filename) async {
    final response = await _send(
        'DELETE', Uri.parse('$_base/${Uri.encodeComponent(filename)}'));
    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      throw WebDavException(
          'WebDAV delete failed (HTTP ${response.statusCode})');
    }
  }

  List<SyncFile> _parseListing(String xml) {
    final files = <SyncFile>[];
    final responseRegex = RegExp(
      r'<[a-zA-Z0-9]*:?response[ >].*?</[a-zA-Z0-9]*:?response>',
      dotAll: true,
    );
    for (final match in responseRegex.allMatches(xml)) {
      final block = match.group(0)!;
      final href = _extractTag(block, 'href');
      if (href == null || href.isEmpty) continue;
      if (href.endsWith('/')) continue; // the folder entry itself
      if (RegExp(r'<[a-zA-Z0-9]*:?collection\s*/?>').hasMatch(block)) {
        continue;
      }
      final decodedHref = Uri.decodeComponent(href);
      final name = decodedHref
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .last;
      final lastModifiedRaw = _extractTag(block, 'getlastmodified');
      final contentLengthRaw = _extractTag(block, 'getcontentlength');
      files.add(SyncFile(
        name: name,
        modifiedTime:
            lastModifiedRaw == null ? null : _parseHttpDate(lastModifiedRaw),
        size: contentLengthRaw == null ? null : int.tryParse(contentLengthRaw),
      ));
    }
    files.sort((a, b) =>
        (b.modifiedTime ?? DateTime(0)).compareTo(a.modifiedTime ?? DateTime(0)));
    return files;
  }

  String? _extractTag(String block, String localName) {
    final regex = RegExp(
      '<[a-zA-Z0-9]*:?$localName[^>]*>(.*?)</[a-zA-Z0-9]*:?$localName>',
      dotAll: true,
    );
    return regex.firstMatch(block)?.group(1)?.trim();
  }

  DateTime? _parseHttpDate(String raw) {
    try {
      return DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US')
          .parseUtc(raw);
    } catch (e) {
      return DateTime.tryParse(raw);
    }
  }
}
