# Server HTTP API

Current state, read from `server/lib/src/`. Every route the server answers is listed here — a test
(`server/test/api_docs_test.dart`) fails the build if a route exists in code but not on this page.

**Auth** — `none`: open. `session`: `Authorization: Bearer <sessionToken>`, resolved by `requireAuth`
(`auth/auth_middleware.dart`), which rejects with `401`. `admin`: additionally `requireAdmin`, which
re-reads the role from the session on every request and rejects with `403`.

**Scope** — which data the request reaches. `user`: the caller's own. `dataset`: the household's,
shared by every member. `instance`: the whole deployment, the same answer for everyone. The split is
deliberate, not drift; see [storage.md](storage.md).

| Route | Auth | Scope | Behaviour |
|---|---|---|---|
| `GET /health` | none | — | `{"status":"ok","version":"1.0.0-beta.N"}`. Version read from the served web build — how a redeploy is confirmed. |
| `GET /sync-stream` | first message | dataset | WebSocket wake-up. See below. |
| `GET /auth/setup-state` | none | — | `{"needsSetup": <instance has zero users>}`. |
| `POST /auth/setup` | none | — | Creates the first account, which becomes administrator. `409` once any account exists. Rate-limited. |
| `POST /auth/login` | none | — | `{email, password}` → session. `401` on bad credentials. Rate-limited. |
| `POST /auth/refresh` | token in body | — | `{sessionToken}` → `{sessionToken, expiresAt}`, sliding expiry. `401` if expired. |
| `POST /auth/logout` | token in body | — | `{sessionToken}` → `200`. Always `200`, even for an unknown token. |
| `GET /auth/me` | session | user | The caller's own account JSON. |
| `PATCH /auth/me` | session | user | `{name?, email?}`. `400` if neither, `409` if the email is taken. |
| `POST /auth/me/password` | session | user | `{currentPassword, newPassword}` → a fresh session. Signs out every other device. `422` (not `401`) if the current password is wrong. |
| `GET /sync/files` | session | dataset | Snapshot listing: `[{deviceId, filename, modifiedTime, size}]`. |
| `PUT /sync/files/<filename>` | session | dataset | Uploads a device's SQLite snapshot (binary body). |
| `GET /sync/files/<filename>` | session | dataset | Downloads it. `404` if absent. |
| `DELETE /sync/files/<filename>` | session | dataset | Removes it. |
| `POST /sync/push` | session | dataset | Row-level changes up. See below. |
| `GET /sync/pull` | session | dataset | Row-level changes down. See below. |
| `POST /sync/reset` | session | dataset | Drops the dataset's change feed. See below. |
| `GET /backup/list` | session | **user** | `[{filename, modifiedTime, size}]`. |
| `PUT /backup/<filename>` | session | **user** | Uploads a backup (binary body). |
| `GET /backup/<filename>` | session | **user** | Downloads it. `404` if absent. |
| `DELETE /backup/<filename>` | session | **user** | Removes it. |
| `GET /attachments/list` | session | dataset | `[{filename, modifiedTime, size}]`. |
| `PUT /attachments/<filename>` | session | dataset | Uploads a receipt photo or picked file. |
| `GET /attachments/<filename>` | session | dataset | Downloads it. `404` if absent. |
| `DELETE /attachments/<filename>` | session | dataset | Removes it. |
| `GET /rates` | session | **instance** | `{rates, overrides, fetchedAt}`, USD-based. `503` if the server has never managed to fetch. See [rates.md](rates.md). |
| `PUT /rates/overrides/<currency>` | admin | instance | `{rate: <positive number>}`. `400` on zero, negative or non-numeric. |
| `DELETE /rates/overrides/<currency>` | admin | instance | Falls that currency back to the fetched value. |
| `GET /admin/users` | admin | instance | `{users: [...]}`. |
| `POST /admin/users` | admin | instance | `{email, name?, isAdmin?, shareHousehold?}` → `201 {user, temporaryPassword}`. `409` if the email is taken. |
| `POST /admin/users/<id>/password` | admin | instance | Issues a new temporary password and signs that account's devices out. |
| `PATCH /admin/users/<id>` | admin | instance | `{isAdmin: bool}`. `409` on removing the last administrator. |
| `DELETE /admin/users/<id>` | admin | instance | `409` on self, or on the last administrator. Also deletes stored files — see below. |

