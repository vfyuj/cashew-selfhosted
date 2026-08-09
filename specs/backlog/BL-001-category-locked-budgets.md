# BL-001 — Category-Locked Budgets with Income-Relative Targets, and a Planned-vs-Actual Net Summary

**Status:** Reviewed and corrected. **Not approved for implementation.** Six product decisions in §4
need the owner's answer first, and §3 recommends deferring the start until Stage 2 lands.

**Origin:** owner-submitted feature request, reviewed 2026-08-09 against the actual fork source.

**Local-first check:** ✅ no conflict with `specs/01-local-first-invariant.md`. Everything here is
local Drift reads/writes and local computation. Nothing gates on auth or connectivity.

---

## 1. What the request asks for

Today Cashew's budget↔category relationship is optional and loose: a `Budget` is a top-level entity
that *may* reference some categories, and a category may belong to zero, one, or many budgets. This
request makes it **mandatory and 1:1** for main categories (expense and income), adds a
**percent-of-income** target type as an alternative to a fixed amount, and adds a **Planned vs.
Actual** month summary:

- `x` = Σ(planned target of every main **income** category budget) − Σ(effective target of every main
  **expense** category budget)
- `y` = Σ(actual income transactions) − Σ(actual expense transactions), for the month

Motivation: the household already runs a spreadsheet with two columns — expense categories and income
categories, each with a planned figure. That's envelope budgeting. Cashew's nearest existing feature,
*Category Spending Goals*, is a nested breakdown inside one umbrella `Budget`, where a per-category
percentage is a percentage of *that budget's own fixed target* — never of income.

### Worked example

Income auto-budgets (fixed): Salary 2000 + Freelance 300 → **planned income = 2300**.
Expense auto-budgets: Rent 800, Groceries 400, Savings 10% of income → 230, Fun 150 → **planned
expenses = 1580**. `x = 2300 − 1580 = 720` (planned surplus).
If actual paid transactions this month are 1420 expense / 2100 income: `y = 2100 − 1420 = 680`.

---

## 2. Verification pass — what the request got right

The request was written against a direct read of the source, and it holds up. Every one of these was
checked against this fork and is accurate:

| Claim | Verified at |
|---|---|
| `budgetAmountToPrimaryCurrency` is a 3-line pure function multiplying `budget.amount` by the wallet fx ratio | `app/lib/struct/currencyFunctions.dart:132` |
| It is the shared entry point for budget targets across the budget card, budget page, add/edit pages, limits page, and history | 9 call sites in 5 files, enumerated in §C2 |
| `Budgets` has `amount`, `categoryFks`, `categoryFksExclude`, `income`, `addedTransactionsOnly`, `periodLength`, `reoccurrence`, `walletFk(s)`, `budgetTransactionFilters`, `isAbsoluteSpendingLimit` | `app/lib/database/tables.dart:500-552` |
| `Categories.mainCategoryPk` null ⇒ main category; `Categories.income` is the default type | `app/lib/database/tables.dart:420-450` |
| Nested category goals store a **percentage of the parent budget's amount** when the parent's `isAbsoluteSpendingLimit == false`, and a money value when true; the mode is a property of the parent, applied to all its nested limits at once | `tables.dart:5603-5605`, `tables.dart:5660-5661`, `editBudgetLimitsPage.dart:29` |
| `deleteCategoryBudgetLimitsInCategory` is the existing precedent for cleaning up dependents when a category dies | `tables.dart:5049`, `tables.dart:5127` |
| `homePageAllSpendingSummary.dart` already computes actual income and actual expense with two `watchTotalWithCountOfWallet(isIncome: true/false, followCustomPeriodCycle: true, cycleSettingsExtension: "AllSpendingSummary", onlyIncomeAndExpense: true, …)` calls — reusable verbatim for `y` | `homePageAllSpendingSummary.dart:51, 80` |
| `watchTotalSpentInTimeRangeFromCategories` is the actual-spend aggregator | `tables.dart:5806` |

Reusing the existing summary query for `y` is a genuinely good call — that part is free.

---

## 3. Corrections

Ten issues, roughly in descending order of how much damage they'd do if implemented as written.

### C1 — All file paths are upstream's, not this fork's

The request cites `budget/lib/…`. Upstream's Flutter package directory is `budget/`; **this fork's is
`app/`**. Every path in the original §11 needs rebasing to `app/lib/…`. All named files do exist there.

