# Stage 2 — Live sync

Replaces Stage 1's whole-database exchange with a row-level change feed, and adds automatic
sync (periodic + push + websocket wake-up) on top of it. Read `01-local-first-invariant.md`
first: nothing here may block, delay, or gate a local write.

## Status (last updated 2026-08-08)

Implemented end to end (server + app) and static-analyzed clean on both. Two rounds of testing
against a real deployment each found a Drift JSON-converter bug (see "Applying pulled changes"):
the first stopped any push from ever leaving a device, the second let pushes through but broke
reconstruction on the receiving device. Both fixed, with regression tests. That second round also
exposed how a stuck cycle degenerates into a fleet-wide push storm, and motivated the Reset Sync
escape hatch. Still needs the on-device acceptance pass below.

- [x] Server: `sync_records` / `sync_state` schema
- [x] Server: `POST /sync/push`, `GET /sync/pull`
- [x] Server: `/sync-stream` WebSocket wake-up + in-memory hub
- [x] Server: `POST /sync/reset`; `min_retained_seq` / 409 rebootstrap now actually used
- [x] Server: push notifies peers only when something actually changed
- [x] App: `insertOrIgnore` merge-bug fix in `processSyncLogs`
- [x] App: `liveSyncClient.dart` push/pull cycle (cursor-scan design — see below, this deviates
  from the outbox/trigger design originally sketched here)
- [x] App: WebSocket client, reconnect/backoff
- [x] App: wired to app start, local-change debounce, periodic timer, app resume, websocket wake
- [x] App: `JsonTypeConverter2` on every list converter; per-change pull resilience
- [x] App: Reset Sync button + rebootstrap handling
- [ ] Verified against a real server deployment (airplane-mode test, two-device test) — the owner
  tests manually, per "Testing & verification workflow" in `CLAUDE.md`.
