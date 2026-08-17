import 'package:cashew_selfhosted/database/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [decideWanderingTransaction], the decision that used to destroy
/// household data.
///
/// The invariant is upstream's: `Transactions.categoryFk` always names a MAIN
/// category, with any subcategory recorded separately in `subCategoryFk`.
/// `createOrUpdateTransaction` repairs a violation by swapping the two, and
/// says so in a comment that ends "otherwise the wandering transactions
/// algorithm will delete it".
///
/// `deleteWanderingTransactions` used to answer every violation the same way:
/// delete the row AND write a `DeleteLogType.Transaction` tombstone. A device
/// that was merely *behind* -- one that had not yet learned a subcategory was
/// promoted -- therefore broadcast the deletion of perfectly good transactions
/// to the entire household, including back to the device that made the change.
///
/// So the bug was never in the deleting. It was in there being only one
/// answer. These tests pin the three cases apart.
void main() {
  TransactionCategory category(String pk, {String? parent}) =>
      TransactionCategory(
        categoryPk: pk,
        name: pk,
        dateCreated: DateTime.fromMillisecondsSinceEpoch(1786150106000),
        order: 0,
        income: false,
        mainCategoryPk: parent,
      );

  Map<String, TransactionCategory> byPk(List<TransactionCategory> categories) =>
      {for (TransactionCategory c in categories) c.categoryPk: c};

  test('a transaction on a main category is left alone', () {
    expect(
      decideWanderingTransaction(
        categoryFk: 'food',
        categoriesByPk: byPk([category('food')]),
      ),
      WanderingTransactionAction.keep,
    );
  });

  test('a transaction filed on a subcategory is repaired, not deleted', () {
    // The reported scenario, seen from the device that is behind: "groceries"
    // has been promoted to a main category elsewhere, but here it still reads
    // as a subcategory of "food". The old code deleted this transaction and
    // told every other device to do the same.
    expect(
      decideWanderingTransaction(
        categoryFk: 'groceries',
        categoriesByPk: byPk([
          category('food'),
          category('groceries', parent: 'food'),
        ]),
      ),
      WanderingTransactionAction.repair,
    );
  });

  test('a transaction whose category does not exist here is deleted', () {
    expect(
      decideWanderingTransaction(
        categoryFk: 'deleted-long-ago',
        categoriesByPk: byPk([category('food')]),
      ),
      WanderingTransactionAction.delete,
    );
  });

  test('a subcategory whose parent is also gone has nothing to repair into',
      () {
    expect(
      decideWanderingTransaction(
        categoryFk: 'groceries',
        categoriesByPk: byPk([category('groceries', parent: 'food')]),
      ),
      WanderingTransactionAction.delete,
    );
  });

  test('an empty category map deletes nothing it cannot account for', () {
    // Degenerate but worth pinning: on a device that has not yet received any
    // categories, every transaction looks orphaned. The caller is what makes
    // this survivable -- it deletes without a tombstone, so the mistake stays
    // local and the next pull restores the rows.
    expect(
      decideWanderingTransaction(
        categoryFk: 'food',
        categoriesByPk: const {},
      ),
      WanderingTransactionAction.delete,
    );
  });
}
