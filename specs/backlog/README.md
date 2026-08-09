# Backlog

Product feature requests that are **not** part of the self-hosting roadmap (`specs/02-*` … `specs/05-*`).

The numbered stage docs are the plan for replacing Google auth/sync/backup. This folder is for
everything else: budgeting features, UI changes, quality-of-life work. Items here are **reviewed but
not scheduled** — nothing in this folder is approved for implementation until the owner says so.

## Ground rules for anything in this folder

1. The local-first invariant (`specs/01-local-first-invariant.md`) applies here exactly as it does to
   the stage docs. A feature that only works when signed in is wrong.
2. Anything touching a Drift table also touches this fork's sync path. Upstream ships whole SQLite
   files; **this fork also ships row-level JSON deltas** (`app/lib/struct/liveSyncClient.dart`), so a
   schema change that upstream could make safely can break sync here. See BL-001 §C3.
3. Prefer small, surgical diffs. Same warning as `CLAUDE.md`: large diffs in this codebase are a
   warning sign, not a sign of thoroughness.
4. Don't start a backlog item while Stage 2 is in flight if it touches the same tables.

## Items

| ID | Title | Status | Blocked on |
|---|---|---|---|
| [BL-001](BL-001-category-locked-budgets.md) | Category-locked budgets, income-relative targets, planned-vs-actual summary | Reviewed, needs owner decisions | Stage 2 landing; 6 open decisions in §4 |
| [BL-002](BL-002-onboarding-create-main-account.md) | Onboarding screen 2: "Create a budget" → "Create main account", add What-is-an-Account explainer | Reviewed, needs owner decision | 1 open decision in §4 |
| [BL-003](BL-003-upstream-legacy-translations-and-docs.md) | Reminder: decide what to do with upstream-origin translations pipeline and in-app doc/policy links | Reminder / inventory only | Per-item decisions in §3 |
| [BL-004](BL-004-public-readme-for-selfhosted-deploy.md) | Public README.md for the GitHub repo describing self-hosted deployment | Reviewed, needs owner decisions | 2 open decisions in §5 |
