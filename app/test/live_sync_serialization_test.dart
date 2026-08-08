import 'dart:convert';

import 'package:cashew_selfhosted/database/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the bug that made Stage 2 live sync fail completely:
/// columns whose converter was a plain `TypeConverter` were left untouched by
/// Drift's generated `toJson`, so the data class emitted raw Dart enum
/// instances. `jsonEncode` in `pushSyncChanges` then threw
/// "Converting object to an encodable object failed", which the push loop
/// caught and turned into a silent, permanent sync outage -- no row ever
/// reached the server. See specs/04-stage-2-instant-sync.md.
///
/// These tests exercise exactly what live sync does: `toJson()` -> `jsonEncode`
/// (the push side) and `jsonDecode` -> `fromJson` (the pull side). A plain
/// `toJson()` assertion would NOT have caught the original bug -- it only
/// surfaces once the result is actually encoded.
void main() {
  group('wallet round-trips through the live sync wire format', () {
    // Non-null homePageWidgetDisplay is the default for every wallet
    // (initializeDefaultDatabase.dart), which is why this broke for everyone.
    final wallet = TransactionWallet(
      walletPk: '0',
      name: 'Bank',
      dateCreated: DateTime.fromMillisecondsSinceEpoch(1786150106000),
      dateTimeModified: DateTime.fromMillisecondsSinceEpoch(1786150332000),
      order: 0,
      decimals: 2,
      // Exactly defaultWalletHomePageWidgetDisplay -- the [0,1] every real
      // wallet carries, and the value that was actually breaking pushes.
      homePageWidgetDisplay: const [
        HomePageWidgetDisplay.WalletSwitcher,
        HomePageWidgetDisplay.WalletList,
      ],
    );

    test('encodes to JSON without throwing', () {
      expect(() => jsonEncode(wallet.toJson()), returnsNormally);
    });

    test('encodes the enum list as plain indices', () {
      final decoded =
          jsonDecode(jsonEncode(wallet.toJson())) as Map<String, dynamic>;
      expect(decoded['homePageWidgetDisplay'], [0, 1]);
    });

    test('survives a full push -> pull round trip', () {
      final overTheWire =
          jsonDecode(jsonEncode(wallet.toJson())) as Map<String, dynamic>;
      final restored = TransactionWallet.fromJson(overTheWire);
      expect(restored.homePageWidgetDisplay, wallet.homePageWidgetDisplay);
      // Compared as maps rather than as data classes: Drift's generated `==`
      // compares List-typed fields by identity, so two structurally identical
      // wallets are never `==`. Map equality is a deep compare, and it also
      // checks that no *other* field was mangled in transit.
      expect(restored.toJson(), wallet.toJson());
    });

    test('a null enum list round-trips too', () {
      final bare = TransactionWallet(
        walletPk: '1',
        name: 'Cash',
        dateCreated: DateTime.fromMillisecondsSinceEpoch(1786150106000),
        order: 1,
        decimals: 2,
      );
      final restored = TransactionWallet.fromJson(
          jsonDecode(jsonEncode(bare.toJson())) as Map<String, dynamic>);
      expect(restored.homePageWidgetDisplay, isNull);
      expect(restored.toJson(), bare.toJson());
    });
  });

  group('budget round-trips through the live sync wire format', () {
    // Same class of bug on Budgets.budgetTransactionFilters -- latent only
    // because a budget-less database never hit it.
    final budget = Budget(
      budgetPk: 'b1',
      name: 'Groceries',
      amount: 250.0,
      startDate: DateTime.fromMillisecondsSinceEpoch(1786150106000),
      endDate: DateTime.fromMillisecondsSinceEpoch(1788742106000),
      income: false,
      archived: false,
      addedTransactionsOnly: false,
      periodLength: 1,
      dateCreated: DateTime.fromMillisecondsSinceEpoch(1786150106000),
      dateTimeModified: DateTime.fromMillisecondsSinceEpoch(1786150332000),
      pinned: true,
      order: 0,
      walletFk: '0',
      budgetTransactionFilters: const [
        BudgetTransactionFilters.addedToOtherBudget,
        BudgetTransactionFilters.sharedToOtherBudget,
      ],
      // The List<String> columns. These are the sneaky ones: they encode
      // perfectly well, so the push succeeds and only the receiving device
      // blows up on `List<dynamic> is not a subtype of List<String>?`.
      walletFks: const ['0', 'w2'],
      categoryFks: const ['c1', 'c2'],
      categoryFksExclude: const ['c3'],
      sharedMembers: const ['someone@example.com'],
      isAbsoluteSpendingLimit: false,
    );

    test('encodes to JSON without throwing', () {
      expect(() => jsonEncode(budget.toJson()), returnsNormally);
    });

    test('survives a full push -> pull round trip', () {
      final restored = Budget.fromJson(
          jsonDecode(jsonEncode(budget.toJson())) as Map<String, dynamic>);
      expect(restored.budgetTransactionFilters, budget.budgetTransactionFilters);
      expect(restored.walletFks, budget.walletFks);
      expect(restored.categoryFks, budget.categoryFks);
      expect(restored.sharedMembers, budget.sharedMembers);
      expect(restored.toJson(), budget.toJson());
    });
  });

  test('a transaction with budgetFksExclude round-trips', () {
    // Transaction's own List<String> column -- same trap as Budget's.
    final transaction = Transaction(
      transactionPk: 't1',
      name: 'Coffee',
      amount: -4.5,
      note: '',
      categoryFk: '1',
      walletFk: '0',
      dateCreated: DateTime.fromMillisecondsSinceEpoch(1786150106000),
      dateTimeModified: DateTime.fromMillisecondsSinceEpoch(1786150332000),
      income: false,
      paid: true,
      skipPaid: false,
      budgetFksExclude: const ['b1', 'b2'],
    );
    final restored = Transaction.fromJson(
        jsonDecode(jsonEncode(transaction.toJson())) as Map<String, dynamic>);
    expect(restored.budgetFksExclude, transaction.budgetFksExclude);
    expect(restored.toJson(), transaction.toJson());
  });

  test('every synced data class encodes -- guards against the next such column',
      () {
    // A blanket check so a future column with a plain TypeConverter fails here
    // rather than silently killing sync in production.
    final rows = <dynamic>[
      TransactionWallet(
        walletPk: '0',
        name: 'Bank',
        dateCreated: DateTime.now(),
        order: 0,
        decimals: 2,
        homePageWidgetDisplay: HomePageWidgetDisplay.values,
      ),
      TransactionCategory(
        categoryPk: '1',
        name: 'Dining',
        dateCreated: DateTime.now(),
        order: 0,
        income: false,
        methodAdded: MethodAdded.csv,
      ),
      Transaction(
        transactionPk: 't1',
        name: 'Coffee',
        amount: -4.5,
        note: '',
        categoryFk: '1',
        walletFk: '0',
        dateCreated: DateTime.now(),
        income: false,
        paid: true,
        skipPaid: false,
        type: TransactionSpecialType.subscription,
        methodAdded: MethodAdded.csv,
        sharedStatus: SharedStatus.shared,
      ),
      Objective(
        objectivePk: 'o1',
        type: ObjectiveType.goal,
        name: 'Trip',
        amount: 1000,
        order: 0,
        dateCreated: DateTime.now(),
        income: true,
        pinned: true,
        archived: false,
        walletFk: '0',
      ),
    ];

    for (final row in rows) {
      expect(() => jsonEncode(row.toJson()), returnsNormally,
          reason: '${row.runtimeType}.toJson() is not JSON-encodable');
    }
  });
}