Any file route rejects a filename containing a path separator or `..` with `400`; the store never
takes a client-supplied path (`storage.dart`).

## Mounting and middleware order

`server/lib/src/api.dart` composes the whole surface. Two details that surprise people:

- **Two routers share `/auth`.** The public one is mounted first (`setup-state`, `setup`, `login`,
  `refresh`, `logout`); anything it does not recognise falls through to the authenticated account
  router (`me`, `me/password`), because a nested `Router` returns `routeNotFound` rather than a `404`.
- **`/rates` and `/rates/overrides` are two mounts, not one router.** Mount middleware runs before
  the nested router looks at the path, so an admin-gated router sharing the `/rates` prefix would
  answer an ordinary member's read with `403`. The longer prefix is registered first, because the
  first match wins.
- **`/sync-stream` is registered directly, not mounted.** A single-segment mount with no sub-path
  does not reliably match its own root in `shelf_router` 1.1.4 — it fell through to the SPA
  catch-all and logged a misleading `[200]`.

Everything the router does not match falls through a `Cascade` to the web handler, which serves the
compiled Flutter build (`web_handler.dart`). One origin, one port, so there is no CORS layer.

## Session tokens

Opaque random strings, stored sha256-hashed. The client sends the raw token as a `Bearer` header;
`refresh` extends expiry and returns the same or a new token. See [auth.md](auth.md).

## `POST /sync/push`

```jsonc
{ "deviceId": "...", "changes": [
  { "table": "transactions", "pk": "...", "deleted": false,
    "modifiedAt": 1723459200000, "payload": { /* the row */ } }
] }
```

→ `{"serverTime": <epoch ms>, "conflictCount": <n>}`.

Last-write-wins by `modifiedAt`. A timestamp more than two minutes ahead of server time is clamped
down, so a fast client clock cannot win every future conflict. A change older than what is stored
counts as a conflict and is dropped; one with an equal timestamp is a no-op unless the payload
differs. Peers are woken only when something actually changed — see [sync.md](sync.md) for why that
matters.

## `GET /sync/pull?since=<seq>&limit=<n>`

`limit` defaults to 500, clamped to 1–2000. →
`{"changes": [...], "nextCursor": <seq>, "hasMore": <bool>, "serverTime": <epoch ms>}`, ordered by
`seq`, each change shaped like a push change plus its `seq`.

**`409 {"error":"rebootstrap","minRetainedSeq":<n>}`** when `since` is below what the server still
retains. The client must fall back to a snapshot sync and resume from `minRetainedSeq`.

## `POST /sync/reset`

Deletes the dataset's `sync_records` and parks `min_retained_seq` on top of `next_seq`, so every
other device's next pull gets the `409` above and rebootstraps. → `{"minRetainedSeq": <n>}`.

Stored backups and every device's local database are untouched; this clears only what the server
knows.

## `GET /sync-stream`

WebSocket. A browser handshake cannot carry an `Authorization` header, so the socket authenticates
with its first message — `{"type":"auth","token":"<sessionToken>"}` — and never a URL query
parameter, which would land the token in reverse-proxy logs. The server replies `{"type":"ready"}`,
or closes with code `4001`.

Afterwards the server only ever sends `{"type":"changed"}`, carrying no data: the client's sole
reaction is an ordinary pull, so a dropped, duplicated or reordered message cannot lose or
double-apply anything. Ping interval 30s.

## Deleting an account

`DELETE /admin/users/<id>` cascades sessions and dataset membership through foreign keys, then
deletes that user's `backup/` directory unconditionally. Sync snapshots and attachments belong to the
dataset and are deleted **only when the removed account was its last member** — removing one member
of a household must not delete the household's data.

---

Why any of this is shaped this way: `specs/03-stage-1-kill-google.md` (auth, snapshot sync, backup,
attachments), `specs/04-stage-2-instant-sync.md` (the change feed), `specs/05-accounts-and-admin.md`
(setup and administration), `specs/06-shared-household-data.md` (datasets).
