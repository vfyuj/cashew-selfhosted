# BL-001 — Category budgets, percent-of-income entry, and share-of-plan labels

**Status:** Implemented 2026-08-09 on branch `claude/new-budgeting-system-88283e`. Not yet
acceptance-tested by the owner.

**Origin:** owner-submitted feature request (2026-08-09), reviewed against the fork source, then
**redesigned by the owner** the same day around a hard "no schema changes" constraint. This document
describes what was built. The earlier schema-based design is summarised in §8 for context — it is
superseded, not deferred.

**Local-first check:** ✅ no conflict with `specs/01-local-first-invariant.md`. Everything here is
local Drift reads/writes and local computation. Nothing gates on auth or connectivity.

**Upstream-compatibility check:** ✅ `app/lib/database/tables.dart` is untouched. `schemaVersionGlobal`
is still 46 and the 10 tables are byte-identical to upstream's, so the hard invariant in `CLAUDE.md`
holds and original-Cashew backups still import.

---

## 1. What this delivers

The household runs a spreadsheet with two columns — expense categories and income categories, each
with a planned figure. That is envelope budgeting, and Cashew has no first-class notion of it: a
`Budget` may reference any number of categories, and nothing ties one to a single category.

This adds that notion **without storing anything new**:

1. Every main category automatically gets one budget — its envelope.
2. The budgets list splits into **Main Categories** and **Custom** tabs.
3. An expense budget's target can be entered as a **percentage of planned income**, which is resolved
   to a plain number at entry time.
4. Each category budget card shows its **share of total planned expenses**.

### Worked example

Income budgets: Salary 2000 + Freelance 300 → **planned income = 2300**.
Entering "10%" on the Savings envelope writes `230` into its amount field — a plain number, no
different from typing it. With Rent 800, Groceries 400, Savings 230, Fun 150, total planned expenses
is 1580, so the Rent card reads `50.6% of plan`.

---

## 2. The load-bearing constraint: nothing new is stored

The original design added two columns to `Budgets` (`budgetAmountType`, `linkedCategoryPk`) and bumped
the schema to 47. The owner rejected that outright. Everything below follows from it:

- **No `linkedCategoryPk`.** "This budget belongs to a main category" is *derived* — see §3.
- **No `budgetAmountType`.** A percentage is never persisted; it is resolved once, at entry — see §5.
- **No migration, no `schema_versions.dart` regeneration, no `drift_schemas/` file.**
- **No sync-compatibility risk.** The original design's biggest hazard (`Budget.fromJson` throwing on
  a device still on schema 46, old→new, taking the whole apply batch with it — see
  `app/lib/struct/liveSyncClient.dart`) does not exist, because the payload shape never changed.

The rule of thumb for anyone extending this: if a feature here seems to need a new column, it is
probably the wrong feature.

---

## 3. Deriving "this budget belongs to a main category"

`app/lib/struct/mainCategoryBudgets.dart` — `PlannedBudgetTotals.isMainCategoryBudget`.

A non-archived budget belongs to a main category when:

- its `categoryFks` holds **exactly one** entry, **and**
- that entry is a **main** category (`Categories.mainCategoryPk == null`).

Everything else is a custom budget. `categoryFksExclude` is deliberately ignored — narrowing an
envelope with exclusions doesn't stop it being that category's envelope.

Two derived totals sit on the same class:

| Quantity | Definition | Used by |
|---|---|---|
| **Total planned expenses** | Σ target of every main-category budget with `income == false` | share label denominator (§6) |
| **Planned income** | Σ target of **every** non-archived budget with `income == true` | percent-of-income entry (§5) |

Planned income deliberately counts *all* income budgets, not just main-category ones, so a single
catch-all income budget still produces a sensible number. Note this app labels income budgets
**"savings budgets"** in the UI (`IncomeExpenseTabSelector` in `app/lib/pages/addBudgetPage.dart`),
which is the wording the empty state uses.

Both are computed in primary currency via the existing `budgetAmountToPrimaryCurrency`
(`app/lib/struct/currencyFunctions.dart`) — whose signature and all 9 call sites are **unchanged**,
which was the explicit goal of the original review's §C2.

### Caching

`watchPlannedBudgetTotals()` is a single app-wide broadcast stream over
`watchAllBudgets(hideArchived: true)` plus a category fetch, with `latestPlannedBudgetTotals` retained
for `StreamBuilder.initialData`. This exists so N budget cards on screen share one pair of database
reads instead of opening N. The underlying subscription is intentionally never cancelled — it lives as
long as the app. `getPlannedBudgetTotals()` is the one-shot equivalent for code outside a widget tree.

---

## 4. Auto-created category budgets

`ensureMainCategoryBudgetsExist()` in `app/lib/struct/mainCategoryBudgets.dart`.

