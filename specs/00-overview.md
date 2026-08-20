# Overview

## What this is

A fork of Cashew (Flutter/Dart budgeting app, GPL-3.0) that replaces its Google-dependent auth, sync, and backup with self-hosted equivalents, deployed on the owner's home server (Docker, own domain).

## Why (do not re-litigate these — they are settled decisions)

- Web auth breaks on page reload (Firebase Auth Web session-persistence issue on Flutter web reinit).
- Sync requires manually triggering before switching devices and is slow — see "Why sync is slow today" in `04-stage-2-instant-sync.md` for the root cause and the fix.
- Backups to Google Drive work, but the owner wants a self-hosted alternative (own server and/or Nextcloud/WebDAV).
- Upstream's maintainer has repeatedly and thoughtfully declined self-hosting/multi-user support (relational DB architecture doesn't support live collection sync without a middle server; unwilling to bear cost/liability of hosting users' financial data). This fork exists because that's a reasonable position for upstream and a real gap for this owner. **This will never be upstreamed. Treat it as permanently diverging.**

## Non-negotiable principles

1. **Local data first.** Sync and auth are an optional layer over the local Drift database, never a gate on it — see `01-local-first-invariant.md`. Matters most for local testing and for devices reconnecting after time offline; it's not a mandate to engineer "offline" as a feature in itself.
2. **No Google/Firebase anywhere** in the auth, sync, or backup path.
3. **Data belongs to a dataset, not to an account.** Superseded Stage 4's original wording, which said single-owner-per-account. Since `06-shared-household-data.md` shipped, an account can share a dataset with another account, and everything — sync files, the change feed, attachments — is scoped to the dataset rather than the user. An account created without the sharing switch gets a dataset of its own and behaves exactly as before, which is still the default. Backups are the one deliberate exception and stay per-user; that file says why.
4. **Reuse, don't rewrite, the local conflict-resolution logic.** Upstream's `SyncLog` model, `processSyncLogs` (last-write-wins by `dateTimeModified`), and `DeleteLog` tombstone table are sound and transport-agnostic. Only the transport (how bytes move between devices) and auth (how a device is authorized) are being replaced.
5. **GPL-3.0 compliance.** Keep LICENSE and copyright notices. Source stays available (public repo). Fork identity (name/icon/package id) must be distinct from upstream before any distribution beyond the owner's own devices.
6. **Reuse beats a second copy, and upstream's files are not off limits.** Only the *table schema* is pinned (`CLAUDE.md`, "Upstream database compatibility"), and that is about keeping an original-Cashew backup restorable — not about code. Everything else in `app/lib` is this fork's to optimise: extending an upstream widget with an optional parameter, or lifting a shared piece out of one, is preferable to writing a near-duplicate beside it. Added 2026-08-20, after a review found the opposite habit had taken hold with nothing behind it — see the note below.
7. **Single-tenant per deployment.** This is software a family self-hosts for themselves, not a multi-tenant SaaS. Each deployment serves one household's accounts. (Stage 4's "multi-user" means multiple people within one household's server, not multiple unrelated households sharing infrastructure.)

### On not treating `upstream/` as an authority

Worth stating plainly, because for months the code was written as if the rule were the reverse.
Upstream files were left untouched even where reuse was the obvious move, which is where the fork's
handful of near-duplicate widgets came from — an envelope total beside a budget total, an envelope
carousel beside a budget carousel, each one written fresh rather than sharing.

Nothing ever asked for that. No spec required it, and a review in August 2026 found that in 136
commits **not one upstream bug fix had ever been ported**; every mention of upstream in the history
is the fork moving further away from it. The `upstream/` clone was five months stale at the time. The
file-level diffability being protected had never once been used for the thing it was being protected
for.

So: `upstream/` is a reference for checking the table schema and for the occasional deliberate port.
It is not a baseline that files are expected to match. **Git history is what records what changed and
why** — it knows the reasoning, which a diff against a half-year-old snapshot never can.

Two things this does *not* loosen: the table schema stays column-for-column identical, and changes
near sync stay small and careful for the reason `04-stage-2-instant-sync.md` gives — a reverted
~4,300-line attempt. Neither of those is about upstream parity.

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
4. `05-accounts-and-admin.md` — first-run setup wizard, account management, instance administration. Revises Stage 1's auth section.
5. `06-shared-household-data.md` — Stage 4. **Implemented.** Shared dataset and per-user views. Personal budgets and the subcategory allocation check shipped in it and were withdrawn in 1.2.0; both sections are kept there as cancelled decisions.
6. Stage 3 (public-fork readiness) is intentionally **not yet written** — it depends on decisions we'll make while executing the earlier stages, and writing it now risks locking in guesses.

`07-versioning.md` sits outside the stage sequence: it's the fork's release-numbering contract (`1.0.0-beta.<n>`, auto-bumped per commit, shown in the sidebar), which every stage from here on ships under. `08-release-notes-style.md` sits alongside it: not numbering mechanics but the editorial guideline for what to actually write in a changelog section (curate, don't narrate everything; scale effort to the release; call out breaking changes plainly).

`backlog/` holds product feature requests that are **not** part of this roadmap (budgeting features, UI work). Reviewed but unscheduled — see `backlog/README.md`. Nothing there is approved for implementation, and nothing there should start while it touches tables a live stage is changing.

## Explicit non-goals (do not build these unless a spec above says to)

- Multi-tenant hosting (many unrelated households on one deployment).
- Shared/merged household data before Stage 4.
- Any Google/Firebase dependency, including as a "fallback."
- Native iOS build pipeline (unless a future spec revises this).
- Open public registration. Note this is *not* the same as "no registration at all": since `05-accounts-and-admin.md`, a fresh instance lets the first visitor create the administrator account (the Nextcloud/Immich bootstrap model), and that administrator provisions everyone else from inside the app. Setup closes permanently once one account exists. What stays out of scope is an endpoint that lets anyone create an account on an already-running instance.
