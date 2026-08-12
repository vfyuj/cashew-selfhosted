import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../auth/auth_middleware.dart';
import '../storage.dart';
import 'sync_hub.dart';

/// Assigns the next per-dataset sequence number, creating the dataset's
/// sync_state row on first use. One sequence space is shared by every member
/// of a household, which is what lets their devices follow one another's
/// changes with a single cursor. Must be called inside the same transaction as the
/// write it numbers -- sqlite3's synchronous API plus Dart's single-threaded
/// event loop is what makes this race-free (see specs/04-stage-2-instant-sync.md).
int _nextSeq(Database db, int datasetId) {
  db.execute(
    'INSERT OR IGNORE INTO sync_state (dataset_id, next_seq, min_retained_seq) VALUES (?, 1, 0)',
    [datasetId],
  );
  final seq = db.select('SELECT next_seq FROM sync_state WHERE dataset_id = ?', [datasetId]).first['next_seq'] as int;
  db.execute('UPDATE sync_state SET next_seq = ? WHERE dataset_id = ?', [seq + 1, datasetId]);
  return seq;
}

/// Stage 1's snapshot-diff transport (still mounted for backward
/// compatibility -- see the Migration section of specs/04-stage-2-instant-sync.md)
/// plus Stage 2's row-level change feed (`/push`, `/pull`). Both share this
/// router because both are scoped by the same authenticated-user middleware.
Router buildSyncRouter(String dataDir, Database db) {
  final router = Router();

  // Scoped by dataset, not by user: the members of a household sync one set of
  // snapshots between all of their devices. Filenames stay collision-free in
  // the shared directory because clientID carries a millisecond suffix.
  UserFileStore storeFor(Request request) =>
      UserFileStore(dataDir, 'sync', currentUser(request).datasetId);

  router.get('/files', (Request request) {
    final files = storeFor(request).list();
    final json = files
        .map((f) => {
              'deviceId': p.basenameWithoutExtension(f.filename),
              ...f.toJson(),
            })
        .toList();
    return Response.ok(jsonEncode(json), headers: {'content-type': 'application/json'});
  });

  router.put('/files/<filename>', (Request request, String filename) async {
    final bytes = await request.read().expand((chunk) => chunk).toList();
    try {
      storeFor(request).write(filename, bytes);
      return Response.ok('');
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  router.get('/files/<filename>', (Request request, String filename) {
    try {
      final bytes = storeFor(request).read(filename);
      if (bytes == null) return Response.notFound('not found');
      return Response.ok(bytes, headers: {'content-type': 'application/octet-stream'});
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  router.delete('/files/<filename>', (Request request, String filename) {
    try {
      storeFor(request).delete(filename);
      return Response.ok('');
    } on InvalidFilenameException {
      return Response(400, body: 'invalid filename');
    }
  });

  // Stage 2 row-level change feed. See specs/04-stage-2-instant-sync.md.
  router.post('/push', (Request request) async {
    final datasetId = currentUser(request).datasetId;
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final deviceId = (body['deviceId'] as String?) ?? '';
    final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
    final serverTime = DateTime.now();
    final maxAllowed = serverTime.add(const Duration(minutes: 2)).millisecondsSinceEpoch;

    int conflictCount = 0;
    // Counts changes that actually altered stored state. A push where every
    // change was a no-op (the common case -- devices re-scan by timestamp and
    // routinely re-send rows the server already has) must NOT wake every other
    // device: doing so let one device stuck in a failing cycle re-push
    // constantly and drive the whole fleet into a permanent ~1Hz sync storm.
    int appliedCount = 0;

    db.execute('BEGIN');
    try {
      for (final change in changes) {
        final table = change['table'] as String;
        final pk = change['pk'] as String;
        final deleted = change['deleted'] as bool? ?? false;
        // Clamp a clock-skewed future timestamp down to server time so a
        // fast client clock can't win every future conflict forever.
        final rawModifiedAt = change['modifiedAt'] as int;
        final modifiedAt = rawModifiedAt > maxAllowed ? serverTime.millisecondsSinceEpoch : rawModifiedAt;
        final payloadJson = deleted ? null : jsonEncode(change['payload']);

        final existing = db.select(
          'SELECT modified_at, payload FROM sync_records WHERE dataset_id = ? AND table_name = ? AND pk = ?',
          [datasetId, table, pk],
        );

        if (existing.isEmpty) {
          final seq = _nextSeq(db, datasetId);
          db.execute(
            'INSERT INTO sync_records (dataset_id, table_name, pk, seq, deleted, modified_at, device_id, payload) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [datasetId, table, pk, seq, deleted ? 1 : 0, modifiedAt, deviceId, payloadJson],
          );
          appliedCount++;
          continue;
        }

        final storedModifiedAt = existing.first['modified_at'] as int;
        final storedPayload = existing.first['payload'] as String?;

        if (modifiedAt > storedModifiedAt) {
          final seq = _nextSeq(db, datasetId);
          db.execute(
            'UPDATE sync_records SET seq = ?, deleted = ?, modified_at = ?, device_id = ?, payload = ? '
            'WHERE dataset_id = ? AND table_name = ? AND pk = ?',
            [seq, deleted ? 1 : 0, modifiedAt, deviceId, payloadJson, datasetId, table, pk],
          );
          appliedCount++;
        } else if (modifiedAt == storedModifiedAt) {
          // Same instant as what's stored: either a retry of an already-applied
          // push (lost ack) or an echo of a row this device just pulled from a
          // peer -- in both cases the content matches, so it's a safe no-op.
          // Only a genuine same-millisecond collision between two different
          // edits (vanishingly rare) has different content, and that's a real
          // conflict worth surfacing.
          if (payloadJson != storedPayload) conflictCount++;
        } else {
          // Older than what's already stored -- a real conflict: this edit
          // loses to one that was already accepted from another device.
          conflictCount++;
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }

    if (appliedCount > 0) syncHub.notify(datasetId);

    return Response.ok(
      jsonEncode({'serverTime': serverTime.millisecondsSinceEpoch, 'conflictCount': conflictCount}),
      headers: {'content-type': 'application/json'},
    );
  });

  router.get('/pull', (Request request) {
    final datasetId = currentUser(request).datasetId;
    final since = int.tryParse(request.url.queryParameters['since'] ?? '0') ?? 0;
    final limitParam = int.tryParse(request.url.queryParameters['limit'] ?? '500') ?? 500;
    final limit = limitParam.clamp(1, 2000);

    final stateRows = db.select('SELECT min_retained_seq FROM sync_state WHERE dataset_id = ?', [datasetId]);
    final minRetained = stateRows.isEmpty ? 0 : stateRows.first['min_retained_seq'] as int;
    if (since < minRetained) {
      return Response(
        409,
        body: jsonEncode({'error': 'rebootstrap', 'minRetainedSeq': minRetained}),
        headers: {'content-type': 'application/json'},
      );
    }

    final rows = db.select(
      'SELECT seq, table_name, pk, deleted, modified_at, device_id, payload FROM sync_records '
      'WHERE dataset_id = ? AND seq > ? ORDER BY seq LIMIT ?',
      [datasetId, since, limit + 1],
    );
    final hasMore = rows.length > limit;
    final page = hasMore ? rows.take(limit) : rows;
    final changes = page
        .map((r) => {
              'seq': r['seq'],
              'table': r['table_name'],
              'pk': r['pk'],
              'deleted': (r['deleted'] as int) == 1,
              'modifiedAt': r['modified_at'],
              'deviceId': r['device_id'],
              'payload': r['payload'] == null ? null : jsonDecode(r['payload'] as String),
            })
        .toList();
    final nextCursor = changes.isEmpty ? since : changes.last['seq'] as int;

    return Response.ok(
      jsonEncode({
        'changes': changes,
        'nextCursor': nextCursor,
        'hasMore': hasMore,
        'serverTime': DateTime.now().millisecondsSinceEpoch,
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // Reset Sync -- drops the change feed so the next device to sync becomes the
  // new baseline. Stored backups and every device's local database are
  // untouched; this only clears what the server knows. Mirrors upstream
  // Cashew's button of the same name, which exists precisely because a feed
  // can end up in a state no client can make progress against.
  router.post('/reset', (Request request) {
    final datasetId = currentUser(request).datasetId;

    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM sync_records WHERE dataset_id = ?', [datasetId]);
      db.execute(
        'INSERT OR IGNORE INTO sync_state (dataset_id, next_seq, min_retained_seq) VALUES (?, 1, 0)',
        [datasetId],
      );
      // next_seq deliberately keeps climbing, and min_retained_seq parks on
      // top of it. Every *other* device is holding a cursor below that, so its
      // next pull gets a 409 and rebootstraps -- that 409 is the only way a
      // peer can find out its cursor now means nothing, and it matters for
      // reading *and* writing: after a reset every device must re-push, not
      // just re-read. Rewinding next_seq to 1 instead would strand those peers
      // silently, their stored cursor sitting above every newly issued seq.
      //
      // One seq is burned as the reset barrier: min_retained_seq lands on it
      // and the next record issued sits strictly above it. Without that gap
      // the first post-reset record would be assigned exactly min_retained_seq
      // -- and since the resetting device resumes *at* that cursor and pull is
      // `seq > since`, its own re-upload would be invisible to it.
      db.execute(
        'UPDATE sync_state SET min_retained_seq = next_seq, next_seq = next_seq + 1 '
        'WHERE dataset_id = ?',
        [datasetId],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }

    final minRetained = db.select(
        'SELECT min_retained_seq FROM sync_state WHERE dataset_id = ?',
        [datasetId]).first['min_retained_seq'] as int;

    // Wake peers so they discover the reset now rather than up to 45s later.
    syncHub.notify(datasetId);

    return Response.ok(
      jsonEncode({'minRetainedSeq': minRetained}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}
