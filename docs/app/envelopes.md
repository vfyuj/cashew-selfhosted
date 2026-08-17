# Envelopes

How much each category is meant to get this month. A side-menu entry of its own
(`pages/envelopesPage.dart`), deliberately separate from [budgets](budgets.md), which are upstream's
and stay that way.

## The model

One row per category per month, in the fork-owned `CategoryEnvelopes` table
([database.md](database.md)). Everything else is derived:

| | |
|---|---|
| Period | One calendar month. There is no other option, so there is no cycle to configure. |
| Which categories | Main categories, minus the balance-correction category `"0"` (corrections and transfers are not planned spending). Subcategories roll up into their parent. |
| Income or expense | Read from `Categories.income`. **Never stored on the envelope.** |
| Order and visibility | The category list's. Envelopes have no list of their own to sort or hide. |
| Amount | `RealColumn`, in the primary currency. Zero is a real answer, meaning "nothing planned". |

`struct/categoryEnvelopes.dart` owns all of it, and the parts that are decisions rather than queries
are pure functions with tests (`test/category_envelopes_test.dart`).

## Four rules worth knowing

**Every main category has an envelope, always.** Not "once something has created one" — the screen is
built from `watchAllCategories()`, and a row exists because the category does
(`widgets/envelopePlanBuilder.dart`). A stored row carries an *amount*, nothing more, so a household
that has never opened this screen still sees its whole plan laid out at zero, and no conversion,
backup import or sync state can produce an empty page while categories exist. The category list is
the outer stream for exactly this reason; amounts and spending totals are inner ones, and a failure
in either shows as a missing number rather than a missing row.

**It follows the category list through every change.** Create a category and its envelope is there on
the next stream emit; delete it and its rows go too, with tombstones. Demote a main category to a
subcategory and it drops off the plan while its rows stay in the table — promote it back and the
amounts it had come back with it. All of this falls out of deriving the list rather than storing it;
`test/schema_migration_test.dart` pins the whole sequence.

**The primary key is derived, not generated:** `"<categoryPk>:<yyyy-MM>"`. Two devices that set the
same category's amount for the same month write the same row, so the merge is a normal
last-write-wins on one row instead of two rows that both count. This is the one part of the old
envelope budgets that worked, and it is kept.

**A month with no row of its own is not empty.** It resolves to the nearest *earlier* month that has
one — so "same amount every month" costs a single row, and a month you have never opened already
shows the plan. Nothing is written in the background, and a later month never affects an earlier one:
setting March in advance leaves February reading February's own amount.

Between them these remove the entire class of problems the previous implementation spent its code on:
duplicate envelopes, envelopes whose income flag drifted away from the category's, envelopes
reappearing after being deleted, and zero-amount rows racing real ones through sync at first launch.
There is no reconciler here, because there is nothing to reconcile.

## The screen

A card per category, not a table row: the app's plain surface (white, or the lightened accent under
Material You) with a shadow tinted to the category's own colour, so the list reads as a row of
envelopes rather than a spreadsheet. Inside each card: the category, what has been spent and what is
left, the planned amount as a tap target of its own, and the **budget card's own `BudgetProgress`
bar** — reused directly from `widgets/budgetContainer.dart`, so the percent label, the overspend
shake and the "today" marker behave exactly as they do on a budget. The marker only appears on the
current month; a month that has ended has no today to mark.

Tapping the card opens `pages/envelopeDetailsPage.dart` — that category, that month:

- the same card, larger, with the amount still editable;
- **where the money went inside the category**: one row per subcategory plus one for transactions
  filed straight under the category, with each row's share of the total. The query is
  `includeAllSubCategories: true` with `countUnassignedTransactions: false`, and that pairing is
  load bearing — it partitions the transactions. With `countUnassignedTransactions: true` the main
  category matches *every* transaction as well as its subcategory, and the page reports exactly
  double what was spent;
- **the month's transactions**, drawn by `TransactionEntries`, the same widget the transactions list
  and the budget page use, so selecting, editing and swiping behave as they do everywhere else.

Tapping the amount — on the card or in the header — opens the number pad. Long-pressing a card opens
the category itself.

**The two sides of the ledger do not read the same way, and that is deliberate** (`envelopeActionWord`
/ `envelopeStatusWord` / `envelopeStatusColor` in `pages/envelopesPage.dart`). Money going out is
*spent*, what is left is *remaining*, and passing the plan is *over*, in red. Money coming in is
*received*, what has not arrived yet is *still to come*, and passing the plan is *above plan*, in
green — being paid more than you expected is not an overspend, and colouring it like one is telling
the household that good news is a problem.

