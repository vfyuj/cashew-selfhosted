import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/mainCategoryBudgets.dart';
import 'package:cashew_selfhosted/struct/subCategoryBudgetAllocation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The over-allocation check converts every subcategory budget to the parent
/// envelope's period before summing, so a weekly budget and a monthly one can
/// be added together meaningfully.
///
/// Only [amountOverPeriod] is exercised here. Everything above it needs
/// `getBudgetDate` (for the period lengths) and `budgetAmountToPrimaryCurrency`
/// (for the exchange rates), both of which reach globals that only exist in a
/// running app -- the same reason budget_period_amounts_test.dart targets
/// `budgetAmountForPeriodStart` rather than `budgetAmountForPeriod`. The
/// conversion is the part that is new and the part that can be silently wrong.
void main() {
  group('converting an amount between periods', () {
    test('an amount already on the target period is untouched', () {
      expect(amountOverPeriod(400, 31, 31), 400);
    });

    test('a weekly budget scales up against a month', () {
      // 100 a week is what you actually commit across a 31 day month.
      expect(amountOverPeriod(100, 7, 31), closeTo(442.857, 0.001));
    });

    test('a yearly budget scales down against a month', () {
      expect(amountOverPeriod(1200, 365, 30), closeTo(98.630, 0.001));
    });

    test('a nonsensical period is left alone rather than dividing by zero', () {
      // getBudgetDate can return a zero-length range for a custom budget whose
      // start and end are the same day. Counting that amount once is wrong by
      // less than crashing, or than silently contributing infinity to a total
      // that then always looks over-allocated.
      expect(amountOverPeriod(50, 0, 31), 50);
      expect(amountOverPeriod(50, 31, 0), 50);
      expect(amountOverPeriod(50, -1, 31), 50);
    });

    test('zero stays zero', () {
      expect(amountOverPeriod(0, 7, 31), 0);
    });
  });

  group('attributing a budget to a main category', () {
    // "Gifts & charity" has three subcategories; "Food" has one. Only budgets
    // whose every category sits under the same parent count against that
    // parent's envelope.
    const PlannedBudgetTotals totals = PlannedBudgetTotals(
      budgets: [],
      mainCategoryPks: {'gifts', 'food'},
      subCategoryParents: {
        'presents': 'gifts',
        'charity': 'gifts',
        'irregular': 'gifts',
        'groceries': 'food',
      },
    );

    test('one subcategory attributes to its parent', () {
      expect(totals.soleParentOfSubCategories(['presents']), 'gifts');
    });

    test('several subcategories of one parent still attribute to it', () {
      // The ordinary case once the picker lets you tick two subcategories in
      // one budget.
      expect(
          totals.soleParentOfSubCategories(['presents', 'charity']), 'gifts');
      expect(
          totals
              .soleParentOfSubCategories(['presents', 'charity', 'irregular']),
          'gifts');
    });

    test('subcategories of different parents attribute to neither', () {
      expect(
          totals.soleParentOfSubCategories(['presents', 'groceries']), isNull,
          reason: 'a budget spanning two categories belongs to neither, and '
              'counting it against one would overstate that one');
    });

    test('a main category is not a subcategory of anything', () {
      expect(totals.soleParentOfSubCategories(['gifts']), isNull);
      expect(totals.soleParentOfSubCategories(['gifts', 'presents']), isNull,
          reason: 'the parent alone already covers everything inside it');
    });

    test('an unknown category attributes to nothing', () {
      expect(totals.soleParentOfSubCategories(['made-up']), isNull);
      expect(totals.soleParentOfSubCategories([]), isNull);
    });
  });

  group('reporting an allocation', () {
    final Budget envelope = Budget(
      budgetPk: 'personal',
      name: 'Personal',
      amount: 1000,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 2, 1),
      categoryFks: const ['personal'],
      income: false,
      archived: false,
      addedTransactionsOnly: false,
      periodLength: 1,
      reoccurrence: BudgetReoccurence.monthly,
      dateCreated: DateTime(2026, 1, 1),
      pinned: false,
      order: 0,
      walletFk: '0',
      isAbsoluteSpendingLimit: false,
    );

    SubCategoryAllocation allocation({
      required double budgeted,
      required double allocated,
      double hidden = 0,
      int hiddenCount = 0,
    }) {
      return SubCategoryAllocation(
        envelope: envelope,
        envelopeAmount: budgeted,
        allocated: allocated,
        hiddenAllocated: hidden,
        hiddenCount: hiddenCount,
      );
    }

    test('fitting inside the envelope is not a problem', () {
      final a = allocation(budgeted: 1000, allocated: 800);
      expect(a.isOver, isFalse);
      expect(a.excess, 0);
    });

    test('exactly filling the envelope is not a problem either', () {
      expect(allocation(budgeted: 1000, allocated: 1000).isOver, isFalse);
    });

    test('committing more than the envelope reports the shortfall', () {
      final a = allocation(budgeted: 1000, allocated: 1200);
      expect(a.isOver, isTrue);
      expect(a.excess, 200);
    });

    test('knows when part of the total is not on screen', () {
      expect(allocation(budgeted: 1000, allocated: 1200).hasHidden, isFalse);
      expect(
          allocation(
                  budgeted: 1000, allocated: 1200, hidden: 600, hiddenCount: 2)
              .hasHidden,
          isTrue);
    });
  });
}
