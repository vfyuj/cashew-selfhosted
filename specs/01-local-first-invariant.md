# Local data and offline behavior

## The goal

Cashew Selfhosted keeps upstream Cashew's local-first behavior: every transaction, budget, category, wallet, and objective lives in the local Drift database first, and the app is fully usable from that local copy regardless of whether a server is configured or reachable. Sync and backup are an optional layer on top of that data — never a gate on it.

This matters concretely in two situations, and the design should be justified by them rather than by "offline" as an abstract goal:

- **Local development and testing.** Standing up a server for every change would be wasted effort — the app should just work against local data while it's being built on.
- **A device going offline and coming back.** Normal phone behavior (subway, flight, spotty wifi), not an edge case: changes made while offline must not be lost, and must sync cleanly once connectivity returns.

Don't add UI, settings, or code paths whose only purpose is proving offline capability for its own sake — that's not the goal, and it's the failure mode this doc used to invite.

## Rules

- App launch and the core budgeting features (create/edit/delete transactions, budgets, categories, wallets, objectives) never wait on a network call. This is inherited for free from local storage; don't add anything that changes it.
- Auth/sync failures degrade to "sync paused," never to a blocked, locked, or read-only UI. Silent re-auth/token refresh happens in the background and never blocks a user-facing flow — same pattern as the old Google sign-in's `silentSignIn`.
- A local write is never lost because the server was unreachable. If sync fails, the change still exists locally and goes out on the next successful sync — there's no need for a dedicated outbox mechanism beyond the source tables themselves (see how Stage 2 relies on this in `04-stage-2-instant-sync.md`).

## Checking it

After a change that touches startup, auth, or sync: reason about the code path first — does anything on it await a network call before rendering local data, or turn an auth/sync failure into a blocked screen? That's usually enough.

Only reach for the **airplane-mode test** — network off, force-quit, relaunch, confirm the app opens to existing data, make a change, relaunch again, confirm it persisted, then reconnect and confirm the change syncs on the normal trigger — when the reasoning above is genuinely unclear. The owner runs this manually, see "Testing & verification workflow" in `CLAUDE.md`; it is not a ritual to repeat after every unrelated change.
