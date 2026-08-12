import 'dart:convert';

import 'package:test/test.dart';

import 'test_api.dart';

/// The Stage 2 row-level change feed: `/sync/push`, `/sync/pull`,
/// `/sync/reset`.
///
/// This had no test coverage at all until the dataset re-keying rewrote every
/// statement in it. The contracts asserted here are the ones that are easy to
/// break silently -- a feed that loses a change, or resurrects a deleted one,
/// still returns 200 to everybody involved.
void main() {
  late TestApi api;
  setUp(() => api = TestApi.create());
  tearDown(() => api.dispose());

  Future<Map<String, dynamic>> pull(String token,
      {int since = 0, int? limit}) async {
    final query = 'since=$since${limit == null ? '' : '&limit=$limit'}';
    return api.json(await api.send('GET', '/sync/pull?$query', token: token));
  }

  group('push and pull', () {
    test('a pushed row comes back to a peer', () async {
      final token = await api.setupAdmin();

      final pushed = await api.json(await api.push(token,
          pk: 'w1', modifiedAt: 5000, payload: {'name': 'Cash'}));
      expect(pushed['conflictCount'], 0);

      final feed = await pull(token);
      final change = (feed['changes'] as List).single as Map<String, dynamic>;
      expect(change['table'], 'wallets');
      expect(change['pk'], 'w1');
      expect(change['deleted'], isFalse);
      expect(change['modifiedAt'], 5000);
      expect(change['payload'], {'name': 'Cash'});
      expect(feed['hasMore'], isFalse);
      expect(feed['nextCursor'], change['seq']);
    });

    test('an empty pull leaves the cursor where it was', () async {
      final token = await api.setupAdmin();
      await api.push(token, pk: 'w1');
      final first = await pull(token);
      final cursor = first['nextCursor'] as int;

      final second = await pull(token, since: cursor);

      expect(second['changes'], isEmpty);
      expect(second['nextCursor'], cursor,
          reason: 'a cursor that moved on an empty pull would skip the next '
              'change instead of returning it');
    });

    test('pages, and reports whether more is waiting', () async {
      final token = await api.setupAdmin();
      for (var i = 0; i < 5; i++) {
        await api.push(token, pk: 'w$i', modifiedAt: 1000 + i);
      }

      final firstPage = await pull(token, limit: 2);
      expect((firstPage['changes'] as List).length, 2);
      expect(firstPage['hasMore'], isTrue);

      final rest = await pull(token, since: firstPage['nextCursor'] as int);
      expect((rest['changes'] as List).length, 3);
      expect(rest['hasMore'], isFalse);
    });

    test('a newer edit supersedes the row rather than appending to it', () async {
      final token = await api.setupAdmin();
      await api.push(token, pk: 'w1', modifiedAt: 1000, payload: {'name': 'Old'});
      await api.push(token, pk: 'w1', modifiedAt: 2000, payload: {'name': 'New'});

      final changes = await api.pullAll(token);

      // One row per record, not per change -- what keeps the feed bounded by
      // data size rather than by sync history.
      expect(changes.length, 1);
      expect(changes.single['payload'], {'name': 'New'});
    });

    test('an older edit loses and is reported as a conflict', () async {
      final token = await api.setupAdmin();
      await api.push(token, pk: 'w1', modifiedAt: 2000, payload: {'name': 'New'});

      final stale = await api.json(await api.push(token,
          pk: 'w1', modifiedAt: 1000, payload: {'name': 'Old'}));

      expect(stale['conflictCount'], 1);
      expect((await api.pullAll(token)).single['payload'], {'name': 'New'},
          reason: 'the accepted edit must survive a late arrival');
    });

    test('re-pushing an identical row is a silent no-op', () async {
      final token = await api.setupAdmin();
      await api.push(token, pk: 'w1', modifiedAt: 1000, payload: {'name': 'Cash'});

      // Devices re-scan by timestamp and routinely re-send rows the server
      // already has; an echo of a row just pulled from a peer looks the same.
      // Counting these as conflicts would make the number meaningless.
      final echo = await api.json(await api.push(token,
          pk: 'w1', modifiedAt: 1000, payload: {'name': 'Cash'}));

      expect(echo['conflictCount'], 0);
      expect((await api.pullAll(token)).single['seq'], 1,
          reason: 'a no-op must not burn a sequence number and wake the fleet');
    });

    test('a same-millisecond edit with different content is a real conflict', () async {
      final token = await api.setupAdmin();
      await api.push(token, pk: 'w1', modifiedAt: 1000, payload: {'name': 'A'});

      final collision = await api.json(await api.push(token,
          pk: 'w1', modifiedAt: 1000, payload: {'name': 'B'}));

      expect(collision['conflictCount'], 1);
    });

    test('a future timestamp is clamped to server time', () async {
      final token = await api.setupAdmin();
      final farFuture =
          DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch;

      await api.push(token, pk: 'w1', modifiedAt: farFuture);

      final stored = (await api.pullAll(token)).single['modifiedAt'] as int;
      expect(stored, lessThan(farFuture),
          reason: 'a fast client clock would otherwise win every conflict '
              'against every other device, forever');
    });

    test('the sync_state row is created on first use', () async {
      final token = await api.setupAdmin();
      final me = await api.json(await api.send('GET', '/auth/me', token: token));

      expect(
          api.db.select('SELECT COUNT(*) AS c FROM sync_state WHERE dataset_id = ?',
              [me['datasetId']]).first['c'],
          0);
      await api.push(token);
      expect(
          api.db.select('SELECT next_seq FROM sync_state WHERE dataset_id = ?',
              [me['datasetId']]).first['next_seq'],
          2);
    });

    test('one dataset\'s feed is invisible to another', () async {
      final adminToken = await api.setupAdmin();
      final isolated = await api.addMember(adminToken);

      await api.push(adminToken, pk: 'w1');
      await api.push(isolated.token, pk: 'w2');

      expect((await api.pullAll(adminToken)).single['pk'], 'w1');
      expect((await api.pullAll(isolated.token)).single['pk'], 'w2');
    });
  });

  group('reset', () {
    test('parks the retention floor above every existing cursor', () async {
      final token = await api.setupAdmin();
      await api.push(token, pk: 'w1');
      final beforeReset = (await pull(token))['nextCursor'] as int;

      final reset =
          await api.json(await api.send('POST', '/sync/reset', token: token));

      expect(reset['minRetainedSeq'], greaterThan(beforeReset));
      expect(api.db.select('SELECT COUNT(*) AS c FROM sync_records').first['c'], 0);
    });

    test('a peer holding a stale cursor is told to rebootstrap', () async {
      final token = await api.setupAdmin();
      await api.push(token, pk: 'w1');
      final staleCursor = (await pull(token))['nextCursor'] as int;

      final reset =
          await api.json(await api.send('POST', '/sync/reset', token: token));

      final response =
          await api.send('GET', '/sync/pull?since=$staleCursor', token: token);
      expect(response.statusCode, 409);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'rebootstrap');
      expect(body['minRetainedSeq'], reset['minRetainedSeq']);
    });

    test('the resetting device can see its own re-upload', () async {
      final token = await api.setupAdmin();
      await api.push(token, pk: 'w1');
      final reset =
          await api.json(await api.send('POST', '/sync/reset', token: token));
      final floor = reset['minRetainedSeq'] as int;

      // The reset deliberately burns one sequence number as a barrier: without
      // that gap the device that just reset would re-upload at exactly
      // minRetainedSeq and then be unable to pull its own rows back, because a
      // pull from the floor asks for seq strictly greater than it.
      await api.push(token, pk: 'w1', modifiedAt: 9000);

      final feed = await pull(token, since: floor);
      expect((feed['changes'] as List).single['pk'], 'w1');
    });

    test('resetting one dataset does not disturb another', () async {
      final adminToken = await api.setupAdmin();
      final isolated = await api.addMember(adminToken);
      await api.push(adminToken, pk: 'w1');
      await api.push(isolated.token, pk: 'w2');

      await api.send('POST', '/sync/reset', token: adminToken);

      // The reset's retention floor is per-dataset too: it rebootstraps the
      // resetter's own devices and nobody else's.
      expect((await api.send('GET', '/sync/pull?since=0', token: adminToken))
          .statusCode, 409);
      expect((await api.pullAll(isolated.token)).single['pk'], 'w2',
          reason: 'another dataset keeps both its rows and its cursor');
    });
  });
}
