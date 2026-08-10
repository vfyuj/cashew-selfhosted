import 'dart:convert';

import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:http/http.dart' as http;

/// One client for the whole app, rather than `package:http`'s top-level
/// `http.get`/`http.post` helpers.
///
/// Those helpers open a client, send, and close it again for every single
/// call -- so each one paid a fresh TCP connection and a full TLS handshake.
/// Live sync makes a steady trickle of small requests forever, and the
/// handshakes cost far more than the requests do: on the phone it is radio
/// time and battery, on the server it is asymmetric crypto per poll. Holding
/// one client lets keep-alive do its job and collapses that to a single
/// connection.
///
/// Never closed: it lives as long as the process. On web this is a
/// `BrowserClient` and the browser owns the connection pool anyway.
final http.Client _httpClient = http.Client();

/// Replaced Google Drive's appDataFolder + Firebase Auth for this fork's
/// self-hosted server (see specs/03-stage-1-kill-google.md). A file here is
/// identified by its filename alone (unlike Drive's opaque file ids) --
/// `id` is kept equal to `name` because the UI this replaced expected a
/// drive.File-shaped object with an `id` field.
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

/// The signed-in session for this fork's self-hosted server -- the single
/// "are we signed in" source of truth now that every Google code path is gone
/// (see specs/03-stage-1-kill-google.md).
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
/// path.
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

/// The signed-in user's account details, as the server knows them.
class ServerProfile {
  final int id;
  final String email;
  final String name;
  final bool isAdmin;

  ServerProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.isAdmin,
  });

  /// Falls back rather than throwing on a missing field, so an older server
  /// that doesn't send `user` yet can't break sign-in.
  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
        id: json['id'] as int? ?? 0,
        email: json['email'] as String? ?? "",
        name: json['name'] as String? ?? "",
        isAdmin: json['isAdmin'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'email': email, 'name': name, 'isAdmin': isAdmin};

  /// What to show as this person's display name, never blank.
  String get displayName => name.trim().isNotEmpty ? name.trim() : email;
}

/// Another account on this instance, as listed by an administrator.
class ServerUser {
  final int id;
  final String email;
  final String name;
  final bool isAdmin;

  ServerUser({
    required this.id,
    required this.email,
    required this.name,
    required this.isAdmin,
  });

  factory ServerUser.fromJson(Map<String, dynamic> json) => ServerUser(
        id: json['id'] as int? ?? 0,
        email: json['email'] as String? ?? "",
        name: json['name'] as String? ?? "",
        isAdmin: json['isAdmin'] == true,
      );

  String get displayName => name.trim().isNotEmpty ? name.trim() : email;
}

/// A newly-provisioned account plus the one-time password to hand over. The
/// server only ever returns this password once -- it is not recoverable, only
/// re-issuable.
class CreatedUser {
  final ServerUser user;
  final String temporaryPassword;
  CreatedUser(this.user, this.temporaryPassword);
}

/// Why a server call didn't succeed, so callers can show a specific message
/// instead of a generic failure. Nothing in this file throws for these --
/// see the local-first note on [selfHostedLogin].
enum ServerCallResult {
  ok,

  /// Wrong email/password, wrong current password, or no session at all.
  invalidCredentials,

  /// Signed in, but not an administrator.
  forbidden,

  /// Email already taken, server already set up, or would remove the last
  /// administrator.
  conflict,

  /// The request itself was rejected -- in practice, a password below the
  /// server's minimum length.
  validationError,

  /// Couldn't reach the server at all. Never an error worth blocking on.
  unreachable,

  serverError,
}

