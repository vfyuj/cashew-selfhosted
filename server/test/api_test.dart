import 'dart:convert';
import 'dart:io';

import 'package:server/src/api.dart';
import 'package:server/src/web_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_api.dart';

void main() {
  late TestApi api;
  setUp(() => api = TestApi.create());
  tearDown(() => api.dispose());

  group('health', () {
    test('reports liveness without authentication', () async {
      final response = await api.send('GET', '/health');
      expect(response.statusCode, 200);
      expect((await api.json(response))['status'], 'ok');
    });

    test('omits the version when no web build is being served', () async {
      // API-only local dev: WEB_DIR is unset, so there is no version.json to
      // read and /health must still answer.
      expect((await api.json(await api.send('GET', '/health')))['version'],
          isNull);
    });

    test('reports the version of the web build it is serving', () async {
      final handler = buildApiRouter(api.authService, api.db, api.dataDir.path,
              appVersion: '1.0.0-beta.12')
          .call;
      final response = await handler(Request('GET', Uri.parse('http://localhost/health')));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(body['status'], 'ok');
      expect(body['version'], '1.0.0-beta.12',
          reason: 'this is the deploy smoke test in DEPLOYMENT.md');
    });

    test('readWebBuildVersion reads what flutter build web emits', () async {
      final webDir = Directory.systemTemp.createTempSync('cashew-web-test');
      addTearDown(() => webDir.deleteSync(recursive: true));

      expect(readWebBuildVersion(webDir.path), isNull,
          reason: 'no version.json yet');

      File('${webDir.path}/version.json').writeAsStringSync(jsonEncode({
        'app_name': 'cashew_selfhosted',
        'version': '1.0.0-beta.12',
        'build_number': '12',
      }));
      expect(readWebBuildVersion(webDir.path), '1.0.0-beta.12');

      File('${webDir.path}/version.json').writeAsStringSync('not json');
      expect(readWebBuildVersion(webDir.path), isNull,
          reason: 'a malformed build must not stop the server from starting');
    });
  });

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

  group('household sharing', () {
    Future<Response> putFile(String path, String token, List<int> bytes) async =>
        await api.handler(Request('PUT', Uri.parse('http://localhost$path'),
            body: bytes, headers: {'authorization': 'Bearer $token'}));

    test('an account created with shareHousehold joins the creator\'s dataset', () async {
      final adminToken = await api.setupAdmin();
      final shared = await api.addMember(adminToken, shareHousehold: true);
      final isolated = await api.addMember(adminToken,
          email: 'other@example.com', shareHousehold: false);

      final me = await api.json(await api.send('GET', '/auth/me', token: adminToken));
      expect(shared.datasetId, me['datasetId']);
      expect(isolated.datasetId, isNot(me['datasetId']));
      expect(me['householdSize'], 2, reason: 'the admin plus the shared member');
    });

    test('a shared member sees the household feed, an isolated one does not', () async {
      final adminToken = await api.setupAdmin();
      final shared = await api.addMember(adminToken, shareHousehold: true);
      final isolated = await api.addMember(adminToken,
          email: 'other@example.com', shareHousehold: false);

      expect((await api.push(adminToken)).statusCode, 200);

      expect((await api.pullAll(shared.token)).single['pk'], 'w1');
      expect(await api.pullAll(isolated.token), isEmpty);
    });

    test('household members share one sequence space', () async {
      final adminToken = await api.setupAdmin();
      final shared = await api.addMember(adminToken, shareHousehold: true);

      await api.push(adminToken, pk: 'w1', modifiedAt: 1000, deviceId: 'a');
      await api.push(shared.token, pk: 'w2', modifiedAt: 2000, deviceId: 'b');

      final seen = await api.pullAll(adminToken);
      expect(seen.map((c) => c['pk']), ['w1', 'w2']);
      expect(seen.map((c) => c['seq']), [1, 2],
          reason: 'one monotonic feed, not two interleaved ones');
    });

    test('sync snapshots and attachments are shared, backups are not', () async {
      final adminToken = await api.setupAdmin();
      final shared = await api.addMember(adminToken, shareHousehold: true);

      await putFile('/sync/files/sync-phone-1.sqlite', adminToken, [1]);
      await putFile('/attachments/receipt.jpg', adminToken, [2]);
      await putFile('/backup/db-v46-phone.sqlite', adminToken, [3]);

      final syncList = jsonDecode(await (await api.send('GET', '/sync/files',
              token: shared.token))
          .readAsString()) as List;
      expect(syncList.single['filename'], 'sync-phone-1.sqlite');

      // Load-bearing: attachmentUrl() bakes this path into the transaction
      // note, and the note syncs. Scoped by user it would 404 for the other.
      expect(
          (await api.send('GET', '/attachments/receipt.jpg', token: shared.token))
              .statusCode,
          200);

      final backupList = jsonDecode(
              await (await api.send('GET', '/backup/list', token: shared.token))
                  .readAsString())
          as List;
      expect(backupList, isEmpty,
          reason: 'backups stay per-user on purpose -- backup filenames drop '
              'clientID\'s millisecond suffix, so two same-model phones in one '
              'household would overwrite each other, and retention prunes '
              'across the whole listing. Do not "fix" this for consistency.');
    });

    test('deleting one member leaves the household\'s data intact', () async {
      final adminToken = await api.setupAdmin();
      final shared = await api.addMember(adminToken, shareHousehold: true);
      await api.push(adminToken);
      await putFile('/sync/files/sync-phone-1.sqlite', adminToken, [1]);

      expect((await api.send('DELETE', '/admin/users/${shared.id}', token: adminToken))
          .statusCode, 200);

      expect((await api.pullAll(adminToken)).single['pk'], 'w1',
          reason: 'removing one account must not delete the household feed');
      expect(
          Directory('${api.dataDir.path}/sync/${shared.datasetId}').existsSync(), isTrue);
    });

    test('deleting the last member reaps the dataset and its files', () async {
      final adminToken = await api.setupAdmin();
      final isolated = await api.addMember(adminToken);
      await api.push(isolated.token);
      await putFile('/sync/files/sync-x.sqlite', isolated.token, [1]);
      await putFile('/attachments/r.jpg', isolated.token, [2]);
      await putFile('/backup/b.sqlite', isolated.token, [3]);

      await api.send('DELETE', '/admin/users/${isolated.id}', token: adminToken);

      // Dropping the datasets row is what cascades the feed away now that
      // sync_records no longer hangs off users.
      expect(
          api.db.select('SELECT COUNT(*) AS c FROM sync_records '
              'WHERE dataset_id = ?', [isolated.datasetId]).first['c'],
          0);
      expect(api.db.select('SELECT COUNT(*) AS c FROM datasets WHERE id = ?',
          [isolated.datasetId]).first['c'], 0);
      for (final ns in ['sync', 'attachments']) {
        expect(Directory('${api.dataDir.path}/$ns/${isolated.datasetId}').existsSync(),
            isFalse, reason: '$ns directory should be gone');
      }
      expect(Directory('${api.dataDir.path}/backup/${isolated.id}').existsSync(),
          isFalse);
    });

    test('the admin listing reports each account\'s dataset', () async {
      final adminToken = await api.setupAdmin();
      final shared = await api.addMember(adminToken, shareHousehold: true);
      final isolated =
          await api.addMember(adminToken, email: 'other@example.com');

      final body = await api.json(await api.send('GET', '/admin/users', token: adminToken));
      final users = (body['users'] as List).cast<Map<String, dynamic>>();
      final byId = {for (final u in users) u['id'] as int: u['datasetId'] as int};

      expect(byId[shared.id], byId[1], reason: 'shares the administrator\'s dataset');
      expect(byId[isolated.id], isNot(byId[1]));
    });

    test('a solo account is unaffected by any of this', () async {
      final adminToken = await api.setupAdmin();
      final me = await api.json(await api.send('GET', '/auth/me', token: adminToken));

      expect(me['householdSize'], 1);
      await api.push(adminToken);
      expect((await api.pullAll(adminToken)).single['pk'], 'w1');
    });
  });
}
