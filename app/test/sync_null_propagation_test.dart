import 'package:cashew_selfhosted/database/tables.dart';
// Only the three symbols this test needs. A bare drift import also exports an
// `isNull` that collides with the matcher of the same name.
import 'package:drift/drift.dart' show Expression, Insertable, Variable;
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the bug that deleted household transactions: a cleared
/// column never crossed to another device.
///
/// `processSyncLogs` applies each incoming row with `batch.update(table, row)`.
/// Drift's `Batch.update` calls `entity.toColumns(nullToAbsent: true)`, and a
/// generated **data class** honours that flag by omitting every null column
/// from the SET clause. The `insertOrIgnore` that follows is a no-op for a row
/// that already exists, so "this column is now null" was silently dropped.
///
/// Promoting a subcategory to a main category clears
/// `Categories.mainCategoryPk`. On every peer the category therefore stayed a
/// subcategory, `deleteWanderingTransactions` judged its transactions orphaned,
/// and -- back when it wrote tombstones -- broadcast their deletion to the
/// whole household.
///
/// The fix converts each row with `toCompanion(false)` first: a companion
/// ignores `nullToAbsent` and emits every column, with an explicit
/// `Value(null)` for each nullable field.
///
/// Note what these tests assert against. A `toJson()` round trip -- what
/// live_sync_serialization_test.dart covers -- would NOT have caught this: the
/// null travelled over the wire perfectly well. The loss happened one layer
/// further in, when the received row was turned into SQL. So these tests call
/// `toColumns` directly, the way `Batch.update` does.
void main() {
  /// The SET clause Drift builds for this row, exactly as `Batch.update` does.
  Map<String, Expression> setClauseFor(Insertable<dynamic> row) =>
      row.toColumns(true);

  bool writes(Insertable<dynamic> row, String column) =>
      setClauseFor(row).containsKey(column);

  Object? writtenValue(Insertable<dynamic> row, String column) =>
      (setClauseFor(row)[column] as Variable).value;

  /// Asserts the pair that matters for one column: the data class drops it,
  /// the companion writes it as an explicit NULL.
  ///
  /// `row` is dynamic because `toCompanion` lives on each generated data class
  /// rather than on the shared `DataClass` supertype.
  void expectClearable(dynamic row, String column) {
    expect(writes(row, column), isFalse,
        reason: '$column: a data class is expected to drop nulls. If this '
            'fails, Drift changed nullToAbsent semantics and processSyncLogs '
            'can be simplified.');
    final Insertable<dynamic> companion = row.toCompanion(false);
    expect(writes(companion, column), isTrue,
        reason: '$column would not be cleared on a peer device');
    expect(writtenValue(companion, column), isNull);
  }

  group('a promoted subcategory clears mainCategoryPk over sync', () {
    final promoted = TransactionCategory(
      categoryPk: 'groceries',
      name: 'Groceries',
      dateCreated: DateTime.fromMillisecondsSinceEpoch(1786150106000),
      dateTimeModified: DateTime.fromMillisecondsSinceEpoch(1786150332000),
      order: 3,
      income: false,
      // The whole point: no longer a subcategory of anything.
      mainCategoryPk: null,
    );

    test('the cleared column survives the trip into SQL', () {
      expectClearable(promoted, 'main_category_pk');
    });

    test('the companion still carries the non-null columns', () {
      final companion = promoted.toCompanion(false);
      expect(writtenValue(companion, 'category_pk'), 'groceries');
      expect(writtenValue(companion, 'name'), 'Groceries');
      expect(writtenValue(companion, 'order'), 3);
      expect(writtenValue(companion, 'income'), false);
    });
  });

  group('other nullable columns a peer must be able to clear', () {
    // Cleared by the same promotion that clears mainCategoryPk: the
    // transaction moves up to the category itself, so its subcategory is
    // unset. Had this one not crossed either, a repaired device would still
    // disagree with the origin about which subcategory the row belongs to.
    final transaction = Transaction(
      transactionPk: 't1',
      name: 'Milk',
      amount: -4.5,
      note: '',
      categoryFk: 'groceries',
      subCategoryFk: null,
      walletFk: '0',
      dateCreated: DateTime.fromMillisecondsSinceEpoch(1786150106000),
      income: false,
      paid: true,
      skipPaid: false,
      objectiveFk: null,
      endDate: null,
    );

    test('Transactions.subCategoryFk', () {
      expectClearable(transaction, 'sub_category_fk');
    });

    test('Transactions.objectiveFk', () {
      expectClearable(transaction, 'objective_fk');
    });

    test('Transactions.endDate', () {
      expectClearable(transaction, 'end_date');
    });

    test('Categories.colour', () {
      final category = TransactionCategory(
        categoryPk: 'plain',
        name: 'Plain',
        dateCreated: DateTime.fromMillisecondsSinceEpoch(1786150106000),
        order: 0,
        income: false,
        colour: null,
      );
      expectClearable(category, 'colour');
    });
  });
}