- [ ] **Regression pass not done.** An earlier WebSocket attempt at this stage was reverted after
  breaking the "Add Account" button on `accountsPage.dart` and reintroducing a restore-propagation
  race (device A restores and syncs; device B edits before pulling A's restore; A reloads and rolls
  forward past B's edit). This implementation is a different, later attempt and neither symptom has
  been re-checked. Check both before trusting this stage, along with sign-in, account creation, and
  the existing full-snapshot sync/backup UI.

**Empirical note (owner testing, 2026-08-08)**, carried over from the previous plan and still
relevant: comparing "sync on every change" against a vanilla Cashew instance, the vanilla/Google
Drive loading bar is very slow and clearly visible while this fork's is barely visible — despite
both doing full-snapshot-per-change work at the time. That gap is almost certainly Google Drive's
API latency (OAuth handling, real internet round-trips) versus a self-hosted server on the same
LAN. Two implications: don't assume "slow sync" reports are about payload size alone, the network
path matters at least as much; and this stage's payoff grows with transaction history rather than
being urgent on a small database. Worth re-measuring on a realistically-sized database (years of
transactions, not a fresh test account).

## Why replace the Stage 1 mechanism

`syncData()` uploads this device's entire SQLite file and downloads every peer's entire SQLite
file, opening each as a second Drift database to diff it. Cost scales with **database size**, not
with how much changed: 4 devices × a 5 MB database ≈ 80 MB per family-wide sync round. Automating
that on a timer is not viable. After this stage, a sync that finds nothing new transfers a few
hundred bytes regardless of how large the database has grown.

### The old mechanism was kept, then deleted (2026-08-20)

For a while `syncClient.dart` stayed untouched and reachable from the "manage synced devices" screen,
with only the *automatic* triggers switched over. That was meant as a safety net while this stage
settled. It became a liability instead.

**Both mechanisms hand-listed every syncable table, and the two lists drifted.** `AppSettings` was
added to the feed when per-user view settings shipped (`06-shared-household-data.md`) and never to
the snapshot path — so a manual sync silently failed to carry a member's hidden accounts or home-page
order. `CategoryEnvelopes` had to be added to both. Every future table would too, and nothing checked
that it was.

Deleted, therefore, along with everything only it used:

- app: `createSyncBackup()`, `syncData()`/`_syncData()`, the per-client `dateOfLastSyncedWithClient`
  cursors, the `sync-<clientID>.sqlite` filename helpers, the `isClientSync` branch of the backup
  sheet (twenty conditionals in one widget), and the `syncEveryChange` / `devicesHaveBeenSynced`
  settings. `SyncLog` moved to `struct/syncLog.dart` — it belongs to the merge, not the transport.
- server: `GET/PUT/GET/DELETE /sync/files*` and the `sync/` storage namespace. Existing directories
  are left on disk rather than deleted on upgrade; `DEPLOYMENT.md` says how to remove them.

Two things the removal had to preserve, because they were never part of the snapshot exchange and
only shared its file or its screen:

- **Reset Sync** belongs to the change feed. It moved to a small `SyncSettings` sheet
  (`widgets/accountAndBackup.dart`) with the `backupSync` master switch, which is what remains of the
  devices screen.
- **`pauseLiveSync()` now actually pauses.** `importDB` and `loadBackup` used
  `cancelAndPreventSyncOperation()` to hold sync off while they replace the database file; the
  replacement is `pauseLiveSyncAndWait()`. It also fixed a latent bug — `runLiveSyncCycle()` did not
  check the paused flag, so a debounce already in flight ran a full cycle after a pause anyway.

## Design in one line

The server keeps **one row per record** (not per change) with a monotonic per-user `seq`; clients
push changed rows and pull `seq > cursor`.

Keeping only the newest version per record is safe precisely because merge is last-write-wins per
row: applying only the latest version of a row yields the same result as replaying every
intermediate version. That property is what keeps server storage bounded by the size of the data
rather than by the length of its history. There is no per-change history table — it would grow
without bound and buy nothing.

## Server

### Schema (`server/lib/src/database.dart`)

```sql
CREATE TABLE sync_records (
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  table_name  TEXT    NOT NULL,
  pk          TEXT    NOT NULL,
  seq         INTEGER NOT NULL,
  deleted     INTEGER NOT NULL DEFAULT 0,
  modified_at INTEGER NOT NULL,   -- epoch ms; client dateTimeModified after clamping
  device_id   TEXT    NOT NULL,   -- who pushed it (debugging only, not part of LWW)
  payload     TEXT,               -- row as JSON; NULL when deleted
  PRIMARY KEY (user_id, table_name, pk)
);
CREATE INDEX idx_sync_records_feed ON sync_records(user_id, seq);

CREATE TABLE sync_state (
  user_id          INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  next_seq         INTEGER NOT NULL DEFAULT 1,
  min_retained_seq INTEGER NOT NULL DEFAULT 0
);
```

`min_retained_seq` is 0 until someone runs **Reset Sync**, which parks it above every cursor in
circulation so that peers are forced to rebootstrap (see below). There is still no tombstone
cleanup; that would be the column's other use.

### `POST /sync/push` (`server/lib/src/sync/sync_routes.dart`)

```jsonc
// request
{ "deviceId": "…", "changes": [
    { "table": "Transaction", "pk": "…", "deleted": false,
      "modifiedAt": 1754600000000, "payload": { /* row.toJson() */ } } ] }

// response
{ "serverTime": 1754600000123, "conflictCount": 0 }
```

`table` is the wire value of Dart's `UpdateLogType`/`DeleteLogType` enum (`.name`, e.g.
`"Transaction"`, `"TransactionWallet"`) — the two enums are structurally parallel, so one string
space serves both directions with no separate mapping table.

Per change, all inside one `BEGIN`/`COMMIT` (no `await` between them, so sqlite3's synchronous API
plus Dart's single-threaded event loop makes each push atomic against concurrent requests without
needing app-level locking):

1. Clamp `modifiedAt` to at most `serverTime + 120_000`. Without this, one device with a fast
   clock silently wins every conflict forever.
