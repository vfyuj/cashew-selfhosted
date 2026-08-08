# Stage 2 — Incremental sync (triggered, not real-time)

Adds a lightweight incremental path on top of Stage 1's snapshot-diff sync. Does **not** replace it — full snapshot-diff sync stays exactly as it is today, unconditionally, as the disaster-recovery fallback and each device's own backup. Read `01-local-first-invariant.md` first: none of this may ever block local writes.

**This file's name says "instant" — that description is deliberately wrong now.** The first attempt at this stage built real-time/event-push sync (persistent WebSocket, live fan-out) and it made things worse, not better. See "Postmortem: the reverted attempt" below before proposing anything with a persistent connection again. The filename is kept for link stability; the design is not what it used to say.

## Status (last updated 2026-08-08)

- [ ] Server: `sync_changes` table + `POST/GET /sync/changes` endpoints (Step 1 below).
- [ ] Client: push side — compute local delta, upload to `/sync/changes` (Step 2).
- [ ] Client: pull side — fetch delta since last-applied sequence, merge via `processSyncLogs` (Step 3).
- [ ] Regression pass: sign-in, account creation, existing full-snapshot sync/backup UI all still work (Step 4, owner-run — see "Testing & verification workflow" in `CLAUDE.md`).
- [ ] Two-device race scenario verified (Step 4, owner-run — see Acceptance criteria).

Nothing above is done. A prior attempt reached a broken, uncommitted state and was reverted (not merged, not pushed) rather than fixed — see the postmortem below for why redoing it from this plan was judged faster than debugging it forward.

## Why sync is slow today

Traced directly from `upstream/budget/lib/struct/syncClient.dart` (unchanged in this fork except swapping the Drive transport for the self-hosted one, per `03-stage-1-kill-google.md`):

Each device keeps one full SQLite snapshot of its own local database on the server, named `sync-<deviceId>.sqlite`, re-uploaded wholesale on every trigger (`createSyncBackup`). Pulling in changes (`_syncData`) lists every device's snapshot file and, for each one whose server-side `modifiedTime` is newer than the last time *this* device synced with *that specific device* (a per-device watermark), **downloads that peer's entire snapshot file**, opens it as a second local Drift database, and runs a set of `getAllNew<Table>(lastSynced)` queries against it to extract just the rows newer than the watermark. Those extracted rows become `SyncLog` entries, and `database.processSyncLogs(syncLogs)` merges them into the live local database, last-write-wins by `dateTimeModified`.

So the existing mechanism already has a real per-device skip (a peer with no new rows is never downloaded) and a real per-row diff (only rows newer than the watermark are extracted and merged) — it is not naively "re-download and replay everything." The actual cost is: **when a peer has changed at all, the entire peer database file is downloaded and opened just to pull out however many rows actually changed** — one new transaction on a phone with years of history means downloading and parsing that phone's whole database on every other device before continuing.

That single fact is the entire target of this stage: let a device fetch *only the changed rows* instead of the whole peer file, when there's a cheap way to do that. Everything else about today's mechanism — the trigger points, the per-row LWW merge, the full snapshot as source of truth and backup — is sound and is being kept.

