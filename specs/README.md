# Specs index

**Why decisions were made, and what is planned.** For how something works *today*, start at
[`docs/README.md`](../docs/README.md) instead — it is shorter and read from the code.

Open a spec when you need the reasoning, the alternatives that were rejected, or the acceptance
criteria. Do not read the set.

| Spec | Open it when |
|---|---|
| [00-overview.md](00-overview.md) | Starting anything. Principles, tech-stack decisions, glossary, and the explicit non-goals. Settled decisions — do not re-litigate them. |
| [01-local-first-invariant.md](01-local-first-invariant.md) | Touching startup, auth, or sync. Local data is always readable and writable; sync sits on top and never gates it. Cited from 8 places in the app code. |
| [02-stage-0-foundations.md](02-stage-0-foundations.md) | Rarely. Dev environment, fork identity, the original server skeleton. Status checkboxes at the top. |
| [03-stage-1-kill-google.md](03-stage-1-kill-google.md) | Anything that used to be Google's: auth, snapshot sync, backup, attachments. Also the record of what de-Googling removed and what replaced it. |
| [04-stage-2-instant-sync.md](04-stage-2-instant-sync.md) | **Before changing sync.** The change-feed design, the race analysis, and the postmortem of a first attempt that was reverted after ~4,300 lines broke unrelated things. Large; the current mechanics are summarised in [docs/server/sync.md](../docs/server/sync.md). |
| [05-accounts-and-admin.md](05-accounts-and-admin.md) | First-run setup, account management, instance administration, and the accepted setup-window exposure. |
| [06-shared-household-data.md](06-shared-household-data.md) | Datasets and per-user view settings. Describes what shipped rather than a design, including two decisions since cancelled. |
| [07-versioning.md](07-versioning.md) | Anything about version numbers, the pre-commit bump, or `/health`. |
| [08-release-notes-style.md](08-release-notes-style.md) | Writing a changelog section. Editorial guidance, not mechanics. |
| [09-releases.md](09-releases.md) | Cutting a release: tags, signing, the GHCR image, the AGP 8 upgrade that unblocked release builds. |

Stage 3 (public-fork readiness) is intentionally unwritten — it depends on decisions made while
executing the earlier stages.

## Backlog

[`backlog/`](backlog/README.md) holds product feature requests that are **not** part of the roadmap.
Reviewed but unscheduled; nothing there is approved for implementation. Several have since shipped
and their files record how — `BL-002` (onboarding), `BL-004` (public README), `BL-007` (fork-owned
translations). Two shipped and were then superseded by the Envelopes feature in 1.2.0 — `BL-001`
(category-locked budgets) and `BL-006` (per-period budget amounts) — and their files say what
replaced them.

## Keeping these honest

Update the spec when a decision changes; do not let code and specs drift. When a spec turns out to
describe something that shipped differently, fix the spec rather than adding a note somewhere else.
