# The app's database

Drift over SQLite, `app/lib/database/tables.dart`. This is the real data — transactions, budgets,
categories, wallets, objectives — and it is what a Cashew backup file contains. The server's own
database is unrelated; see [../server/database.md](../server/database.md).

## The schema is identical to upstream's, on purpose

`schemaVersionGlobal = 46`, 10 tables, byte-identical to upstream Cashew's, so an original-Cashew
backup imports as-is. Verify:

```bash
diff <(grep -E "^class [A-Za-z]+ extends Table|^  [A-Za-z]+Column" app/lib/database/tables.dart) <(grep -E "^class [A-Za-z]+ extends Table|^  [A-Za-z]+Column" upstream/budget/lib/database/tables.dart)
```

Empty output means still identical. (`upstream/` is a read-only reference clone and is not checked
in, so it exists only in the main checkout — from a worktree, point the second path there.)

The pattern is narrowed to `extends Table` and column declarations deliberately. A looser `^class`
also catches the type converters, which legitimately differ: the fork gave them
`with JsonTypeConverter2<...>` so the sync feed can carry them as JSON. That changes serialization,
not the stored SQLite representation — a real difference that is not a schema difference, and it
produces a false alarm.

That converter change was not cosmetic. `List<String>` columns (`walletFks`, `categoryFks`,
`sharedMembers`, `budgetFksExclude`) are JSON-encodable, so pushes went out clean and only
*reconstruction* on the receiving device threw `List<dynamic> is not a subtype of List<String>?`.

Divergence is allowed when a feature genuinely needs it — compatibility can then be carried by a
conversion step instead of by identical tables. What to avoid is *incidental* drift: adding or
changing a column without noticing the option has been spent.

## Dead columns as fork storage

Two features live in columns left behind by the deleted Firestore sharing. **Their names no longer
describe their contents**, and each has exactly one owning file. Nothing else in the app may touch
them:

| Column | Now holds | Owner |
|---|---|---|
| `Budgets.sharedAllMembersEver` | per-period amount history | `struct/budgetPeriodAmounts.dart` |
| `Budgets.sharedMembers` | the one member a budget is personal to | `struct/budgetVisibility.dart` |

Both parse **strictly**: an original-Cashew backup has real member IDs in these columns, and anything
not matching the expected shape exactly must be ignored rather than misread. That strictness is what
keeps upstream backups importable, so do not relax it for convenience.

`sharedKey`, `sharedOwnerMember` and `sharedDateUpdated` are still genuinely dead and nothing writes
them. That matters: the two surviving bits of Firestore UI (the "Created by" line on the budget page,
the payer chips on the add-transaction page) are gated on `sharedKey != null`. Writing to it would
wake those dead paths and put a raw user id on screen — which is why `sharedMembers` was borrowed
instead.

Before borrowing a third column, check the same two things: that nothing reads it today, and that
writing it does not re-animate UI that was left in place.

## Sync writes must carry nulls

Every branch of `processSyncLogs` (`database/tables.dart`) converts the incoming row with
`toCompanion(false)` before writing it. That is load bearing.

`Batch.update` calls `entity.toColumns(nullToAbsent: true)`. A generated **data class** honours that
flag and omits every null column from the SET clause; a **companion** ignores it and emits all
columns, and `toCompanion(false)` fills each nullable field with an explicit `Value(null)`. Handed a
data class, an `UPDATE` simply never mentioned the cleared column, and the `insertOrIgnore` that
follows is a no-op for a row that already exists. **Clearing a column was therefore invisible to
every other device.**

That is not a cosmetic gap. Promoting a subcategory to a main category clears
`Categories.mainCategoryPk`. The promotion never landed on peers, so they still read the category as
a subcategory, and `deleteWanderingTransactions` — which back then deleted *and* wrote tombstones —
broadcast the removal of that category's transactions to the whole household, including back to the
device that had made the change. See `specs/04-stage-2-instant-sync.md`.

Upstream got this property for free from `InsertMode.insertOrReplace`, which reinserted the whole
row so absent columns fell back to their null defaults. This fork replaced that with a guarded
update plus `insertOrIgnore` to stop a primary-key conflict from overwriting a newer local row. Both
properties are required — nulls must cross **and** the timestamp guard must hold — and the companion
is what gives the first without giving up the second.

`test/sync_null_propagation_test.dart` pins it per column. Note that a `toJson()` round trip does
**not** cover this: the null travels over the wire perfectly well, and is lost one layer further in,
when the received row is turned into SQL.

---

Why: `specs/backlog/BL-006-per-period-budget-amounts.md` (the first borrowing, and how upstream
behaves if it ever reads one back), `specs/06-shared-household-data.md` (the second),
`specs/04-stage-2-instant-sync.md` (the converter change).
