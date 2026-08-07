# Cashew Selfhosted (fork)

A permanently-diverging fork of [jameskokoska/Cashew](https://github.com/jameskokoska/Cashew) (GPL-3.0) that replaces Google Sign-In / Firebase Auth / Google Drive (auth, sync, backup) with self-hosted equivalents. Background and rationale: `specs/00-overview.md`.

## Before changing anything

1. Read `specs/00-overview.md` (principles, tech stack, non-goals).
2. Read `specs/01-local-first-invariant.md` — **hard constraint, not a suggestion**: the app must be fully usable offline, forever, and auth must never gate local usage. Any change that violates this is wrong regardless of what else it accomplishes.
3. Check which stage doc applies to the current work (`specs/02-*`, `specs/03-*`, ...) and its acceptance criteria before considering work done.

## Repo layout

- `upstream/` — pristine shallow clone of upstream Cashew, kept **read-only** as a reference for diffing/porting. Do not edit in place; re-clone/re-pull if it goes stale.
- `specs/` — source of truth for what to build. Written for AI agents: precise contracts, explicit non-goals, testable acceptance criteria. Update specs when a decision changes; don't let code and specs drift.
- `app/` — the Flutter fork (created in Stage 0, package `cashew_selfhosted` / applicationId `com.selfhosted.cashew`; fork name is finalized as "Cashew Selfhosted", so these are no longer placeholders).
- `server/` — the Dart backend (created in Stage 0; auth/sync/backup endpoints added in Stage 1).

## Status

Stage 0 and Stage 1 have initial implementations (last updated 2026-08-07) — the "Status" sections at the top of `specs/02-stage-0-foundations.md` and `specs/03-stage-1-kill-google.md` now use `- [ ]`/`- [x]` checkboxes; check those first before assuming something is or isn't done, and check items off as you complete them instead of re-describing status in prose each session. Short version: `/app` and `/server` exist and build clean (`flutter build apk`/`flutter build web`, `docker compose up`); server auth/sync/backup endpoints work end-to-end (tested via curl); app-side sign-in/sync/backup UI is repointed to the new server, including an optional client-side WebDAV/Nextcloud backup target (not yet verified against a real WebDAV server). Not yet done: real home-server deployment (needs the operator's physical server/NPM — see `/DEPLOYMENT.md`), fork icon (name is finalized as "Cashew Selfhosted"; icon is still a placeholder), and the acceptance-criteria verification pass (airplane-mode test, two-device test, network inspection for zero Google calls).
