import 'dart:convert';
import 'dart:io';

import 'package:server/src/api.dart';
import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/database.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Drives the real router + middleware composition against an in-memory
/// database, so routing, auth gating and status codes are all exercised as
/// they are in production -- no port binding, no fixtures shared between tests.
class TestApi {
  final Database db;
  final AuthService authService;
  final Handler handler;
  final Directory dataDir;

  TestApi._(this.db, this.authService, this.handler, this.dataDir);

  /// Wraps a router that the caller composed themselves, for tests that need
  /// to inject something into buildApiRouter (the exchange-rate fetcher, say)
  /// while still using the helpers below.
  factory TestApi.forHandler(
          Database db, AuthService authService, Handler handler, Directory dataDir) =>
      TestApi._(db, authService, handler, dataDir);

  factory TestApi.create() {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys=ON;');
    migrate(db);
    final authService = AuthService(db);
    final dataDir = Directory.systemTemp.createTempSync('cashew-api-test');
    return TestApi._(
        db, authService, buildApiRouter(authService, db, dataDir.path).call, dataDir);
  }

  void dispose() {
    db.dispose();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  }

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    return await handler(Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
    ));
  }

  Future<Map<String, dynamic>> json(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  /// Completes first-run setup and returns the administrator's session token.
  Future<String> setupAdmin({
    String email = 'owner@example.com',
    String password = 'owner-password',
  }) async {
    final response = await send('POST', '/auth/setup',
        body: {'email': email, 'name': 'The Owner', 'password': password});
    // A shelf body can only be read once, so capture it before asserting on it.
    final raw = await response.readAsString();
    expect(response.statusCode, 200, reason: raw);
    return (jsonDecode(raw) as Map<String, dynamic>)['sessionToken'] as String;
  }

  /// Creates a non-admin account via the admin API and signs in as them.
  ///
  /// With [shareHousehold] the account joins the creating administrator's
  /// dataset and sees their data; without it the account is isolated, which is
  /// how every account behaved before datasets existed.
  Future<({int id, int datasetId, String token, String password})> addMember(
    String adminToken, {
    String email = 'spouse@example.com',
    bool shareHousehold = false,
  }) async {
    final created = await json(await send('POST', '/admin/users',
        body: {
          'email': email,
          'name': 'Member',
          if (shareHousehold) 'shareHousehold': true,
        },
        token: adminToken));
    final password = created['temporaryPassword'] as String;
    final user = created['user'] as Map<String, dynamic>;
    final login = await json(
        await send('POST', '/auth/login', body: {'email': email, 'password': password}));
    return (
      id: user['id'] as int,
      datasetId: user['datasetId'] as int,
      token: login['sessionToken'] as String,
      password: password,
    );
  }

  /// Pushes one row into the caller's change feed.
  Future<Response> push(
    String token, {
    String table = 'wallets',
    String pk = 'w1',
    int modifiedAt = 1000,
    String deviceId = 'device-a',
    Map<String, dynamic>? payload,
  }) =>
      send('POST', '/sync/push', token: token, body: {
        'deviceId': deviceId,
        'changes': [
          {
            'table': table,
            'pk': pk,
            'deleted': false,
            'modifiedAt': modifiedAt,
            'payload': payload ?? {'name': 'Cash'},
          }
        ],
      });

  /// Every change visible to [token] from the start of its feed.
  Future<List<Map<String, dynamic>>> pullAll(String token) async {
    final body = await json(await send('GET', '/sync/pull?since=0', token: token));
    return (body['changes'] as List).cast<Map<String, dynamic>>();
  }
}
