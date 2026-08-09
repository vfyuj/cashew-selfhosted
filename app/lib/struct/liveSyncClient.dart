import 'dart:async';
import 'dart:convert';

import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/struct/syncClient.dart' show SyncLog;
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart'
    show errorSigningInDuringCloud;
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Stage 2 live sync -- see specs/04-stage-2-instant-sync.md.
///
/// Row-level push/pull against the server's change feed, replacing Stage 1's
/// whole-database exchange as the *automatic* sync mechanism (timer, app
/// resume, websocket wake-up, on local change). The legacy sync-*.sqlite
/// mechanism in syncClient.dart is untouched and still reachable from the
/// "manage synced devices" screen for manual use -- this file only changes
/// what runs automatically in the background.
///
/// Deliberately does not use a persisted local outbox table. The Stage 1
/// query methods `getAllNewX(lastSynced)` already select "rows changed since
/// a given timestamp" straight from the source-of-truth Drift tables, so
/// those tables themselves serve as the outbox: nothing can be lost between
/// a local write and the next successful push, because there is nowhere
/// else the write could be. This also sidesteps needing SQLite triggers
/// (and their JSON1/web-WASM portability question) and a schema migration.

// ---------------------------------------------------------------------------
// Cursors
// ---------------------------------------------------------------------------

const _pushCursorPrefsKeyPrefix = "liveSyncPushCursorMs:";
const _pullCursorPrefsKeyPrefix = "liveSyncPullCursorSeq:";

/// Scopes cursors per server+account, same reasoning as the existing
/// per-account session storage: switching servers/accounts must not reuse
/// stale progress from a different one.
String? _cursorScopeKey() {
  final session = selfHostedSession;
  if (session == null) return null;
  return "${session.serverUrl}:${session.email}";
}

Future<DateTime> _getPushCursor() async {
  final scope = _cursorScopeKey();
  if (scope == null) return DateTime(0);
  final ms = sharedPreferences.getInt(_pushCursorPrefsKeyPrefix + scope);
  return ms == null ? DateTime(0) : DateTime.fromMillisecondsSinceEpoch(ms);
}

Future<void> _setPushCursor(DateTime cursor) async {
  final scope = _cursorScopeKey();
  if (scope == null) return;
  await sharedPreferences.setInt(
      _pushCursorPrefsKeyPrefix + scope, cursor.millisecondsSinceEpoch);
}

Future<int> _getPullCursor() async {
  final scope = _cursorScopeKey();
  if (scope == null) return 0;
  return sharedPreferences.getInt(_pullCursorPrefsKeyPrefix + scope) ?? 0;
}

Future<void> _setPullCursor(int cursor) async {
  final scope = _cursorScopeKey();
  if (scope == null) return;
  await sharedPreferences.setInt(_pullCursorPrefsKeyPrefix + scope, cursor);
}

// ---------------------------------------------------------------------------
// Local change collection (push side)
// ---------------------------------------------------------------------------

Map<String, dynamic> _asChange({
  required String table,
  required String pk,
  required DateTime? modifiedAt,
  required Map<String, dynamic>? payload,
  required bool deleted,
}) {
  return {
    'table': table,
    'pk': pk,
    'deleted': deleted,
    // A row with no dateTimeModified (pre-migration data) is treated as
    // "changed right now", mirroring the fallback processSyncLogs already
    // uses elsewhere -- safe because "now" always wins LWW against whatever
    // is already stored.
    'modifiedAt': (modifiedAt ?? DateTime.now()).millisecondsSinceEpoch,
    'payload': payload,
  };
}

