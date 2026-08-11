# Cashew Selfhosted (fork)

A permanently-diverging fork of [jameskokoska/Cashew](https://github.com/jameskokoska/Cashew) (GPL-3.0) that replaces Google Sign-In / Firebase Auth / Google Drive (auth, sync, backup) with self-hosted equivalents. Background and rationale: `specs/00-overview.md`.

## Before changing anything

1. Read `specs/00-overview.md` (principles, tech stack, non-goals).
2. Read `specs/01-local-first-invariant.md` — **hard constraint, not a suggestion**: the app must be fully usable offline, forever, and auth must never gate local usage. Any change that violates this is wrong regardless of what else it accomplishes.
3. Check which stage doc applies to the current work (`specs/02-*`, `specs/03-*`, ...) and its acceptance criteria before considering work done.
4. Prefer small, surgical diffs over sweeping rewrites, especially anywhere near sync. A previous Stage 2 attempt (event-push/WebSocket instant sync) landed ~4,300 lines of change, broke unrelated UI (the "Add Account" button), and reintroduced a data-loss race on backup restore — it was reverted (never merged; see `specs/04-stage-2-instant-sync.md` for the postmortem and the current plan). Large diffs in this codebase are a warning sign, not a sign of thoroughness.

## Versioning

Full contract in `specs/07-versioning.md`. The short version:

- `app/pubspec.yaml` holds the only version number: `1.0.0-beta.<n>+<n>`. The fork restarted at `1.0.0-beta.1` and does not continue upstream's 5.x line.
- **Every commit bumps it**, via `.githooks/pre-commit`. Enable once per clone — do this before your first commit in a fresh clone, or builds stop being distinguishable:

```bash
git config core.hooksPath .githooks
```

- The running version shows in the sidebar (on the About row) and in `GET /health`. That's how the owner confirms a redeploy landed, so don't break it casually.
- The changelog in `app/lib/widgets/showChangelog.dart` is the fork's own; upstream's was removed and still lives in `upstream/`. **Only add a section when a change is worth interrupting someone for** — most betas get none, and a version with no section shows no popup. Use raw English strings, never `.tr()` keys (see BL-003).

## Testing & verification workflow

The owner has time to test and wants to do it themselves — do not spend agent time/tokens simulating multi-device scenarios, airplane mode, or long manual QA passes. Instead:

- Build and start the app locally (`docker compose up --build`, or `flutter run -d chrome` / `-d web-server` for faster iteration) yourself.
- Report back the URL (e.g. `http://localhost:8080`) and any credentials needed (account email/password, e.g. from `bin/create_user.dart`) so the owner can log in and test.
- Let the owner drive acceptance testing (two-device sync, airplane-mode/offline behavior, restore propagation, etc.) — these are exactly the scenarios that are slow and expensive for an agent to verify but fast for a human to click through.
- Still run fast, cheap checks yourself before handing off: `flutter analyze`, `dart analyze`, and getting a build to succeed. Don't hand off code that doesn't even compile.
- If the owner reports a bug, reproduce it by reading/tracing code first; only drive the UI yourself for verification if the owner asks you to or it's the fastest way to confirm a fix.

## Repo layout

- `upstream/` — pristine shallow clone of upstream Cashew, kept **read-only** as a reference for diffing/porting. Do not edit in place; re-clone/re-pull if it goes stale.
- `specs/` — source of truth for what to build. Written for AI agents: precise contracts, explicit non-goals, testable acceptance criteria. Update specs when a decision changes; don't let code and specs drift.
- `app/` — the Flutter fork (created in Stage 0, package `cashew_selfhosted` / applicationId `com.selfhosted.cashew`; fork name is finalized as "Cashew Selfhosted", so these are no longer placeholders).
- `server/` — the Dart backend (created in Stage 0; auth/sync/backup endpoints added in Stage 1).
- `.github/workflows/` — `ci.yml` (`flutter`/`dart analyze` + tests for both `app/` and `server/`, plus a Dockerfile build check), `build-apk.yml` (a debug APK on every push/PR as a downloadable artifact — debug because PR builds deliberately have no access to the signing secrets, *not* because release builds are broken any more), and `release.yml` (on a `v*` tag: signed release APK + multi-arch GHCR image + GitHub Release). Release process and the AGP 8 upgrade that unblocked it: `specs/09-releases.md`.

## Hard invariant: upstream database compatibility

The **app's** Drift table/column structure must stay identical to upstream Cashew's (currently `schemaVersionGlobal = 46`, 10 tables). This is what makes an original-Cashew backup importable, and the owner cares about it. Verify with:

```bash
diff <(grep -E "^class [A-Za-z]+ extends Table|^  [A-Za-z]+Column" app/lib/database/tables.dart) <(grep -E "^class [A-Za-z]+ extends Table|^  [A-Za-z]+Column" upstream/budget/lib/database/tables.dart)
```

Empty output = still compatible. Note `upstream/` is not checked in, so it only exists in the main checkout — from a `.claude/worktrees/` worktree, point the second path at the main checkout's copy. Note the pattern is deliberately narrowed to `extends Table` and column declarations: a looser `^class ` also catches the type converters, which legitimately differ from upstream (Stage 2 gave them `with JsonTypeConverter2<...>` for the sync feed's JSON payloads — that changes serialization, not the stored SQLite representation) and produces a false alarm.