**`budgetPk` is the `categoryPk`.** This is what makes two devices that create the same category
converge on one row instead of each minting a uuid and silently doubling the planned totals after
sync — the failure mode called out as the most likely production bug in the original review (§C10).

**It reconciles; it does not hook creation.** One idempotent pass creates a budget for every main
category that lacks one. That single implementation covers three cases the original design needed
separate machinery for: new categories, the one-time backfill for categories predating the feature,
and categories that arrived over sync rather than being created locally. It also sidesteps the fact
that `createOrUpdateCategory(insert: true)` blanks the pk so Drift can generate it, leaving the caller
with no way to know what the new `categoryPk` is.

Called from:

| Site | Covers |
|---|---|
| `initializeDefaultDatabase()` (`app/lib/database/initializeDefaultDatabase.dart`) | every launch: default categories on first run, backfill, synced arrivals |
| `addCategory()` (`app/lib/pages/addCategoryPage.dart`) | a category created by hand, immediately |

The created budget mirrors the category: same name and colour, `amount: 0`, one calendar month
(`periodLength: 1`, `reoccurrence: monthly`), `income` copied from the category, `pinned: false` so
the home carousel is not flooded, and `order` copied from `Categories.order` so the budgets list
mirrors the category list rather than appending (original review §C8). It is written with
`updateSharedEntry: false` so it can never reach the dead Firestore branch inside
`createOrUpdateBudget` (§C10).

**Deletion:** `deleteCategory` (`app/lib/database/tables.dart`) now writes a
`DeleteLogType.Budget` delete log and removes the budget keyed by that `categoryPk`, mirroring the
existing `deleteCategoryBudgetLimitsInCategory` cleanup. Deleted, not archived — `deleteCategory`
already deletes every transaction in the category, so an archived envelope would only preserve an
empty history.

**Subcategories get no envelope.** They roll up into their main category's card. The existing nested
Category Spending Goal mechanism stays available inside an envelope for finer tracking.

---

## 5. Percent-of-income entry

A **"Set as % of planned income"** button on the add/edit budget page
(`app/lib/pages/addBudgetPage.dart`), directly above "Set Category Spending Goals". It opens a
percentage input (`SelectAmountValue` with `suffix: "%"`, the same control the category-limits sheet
uses), and on confirm computes `percent / 100 × plannedIncome` and writes the result into the amount
field via `_BudgetDetailsState.applyAmount`.

**The percentage is not stored anywhere.** What lands in `Budgets.amount` is a plain number,
indistinguishable from one typed by hand. Consequences, all of them intentional:

- No new column, no sync risk, no double-conversion hazard in `budgetAmountToPrimaryCurrency`.
- Targets do **not** drift when planned income later changes. Re-run the button to re-derive.
- `pastBudgetsPage` history is unaffected — the original design's §C9 problem (last March silently
  rewriting itself when you change your salary target) cannot occur.

Two guards:

- Hidden on savings/income budgets — "% of planned income" of an income budget is not meaningful.
- Planned income of 0 opens an explanatory popup instead of writing 0, so nobody ends up with a
  silently zeroed target. This replaces the original design's much larger §C6 problem, where the
  backfill left every user with permanently zero-target percentage budgets.

Shown in both add and edit mode, unlike the spending-goals button beneath it (which needs a saved
budget). Edit-only would force create → save → reopen → set percentage.

---

## 6. Share-of-plan label

`BudgetSharePercentLabel` in `app/lib/widgets/budgetContainer.dart`, right-aligned in the card header
next to the budget name. Renders `23.5% of plan` — `this budget's target ÷ total planned expenses ×
100`.

It returns `SizedBox.shrink()` for income budgets, for custom budgets, and when the denominator is 0,
so there is no `NaN%` and no bare percentage on a card where it would be meaningless. The suffix is
there because an unqualified percentage on a budget card reads as *percent spent*, which is what the
rest of the card is about.

---

## 7. Budgets list tabs

`app/lib/pages/budgetsListPage.dart` — a `SlidingSelectorIncomeExpense` with
`options: ["main-categories", "custom-budgets"]`, filtering the list by §3's predicate. Existing
budgets sort themselves into the two tabs with no migration and no user action.

Laid out like the selector on the Scheduled page (`app/lib/pages/upcomingOverdueTransactionsPage.dart`):
full width inside a `Row` with 13px gutters, `useHorizontalPaddingConstrained: false`,
`customPadding: zero`. **Note the vertical padding is load-bearing:** slivers clip on the scroll axis,
and `boxShadowGeneral` reaches 28px (blur 20 + spread 8), so a `SliverToBoxAdapter` with tight
vertical padding slices the selector's shadow into a visible hard edge. The Scheduled page avoids this
by accident — its taller search button gives the row slack.