2. Load the stored row for `(user_id, table_name, pk)`. No stored row → insert, assign `seq`.
3. Stored row exists, incoming `modifiedAt` strictly greater → accept, assign a new `seq`.
4. Incoming `modifiedAt` equal to stored → **no-op**, not a conflict, *unless* the payload also
   differs from what's stored, in which case it's a genuine same-millisecond collision between two
   different edits and does count as a conflict. Content-equality (not `deviceId`) is what makes
   this the correct no-op check: a device that re-pushes a row it only just pulled from a peer
   arrives with the *same* timestamp and *identical* content, and must not increment
   `conflictCount` or spuriously flip whose `device_id` is on record. (This case is called "echo
   suppression" in the client section below.)
5. Incoming `modifiedAt` strictly less than stored → conflict, rejected, not applied.

After commit, if any changes were pushed, notify every other open `/sync-stream` socket for that
user (see below).

### `GET /sync/pull?since=<seq>&limit=<n>` (same file)

`limit` defaults to 500, clamped to [1, 2000].

```jsonc
{ "changes": [ { "seq": 4128, "table": "Transaction", "pk": "…", "deleted": false,
                 "modifiedAt": …, "deviceId": "…", "payload": { … } } ],
  "nextCursor": 4128, "hasMore": false, "serverTime": … }
```

Returns `409 {"error":"rebootstrap","minRetainedSeq":N}` when `since < min_retained_seq` (dead
code today, per the note above). A new device bootstraps with `since=0` and pages through.

### `/sync-stream` (WebSocket — `sync_stream_routes.dart` + `sync_hub.dart`)

Mounted as a **separate top-level route**, not under `/sync` — a WebSocket handshake (especially
from a browser) can't carry a custom `Authorization` header, so this endpoint is unauthenticated
at the HTTP layer and instead requires `{"type":"auth","token":"…"}` as the first message. Never a
URL query parameter, so a token can't land in reverse-proxy access logs. (The spec originally
called this `/sync/stream`; it was moved a level up specifically to avoid any ambiguity with
`shelf_router`'s route-matching order against the `/sync` mount — a `/sync-stream` sibling path
sidesteps the question entirely rather than relying on registration-order precedence.)

- On successful auth: server replies `{"type":"ready"}` and registers the socket in an in-memory
  `SyncHub` (`Map<userId, Set<WebSocketChannel>>`).
- On push: every socket for that `userId` receives a bare `{"type":"changed"}` — no payload. The
  client's only reaction is to run an ordinary pull, so a dropped, duplicated, or reordered
  message can never lose or double-apply data; worst case is one redundant pull.
- Server-side ping every 30s via `shelf_web_socket`'s `pingInterval` (keeps the connection alive
  through reverse-proxy idle timeouts and lets a dead peer be detected).

**Debugging note:** a *successful* upgrade never appears in the server log. `logRequests` logs a
response, and the WebSocket handler hijacks the socket instead of returning one. So the absence of
`/sync-stream` lines proves nothing about whether clients are connected — a plain non-upgrade
`GET /sync-stream` (which logs `[200]`, having fallen through the `Cascade` to the SPA catch-all)
is not the same event. To check the endpoint itself, do the handshake by hand and look for `101`:

```bash
curl -i --max-time 5 -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" http://localhost:8080/sync-stream
```

**Documented constraint:** both `seq` assignment and the socket hub are only correct because the
server is a single Dart process. A second writer process could commit a lower `seq` after a higher
one is already visible to a reader, and a second process wouldn't see the first's in-memory
sockets at all. Revisit before scaling out.

## App

### What actually changed vs. the original plan here

The original version of this document specified a **persisted local outbox table fed by SQLite
triggers**, with an explicit echo-suppression flag. That was not built. Instead:

