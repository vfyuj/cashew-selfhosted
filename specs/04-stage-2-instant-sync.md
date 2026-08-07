# Stage 2 — Instant per-action sync

Adds real-time push on top of Stage 1's server. Does not replace Stage 1's snapshot-diff mechanism — that becomes the offline catch-up fallback. Read `01-local-first-invariant.md` first: none of this may ever block local writes.

## Why this is a separate stage from Stage 1

Stage 1 proves auth + a working transport end-to-end with the smallest possible change to the existing (well-tested) diff/merge logic. Real-time push is a genuinely different mechanism (persistent connections, server-side fan-out, ordering, reconnect handling) and mixing it into Stage 1 risks shipping neither reliably. Build on a working Stage 1, don't build both at once.

## Event schema

```
{
  eventId:   uuid,        // client-generated, for dedup
  userId:    string,      // server derives/verifies from session, never trusts client value
  deviceId:  string,
  table:     string,      // e.g. "transactions", "budgets", "delete_log"
  pk:        string,
  operation: "upsert" | "delete",
  payload:   object|null, // full row for upsert, null for delete
  timestamp: iso8601,     // client's dateTimeModified, used for LWW same as today
  sequence:  int|null     // server-assigned on receipt; null when client sends it
}
```

This is a formalization of the existing `SyncLog` concept as something emitted immediately at write-time, instead of reconstructed later by diffing two snapshots.

## Client: outbox

- Every local write (insert/update/delete on a synced table) appends one event to a **persisted local outbox table** — this must happen synchronously with the local write itself, not as an afterthought, so a crash immediately after a write can't lose the corresponding event.
- A background drainer sends queued events when connected (WebSocket if open, else batched HTTP as fallback — see below), marks them sent on server ack, retries with backoff on failure.
- Outbox size/age must never be bounded in a way that drops events. Per `01-local-first-invariant.md`, a week offline must not lose data — it just means a week of events to send on reconnect.

## Transport

- Primary: WebSocket, `wss://<server>/sync/stream`, authenticated with the Stage 1 session token (sent as the first message after connect, not as a URL query param, to avoid it landing in server logs).
- Fallback: `POST /sync/events` (batched array of events) for networks that block WebSocket. Client should prefer WS but must function correctly on this fallback alone — treat WS as a latency optimization, not a hard dependency.
- Heartbeat ping/pong to detect dead connections; exponential-backoff reconnect on drop.

## Server

- Durable, append-only, per-user event log (e.g. a table `events(sequence INTEGER PRIMARY KEY AUTOINCREMENT, userId, deviceId, table, pk, operation, payload, timestamp)`).
- On receiving an event: verify it belongs to the authenticated session's userId, persist it, assign `sequence`, ack the sender, then push it verbatim to every *other* currently-connected WebSocket session for that same userId. The sender's own other open connections (if any) also get it, for consistency.
- `GET /sync/events?since=<sequence>` — catch-up endpoint, returns all events for the authenticated user with `sequence > since`, ordered. This is what a reconnecting/offline device calls instead of Stage 1's full-snapshot download-and-diff.

## Client: applying incoming events

- One incoming event → one application of the existing merge logic (the `processSyncLogs`-equivalent function), same last-write-wins-by-timestamp semantics as today. Do not write a second, parallel merge implementation for the real-time path — both the WebSocket push path and the catch-up path must call the same apply function, so there is exactly one place conflict resolution happens and exactly one thing to trust.
- Client tracks its own last-applied `sequence` locally; on connect/reconnect, calls the catch-up endpoint with that value before (or in parallel with, carefully ordered) processing new live pushes, so nothing is double-applied or skipped.

## Conflict resolution

Unchanged from today: last-write-wins per row by `dateTimeModified`. This is adequate because Stage 2 is still single-owner-multi-device (per Stage 1's scope). Revisit if Stage 4 introduces genuinely concurrent multi-person edits to the same records — do not attempt to solve that here.

## Non-goals for this stage

- No change to conflict-resolution semantics.
- No multi-user/shared data (still Stage 4).
- No guaranteed message ordering across different `table`s beyond timestamp — only per-row ordering matters, since merge is per-row.

## Acceptance criteria

- A change made on one connected device appears on another connected device for the same user within ~2 seconds on a normal home network.
- Force-killing the app mid-outbox-backlog and relaunching does not lose queued events (verify via the outbox persistence, not just "it seemed fine").
- A device offline for a week, then reconnected, catches up completely and correctly via `since=<sequence>`, with no duplicate or missing rows.
- `01-local-first-invariant.md`'s airplane-mode test still passes unchanged.
- Falls back to working (if not instant) sync when WebSocket is blocked, using the HTTP batch endpoint.