---

## 8. What the earlier design proposed, and why it is gone

For anyone reading the git history or the original request. All of this is **superseded**:

| Original proposal | Outcome |
|---|---|
| `budgetAmountType` + `linkedCategoryPk` columns, schema 47 | Dropped. Owner constraint; §2. |
| Drift versioned-schema migration, `Schema47`, `from46To47` | Not needed. |
| Nullable `budgetAmountType` to survive old→new sync payloads (§C3) | Moot — payload shape unchanged. |
| `BudgetPeriodSnapshots` table to freeze percentage history (§C9) | Moot — percentages are never stored. |
| Planned-income cache threaded into `budgetAmountToPrimaryCurrency` (§C2) | Not needed; the function is untouched. Its 9 call sites still need no edits, for a different reason. |
| Zero-planned-income empty state on every percent budget card (§C6) | Reduced to a one-time popup at entry; §5. |
| A "Planned vs. Actual" home-page section (`x` and `y`) | **Not implemented.** Still wanted — see §9. |

---

## 9. Not implemented

- **Planned vs. Actual home-page summary.** `x` = Σ planned income − Σ planned expenses, `y` = actual
  income − actual expenses for the month. Both halves are cheap from here: `x` is already computable
  from `PlannedBudgetTotals`, and `y` can reuse the two existing
  `watchTotalWithCountOfWallet(isIncome: true/false, followCustomPeriodCycle: true, …)` calls in
  `app/lib/pages/homePage/homePageAllSpendingSummary.dart`. Register it as a `homePageOrder` string key
  plus a section entry and a `show…` setting — **not** as a `HomePageWidgetDisplay` member, which
  drives the wallet-details page, not the home page. `fixHomePageOrder`
  (`app/lib/struct/settings.dart`) reconciles saved order against defaults, so existing users pick up
  a new key automatically.

## 10. Known gaps

Deliberate, and each is a small change if the owner wants it closed:

- **Renaming a category does not rename its envelope budget.** Creation copies the name once; there is
  no ongoing sync. Auto-updating it would silently overwrite a budget the owner had renamed on
  purpose, and without stored state there is no way to tell the two cases apart.
- **A hand-deleted category budget comes back on the next launch.** Correct for an envelope system
  where every category has one, but it means "delete" is not a way to hide an envelope. The original
  design's §8.7 "guard direct deletion of an auto-budget" was never built.
- **Planned income mixes budget periods.** It sums income budget targets regardless of each budget's
  cycle, so a weekly income budget and a monthly expense budget produce a misleading figure. Fine for
  the all-monthly setup this was built for. The percent sheet shows the resolved planned-income figure
  before you enter a percentage, so a wrong number is visible rather than silent.
- **Share label counts only non-archived budgets** and does not appear on `PastBudgetContainer`.

---

## 11. Files touched

| File | Role |
|---|---|
| `app/lib/struct/mainCategoryBudgets.dart` | **New.** Derivation, totals, shared cache, auto-creation. |
| `app/lib/database/initializeDefaultDatabase.dart` | Reconcile hook on every launch |
| `app/lib/database/tables.dart` | `deleteCategory` cleanup only — **no schema change** |
| `app/lib/pages/addCategoryPage.dart` | Reconcile hook after creating a category |
| `app/lib/pages/addBudgetPage.dart` | "% of planned income" button, popup, `applyAmount` |
| `app/lib/widgets/budgetContainer.dart` | `BudgetSharePercentLabel` |
| `app/lib/pages/budgetsListPage.dart` | Main Categories / Custom tabs |
| `app/assets/translations/generated/en.json` | 7 new English keys |

---

## 12. Acceptance criteria

Owner-run, per "Testing & verification workflow" in `CLAUDE.md`.

- [ ] Fresh install lands on the Budgets page with one envelope per default main category, ordered
      like the category list, and none of them pinned to the home carousel.
- [ ] An existing database gets envelopes backfilled on first launch, with existing manual budgets
      untouched and appearing under **Custom**.
- [ ] Creating a main category creates its envelope immediately; deleting the category removes it.
- [ ] Creating a *sub*category creates no envelope.
- [ ] Set income targets, then "Set as % of planned income" on an expense budget: the amount field
      shows the resolved number, and saving stores that number.
- [ ] With no income budgets, the button explains itself rather than writing 0.
- [ ] Share labels across the Main Categories tab sum to ~100%.
- [ ] The tab selector's shadow is not clipped, at both narrow and double-column widths.
- [ ] **Sync:** create the same category on two devices while both are offline, then sync — exactly
      one envelope survives, and planned totals do not double.
- [ ] **Local-first:** all of the above works with the server unreachable.
- [ ] An original-Cashew backup still imports (schema is unchanged, but confirm).