**No new Drift table, no schema migration, no triggers.** Stage 1 already has, and already tests,
a full set of `getAllNewX(DateTime lastSynced)` query methods on `FinanceDatabase` — one per
synced table (`getAllNewWallets`, `getAllNewTransactions`, …) plus `getAllNewDeleteLogs` — each
selecting rows with `dateTimeModified >= lastSynced`. The push side of live sync reuses these
unchanged. The source-of-truth tables themselves serve as the outbox: a write is durable the
instant it lands in Drift, which is also the instant it becomes visible to the next push scan, so
nothing extra needs to persist it. This was a deliberate simplification, chosen over the
trigger design for three reasons: it avoids the open question (never resolved) of whether the
JSON1 SQLite extension is available in Drift's web/WASM build; it reuses code that Stage 1 already
exercises rather than adding an untested subsystem; and per this fork's working style, it's the
option that doesn't add a mechanism beyond what the task needs.

This does require care that the trigger design would have avoided for free — see "Echo
suppression and the cursor race" below.

### Cursors

Two independent `sharedPreferences` values, scoped per `serverUrl:email` (mirrors the existing
session-storage scoping) so switching accounts/servers can't reuse stale progress:

- **Push cursor** (`liveSyncPushCursorMs:<scope>`) — a `DateTime`, milliseconds since epoch.
  Default `DateTime(0)` when unset, which is also what makes first-run migration work for free
  (see below) — an unset cursor means "everything is new."
- **Pull cursor** (`liveSyncPullCursorSeq:<scope>`) — the server `seq`, an `int`. Default `0`.

### The cycle — `runLiveSyncCycle()` (`lib/struct/liveSyncClient.dart`)

Guarded by the same local-first checks as the old mechanism (`hasSignedIn`, `backupSync`,
`errorSigningInDuringCloud`, `selfHostedSession != null`) plus a re-entrancy flag so overlapping
triggers collapse into one in-flight cycle rather than piling up.

1. `selfHostedRefresh()` — silent, non-blocking, per `01-local-first-invariant.md`.
2. Capture `cycleStartTime = DateTime.now()` **before** touching the network — this is what makes
   step 5 race-free; see below.
3. **Push.** Call the eight `getAllNewX(pushCursor)` methods plus `getAllNewDeleteLogs`, batch
   into groups of ≤200, `POST /sync/push`. Sum `conflictCount` across batches. Any batch failing
   aborts the push loop, but **the pull still runs** — see "A failed push must not block the
   pull" below. The push cursor stays unchanged, so the whole push is retried from scratch next
   cycle; no attempt is made to salvage a partial push.
4. **Pull.** Loop `GET /sync/pull?since=pullCursor` while `hasMore`; convert each change to a
   `SyncLog` and apply the whole batch via the existing `processSyncLogs` once the loop ends.
   Advance and persist the pull cursor after *each* page (not just at the end), so a crash
   mid-loop only re-fetches the last unconfirmed page — safe, since applying the same page twice
   is a no-op under LWW.

   **Reconstructing one change is wrapped in its own `try`.** An unreadable change is counted,
   logged, skipped, and reported to the user in a snackbar; the cursor still advances past it.
   This looks like it loses data, and it does lose that one row — but the alternative is strictly
   worse, and was the original behaviour: the throw escaped the loop *before* the cursor was
   persisted, so every change after the bad one became unreachable and sync was dead for that
   device permanently. See "The failure mode this creates" below for how badly that degraded.
5. **Advance the push cursor — only if the push succeeded**, taking the max of two contributions:
   - `cycleStartTime` (everything local as of the scan is now server-side).
   - If anything was pulled, `min(maxPulledModifiedAt, cycleStartTime)` — see the race note below
     for why this is clamped rather than using the raw pulled timestamp.

   When the push failed the cursor does not move at all, *including* the pulled-data contribution:
   advancing it past a local edit that never reached the server would drop that edit permanently.
   Deferring echo suppression to the next successful cycle costs at most one redundant re-push,
   which the server's content-equality check no-ops.
6. If `conflictCount > 0`, a non-blocking snackbar. Notification only — no archive, no restore
   button, per explicit direction: *"Simply display a notification about the conflict, no need to
   have a button to restore. I don't need the restore mechanism."*

