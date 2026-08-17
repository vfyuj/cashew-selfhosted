# Backlog

Product feature requests that are **not** part of the self-hosting roadmap (`specs/02-*` … `specs/05-*`).

The numbered stage docs are the plan for replacing Google auth/sync/backup. This folder is for
everything else: budgeting features, UI changes, quality-of-life work. Items here are **reviewed but
not scheduled** — nothing in this folder is approved for implementation until the owner says so.

## Ground rules for anything in this folder

1. Local data (`specs/01-local-first-invariant.md`) works the same with no server configured. A
   feature that only works when signed in needs a specific reason.
2. Anything touching a Drift table also touches this fork's sync path. Upstream ships whole SQLite
   files; **this fork also ships row-level JSON deltas** (`app/lib/struct/liveSyncClient.dart`), so a
   schema change that upstream could make safely can break sync here. See BL-001 §2, which avoided
   a schema change partly for this reason.
3. Prefer small, surgical diffs. Same warning as `CLAUDE.md`: large diffs in this codebase are a
   warning sign, not a sign of thoroughness.
4. Don't start a backlog item while Stage 2 is in flight if it touches the same tables.

## Items

| ID | Title | Status | Blocked on |
|---|---|---|---|
| [BL-001](BL-001-category-locked-budgets.md) | Category budgets, percent-of-income entry, share-of-plan labels | **Superseded 2026-08-17** by Envelopes (1.2.0) — see `docs/app/envelopes.md` | — |
| [BL-002](BL-002-onboarding-create-main-account.md) | Onboarding rework: accounts, income, categories, envelope explainer, skippable steps | **Implemented 2026-08-10** | — |
| [BL-003](BL-003-upstream-legacy-translations-and-docs.md) | Reminder: decide what to do with upstream-origin translations pipeline and in-app doc/policy links | §2A resolved by BL-007; §2B still open | §2B per-item decisions |
| [BL-004](BL-004-public-readme-for-selfhosted-deploy.md) | Public README.md for the GitHub repo describing self-hosted deployment | Reviewed, needs owner decisions | 2 open decisions in §5 |
| [BL-005](BL-005-imap-receipt-scanning.md) | Receipt scanning over IMAP, replacing the deleted Gmail version | Not started | Web-vs-Android decision in §4 |
| [BL-006](BL-006-per-period-budget-amounts.md) | Per-period budget amounts, so changing a budget stops rewriting finished periods | **Superseded 2026-08-17** by Envelopes (1.2.0) — one row per month instead | — |
| [BL-007](BL-007-fork-owned-translations.md) | Fork-owned translations + in-app translation editor, dropping the last upstream dependency | **Implemented 2026-08-12**, needs owner acceptance pass | — |
