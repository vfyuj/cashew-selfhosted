# The server's database

File: `server/lib/src/database.dart`. SQLite at `<DATA_DIR>/db.sqlite`, WAL, foreign keys on,
`busy_timeout=5000`.

**This is not the app's database.** The app's Drift database — transactions, budgets, wallets — is
what a Cashew backup file contains, is described in [../app/database.md](../app/database.md), and
must stay byte-identical to upstream's. Nothing here affects a backup's restorability, so this schema
is free to change whenever convenient. Do not confuse the two; the confusion is common enough that
the code says so too.

## Tables

| Table | Key | Holds |
|---|---|---|
| `users` | `id` | `email` (unique), `password_hash`, `name`, `is_admin`, `created_at` |
| `sessions` | `token_hash` | `user_id`, `created_at`, `expires_at` |
| `datasets` | `id` | `name`, `created_at` — the unit data is scoped to |
| `dataset_members` | `user_id` | `dataset_id`, `joined_at` |
| `sync_records` | `(dataset_id, table_name, pk)` | `seq`, `deleted`, `modified_at`, `device_id`, `payload` |
| `sync_state` | `dataset_id` | `next_seq`, `min_retained_seq` |

`dataset_members.user_id` is the primary key, not half of a composite one: a user belongs to exactly
one dataset, so a request's storage scope is never ambiguous and never needs a tie-break.

Sessions cascade from `users`; `sync_records` and `sync_state` cascade from `datasets`, which is why
deleting one member of a shared household does not take the household's feed with them.

## Migrations

`PRAGMA user_version`, no bookkeeping table. `currentSchemaVersion = 4`; `migrate()` applies each
missing step in order and stamps the version **per step**, so a failure part-way through a
multi-version upgrade does not re-run what already committed.

**Forward-only.** There is no down path, so rolling a deployment's image back past a schema version
is not symmetric with upgrading — see `DEPLOYMENT.md` before pinning an older tag.

| v | Change |
|---|---|
| 1 | Everything from before versioning existed (`users`, `sessions`, `sync_records`, `sync_state`). Every statement is `IF NOT EXISTS`: a pre-versioning deployment reports `user_version = 0` while already having these tables. |
| 2 | Adds `users.name` and `users.is_admin`, and promotes the earliest account. An instance provisioned before roles existed would otherwise have no administrator and no reachable way to appoint one. |
| 3 | Adds `datasets` and `dataset_members`, seeding one dataset per existing user. Behaviour unchanged by this step alone. |
| 4 | Re-keys `sync_records` and `sync_state` from user to dataset. |

**A dataset's id equals its founding member's user id, for datasets created by v3's seed.** That was
what made the migration free — `sync/<userId>` was already the right directory once read as
`sync/<datasetId>`, and stored `user_id` values were already valid dataset ids. It is a coincidence
of the seed, *not* a rule: datasets allocated later start above the seeded block. Code that assumes
`datasetId == userId` will work on the operator's own instance and break on somebody's second
account.

Two things v4 shows that are worth copying if another re-keying is ever needed: the tables are
rebuilt rather than renamed in place (a renamed column keeps the old foreign key, which would have
left `dataset_id` pointing at `users`), and any reader still saying `user_id` then fails loudly with
"no such column" instead of silently serving another dataset's rows.

---

Why: `specs/06-shared-household-data.md` (datasets), `specs/04-stage-2-instant-sync.md` (the feed
tables), `specs/05-accounts-and-admin.md` (roles).