The **server's** database (`users`, `sessions`, `sync_records`, `sync_state`) is entirely unrelated and free to change — it has its own migration runner and has never held a transaction. Don't confuse the two. Breaking the app-side invariant is a Stage 4 decision, scoped in `specs/06-shared-household-data.md`; don't do it incidentally.

## Status

Accounts work landed 2026-08-09 and merged to `main` via PR #8: first-run setup wizard where the first user becomes instance administrator, in-app account management (name/email/password), admin user provisioning, and password-manager autofill. Full detail and acceptance criteria in `specs/05-accounts-and-admin.md`. Stage 4 (shared household data, per-user views, private transactions) is now designed but **not implemented** — `specs/06-shared-household-data.md`.

**De-Googled completely, 2026-08-10.** The fork no longer depends on Google at build time or run time. Firebase/Firestore, Google Sign-In, `googleapis`, Play Billing and Play Review are gone from `pubspec.yaml`, and `pubspec.lock` resolves no package matching `google|firebase|firestore|gms|play` — that grep is the cheapest regression check. Shared budgets (Firestore), Gmail receipt scanning, the feedback/rating popups and the Play Billing paywall were deleted; attachments were **replaced** with server-side storage (`/attachments`, a third `UserFileStore` namespace next to sync and backup). A Google request that wasn't in the dependency list at all — CanvasKit, fetched from gstatic by Flutter's default web renderer — was found by grepping the built `main.dart.js` for external hosts and fixed in the `Dockerfile`. The upstream schema invariant still passes: every `shared*` column stays, nothing writes them. Full detail in `specs/03-stage-1-kill-google.md`; the one deleted feature with no replacement is tracked in `specs/backlog/BL-005-imap-receipt-scanning.md`.

Budget amounts became per-period on 2026-08-10: editing a budget's amount now applies from the current period onward, and finished periods keep the target they had at the time, instead of the history view recomputing every past period from the current value. Done without a schema change by storing the history in `Budgets.sharedAllMembersEver`, a dead column from the deleted Firestore sharing — **read and write it only through `app/lib/struct/budgetPeriodAmounts.dart`**, and note the column name no longer describes its contents. Design, the rejected alternatives, and both directions of upstream compatibility are in `specs/backlog/BL-006-per-period-budget-amounts.md`.

**Releasing became a real process 2026-08-11.** `flutter build apk --release` works for the first time — the SDK-35/aapt2 failure was an AGP 7.3.1 limitation, fixed by moving to AGP 8.7.3 / Gradle 8.9 / `compileSdk 35` (Flutter itself stays pinned at 3.19.6). Pushing a `v*` tag now runs `release.yml`: a signed APK, a multi-arch image on `ghcr.io/vfyuj/cashew-selfhosted`, and a GitHub Release. Two things are the owner's and cannot be done from here — generating and backing up the Android signing keystore (lose it and no existing install can ever be upgraded in place) and making the GHCR package public. Design, the AGP 8 knock-on fixes, and the acceptance checklist: `specs/09-releases.md`.

Onboarding was reworked 2026-08-10 into five skippable steps (accounts → categories → expected income → planned spending), where the last two set amounts on BL-001's per-category envelope budgets rather than creating budgets of their own; and signing in to an account that already has server-side data no longer re-runs onboarding on the new device. Detail and testing checklist in `specs/backlog/BL-002-onboarding-create-main-account.md`.

Stage 0 and Stage 1 have initial implementations (last updated 2026-08-08) — the "Status" sections at the top of `specs/02-stage-0-foundations.md` and `specs/03-stage-1-kill-google.md` now use `- [ ]`/`- [x]` checkboxes; check those first before assuming something is or isn't done, and check items off as you complete them instead of re-describing status in prose each session. Short version: `/app` and `/server` exist and build clean (`flutter build apk`/`flutter build web`, `docker compose up`); server auth/sync/backup endpoints work end-to-end (tested via curl); app-side sign-in/sync/backup UI is repointed to the new server, including an optional client-side WebDAV/Nextcloud backup target (not yet verified against a real WebDAV server). `docker-compose.yml` runs a single container — the Dart server compiles the Flutter web build from source and serves both the API and the UI from one port, so there's nothing to path-split behind the reverse proxy; see `DEPLOYMENT.md`. Fork identity (name "Cashew Selfhosted", icon) is finalized. A real bug where restoring a backup or importing a `.sqlite` file didn't propagate to other synced devices has been fixed (rows are now stamped as modified on restore, same as any other write). Not yet done: real home-server deployment (needs the operator's physical server/NPM — see `/DEPLOYMENT.md`), and the acceptance-criteria verification pass (now the owner's job to run against a locally-started instance — see "Testing & verification workflow" above, not an agent task). Stage 2 (live sync) **is** implemented end to end, server and app: a row-level change feed with a WebSocket wake-up, plus a Reset Sync escape hatch. What it still lacks is the on-device acceptance pass — see the status block in `specs/04-stage-2-instant-sync.md`, which is authoritative. (Note this is the *second* attempt; the first was reverted, see "Before changing anything" above.)
