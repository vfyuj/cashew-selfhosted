import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/budgetPeriodAmounts.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

/// A budget used to be one row with one `amount`, so raising this month's
/// target silently rewrote every finished month to the new number -- the
/// history view recomputes each past period from the current value. Per-period
/// amounts fix that by recording, in `Budgets.sharedAllMembersEver`, what the
/// target was from each period onward. See
/// specs/backlog/BL-006-per-period-budget-amounts.md.
///
/// These tests target `budgetAmountForPeriodStart` rather than
/// `budgetAmountForPeriod` on purpose: the latter calls `getBudgetDate`, which
/// reaches for the `database` global and cannot run without a real database.
/// The period-boundary maths is upstream Cashew's and already exercised by the
/// app; what is new, and what these pin down, is the resolution rule.
void main() {
  DateTime month(int year, int monthOfYear) => DateTime(year, monthOfYear, 1);

  Budget budgetWith({required double amount, List<String>? history}) {
    return Budget(
      budgetPk: 'groceries',
      name: 'Groceries',
      amount: amount,
      startDate: month(2026, 1),
      endDate: month(2026, 2),
      categoryFks: const ['groceries'],
      income: false,
      archived: false,
      addedTransactionsOnly: false,
      periodLength: 1,
      reoccurrence: BudgetReoccurence.monthly,
      dateCreated: month(2026, 1),
      pinned: false,
      order: 0,
      walletFk: '0',
      isAbsoluteSpendingLimit: false,
      sharedAllMembersEver: history,
    );
  }

  // "was 400 from January, became 500 from April"
  List<String> januaryFourHundredAprilFiveHundred() => encodeAmountHistory([
        BudgetAmountChange(from: month(2026, 1), amount: 400),
        BudgetAmountChange(from: month(2026, 4), amount: 500),
      ]);

  group('resolving a period amount', () {
    test('a budget that was never adjusted reads its current amount', () {
      final budget = budgetWith(amount: 400);
      expect(budgetAmountForPeriodStart(budget, month(2026, 1)), 400);
      expect(budgetAmountForPeriodStart(budget, month(2030, 9)), 400);
    });

    test('finished periods keep the amount they had, not the current one', () {
      // The whole point: amount is now 500, but January must still read 400.
      final budget =
          budgetWith(amount: 500, history: januaryFourHundredAprilFiveHundred());
      expect(budgetAmountForPeriodStart(budget, month(2026, 1)), 400);
      expect(budgetAmountForPeriodStart(budget, month(2026, 2)), 400);
      expect(budgetAmountForPeriodStart(budget, month(2026, 3)), 400);
    });

    test('the period an entry starts in, and every one after, takes it', () {
      final budget =
          budgetWith(amount: 500, history: januaryFourHundredAprilFiveHundred());
      expect(budgetAmountForPeriodStart(budget, month(2026, 4)), 500);
      expect(budgetAmountForPeriodStart(budget, month(2026, 5)), 500);
      expect(budgetAmountForPeriodStart(budget, month(2031, 1)), 500);
    });

    test('a period before the first entry keeps the oldest amount', () {
      final budget =
          budgetWith(amount: 500, history: januaryFourHundredAprilFiveHundred());
      expect(budgetAmountForPeriodStart(budget, month(2025, 6)), 400);
    });

    test('entries out of order still resolve chronologically', () {
      final budget = budgetWith(
        amount: 500,
        history: encodeAmountHistory([
          BudgetAmountChange(from: month(2026, 4), amount: 500),
          BudgetAmountChange(from: month(2026, 1), amount: 400),
        ]),
      );
      expect(budgetAmountForPeriodStart(budget, month(2026, 2)), 400);
      expect(budgetAmountForPeriodStart(budget, month(2026, 4)), 500);
    });
  });

  group('upstream Cashew compatibility', () {
    // The column this feature borrows holds member IDs in an original-Cashew
    // backup. Misreading those as amounts is exactly what would break the
    // "upstream backups still import" invariant in CLAUDE.md.
    test('member IDs from an upstream backup are ignored, not parsed', () {
      final budget = budgetWith(
        amount: 250,
        history: const [
          'aBcD1234EfGh',
          'someone@example.com',
          'member=42',
          '',
        ],
      );
      expect(budgetAmountHistory(budget), isEmpty);
      expect(budgetAmountForPeriodStart(budget, month(2026, 1)), 250);
    });

    test('real entries still parse alongside unrecognised ones', () {
      final budget = budgetWith(
        amount: 500,
        history: [
          'aBcD1234EfGh',
          ...januaryFourHundredAprilFiveHundred(),
        ],
      );
      expect(budgetAmountHistory(budget).length, 2);
      expect(budgetAmountForPeriodStart(budget, month(2026, 2)), 400);
    });
  });

  group('recording an amount change', () {
    // withUpdatedAmountHistory calls getBudgetDate for the *current* period,
    // so only the paths that return before reaching it are unit-testable here.
    // The seed-and-upsert path is covered by the owner's acceptance pass.
    test('a newly created budget starts with no history', () {
      final created = withUpdatedAmountHistory(
        previous: null,
        updated: budgetWith(amount: 400),
      );
      expect(created.sharedAllMembersEver, isNull);
    });

    test('changing the cycle clears history whose keys no longer line up', () {
      final previous =
          budgetWith(amount: 500, history: januaryFourHundredAprilFiveHundred());
      final updated = previous.copyWith(
          reoccurrence: const Value(BudgetReoccurence.weekly));
      expect(
        withUpdatedAmountHistory(previous: previous, updated: updated)
            .sharedAllMembersEver,
        isNull,
      );
    });

    test('a cycle change is only worth warning about when history exists', () {
      final withHistory =
          budgetWith(amount: 500, history: januaryFourHundredAprilFiveHundred());
      final neverAdjusted = budgetWith(amount: 500);
      final toWeekly = const Value(BudgetReoccurence.weekly);

      // Worth interrupting for: there is a record and it would be discarded.
      expect(
        amountHistoryWouldBeCleared(
          previous: withHistory,
          updated: withHistory.copyWith(reoccurrence: toWeekly),
        ),
        isTrue,
      );
      // Nothing to lose, so the prompt must not fire.
      expect(
        amountHistoryWouldBeCleared(
          previous: neverAdjusted,
          updated: neverAdjusted.copyWith(reoccurrence: toWeekly),
        ),
        isFalse,
      );
      // History exists but the cycle is untouched.
      expect(
        amountHistoryWouldBeCleared(
          previous: withHistory,
          updated: withHistory.copyWith(amount: 900),
        ),
        isFalse,
      );
      // Creating a budget has no previous state to warn about.
      expect(
        amountHistoryWouldBeCleared(previous: null, updated: withHistory),
        isFalse,
      );
    });

    test('period length and start date also count as cycle changes', () {
      final previous =
          budgetWith(amount: 500, history: januaryFourHundredAprilFiveHundred());
      expect(
        amountHistoryWouldBeCleared(
          previous: previous,
          updated: previous.copyWith(periodLength: 2),
        ),
        isTrue,
      );
      expect(
        amountHistoryWouldBeCleared(
          previous: previous,
          updated: previous.copyWith(startDate: month(2026, 3)),
        ),
        isTrue,
      );
    });

    test('saving without touching the amount leaves history alone', () {
      final history = januaryFourHundredAprilFiveHundred();
      final previous = budgetWith(amount: 500, history: history);
      final updated = previous.copyWith(name: 'Food');
      expect(
        withUpdatedAmountHistory(previous: previous, updated: updated)
            .sharedAllMembersEver,
        history,
      );
    });
  });

  group('encoding', () {
    test('round-trips through the stored string form', () {
      final budget =
          budgetWith(amount: 500, history: januaryFourHundredAprilFiveHundred());
      final parsed = budgetAmountHistory(budget);
      expect(parsed.map((c) => c.amount).toList(), [400, 500]);
      expect(parsed.map((c) => c.from).toList(), [month(2026, 1), month(2026, 4)]);
      expect(encodeAmountHistory(parsed), januaryFourHundredAprilFiveHundred());
    });

    test('negative and fractional amounts survive', () {
      final budget = budgetWith(
        amount: 0,
        history: encodeAmountHistory([
          BudgetAmountChange(from: month(2026, 1), amount: -12.75),
        ]),
      );
      expect(budgetAmountForPeriodStart(budget, month(2026, 1)), -12.75);
    });
  });
}
