import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/budgetVisibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// Per-budget visibility rides in `Budgets.sharedMembers`, a column left dead
/// by the removal of Firestore sharing. See struct/budgetVisibility.dart.
///
/// These target the pure encode/decode and the visibility rule, and avoid the
/// helpers that read `cachedServerProfile` -- that global belongs to the
/// signed-in session and there is no session in a unit test. The rule itself
/// takes the viewer as a parameter for exactly that reason.
void main() {
  Budget budgetWith({List<String>? members}) {
    return Budget(
      budgetPk: 'holiday',
      name: 'Holiday',
      amount: 100,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 2, 1),
      categoryFks: const ['travel'],
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
      sharedMembers: members,
    );
  }

  group('resolving an owner', () {
    test('no entry means the budget belongs to the whole household', () {
      expect(budgetOwner(budgetWith()), isNull);
      expect(budgetOwner(budgetWith(members: const [])), isNull);
      expect(isPersonalBudget(budgetWith()), isFalse);
    });

    test('a single numeric entry is the owning account', () {
      expect(budgetOwner(budgetWith(members: const ['7'])), 7);
      expect(isPersonalBudget(budgetWith(members: const ['7'])), isTrue);
    });

    test('an original-Cashew backup\'s member IDs read as shared', () {
      // Upstream stored real member identifiers here. Misreading one as a user
      // id would hide somebody's imported budgets from them with no way to
      // find out why, so anything that is not exactly one run of digits is
      // treated as "shared" -- the same strictness budgetPeriodAmounts.dart
      // applies to the column next door.
      for (final members in const [
        ['someone@example.com'],
        ['someone@example.com', 'other@example.com'],
        ['7', '9'],
        [''],
        ['7a'],
        ['-7'],
      ]) {
        expect(budgetOwner(budgetWith(members: members)), isNull,
            reason: 'members $members must not be read as an owner');
      }
    });

    test('round-trips through the stored form', () {
      final shared = withBudgetOwner(budgetWith(), null);
      expect(shared.sharedMembers, isNull);
      expect(budgetOwner(shared), isNull);

      final personal = withBudgetOwner(budgetWith(), 42);
      expect(personal.sharedMembers, ['42']);
      expect(budgetOwner(personal), 42);

      // Sharing something previously personal must actually clear it, not
      // leave a stale owner behind.
      expect(budgetOwner(withBudgetOwner(personal, null)), isNull);
    });
  });

  group('deciding what to draw', () {
    test('a shared budget is visible to everyone', () {
      final budget = budgetWith();
      expect(isBudgetVisibleTo(budget, 1), isTrue);
      expect(isBudgetVisibleTo(budget, 2), isTrue);
      expect(isBudgetVisibleTo(budget, null), isTrue);
    });

    test('a personal budget is visible only to its owner', () {
      final budget = budgetWith(members: const ['1']);
      expect(isBudgetVisibleTo(budget, 1), isTrue);
      expect(isBudgetVisibleTo(budget, 2), isFalse);
    });

    test('everything is visible when signed out', () {
      // No account means nobody to hide from, and hiding rows on a device with
      // no session would just lose them from view with no way back.
      expect(isBudgetVisibleTo(budgetWith(members: const ['1']), null), isTrue);
    });
  });
}