### The failure mode this creates (and why the server only notifies on real changes)

Worth writing down, because a stuck cycle does not fail quietly — it amplifies into a fleet-wide
storm, and the observable symptoms point away from the cause:

1. A cycle throws part-way through. Neither cursor advances.
2. Because the push cursor never advances, the *next* cycle re-scans and re-pushes the device's
   entire changed set. Every row is byte-identical to what the server holds, so every change is a
   no-op — `next_seq` doesn't move and nothing is really written.
3. The push handler used to notify peers whenever `changes.isNotEmpty`, i.e. even when every change
   was a no-op. So each pointless re-push woke every other device over `/sync-stream`.
4. Those devices ran a cycle, hit the same throw, re-pushed everything, and woke everyone back.

Steady state was ~1 push storm per second across every signed-in device, indefinitely, with every
request returning `200`. `lastSynced` froze (it is only written on a fully successful cycle), so the
UI reported "Synced 6 minutes ago" forever while the server log scrolled with successful traffic.

Two independent changes stop this: the per-change `try` in step 4 above means a bad row no longer
wedges the cycle, and the push handler now counts changes that actually altered stored state and
calls `syncHub.notify` only when that count is greater than zero. The second one is worth keeping
regardless of the first: a push in which nothing changed gives peers nothing to fetch, so waking
them is pure waste even when everything is healthy.

### Echo suppression and the cursor race

Without the trigger design's explicit suppression flag, two problems have to be solved by how the
push cursor moves, both handled by step 5 above:

**Echoes.** Device B pulls a row Device A authored (`modifiedAt = T`). Applying it via
`processSyncLogs` writes that same `T` into B's local table (the payload carries its own original
timestamp — pulling never stamps "now"). Without bumping B's push cursor past `T`, B's *own* next
push scan (`dateTimeModified >= cursor`) would re-select and re-send that row forever, on every
single cycle, permanently — not a one-time waste but unbounded, growing as more rows arrive via
pull. Bumping the push cursor to (at least) `T` after a pull fixes this: the row no longer
satisfies `>= cursor` next time. The server-side content-equality no-op check (see push handler,
step 4) is a second, independent line of defense against any echo that slips through anyway.

**The race that naive bumping would introduce.** If the push cursor were simply set to
`maxPulledModifiedAt` with no clamp, a narrow but real bug follows: suppose the user edits a
transaction *during* the pull phase of a cycle, and a peer's pulled row happens to have a later
timestamp than that brand-new local edit. Bumping the cursor to the pulled row's timestamp would
push it *past* the new edit's timestamp too, and the next push scan (`>= cursor`) would silently
skip that edit forever — a genuine lost write, not just a wasted round trip.

The fix is the `cycleStartTime` clamp in step 5: the push cursor can never advance past the moment
the cycle began. Any local edit made during the cycle necessarily has `dateTimeModified >=
cycleStartTime`, so it always remains `>= cursor` and will be picked up next scan, regardless of
what got bumped from pulled data. The only cost is that a pulled row whose timestamp exceeds
`cycleStartTime` (only possible in that same narrow window) doesn't get its echo fully suppressed
until the *following* cycle — one harmless extra re-push, caught by the server-side no-op check,
never a correctness problem.

### Applying pulled changes

Reconstructed via each table's Drift-generated `fromJson`/`toJson` (`TransactionWallet.fromJson`,
`Transaction.fromJson`, …) — no manual field mapping. Built into a `SyncLog` and handed to the
existing `processSyncLogs`, unchanged: the merge logic is exactly what Stage 1 already had and
tested; only what feeds it is new.

**Every converter on a synced column must mix in `JsonTypeConverter2`.** Drift applies a plain
`TypeConverter` to SQL only — the generated `toJson` emits the *raw Dart value*, and `fromJson`
casts the decoded JSON straight back to the Dart type. This is not a theoretical hazard; it took
live sync down twice, in two different ways, and the second way is the more instructive one:

