import 'dart:convert';

import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:http/http.dart' as http;

/// Replaces Google Drive's appDataFolder + Firebase Auth for this fork's
/// self-hosted server (see specs/03-stage-1-kill-google.md). A file here is
/// identified by its filename alone (unlike Drive's opaque file ids) --
/// `id` is kept equal to `name` so existing UI code that expected a
/// drive.File-shaped object with an `id` field needs no further changes.
class SyncFile {
  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int? size;

  SyncFile({
    required this.name,
    this.modifiedTime,
    this.size,
  }) : id = name;

  factory SyncFile.fromJson(Map<String, dynamic> json) {
    return SyncFile(
      name: json['filename'] as String,
      modifiedTime: json['modifiedTime'] == null
          ? null
          : DateTime.tryParse(json['modifiedTime'] as String),
      size: json['size'] as int?,
    );
  }
}

/// The signed-in session for this fork's self-hosted server. Kept entirely
/// separate from `googleUser` (still used only by the opt-in receipt/
/// attachment upload feature in uploadAttachment.dart, which is out of
/// scope for the auth/sync/backup replacement -- see specs/03-stage-1-kill-google.md).
class SelfHostedSession {
  final String serverUrl;
  final String email;
  String sessionToken;
  DateTime expiresAt;

  SelfHostedSession({
    required this.serverUrl,
    required this.email,
    required this.sessionToken,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'email': email,
        'sessionToken': sessionToken,
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory SelfHostedSession.fromJson(Map<String, dynamic> json) {
    return SelfHostedSession(
      serverUrl: json['serverUrl'] as String,
      email: json['email'] as String,
      sessionToken: json['sessionToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }
}

/// Set at launch from persisted storage (see [loadPersistedSelfHostedSession])
/// and updated by [selfHostedLogin]/[selfHostedLogout]/[selfHostedRefresh].
/// This is the single "are we signed in" source of truth for the self-hosted
/// path, mirroring the old `googleUser == null` check.
SelfHostedSession? selfHostedSession;

const _sessionPrefsKey = "selfHostedSession";

/// Reads any previously-saved session from local storage. Purely local --
/// no network call -- so it can run unconditionally on startup without
/// risking the local-first invariant (specs/01-local-first-invariant.md).
Future<void> loadPersistedSelfHostedSession() async {
  final raw = sharedPreferences.getString(_sessionPrefsKey);
  if (raw == null) return;
  try {
    selfHostedSession = SelfHostedSession.fromJson(jsonDecode(raw));
  } catch (e) {
    print("Error loading persisted self-hosted session: $e");
    selfHostedSession = null;
  }
}

Future<void> _persistSession() async {
  if (selfHostedSession == null) {
    await sharedPreferences.remove(_sessionPrefsKey);
  } else {
    await sharedPreferences.setString(
        _sessionPrefsKey, jsonEncode(selfHostedSession!.toJson()));
  }
}

String _normalizeServerUrl(String serverUrl) {
  String url = serverUrl.trim();
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  return url;
}

/// Response shape for `POST /sync/push` (specs/04-stage-2-instant-sync.md).
class SyncPushResult {
  final DateTime serverTime;
  final int conflictCount;
  SyncPushResult({required this.serverTime, required this.conflictCount});
}

/// Response shape for `GET /sync/pull`.
class SyncPullResult {
  final List<Map<String, dynamic>> changes;
  final int nextCursor;
  final bool hasMore;
  SyncPullResult({required this.changes, required this.nextCursor, required this.hasMore});
}

/// Thrown when `GET /sync/pull` answers `409 rebootstrap`: the client's cursor
/// points below what the server still retains, which is what a Reset Sync on
/// another device leaves behind. The only valid response is to drop both local
/// cursors and start over from scratch. See specs/04-stage-2-instant-sync.md.
class SyncRebootstrapRequiredException implements Exception {
  /// Where the server's feed now starts. The client resumes from here rather
  /// than from 0 -- resuming from 0 would just trip the same 409 again.
  final int minRetainedSeq;
  SyncRebootstrapRequiredException(this.minRetainedSeq);
}

class InvalidLoginException implements Exception {}

/// Logs in against the configured self-hosted server and persists the
/// resulting session. Never throws for expected failure modes (bad
/// credentials, unreachable server) -- returns false instead, matching
/// the local-first invariant's "never block the UI on a network failure".
Future<bool> selfHostedLogin({
  required String serverUrl,
  required String email,
  required String password,
}) async {
  final url = _normalizeServerUrl(serverUrl);
  try {
    final response = await http
        .post(
          Uri.parse('$url/auth/login'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return false;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    selfHostedSession = SelfHostedSession(
      serverUrl: url,
      email: email,
      sessionToken: body['sessionToken'] as String,
      expiresAt: DateTime.parse(body['expiresAt'] as String),
    );
    await _persistSession();
    await updateSettings("serverUrl", url, updateGlobalState: false);
    await updateSettings("currentUserEmail", email, updateGlobalState: false);
    await updateSettings("hasSignedIn", true, updateGlobalState: false);
    return true;
  } catch (e) {
    print("Error logging in to self-hosted server: $e");
    return false;
  }
}

/// Silent, non-blocking re-auth: rotates the session token before it
/// expires. Failure just leaves the old (possibly-expired) token in place --
/// sync/backup calls will no-op until the next successful refresh or manual
/// login, never blocking the app. Mirrors the old
/// `signInGoogle(silentSignIn: true, waitForCompletion: false)` pattern.
Future<bool> selfHostedRefresh() async {
  final session = selfHostedSession;
  if (session == null) return false;
  try {
    final response = await http
        .post(
          Uri.parse('${session.serverUrl}/auth/refresh'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'sessionToken': session.sessionToken}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return false;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    session.sessionToken = body['sessionToken'] as String;
    session.expiresAt = DateTime.parse(body['expiresAt'] as String);
    await _persistSession();
    return true;
  } catch (e) {
    print("Error refreshing self-hosted session: $e");
    return false;
  }
}

Future<bool> selfHostedLogout() async {
  final session = selfHostedSession;
  if (session != null) {
    try {
      await http.post(
        Uri.parse('${session.serverUrl}/auth/logout'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'sessionToken': session.sessionToken}),
      );
    } catch (e) {
      print("Error logging out (ignoring, clearing local session anyway): $e");
    }
  }
  selfHostedSession = null;
  await _persistSession();
  await updateSettings("currentUserEmail", "", updateGlobalState: false);
  await updateSettings("hasSignedIn", false, updateGlobalState: false);
  return true;
}

class SelfHostedUnauthenticatedException implements Exception {}

/// Common shape for anywhere a backup can be stored/listed/restored from.
/// Lets accountAndBackup.dart's backup functions work identically whether
/// the destination is this fork's own server or an optional WebDAV target
/// (see lib/struct/webdavClient.dart and specs/03-stage-1-kill-google.md)
/// without branching on which one is active.
abstract class BackupTransport {
  Future<List<SyncFile>> listFiles();
  Future<List<int>> getFile(String filename);
  Future<void> putFile(String filename, List<int> bytes);
  Future<void> deleteFile(String filename);
}

/// Talks to one of this fork's two file namespaces -- `/sync/files` (device
/// snapshot-diff transport) or `/backup` (full backups) -- both scoped
/// server-side to the authenticated user. See specs/03-stage-1-kill-google.md.
/// Implements [BackupTransport] via its `/sync/files` methods -- that's the
/// only transport the device-to-device sync path is ever allowed to use.
class SelfHostedClient implements BackupTransport {
  final SelfHostedSession session;
  SelfHostedClient(this.session);

  Map<String, String> get _authHeader =>
      {'authorization': 'Bearer ${session.sessionToken}'};

  Future<T> _withRefreshRetry<T>(Future<T> Function() attempt) async {
    try {
      return await attempt();
    } on SelfHostedUnauthenticatedException {
      final refreshed = await selfHostedRefresh();
      if (!refreshed) rethrow;
      return await attempt();
    }
  }

  void _throwIfUnauthenticated(http.Response response) {
    if (response.statusCode == 401) throw SelfHostedUnauthenticatedException();
  }

  Future<List<SyncFile>> listFiles() => _withRefreshRetry(() async {
        final response = await http
            .get(Uri.parse('${session.serverUrl}/sync/files'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwIfUnauthenticated(response);
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((e) => SyncFile.fromJson(e)).toList();
      });

  Future<List<int>> getFile(String filename) => _withRefreshRetry(() async {
        final response = await http
            .get(Uri.parse('${session.serverUrl}/sync/files/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 60));
        _throwIfUnauthenticated(response);
        return response.bodyBytes;
      });

  Future<void> putFile(String filename, List<int> bytes) =>
      _withRefreshRetry(() async {
        final response = await http
            .put(Uri.parse('${session.serverUrl}/sync/files/$filename'),
                headers: _authHeader, body: bytes)
            .timeout(const Duration(seconds: 60));
        _throwIfUnauthenticated(response);
      });

  Future<void> deleteFile(String filename) => _withRefreshRetry(() async {
        final response = await http
            .delete(Uri.parse('${session.serverUrl}/sync/files/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwIfUnauthenticated(response);
      });

  Future<List<SyncFile>> listBackupFiles() => _withRefreshRetry(() async {
        final response = await http
            .get(Uri.parse('${session.serverUrl}/backup/list'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwIfUnauthenticated(response);
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((e) => SyncFile.fromJson(e)).toList();
      });

  Future<List<int>> getBackupFile(String filename) =>
      _withRefreshRetry(() async {
        final response = await http
            .get(Uri.parse('${session.serverUrl}/backup/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 60));
        _throwIfUnauthenticated(response);
        return response.bodyBytes;
      });

  Future<void> putBackupFile(String filename, List<int> bytes) =>
      _withRefreshRetry(() async {
        final response = await http
            .put(Uri.parse('${session.serverUrl}/backup/$filename'),
                headers: _authHeader, body: bytes)
            .timeout(const Duration(seconds: 60));
        _throwIfUnauthenticated(response);
      });

  Future<void> deleteBackupFile(String filename) =>
      _withRefreshRetry(() async {
        final response = await http
            .delete(Uri.parse('${session.serverUrl}/backup/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwIfUnauthenticated(response);
      });

  /// Stage 2 row-level change feed -- see specs/04-stage-2-instant-sync.md.
  Future<SyncPushResult> pushSyncChanges({
    required String deviceId,
    required List<Map<String, dynamic>> changes,
  }) =>
      _withRefreshRetry(() async {
        final response = await http
            .post(Uri.parse('${session.serverUrl}/sync/push'),
                headers: {..._authHeader, 'content-type': 'application/json'},
                body: jsonEncode({'deviceId': deviceId, 'changes': changes}))
            .timeout(const Duration(seconds: 30));
        _throwIfUnauthenticated(response);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return SyncPushResult(
          serverTime: DateTime.fromMillisecondsSinceEpoch(body['serverTime'] as int),
          conflictCount: body['conflictCount'] as int,
        );
      });

  Future<SyncPullResult> pullSyncChanges({required int since, int limit = 500}) =>
      _withRefreshRetry(() async {
        final response = await http
            .get(Uri.parse('${session.serverUrl}/sync/pull?since=$since&limit=$limit'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 30));
        _throwIfUnauthenticated(response);
        if (response.statusCode == 409) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          throw SyncRebootstrapRequiredException(
              (body['minRetainedSeq'] as int?) ?? 0);
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return SyncPullResult(
          changes: (body['changes'] as List).cast<Map<String, dynamic>>(),
          nextCursor: body['nextCursor'] as int,
          hasMore: body['hasMore'] as bool,
        );
      });

  /// Clears the server's row-level change feed for this user. Local databases
  /// and stored backups are untouched -- the next device to run a cycle
  /// re-uploads its own data and becomes the new baseline. Mirrors upstream
  /// Cashew's "Reset Sync". See specs/04-stage-2-instant-sync.md.
  /// Returns the feed's new starting seq, which the caller stores as its pull
  /// cursor.
  Future<int> resetSyncDatabase() => _withRefreshRetry(() async {
        final response = await http
            .post(Uri.parse('${session.serverUrl}/sync/reset'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 30));
        _throwIfUnauthenticated(response);
        if (response.statusCode != 200) {
          throw Exception('Reset sync failed: ${response.statusCode}');
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return (body['minRetainedSeq'] as int?) ?? 0;
      });
}

/// Adapts [SelfHostedClient]'s `/backup` namespace to [BackupTransport], so
/// "back up to my own server" and "back up to WebDAV" are interchangeable
/// at the call site (see getBackupTransport() in accountAndBackup.dart).
class SelfHostedBackupTransport implements BackupTransport {
  final SelfHostedClient _client;
  SelfHostedBackupTransport(this._client);

  @override
  Future<List<SyncFile>> listFiles() => _client.listBackupFiles();

  @override
  Future<List<int>> getFile(String filename) =>
      _client.getBackupFile(filename);

  @override
  Future<void> putFile(String filename, List<int> bytes) =>
      _client.putBackupFile(filename, bytes);

  @override
  Future<void> deleteFile(String filename) =>
      _client.deleteBackupFile(filename);
}
