# Overview

## What this is

A fork of Cashew (Flutter/Dart budgeting app, GPL-3.0) that replaces its Google-dependent auth, sync, and backup with self-hosted equivalents, deployed on the owner's home server (Docker, own domain).

## Why (do not re-litigate these — they are settled decisions)

- Web auth breaks on page reload (Firebase Auth Web session-persistence issue on Flutter web reinit).
- Sync requires manually triggering before switching devices and is slow — see "Why sync is slow today" in `04-stage-2-instant-sync.md` for the root cause and the fix.
- Backups to Google Drive work, but the owner wants a self-hosted alternative (own server and/or Nextcloud/WebDAV).
- Upstream's maintainer has repeatedly and thoughtfully declined self-hosting/multi-user support (relational DB architecture doesn't support live collection sync without a middle server; unwilling to bear cost/liability of hosting users' financial data). This fork exists because that's a reasonable position for upstream and a real gap for this owner. **This will never be upstreamed. Treat it as permanently diverging.**

## Non-negotiable principles

1. **Local-first, always.** Full detail and acceptance tests in `01-local-first-invariant.md`. The single most important constraint in this project.
2. **No Google/Firebase anywhere** in the auth, sync, or backup path.
3. **Single-owner-per-account** until Stage 4. No shared/merged household data yet — each person has their own private multi-device sync, same as today's one-Google-account-per-person model.
4. **Reuse, don't rewrite, the local conflict-resolution logic.** Upstream's `SyncLog` model, `processSyncLogs` (last-write-wins by `dateTimeModified`), and `DeleteLog` tombstone table are sound and transport-agnostic. Only the transport (how bytes move between devices) and auth (how a device is authorized) are being replaced.
5. **GPL-3.0 compliance.** Keep LICENSE and copyright notices. Source stays available (public repo). Fork identity (name/icon/package id) must be distinct from upstream before any distribution beyond the owner's own devices.
6. **Single-tenant per deployment.** This is software a family self-hosts for themselves, not a multi-tenant SaaS. Each deployment serves one household's accounts. (Stage 4's "multi-user" means multiple people within one household's server, not multiple unrelated households sharing infrastructure.)

## Tech stack decisions

- **Client**: fork of upstream Flutter app. Local storage stays Drift/SQLite, untouched. Only the auth screens and the transport layer inside `syncClient.dart`-equivalent and `accountAndBackup.dart`-equivalent code are replaced.
- **New server**: Dart (`shelf` or `dart_frog`), containerized. Rationale: same language as the client — no schema/type translation layer between app and server; small enough workload (household scale) that a heavier platform (Supabase/Pocketbase/etc.) would add operational surface without removing custom-code burden, since Cashew's specific sync semantics would need a translation layer onto any generic platform anyway.
- **iOS distribution**: self-hosted Flutter **web** build, added to iPhone home screen (PWA — `web/manifest.json` already has `"display": "standalone"` and icons). No native iOS build, no Xcode, no Apple Developer account, for now.
- **Android distribution**: sideloaded APK, self-signed. No Play Store dependency.
- **Backup transport**: own server by default (same REST API as sync storage); Nextcloud/WebDAV as an alternative, configured client-side and spoken directly by the app (no server-side proxying needed).

## Glossary

- **appDataFolder-equivalent**: the new server's per-user file storage, replacing Google Drive's hidden app-scoped Drive folder.
- **Snapshot-diff sync**: today's mechanism (upload/download full SQLite files, diff by timestamp). This is the Stage 1 transport (just repointed at the new server) and stays the always-available fallback in Stage 2 — for a device's first-ever sync, or one that's been offline long enough that the incremental log no longer covers the gap.
- **Incremental sync**: Stage 2's addition — individual row changes uploaded/downloaded directly as small JSON deltas (via a durable per-user change log on the server) instead of moving a whole SQLite file, so a trigger only transfers what actually changed. Still triggered by the same user actions as today (pull-to-refresh, app foreground, manual sync) — **not** a persistent connection or real-time push; an earlier attempt at real-time/event-push sync was tried and reverted (see `04-stage-2-instant-sync.md`).
- **SyncLog / DeleteLog**: upstream's existing merge-log types. Reused, not replaced.

## Roadmap index

1. `02-stage-0-foundations.md` — dev environment, fork identity, empty server skeleton deployed.
2. `03-stage-1-kill-google.md` — self-hosted auth + repointed snapshot sync/backup. First real release.
3. `04-stage-2-instant-sync.md` — incremental sync on top of Stage 1's snapshot-diff, triggered by the same user actions as today (not real-time push — see that file for why).
4. Stage 3 (public-fork readiness) and Stage 4 (multi-user/ACL) specs are intentionally **not yet written** — they depend on decisions we'll make while executing Stages 1-2, and writing them now risks locking in guesses. Write them when the preceding stage is actually done.

`backlog/` holds product feature requests that are **not** part of this roadmap (budgeting features, UI work). Reviewed but unscheduled — see `backlog/README.md`. Nothing there is approved for implementation, and nothing there should start while it touches tables a live stage is changing.

## Explicit non-goals (do not build these unless a spec above says to)

- Multi-tenant hosting (many unrelated households on one deployment).
- Shared/merged household data before Stage 4.
- Any Google/Firebase dependency, including as a "fallback."
- Native iOS build pipeline (unless a future spec revises this).
- Public self-service registration (see auth design in `03-stage-1-kill-google.md` — accounts are provisioned, not self-registered).
