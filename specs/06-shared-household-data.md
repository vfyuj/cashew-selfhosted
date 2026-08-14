# Shared household data (Stage 4)

**Implemented 2026-08-12.** This file described a design; it now describes what
shipped, and where the shipped thing deliberately differs from the design.

Up to and including `05-accounts-and-admin.md` the fork kept `00-overview.md`
principle 3: two accounts on one server are fully isolated, each with their own
private multi-device sync. This is the stage that changed that.

## What was asked for

A family instance where two adult accounts share one budget with full access to
everything, and every other account is an ordinary isolated one — an
administrator can create it and reset its password, but cannot see its
transactions from inside the app. Explicitly *not* a parent/child hierarchy;
two roles and nothing finer.

## The model

Two orthogonal axes. **Do not collapse them.**

| | `users.is_admin` | dataset membership |
|---|---|---|
| controls | provisioning accounts, resetting passwords | which synced data you see |
| household members | typically yes | same dataset |
| everyone else | no | own dataset |

Collapsing "administrator ⇒ shares the budget" would mean granting somebody
administration silently merged their finances into the household's, and
removing it detached them from the household's data.

Isolated accounts are literally the behaviour every account already had, so
that half cost nothing to build. Only the sharing side is new.

**Sharing is set at account creation only.** There is no endpoint to move an
existing account into a household, because merging two datasets means merging
two sets of rows that share no primary keys — every wallet, category and
transaction would be duplicated. The second member's account is created with
the switch on and signed into on a fresh install, where the app already
converges correctly (see "Why a fresh install just works" below).

## Storage scoping

`UserFileStore` already took an arbitrary namespace and id, so pointing it at a
dataset was close to mechanical. What was not mechanical:

- **The change feed had to be re-keyed, not reinterpreted.** `sync_records` and
  `sync_state` were rebuilt with `dataset_id` and a foreign key onto `datasets`.
  A `RENAME COLUMN` would have kept the old foreign key pointing at `users`, and
  then removing one member of a household would have cascaded the whole
  household's feed away. Rebuilding also makes any reader still saying `user_id`
  fail loudly instead of silently serving the wrong scope.
- **The migration is free.** v3 seeds each existing user a dataset whose id
  equals their user id, so `data/sync/<userId>` is already correct as
  `data/<ns>/<datasetId>` and the values already in `sync_records.user_id` are
  already valid dataset ids. No files move, no rows are rewritten.
- **`SyncHub` is keyed by dataset.** Miss this and the other member's device
  never wakes — it still syncs on the 45s/5min poll, so it fails slowly and
  reads as "sync is laggy" rather than broken.
- **Attachments follow the dataset**, and must: `attachmentUrl()` writes the
  server URL into the transaction's note, and the note syncs, so a user-scoped
  receipt would 404 for the other member.
- **Backups stay per-user.** Not an oversight. `createBackup` names a file
  `db-v<schema>-<deviceName>`, and `getCurrentDeviceName()` strips clientID's
  millisecond suffix down to the device model, so two same-model phones in one
  household would silently overwrite each other's backups; and
  `deleteRecentBackups` prunes across the whole listing, so one member's
  automatic backup would evict another's. Each member keeping their own history
  costs nothing — they are snapshots of the same shared database, so either
  member's restores the household. An `api_test.dart` case pins this against a
  future "consistency" cleanup.
- **Deleting a member no longer deletes the dataset's files** unless they were
  its last member. Dropping the `datasets` row is now what reaps the feed,
  since `sync_records` no longer hangs off `users`.

`clientID` uniqueness, which the original design listed as work, turned out to
already hold: it carries a `millisecondsSinceEpoch` suffix. The collision was
in the *backup* filename instead, which the decision above avoids.

## Privacy: on budgets, not on transactions

The original design put privacy on **transactions** and flagged its own flaw —
hiding a transaction makes the other person's wallet balance and totals
disagree with reality, which is worse than the problem being solved. It then
recommended wallet-level privacy instead.

What shipped puts it on **budgets**, which is better than either. A budget is a
target and a grouping, not an amount in a balance: hide one and every remaining
number stays correct. It also needed no schema change, because `Budgets` has a
dead column to borrow and `Wallets` does not.

- Custom budgets default to belonging to whoever created them. Main-category
  envelopes are always the household's — they are the shared plan, and the
  over-allocation check measures against them.
- Stored in `Budgets.sharedMembers` via `app/lib/struct/budgetVisibility.dart`,
  the same borrowed-dead-column trick and the same single-owner discipline as
  `budgetPeriodAmounts.dart` next door.
- `sharedMembers` rather than `sharedKey` deliberately: the two surviving bits
  of Firestore UI that would render this are both gated on `sharedKey`, and
  nothing writes it. Borrowing `sharedMembers` leaves those dead paths dead.

