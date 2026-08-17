import 'package:cashew_selfhosted/database/envelopeMigration.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one-shot conversion from envelopes-as-budgets to the CategoryEnvelopes
/// table, minus the database: which budgets are recognised as envelopes, what
/// their packed amount history becomes, and - the one that matters most - which
/// budgets are left strictly alone.
void main() {
  Budget budget({
    required String budgetPk,
    List<String>? categoryFks,
    double amount = 0,
    List<String>? sharedAllMembersEver,
  }) =>
      Budget(
        budgetPk: budgetPk,
        name: 'Budget $budgetPk',
        amount: amount,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 31),
        income: false,
        archived: false,
        addedTransactionsOnly: false,
        periodLength: 1,
        dateCreated: DateTime(2026, 1, 1),
        pinned: false,
        order: 0,
        walletFk: '0',
        categoryFks: categoryFks,
        sharedAllMembersEver: sharedAllMembersEver,
        isAbsoluteSpendingLimit: false,
      );

  final Set<String> mainCategories = {'1', '2', '3'};

  group('which budgets were envelopes', () {
    test('an auto-created envelope is recognised by its pk', () {
      // ensureMainCategoryBudgetsExist keyed every envelope it created by the
      // category's own pk. Nothing else can have that shape.
      expect(
          isLegacyEnvelopeBudget(
              budget(budgetPk: '1', categoryFks: ['1']), mainCategories),
          isTrue);
    });

    test('one whose category list was lost is still recognised', () {
      expect(isLegacyEnvelopeBudget(budget(budgetPk: '2'), mainCategories),
          isTrue);
    });

    test('a hand-made budget targeting one main category is left alone', () {
      // The old implementation would adopt such a budget as a category's
      // envelope. It is still a budget somebody made by hand, it is an ordinary
      // upstream budget now, and this conversion runs on every launch - so
      // converting on intent rather than on pk would eventually eat a budget
      // created after the upgrade.
      expect(
          isLegacyEnvelopeBudget(
              budget(budgetPk: 'uuid', categoryFks: ['1']), mainCategories),
          isFalse);
    });

    test('a budget spanning two categories is left alone', () {
      expect(
          isLegacyEnvelopeBudget(
              budget(budgetPk: 'uuid', categoryFks: ['1', '2']),
              mainCategories),
          isFalse);
    });

    test('an all-categories budget is left alone', () {
      expect(isLegacyEnvelopeBudget(budget(budgetPk: 'uuid'), mainCategories),
          isFalse);
    });

    test('one whose category has not arrived over sync yet is left alone', () {
      // The safety property. This device simply has not heard of the category
      // yet; converting on that guess would delete the budget on every device
      // (specs/01-local-first-invariant.md). A later launch, once it has
      // arrived, converts it.
      expect(isLegacyEnvelopeBudget(budget(budgetPk: 'not-here'), {}), isFalse);
    });

    test('an envelope for the balance-correction category is left alone', () {
      // Category "0" is never envelope-eligible, so it is not in the set.
      expect(isLegacyEnvelopeBudget(budget(budgetPk: '0'), mainCategories),
          isFalse);
    });
  });

  group('the packed amount history', () {
    test('parses entries this fork wrote', () {
      final List<LegacyAmountChange> history = legacyAmountHistory(budget(
        budgetPk: '1',
        sharedAllMembersEver: [
          '${DateTime(2026, 4, 1).millisecondsSinceEpoch}=500',
          '${DateTime(2026, 1, 1).millisecondsSinceEpoch}=100.5',
        ],
      ));
      expect(history.map((c) => c.amount), [100.5, 500]);
      expect(history.first.from, DateTime(2026, 1, 1));
    });

    test('ignores anything that is not exactly that shape', () {
      // An original-Cashew backup has real member ids in this column. Reading
      // one as an amount would invent a plan the household never set.
      final List<LegacyAmountChange> history = legacyAmountHistory(budget(
        budgetPk: '1',
        sharedAllMembersEver: ['someone@example.com', 'member-2', '=', '12345'],
      ));
      expect(history, isEmpty);
    });
  });

  group('what a budget becomes', () {
    final DateTime now = DateTime(2026, 8, 17);

    test('every recorded month becomes its own row', () {
      final List<CategoryEnvelope> envelopes = envelopesForLegacyBudget(
        budget(
          budgetPk: '1',
          categoryFks: ['1'],
          amount: 500,
          sharedAllMembersEver: [
            '${DateTime(2026, 1, 1).millisecondsSinceEpoch}=100',
            '${DateTime(2026, 4, 1).millisecondsSinceEpoch}=500',
          ],
        ),
        '1',
        now: now,
      );
      expect(envelopes.map((e) => e.envelopePk), ['1:2026-01', '1:2026-04']);
      expect(envelopes.map((e) => e.amount), [100, 500]);
      // Nothing is written for the months in between: they resolve by carrying
      // January's 100 forward, which is what they showed before.
      expect(envelopes.length, 2);
    });

    test('two changes inside one month collapse to the later one', () {
      final List<CategoryEnvelope> envelopes = envelopesForLegacyBudget(
        budget(
          budgetPk: '1',
          categoryFks: ['1'],
          sharedAllMembersEver: [
            '${DateTime(2026, 4, 1).millisecondsSinceEpoch}=100',
            '${DateTime(2026, 4, 20).millisecondsSinceEpoch}=300',
          ],
        ),
        '1',
        now: now,
      );
      expect(envelopes.length, 1);
      expect(envelopes.single.amount, 300);
    });

    test('a budget with no history becomes this month at its current amount',
        () {
      final List<CategoryEnvelope> envelopes = envelopesForLegacyBudget(
        budget(budgetPk: '1', categoryFks: ['1'], amount: 250),
        '1',
        now: now,
      );
      expect(envelopes.single.envelopePk, '1:2026-08');
      expect(envelopes.single.amount, 250);
    });

    test('a budget that was never filled in becomes nothing', () {
      // Amount 0 with no history is an envelope the household never set. A zero
      // row would claim they deliberately planned nothing this month.
      expect(
        envelopesForLegacyBudget(
            budget(budgetPk: '1', categoryFks: ['1']), '1',
            now: now),
        isEmpty,
      );
    });
  });
}