### C2 — "Close to a one-stop change" is wrong: all 9 call sites need edits, and 2 need restructuring

This is the load-bearing claim of the original §6, and it doesn't hold.

The proposed signature is:

```dart
double budgetAmountToPrimaryCurrency(AllWallets allWallets, Budget budget,
    {double? plannedIncomeForPeriod}) { … budget.amount / 100 * (plannedIncomeForPeriod ?? 0) … }
```

With `?? 0`, **any call site that doesn't pass the new argument renders a percent-of-income budget's
target as `0`** — i.e. permanently and maximally over budget — rather than "keeping working
unmodified." So every call site must be touched:

| File | Lines |
|---|---|
| `app/lib/widgets/budgetContainer.dart` | 50, 424 |
| `app/lib/pages/budgetPage.dart` | 230, 1141, 1321 |
| `app/lib/pages/pastBudgetsPage.dart` | 271, 965 |
| `app/lib/pages/addBudgetPage.dart` | 581 |
| `app/lib/pages/editBudgetLimitsPage.dart` | 43 |

Worse than the count: `budgetContainer.dart:50` and `pastBudgetsPage.dart:271` compute the target
**synchronously at the top of `build()`** from a `Provider.of<AllWallets>`, not inside a
`StreamBuilder`. Threading in a value that requires a DB read means wrapping those widgets in another
`StreamBuilder` — restructuring the most-rendered widget in the app.

**Recommended fix that actually recovers the one-stop property:** don't pass planned income as an
argument. Expose it the same way `AllWallets` is already exposed — a `Provider`-backed (or global
cached) value recomputed on any write to an income-category budget. Then
`budgetAmountToPrimaryCurrency` stays synchronous and pure-ish, its signature never changes, and all 9
call sites genuinely need no edits. This is the difference between a ~40-line change and a ~400-line one.

### C3 — Live sync will throw on `Budget.fromJson` from a device still on the old schema

**This fork is not upstream here.** Upstream syncs by shipping whole SQLite files. This fork *also*
ships row-level JSON deltas: `app/lib/struct/liveSyncClient.dart:118-123` sends `row.toJson()` for
budgets, and line 217 applies them with `Budget.fromJson(payload)`.

Drift generates non-nullable field reads for non-nullable columns — e.g.
`income: serializer.fromJson<bool>(json['income'])` at `app/lib/database/tables.g.dart:4091`. A
`budgetAmountType` declared as a non-nullable int enum with a default generates
`serializer.fromJson<int>(json['budgetAmountType'])`. A payload sent by a device still on schema 46
has no such key → `null` → type error → **the sync apply loop throws**, taking the whole batch with it.

The original §10 hoped this would "degrade gracefully (e.g. treat unrecognized `budgetAmountType` as
`fixedAmount` on an older synced client)". Half of that is free, half isn't:

- New → old: **safe.** Drift's generated `fromJson` ignores keys it doesn't know about.
- Old → new: **breaks**, as above.

**Fix:** declare it nullable and treat `null` as `fixedAmount`:

```dart
IntColumn get budgetAmountType => intEnum<BudgetAmountType>().nullable()();
```

`linkedCategoryPk` is already specified as nullable, so it's fine as-is. Note this also means the
original §10's "multi-user sync semantics … isn't a design target here" **cannot** be carried over —
multi-device sync is the entire point of this fork, so it's in scope by definition.

### C4 — The migration is more than a `schemaVersionGlobal` bump

Current version is **46** (`app/lib/database/tables.dart:29`). This repo uses Drift's *versioned
schema* tooling, so adding columns means all of:

1. Bump `schemaVersionGlobal` to 47.
2. Regenerate `app/drift_schemas/drift_schema_v47.json` and the `Schema47` class in
   `app/lib/database/schema_versions.dart` (existing chain ends at `Schema46`,
   `schema_versions.dart:4471`).
3. Add a `from46To47:` step to the `stepByStep` chain (the `from45To46:` precedent is at
   `tables.dart:1196`).
4. Follow the house style: wrap **each** `m.addColumn` in its own `try/catch` with a printed error.
   Upstream does this deliberately — a past migration bug left some devices with columns already
   present, and an unguarded `addColumn` would hard-fail their upgrade.

### C5 — Categories can't be archived, so that edge case doesn't exist

The original §9.6 lists "handle archived categories". `Budgets` has an `archived` column
(`tables.dart:517`); **`Categories` does not** (`tables.dart:420-450`). Categories are deleted, not
archived.

