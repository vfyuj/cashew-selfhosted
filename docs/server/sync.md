# Sync: the change feed

Files: `server/lib/src/sync/` (`sync_routes.dart`, `sync_stream_routes.dart`, `sync_hub.dart`).
Request and response shapes are in [api.md](api.md); the client half is in
[../app/sync-client.md](../app/sync-client.md).

One transport, scoped to the **dataset**, so every member of a household follows one stream:
`/sync/push` and `/sync/pull`, small JSON deltas, with `/sync-stream` as a wake-up.

There used to be a second — `/sync/files*`, whole SQLite files — kept as a fallback for a device's
first sync or one that had been away too long. It was removed in 1.3.x: neither case actually needed
it (a stale cursor is handled by the `409 rebootstrap` below), and keeping two mechanisms meant two
hand-written lists of every syncable table, which had already drifted apart. See
`specs/04-stage-2-instant-sync.md`.

## The feed

One row of `sync_records` per record — **not** per change. Applying only the newest version of a row
is equivalent to replaying its whole history under last-write-wins, so the table is bounded by data
size and never by sync history.

`sync_state.next_seq` issues a per-dataset sequence number, assigned inside the same transaction as
the write it numbers. sqlite3's synchronous API on Dart's single-threaded event loop is what makes
that race-free — and it is also why the server must stay one process.

## Push

Last-write-wins by `modifiedAt`:

| Incoming vs stored | Result |
|---|---|
| no stored row | insert, new `seq`, `appliedCount++` |
| newer | update, new `seq`, `appliedCount++` |
| equal timestamp, same payload | no-op (a retried push or an echo of a row this device just pulled) |
| equal timestamp, different payload | `conflictCount++` — a genuine same-millisecond collision |
| older | `conflictCount++`, dropped |

A `modifiedAt` more than two minutes ahead of server time is clamped down to server time, so a fast
client clock cannot win every future conflict forever.

**Peers are woken only when `appliedCount > 0`.** Devices re-scan by timestamp and routinely re-send
rows the server already has; waking everyone on a no-op push once let a single device stuck in a
failing cycle drive the whole fleet into a permanent ~1 Hz sync storm.

## Pull

`GET /sync/pull?since=<seq>` returns changes with `seq > since`, ordered, plus `nextCursor` and
`hasMore`. `limit` defaults to 500 and is clamped to 1–2000.

If `since` is below `min_retained_seq`, the answer is
**`409 {"error":"rebootstrap","minRetainedSeq":<n>}`**. The client cannot catch up incrementally and
must take a snapshot, then resume from that cursor.

## The wake-up socket

`syncHub` is an in-memory `datasetId → open sockets` registry. After an applied push it sends
`{"type":"changed"}` to every socket for that dataset — every device of every member, including
other devices of the pusher.

The message carries **no data**. The client's only reaction is an ordinary pull, so a dropped,
duplicated or reordered notification cannot lose or double-apply anything; the socket is an
optimisation over polling, never the transport.

Being process-local, it is correct only because the server is a single Dart process. Registration is
keyed by dataset, matching `notify` — keying it by user id would still compile and still work for a
solo account, while silently leaving the rest of a household on the poll interval and looking like
"sync is slow" rather than broken.

Authentication is by first message, not header — see [api.md](api.md#get-sync-stream).

## Reset

`POST /sync/reset` deletes the dataset's `sync_records`, then parks `min_retained_seq` on top of
`next_seq` and burns one sequence number as a barrier:

- `next_seq` keeps climbing rather than rewinding to 1. Every other device holds a cursor below the
  new floor, so its next pull gets the `409` and rebootstraps — that `409` is the only way a peer
  learns its cursor means nothing, and it matters for writing as well as reading, because after a
  reset every device must re-push.
- The burned number matters because pull is `seq > since`: without the gap the first post-reset
  record would land exactly on the resetting device's own cursor and be invisible to it.

Stored backups and every device's local database are untouched.

---

Why, plus the reverted first attempt at real-time push: `specs/04-stage-2-instant-sync.md`. Read it
before changing anything here, and keep diffs small — that is the file's own lesson.