- **`List<enum>` columns fail on encode.** `Wallets.homePageWidgetDisplay` and
  `Budgets.budgetTransactionFilters` emitted enum *instances*, so `jsonEncode` threw
  `Converting object to an encodable object failed`. Because every wallet gets a non-null
  `defaultWalletHomePageWidgetDisplay`, the first push batch of every device died and not one row
  ever reached the server.
- **`List<String>` columns fail only on decode** — and that is far nastier, because a
  `List<String>` encodes perfectly well. `Budgets.walletFks`/`categoryFks`/`sharedMembers`/… and
  `Transactions.budgetFksExclude` pushed cleanly, so the server filled up and the sending device
  looked healthy; the *receiving* device then threw
  `List<dynamic> is not a subtype of List<String>?` while reconstructing. Fixing only the
  encode-breaking columns therefore looked like a working sync right up until a second device
  tried to read a budget.

All the list converters (`IntList`, `StringList`, `DoubleList`, plus the two enum ones) now mix in
`JsonTypeConverter2<…, String, List<dynamic>>`, producing the same JSON array `toSql` already
encoded into its string. `toSql`/`fromSql` are untouched, so the SQL format is unchanged and no
migration was needed — and payloads already stored on the server stay readable.

The moral for anything added later: a synced column carrying a collection or an enum needs a
`JsonTypeConverter2`, and it is not enough to check that `toJson()` succeeds.

`test/live_sync_serialization_test.dart` locks this down by round-tripping the data classes
through `jsonEncode`/`jsonDecode`, plus a blanket "every synced data class encodes" case so the
next column of this kind fails a test instead of production. Note that asserting on `toJson()`
alone would not have caught it — the failure only appears once the result is actually encoded.

**`insertOrIgnore` fix, landed as part of this stage
([tables.dart:3700-3801](../app/lib/database/tables.dart)):** every upsert inside
`processSyncLogs` was a correctly timestamp-guarded `UPDATE` immediately followed by an
*unguarded* `batch.insert(..., mode: InsertMode.insertOrReplace)`. `INSERT OR REPLACE` deletes and
reinserts on primary-key conflict regardless of timestamp, silently undoing the guard above it for
any row that already existed locally. Changed to `InsertMode.insertOrIgnore` at all 8 call sites.
Inherited from upstream; not something row-level sync introduced, but automatic sync running every
tens of seconds instead of on manual pull-to-refresh made it far more likely to actually bite.

**That fix was necessary but not sufficient, and the gap destroyed user data (fixed in 1.1.1).**
`insertOrReplace` had been carrying a second, undocumented property: it reinserted the whole row, so
a column absent from the payload fell back to its null default. Swapping in `insertOrIgnore` kept
the timestamp guard and silently dropped that. What remained was `batch.update(table, dataClass)`,
and `Batch.update` calls `toColumns(nullToAbsent: true)` — a data class omits every null column from
the SET clause, and the `insertOrIgnore` behind it cannot compensate for a row that already exists.
**No nullable column could be cleared over sync at all.**

The failure chain that surfaced it: promoting a subcategory to a main category clears
`Categories.mainCategoryPk` and repoints the affected transactions. The transactions crossed;
the cleared `mainCategoryPk` did not. Peers therefore still saw a subcategory under `categoryFk`,
`deleteWanderingTransactions` judged those transactions orphaned, and — because it deleted *and*
wrote `DeleteLogType.Transaction` tombstones — sentenced them on every device in the household,
including the one that had made the change. Wallet balances rose accordingly.

Two fixes, deliberately separate:

- **`processSyncLogs`** converts each incoming row with `toCompanion(false)` first, so nulls are
  written as explicit nulls while the guard stays exactly as it was. Pinned by
  `test/sync_null_propagation_test.dart`.
- **`deleteWanderingTransactions`** no longer answers every violation identically. A transaction
  filed against a subcategory whose parent exists is now *repaired* with the same swap
  `createOrUpdateTransaction` already applies; only a transaction whose category resolves to nothing
  is deleted, and that deletion writes **no tombstone** — a device must not pass sentence on data it
  may simply not have received yet (`specs/01-local-first-invariant.md`). The repair deliberately
  does not bump `dateTimeModified`, so one device's guess can never outrank the authoritative copy.
  Pinned by `test/wandering_transactions_test.dart`.

