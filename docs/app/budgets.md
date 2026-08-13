# Budgets: the fork's additions

Four pieces sit on top of upstream's budget model, none of which changed the schema. Storage
mechanics for two of them are in [database.md](database.md).

## Per-period amounts

`struct/budgetPeriodAmounts.dart`, stored in `Budgets.sharedAllMembersEver`.

Editing a budget's amount applies **from the current period onward**; finished periods keep the
target they actually had, instead of the history view recomputing every past period from today's
number.

The model is effective-from: each entry means "from this period onward, until the next entry, the
target was this much", encoded `<periodStartEpochMillis>=<amount>`. `Budget.amount` always equals the
**current** period's amount — which is what keeps every code path that has not been taught about
history, plus backups, sync and upstream Cashew itself, reading a correct value.

Parsing is deliberately strict; anything not exactly that shape is skipped, because an
original-Cashew backup has real member IDs in this column.

## Category-locked envelope budgets

`struct/mainCategoryBudgets.dart`. A budget "belongs to" a main category when it targets exactly one
category and that category is a main category.

**Derived, never stored.** That is what let the feature ship without touching the Drift schema. The
cached snapshot also carries a `subcategory pk → parent main category` map so the allocation check
below can group budgets without opening its own subscription.

## Personal budgets

`struct/budgetVisibility.dart`, stored in `Budgets.sharedMembers` as at most one entry: the server
user id of the member the budget is personal to, or nothing when the whole household shares it.

**This is not privacy.** A personal budget still syncs, and its row is physically present in every
member's database — it is filtered out **when drawing the screen, nowhere else**. It hides a budget
from the app, not from someone with a SQLite browser.

That is deliberate, and it is the one rule most likely to be "cleaned up" into a bug: **never filter
personal budgets in a query that feeds a total.** The allocation check below has to count budgets the
viewer cannot see.

Anything that is not exactly one entry of digits reads as *shared* — an original-Cashew backup's real
member IDs must arrive harmlessly rather than be mistaken for a user id.

## The over-allocation check

`struct/subCategoryBudgetAllocation.dart`. Do the subcategory budgets under a main category still fit
inside that category's envelope?

Without it, subcategory budgets can be created without limit while none of them affects the envelope
they sit under, so a household plans 1200 inside a category budgeted at 1000 and finds out at the end
of the month. Personal budgets make it easier to miss, because part of the total is not on screen.

So the sum **includes another member's personal budgets**. This is the reason personal budgets sync
at all rather than being kept off the server: a gap the viewer cannot see is exactly the gap worth
warning about. The figures therefore will not always match the cards on screen, and the warning says
so. Under-allocating is fine and never warns.

---

Why: `specs/backlog/BL-006-per-period-budget-amounts.md`,
`specs/backlog/BL-001-category-locked-budgets.md`, `specs/06-shared-household-data.md`.
