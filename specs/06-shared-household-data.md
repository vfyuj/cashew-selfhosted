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

## Privacy: on budgets, not on transactions — CANCELLED 2026-08-17

**This shipped and was then withdrawn in release 1.2.0. Recorded because the
reasoning still stands; the code is gone.** Every budget is the household's
again, `Budgets.sharedMembers` is a dead column once more, and the conversion in
`database/envelopeMigration.dart` nulls it out.

What was decided, and why it was still the right shape of answer: the original
design put privacy on **transactions** and flagged its own flaw — hiding a
transaction makes the other person's wallet balance and totals disagree with
reality, which is worse than the problem being solved. Putting it on **budgets**
avoided that: a budget is a target and a grouping, not an amount in a balance,
so hiding one leaves every remaining number correct. Custom budgets belonged to
whoever created them; main-category envelopes were always the household's.
Everything still synced, and hiding happened only at draw time — stated openly,
because the over-allocation check below had to count budgets the viewer could
not see.

**Why it was cancelled.** Three things, none of them the privacy idea itself:

- It rested on the same dead-column storage as the per-period amounts (BL-006),
  with the same "this column's name lies" tax on every reader, and the same
  parser that had to stay strict against an original-Cashew backup's real member
  IDs arriving in it.
- "Hidden from the app, not from a SQLite browser" is a genuinely awkward thing
  to have to keep saying, and the one screen that had to admit another member's
  budget existed — nameless, half opacity, completely inert — was the shape of a
  feature arguing with itself.
- It was never asked for twice. The household that motivated Stage 4 shares its
  data; the budgets it kept apart were a nice-to-have, and the fork paid for it
  in every budget screen at once.

Personal *views* — which is what people actually notice — are being answered
separately, by their own channel rather than by the dataset feed. See the
per-user views section below.

## Subcategory budgets sum to their main category — CANCELLED 2026-08-17

**Also withdrawn in 1.2.0, together with personal budgets, which it was the
reason for syncing.**

The problem it addressed was real: budgets for a main category's subcategories
could be created without limit while none of them touched the envelope they sit
under, so a household could plan 1200 of spending inside a category budgeted at
1000 and find out at the end of the month. The check summed subcategory budgets
per parent — normalising periods so a weekly and a monthly budget could be added
— and offered to raise the envelope to fit.

**Why it was cancelled.** It only existed because envelopes *were* budgets. Now
that an envelope is a row in its own table with one amount per month, a budget
underneath a category is just a budget: it is not part of the plan and there is
nothing for it to over-allocate. The warning would have had nothing coherent to
measure. Reintroducing an over-allocation check on top of envelopes is a
sensible future request, but it would be a new design, not this one restored.

## Per-user views

Layout preferences lived in `sharedPreferences`, so they were per *device* — a
member's phone and laptop never agreed — and the only account-level control over
which accounts appear on the home page was `Wallets.homePageWidgetDisplay`, a
synced column, so hiding an account hid it for everyone.

Shipped as one `AppSettings` row per member, keyed by their server user id,
carrying a short allow-list of view preferences (`app/lib/struct/perUserViewSettings.dart`).
Row 0 keeps its existing job as the device-local settings blob and is excluded
from the feed — that exclusion is the safety property that makes syncing this
table acceptable at all, since row 0 holds the server URL and the signed-in
email.

### Sharing data forces a shared reading of it (added 2026-08-20)

Row 0 also held the cached currency table, and that turned out to be a real bug
rather than a harmless leftover. Every device fetched the published rate feed
itself and cached it there, so nothing shared it: the owner found the same
18 950 ₽ transaction counted as 22 594 dinars in one account and 22 837 in the
other, and every budget and envelope touching a foreign currency disagreed by
about a percent. Two devices, last launched days apart, holding two snapshots of
a moving rate.

The general point, worth applying to the next setting as well: **this stage made
the data shared, and anything that decides how that data is *read* has to become
shared with it.** A rate is not identity like a server URL or an email — it is an
interpretation, and an interpretation everyone has to agree on. It was filed with
the device-local keys on the grounds that it lived in `appStateSettings`, which
is not a reason for anything.

Fixed by moving the table to the server (`docs/server/rates.md`), not by adding
it to the sync feed. Rates are wider than a household — every account on a
deployment wants the same ones — and the per-user mechanism here has no
household-wide level at all, since its rows are keyed by user id. Administrator
overrides moved with it, for the same reason: one member pinning a rate locally
would have put the household straight back out of step.

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
- Cryptographic privacy. Explicitly rejected in favour of UI-level hiding — and
  since 1.2.0 there is no per-budget hiding either, so nothing in the household's
  data is hidden from anyone in the household.
- A general permission system.
- Moving an existing account into a household, or splitting one back out.