ServerCallResult _resultFromStatus(int statusCode) {
  if (statusCode >= 200 && statusCode < 300) return ServerCallResult.ok;
  switch (statusCode) {
    case 400:
      return ServerCallResult.validationError;
    // 401 means the session is gone; 422 means the credential in the body was
    // wrong. The server keeps these distinct on purpose -- see the password
    // handler in server/lib/src/auth/auth_routes.dart.
    case 401:
    case 422:
      return ServerCallResult.invalidCredentials;
    case 403:
      return ServerCallResult.forbidden;
    case 409:
      return ServerCallResult.conflict;
    default:
      return ServerCallResult.serverError;
  }
}

/// The signed-in user's profile, cached locally.
///
/// The UI reads `isAdmin` and the display name from here, never from a live
/// call -- that's what lets the account page render correctly with no network,
/// as required by specs/01-local-first-invariant.md.
ServerProfile? cachedServerProfile;

/// Deliberately a separate key from [_sessionPrefsKey] rather than extra fields
/// on [SelfHostedSession]: [_persistSession] rewrites that JSON on every token
/// refresh and must not be able to clobber profile data, and
/// [SelfHostedSession.fromJson]'s fields are all non-nullable, so widening it
/// would fail to deserialize sessions saved by an older build.
const _profilePrefsKey = "selfHostedProfile";

/// Local-only read, mirroring [loadPersistedSelfHostedSession] -- no network,
/// safe to call unconditionally at startup.
Future<void> loadPersistedServerProfile() async {
  final raw = sharedPreferences.getString(_profilePrefsKey);
  if (raw == null) return;
  try {
    cachedServerProfile = ServerProfile.fromJson(jsonDecode(raw));
  } catch (e) {
    print("Error loading persisted server profile: $e");
    cachedServerProfile = null;
  }
}

Future<void> _persistServerProfile() async {
  if (cachedServerProfile == null) {
    await sharedPreferences.remove(_profilePrefsKey);
  } else {
    await sharedPreferences.setString(
        _profilePrefsKey, jsonEncode(cachedServerProfile!.toJson()));
  }
}

Future<void> _adoptProfile(Map<String, dynamic>? userJson) async {
  if (userJson == null) return;
  cachedServerProfile = ServerProfile.fromJson(userJson);
  await _persistServerProfile();
  await reconcileLocalUsername(newServerName: cachedServerProfile!.name);
}

