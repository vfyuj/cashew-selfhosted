# Sync client

Files: `app/lib/struct/liveSyncClient.dart` (the cycle), `struct/selfHostedClient.dart`
(HTTP/session layer), `struct/syncLog.dart` (the merge's input type). Server half:
[../server/sync.md](../server/sync.md).

**There is one sync mechanism.** Stage 1's whole-database exchange (`syncClient.dart`, a
`sync-<clientID>.sqlite` per device plus a "manage synced devices" screen) lived alongside this one
for a while and was removed in August 2026: both hand-listed every syncable table, and the two lists
had already drifted — `AppSettings` reached the feed and not the snapshot, so per-user view
preferences did not travel over a manual sync. `specs/04-stage-2-instant-sync.md` has the record.

## No outbox table

The `getAllNewX(lastSynced)` queries already select "rows changed since a timestamp" straight
from the source-of-truth Drift tables, so **those tables are the outbox**. Nothing can be lost
between a local write and the next push, because there is nowhere else the write could be. This also
avoided SQLite triggers (and their web/WASM portability question) and a schema migration.

## Cursors

Two, in shared preferences, keyed by **server + account + dataset**:

- **push cursor** — a timestamp. Local rows modified after it still need sending. It starts one
  millisecond above `DateTime(0)`, and that millisecond is load-bearing: `DateTime(0)` is the stamp
  `initializeDefaultDatabase()` puts on the default wallet and the eleven default categories to mark
  them as seeded rather than entered, and the `getAllNewX` scans compare with `>=`. Starting at
  `DateTime(0)` exactly sent them, so every device's first push planted those categories in the
  household's feed — where they stayed, since nothing ever edits a default category and so nothing
  supersedes it. Every device that joined later pulled them down as real data. `resetLiveSync()`
  rewinds to the same floor for the same reason.
- **pull cursor** — a `seq` from the server's feed.

The dataset is in the key because a `seq` is only meaningful within one dataset's feed. Neither the
server URL nor the email changes when an account's dataset does, so without it a stale cursor would
be applied to a new feed and every change below it silently skipped — with no `409` to signal it,
because the server cannot know the cursor came from elsewhere.

## One cycle

`runLiveSyncCycle()` — push, then pull. Guarded against overlap, and it never throws at its caller:
every failure is logged and retried on the next trigger. That is the local-first rule in practice —
sync failures must never become a blocked screen or an error the user has to dismiss.

- **Push** in batches of 200. A failed batch stops the push but **not** the pull: changes from other
  devices are independent of whether this device's own got out, and coupling them once meant a single
  unsendable row stopped this device receiving anything, permanently.
- **Pull** loops on `hasMore`, persisting the cursor **as it goes**. A crash mid-loop then re-fetches
  only the last unconfirmed page, which is safe to reapply because `processSyncLogs` is idempotent
  under last-write-wins.
- Each change is converted inside its own `try`. One unreadable row is skipped and counted; it used
  to throw out of the loop before the cursor was persisted, wedging that device forever — and a
  wedged device re-pushes everything every cycle, so it degenerated into a push storm. Skipping loses
  at most one row; not skipping loses everything after it.
- Pulled changes become `SyncLog`s and go through upstream's existing `processSyncLogs`. **Only the
  input to that merge is new** — the merge itself is untouched, tested, and should stay that way.
- The push cursor advances **only when the push succeeded**, and never past `cycleStartTime`, so an
  edit made during the cycle cannot be skipped.

`409 rebootstrap` (someone ran Reset Sync): resume at `minRetainedSeq` and rewind the push cursor to
zero so the whole local database goes back up. Purely local bookkeeping — nothing is deleted.

`skippedChanges` is surfaced in a snackbar; `conflictCount` deliberately is not. Conflicts are
last-write-wins doing its job on ordinary events (a new browser, a device catching up) and the
warning only ever read as alarming. A skipped row is different: devices can genuinely disagree, and
Reset Sync is the remedy.

## Triggers

| Trigger | Timing |
|---|---|
| local change | debounced 800 ms |
| WebSocket `changed` | immediate |
| poll, socket connected | 5 min |
| poll, no socket | 45 s |
| poll, backing off | up to 15 min |

The socket is an optimisation over the poll, never the transport — see the server page for why its
message carries no data. Session refresh runs inside the cycle but only near expiry; renewing a
30-day token every 45 s was pure overhead at both ends. The cycle also piggybacks a stale-profile
fetch (rate-limited to 30 minutes) so a name or role changed on another device eventually appears.

## Reset Sync

`resetLiveSync()` clears the server feed, drops this device's cursors, and re-uploads this device's
data as the new baseline. Reached from the sync sheet on the accounts page (`SyncSettings` in
`widgets/accountAndBackup.dart`), which is what remains of the old devices screen. A generation counter guards it: a cycle that started before the reset holds
cursors describing the old feed, and writing them back afterwards would silently undo it.

---

Why, including the race analysis behind `cycleStartTime` and the reverted first attempt:
`specs/04-stage-2-instant-sync.md`. The never-block rule: `specs/01-local-first-invariant.md`.