Future<List<Map<String, dynamic>>> _collectLocalChanges(DateTime cursor) async {
  final changes = <Map<String, dynamic>>[];

  for (final row in await database.getAllNewWallets(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.TransactionWallet.name,
        pk: row.walletPk,
        modifiedAt: row.dateTimeModified,
        payload: row.toJson(),
        deleted: false));
  }
  for (final row in await database.getAllNewCategories(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.TransactionCategory.name,
        pk: row.categoryPk,
        modifiedAt: row.dateTimeModified,
        payload: row.toJson(),
        deleted: false));
  }
  for (final row in await database.getAllNewBudgets(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.Budget.name,
        pk: row.budgetPk,
        modifiedAt: row.dateTimeModified,
        payload: row.toJson(),
        deleted: false));
  }
  for (final row in await database.getAllNewCategoryBudgetLimits(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.CategoryBudgetLimit.name,
        pk: row.categoryLimitPk,
        modifiedAt: row.dateTimeModified,
        payload: row.toJson(),
        deleted: false));
  }
  for (final row in await database.getAllNewTransactions(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.Transaction.name,
        pk: row.transactionPk,
        modifiedAt: row.dateTimeModified,
        payload: row.toJson(),
        deleted: false));
  }
  for (final row in await database.getAllNewAssociatedTitles(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.TransactionAssociatedTitle.name,
        pk: row.associatedTitlePk,
        modifiedAt: row.dateTimeModified,
        payload: row.toJson(),
        deleted: false));
  }
  for (final row in await database.getAllNewScannerTemplates(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.ScannerTemplate.name,
        pk: row.scannerTemplatePk,
        modifiedAt: row.dateTimeModified,
        payload: row.toJson(),
        deleted: false));
  }
  for (final row in await database.getAllNewObjectives(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.Objective.name,
        pk: row.objectivePk,
        modifiedAt: row.dateTimeModified,
        payload: row.toJson(),
        deleted: false));
  }
  for (final row in await database.getAllNewDeleteLogs(cursor)) {
    changes.add(_asChange(
        table: row.type.name,
        pk: row.entryPk,
        modifiedAt: row.dateTimeModified,
        payload: null,
        deleted: true));
  }

  return changes;
}

// ---------------------------------------------------------------------------
// Applying pulled changes (pull side) -- reuses the existing, tested
// SyncLog/processSyncLogs merge. Only the input to that merge is new.
// ---------------------------------------------------------------------------

SyncLog? _syncLogFromChange(Map<String, dynamic> change) {
  final table = change['table'] as String;
  final pk = change['pk'] as String;
  final deleted = change['deleted'] as bool;
  final modifiedAt = DateTime.fromMillisecondsSinceEpoch(change['modifiedAt'] as int);

  if (deleted) {
    DeleteLogType? deleteLogType;
    try {
      deleteLogType = DeleteLogType.values.byName(table);
    } catch (_) {
      return null; // unknown table name (future server version) -- ignore, don't crash
    }
    return SyncLog(
        deleteLogType: deleteLogType, pk: pk, transactionDateTime: modifiedAt);
  }

  UpdateLogType updateLogType;
  try {
    updateLogType = UpdateLogType.values.byName(table);
  } catch (_) {
    return null;
  }

  final payload = change['payload'] as Map<String, dynamic>;
  dynamic itemToUpdate;
  switch (updateLogType) {
    case UpdateLogType.TransactionWallet:
      itemToUpdate = TransactionWallet.fromJson(payload);
      break;
    case UpdateLogType.TransactionCategory:
      itemToUpdate = TransactionCategory.fromJson(payload);
      break;
    case UpdateLogType.Budget:
      itemToUpdate = Budget.fromJson(payload);
      break;
    case UpdateLogType.CategoryBudgetLimit:
      itemToUpdate = CategoryBudgetLimit.fromJson(payload);
      break;
    case UpdateLogType.Transaction:
      itemToUpdate = Transaction.fromJson(payload);
      break;
    case UpdateLogType.TransactionAssociatedTitle:
      itemToUpdate = TransactionAssociatedTitle.fromJson(payload);
      break;
    case UpdateLogType.ScannerTemplate:
      itemToUpdate = ScannerTemplate.fromJson(payload);
      break;
    case UpdateLogType.Objective:
      itemToUpdate = Objective.fromJson(payload);
      break;
    case UpdateLogType.Unused:
      return null;
  }

  return SyncLog(
      updateLogType: updateLogType,
      pk: pk,
      itemToUpdate: itemToUpdate,
      transactionDateTime: modifiedAt);
}

