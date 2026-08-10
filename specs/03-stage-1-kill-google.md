# Stage 1 — Kill Google

First real, polished release. Every Google/Firebase touchpoint for auth, sync, and backup is replaced. Read `01-local-first-invariant.md` before touching any of this.

## Status (last updated 2026-08-08)

Check items off as they're completed. Notes are kept short — see git history / code comments for detail, not this list.

### Server (`/server`)
- [x] Auth: `bin/create_user.dart` CLI, `users`/`sessions` tables (sqlite3), bcrypt hashing, opaque sha256-hashed-at-rest session tokens, sliding-expiry `/auth/refresh`. `POST /auth/login`, `/auth/refresh`, `/auth/logout`.
- [x] Sync: `GET /sync/files`, `PUT/GET/DELETE /sync/files/:filename`, scoped server-side to the authenticated user.
- [x] Backup: `GET /backup/list`, `PUT/GET/DELETE /backup/:filename`, separate namespace from sync.
- [x] End-to-end tested via curl (login → sync upload/list/download → backup upload/list/download → refresh → logout, path-traversal rejection) against both the local binary and the built Docker image.
- Note: password hashing uses **bcrypt**, not argon2id (spec allows either) — avoids native/FFI deps in the Docker image.

### App (`/app`)
- [x] `lib/struct/selfHostedClient.dart`: session model (persisted via `sharedPreferences`, no network call at startup — local-first invariant preserved), `SelfHostedClient`, login/refresh/logout.
- [x] `lib/struct/syncClient.dart`: Drive `appDataFolder` calls replaced by `SelfHostedClient` calls; `SyncLog`/`processSyncLogs`/`DeleteLog` merge logic **untouched**.
- [x] `lib/widgets/accountAndBackup.dart` + `lib/pages/accountsPage.dart`: sign-in UI (email/password/server-URL), own-server backup create/list/restore/delete.
- [x] WebDAV/Nextcloud backup target (client-side, optional, alternative to own-server backup — sync is unaffected and always uses the self-hosted server). `BackupTransport` interface (`lib/struct/selfHostedClient.dart`) abstracts "own server" vs "WebDAV" so the backup UI/functions in `accountAndBackup.dart` don't branch on which is active. `lib/struct/webdavClient.dart`: hand-rolled PROPFIND/GET/PUT/DELETE/MKCOL client (no new dependency). `accountsPage.dart`: `BackupDestinationSettings` widget — dropdown + WebDAV URL/username/password/folder fields, shown once signed in. `flutter analyze` clean, `flutter build web --release` and `flutter build apk --debug` both succeed. **Not yet tested against a real WebDAV/Nextcloud server** — no server reachable in this session. Known caveat: PROPFIND/MKCOL are non-simple CORS requests; Nextcloud needs CORS configured for the *web* build to reach it directly (Android is unaffected, no CORS there).
  - [ ] Verify against a real Nextcloud (or other WebDAV) instance once the operator's server is reachable.
