# Accounts, sessions and administration

Files: `server/lib/src/auth/` (`auth_service.dart`, `auth_routes.dart`, `auth_middleware.dart`,
`rate_limiter.dart`), `server/lib/src/admin/admin_routes.dart`, `server/bin/create_user.dart`.
Endpoint shapes are in [api.md](api.md); this page is the model behind them.

## Sessions

Opaque random tokens, not JWTs — revoking one is a `DELETE`, and there is no signing key to manage.
Stored **sha256-hashed**, so the database never holds a usable token; the client sends the raw value
as `Authorization: Bearer <token>`.

- Lifetime `sessionDuration` = 30 days, extended by `POST /auth/refresh` (sliding expiry).
- `requireAuth` resolves the header to an `AuthUser` and puts it in the request context. Handlers
  read `currentUser(request)` and **never** a user id from the URL or body — that is what makes it
  impossible to point a handler at somebody else's account.
- `requireAdmin` composes *after* `requireAuth` and re-reads `isAdmin` from the session on every
  request, so a demotion takes effect immediately. With no `requireAuth` ahead of it, it fails
  closed with `401`.

Changing a password revokes every session for that account and returns a fresh one, so the device
making the change stays signed in while the others are genuinely signed out.

## Passwords

bcrypt, run on a worker isolate — hashing on the event loop made one login freeze every other
request. Unbounded isolates would trade that stall for memory exhaustion under the 512 MB container
cap, so a concurrency gate holds four hashes in flight at once and queues the rest (a queued caller
costs a closure, not an isolate).

`minPasswordLength` is 8. Deliberately modest: a household server with known users, where a rule
strict enough to push people towards reused passwords makes things worse.

## Rate limiting

`rate_limiter.dart`, applied **per route** to the two endpoints that run bcrypt — `POST /auth/setup`
and `POST /auth/login` — at 10 attempts per 5 minutes per client, sliding window. Exhausted, it
answers `429` with `Retry-After`.

The threat it addresses is CPU, not guessing: without it anyone who can reach `/auth/login` can queue
unbounded bcrypt work with a loop and no credentials. It is deliberately *not* blanket middleware —
on `/auth/refresh` it would throttle ordinary sync traffic.

Client identity comes from the **rightmost** `X-Forwarded-For` entry, because nginx appends the peer
it actually saw and that last entry is the only one a client cannot forge. Trusting the header is the
default (the deployment model puts this server behind a proxy, where every request otherwise shares
one bucket); set `TRUST_PROXY_HEADER=false` when the server is exposed directly.

## First-run setup

A fresh instance has zero users. `GET /auth/setup-state` reports that, so the app shows "set up this
server" instead of a sign-in form, and `POST /auth/setup` creates the first account with
`is_admin = 1`. The count check and the insert share one transaction, so two simultaneous requests
cannot both believe they are first, and the endpoint answers `409` forever after.

This means **anyone who reaches the instance before the operator registers can claim the
administrator account** — the same exposure Nextcloud and Immich accept, weighed and accepted. The
operational consequence (register right after `docker compose up`) is in `DEPLOYMENT.md`.

## Provisioning and roles

Administrators add everyone else through `/admin/users`, which generates a temporary password shown
exactly once and never stored in plaintext. If it is lost, the administrator issues a new one.

`shareHousehold` at creation time puts the new account in the caller's dataset. It is settable
**only at creation**: moving an account that already holds data into a household would merge two sets
of rows sharing no primary keys, duplicating every wallet, category and transaction.

Guard rails, all `409`: you cannot delete your own account (it would drop you out of the only session
that could undo it — demote and delete from another admin account), and you cannot remove the last
administrator, which would make every admin-only endpoint permanently unreachable including the one
that grants admin.

**`is_admin` and dataset membership are independent axes.** The role says who provisions accounts;
membership says whose data you see. An administrator can sit in a dataset of their own; a
non-administrator can share the administrator's. Never use one as a proxy for the other.

## Rescue path

`server/bin/create_user.dart` stays in the image for a forgotten administrator password:

```bash
docker compose exec app /app/bin/create_user your@email.tld
```

Creates the account if the email is new, or issues a fresh temporary password if it exists, and
prints it either way. `--admin` grants the role; the very first account always gets it.

---

Why: `specs/03-stage-1-kill-google.md` (replacing Google Sign-In), `specs/05-accounts-and-admin.md`
(setup wizard, administration, the accepted setup-window exposure),
`specs/06-shared-household-data.md` (datasets).