The moral, which generalises past this bug: when replacing an upsert mode, enumerate every property
it was providing, not just the one being fixed.

### Conflict notification

Exactly a snackbar, nothing else — no archive table, no restore UI, no extra endpoints, per
explicit direction. Adequate because the case is narrow: two people each *recording their own
transactions* never collide (every row gets a fresh UUID at creation, so their rows never share a
primary key and LWW never compares them). A conflict requires both people editing **the same
existing record** in the same offline window.

Field-level (per-column) merge was proposed and explicitly rejected by the user as unnecessary
complexity for how rarely that happens. Do not revisit without new direction.

### Triggers wired

- **App start** — `runAllCloudFunctions` (`navigationFramework.dart`) calls `runLiveSyncCycle()`
  where it used to call `syncData()`.
- **Local change** — the existing `database.watchAllForAutoSync()` listener (`navigationFramework.dart`)
  calls `triggerLiveSyncDebounced()` (800ms debounce) instead of `createSyncBackup()`, and does so
  unconditionally. It is not gated behind the legacy `syncEveryChange` setting, which only ever
  applied to the old whole-database mechanism and defaulted off on mobile — the gap the owner asked
  to close. That setting, and the toggle for it that lingered in Settings with no effect on this
  engine, went with the mechanism it belonged to.
- **App resume** — `main.dart`'s existing `OnAppResume` widget now also calls `runLiveSyncCycle()`.
- **Periodic + reconnect** — `startLiveSync()`, called once from the same `initState` block as the
  `watchAllForAutoSync` listener. Runs a 45s `Timer.periodic` that both drives the cycle and
  self-heals the WebSocket connection (attempts to (re)connect if signed in and no socket is
  open). Idempotent and safe to call before sign-in — every piece it starts no-ops on
  `selfHostedSession == null`.
- **WebSocket wake-up** — `_connectLiveSyncSocket()` in `liveSyncClient.dart`: connects to
  `<serverUrl with ws(s)>/sync-stream`, sends the auth message, and on a `changed` message calls
  `triggerLiveSyncDebounced()`. Exponential backoff on disconnect (1s, 2s, 4s, … capped at 60s),
  reset to 0 on any successful message. Not a hard dependency — the 45s timer means sync still
  works, just less instantly, if the socket never connects (blocked by a proxy, etc.).

## Reset Sync

The escape hatch. Upstream Cashew's released app ships a button with this exact name (the GitHub
source this fork was taken from does not, which is why it was missing here), and its documentation
recommends it as the first remedy for devices that won't converge. The bugs above are the argument
for having it: a change feed can reach a state no client can make progress against, and without
this the only fix is editing the server's SQLite by hand.

**What it does not do:** delete local data, on any device, or touch stored backups. It only clears
what the *server* knows.

`POST /sync/reset` (authenticated, `sync_routes.dart`):

1. `DELETE FROM sync_records WHERE user_id = ?`.
2. `UPDATE sync_state SET min_retained_seq = next_seq, next_seq = next_seq + 1`.
3. `syncHub.notify(userId)` so peers find out now rather than within 45s.
4. Returns `{"minRetainedSeq": N}`.

`next_seq` keeps climbing rather than rewinding to 1. Rewinding would leave every peer holding a
cursor *above* every newly issued seq, so they would pull nothing, forever — silently. Parking
`min_retained_seq` on top of the range instead means every peer's cursor is below it, so its next
pull gets `409 {"error":"rebootstrap","minRetainedSeq":N}`. That 409 is the only mechanism by which
a peer can learn its cursor is meaningless, and it matters for **writing as much as reading**: after
a reset every device has to re-push, and a device that never saw a 409 would still believe the
server already had its rows.

