import 'dart:async';
import 'dart:convert';

import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/perUserViewSettings.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/struct/syncLog.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart'
    show errorSigningInDuringCloud;
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Stage 2 live sync -- see specs/04-stage-2-instant-sync.md.
///
/// Row-level push/pull against the server's change feed. The only sync
/// mechanism there is: it replaced Stage 1's whole-database exchange, which was
/// kept alongside it for a while and then deleted -- two hand-written lists of
/// every syncable table had already drifted apart (`AppSettings` reached one
/// and not the other). See specs/04-stage-2-instant-sync.md.
///
/// Deliberately does not use a persisted local outbox table. The
/// `getAllNewX(lastSynced)` query methods already select "rows changed since
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

/// Scopes cursors per server+account+dataset, same reasoning as the existing
/// per-account session storage: switching servers/accounts must not reuse
/// stale progress from a different one.
///
/// The dataset is in the key because the pull cursor is a sequence number and
/// sequence numbers are only meaningful within one dataset's feed. Neither the
/// server URL nor the email changes when an account's dataset does, so without
/// this a cursor from the old feed would be applied to the new one and every
/// change below it would be skipped -- silently, permanently, and with no 409
/// to signal it, because the server has no way to know the cursor came from
/// somewhere else.
///
/// Adding this changes every existing device's key once, so each does one full
/// re-sync on upgrade. That is a no-op in both directions: pushes lose
/// last-write-wins against identical stored timestamps, and pulls lose against
/// identical local ones.
String? _cursorScopeKey() {
  final session = selfHostedSession;
  if (session == null) return null;
  return "${session.serverUrl}:${session.email}:${cachedServerProfile?.datasetId ?? 0}";
}

/// Where a device's push cursor starts, and what Reset Sync rewinds it to.
///
/// One millisecond above `DateTime(0)`, and that millisecond is the whole
/// point. `DateTime(0)` is the stamp `initializeDefaultDatabase()` puts on the
/// default wallet and the eleven default categories to mark them as seeded
/// rather than entered -- upstream's way of keeping them out of a sync. The
/// `getAllNewX` scans compare with `>=`, so a cursor of exactly `DateTime(0)`
/// matched them, and every device's first push planted those categories in the
/// household's feed, where they stayed: nothing ever edits them, so nothing
/// ever supersedes them, and every device that joined later pulled them down
/// as real data.
///
/// Rows with a null `dateTimeModified` are still picked up -- the scans OR in
/// `isNull()` -- so nothing that was genuinely never stamped is skipped.
final DateTime oldestPushCursor =
    DateTime(0).add(const Duration(milliseconds: 1));

