# BL-006 — Per-period budget amounts

**Status:** Implemented 2026-08-10. Not yet acceptance-tested by the owner.

**Origin:** owner question (2026-08-10) — *"Can I adjust monthly budgets each month? Will it overwrite
the budget limits for previous months?"* The answer was yes to both, and the second yes was the bug.

**Local-first check:** ✅ no conflict with `specs/01-local-first-invariant.md`. Local Drift reads and
writes and local computation only. Nothing gates on auth or connectivity.

**Upstream-compatibility check:** ✅ `schemaVersionGlobal` is still 46, the 10 tables are unchanged,
and the `CLAUDE.md` diff still prints nothing. No migration, no `schema_versions.dart` regeneration,
no `drift_schemas/` file. See §3 for the full reasoning, which was the deciding constraint.

---

## 1. The problem

A repeating budget is one row with one `amount` (`Budgets.amount`). Nothing recorded what the target
was during any particular period, and the history view derives every past period from the *current*
value — `pastBudgetsPage.dart` called `budgetAmountToPrimaryCurrency(allWallets, budget)` with no
date at all.

So a household that raised its Groceries envelope from 400 to 500 in April found that January,
February and March retroactively claimed to have been 500-envelope months, and every progress bar,
percentage and over/under figure in the history view changed to match. The transactions were never
touched — only what they were measured against.

This affects **every main-category envelope** from BL-001, since those are ordinary `Budgets` rows
(`budgetPk == categoryPk`), and custom budgets equally.

## 2. What this delivers

Editing a budget's amount now means *"from this period onward"*. Periods that have already ended keep
the target they were set to at the time.

```
Set Groceries to 400 in January  →  Feb, Mar show 400
Change it to 500 in April        →  Jan–Mar still show 400
                                    Apr onward show 500
```

No new UI beyond a one-line note on the edit page. Correct per-period numbers fall out of the read
path, so the history view, the budget page, and the budget cards all became right at once.

## 3. The load-bearing constraint: no schema change

The owner's criterion was **backwards compatibility with upstream Cashew** — the invariant in
`CLAUDE.md` that keeps an original-Cashew backup importable. That ruled out a new table or column and
forced the storage question: the data has to live in one of the 8 tables the sync feed already ships
(`liveSyncClient.dart`), because settings (`AppSettings`) are **not** synced and per-month amounts
that only existed on one device would be useless to a household.

Three candidates were weighed:

| Option | Verdict |
|---|---|
| **Reuse a dead column on `Budgets`** | **Chosen.** Rides the budget row through sync and backup for free, is deleted with the budget for free, and needs no list or picker anywhere to learn a new filter. |
| Extra `Budgets` rows, one per adjusted period | Rejected. Semantically the most honest — Cashew already models one-off budgets — but it fights BL-001's reconcile, which *deletes* duplicate budgets for a category (`mainCategoryBudgets.dart`), and ~10 enumeration sites (budgets list, home carousel, transaction-filter pickers, quick actions) would each need to hide override rows. Exactly the sprawl `CLAUDE.md` warns about. It would also clutter the budget list if the data were ever opened in upstream Cashew. |
| An 11th table | Rejected. Cleanest data model, but breaks the invariant the owner named as the sole criterion, and `CLAUDE.md` scopes that as a Stage 4 decision. Same objection that killed the original BL-001 design. |

### The column, and why that one

`Budgets.sharedAllMembersEver` — a `List<String>` column belonging to the deleted Firestore sharing
feature. Before this change nothing in `app/` wrote it except `generatePreviewData.dart`, which sets
it to `null`.

Entries are `<periodStartEpochMillis>=<amount>`:

```
["1751328000000=400.0", "1759276800000=500.0"]
```

`sharedMembers` was considered and rejected: upstream reads it in far more places, including
`(budget.sharedMembers ?? [""])[0]` with no guard (`upstream/budget/lib/pages/budgetPage.dart`).

### Both directions of compatibility, as actually checked

- **Upstream backup → this fork (the direction the invariant protects): safe.** An incoming backup
  has real member IDs in this column. The parser accepts only entries matching
  `^(\d+)=(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)$` and skips everything else, so those budgets arrive
  with no history and behave exactly as they did before. Pinned by a test.
- **This fork → upstream: safe, with one cosmetic wrinkle.** Upstream reads this column in two
  places. `getAllMembersOfBudgets()` is gated on `getAllBudgets(sharedBudgetsOnly: true)` →
  `sharedKey.isNotNull()`, and this fork never sets `sharedKey`, so it never sees these rows.
  `BudgetSpenderSummary` (`upstream/budget/lib/widgets/budgetContainer.dart`) is **not** gated on
  `sharedKey` — it is gated on the `appStateSettings["sharedBudgets"]` setting
  (`upstream/budget/lib/pages/budgetPage.dart`). So this data opened in original Cashew *with shared
  budgets switched on* would render one spender row per entry, each totalling 0. Cosmetic, no data
  loss, opt-in setting required.