/// Seeds the local display name from the server account name.
///
/// These are deliberately NOT the same value. `appStateSettings["username"]` is
/// the home-page greeting: purely local, editable offline, and it has to keep
/// working for someone who never signs in at all -- making it depend on auth
/// would violate specs/01-local-first-invariant.md. So this only ever copies
/// server -> local, and only when doing so can't discard a choice the user made:
/// either the local name is empty, or it still exactly matches what the server
/// previously said (the common "never diverged" case).
Future<void> reconcileLocalUsername({
  String? previousServerName,
  required String newServerName,
}) async {
  if (newServerName.trim().isEmpty) return;
  final local = (appStateSettings["username"] ?? "").toString();
  final safeToOverwrite =
      local.trim().isEmpty || (previousServerName != null && local == previousServerName);
  if (!safeToOverwrite) return;
  await updateSettings("username", newServerName,
      pagesNeedingRefresh: [0], updateGlobalState: false);
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

/// Turns a successful login/setup response into the signed-in local state.
/// Shared by [selfHostedLogin] and [selfHostedSetup] so the session, the
/// settings writes and the profile cache can never drift apart.
Future<void> _adoptSessionResponse(
    String url, String email, Map<String, dynamic> body) async {
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
  await _adoptProfile(body['user'] as Map<String, dynamic>?);
}

/// Asks whether an instance still needs its first account.
///
/// Returns null for "couldn't find out" -- unreachable, wrong address, or
/// anything unexpected. Callers must treat null as "keep the local-only path
/// available" and never as an error worth blocking on. The timeout is
/// deliberately shorter than [selfHostedLogin]'s because this runs on the
/// app's launch path (specs/01-local-first-invariant.md).
Future<bool?> selfHostedSetupState(
  String serverUrl, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final url = _normalizeServerUrl(serverUrl);
  if (url.isEmpty) return null;
  try {
    final response =
        await _httpClient.get(Uri.parse('$url/auth/setup-state')).timeout(timeout);
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final needsSetup = body['needsSetup'];
    return needsSetup is bool ? needsSetup : null;
  } catch (e) {
    print("Could not reach self-hosted server at $url: $e");
    return null;
  }
}

/// Creates the instance's first account, which becomes its administrator, and
/// signs in as it. Only succeeds while the instance has no users -- afterwards
/// the server answers 409 and the caller should fall back to signing in.
Future<ServerCallResult> selfHostedSetup({
  required String serverUrl,
  required String email,
  required String name,
  required String password,
}) async {
  final url = _normalizeServerUrl(serverUrl);
  try {
    final response = await _httpClient
        .post(
          Uri.parse('$url/auth/setup'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'email': email, 'name': name, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return _resultFromStatus(response.statusCode);
    await _adoptSessionResponse(
        url, email, jsonDecode(response.body) as Map<String, dynamic>);
    return ServerCallResult.ok;
  } catch (e) {
    print("Error setting up self-hosted server: $e");
    return ServerCallResult.unreachable;
  }
}

/// Logs in against the configured self-hosted server and persists the
/// resulting session. Never throws for expected failure modes (bad
/// credentials, unreachable server) -- returns false instead, matching
/// the local-first invariant's "never block the UI on a network failure".
Future<bool> selfHostedLogin({
  required String serverUrl,
  required String email,
  required String password,
}) async {
  return await selfHostedLoginDetailed(
        serverUrl: serverUrl,
        email: email,
        password: password,
      ) ==
      ServerCallResult.ok;
}

/// As [selfHostedLogin], but distinguishes "wrong password" from "couldn't
/// reach the server" so the sign-in form can say which happened.
Future<ServerCallResult> selfHostedLoginDetailed({
  required String serverUrl,
  required String email,
  required String password,
}) async {
  final url = _normalizeServerUrl(serverUrl);
  try {
    final response = await _httpClient
        .post(
          Uri.parse('$url/auth/login'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return _resultFromStatus(response.statusCode);
    await _adoptSessionResponse(
        url, email, jsonDecode(response.body) as Map<String, dynamic>);
    return ServerCallResult.ok;
  } catch (e) {
    print("Error logging in to self-hosted server: $e");
    return ServerCallResult.unreachable;
  }
}

/// Silent, non-blocking re-auth: rotates the session token before it
/// expires. Failure just leaves the old (possibly-expired) token in place --
/// sync/backup calls will no-op until the next successful refresh or manual
/// login, never blocking the app -- see specs/01-local-first-invariant.md.
/// How much of a session's life is allowed to run out before the background
/// sync cycle bothers renewing it. Sessions last 30 days
/// (`sessionDuration` in server/lib/src/auth/auth_service.dart), so a device
/// that syncs at least once a week never lets one lapse.
const _sessionRenewWithin = Duration(days: 7);

/// Renews the session only when it is actually close to expiring.
///
/// The sync cycle used to call [selfHostedRefresh] unconditionally on every
/// tick, which meant rotating a 30-day token roughly every 45 seconds: a
/// request, a `DELETE`+`INSERT` on the server's `sessions` table, and a
/// SharedPreferences write on the device, ~1900 times a day, per device, to
/// extend an expiry that was never near. On a Raspberry Pi that is a
/// meaningful share of the SD card's write budget; on a phone it is wasted
/// radio and flash.
///
/// Skipping the renewal is safe because nothing depends on it: [SelfHostedClient]
/// already refreshes and retries on a 401 (`_withRefreshRetry`), so a token
/// that goes stale sooner than expected still recovers on its own.
Future<bool> selfHostedRefreshIfNeeded() async {
  final session = selfHostedSession;
  if (session == null) return false;
  if (session.expiresAt.difference(DateTime.now()) > _sessionRenewWithin) {
    return true; // plenty of life left
  }
  return await selfHostedRefresh();
}

Future<bool> selfHostedRefresh() async {
  final session = selfHostedSession;
  if (session == null) return false;
  try {
    final response = await _httpClient
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
      await _httpClient.post(
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
  cachedServerProfile = null;
  await _persistServerProfile();
  resetProfileFetchThrottle();
  await updateSettings("currentUserEmail", "", updateGlobalState: false);
  await updateSettings("hasSignedIn", false, updateGlobalState: false);
  return true;
}

class SelfHostedUnauthenticatedException implements Exception {}

/// Thrown when an operation that genuinely needs the server is attempted while
/// signed out. Deliberately rare: per specs/01-local-first-invariant.md almost
/// everything must work signed out, so this is only for things with no local
/// meaning at all, like uploading an attachment.
class SelfHostedSignedOutException implements Exception {}

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
        final response = await _httpClient
            .get(Uri.parse('${session.serverUrl}/sync/files'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwIfUnauthenticated(response);
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((e) => SyncFile.fromJson(e)).toList();
      });

  Future<List<int>> getFile(String filename) => _withRefreshRetry(() async {
        final response = await _httpClient
            .get(Uri.parse('${session.serverUrl}/sync/files/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 60));
        _throwIfUnauthenticated(response);
        return response.bodyBytes;
      });

  Future<void> putFile(String filename, List<int> bytes) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .put(Uri.parse('${session.serverUrl}/sync/files/$filename'),
                headers: _authHeader, body: bytes)
            .timeout(const Duration(seconds: 60));
        _throwIfUnauthenticated(response);
      });

  Future<void> deleteFile(String filename) => _withRefreshRetry(() async {
        final response = await _httpClient
            .delete(Uri.parse('${session.serverUrl}/sync/files/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwIfUnauthenticated(response);
      });

  Future<List<SyncFile>> listBackupFiles() => _withRefreshRetry(() async {
        final response = await _httpClient
            .get(Uri.parse('${session.serverUrl}/backup/list'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwIfUnauthenticated(response);
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((e) => SyncFile.fromJson(e)).toList();
      });

  Future<List<int>> getBackupFile(String filename) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .get(Uri.parse('${session.serverUrl}/backup/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 60));
        _throwIfUnauthenticated(response);
        return response.bodyBytes;
      });

  Future<void> putBackupFile(String filename, List<int> bytes) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .put(Uri.parse('${session.serverUrl}/backup/$filename'),
                headers: _authHeader, body: bytes)
            .timeout(const Duration(seconds: 60));
        _throwIfUnauthenticated(response);
      });

  Future<void> deleteBackupFile(String filename) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .delete(Uri.parse('${session.serverUrl}/backup/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwIfUnauthenticated(response);
      });

  /// Transaction attachments -- a third namespace alongside sync and backup,
  /// replacing the Google Drive upload this fork inherited from upstream.
  /// See specs/03-stage-1-kill-google.md.
  ///
  /// Returns the URL to store in the transaction note. It needs a session to
  /// fetch, exactly as the Drive link it replaces needed a Google login, so
  /// the in-app preview reads it back through [getAttachmentFile] rather than
  /// handing it to the browser.
  Future<String> putAttachmentFile(String filename, List<int> bytes) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .put(Uri.parse('${session.serverUrl}/attachments/$filename'),
                headers: _authHeader, body: bytes)
            .timeout(const Duration(seconds: 120));
        _throwIfUnauthenticated(response);
        if (response.statusCode != 200) {
          throw Exception('attachment upload failed (${response.statusCode})');
        }
        return attachmentUrl(filename);
      });

  Future<List<int>> getAttachmentFile(String filename) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .get(Uri.parse('${session.serverUrl}/attachments/$filename'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 120));
        _throwIfUnauthenticated(response);
        if (response.statusCode != 200) {
          throw Exception('attachment download failed (${response.statusCode})');
        }
        return response.bodyBytes;
      });

  String attachmentUrl(String filename) =>
      '${session.serverUrl}/attachments/$filename';

  /// Stage 2 row-level change feed -- see specs/04-stage-2-instant-sync.md.
  Future<SyncPushResult> pushSyncChanges({
    required String deviceId,
    required List<Map<String, dynamic>> changes,
  }) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
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
        final response = await _httpClient
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
        final response = await _httpClient
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
  // --- Account and instance administration -------------------------------
  //
  // These go through the same _withRefreshRetry wrapper as the file calls, so
  // an expired token is silently renewed once rather than surfacing as a
  // spurious "you've been signed out".

  Map<String, String> get _jsonHeaders =>
      {..._authHeader, 'content-type': 'application/json'};

  /// Throws [ServerCallResult] itself for non-success statuses, so the thin
  /// top-level wrappers below can catch and return it without re-deriving.
  void _throwUnlessOk(http.Response response) {
    _throwIfUnauthenticated(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _resultFromStatus(response.statusCode);
    }
  }

  Future<ServerProfile> getMe() => _withRefreshRetry(() async {
        final response = await _httpClient
            .get(Uri.parse('${session.serverUrl}/auth/me'), headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwUnlessOk(response);
        return ServerProfile.fromJson(jsonDecode(response.body));
      });

  Future<ServerProfile> patchMe({String? name, String? email}) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .patch(
              Uri.parse('${session.serverUrl}/auth/me'),
              headers: _jsonHeaders,
              body: jsonEncode({
                if (name != null) 'name': name,
                if (email != null) 'email': email,
              }),
            )
            .timeout(const Duration(seconds: 20));
        _throwUnlessOk(response);
        return ServerProfile.fromJson(jsonDecode(response.body));
      });

  /// Returns the rotated session token: changing a password signs every device
  /// out, including this one, so the server hands back a fresh token to keep
  /// the device that made the change signed in.
  Future<({String sessionToken, DateTime expiresAt})> postMyPassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .post(
              Uri.parse('${session.serverUrl}/auth/me/password'),
              headers: _jsonHeaders,
              body: jsonEncode({
                'currentPassword': currentPassword,
                'newPassword': newPassword,
              }),
            )
            .timeout(const Duration(seconds: 20));
        // A wrong current password arrives as 422, not 401, so it falls through
        // to _throwUnlessOk and is never mistaken for an expired session (which
        // would trigger a pointless token refresh and retry).
        _throwUnlessOk(response);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return (
          sessionToken: body['sessionToken'] as String,
          expiresAt: DateTime.parse(body['expiresAt'] as String),
        );
      });

  Future<List<ServerUser>> listUsers() => _withRefreshRetry(() async {
        final response = await _httpClient
            .get(Uri.parse('${session.serverUrl}/admin/users'), headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwUnlessOk(response);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return (body['users'] as List<dynamic>)
            .map((e) => ServerUser.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<CreatedUser> createUser({required String email, required String name}) =>
      _withRefreshRetry(() async {
        final response = await _httpClient
            .post(
              Uri.parse('${session.serverUrl}/admin/users'),
              headers: _jsonHeaders,
              body: jsonEncode({'email': email, 'name': name}),
            )
            .timeout(const Duration(seconds: 20));
        _throwUnlessOk(response);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return CreatedUser(
          ServerUser.fromJson(body['user'] as Map<String, dynamic>),
          body['temporaryPassword'] as String,
        );
      });

  Future<String> resetUserPassword(int userId) => _withRefreshRetry(() async {
        final response = await _httpClient
            .post(Uri.parse('${session.serverUrl}/admin/users/$userId/password'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwUnlessOk(response);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['temporaryPassword'] as String;
      });

  Future<void> deleteUser(int userId) => _withRefreshRetry(() async {
        final response = await _httpClient
            .delete(Uri.parse('${session.serverUrl}/admin/users/$userId'),
                headers: _authHeader)
            .timeout(const Duration(seconds: 20));
        _throwUnlessOk(response);
      });
}

/// True when [url] points at the signed-in server's own attachment namespace,
/// i.e. the app can fetch it with the session rather than opening a browser.
bool isSelfHostedAttachmentUrl(String url) =>
    attachmentFilenameFromUrl(url) != null;

/// Uploads an attachment and returns its URL. Throws [SelfHostedSignedOutException]
/// when signed out -- unlike sync there is no local fallback for "store this
/// file where the other device can see it", so the caller must tell the user.
Future<String> uploadAttachmentBytes(String filename, List<int> bytes) async {
  final client = _currentClient();
  if (client == null) throw SelfHostedSignedOutException();
  return await client.putAttachmentFile(filename, bytes);
}

/// Fetches a previously uploaded attachment, or null when signed out.
Future<List<int>?> downloadAttachmentBytes(String filename) async {
  final client = _currentClient();
  if (client == null) return null;
  return await client.getAttachmentFile(filename);
}

/// The stored filename inside an attachment URL, or null if [url] isn't one.
String? attachmentFilenameFromUrl(String url) {
  final session = selfHostedSession;
  if (session == null) return null;
  final prefix = '${session.serverUrl}/attachments/';
  if (!url.startsWith(prefix)) return null;
  final filename = url.substring(prefix.length);
  return filename.isEmpty ? null : filename;
}

/// Builds a client for the current session, or null when signed out. Every
/// wrapper below no-ops rather than throwing in the signed-out case -- being
/// signed out is a normal state in this app, not an error.
SelfHostedClient? _currentClient() {
  final session = selfHostedSession;
  return session == null ? null : SelfHostedClient(session);
}

/// Runs an authenticated call, mapping every expected failure onto a
/// [ServerCallResult] rather than letting it escape. Nothing in the account UI
/// should ever have to wrap a call in its own try/catch.
Future<(ServerCallResult, T?)> _guarded<T>(Future<T> Function(SelfHostedClient) call) async {
  final client = _currentClient();
  if (client == null) return (ServerCallResult.invalidCredentials, null);
  try {
    return (ServerCallResult.ok, await call(client));
  } on ServerCallResult catch (result) {
    return (result, null);
  } on SelfHostedUnauthenticatedException {
    return (ServerCallResult.invalidCredentials, null);
  } catch (e) {
    print("Self-hosted server call failed: $e");
    return (ServerCallResult.unreachable, null);
  }
}

/// Whether this account already holds data on the server -- i.e. whoever just
/// signed in is adding another device to an account that is already in use,
/// rather than starting fresh.
///
/// Used to decide whether to run onboarding after a sign-in. Answering "no"
/// is always the safe direction (onboarding is skippable and creates nothing
/// on its own), so every failure mode -- unreachable, signed out, malformed
/// response -- deliberately returns false rather than throwing.
Future<bool> selfHostedAccountHasExistingData() async {
  final client = _currentClient();
  if (client == null) return false;
  // Deliberately shorter than the client's own per-request timeouts: someone
  // is watching a sign-in complete, and "we couldn't tell" costs them only a
  // skippable onboarding pass.
  const budget = Duration(seconds: 8);
  try {
    // One row is enough to answer the question; limit=1 keeps this off the
    // critical path of a sign-in.
    final feed =
        await client.pullSyncChanges(since: 0, limit: 1).timeout(budget);
    if (feed.changes.isNotEmpty) return true;
  } on SyncRebootstrapRequiredException {
    // The feed has been reset at some point, which only ever happens to an
    // account that was already being used.
    return true;
  } catch (e) {
    print("Could not check whether this account has existing data: $e");
    return false;
  }
  try {
    // Stage 1's whole-database snapshots. An account last used by a build that
    // predates the row-level feed has these and nothing else.
    final files = await client.listFiles().timeout(budget);
    return files.isNotEmpty;
  } catch (e) {
    print("Could not list existing sync files: $e");
    return false;
  }
}

/// Refreshes the cached profile. On failure the existing cache is deliberately
/// left in place -- a network blip must not make the admin section vanish or
/// the display name blank out.
Future<ServerProfile?> selfHostedFetchProfile() async {
  final (result, profile) = await _guarded((client) => client.getMe());
  if (result != ServerCallResult.ok || profile == null) return null;
  _lastProfileFetch = DateTime.now();
  cachedServerProfile = profile;
  await _persistServerProfile();
  await reconcileLocalUsername(newServerName: profile.name);
  return profile;
}

/// How stale the cached profile is allowed to get before the background sync
/// cycle refetches it.
const _profileRefetchInterval = Duration(minutes: 30);

DateTime? _lastProfileFetch;

/// Refetches the account profile, but at most every [_profileRefetchInterval].
///
/// The sync cycle piggybacks on this to notice a name/email/role change made
/// on another device -- nothing else ever refetches it. That only needs to
/// happen *eventually*, though, and doing it on every 45s tick meant a request
/// plus a SharedPreferences write roughly 1900 times a day per device to
/// re-learn a display name that almost never changes.
///
/// Anything that changes the profile deliberately (the account page, the admin
/// screens) still calls [selfHostedFetchProfile] directly and is unaffected.
Future<void> selfHostedFetchProfileIfStale() async {
  final last = _lastProfileFetch;
  if (last != null && DateTime.now().difference(last) < _profileRefetchInterval) {
    return;
  }
  await selfHostedFetchProfile();
}

/// Forces the next [selfHostedFetchProfileIfStale] to actually go to the
/// server. Called on sign-out so a different account signing in on this device
/// can't be served the previous one's cached profile.
void resetProfileFetchThrottle() {
  _lastProfileFetch = null;
}

Future<ServerCallResult> selfHostedUpdateProfile({String? name, String? email}) async {
  final previousName = cachedServerProfile?.name;
  final (result, profile) =
      await _guarded((client) => client.patchMe(name: name, email: email));
  if (result != ServerCallResult.ok || profile == null) return result;
  cachedServerProfile = profile;
  await _persistServerProfile();
  await updateSettings("currentUserEmail", profile.email, updateGlobalState: false);
  await reconcileLocalUsername(
      previousServerName: previousName, newServerName: profile.name);
  return ServerCallResult.ok;
}

Future<ServerCallResult> selfHostedChangePassword({
  required String currentPassword,
  required String newPassword,
}) async {
  final (result, rotated) = await _guarded((client) => client.postMyPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ));
  if (result != ServerCallResult.ok || rotated == null) return result;
  // The server revoked every session including ours; adopt the replacement it
  // issued, or this device would sign itself out by changing its own password.
  selfHostedSession
    ?..sessionToken = rotated.sessionToken
    ..expiresAt = rotated.expiresAt;
  await _persistSession();
  return ServerCallResult.ok;
}

Future<List<ServerUser>?> selfHostedListUsers() async {
  final (result, users) = await _guarded((client) => client.listUsers());
  return result == ServerCallResult.ok ? users : null;
}

Future<(ServerCallResult, CreatedUser?)> selfHostedCreateUser({
  required String email,
  required String name,
}) =>
    _guarded((client) => client.createUser(email: email, name: name));

Future<(ServerCallResult, String?)> selfHostedResetUserPassword(int userId) =>
    _guarded((client) => client.resetUserPassword(userId));

Future<ServerCallResult> selfHostedDeleteUser(int userId) async {
  final (result, _) = await _guarded((client) => client.deleteUser(userId));
  return result;
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