Future<DateTime> _getPushCursor() async {
  final scope = _cursorScopeKey();
  if (scope == null) return oldestPushCursor;
  final ms = sharedPreferences.getInt(_pushCursorPrefsKeyPrefix + scope);
  return ms == null
      ? oldestPushCursor
      : DateTime.fromMillisecondsSinceEpoch(ms);
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
  // Fork-owned table: a category's plan for one month. Household data, so it
  // rides the ordinary dataset feed like everything else; the server keys
  // sync_records by (dataset_id, table_name, pk) and does not care that it has
  // never heard of this table name.
  for (final row in await database.getAllNewCategoryEnvelopes(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.CategoryEnvelope.name,
        pk: row.envelopePk,
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
  // Per-user view preferences. getAllNewAppSettings excludes row 0, the
  // device-local settings blob, so only rows keyed by a server user id travel.
  // Timestamped from dateUpdated: this is the one synced table whose column
  // isn't called dateTimeModified.
  for (final row in await database.getAllNewAppSettings(cursor)) {
    changes.add(_asChange(
        table: UpdateLogType.AppSetting.name,
        pk: row.settingsPk.toString(),
        modifiedAt: row.dateUpdated,
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
  final modifiedAt =
      DateTime.fromMillisecondsSinceEpoch(change['modifiedAt'] as int);

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
    case UpdateLogType.AppSetting:
      itemToUpdate = AppSetting.fromJson(payload);
      break;
    case UpdateLogType.CategoryEnvelope:
      itemToUpdate = CategoryEnvelope.fromJson(payload);
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
  // Paused means paused. Without this, [pauseLiveSync] only stopped the timers
  // and the socket, so a debounce already in flight -- or any direct caller --
  // still ran a full cycle afterwards. That mattered once importDB started
  // relying on a pause to hold sync off while it replaces the database file
  // underneath it.
  if (_liveSyncPaused) return;
  if (appStateSettings["hasSignedIn"] != true) return;
  if (appStateSettings["backupSync"] == false) return;
  if (errorSigningInDuringCloud == true) return;
  if (selfHostedSession == null) return;
  if (_liveSyncCycleRunning) return;
  _liveSyncCycleRunning = true;

  // null while no request has been attempted yet, so a cycle that bailed out
  // before touching the network (no session, nothing to do) doesn't get
  // counted as the server being unreachable and back the poll off for it.
  bool? reachedServer;

  try {
    // Silent, non-blocking -- see specs/01-local-first-invariant.md. Only
    // actually hits the network when the session is near expiry; renewing a
    // 30-day token on every 45s tick was pure overhead at both ends.
    await selfHostedRefreshIfNeeded();
    final session = selfHostedSession;
    if (session == null) return;
    final client = SelfHostedClient(session);

    // Unawaited: a name/email/role change made on another device is only
    // ever reflected here via cachedServerProfile, and nothing else refetches
    // it periodically. Piggybacking on this cycle is what makes those changes
    // eventually show up on this device without the user having to do
    // anything -- not instantly, but never "not at all." Rate-limited to once
    // every 30 minutes inside the callee; a display name does not change often
    // enough to be worth a request per tick.
    selfHostedFetchProfileIfStale();

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
      final end =
          (i + 200 < localChanges.length) ? i + 200 : localChanges.length;
      try {
        final result = await client.pushSyncChanges(
          deviceId: clientID,
          changes: localChanges.sublist(i, end),
        );
        reachedServer = true;
        conflictCount += result.conflictCount;
      } catch (e) {
        print("Live sync push failed: $e");
        reachedServer ??= false;
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
        reachedServer = true;
      } on SyncRebootstrapRequiredException catch (e) {
        // A 409 is the server answering, so this counts as reached -- the
        // connection is fine, it's the cursor that isn't.
        reachedServer = true;
        // Someone ran Reset Sync. This device's cursors describe a feed that
        // no longer exists, so drop them: resume reading at the feed's new
        // start, and rewind the push cursor to 0 so the whole local database
        // is re-uploaded on the next cycle. Purely local bookkeeping -- no
        // data is deleted here.
        print(
            "Live sync: server feed was reset, rebootstrapping from seq ${e.minRetainedSeq}");
        await _setPullCursor(e.minRetainedSeq);
        await _setPushCursor(DateTime(0));
        return;
      } catch (e) {
        print("Live sync pull failed: $e");
        reachedServer ??= false;
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
        final modifiedAt =
            DateTime.fromMillisecondsSinceEpoch(change['modifiedAt'] as int);
        if (pulledMax == null || modifiedAt.isAfter(pulledMax))
          pulledMax = modifiedAt;
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
      // A view preference changed on this member's other device has just
      // landed in the database; pull it into the live settings map so the
      // screen follows without a restart. Only reads the rows this member
      // owns, and is a no-op on a solo account.
      if (logsToApply.any(
          (SyncLog log) => log.updateLogType == UpdateLogType.AppSetting)) {
        await applyStoredViewSettings();
      }
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
        final bump = localPulledMax.isAfter(cycleStartTime)
            ? cycleStartTime
            : localPulledMax;
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

    // Deliberately not surfaced: conflictCount is just last-write-wins doing
    // its job. It fires on the ordinary cases -- signing in on a new browser,
    // or a device catching up after being away -- where nothing is actually
    // lost and there is nothing for the user to do, so the warning only ever
    // read as alarming. skippedChanges above is different and still shown:
    // that one means a row could not be read at all.
  } catch (e) {
    print("Live sync cycle error: $e");
    reachedServer ??= false;
    if (e is SelfHostedUnauthenticatedException) {
      // The server answered -- it just rejected the session. Backing the poll
      // off would be wrong here; this needs the user, not patience.
      reachedServer = true;
      errorSigningInDuringCloud = true;
    }
  } finally {
    _liveSyncCycleRunning = false;
    if (reachedServer != null) {
      _recordCycleOutcome(reachedServer: reachedServer);
    }
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
    // Re-scan and re-upload everything local -- everything the user actually
    // has, that is. See [oldestPushCursor]: rewinding to DateTime(0) exactly
    // would sweep the seeded default categories back into the feed, which is
    // the mess Reset Sync is most often reached for in the first place.
    await _setPushCursor(oldestPushCursor);
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

Timer? _liveSyncPollTimer;
WebSocketChannel? _liveSyncSocket;
Timer? _liveSyncReconnectTimer;
int _liveSyncReconnectAttempt = 0;
bool _liveSyncStarted = false;

/// True only once the server has acknowledged the auth handshake with
/// `{"type":"ready"}`. A non-null [_liveSyncSocket] means "we opened
/// something", which is not the same thing -- the socket exists from the
/// moment `connect` is called, including while a broken or unauthenticated
/// connection is on its way to failing.
bool _liveSyncSocketReady = false;

/// Set while the app is backgrounded. Everything that would touch the network
/// checks this, so a phone in a pocket isn't running sync.
bool _liveSyncPaused = false;

/// Consecutive cycles that failed to reach the server, used to back the poll
/// off while offline. Reset by any success, by a resume, and by sign-in.
int _liveSyncFailureStreak = 0;

/// Poll cadence when the wake-up socket is down and the poll is the *only*
/// way changes from other devices arrive.
const _pollIntervalWithoutSocket = Duration(seconds: 45);

/// Poll cadence when the socket is up. It is a backstop then, not the
/// mechanism -- a push on another device wakes this one over the socket
/// within a second, so polling every 45s on top of that bought nothing and
/// cost three requests a minute forever.
const _pollIntervalWithSocket = Duration(minutes: 5);

/// Ceiling for the offline backoff. Long enough that a phone with no route to
/// the server stops waking its radio for nothing; short enough that coming
/// back into range is noticed without the user doing anything (and a resume,
/// a local edit, or a socket reconnect all short-circuit it anyway).
const _pollIntervalMax = Duration(minutes: 15);

/// How long to wait before the next poll: the base cadence for the current
/// socket state, doubled per consecutive failure, capped.
Duration _nextPollInterval() {
  final base = _liveSyncSocketReady
      ? _pollIntervalWithSocket
      : _pollIntervalWithoutSocket;
  if (_liveSyncFailureStreak == 0) return base;
  final backedOff = base * (1 << (_liveSyncFailureStreak.clamp(1, 5) - 1));
  return backedOff > _pollIntervalMax ? _pollIntervalMax : backedOff;
}

/// Records whether a cycle managed to talk to the server, so the poll can back
/// off while there's nothing to talk to. Called by [runLiveSyncCycle].
void _recordCycleOutcome({required bool reachedServer}) {
  final previous = _nextPollInterval();
  if (reachedServer) {
    _liveSyncFailureStreak = 0;
  } else if (_liveSyncFailureStreak < 5) {
    _liveSyncFailureStreak++;
  }
  // Only disturb the schedule when the interval actually changed, so a run of
  // failures at the cap doesn't keep pushing the next attempt away.
  if (_nextPollInterval() != previous) _scheduleNextPoll();
}

/// Starts the always-on background machinery: a self-rescheduling poll plus a
/// best-effort websocket connection for near-instant wake-ups. Call once at
/// app startup -- every piece self-guards on `selfHostedSession == null`, so
/// it's harmless to start before the user has ever signed in.
void startLiveSync() {
  if (_liveSyncStarted) return; // idempotent
  _liveSyncStarted = true;
  _connectLiveSyncSocket();
  _scheduleNextPoll();
  // Catch up once at startup rather than waiting out the first interval.
  // watchAllForAutoSync used to supply this implicitly, via the initial value
  // its `.watch()` streams emitted on subscription; it no longer emits one,
  // and depending on that side effect was never obvious anyway.
  runLiveSyncCycle();
}

/// One-shot rather than [Timer.periodic], because the interval is not fixed:
/// it depends on whether the socket is carrying wake-ups and on how long the
/// server has been unreachable.
void _scheduleNextPoll() {
  _liveSyncPollTimer?.cancel();
  _liveSyncPollTimer = null;
  if (_liveSyncPaused || !_liveSyncStarted) return;

  _liveSyncPollTimer = Timer(_nextPollInterval(), () async {
    if (_liveSyncPaused) return;
    if (selfHostedSession != null && _liveSyncSocket == null) {
      _connectLiveSyncSocket();
    }
    await runLiveSyncCycle();
    _scheduleNextPoll();
  });
}

/// Stops all background network activity. Called when the app is backgrounded
/// (see main.dart): without this the poll kept firing out of sight, which on
/// Android -- where the process routinely outlives the UI -- meant a phone in
/// a pocket waking its radio every 45 seconds indefinitely.
void pauseLiveSync() {
  _liveSyncPaused = true;
  _liveSyncPollTimer?.cancel();
  _liveSyncPollTimer = null;
  _liveSyncReconnectTimer?.cancel();
  _liveSyncReconnectTimer = null;
  _closeLiveSyncSocket();
}

/// Pauses, then waits for a cycle that was already running to finish.
///
/// For callers that are about to replace the database file itself: pausing
/// stops anything new from starting, but a cycle already mid-flight is still
/// holding the old database and would write into it. Bounded, because a hung
/// cycle must not turn into a hung restore -- and the wait is a courtesy
/// anyway, since [processSyncLogs] is idempotent under last-write-wins and the
/// restore overwrites everything regardless.
Future<void> pauseLiveSyncAndWait(
    {Duration timeout = const Duration(seconds: 10)}) async {
  pauseLiveSync();
  final DateTime deadline = DateTime.now().add(timeout);
  while (_liveSyncCycleRunning && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (_liveSyncCycleRunning) {
    print("A sync cycle was still running after ${timeout.inSeconds}s; "
        "continuing anyway");
  }
}

/// Resumes after [pauseLiveSync] and catches up immediately. Idempotent, and
/// safe to call without a matching pause -- desktop and web may never report
/// a paused state at all.
void resumeLiveSync() {
  _liveSyncPaused = false;
  // A resume is a fresh chance: the reason the last attempts failed was very
  // possibly that the phone was somewhere else entirely.
  _liveSyncFailureStreak = 0;
  _liveSyncReconnectAttempt = 0;
  if (_liveSyncStarted && _liveSyncSocket == null) _connectLiveSyncSocket();
  _scheduleNextPoll();
  runLiveSyncCycle();
}

void _closeLiveSyncSocket() {
  final socket = _liveSyncSocket;
  _liveSyncSocket = null;
  _liveSyncSocketReady = false;
  if (socket == null) return;
  try {
    socket.sink.close();
  } catch (_) {
    // Already dead; nothing to do.
  }
}

void _connectLiveSyncSocket() {
  if (_liveSyncSocket != null) return;
  if (_liveSyncPaused) return;
  final session = selfHostedSession;
  if (session == null) return;

  try {
    final wsUrl =
        session.serverUrl.replaceFirst(RegExp(r'^http'), 'ws') + '/sync-stream';
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _liveSyncSocket = channel;
    channel.sink
        .add(jsonEncode({'type': 'auth', 'token': session.sessionToken}));

    channel.stream.listen(
      (message) {
        _liveSyncReconnectAttempt = 0;
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'ready') {
            // Authenticated: wake-ups will arrive on their own from here, so
            // the poll can drop back to being a backstop.
            if (!_liveSyncSocketReady) {
              _liveSyncSocketReady = true;
              _scheduleNextPoll();
            }
          } else if (data['type'] == 'changed') {
            triggerLiveSyncDebounced();
          }
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
  final wasReady = _liveSyncSocketReady;
  _liveSyncSocket = null;
  _liveSyncSocketReady = false;
  // Losing the socket means the poll is the only path again, so it has to
  // speed back up -- otherwise a dropped connection would silently leave this
  // device on the 5-minute backstop cadence.
  if (wasReady) _scheduleNextPoll();

  if (_liveSyncPaused) return;
  if (selfHostedSession == null) return;
  final attempt = _liveSyncReconnectAttempt.clamp(0, 6);
  _liveSyncReconnectAttempt++;
  final delaySeconds = (1 << attempt).clamp(1, 60);
  _liveSyncReconnectTimer?.cancel();
  _liveSyncReconnectTimer =
      Timer(Duration(seconds: delaySeconds), _connectLiveSyncSocket);
}