// ---------------------------------------------------------------------------
// The cycle
// ---------------------------------------------------------------------------

bool _liveSyncCycleRunning = false;

/// Bumped by [resetLiveSync]. A cycle that started before a reset holds
/// cursors describing the old feed, and writing them back afterwards would
/// silently undo the reset -- so each cycle checks the generation it started
/// in before persisting anything.
int _liveSyncGeneration = 0;

/// Runs one push-then-pull round. Safe to call as often as you like --
/// guarded against overlap, and every guard mirrors the local-first
/// invariant's "never block, never surface a network error the user has to
/// dismiss" (specs/01-local-first-invariant.md): failures are logged and
/// retried on the next trigger, never thrown at the caller.
Future<void> runLiveSyncCycle() async {
  if (appStateSettings["hasSignedIn"] != true) return;
  if (appStateSettings["backupSync"] == false) return;
  if (errorSigningInDuringCloud == true) return;
  if (selfHostedSession == null) return;
  if (_liveSyncCycleRunning) return;
  _liveSyncCycleRunning = true;

  try {
    await selfHostedRefresh(); // silent, non-blocking -- see specs/01-local-first-invariant.md
    final session = selfHostedSession;
    if (session == null) return;
    final client = SelfHostedClient(session);

    // Unawaited: a name/email/role change made on another device is only
    // ever reflected here via cachedServerProfile, and nothing else refetches
    // it periodically. Piggybacking on this cycle (which already runs every
    // 45s, on local changes, and on websocket wake-ups) is what makes those
    // changes eventually show up on this device without the user having to
    // do anything -- not instantly, but never "not at all."
    selfHostedFetchProfile();

    // Captured before push/pull so the cursor bump below can never advance
    // past "the moment this cycle started" -- see the race analysis in
    // specs/04-stage-2-instant-sync.md. Any local edit made *during* this
    // cycle is guaranteed to have a timestamp >= cycleStartTime, so it can
    // never be skipped by the clamp.
    final cycleStartTime = DateTime.now();
    final generation = _liveSyncGeneration;
    final pushCursor = await _getPushCursor();

    final localChanges = await _collectLocalChanges(pushCursor);
    var pushOk = true;
    var conflictCount = 0;

    for (var i = 0; i < localChanges.length; i += 200) {
      final end = (i + 200 < localChanges.length) ? i + 200 : localChanges.length;
      try {
        final result = await client.pushSyncChanges(
          deviceId: clientID,
          changes: localChanges.sublist(i, end),
        );
        conflictCount += result.conflictCount;
      } catch (e) {
        print("Live sync push failed: $e");
        pushOk = false;
        break;
      }
    }

    // A failed push deliberately does *not* skip the pull. Changes arriving
    // from other devices are independent of whether this device's own changes
    // got out, and coupling them meant a single unsendable local row stopped
    // this device receiving anything at all, permanently. The push cursor
    // stays untouched in that case (see below), so the failed batch is still
    // retried in full next cycle.

    var pullCursor = await _getPullCursor();
    final logsToApply = <SyncLog>[];
    DateTime? pulledMax;
    var skippedChanges = 0;
    var hasMore = true;
    while (hasMore) {
      final SyncPullResult result;
      try {
        result = await client.pullSyncChanges(since: pullCursor);
      } on SyncRebootstrapRequiredException catch (e) {
        // Someone ran Reset Sync. This device's cursors describe a feed that
        // no longer exists, so drop them: resume reading at the feed's new
        // start, and rewind the push cursor to 0 so the whole local database
        // is re-uploaded on the next cycle. Purely local bookkeeping -- no
        // data is deleted here.
        print("Live sync: server feed was reset, rebootstrapping from seq ${e.minRetainedSeq}");
        await _setPullCursor(e.minRetainedSeq);
        await _setPushCursor(DateTime(0));
        return;
      } catch (e) {
        print("Live sync pull failed: $e");
        break; // keep whatever was applied so far; pull cursor already reflects it
      }
      for (final change in result.changes) {
        // Per-change, deliberately: a single unreadable row must never stop
        // the whole feed. It used to -- the throw escaped the loop before the
        // cursor was persisted, so every later change was unreachable and
        // sync was permanently wedged for that device (and, because a stuck
        // cycle re-pushes everything and re-wakes every peer, it degenerated
        // into a push storm). Skipping loses at most that one row; not
        // skipping loses everything after it, forever.
        try {
          final log = _syncLogFromChange(change);
          if (log != null) logsToApply.add(log);
        } catch (e) {
          skippedChanges++;
          print("Live sync: skipping unreadable change "
              "${change['table']}/${change['pk']} (seq ${change['seq']}): $e");
        }
        final modifiedAt = DateTime.fromMillisecondsSinceEpoch(change['modifiedAt'] as int);
        if (pulledMax == null || modifiedAt.isAfter(pulledMax)) pulledMax = modifiedAt;
      }
      pullCursor = result.nextCursor;
      hasMore = result.hasMore;
      if (generation != _liveSyncGeneration) return; // reset mid-cycle
      // Advance as we go, not just at the end: a crash mid-loop then only
      // re-fetches the last unconfirmed page, which is safe to reapply
      // (processSyncLogs is idempotent under LWW).
      await _setPullCursor(pullCursor);
    }

    if (logsToApply.isNotEmpty) {
      await database.processSyncLogs(logsToApply);
    }

    // Only advance the push cursor when the push actually succeeded. Moving it
    // on a failed push -- including via the echo-suppression bump below --
    // would skip local edits that never reached the server, losing them
    // permanently. Deferring echo suppression to the next successful cycle
    // costs at most one redundant re-push, which the server's
    // content-equality check no-ops.
    if (pushOk && generation == _liveSyncGeneration) {
      var newPushCursor =
          pushCursor.isBefore(cycleStartTime) ? cycleStartTime : pushCursor;

      final localPulledMax = pulledMax;
      if (localPulledMax != null) {
        // Clamped to cycleStartTime so a pulled row can never push the cursor
        // past a local edit made during this very cycle -- see the comment on
        // cycleStartTime above.
        final bump = localPulledMax.isAfter(cycleStartTime) ? cycleStartTime : localPulledMax;
        if (bump.isAfter(newPushCursor)) newPushCursor = bump;
      }

      await _setPushCursor(newPushCursor);
      appStateSettings["lastSynced"] = DateTime.now().toString();
    }

    if (skippedChanges > 0) {
      // Surfaced rather than only logged: skipped rows are the one case where
      // devices can silently disagree, and "Reset Sync" is the user-facing
      // remedy for exactly that.
      openSnackbar(SnackbarMessage(
        title: skippedChanges == 1
            ? "1 change from another device could not be read and was skipped"
            : "$skippedChanges changes from another device could not be read and were skipped",
        description: "Try Reset Sync if devices look out of step",
        icon: appStateSettings["outlinedIcons"] == true
            ? Icons.sync_problem_outlined
            : Icons.sync_problem_rounded,
      ));
    }

    if (conflictCount > 0) {
      openSnackbar(SnackbarMessage(
        title: conflictCount == 1
            ? "1 change was overwritten by a newer edit from another device"
            : "$conflictCount changes were overwritten by newer edits from another device",
        icon: appStateSettings["outlinedIcons"] == true
            ? Icons.sync_problem_outlined
            : Icons.sync_problem_rounded,
      ));
    }
  } catch (e) {
    print("Live sync cycle error: $e");
    if (e is SelfHostedUnauthenticatedException) {
      errorSigningInDuringCloud = true;
    }
  } finally {
    _liveSyncCycleRunning = false;
  }
}

