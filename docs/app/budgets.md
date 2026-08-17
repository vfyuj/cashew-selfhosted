# Budgets: upstream's, unmodified

There is nothing fork-specific left on this page, and that is the point of it.

Budgets — `pages/addBudgetPage.dart`, `pages/budgetsListPage.dart`, `pages/budgetPage.dart`,
`pages/pastBudgetsPage.dart`, `pages/editBudgetPage.dart`, `widgets/budgetContainer.dart`,
`pages/homePage/homePageBudgets.dart` — are upstream Cashew's, line for line, apart from the
package rename and the deletions that removed Google (the paywall around past budgets, the Firestore
"shared budget" mode and its member chips). Category spending goals (`widgets/categoryLimits.dart`,
`pages/editBudgetLimitsPage.dart`) were never touched at all.

So: any cycle you like, any set of categories, added-transactions-only, per-category goals inside a
budget. If you want to know how something behaves, upstream's behaviour *is* the answer, and
upstream's code is the reference.

## What used to be here

Three fork features lived on top of budgets and have been withdrawn:

- **Category-locked envelope budgets** — one auto-created budget per main category, plus a
  Main Categories / Custom split on the budgets list. Replaced by a real feature with its own table:
  [envelopes.md](envelopes.md).
- **Per-period amounts** — a budget's amount history, packed into a dead column so finished periods
  kept the target they had. Envelopes have this natively: one row per month.
- **Personal budgets** — a budget owned by one household member and hidden from the others, plus the
  over-allocation warning that had to count budgets the viewer could not see. Dropped outright; every
  budget is the household's again.

The conversion runs once per device (`database/envelopeMigration.dart`) and is described in
[envelopes.md](envelopes.md).

Keeping these three out of the budget pages is deliberate maintenance policy, not tidiness. They had
grown to ~800 lines of divergence across seven files, which made every upstream fix a merge exercise
and every bug ambiguous about whose it was.

---

Why: `specs/backlog/BL-001-category-locked-budgets.md`,
`specs/backlog/BL-006-per-period-budget-amounts.md`, `specs/06-shared-household-data.md`.
