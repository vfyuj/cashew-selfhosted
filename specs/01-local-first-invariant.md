# Local-first invariant

**This is a hard constraint. It overrides convenience, elegance, or "the server design implies X." If a design decision anywhere else conflicts with this file, this file wins and the other design must change.**

## The rule

The app must be fully usable with zero network connectivity, indefinitely. Authentication state must never gate access to locally-stored data or core functionality.

## Why

This is how upstream Cashew already works: data lives locally by default, Google/Drive is purely an optional sync/backup layer on top. Confirmed in upstream source — every sync entry point starts with a guard like `if (appStateSettings["hasSignedIn"] == false) return false;`, which no-ops sync rather than blocking anything. The fork must preserve this property exactly, even though it adds a self-hosted server that feels more "central" than a personal Google account did. The server is an enhancement layer. It is never a dependency for core usage.

## MUST

- App launches and reaches a fully usable main UI without any network call succeeding or even being attempted synchronously.
- Creating, editing, and deleting transactions, budgets, categories, wallets, objectives, etc. always writes to the local Drift database first, immediately, regardless of connectivity or auth state.
- A user who never signs in and never configures a server can use 100% of budgeting/tracking features, forever. This is not a degraded/trial mode — it's the baseline.
- Sign-in and sync, when configured, operate in the background. A failed or expired session degrades to "sync paused" — never to "app blocked," "data hidden," or "read-only until you log in."
- All outbound sync events are queued in a persisted local outbox and sent opportunistically. A backlog of any size or duration must never corrupt, block, or lose local data.
- Silent/background re-auth follows the existing pattern already used for Google sign-in (`waitForCompletion: false, silentSignIn: true`) — attempt quietly, never block the UI thread or a user-facing flow on its result.

## MUST NOT

- Must not require a successful login before reaching the main app screen.
- Must not perform a blocking/synchronous network call on startup before rendering local data.
- Must not delete, lock, or hide local data because of auth/session expiry.
- Must not silently drop locally-made changes because the server was unreachable — they persist in the outbox until synced, even if that's never.
- Must not introduce a code path where a network timeout raises an error the user has to dismiss before they can keep using the app.

## Acceptance test ("airplane mode test")

Run this after any change touching auth, sync, or app startup:

1. Enable airplane mode on the test device.
2. Force-quit and relaunch the app.
3. Confirm: app loads to the main screen, all previously-synced data is visible.
4. Create a new transaction, edit a category, delete a budget.
5. Force-quit and relaunch again, still in airplane mode. Confirm all changes from step 4 persisted.
6. Disable airplane mode. Confirm queued changes sync without any user action beyond whatever the normal sync trigger is for that stage (manual pull in Stage 1, automatic in Stage 2).

If any step fails, the change under test is not done, regardless of what else it achieves.