**The reserved seq in step 2 is load-bearing.** `min_retained_seq` lands on the old `next_seq` and
the next record issued sits strictly above it. Without that one-seq gap the first post-reset record
gets assigned exactly `min_retained_seq`, and since the resetting device resumes *at* that cursor
while pull is `seq > since`, the device's own re-upload is invisible to it — the feed looks empty
right after a reset. (Found by testing the endpoint with curl, not by reading it.)

Client side, `resetLiveSync()` in `liveSyncClient.dart` calls the endpoint, sets the pull cursor to
the returned `minRetainedSeq`, rewinds the push cursor to `DateTime(0)`, and runs a cycle to upload
the new baseline. Peers do the same thing on catching `SyncRebootstrapRequiredException`.

A reset racing an in-flight cycle would otherwise be silently undone — that cycle captured the old
cursors and writes them back when it finishes. A `_liveSyncGeneration` counter, bumped by
`resetLiveSync()` and compared before every cursor write, makes the stale cycle abandon its writes.

## Restore / import

Unchanged from the existing Stage 1 fix: a restore/import overwrites the database file wholesale
and stamps every row's `dateTimeModified` to "now" so it looks like a fresh edit to any
timestamp-diff consumer. Because the push scan is itself a `dateTimeModified >= cursor` query, this
means a restored dataset is automatically picked up and pushed on the very next cycle with **no
special-case code** — no cursor reset needed, unlike what the trigger-based design would have
required (clearing an outbox table). This was one of the concrete payoffs of the simplification
described above.

Restoring an old backup still overwrites newer data on every other device once it propagates —
genuinely destructive, and already gated behind a confirmation dialog in the existing restore
flow. Not modified in this stage.

## Migration from Stage 1

The `sync-*.sqlite` mechanism (`syncClient.dart`) is untouched and keeps running for manual use.

Because the push cursor defaults to `DateTime(0)` when never persisted, a device's very first live
sync cycle after upgrading automatically scans and pushes *every* existing row with its **real**
`dateTimeModified`, seeding the server with correct LWW timestamps across devices — no explicit
migration step was needed in code.

Deleting the old sync-file code path and server-side `sync-*.sqlite` files is left for later, once
every device in actual use has upgraded — an operator decision, not something to automate.

## Non-goals

- Field-level merge, CRDTs, or any change to LWW semantics beyond the clamp.
- Conflict recovery UI (archive, restore button).
- Per-change history on the server.
- Multi-user / shared data (Stage 4).
- Cross-table ordering guarantees. Merge is per row; only per-row ordering matters.
- Sync while the app is fully closed (backgrounded-terminated). Not attempted — Android would need
  `workmanager` at a 15-minute OS-imposed floor, iOS background refresh is unreliable at the OS's
  discretion, and true instant delivery would need a persistent foreground service with a
  permanent notification. Out of scope unless the user later asks specifically for closed-app
  notifications.

## Acceptance criteria

Server and app both build and static-analyze clean (`dart analyze` in `server/`, `flutter analyze`
in `app/` — both run this session, zero errors, only pre-existing unrelated warnings). The
following require a real deployment and manual, on-device testing (explicitly the user's to run,
not the agent's — browser/device testing was excluded from this session's scope):

- Airplane-mode test in `01-local-first-invariant.md` passes unchanged.
- Two devices, both offline, each adds several transactions; both go online; **both devices end up
  with every transaction from both.** No conflict is reported, because none occurred.
- A change on one device appears on another within a couple seconds on a home network (WebSocket
  path), and within ~45s with the WebSocket blocked (periodic-timer fallback).
- Force-killing the app mid-cycle and relaunching loses no data — verified by construction (writes
  live in the source tables, not a separate outbox that could desync), but worth confirming.
- A device offline for a long stretch catches up completely with no duplicate or missing rows on
  reconnect.
- Both devices edit the same transaction offline; after sync both converge to the same value and
  the losing device shows the conflict snackbar.
- A sync cycle that finds nothing new transfers well under 1 KB.
- Restoring a backup propagates to other devices with no special handling needed.
