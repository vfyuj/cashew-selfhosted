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
  Future<({int id, String token, String password})> addMember(
    String adminToken, {
    String email = 'spouse@example.com',
  }) async {
    final created = await json(await send('POST', '/admin/users',
        body: {'email': email, 'name': 'Spouse'}, token: adminToken));
    final password = created['temporaryPassword'] as String;
    final id = (created['user'] as Map<String, dynamic>)['id'] as int;
    final login = await json(
        await send('POST', '/auth/login', body: {'email': email, 'password': password}));
    return (id: id, token: login['sessionToken'] as String, password: password);
  }
}

void main() {
  late TestApi api;
  setUp(() => api = TestApi.create());
  tearDown(() => api.dispose());

  group('first-run setup', () {
    test('a fresh instance reports that it needs setup', () async {
      final body = await api.json(await api.send('GET', '/auth/setup-state'));
      expect(body['needsSetup'], isTrue);
    });

    test('setup creates an administrator and returns a usable session', () async {
      final response = await api.send('POST', '/auth/setup',
          body: {'email': 'owner@example.com', 'name': 'The Owner', 'password': 'owner-password'});

      expect(response.statusCode, 200);
      final body = await api.json(response);
      expect(body['user']['isAdmin'], isTrue);
      expect(body['user']['name'], 'The Owner');
      expect(body['sessionToken'], isNotEmpty);

      final me = await api.json(
          await api.send('GET', '/auth/me', token: body['sessionToken'] as String));
      expect(me['email'], 'owner@example.com');
      expect(me['isAdmin'], isTrue);
    });

    test('setup closes permanently once a user exists', () async {
      await api.setupAdmin();

      expect((await api.json(await api.send('GET', '/auth/setup-state')))['needsSetup'], isFalse);

      final second = await api.send('POST', '/auth/setup',
          body: {'email': 'attacker@example.com', 'name': 'X', 'password': 'another-password'});
      expect(second.statusCode, 409);
      expect(api.authService.countUsers(), 1);
    });

    test('setup rejects a password below the minimum length', () async {
      final response = await api.send('POST', '/auth/setup',
          body: {'email': 'owner@example.com', 'name': 'O', 'password': 'short'});
      expect(response.statusCode, 400);
      expect(api.authService.countUsers(), 0, reason: 'a rejected setup must not create an account');
    });
  });

  group('login', () {
    test('returns the profile alongside the session', () async {
      await api.setupAdmin();
      final body = await api.json(await api.send('POST', '/auth/login',
          body: {'email': 'owner@example.com', 'password': 'owner-password'}));
      expect(body['user']['isAdmin'], isTrue);
      expect(body['user']['name'], 'The Owner');
    });

    test('rejects a wrong password', () async {
      await api.setupAdmin();
      final response = await api.send('POST', '/auth/login',
          body: {'email': 'owner@example.com', 'password': 'wrong-password'});
      expect(response.statusCode, 401);
    });
  });

  /// Regression guard. An earlier change rewrote these handlers from a base
  /// that predated the UTC fix and silently reverted it in three places -- the
  /// kind of thing no other test would have caught, because every assertion
  /// still passed. Without the `Z`, the client's `.toLocal()` shifts the
  /// instant by the timezone offset.
  group('timestamps are serialized as UTC', () {
    void expectUtc(Object? value, String what) {
      expect(value, isA<String>(), reason: '$what should be a string');
      expect(value as String, endsWith('Z'),
          reason: '$what must be serialized with .toUtc() so it carries a Z');
      expect(DateTime.parse(value).isUtc, isTrue, reason: '$what must parse as UTC');
    }

    test('on setup, login, refresh and password change', () async {
      final setup = await api.json(await api.send('POST', '/auth/setup', body: {
        'email': 'owner@example.com',
        'name': 'The Owner',
        'password': 'owner-password',
      }));
      expectUtc(setup['expiresAt'], 'POST /auth/setup expiresAt');

      final login = await api.json(await api.send('POST', '/auth/login',
          body: {'email': 'owner@example.com', 'password': 'owner-password'}));
      expectUtc(login['expiresAt'], 'POST /auth/login expiresAt');

      final refreshed = await api.json(await api.send('POST', '/auth/refresh',
          body: {'sessionToken': login['sessionToken']}));
      expectUtc(refreshed['expiresAt'], 'POST /auth/refresh expiresAt');

      final changed = await api.json(await api.send(
        'POST',
        '/auth/me/password',
        body: {'currentPassword': 'owner-password', 'newPassword': 'a-new-password'},
        token: refreshed['sessionToken'] as String,
      ));
      expectUtc(changed['expiresAt'], 'POST /auth/me/password expiresAt');
    });

    test('on the sync file listing', () async {
      final token = await api.setupAdmin();
      await api.handler(Request(
        'PUT',
        Uri.parse('http://localhost/sync/files/sync-a.sqlite'),
        body: [1, 2, 3],
        headers: {'authorization': 'Bearer $token'},
      ));

      final files = jsonDecode(
          await (await api.send('GET', '/sync/files', token: token)).readAsString()) as List;
      expectUtc(files.single['modifiedTime'], 'GET /sync/files modifiedTime');
    });
  });

  group('profile', () {
    test('updates name and email', () async {
      final token = await api.setupAdmin();
      final response = await api.send('PATCH', '/auth/me',
          body: {'name': 'Renamed', 'email': 'new@example.com'}, token: token);

      expect(response.statusCode, 200);
      final body = await api.json(response);
      expect(body['name'], 'Renamed');
      expect(body['email'], 'new@example.com');
    });

    test('refuses an email already taken by someone else', () async {
      final token = await api.setupAdmin();
      await api.addMember(token);

      final response =
          await api.send('PATCH', '/auth/me', body: {'email': 'spouse@example.com'}, token: token);
      expect(response.statusCode, 409);
    });

    test('requires authentication', () async {
      await api.setupAdmin();
      expect((await api.send('GET', '/auth/me')).statusCode, 401);
    });
  });

  group('password change', () {
    test('signs other devices out but keeps the caller signed in', () async {
      final firstDevice = await api.setupAdmin();
      final secondDevice = (await api.json(await api.send('POST', '/auth/login',
          body: {'email': 'owner@example.com', 'password': 'owner-password'})))['sessionToken'];

      final response = await api.send('POST', '/auth/me/password',
          body: {'currentPassword': 'owner-password', 'newPassword': 'a-new-password'},
          token: firstDevice);
      expect(response.statusCode, 200);
      final rotated = (await api.json(response))['sessionToken'] as String;

      expect((await api.send('GET', '/auth/me', token: rotated)).statusCode, 200,
          reason: 'the device that changed the password keeps working');
      expect((await api.send('GET', '/auth/me', token: firstDevice)).statusCode, 401,
          reason: 'the old token is revoked even for the caller');
      expect((await api.send('GET', '/auth/me', token: secondDevice as String)).statusCode, 401,
          reason: 'other devices are signed out');

      expect(
          (await api.send('POST', '/auth/login',
                  body: {'email': 'owner@example.com', 'password': 'a-new-password'}))
              .statusCode,
          200);
    });

    test('rejects a wrong current password without changing anything', () async {
      final token = await api.setupAdmin();
      final response = await api.send('POST', '/auth/me/password',
          body: {'currentPassword': 'not-the-password', 'newPassword': 'a-new-password'},
          token: token);

      // 422, not 401: 401 is reserved for "your session is gone", so a client
      // can tell the two apart. See the handler for why.
      expect(response.statusCode, 422);
      expect((await api.send('GET', '/auth/me', token: token)).statusCode, 200,
          reason: 'a failed attempt must not revoke the session');
    });

    test('rejects a new password below the minimum length', () async {
      final token = await api.setupAdmin();
      final response = await api.send('POST', '/auth/me/password',
          body: {'currentPassword': 'owner-password', 'newPassword': 'short'}, token: token);
      expect(response.statusCode, 400);
    });
  });

  group('admin access control', () {
    test('a non-admin is refused every admin route', () async {
      final adminToken = await api.setupAdmin();
      final member = await api.addMember(adminToken);

      for (final (method, path) in [
        ('GET', '/admin/users'),
        ('POST', '/admin/users'),
        ('DELETE', '/admin/users/1'),
      ]) {
        final response = await api.send(method, path,
            body: method == 'POST' ? {'email': 'x@example.com'} : null, token: member.token);
        expect(response.statusCode, 403, reason: '$method $path should be admin-only');
      }
    });

    test('an unauthenticated request is refused before the admin check', () async {
      await api.setupAdmin();
      expect((await api.send('GET', '/admin/users')).statusCode, 401);
    });

    test('a promoted user gains access immediately', () async {
      final adminToken = await api.setupAdmin();
      final member = await api.addMember(adminToken);
      expect((await api.send('GET', '/admin/users', token: member.token)).statusCode, 403);

      await api.send('PATCH', '/admin/users/${member.id}',
          body: {'isAdmin': true}, token: adminToken);

      expect((await api.send('GET', '/admin/users', token: member.token)).statusCode, 200,
          reason: 'the role is re-read per request, not baked into the session');
    });
  });

  group('admin user management', () {
    test('creating a user returns a temporary password that actually works', () async {
      final adminToken = await api.setupAdmin();
      final response = await api.send('POST', '/admin/users',
          body: {'email': 'spouse@example.com', 'name': 'Spouse'}, token: adminToken);

      expect(response.statusCode, 201);
      final body = await api.json(response);
      expect(body['user']['isAdmin'], isFalse);
      expect(body['temporaryPassword'], isNotEmpty);

      final login = await api.send('POST', '/auth/login', body: {
        'email': 'spouse@example.com',
        'password': body['temporaryPassword'],
      });
      expect(login.statusCode, 200);
    });

    test('creating a duplicate email is refused', () async {
      final adminToken = await api.setupAdmin();
      await api.addMember(adminToken);
      final response = await api.send('POST', '/admin/users',
          body: {'email': 'spouse@example.com'}, token: adminToken);
      expect(response.statusCode, 409);
    });

    test('resetting a password revokes that user\'s sessions', () async {
      final adminToken = await api.setupAdmin();
      final member = await api.addMember(adminToken);
      expect((await api.send('GET', '/auth/me', token: member.token)).statusCode, 200);

      final response = await api
          .send('POST', '/admin/users/${member.id}/password', token: adminToken);
      expect(response.statusCode, 200);
      final newPassword = (await api.json(response))['temporaryPassword'] as String;

      expect((await api.send('GET', '/auth/me', token: member.token)).statusCode, 401);
      expect(
          (await api.send('POST', '/auth/login',
                  body: {'email': 'spouse@example.com', 'password': newPassword}))
              .statusCode,
          200);
    });

    test('deleting a user removes their stored sync and backup files', () async {
      final adminToken = await api.setupAdmin();
      final member = await api.addMember(adminToken);

      await api.handler(Request(
        'PUT',
        Uri.parse('http://localhost/sync/files/sync-device.sqlite'),
        body: [1, 2, 3],
        headers: {'authorization': 'Bearer ${member.token}'},
      ));
      final syncDir = Directory('${api.dataDir.path}/sync/${member.id}');
      expect(syncDir.existsSync(), isTrue, reason: 'precondition: the upload landed');

      expect((await api.send('DELETE', '/admin/users/${member.id}', token: adminToken)).statusCode,
          200);

      expect(syncDir.existsSync(), isFalse);
      expect(api.authService.listUsers().map((u) => u.email), ['owner@example.com']);
    });

    test('an admin cannot delete their own account', () async {
      final adminToken = await api.setupAdmin();
      final me = await api.json(await api.send('GET', '/auth/me', token: adminToken));

      final response =
          await api.send('DELETE', '/admin/users/${me['id']}', token: adminToken);
      expect(response.statusCode, 409);
      expect(api.authService.countUsers(), 1);
    });

    test('the last administrator cannot be demoted', () async {
      final adminToken = await api.setupAdmin();
      final me = await api.json(await api.send('GET', '/auth/me', token: adminToken));

      final response = await api.send('PATCH', '/admin/users/${me['id']}',
          body: {'isAdmin': false}, token: adminToken);
      expect(response.statusCode, 409);
      expect(api.authService.countAdmins(), 1);
    });

    test('the last administrator cannot be deleted by another admin', () async {
      final adminToken = await api.setupAdmin();
      final member = await api.addMember(adminToken);
      await api.send('PATCH', '/admin/users/${member.id}',
          body: {'isAdmin': true}, token: adminToken);
      final owner = await api.json(await api.send('GET', '/auth/me', token: adminToken));

      // Two admins: deleting one is allowed.
      expect(
          (await api.send('DELETE', '/admin/users/${owner['id']}', token: member.token)).statusCode,
          200);
      // One admin left: they cannot be removed, leaving the instance headless.
      final meAsLastAdmin = await api.json(await api.send('GET', '/auth/me', token: member.token));
      final selfDelete =
          await api.send('DELETE', '/admin/users/${meAsLastAdmin['id']}', token: member.token);
      expect(selfDelete.statusCode, 409);
      expect(api.authService.countAdmins(), 1);
    });

    test('a missing user id is a 404, not a crash', () async {
      final adminToken = await api.setupAdmin();
      expect((await api.send('DELETE', '/admin/users/9999', token: adminToken)).statusCode, 404);
      expect(
          (await api.send('POST', '/admin/users/9999/password', token: adminToken)).statusCode, 404);
    });
  });

  group('existing sync and backup behaviour is unchanged', () {
    test('sync files stay scoped to the authenticated user', () async {
      final adminToken = await api.setupAdmin();
      final member = await api.addMember(adminToken);

      await api.handler(Request(
        'PUT',
        Uri.parse('http://localhost/sync/files/sync-a.sqlite'),
        body: [9, 9, 9],
        headers: {'authorization': 'Bearer $adminToken'},
      ));

      // GET /sync/files returns a bare JSON array, matching what the Drive
      // files.list call it replaced returned.
      final ownerList = jsonDecode(
          await (await api.send('GET', '/sync/files', token: adminToken)).readAsString()) as List;
      final memberList = jsonDecode(
          await (await api.send('GET', '/sync/files', token: member.token)).readAsString()) as List;
      expect(ownerList.length, 1);
      expect(ownerList.single['filename'], 'sync-a.sqlite');
      expect(memberList, isEmpty, reason: 'two accounts on one server remain isolated');
    });
  });
}