- [x] Translations: new strings added to **English only** (`assets/translations/generated/en.json`); other 46 languages need the CSV pipeline re-run (needs maintainer's Google Sheet access) and will show English fallback until then.
- [x] Restore/import safety and cross-device propagation fix, found via real multi-window testing: restoring a backup or importing a `.sqlite` file now (1) takes a best-effort backup of the current state first, under its own `pre-restore-<device>-<timestamp>.sqlite` filename, so a wrong pick or change of mind isn't unrecoverable (`createSafetyBackupBeforeOverwrite` in `accountAndBackup.dart`), and (2) stamps every row's `dateTimeModified` to now on next launch (`FinanceDatabase.bumpAllModifiedTimestampsForResync` in `tables.dart`, invoked from the existing `databaseJustImported` handling in `initializeSettings()`). (2) fixes a real bug, not a Stage 2 gap: restored rows kept their original (often old) `dateTimeModified`, so peers' timestamp-diff pull (`getAllNew*(lastSynced)`) silently skipped them as "not new" -- the restore would never reach other devices, only writes made after it would. This is a gap in the diff/merge logic itself, inherited unchanged from upstream (see "Sync transport" below). Because the fix works by making the diff/merge logic see restored rows as ordinary new writes, it is inherited for free by Stage 2's incremental path too (both paths query the same `getAllNew*(lastSynced)`-style functions) — see `04-stage-2-instant-sync.md`.
- **Deliberate scope decision**: `signInGoogle`/`googleUser`/Drive OAuth code was **not deleted** — kept but fully decoupled from `hasSignedIn`/auth state, since it's still used by two unrelated opt-in features out of this stage's scope (receipt/attachment upload to the user's own Drive in `uploadAttachment.dart`, Gmail auto-transaction scanning in `autoTransactionsPageEmail.dart`). Both off by default. Flag if full Google removal is wanted later.
- Firebase shared-budget feature (`shareBudget.dart`, `firebaseAuthGlobal.dart`) otherwise untouched — out of scope (Stage 4).
- [x] Firebase initialization is **lazy**. `main()` used to `await Firebase.initializeApp()` before anything else. The note here previously called that "local SDK init, not a network call" — that was wrong on web: `firebase_core_web`'s `initializeApp` injects `https://www.gstatic.com/firebasejs/<version>/firebase-*.js` script tags and awaits them, so launching the web build required reaching Google's CDN and disclosed every user's IP to Google on every load. It is now `ensureFirebaseInitialized()` in `firebaseAuthGlobal.dart` — a memoized, non-throwing init called from `firebaseGetDBInstance()` / `firebaseGetDBInstanceAnonymous()`, which are the only two doors to Firebase in the app. Everything that touches `FirebaseAuth.instance` or `FirebaseFirestore.instance` is downstream of one of them (verified by grep). A failed init returns false instead of throwing and is retried on the next opt-in use, so being offline degrades those features rather than erroring. Note this is *not* the same change as removing the hand-written SDK `<script>` block from `web/index.html` — that was a duplicate load against upstream's own Firebase project, removed separately.

### Remaining for this stage
- [ ] Manual migration procedure (last Google backup → verify → switch → restore → verify) — inherently a manual user action, not code. See "Migration" section below.
- [ ] Acceptance criteria verification: two-device test, airplane-mode test, network inspection for zero Google calls, web-reload-while-signed-in test. This is the owner's to run against a locally-started instance (see "Testing & verification workflow" in `CLAUDE.md`) — not something the agent should attempt to simulate itself.
- [x] Icon/app-name finalized (tracked in Stage 0 status).

## Scope clarification (do not over-build)

Each person gets their own private multi-device sync — this mirrors today's one-Google-account-per-person model exactly. There is **no shared/merged household data in this stage**. Two accounts on the same server are fully isolated from each other. Shared data is Stage 4, deliberately deferred.

## Auth

> **Superseded in part by `05-accounts-and-admin.md`.** CLI-only provisioning was replaced by a first-run setup wizard plus in-app administration. The session model, hashing choice and endpoint shapes below are unchanged and still authoritative; the provisioning story is not. `bin/create_user.dart` survives as the operator's rescue path for a forgotten administrator password.

No open public registration. This is a household server with a known, small set of users — an endpoint letting anyone create an account on a running instance is unnecessary attack surface for something meant to be publicly forkable and self-hosted by non-experts.

- Sessions use **opaque random tokens stored server-side** (session table: token hash, userId, createdAt, expiresAt), not JWTs — simpler to revoke and audit at this scale, no signing-key management.
- Password hashing: a vetted algorithm via a maintained package (argon2id or bcrypt) — never hand-rolled.

### Endpoints
- `POST /auth/login` `{email, password}` → `{sessionToken, expiresAt, user}`
- `POST /auth/refresh` `{sessionToken}` → `{sessionToken, expiresAt}` (sliding expiry)
- `POST /auth/logout` `{sessionToken}` → `200`

See `05-accounts-and-admin.md` for the setup, profile and administration endpoints added on top of these.

### App-side behavior
- Sign-in uses email/password plus a **server URL field** on native builds (not hardcoded — required for the public-fork goal, and for the owner's own multi-environment testing). On web the app is served from its own API's origin, so the field is hidden behind an "advanced" disclosure.
- Per `01-local-first-invariant.md`: failed/expired session never blocks the UI. Silent background re-auth using the refresh token, same non-blocking pattern as today's `signInGoogle(silentSignIn: true, waitForCompletion: false)`.

## Sync transport (still snapshot-diff — only the transport changes)

Deliberately mirrors today's Google Drive appDataFolder calls closely, so the existing diff/merge logic (`SyncLog`, `processSyncLogs`, `DeleteLog`) needs minimal changes — only the code that currently constructs a `drive.DriveApi` and calls `.files.list/.get/.create/.delete` against `appDataFolder` gets swapped for calls to these endpoints. The per-table "new since timestamp" queries, the tombstone handling, and the last-write-wins merge stay exactly as they are today.

### Endpoints (all scoped server-side to the authenticated user — never trust a client-supplied user id)
- `GET /sync/files` → `[{deviceId, filename, modifiedTime, size}]` (equivalent to `driveApi.files.list(spaces: 'appDataFolder')`)

**`modifiedTime` must be UTC with a `Z`** (`stat.modified.toUtc().toIso8601String()` in
`storage.dart`). `FileStat.modified` is a *local* `DateTime`, and `toIso8601String()` on a local
`DateTime` emits no timezone designator at all — which `DateTime.parse` on the client then reads
as *client*-local. Shipping it bare made every backup timestamp display off by the client's UTC
offset (2h for CEST against a UTC container) while the home screen's own "last synced" stayed
correct, because that one is written locally and never round-trips through the server. It also
skewed `syncClient.dart`'s "has this peer changed since last sync" comparison by the same amount.
The app's display sites already call `.toLocal()`, so emitting a correct `Z` is the whole fix.
- `PUT /sync/files/:filename` (binary body, the device's SQLite snapshot) → `200`
- `GET /sync/files/:filename` → binary stream
- `DELETE /sync/files/:filename` → `200`

## Backup

- **Own server (default)**: same shape as sync storage, separate namespace — `GET/PUT/GET/DELETE /backup/:filename`, plus `GET /backup/list`.
- **Nextcloud/WebDAV (optional, alternative target)**: configured entirely client-side (WebDAV URL + credentials, stored in app settings). The Flutter app speaks WebDAV directly to Nextcloud for this — **the new server does not proxy or need to know about this path at all**. Keep this separation; do not add WebDAV client code to the server.

## Migration (existing Google-backed data → new system)

No special migration API. The path is:
1. On the current install, do one last Google Drive backup (existing flow, untouched).
2. Confirm the backup restores correctly (test this on a copy of the data, not live, before trusting it).
3. Switch the app's sign-in/server settings to the new self-hosted system.
4. Use the app's existing restore-from-backup flow to bring that last Google-based backup into the now-self-hosted install.
5. Perform a first sync/backup against the new server to confirm the new path works.

Do not remove or disable the Google-based path until step 5 is verified working — this is the fallback described in `01-local-first-invariant.md`'s spirit: never leave the owner without working data access during a transition.

## Non-goals for this stage

- No incremental sync yet — every pull still downloads a full peer snapshot when that peer has any new row (Stage 2).
- No shared/multi-user data (Stage 4 — see `06-shared-household-data.md`).
- ~~No admin UI — CLI only.~~ Delivered in `05-accounts-and-admin.md`.
- ~~No password reset flow.~~ Delivered in `05-accounts-and-admin.md`: users change their own password, administrators issue temporary ones. There is still no self-service *forgotten*-password flow (no email sending) — an administrator resets it, or the operator uses the CLI.

## Acceptance criteria

- Two independent accounts (owner + spouse) can each sign in through the self-hosted server.
- Each account syncs correctly across that person's own Android (APK) and iPhone (web, added to home screen) — changes on one device appear on the other after the normal manual trigger (pull-to-refresh/relaunch), same UX as today.
- A backup lands in the owner's own storage and, when configured, in Nextcloud — and is restorable from either.
- Zero Google/Firebase network calls occur anywhere in the auth/sync/backup path (verify via network inspection, not just "it looks right").
- The `01-local-first-invariant.md` airplane-mode test passes.
- The web-reload auth bug is gone (implied by Firebase Auth Web's removal — verify explicitly by reloading the web app repeatedly while signed in).