The real question in its place: when a category is deleted, is its auto-budget **deleted** or
**archived**? Note `deleteCategory` (`tables.dart:5044`) already deletes every transaction in the
category, so deleting the budget outright orphans nothing — but archiving preserves history in
`pastBudgetsPage`. Pick one explicitly.

### C6 — The divide-by-zero worry is misplaced; the real hazard is planned income = 0

`amount / 100 * plannedIncome` never divides by zero. The actual failure mode is the opposite: when
planned income is `0` — which is the **default state after the §4.5 backfill, for every existing
user** — every percent-of-income budget resolves to a target of `0`, so any spending at all renders as
over-budget with a full/overflowing progress ring across the entire budgets list.

Needs an explicit "no planned income set yet" state on those cards instead of a 0-target budget, plus
an onboarding nudge to set income targets first. This should be treated as a blocking design item, not
polish.

### C7 — `HomePageWidgetDisplay` is the wrong extension point

The original §7 proposes "a new `HomePageWidgetDisplay` entry". That enum (`tables.dart:86`) has
exactly five members — `WalletSwitcher`, `WalletList`, `NetWorth`, `AllSpendingSummary`, `PieChart` —
and drives the **wallet-details** page, not the home page.

Home-page sections are string keys in `appStateSettings["homePageOrder"]` and
`["homePageOrderFullScreen"]` (`app/lib/struct/defaultPreferences.dart:75, 90`), rendered from a
section map in `app/lib/pages/homePage/homePage.dart`, each gated by a `show<Section>` boolean read
through `isHomeScreenSectionEnabled`.

Good news attached: `fixHomePageOrder` (`app/lib/struct/settings.dart:145-146`) reconciles a user's
saved order against the defaults, so adding a new key is picked up by existing users automatically —
no settings migration needed.

### C8 — Auto-budgets flood the budgets list, and `order` needs a strategy

The original §7's "no new card widget needed — auto-budgets are ordinary `Budget` rows, so
`HomePageBudgets` → `BudgetContainer` renders them automatically" is technically true and product-wise
the biggest unaddressed consequence in the request.

A fresh install has **13 default categories** (12 expense + 1 income,
`app/lib/struct/defaultCategories.dart`), so day one becomes 13 budget cards in the home-page carousel
and on the Budgets page, growing with every category the user adds. The budgets surface stops being
"my budgets" and becomes "my category list."

Also mechanical: `Budgets.order` is non-nullable with no default (`tables.dart:527`) and budgets are
user-reorderable, so auto-created rows need an explicit ordering rule — most likely mirroring
`Categories.order` rather than appending to the end.

**Recommendation:** keep auto-budgets out of the existing budgets list and carousel by default, on
their own screen or behind a filter, with manual budgets left alone. This is a real product decision
and belongs in §4, not in implementation.

### C9 — Percent-of-income history is retroactive, and §5 has nowhere to store the locked value

`pastBudgetsPage` synthesizes prior periods from the *current* budget row
(`pastBudgetsPage.dart:271, 965`). A percent-of-income target stores only the percentage, so every past
period's target is recomputed from **today's** planned income — change your salary target and last
March silently rewrites itself.

The original §4.2 says planned income is "locked at the start of the cycle," but the §5 data model
provides no field to store the locked value. Either add a per-period snapshot (a small
`BudgetPeriodSnapshots` table keyed by `budgetPk` + period start), or accept and explicitly document
that history for percent budgets always reflects current planned income.

### C10 — Smaller items

- **Duplicate auto-budgets from concurrent devices.** §5 says "enforce one-per-category at the app
  layer," but there's no unique index, and last-write-wins merges by `dateTimeModified` per
  `budgetPk`. Two devices that each auto-create a budget for the same category produce **two rows with
  the same `linkedCategoryPk` and different `budgetPk`s**, and sync will happily keep both — planned
  totals silently double. **Fix:** derive the auto-budget's `budgetPk` deterministically from the
  `categoryPk` (reuse it directly, or a uuid v5 of it) so both devices converge on the same row. Given
  this fork's multi-device focus, this is the most likely production bug in the whole design.
- **Two percentage bases in one card.** `isAbsoluteSpendingLimit` lives on the parent budget, so an
  auto-budget that is itself "% of income" *and* contains nested category goals in percentage mode has
  two different percentage bases stacked in one card. Needs an explicit rule — simplest is to force
  `isAbsoluteSpendingLimit = true` on percent-of-income auto-budgets.