## 4. The model: effective-from

Entries are sorted and mean "from this period onward, until the next entry". Resolving period `P`:

1. No entries → `budget.amount`, so an unadjusted budget behaves exactly as it always did.
2. Otherwise → the last entry whose `periodStart <= P.start`.
3. `P.start` earlier than the first entry → the first entry's amount.

**`budget.amount` always equals the current period's amount.** That invariant is what keeps every
code path not taught about history — plus backups, the sync feed and upstream — reading a correct
value, and it is why the read seam could be an *optional* parameter rather than a breaking change.

Writing, when the amount changes on save:

- If the history is empty, seed `(previousPeriodStart, oldAmount)` first. Without the seed a lone
  `(April, 500)` entry would apply 500 to January via rule 3 — the exact bug being fixed.

  The seed is anchored to the **previous period**, not to the budget's own `startDate`. Anchoring to
  `startDate` looks natural and is wrong: every envelope BL-001 creates starts on the first of the
  month it was created in, so a budget adjusted during its first month would get no seed at all —
  while the history view still shows earlier periods for it, which would then read the new amount.
  Any date strictly before the current period start resolves identically, because rule 3 sends
  anything older to the oldest entry anyway. A custom (non-repeating) budget has only one period, so
  the previous-period lookup returns that same period and the seed is correctly skipped.
- Then insert-or-replace `(currentPeriodStart, newAmount)`, keyed by period, so adjusting twice in one
  month replaces rather than appends. The list grows by at most one short string per month adjusted.
- If `reoccurrence`, `periodLength` or `startDate` change, **clear the history** — the old period keys
  no longer line up with real boundaries, and clearing is far easier to reason about than remapping.

  This is the only edit in the app that destroys the record, and it sits on the same screen as the
  amount, so it is guarded by a confirmation prompt (`confirmClearingAmountHistory` in
  `addBudgetPage.dart`, gated on `amountHistoryWouldBeCleared`). The prompt fires only when there is
  a history to lose, so a budget that has never been adjusted still saves in one tap; cancelling, or
  dismissing the popup, abandons the whole save rather than saving with the cycle reverted.

## 5. Where the code is

| File | Role |
|---|---|
| `app/lib/struct/budgetPeriodAmounts.dart` | **New.** The only file that knows about the column. Parse, encode, resolve, and the write rule. |
| `app/lib/struct/currencyFunctions.dart` | `budgetAmountToPrimaryCurrency` gained an optional `forDate`. Omitting it reads the current amount, so an unthreaded call site degrades to old behaviour rather than breaking. |
| `app/lib/widgets/budgetContainer.dart` | Budget cards, threaded with the period being rendered. |
| `app/lib/pages/budgetPage.dart` | Budget page, its line graph, and `TotalSpent` (which gained a `forDate`). |
| `app/lib/pages/pastBudgetsPage.dart` | The history list. |
| `app/lib/pages/addBudgetPage.dart` | The single save site: `createBudget()` now ends in `withUpdatedAmountHistory`. Plus the explanatory note and the cycle-change confirmation prompt. |
| `app/lib/database/tables.dart` | Warning comment on the column. |
| `app/test/budget_period_amounts_test.dart` | **New.** 12 tests. |

Left deliberately on the current amount, because they are about *now* rather than about a past
period: `mainCategoryBudgets.dart` (planned totals and the share-of-plan denominator),
`onBoardingPage.dart`, `editBudgetLimitsPage.dart`, and the `horizontalLineAt` reference line on the
history page's graph, which spans many periods at once and so cannot take a single per-period value.

## 6. Non-goal

Per-category spending goals nested inside a budget (`CategoryBudgetLimits`, reached via "Set Category
Spending Goals") keep today's behaviour — one amount for all time. These are the optional
per-subcategory goals *within* an envelope, not the envelope itself; every main-category envelope is
covered by §2. `CategoryBudgetLimits` has no spare column to borrow and would need its own storage
answer, so it is a known gap rather than an oversight.

## 7. Acceptance criteria

- [ ] Set an envelope to 400, let a period end, change it to 500: the finished period still reads 400,
      the current one reads 500.
- [ ] The same budget's history view shows the old amounts, not the new one, for every finished period.
- [ ] Adjusting the amount twice in one month leaves one entry, not two.
- [ ] A second signed-in device shows the same per-period amounts after sync.
- [ ] A backup restored onto a fresh install keeps the history.
- [ ] An original-Cashew backup still imports and its budgets behave normally.
- [ ] Changing a budget's cycle asks for confirmation first, and cancelling leaves the budget as it
      was; confirming clears the history rather than misattributing it.
- [ ] Changing the cycle of a budget that was never adjusted saves without any prompt.