## Elsewhere in the app

- **The home page** (`pages/homePage/homePageEnvelopes.dart`) carries the same cards in a horizontal
  carousel, the shape the pinned budgets use, as its own section — toggled and reordered from Edit
  Home like every other one (`showEnvelopes`, key `"envelopes"`). It shows **only envelopes with an
  amount set for this month**: every main category has an envelope, which is right for the envelopes
  page and wrong here, where a household with twenty categories would get twenty cards to swipe
  through, most of them empty.
- **Planned vs Actual** (`pages/homePage/homePagePlannedVsActual.dart`) reads envelope totals for its
  Planned card and the month's transactions for its Actual one. It sits on the home page and at the
  top of the envelopes page, following whichever month is on screen.
- **Onboarding** (`pages/onBoardingPage.dart`) fills in this month's envelopes: the income step and
  the spending step are one row per category, writing straight to this table.
- **"% of planned income"** is a convenience when setting an expense amount, not a stored setting.
  The percentage is resolved against this month's income envelopes and the plain number it comes to
  is what gets saved.

## Sync

Household data, on the ordinary dataset change feed, like transactions and categories:
`UpdateLogType.CategoryEnvelope` and `DeleteLogType.CategoryEnvelope`, both **appended** to their
enums because `DeleteLogs.type` stores the index on disk. Collected by `getAllNewCategoryEnvelopes`
and merged by the `processSyncLogs` branch, in the `toCompanion(false)` form every branch uses.

**The server needed no change.** `sync_records` is keyed by `(dataset_id, table_name, pk)` and is
indifferent to a table name it has never seen.

Deleting a category deletes its envelopes, with tombstones
(`deleteCategoryEnvelopesInCategory`).

## Converting the old envelope budgets

`database/envelopeMigration.dart`, run from `initializeDefaultDatabase()` — that
is, **on every launch**, not once.

It finds the budgets the old implementation created for itself, turns each
recorded past amount into a row, and deletes the budget with a tombstone so the
household's other devices lose it too. Every other budget is untouched except
for having the two dead columns nulled out, which is what makes it a plain
upstream budget again.

Three details carry the weight:

- **An envelope budget is identified by `budgetPk == categoryPk`, and only
  that.** `ensureMainCategoryBudgetsExist` keyed every envelope it created by
  the category's own pk; a hand-made budget gets a uuid. So the test is a
  property of the row, not a guess about intent — which is what makes it safe to
  run forever. A budget that merely *targets* one main category (the old code
  could adopt one as an envelope) stays a budget: it is one somebody made by
  hand, deleting it would be the only irreversible thing here, and it is a
  perfectly good upstream budget now.
- **No "this device has migrated" flag.** That was the first design and it was
  wrong: a flag is a statement about the device, and the data does not arrive
  with the device. It arrives when a backup is imported, when the first sync
  pull lands, or when a household member still on the old version recreates an
  envelope budget. A device that had "migrated" an empty database would never
  look again, and the household's envelopes would sit there as budgets forever.
  Running every launch costs two queries once there is nothing left to convert.
- **Envelope rows are written `insertOrIgnore`, and a budget whose category this
  device has never heard of is left completely alone.** The first stops a device
  converting late from overwriting what the household has edited since; the
  second stops a category that simply has not synced yet from being read as a
  deleted one (`specs/01-local-first-invariant.md`). A later launch, once it has
  arrived, converts it.

Devices converge without coordinating, because the envelope pk is derived from
the category and the month rather than generated. While one device is still on
the old version it will keep recreating its envelope budgets — stamped
`DateTime(0)`, so they lose last-write-wins against the conversion's tombstones —
and will not see new envelopes at all. That is expected until every device is
updated.

`test/schema_migration_test.dart` runs all of this against a real SQLite
database migrated from v46, which is the shape an imported 1.1.x backup has.

The table itself is created in `beforeOpen` rather than trusted to the migration
step, because a backup from a *newer* upstream Cashew arrives with a schema
version above the fork's and gets no migration at all — see
[database.md](database.md). Without that, the screen renders (it is built from
categories) but every amount typed into it is dropped on a table that does not
exist.

---

Why: `specs/backlog/BL-001-category-locked-budgets.md` (what envelopes replaced and why the
budget-shaped version was withdrawn).