- **§4.5 wording:** "income-category auto-budgets default to fixed amount at 0%" → at **0** (an
  amount, not a percentage).
- **Firebase branch in the write path.** `createOrUpdateBudget` still contains a Firestore call
  (`tables.dart:4318`), dead in this fork but guarded only by `sharedKey != null` and
  `appStateSettings["sharedBudgets"]`. Auto-budget creation should route through a path that can't
  reach it.

---

## 4. Open decisions — owner input needed before implementation

The request pre-answered most of these with reasonable recommendations; they're restated here as
decisions rather than assumptions, plus the one C8 surfaced.

1. **Planned income = Σ(fixed targets of income-category budgets)** — proposed. Maps 1:1 onto the
   spreadsheet's two columns, stable rather than drifting with each paycheck, reuses the same
   lifecycle machinery. Income-category budgets are fixed-amount only.
2. **Percentage denominator locked per cycle** — proposed, so % targets don't recalculate on every new
   income transaction. See C9: this needs somewhere to store the locked value, or an accepted caveat.
3. **One shared calendar-month cycle for all auto-budgets** — proposed, so `x` and `y` sum cleanly as
   "this month." Manual budgets keep their arbitrary cycles.
4. **Wallet/currency scope: all wallets, converted to primary** — proposed, matching the existing All
   Spending Summary default.
5. **Backfill at migration: one auto-budget per pre-existing main category**, expense ones defaulting
   to % of income at 0%, income ones to a fixed amount of 0. See C6 — this default lands every existing
   user in the "planned income = 0" state, so it needs the empty-state handling.
6. **Subcategories get no auto-budget** — proposed; they roll up into their main category's card. The
   existing nested Category Spending Goal mechanism stays available inside an auto-budget for finer
   tracking.
7. **NEW (from C8): do auto-budgets appear in the existing budgets list and home carousel, or on their
   own surface?** Not answered by the original request, and it changes the shape of the UI work
   substantially.

---

## 5. Corrected data model

Two columns on `Budgets` (`app/lib/database/tables.dart:500`):

- **`budgetAmountType`** — `intEnum<BudgetAmountType>().nullable()` — `fixedAmount` (0) /
  `percentOfIncome` (1). **Nullable, per C3**; `null` is read as `fixedAmount`, which is what makes old
  clients' sync payloads safe. Only meaningful when `linkedCategoryPk` points at an *expense* category;
  ignored for income-category budgets and for manual budgets.
- **`linkedCategoryPk`** — `text().nullable()`, FK → `Categories.categoryPk`. When set, this row *is*
  the system-managed card for that category. Manual budgets leave it null and are untouched by
  everything in this document. **`budgetPk` for these rows is derived deterministically from
  `categoryPk`** (per C10) so concurrent devices converge instead of duplicating.

When `budgetAmountType == percentOfIncome`, `amount` holds the percentage (0–100) — the same storage
convention `CategoryBudgetLimit.amount` already uses in percentage mode, applied one level up. For
income-category auto-budgets `amount` is always a currency amount.

No changes to `Categories` or `CategoryBudgetLimits`. An auto-budget is an ordinary `Budgets` row, so
nested Category Spending Goals keep working inside it.

Migration: the full four-step drift procedure in C4, plus the §4.5 backfill.

---

## 6. Corrected logic changes

**New helper** `plannedIncomeForPeriod(DateTime start, DateTime end)` — sums `amount` over `Budget`
rows whose `linkedCategoryPk` resolves to a main income category (`Categories.income == true &&
mainCategoryPk == null`) in range, converted to primary currency.

**Integration point** — `budgetAmountToPrimaryCurrency` branches on the new field:

```dart
double budgetAmountToPrimaryCurrency(AllWallets allWallets, Budget budget) {
  if (budget.budgetAmountType == BudgetAmountType.percentOfIncome) {
    // Already primary currency by definition — do NOT also apply the wallet fx ratio.
    return budget.amount / 100 * plannedIncomeCache.value;
  }
  return budget.amount * amountRatioToPrimaryCurrencyGivenPk(allWallets, budget.walletFk);
}
```

Per C2, planned income arrives through a `Provider`/cached global (recomputed on any income-budget
write), **not** as a new parameter — that's what keeps the signature stable and all 9 call sites
untouched. The double-conversion warning in the original request is correct and important: the percent
branch must skip `amountRatioToPrimaryCurrencyGivenPk` entirely.