/// User-facing "Reset Sync" (upstream Cashew has the same escape hatch, and
/// this fork needed one for the same reason: a change feed can reach a state
/// no client can make progress against, and there is otherwise no way out).
///
/// Clears the server's change feed, drops this device's cursors, then
/// re-uploads this device's data as the new baseline. **No local data and no
/// stored backup is deleted** -- on this device or any other. Other devices
/// find out via a `409 rebootstrap` on their next pull and re-upload their own
/// data too, so nothing is lost as long as each device eventually syncs.
Future<bool> resetLiveSync() async {
  final session = selfHostedSession;
  if (session == null) return false;
  try {
    final newStart = await SelfHostedClient(session).resetSyncDatabase();
    // Bump first: this invalidates any cycle already in flight, so it can't
    // write its now-meaningless cursors back over the ones set just below.
    _liveSyncGeneration++;
    await _setPullCursor(newStart);
    await _setPushCursor(DateTime(0)); // re-scan and re-upload everything local
    await runLiveSyncCycle();
    return true;
  } catch (e) {
    print("Reset sync failed: $e");
    return false;
  }
}

// ---------------------------------------------------------------------------
// Triggers: debounced local-change hook, periodic timer, websocket wake-up
// ---------------------------------------------------------------------------

Timer? _liveSyncDebounceTimer;