**Everything syncs, including hidden budgets; hiding is at the UI layer only.**
This is a deliberate call, not a shortcut. The over-allocation check below has
to count budgets the viewer cannot see, or a household can silently
over-commit a category. State the consequence honestly wherever it matters:
this hides a budget from the app, not from anyone with a SQLite browser.

The one place another member's budget is admitted is the manage-budgets screen,
where it appears without its name, at half opacity, and completely inert — no
rename, reorder, delete, open or unhide — so it can never be promoted onto this
device's budgets page.

## Subcategory budgets sum to their main category

New in this stage, and the reason personal budgets sync. Budgets for a main
category's subcategories could be created without limit and none of them
touched the envelope they sit under, so a household could plan 1200 of spending
inside a category budgeted at 1000 and find out at the end of the month.

`app/lib/struct/subCategoryBudgetAllocation.dart` measures each main category's
subcategory budgets against its envelope and warns when they exceed it, offering
to raise the envelope so they fit. Under-allocating is fine and never warns.

- Amounts are converted to the envelope's period before summing, so a weekly
  budget and a monthly one can be added together. Nothing in the app normalized
  periods before this, so it is established locally rather than retrofitted onto
  `totalPlannedExpenses`.
- Both sides go through `budgetAmountToPrimaryCurrency`.
- Raising the envelope goes through `withUpdatedAmountHistory`, so finished
  periods keep the target they were set to at the time (BL-006).
- Expenses only. Budgets spanning several categories, or none, cannot be
  attributed to one parent and are left out rather than guessed at.

Because hidden budgets count, the figures will not always add up against the
cards on screen. The copy says so when it applies.

## Per-user views

Layout preferences lived in `sharedPreferences`, so they were per *device* — a
member's phone and laptop never agreed — and the only account-level control over
which accounts appear on the home page was `Wallets.homePageWidgetDisplay`, a
synced column, so hiding an account hid it for everyone.

Shipped as one `AppSettings` row per member, keyed by their server user id,
carrying a short allow-list of view preferences (`app/lib/struct/perUserViewSettings.dart`).
Row 0 keeps its existing job as the device-local settings blob and is excluded
from the feed — that exclusion is the safety property that makes syncing this
table acceptable at all, since row 0 holds the server URL, the signed-in email
and the cached exchange rates.

Wallet hiding was originally layered *on top of* `homePageWidgetDisplay`
rather than replacing it: the household still decided which accounts were
pinned where, and this dropped some of them from one person's view. That
turned out to be a dead end for the home page specifically (WalletSwitcher
and WalletList): upstream's old pin UI for those two was a per-account
checkmark that this feature's popup redesign replaced with the eye toggle
above, and nothing was left that could write `WalletSwitcher`/`WalletList`
back into a wallet's `homePageWidgetDisplay` once removed. Any account
hidden via the old pin — which, before this feature shipped, was the *only*
way to hide an account — became permanently stuck off the home page, with
`hiddenWalletPks` unable to reach it since it only ever subtracts.
`watchAllWalletsWithDetails` (`app/lib/database/tables.dart`) now ignores
`homePageWidgetDisplay` entirely when asked for `WalletSwitcher`/`WalletList`
and gates on `hiddenWalletPks` alone, so it is the sole visibility control for
the home page and every account is reachable through it. The column is still
live and unchanged for the Net Worth / income-expense / pie-chart
calculation-scope pickers (`getAllPinnedWallets`), which is a different
question — which accounts feed a total — and keeps its original
household-wide checkmark UI.

**The restore carve-out is load-bearing.** A backup holds every member's rows,
and `bumpAllModifiedTimestampsForResync` would stamp them as newest and push
them — so one person restoring a backup would rearrange everyone's home page.
The other members' rows are dropped before the bump.

## Restore in a shared dataset — warn, do not reset

A restore reaches everyone now, so the confirmation says so when
`householdSize > 1`. It deliberately does **not** force a Reset Sync: a restore
removes rows without creating tombstones, and a reset rewinds every peer's push
cursor to `DateTime(0)`, so they would re-upload exactly the rows the restore
removed. Warn, don't reset.

## Sync semantics that did not change

Last-write-wins on `dateTimeModified`, with no per-row authorship and no
field-level merge. Two members editing the same budget on the same evening is
now a normal case rather than an edge case, and one of them silently wins.
Left alone on purpose: it wants real two-person usage to know whether it is
actually annoying, and `04-stage-2-instant-sync.md` is the place that would
change.

## Test coverage

Server tests went from 55 to 86. `/sync/push`, `/sync/pull`, `/sync/reset` and
`SyncHub` had **no** coverage at all before this stage rewrote every statement
in them; `server/test/sync_feed_test.dart` now covers the round trip, paging,
last-write-wins, echo suppression, the clock clamp, and the reserved-seq gap
that lets a resetting device see its own re-upload.

## Non-goals

- Multi-tenant hosting. Unchanged from `00-overview.md`.
- Cryptographic privacy. Explicitly rejected in favour of UI-level hiding.
- A general permission system.
- Moving an existing account into a household, or splitting one back out.
