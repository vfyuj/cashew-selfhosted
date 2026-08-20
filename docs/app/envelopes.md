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
| Order | `Categories.order`, the household's own column — the same order the categories screen has, dragged into shape on Edit Envelopes. Shared, not personal: everyone with the same data sees the same order. |
| Visibility | The category list's. Envelopes have no list of their own to hide from. |
| Amount | `RealColumn`, plus the account whose currency it is counted in (`walletFk`). Zero is a real answer, meaning "nothing planned". |

`struct/categoryEnvelopes.dart` owns all of it, and the parts that are decisions rather than queries
are pure functions with tests (`test/category_envelopes_test.dart`).

## Five rules worth knowing

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

**An amount is a number *and* the account its currency belongs to.** `walletFk`, exactly as budgets,
objectives and category limits record theirs, and read back through
`envelopeAmountToPrimaryCurrency` (`struct/currencyFunctions.dart`). Without it an envelope was a
bare number whose meaning changed under it: plan 50,000 with a ruble account selected, make a dollar
account primary, and the plan read $50,000 while the spending measured against it had been converted
properly — a card comparing two different currencies and calling one of them overspending. The number
pad edits the amount **as stored**, in its own account's currency, and offers an account picker only
where the household keeps more than one currency; everything else on screen — the cards, the section
totals, Planned vs Actual — is converted to the primary account's currency by `EnvelopePlan`, so it
moves with the primary account the way every other figure in the app does.

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
envelopes rather than a spreadsheet. Inside each card: the category, the two figures that describe
it, the planned amount as a tap target of its own, and the **budget card's own `BudgetProgress`
bar** — reused directly from `widgets/budgetContainer.dart`, so the percent label, the overspend
shake and the "today" marker behave exactly as they do on a budget. The marker only appears on the
current month; a month that has ended has no today to mark.

**Which of the two figures leads is the reader's choice**, exactly as it is on a budget:
`showTotalSpentForEnvelope` (device-local, like `showTotalSpentForBudget`) swaps between leading with
what is left and leading with what has moved. Both figures are always shown, so the setting changes
the emphasis and never hides a number. One helper decides it for every screen —
`envelopeHeadline` in `pages/envelopesPage.dart` — so the card and the detail page cannot disagree.
A category with no plan at all always leads with what moved: there is no "remaining" to lead with.

The pencil in the corner opens **Edit Envelopes** (`pages/editEnvelopesPage.dart`): drag to reorder,
and a corner button for the total-type setting. It is deliberately smaller than Edit Budgets —
there is no add button and no delete, because an envelope exists because a category exists. Tapping a
row opens the category, which is where a name, colour or icon actually lives. The setting sheet is
upstream's own `TotalSpentToggle` pointed at the envelope key rather than a second copy of it.

**Reordering writes `Categories.order`**, so it rides the ordinary change feed, everyone sharing the
data ends up with the same order, and the screen redraws itself — the order is a query, not a
setting, so there is nothing to store, refresh or reconcile. The visible consequence is deliberate:
this is the *same* order the categories screen has. A per-account order was built first and
withdrawn; the reasoning, and why the per-user settings mechanism could not carry it, is in
[settings.md](settings.md).

The screen draws the two sides of the ledger as two lists, because a drag that moved a category
across the divide would look like it had done nothing. Each list rearranges only the order slots its
own categories already hold (`reorderCategoriesWithinTheirSlots`), so reordering expenses cannot
disturb the income categories or the balance-correction category sitting between them. `moveCategory`
is the wrong tool for that — it shifts everything between the two positions by one.

Tapping the card opens `pages/envelopeDetailsPage.dart` — that category, that month, **shaped like
the budget page**:

- the category's colour seeds the whole page through `CustomColorTheme`, so the app bar and the block
  under it are a tint of it rather than the app's accent, and the progress bar keeps its contrast
  because `BudgetProgress` derives its own track from the same colour;
- the figure and its clause sit in the app bar as the subtitle, tappable to swap the total type —
  literally the same widget the budget page uses, `widgets/swappableTotal.dart`, which takes what the
  two figures are *called* as its only parameter;
- the month's name sits under the bar. It is a label, not a timeline: an envelope is always exactly
  one calendar month, so there is no range to draw. There is **no pie chart and no
  spending-over-time graph** either — one category for one month has nothing to divide;
- **where the money went inside the category**, in upstream's own `CategoryEntry` box
  (`widgets/categoryEntry.dart` + `SubCategoriesContainer`): the progress ring on each icon is that
  row's share, subcategories sit under their main category, and each row carries its transaction
  count. Tapping a row narrows the transaction list below to it, as selecting a slice does on a
  budget. The query is `includeAllSubCategories: true` with **`countUnassignedTransactions: true`**,
  which is the pairing `watchTotalSpentInTimeRangeHelper` is written for: the main category's row
  counts every transaction in the category and each subcategory's counts its own, and the helper
  sums only rows with no main category of their own. The earlier version of this page hand-summed
  every row instead, and *that* arithmetic needs `countUnassignedTransactions: false` or the total
  comes out doubled. Either pairing is correct with its own summing; mixing them is what doubles the
  number, so the flag and the helper move together;
- **the month's transactions**, drawn by `TransactionEntries`, the same widget the transactions list
  and the budget page use, so selecting, editing and swiping behave as they do everywhere else.

Two consequences of using upstream's box rather than a hand-rolled list, both accepted: there is **no
dedicated "no subcategory" row** any more — the main category's row carries the whole total and the
subcategory rows fall short of it — and a category with **no** subcategories now shows one row rather
than nothing, which is where its transaction count lives.

