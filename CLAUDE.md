# Cashew Selfhosted (fork)

A permanently-diverging fork of [jameskokoska/Cashew](https://github.com/jameskokoska/Cashew) (GPL-3.0) that replaces Google Sign-In / Firebase Auth / Google Drive (auth, sync, backup) with self-hosted equivalents. Background and rationale: `specs/00-overview.md`.

## Before changing anything

1. Read `specs/00-overview.md` (principles, tech stack, non-goals).
2. Read `specs/01-local-first-invariant.md` — **hard constraint, not a suggestion**: the app must be fully usable offline, forever, and auth must never gate local usage. Any change that violates this is wrong regardless of what else it accomplishes.
3. Check which stage doc applies to the current work (`specs/02-*`, `specs/03-*`, ...) and its acceptance criteria before considering work done.
4. Prefer small, surgical diffs over sweeping rewrites, especially anywhere near sync. A previous Stage 2 attempt (event-push/WebSocket instant sync) landed ~4,300 lines of change, broke unrelated UI (the "Add Account" button), and reintroduced a data-loss race on backup restore — it was reverted (never merged; see `specs/04-stage-2-instant-sync.md` for the postmortem and the current plan). Large diffs in this codebase are a warning sign, not a sign of thoroughness.

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

## Status

Stage 0 and Stage 1 have initial implementations (last updated 2026-08-08) — the "Status" sections at the top of `specs/02-stage-0-foundations.md` and `specs/03-stage-1-kill-google.md` now use `- [ ]`/`- [x]` checkboxes; check those first before assuming something is or isn't done, and check items off as you complete them instead of re-describing status in prose each session. Short version: `/app` and `/server` exist and build clean (`flutter build apk`/`flutter build web`, `docker compose up`); server auth/sync/backup endpoints work end-to-end (tested via curl); app-side sign-in/sync/backup UI is repointed to the new server, including an optional client-side WebDAV/Nextcloud backup target (not yet verified against a real WebDAV server). `docker-compose.yml` runs a single container — the Dart server compiles the Flutter web build from source and serves both the API and the UI from one port, so there's nothing to path-split behind the reverse proxy; see `DEPLOYMENT.md`. Fork identity (name "Cashew Selfhosted", icon) is finalized. A real bug where restoring a backup or importing a `.sqlite` file didn't propagate to other synced devices has been fixed (rows are now stamped as modified on restore, same as any other write). Not yet done: real home-server deployment (needs the operator's physical server/NPM — see `/DEPLOYMENT.md`), the acceptance-criteria verification pass (now the owner's job to run against a locally-started instance — see "Testing & verification workflow" above, not an agent task), and Stage 2 (incremental sync) — see `specs/04-stage-2-instant-sync.md` for the current plan; an earlier attempt at this was reverted, see "Before changing anything" above.
