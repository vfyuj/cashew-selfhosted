# Shared household data (Stage 4)

**Design only. Nothing here is implemented.** Written down now, while the reasoning is fresh, so this can be picked up cold later.

Everything up to and including `05-accounts-and-admin.md` keeps the model from `00-overview.md` principle 3: two accounts on one server are fully isolated, each person having their own private multi-device sync. This is the stage that changes that.

## What the owner asked for

1. A second account for a family member, with access to the **same data**.
2. Each person able to customise their own view of it — hide money accounts that aren't theirs, reorder the screen — without changing what the other sees.
3. Some transactions kept private, so a gift for the other person doesn't show up in their app.

## The easy part: storage scoping

Server-side scoping is a genuine two-line choke point:

- `server/lib/src/sync/sync_routes.dart` — `UserFileStore(dataDir, 'sync', currentUser(request).id)`
- `server/lib/src/backup/backup_routes.dart` — the same shape for `'backup'`

`UserFileStore` already takes an arbitrary namespace and id, so pointing both at a resolved `datasetId` instead of a `userId` is close to mechanical. Add `datasets` and `dataset_members` tables (the migration runner from `05-accounts-and-admin.md` now exists to carry them), resolve the caller's dataset from their session, and the storage layer is done.

**Do not mistake this for the feature being easy.**

## The hard part: sync semantics

Sync is per-device whole-database SQLite snapshots, merged client-side by last-write-wins on `dateTimeModified`. Pointing two people's devices at one directory makes their snapshots merge exactly as though they were one person's devices. That will mostly appear to work, which is the danger. What it does not give you:

- **No per-row authorship.** Nothing records who wrote a row, so nothing can filter by it.
- **No partial visibility.** It is all-or-nothing on an entire database file. There is no mechanism for "send them these rows but not those".
- **No awareness of concurrent human edits.** `04-stage-2-instant-sync.md` already flags this: LWW is "adequate because Stage 2 is still single-owner-multi-device… Revisit if Stage 4 introduces genuinely concurrent multi-person edits." Two people editing the same budget on the same evening is the normal case here, not an edge case.

### Also required
- **`clientID` uniqueness must hold globally, not per user.** `sync-<clientID>.sqlite` filenames would now share one directory across people.
- **Restore is sharper once shared.** A snapshot restore overwrites the whole database file. Decide explicitly what that means when the file is not solely yours.

## Per-user views (item 2) — nearly free

`AppSettings` is a Drift table that `processSyncLogs` deliberately does not merge, and `appStateSettings` lives in `sharedPreferences`, not in the database at all. So per-person wallet visibility and layout order can stay local with no schema change and no sync work.

The one trap: a snapshot restore overwrites the whole database file *including* `AppSettings`. That is already a mild footgun and becomes a sharper one when a restore is triggered by the other person. Needs an explicit carve-out.

## Private transactions (item 3)

**Decided: UI-level hiding, not encryption.** The owner chose this deliberately, understanding the trade-off.

State the caveat honestly wherever this surfaces to a user: the rows are physically present in the shared database on the other person's device. This hides things from the app, not from a person with a SQLite browser. It is appropriate for "don't spoil the gift", not for "protect this from someone who might go looking".

### Open design question — settle before building

Attaching privacy to a **transaction** breaks the other person's arithmetic: a hidden amount makes their wallet balance and totals wrong, which is worse than the problem being solved. Attaching it to a **wallet** keeps every visible total internally consistent, because the wallet is simply absent from their view.

**Recommendation: the wallet-level model.** It also composes with item 2, which is already about hiding wallets that aren't relevant to you.

### Upstream compatibility — a decision this stage must make consciously

Everything up to this point keeps the app's Drift schema identical to original Cashew's (`schemaVersionGlobal = 46`, same 10 tables), which is what currently makes an original-Cashew backup importable — for free, verified by the diff in `CLAUDE.md`. The actual goal was never the identical schema; it's staying import-compatible with upstream for as long as that's practical. Identical tables are just the cheapest way to get that while it costs nothing.

This stage is the first thing that genuinely wants to spend that budget — a private/owner flag has to live on a row somewhere. Two ways to keep the real goal without keeping the schema identical:

1. **Cheapest: keep privacy flags out of the synced schema entirely** — in the *unsynced* settings layer, keyed by row id. Full compatibility in both directions, at the cost of the flags not surviving a device migration or a restore. For a "don't spoil the gift" threat model, likely the better trade regardless of the point below.
2. **If the flag has to live in the synced table:** importing an original-Cashew backup still works (Drift migrations run forward). What breaks is the reverse — a fork backup importing into stock Cashew, which has no migration for a column it doesn't know. That's a reasonable trade to accept, or it can be recovered with a small conversion step (an export path that strips or translates the fork-only column back out) rather than treated as a hard blocker. Only worth deciding if option 1 turns out not to fit.

## Sequencing

1. `datasets` + `dataset_members`, and dataset resolution in the two scoping lines. Storage only; behaviour unchanged while every dataset has exactly one member.
2. Global `clientID` uniqueness.
3. Invite/join flow, reusing the administration surface from `05-accounts-and-admin.md`.
4. Decide the LWW question with real two-person usage before building anything on top of it.
5. Per-user views (mostly already local — verify the restore carve-out).
6. Private wallets, after the schema-compatibility decision above is made explicitly.

## Non-goals

- Multi-tenant hosting. Unchanged from `00-overview.md`.
- Cryptographic privacy. Explicitly rejected in favour of UI-level hiding.
- A general permission system. Two roles, plus per-wallet visibility, is the whole model.