The amount is set from the card, or from **Set amount** in the detail page's corner menu, beside
**Edit category** — the same two-item menu shape the budget page has. Long-pressing a card also opens
the category.

**The two sides of the ledger do not read the same way, and that is deliberate** (`envelopeActionWord`
/ `envelopeStatusWord` / `envelopeStatusColor` / `envelopeStatusSpans` in `pages/envelopesPage.dart`).
Money going out is *spent in total*, what is left is *left*, and passing the plan is *overspent*, in
red. Money coming in is *received*, what has not arrived yet is *still to come*, and passing the plan
is *above plan*, in green — being paid more than you expected is not an overspend, and colouring it
like one is telling the household that good news is a problem.

The expense side is also punctuated differently, for a reason worth keeping: two full sentences with
the leading clause in bold, rather than one comma-spliced phrase. "6,428 overspent, 37,232 spent"
reads as though the second number were another slice of the first; a full stop makes them the two
separate statements they are. *Overspent* rather than a bare *over* because the figure beside it is
what the category went over **by**, and *in total* because the other figure is the whole month's
spending, not a part of the plan. The income side keeps its comma and its words: "received" was never
ambiguous. Both sides bold the leading clause, which is presentation rather than wording.

## Elsewhere in the app

- **The home page** (`pages/homePage/homePageEnvelopes.dart`) carries the same cards in a horizontal
  carousel — `widgets/homePageCardCarousel.dart`, shared with the pinned budgets — as its own
  section, toggled and reordered from Edit Home like every other one (`showEnvelopes`, key
  `"envelopes"`). It shows **only envelopes with an amount set for this month**: every main category
  has an envelope, which is right for the envelopes page and wrong here, where a household with twenty categories would get twenty cards to swipe
  through, most of them empty.
- **Planned vs Actual** (`pages/homePage/homePagePlannedVsActual.dart`) reads envelope totals for its
  Planned card and the month's transactions for its Actual one. It sits on the home page and at the
  top of the envelopes page, following whichever month is on screen. It takes an already-built plan
  when it is given one: the envelopes page builds a single `EnvelopePlanBuilder` for the whole screen
  and hands it down, because each builder holds two live queries and three side by side meant six
  subscriptions for one screen's worth of the same two answers.
- **Onboarding** (`pages/onBoardingPage.dart`) fills in this month's envelopes: the income step and
  the spending step are one row per category, writing straight to this table. No account picker here
  on purpose — it is a list of numbers typed quickly in the primary account's currency, which is what
  the rows are stamped with.
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

**Two table enumerations have to name it, and both were missed when the table was added in 1.2.0**
(fixed in 1.2.2, pinned by `test/envelope_sync_enrolment_test.dart`). Neither failure says anything:
every screen keeps working and every amount saves, the plan just never leaves the device it was typed
on, and the rest of the household sees zeroes.

- `watchAllForAutoSync` — the tables whose writes wake a sync cycle. Without it, typing an amount
  pushed nothing; the row only went out when an unrelated table happened to be written, so a plan set
  and then left alone could sit on one device indefinitely.
- `bumpAllModifiedTimestampsForResync` — run once after a restore, so restored rows are newer than
  what peers have already synced from this device. Without it, the envelopes in an imported backup
  kept their exported timestamps, `getAllNewCategoryEnvelopes` never picked them up, and the whole
  plan stayed on the importing device while its categories and transactions travelled normally.

A fork-owned table added later needs both, and a test here.

Deleting a category deletes its envelopes, with tombstones
(`deleteCategoryEnvelopesInCategory`).

## Converting the old envelope budgets

`database/envelopeMigration.dart`, run from `initializeDefaultDatabase()` — that
is, **on every launch**, not once.

It finds the budgets the old implementation created for itself, turns each
recorded past amount into a row — carrying over the budget's own `walletFk`,
since the envelope means the same thing in the same currency — and deletes the
budget with a tombstone so the household's other devices lose it too. Every
other budget is untouched except for having the two dead columns nulled out,
which is what makes it a plain upstream budget again.

Three details carry the weight:

- **An envelope budget is identified by `budgetPk == categoryPk`, and only
  that.** `ensureMainCategoryBudgetsExist` keyed every envelope it created by
  the category's own pk; a hand-made budget gets a uuid. So the test is a
  property of the row, not a guess about intent — which is what makes it safe to
  run forever. A budget that merely *targets* one main category (the old code
  could adopt one as an envelope) stays a budget: it is one somebody made by
  hand, deleting it would be the only irreversible thing here, and it is a
  perfectly good upstream budget now. The cost of that choice is real and is
  accepted: the category it stood in for comes up with **no plan**, and its
  amount history is gone with the dead column, so the household re-enters that
  one amount by hand. The 1.2.0 changelog says so rather than promising a clean
  sweep.
- **The month a budget without history lands in is the budget's own start, not
  the day the conversion happens** (`legacyBudgetMonth`, clamped so a hand-edited
  future start cannot put the plan in a month nothing reads back). Two devices
  converting the same household in different months would otherwise write the
  same plan into two months, and both would count.
- **Nothing here may throw.** The conversion is awaited on the startup path, and
  everything after it — starting the first sync of the launch — is skipped if it
  does. Each budget is converted inside its own `try`, with a second one around
  the whole pass, so a row the conversion cannot make sense of costs that row
  and nothing else (`specs/01-local-first-invariant.md`).
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
