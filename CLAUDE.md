# Cashew Selfhosted (fork)

A permanently-diverging fork of [jameskokoska/Cashew](https://github.com/jameskokoska/Cashew) (GPL-3.0) that replaces Google Sign-In / Firebase Auth / Google Drive (auth, sync, backup) with self-hosted equivalents.

## Before changing anything

1. Read `specs/00-overview.md` — principles, tech stack, settled decisions, explicit non-goals.
2. **How something works today: `docs/README.md`** (per-module, read from code). **Why it was decided that way: `specs/README.md`.** Open the one page you need; don't read either set.
3. Open the stage doc when your change touches that stage — not up front. Its acceptance criteria decide when the work is done, and its `- [x]` checkboxes are the status of record; check items off instead of re-describing status in prose.
4. **Near sync, prefer small surgical diffs.** A previous Stage 2 attempt landed ~4,300 lines, broke unrelated UI and reintroduced a data-loss race; it was reverted. Postmortem: `specs/04-stage-2-instant-sync.md`. Large diffs *there* are a warning sign, not thoroughness. This is about the blast radius of sync changes specifically — it is not a general discouragement from refactoring, and it is not a reason to write a second copy of something rather than reuse what exists.

## Invariants

Break one of these and it usually fails silently. One line each; the reasoning is on the linked page.

- **Local data is always readable and writable**, regardless of network or auth state. Sync and auth sit on top and never gate it, and a sync failure never becomes a blocked screen or an error the user must dismiss. `specs/01-local-first-invariant.md` (cited from 8 places in the app code).
- **`is_admin` is a role; dataset membership is what data you see.** Independent axes — never use one as a proxy for the other. `docs/server/auth.md`
- **Backups are per-user; sync and attachments follow the dataset.** Deliberate, with a test pinning it. `docs/server/storage.md`
- **`AppSettings` row 0 is device-local and excluded from the change feed.** That exclusion is what makes syncing the table safe at all. `docs/app/settings.md`
- **`CategoryEnvelopes` is the fork's own table and the only one that may be.** Every other table is upstream's and must not change, column for column. `docs/app/database.md`
- **An envelope's income/expense comes from `Categories.income`, never from the envelope row.** Storing a second copy is what the previous implementation spent its life reconciling. `docs/app/envelopes.md`

## Checks

Fast and cheap; run them yourself before handing anything off.

```bash
cd app && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test
cd server && dart analyze && dart test
```

`--no-fatal-infos/--no-fatal-warnings` because the fork carries ~260 pre-existing warning/info issues, zero errors — real errors still fail.

```bash
# Upstream's tables still identical? Empty output = yes. (The sed drops the
# fork's own CategoryEnvelopes table; every other difference is a finding.)
diff <(sed '/^@DataClassName..CategoryEnvelope../,/^}/d' app/lib/database/tables.dart | grep -E "^class [A-Za-z]+ extends Table|^  [A-Za-z]+Column") <(grep -E "^class [A-Za-z]+ extends Table|^  [A-Za-z]+Column" upstream/budget/lib/database/tables.dart)

# Still de-Googled? Must print nothing.
grep -iE "google|firebase|firestore|gms|play" app/pubspec.lock

# Every server route documented? (also runs in CI as api_docs_test.dart)
grep -rnoE "\.(get|post|put|delete|patch)\(\s*'[^']*'" server/lib
```

`upstream/` is not checked in — from a `.claude/worktrees/` worktree, point the diff's second path at the main checkout.

## Versioning

Full contract in `specs/07-versioning.md`.

- `app/pubspec.yaml` holds the only version number: `1.0.0-beta.<n>+<n>`. The fork restarted at `1.0.0-beta.1` and does not continue upstream's 5.x line.
- **Every commit bumps it**, via `.githooks/pre-commit`. Enable once per clone, before your first commit:

```bash
git config core.hooksPath .githooks
```

- The version shows in the sidebar (About row) and in `GET /health`. That's how the owner confirms a redeploy landed — don't break it casually.
- The changelog (`app/lib/widgets/showChangelog.dart`) is the fork's own. **Only add a section when a change is worth interrupting someone for** — most betas get none, and a version with no section shows no popup.
- **Changelog title and bullet text must be `.tr()` keys, translated into all 8 locales**, like any other user-facing text. Older sections predate this rule and are raw English; `.tr()` falls back to the string itself, so they render unchanged — no backfill needed. The in-app translation editor's own chrome stays raw English on purpose: it's the tool for fixing a broken translation, so it can't depend on the system it repairs.
- **When a version's section covers more than one feature, give each its own short bold title** (a `## Title` line above its paragraph — see the format comment above `getChangelogString()`), so the popup is scannable. Skip it on a single-bug-fix version.

## Translations

Every change that adds, edits or removes user-facing text must translate it into all 8 locales in the same change — `en, ru, de, es, fr, pt, uk, zh`, in `app/assets/translations/generated/<locale>.json` (flat `key: string`, two-space indent, no trailing newline).

`app/test/translation_keys_test.dart` only enforces that a `.tr()` key exists in `en.json`; the other 7 falling back to English is a safety net for a missed key, not a substitute for translating one. Provenance and the in-app editor: `app/assets/translations/README.md`.

## Testing & verification workflow

The owner has time to test and wants to do it themselves — **do not spend agent time simulating multi-device scenarios, airplane mode, or long manual QA passes.**

- Build and start the app locally yourself (`docker compose up --build`, or `flutter run -d chrome` for faster iteration).
- Report the URL and any credentials needed (e.g. from `bin/create_user.dart`) so the owner can log in and test.
- Let the owner drive acceptance testing — two-device sync, offline behaviour, restore propagation. Slow for an agent, fast for a human.
- Run the checks above first. Don't hand off code that doesn't compile.
- If the owner reports a bug, reproduce it by reading and tracing code first; drive the UI only if asked or if it's genuinely fastest.

## Repo layout

- `app/` — the Flutter fork (package `cashew_selfhosted`, applicationId `com.selfhosted.cashew`).
- `server/` — the Dart backend (auth, sync, backup, attachments, admin).
- `docs/` — **how it works now**, per module, read from code. Start at `docs/README.md`.
- `specs/` — **why it was decided**, plus what's planned and the acceptance criteria. Start at `specs/README.md`. Update a spec when a decision changes; don't let code and specs drift.
- `upstream/` — pristine shallow clone of upstream Cashew, **read-only** reference for checking the table schema and for the occasional deliberate port. Not checked in. **Not a baseline the fork's files are expected to match** — reuse beats a near-duplicate, upstream files included; see `specs/00-overview.md`, "On not treating `upstream/` as an authority".
- `app/assets/translations/` — the fork's own 8 languages, no longer generated from upstream's spreadsheet.
- `.github/workflows/` — `ci.yml` (analyze + tests for both packages, plus a Dockerfile build), `build-apk.yml` (debug APK per push/PR; debug because PR builds deliberately have no signing secrets), `release.yml` (on a `v*` tag: signed APK + multi-arch GHCR image + GitHub Release). See `specs/09-releases.md`.

## Upstream database compatibility

An original-Cashew backup should stay importable for as long as reasonably possible. Upstream's tables are unchanged, column for column, and must stay that way; the fork owns exactly one table of its own (`CategoryEnvelopes`), which an upstream backup simply doesn't have. Adding a table is the cheap kind of divergence, changing an existing one is not. *Incidental* drift is what to avoid.

Mechanics, the dead-column convention, and why the diff pattern is narrowed: `docs/app/database.md`.

The **server's** database is entirely unrelated and free to change however's convenient — it has its own migration runner and has never held a transaction. `docs/server/database.md`. Don't confuse the two.

## Status

Stage docs carry the authoritative checkboxes; this is the map.

| Area | State | Where |
|---|---|---|
| Stage 0/1 foundations — app, server, Docker, repointed sign-in/sync/backup | built | `specs/02-*`, `specs/03-*` |
| De-Googling — Firebase, Sign-In, Drive, Play all gone; attachments replaced server-side | complete | `specs/03-*`; the one gap with no replacement is `backlog/BL-005` |
| Accounts, first-run setup wizard, admin provisioning | shipped | `specs/05-*` |
| Stage 2 live sync — row feed, WebSocket wake-up, Reset Sync | implemented end to end; owner's acceptance pass outstanding | `specs/04-*` |
| Stage 4 shared household data — datasets, per-user views | shipped; personal budgets withdrawn in 1.2.0 | `specs/06-*` |
| Releases — signed APK, multi-arch GHCR image, tag workflow | working | `specs/09-*` |
| Per-period budget amounts | withdrawn in 1.2.0 — envelopes store one row per month instead | `backlog/BL-006` |
| Envelopes (monthly plan per category), Planned vs Actual | shipped; replaced the budget-shaped version in 1.2.0 | `backlog/BL-001`, `docs/app/envelopes.md` |
| Onboarding rework | shipped | `backlog/BL-002` |
| Fork-owned translations + in-app editor | shipped | `backlog/BL-007` |
| Real home-server deployment, and every acceptance pass | the owner's, not an agent task | `DEPLOYMENT.md` |

Stage 3 (public-fork readiness) is intentionally unwritten.