**Empirical note (owner testing, 2026-08-08)**: comparing "sync on every change" against a vanilla Cashew instance vs. this fork's Stage 1 (self-hosted) sync, the vanilla/Google Drive loading bar is very slow and clearly visible; this fork's is barely visible. Both are doing the same full-snapshot-per-change work today (Stage 1 hasn't built the incremental path yet), so the gap isn't explained by anything in this codebase — it's almost certainly Google Drive's API latency (OAuth token handling, real internet round-trips to Google's servers) versus a self-hosted server on the same LAN/localhost. Two implications for this stage: (1) don't assume "slow" reports are about payload size alone — network path matters at least as much; (2) this fork's sync may already feel acceptably fast for small-to-medium datasets purely from being self-hosted, even before this stage's work lands — the incremental path mainly matters as transaction history grows large enough that whole-file transfer cost dominates even on a fast LAN. Worth re-measuring with a realistically-sized database (years of transactions, not a fresh test account) before treating this stage as urgent.

## Postmortem: the reverted attempt

An earlier session implemented something close to the original version of this file's design: a persisted client-side outbox table (new Drift schema, full `tables.g.dart` regeneration), a WebSocket transport, and a server-side event log with live fan-out to connected sessions. It reached an uncommitted, unpushed state (~4,300 lines changed) with several problems reported by the owner after testing it locally:

1. Incoming changes only became visible after a full page reload — the "instant" part of instant sync didn't actually work, defeating the point of the persistent connection it paid for in complexity.
2. Unrelated UI broke (the "Add Account" button on `accountsPage.dart` stopped working) — a regression nothing in the sync design should have touched, most likely fallout from the size and reach of the diff (schema changes cascading through generated code, widget files touched that didn't need to be).
3. The restore-propagation race reappeared in a new form: if device A restored a backup and synced, then device B made an independent edit *before* pulling A's restore, then A reloaded — A's reload could roll forward past B's edit without it, effectively losing B's change from A's perspective. (Stage 1 already fixed the *original* version of this bug for the snapshot-diff path — see `03-stage-1-kill-google.md`'s Status notes — but the new event-log path apparently had its own, separate bug here.)
4. The size of the diff, relative to the value delivered and the number of new bugs, made the whole change harder to trust than to redo.

The owner's read, which this plan follows: don't rewrite the transport, add to it. Reuse vanilla's proven snapshot-diff/merge logic as-is; add a narrow, additive incremental path; keep the diff small enough to actually review. Nothing here should require regenerating `tables.g.dart` or introducing a persistent connection.

## Design

### What's added

- **One new server-side table**: an append-only, per-user change log (name it `sync_changes`) — `(sequence INTEGER PRIMARY KEY AUTOINCREMENT, userId, deviceId, tableName, pk, operation, payload, dateTimeModified, receivedAt)`. Same shape as the `SyncLog`/event concept already in this codebase, just persisted directly instead of reconstructed from a downloaded file.
- **Two new server endpoints**, additive, alongside (not replacing) the existing `/sync/files/*` routes in `server/lib/src/sync/sync_routes.dart`:
  - `POST /sync/changes` — client uploads a batch of its own new/changed rows (same `SyncLog` shape already used client-side) since its own last successful push. Server verifies `userId` from the session (never trusts a client-supplied value, same rule as every other route here), appends each row to `sync_changes`, assigns `sequence`.
  - `GET /sync/changes?since=<sequence>` — returns every row in `sync_changes` for this user with `sequence > since`, from **any** device, ordered. One unified per-user log, not per-device — the client only needs to remember one watermark (the highest `sequence` it has applied), not a map of per-device timestamps like the snapshot-file path needs.
- **Client-side**: no new local database table, no schema change, no `tables.g.dart` regeneration. The two new watermarks this needs (`lastPushedChangeTimestamp`, `lastAppliedChangeSequence`) are stored in `sharedPreferences`, exactly like `dateOfLastSyncedWithClient` already is today. This is a deliberate, load-bearing constraint, not an oversight — see the postmortem above for what a schema-touching version of this cost last time.

### What's unchanged

- `SyncLog`, `processSyncLogs`, `DeleteLog`, and every `getAllNew<Table>(lastSynced)` query — reused as-is, in both the existing full-snapshot path and the new incremental path. **There is exactly one merge function.** Both paths produce a `List<SyncLog>` and hand it to the same `database.processSyncLogs(syncLogs)` call. This is what makes the design safe against the class of bug in postmortem point 3: since merge is per-row, last-write-wins by `dateTimeModified`, applying the same row twice or receiving rows out of order can never move a row backward in time — it's idempotent and commutative by construction, regardless of which transport delivered which row, or in what order the two transports run.
- The full snapshot file upload (`createSyncBackup`) and the existing `/sync/files/*` endpoints — untouched, called exactly as today, on every trigger, unconditionally. This remains each device's own backup and the fallback for any device the incremental log can't serve (see below).
- Every existing sync trigger point (pull-to-refresh in `pullDownToRefreshSync.dart`, `runAllCloudFunctions` calls in `navigationFramework.dart` / `navigationSidebar.dart`, the debug-page manual trigger). No new trigger mechanism, no timer, no persistent connection. "Triggered by user action" means literally the same actions that already trigger sync today.

### Push flow (upload), on every existing trigger

1. Query the *live local* `database` (not a downloaded peer snapshot) for everything changed since `lastPushedChangeTimestamp`, using the exact same `getAllNew<Table>(lastSynced)` functions `_syncData` already calls against `databaseSync` today — just pointed at the local database instead. This needs no new query logic.
2. POST the resulting `SyncLog` list as JSON to `/sync/changes`.
3. On success, set `lastPushedChangeTimestamp` to the moment the push started (same "capture the timestamp before the read, not after" pattern `_syncData` already uses via its `syncStarted` variable, so a write that lands mid-push isn't missed next time).
4. Still call `createSyncBackup()` exactly as today, unconditionally, in parallel/sequence with the above — the full snapshot upload is not gated on or replaced by this.

### Pull flow (download), on every existing trigger

1. Call `GET /sync/changes?since=<lastAppliedChangeSequence>`.
2. If the server can serve it (see retention below): feed the returned rows directly into `database.processSyncLogs(syncLogs)`, update `lastAppliedChangeSequence` to the max sequence received. No file download, no secondary database, for whichever peers' changes arrived this way.
3. For the existing per-device full-snapshot loop in `_syncData`: keep it exactly as-is, but it now only needs to run for a peer device when the incremental path didn't already cover it — i.e., treat incremental catch-up as the first attempt, and fall back to that specific device's full-snapshot download only when needed (see next section). A device syncing for the very first time, or one whose gap is older than the log's retention, falls back for everything, which is exactly today's behavior — nothing gets worse for that case, it just doesn't get better yet either.

### Fallback conditions (when the full snapshot path is still used)

- First sync ever for this account/device (no watermark yet).
- `GET /sync/changes?since=...` reports the requested range is no longer available (see retention).
- The incremental request fails for any reason (network, server error) — fail open to the proven path rather than blocking sync.

### Retention

No pruning in v1. A household's transaction volume is small enough that even years of `sync_changes` rows is not a real storage concern, and not pruning removes an entire class of "did I keep enough history" bugs before they can exist. Revisit only if `sync_changes` table size actually becomes a measured problem on the operator's server — do not pre-build pruning logic speculatively.

## Non-goals for this stage

- No persistent connection (WebSocket or otherwise), no live push, no "appears on another device within N seconds" latency target. Sync remains something the user triggers, same as today — it's just fast once triggered.
- No client-side outbox table, no write-time hook on every insert/update/delete. The delta is computed lazily at trigger time by querying `dateTimeModified`, not captured eagerly at write time.
- No local database schema changes.
- No change to conflict-resolution semantics — still last-write-wins per row by `dateTimeModified`.
- No multi-user/shared data (Stage 4).
- No pruning/retention logic (see above).

## Step-by-step plan

Each step should be independently shippable and testable before starting the next — keep diffs small and reviewable, per the postmortem.

1. **Server: `sync_changes` table + endpoints.** Add the table and the two routes to `server/lib/src/sync/sync_routes.dart` (or a sibling file, mirroring its existing structure — per-user scoping via `currentUser(request).id`, same pattern as the file routes). No client changes yet. Test with `curl` end-to-end (push a fake batch, pull it back with `since=0`, confirm ordering and per-user isolation), same style as Stage 1's curl testing.
2. **Client: push side.** Add the local-delta query + `POST /sync/changes` call, wired into the same call site as `createSyncBackup()`. Store `lastPushedChangeTimestamp` in `sharedPreferences`. `createSyncBackup()` itself is untouched.
3. **Client: pull side.** Add the `GET /sync/changes` call and wire its results into the existing `database.processSyncLogs(syncLogs)` call in `_syncData`, before/alongside the existing per-device full-snapshot loop, with the fallback conditions above. Store `lastAppliedChangeSequence` in `sharedPreferences`.
4. **Regression + scenario testing — owner-run.** Per "Testing & verification workflow" in `CLAUDE.md`: agent builds and starts the app locally and hands over the URL and credentials; the owner runs the acceptance criteria below themselves.
5. **Update this file's Status checkboxes** as each step lands, instead of re-describing status in prose.

## Acceptance criteria

- Existing, unrelated functionality is unaffected: signing in, creating an account (`bin/create_user.dart` flow through the UI), and the existing full-snapshot sync/backup UI all still work exactly as before. (This directly targets postmortem point 2 — it must be checked explicitly, not assumed from a green build.)
- A change made on one device becomes visible on another device after that other device's *next normal trigger* (pull-to-refresh, foreground, etc.) — still no reload required beyond what today's full-snapshot sync already needs, and no worse. (Targets postmortem point 1: confirm applying an incremental delta doesn't silently require a page reload where full-snapshot sync doesn't.)
- **Two-device race, the exact scenario the owner hit**: Device A restores a backup or imports a `.sqlite` file (bumping `dateTimeModified` per the Stage 1 fix) and syncs. Before device B has pulled that restore, device B independently creates a new transaction and syncs (pushes its own change, pulls what's available). Confirm: B ends up with **both** the restored data and its own new transaction — neither is lost. A's next sync also ends up with both. (Targets postmortem point 3 directly — this must be a manual test step, not inferred from the merge logic being "obviously" correct.)
- A device that has been offline long enough to fall outside the incremental path (or is syncing for the first time) still catches up completely and correctly via the unchanged full-snapshot fallback — no duplicate or missing rows.
- `01-local-first-invariant.md`'s airplane-mode test still passes: no new synchronous network call was added to app startup (the new watermarks are `sharedPreferences` reads, same cost as the existing `dateOfLastSyncedWithClient` read).
- The diff for this stage is reviewable — if it starts approaching the size of the reverted attempt, stop and reconsider scope before continuing.