/// Coalesces bursts of triggers (rapid local edits, or a burst of websocket
/// wake-ups) into a single cycle a moment later, instead of one cycle per
/// event.
void triggerLiveSyncDebounced() {
  _liveSyncDebounceTimer?.cancel();
  _liveSyncDebounceTimer = Timer(const Duration(milliseconds: 800), () {
    runLiveSyncCycle();
  });
}

Timer? _liveSyncPeriodicTimer;
WebSocketChannel? _liveSyncSocket;
Timer? _liveSyncReconnectTimer;
int _liveSyncReconnectAttempt = 0;

/// Starts the always-on background machinery: a periodic cycle (also acts as
/// the socket's reconnect/keepalive poll) plus a best-effort websocket
/// connection for near-instant wake-ups. Call once at app startup -- every
/// piece self-guards on `selfHostedSession == null`, so it's harmless to
/// start before the user has ever signed in.
void startLiveSync() {
  if (_liveSyncPeriodicTimer != null) return; // idempotent
  _connectLiveSyncSocket();
  _liveSyncPeriodicTimer = Timer.periodic(const Duration(seconds: 45), (_) {
    if (selfHostedSession != null && _liveSyncSocket == null) {
      _connectLiveSyncSocket();
    }
    runLiveSyncCycle();
  });
}

void _connectLiveSyncSocket() {
  if (_liveSyncSocket != null) return;
  final session = selfHostedSession;
  if (session == null) return;

  try {
    final wsUrl = session.serverUrl.replaceFirst(RegExp(r'^http'), 'ws') + '/sync-stream';
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _liveSyncSocket = channel;
    channel.sink.add(jsonEncode({'type': 'auth', 'token': session.sessionToken}));

    channel.stream.listen(
      (message) {
        _liveSyncReconnectAttempt = 0;
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'changed') triggerLiveSyncDebounced();
        } catch (_) {
          // Not JSON or not the shape we expect -- ignore, the socket carries
          // no data we depend on beyond the bare "changed" wake-up.
        }
      },
      onDone: _scheduleLiveSyncReconnect,
      onError: (_) => _scheduleLiveSyncReconnect(),
      cancelOnError: true,
    );
  } catch (e) {
    print("Live sync socket connect failed: $e");
    _scheduleLiveSyncReconnect();
  }
}

void _scheduleLiveSyncReconnect() {
  _liveSyncSocket = null;
  if (selfHostedSession == null) return;
  final attempt = _liveSyncReconnectAttempt.clamp(0, 6);
  _liveSyncReconnectAttempt++;
  final delaySeconds = (1 << attempt).clamp(1, 60);
  _liveSyncReconnectTimer?.cancel();
  _liveSyncReconnectTimer = Timer(Duration(seconds: delaySeconds), _connectLiveSyncSocket);
}