**Category lifecycle hooks** — extend `createOrUpdateCategory` (`tables.dart:4092`) to auto-create the
linked budget for new main categories, and `deleteCategory` (`tables.dart:5044`) to tear it down,
mirroring the existing `deleteCategoryBudgetLimitsInCategory` cleanup. Per C5, decide delete vs.
archive.

---

## 7. Corrected UI changes

- **Amount entry for an expense auto-budget** — a segmented "% of income / Fixed amount" control,
  reusing the toggle pattern already in `app/lib/widgets/categoryLimits.dart` (`TappableTextEntry` +
  `convertToPercent`/`convertToMoney`), pointed at the new top-level field. Income auto-budgets show
  fixed amount only.
- **Zero-planned-income state** (C6) — percent budgets must render a "set your income targets first"
  state, never a 0-target progress ring.
- **Budgets list placement** — pending decision 4.7 (C8).
- **New "Planned vs. Actual" home-page section** — added as a `homePageOrder` string key + section
  entry + `show…` setting (C7), **not** a `HomePageWidgetDisplay` member. Two boxes modeled on
  `homePageAllSpendingSummary.dart`: "Planned" = `x`, "Actual" = `y`, the latter reusing that file's
  two existing `watchTotalWithCountOfWallet` calls subtracted instead of displayed side by side.
  Colour-code by sign; tapping routes to the budgets list or `TransactionsSearchPage`, consistent with
  existing home-page behaviour.

---

## 8. Suggested implementation order

Unchanged in spirit from the original request, with the corrections folded in:

1. **Schema** — both columns (`budgetAmountType` nullable per C3), full drift versioned-schema
   migration per C4, no behaviour change yet.
2. **Auto-budget lifecycle** — deterministic `budgetPk` (C10), create/delete hooks, one-time backfill.
3. **Percent-of-income engine** — `plannedIncomeForPeriod`, the planned-income cache/provider (C2),
   the `budgetAmountToPrimaryCurrency` branch. Verify existing budget screens render auto-budgets with
   no edits — if they need edits, the C2 approach wasn't followed.
4. **Zero-planned-income empty state** (C6) — before the toggle UI, not after; the backfill puts every
   user in this state on day one.
5. **Type-toggle UI** on the amount entry.
6. **Planned vs. Actual home-page section.**
7. **Edge cases and polish** — guard direct deletion of an auto-budget, category-deletion path,
   history semantics per C9.

Each step should be its own small PR. Step 1 alone is a safe, independently shippable no-op.

---

## 9. Out of scope

- Goals/Objectives, Loans, transfers, Balance Correction handling — unchanged.
- Auto-budgets at the subcategory level (decision 4.6).
- **Not out of scope, contrary to the original request:** sync semantics for the two new fields. See
  C3 and C10 — multi-device sync is this fork's reason to exist.

---

## 10. Files touched (rebased onto this fork)

| File | Role |
|---|---|
| `app/lib/database/tables.dart` | `Budgets`/`Categories` schema, `schemaVersionGlobal`, `stepByStep` migration, `createOrUpdateCategory`, `deleteCategory`, `watchTotalSpentInTimeRangeFromCategories`, `watchTotalWithCountOfWallet`, `HomePageWidgetDisplay` |
| `app/lib/database/schema_versions.dart`, `app/drift_schemas/` | Generated versioned schema — must be regenerated (C4) |
| `app/lib/struct/currencyFunctions.dart` | `budgetAmountToPrimaryCurrency` — central integration point |
| `app/lib/struct/liveSyncClient.dart` | Row-level JSON sync — the C3 compatibility risk lives here |
| `app/lib/struct/defaultPreferences.dart`, `app/lib/pages/homePage/homePage.dart` | Home-page section registration (C7) |
| `app/lib/widgets/budgetContainer.dart` | Budget card — 2 call sites, both synchronous in `build()` (C2) |
| `app/lib/widgets/categoryLimits.dart` | Precedent for the %-vs-fixed toggle UI |
| `app/lib/pages/budgetPage.dart`, `pastBudgetsPage.dart`, `addBudgetPage.dart`, `editBudgetLimitsPage.dart` | Remaining `budgetAmountToPrimaryCurrency` call sites (C2), history semantics (C9) |
| `app/lib/pages/homePage/homePageAllSpendingSummary.dart` | Actual income/expense query, reused for `y` |
| `app/lib/pages/addCategoryPage.dart` | Category creation entry point for the lifecycle hook |
