# How it works now

Current-state reference, one page per module. **Open the page you need, not the set** — that is the
point of splitting them.

Two shelves, and they answer different questions:

- **`docs/` (here) — how it works now.** Read from code. If it disagrees with the code, it is a bug.
- **[`specs/`](../specs/README.md) — why it was decided, and what is planned.** Design intent,
  rejected alternatives, postmortems. If it describes something that is not built yet, that is normal.

Each page ends with a pointer into `specs/` for its reasoning. Nothing is documented twice: if a fact
belongs to another page, this one links it.

## Server

| Page | Open it when |
|---|---|
| [server/api.md](server/api.md) | You need the HTTP surface — every route, its auth level, its scope. Guarded by a test, so it cannot silently rot. |
| [server/sync.md](server/sync.md) | You are touching push/pull, sequence numbers, the wake-up socket, or Reset Sync. |
| [server/auth.md](server/auth.md) | Sessions, passwords, rate limiting, first-run setup, roles, provisioning. |
| [server/storage.md](server/storage.md) | Files on disk: the three namespaces, and why backups are scoped differently from everything else. |
| [server/database.md](server/database.md) | The server's own SQLite — tables and migrations. Not the app's database. |
| [server/rates.md](server/rates.md) | Currency rates: why the server holds them, and why they are instance-wide rather than per household. |

## App

| Page | Open it when |
|---|---|
| [app/database.md](app/database.md) | Anything near the Drift schema. Explains the upstream-compatibility invariant and the one table the fork owns. |
| [app/sync-client.md](app/sync-client.md) | The device side of sync: cursors, the cycle, triggers, rebootstrap. |
| [app/budgets.md](app/budgets.md) | Short: budgets are upstream's, unmodified. Read it to find out what used to be here and where it went. |
| [app/envelopes.md](app/envelopes.md) | The monthly plan per category — the fork's own table, how a month resolves, and the one-shot conversion from the old envelope budgets. |
| [app/settings.md](app/settings.md) | Which preferences follow a person between their devices, and why row 0 must never sync. |

## Operations

Not in here — these are for the person running the server, and they live at the repo root:

- [`DEPLOYMENT.md`](../DEPLOYMENT.md) — deploying on a home server, upgrading, administrator bootstrap.
- [`RUNNING_LOCALLY.md`](../RUNNING_LOCALLY.md) — building and running the app locally to test a change.
- [`README.md`](../README.md) — what the fork is, and how someone installs it.

## Adding a page

Keep pages in the 60–200 line band. Finer than that and a reader pays for an index lookup plus
several reads to learn one thing; coarser and they load a module's worth of text to check one fact.
Add the row here at the same time, with a real "open it when" — an index nobody trusts sends people
back to reading the source.
