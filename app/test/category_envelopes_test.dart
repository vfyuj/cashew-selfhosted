import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:flutter_test/flutter_test.dart';

/// The decisions behind envelopes, tested without a database: which categories
/// get one, what a month with no row of its own resolves to, and that two
/// devices setting the same month land on the same row.
///
/// The carry-forward cases are the ones ported from the deleted
/// budget_period_amounts_test.dart - same rule, applied to a real table instead
/// of a string packed into a dead column.
void main() {
  TransactionCategory category(String pk,
          {bool income = false, String? mainCategoryPk}) =>
      TransactionCategory(
        categoryPk: pk,
        name: 'Category $pk',
        dateCreated: DateTime(2026, 1, 1),
        order: 0,
        income: income,
        mainCategoryPk: mainCategoryPk,
        methodAdded: MethodAdded.csv,
      );

  CategoryEnvelope envelope(String categoryPk, DateTime month, double amount) =>
      newCategoryEnvelope(
          categoryPk: categoryPk, periodStart: month, amount: amount);

  group('envelope primary keys', () {
    test('are derived from the category and the month, not generated', () {
      expect(envelopePkFor('7', DateTime(2026, 8, 1)), '7:2026-08');
      // Two devices, same category, same month, one row.
      expect(envelopePkFor('7', DateTime(2026, 8, 14)),
          envelopePkFor('7', DateTime(2026, 8, 1)));
    });

    test('pad the month so keys sort the way months do', () {
      expect(envelopePkFor('7', DateTime(2026, 3, 1)), '7:2026-03');
    });

    test('a new envelope is normalised to the first of the month', () {
      final CategoryEnvelope created = envelope('7', DateTime(2026, 8, 23), 50);
      expect(created.periodStart, DateTime(2026, 8, 1));
      expect(created.envelopePk, '7:2026-08');
    });
  });

  group('which categories get an envelope', () {
    test('main categories do', () {
      expect(isEnvelopeEligible(category('7')), isTrue);
    });

    test('subcategories do not - the plan is per main category', () {
      expect(isEnvelopeEligible(category('8', mainCategoryPk: '7')), isFalse);
    });

    test('the balance-correction category never does', () {
      // Category "0" stands in for account corrections and transfers, neither
      // of which is planned spending.
      expect(isEnvelopeEligible(category(balanceCorrectionCategoryPk)), isFalse);
    });
  });

  group('resolving the amount for a month', () {
    final List<CategoryEnvelope> envelopes = [
      envelope('7', DateTime(2026, 1, 1), 100),
      envelope('7', DateTime(2026, 4, 1), 500),
    ];

    test('a month with its own row uses it', () {
      expect(
          envelopeAmountForPeriodStart(envelopes, DateTime(2026, 4, 1)), 500);
    });

    test('a later month carries the nearest earlier row forward', () {
      expect(
          envelopeAmountForPeriodStart(envelopes, DateTime(2026, 9, 1)), 500);
    });

    test('a month between two rows keeps the earlier one', () {
      // The exact bug per-period amounts existed to fix: raising the amount in
      // April must not rewrite what February was measured against.
      expect(
          envelopeAmountForPeriodStart(envelopes, DateTime(2026, 2, 1)), 100);
    });

    test('a month before every row has no plan at all', () {
      // Null, not zero: "never filled in" and "deliberately nothing" are
      // different answers, and only one of them should read as a placeholder.
      expect(envelopeAmountForPeriodStart(envelopes, DateTime(2025, 12, 1)),
          isNull);
    });

    test('a category with no rows has no plan', () {
      expect(envelopeAmountForPeriodStart([], DateTime(2026, 4, 1)), isNull);
    });

    test('an explicit zero is a plan, and stops the carry-forward', () {
      final List<CategoryEnvelope> withZero = [
        ...envelopes,
        envelope('7', DateTime(2026, 6, 1), 0),
      ];
      expect(envelopeAmountForPeriodStart(withZero, DateTime(2026, 7, 1)), 0);
    });

    test('any day of the month resolves to that month', () {
      expect(
          envelopeAmountForPeriodStart(envelopes, DateTime(2026, 4, 30)), 500);
    });
  });

  group('the plan as a whole', () {
    final List<TransactionCategory> categories = [
      category('1'),
      category('2'),
      category('3', income: true),
      category('4', mainCategoryPk: '1'),
      category(balanceCorrectionCategoryPk),
    ];
    final List<CategoryEnvelope> envelopes = [
      envelope('1', DateTime(2026, 8, 1), 300),
      envelope('2', DateTime(2026, 7, 1), 200),
      envelope('3', DateTime(2026, 8, 1), 2000),
      envelope('4', DateTime(2026, 8, 1), 50),
      envelope(balanceCorrectionCategoryPk, DateTime(2026, 8, 1), 999),
    ];
    final EnvelopePlan plan = buildEnvelopePlan(categories, envelopes);

    test('lists only categories that can have an envelope', () {
      expect(plan.categories.map((c) => c.categoryPk), ['1', '2', '3']);
    });

    test('income and expense come from the category, never from the row', () {
      expect(plan.categoriesOfType(income: true).map((c) => c.categoryPk),
          ['3']);
      expect(plan.categoriesOfType(income: false).map((c) => c.categoryPk),
          ['1', '2']);
    });

    test('totals include an amount carried forward from an earlier month', () {
      // Category 2 was last set in July and is untouched in August.
      expect(
          plan.totalPlanned(income: false, periodStart: DateTime(2026, 8, 1)),
          500);
      expect(plan.totalPlanned(income: true, periodStart: DateTime(2026, 8, 1)),
          2000);
    });

    test('rows for ineligible categories are ignored, not counted', () {
      expect(plan.amountFor('4', DateTime(2026, 8, 1)), isNull);
      expect(plan.amountFor(balanceCorrectionCategoryPk, DateTime(2026, 8, 1)),
          isNull);
    });

    test('a carried-forward amount is distinguishable from a stored one', () {
      // What lets the screen show a real number for August while still knowing
      // that August has no row to update in place.
      expect(plan.amountFor('2', DateTime(2026, 8, 1)), 200);
      expect(plan.storedEnvelopeFor('2', DateTime(2026, 8, 1)), isNull);
      expect(plan.storedEnvelopeFor('2', DateTime(2026, 7, 1))?.amount, 200);
    });
  });
}
