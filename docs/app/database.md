# The app's database

Drift over SQLite, `app/lib/database/tables.dart`. This is the real data — transactions, budgets,
categories, wallets, objectives — and it is what a Cashew backup file contains. The server's own
database is unrelated; see [../server/database.md](../server/database.md).

## Upstream's tables are identical to upstream's, on purpose

`schemaVersionGlobal = 48`, 11 tables: upstream Cashew's 10, unchanged column for column, plus one
the fork owns. An original-Cashew backup therefore imports as-is. Verify:

```bash
diff <(sed '/^@DataClassName..CategoryEnvelope../,/^}/d' app/lib/database/tables.dart | grep -E "^class [A-Za-z]+ extends Table|^  [A-Za-z]+Column") <(grep -E "^class [A-Za-z]+ extends Table|^  [A-Za-z]+Column" upstream/budget/lib/database/tables.dart)
```

Empty output means the shared tables are still identical. (`upstream/` is a read-only reference clone
and is not checked in, so it exists only in the main checkout — from a worktree, point the second
path there.)

The `sed` cuts the fork's own table out before comparing. Every *other* difference is still a
finding: **no upstream table or column may change**, which is the part that keeps backups importable.

## Fork-owned tables

One, so far:

| Table | Holds | Owner |
|---|---|---|
| `CategoryEnvelopes` | one category's planned amount for one month, and the account whose currency it is in | `struct/categoryEnvelopes.dart` |

Adding a table is the one shape of divergence that costs nothing in the direction we promised:
restoring an original-Cashew backup just leaves it empty. Changing an existing table would break that
promise and is still off the table.

Keep this list and the `sed` above in step. A second fork table means extending both, and it means
asking first whether a dead column would do — the answer is usually no, which is why this section
exists at all (see below).

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

## Changing the schema

`schemaVersionGlobal`, a `fromNToN+1` step in `tables.dart`, and three generated artefacts that have
to be regenerated in the same change:

```bash
cd app
dart run build_runner build --delete-conflicting-outputs          # tables.g.dart
dart run drift_dev schema dump lib/database/tables.dart drift_schemas/drift_schema_v<N>.json
dart run drift_dev schema steps drift_schemas/ lib/database/schema_versions.dart
dart run drift_dev schema generate drift_schemas/ test/generated_migrations
```

The last one is what `test/schema_migration_test.dart` runs against: it migrates a real SQLite
database from the previous version and validates the result against the generated definition of the
new one. That test exists because a migration step that quietly does nothing is invisible — the table
is missing, every query against it throws inside a stream, and the screen that reads it just renders
empty. It also covers the envelope conversion end to end, on the database shape an imported 1.1.x
backup actually has.

## Version numbers are shared with upstream, and that bites

The fork owns a table but not the counter: `schemaVersionGlobal` is upstream Cashew's, and upstream
kept moving after the release this fork branched from. Its 6.x backups declare **48** — the same
number the fork now uses, with a different meaning, and until 1.2.1 a number *above* the fork's own.
Importing one is at best a no-op and at worst a *downgrade* as far as drift is concerned, so it runs
no migration at all, and the database then has upstream's newer schema with no `category_envelopes`
in it, because that table is the fork's.

That is not a hypothetical: an owner imported a 6.6.11 backup and got an envelopes screen that read
empty and swallowed every amount typed into it, with `Migrating from: 48 to 47` the only clue.

So the fork-owned table is created in **`beforeOpen`**, not only in the migration step — one failed
statement per launch buys an invariant instead of a promise about version numbers. **Every column
added to it since gets the same treatment**, one `addColumn` per launch, for exactly the same reason:
a database that arrives already stamped at or above our version never runs the step that would have
added it, and a table missing a column fails every read of it. Any future fork-owned table or column
must do the same. `test/schema_migration_test.dart` pins both with databases deliberately stamped by
hand.

Importing a *newer* upstream backup is otherwise outside what `CLAUDE.md` promises — that promise is
about original-Cashew backups from the 5.4.3 line the fork branched from. Extra columns upstream adds
are harmless (queries name their columns), but a table or column upstream *removes* would not be.

## Dead columns as fork storage — withdrawn

Every `shared*` column on `Budgets` is dead again. Nothing in the app reads or writes any of them.

For two releases, `Budgets.sharedAllMembersEver` held a budget's per-period amount history and
`Budgets.sharedMembers` held the one member a budget was personal to. Both features are gone: the
plan moved to the `CategoryEnvelopes` table above, and budgets went back to being upstream's budgets.
The one-shot conversion (`database/envelopeMigration.dart`) nulls both columns out on the way past.

It is worth knowing why that experiment ended, because the columns are still sitting there looking
convenient. Storing a feature in a column whose name says something else means every reader has to be
told the name lies, every parse has to be defensive enough to survive an original-Cashew backup's
real member IDs arriving in the same column, and the schema check that is supposed to catch drift
reports nothing at all. A table of the fork's own says what it is, and costs one line in the section
above.

`sharedKey`, `sharedOwnerMember` and `sharedDateUpdated` were never borrowed. That matters: the two surviving bits of Firestore UI (the "Created by" line on the budget page,
the payer chips on the add-transaction page) are gated on `sharedKey != null`. Writing to it would
wake those dead paths and put a raw user id on screen — which is why `sharedMembers` was borrowed
instead.

If a dead column is ever borrowed again, check the same two things first: that nothing reads it
today, and that writing it does not re-animate UI that was left in place. Then check the harder one —
whether what you actually want is a fork-owned table.

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

Why: `specs/backlog/BL-001-category-locked-budgets.md` and
`specs/backlog/BL-006-per-period-budget-amounts.md` (the two withdrawn features and what replaced
them), `specs/06-shared-household-data.md` (personal budgets, and why they were dropped),
`specs/04-stage-2-instant-sync.md` (the converter change).
