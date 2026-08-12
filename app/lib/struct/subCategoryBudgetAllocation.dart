import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/budgetPeriodAmounts.dart';
import 'package:cashew_selfhosted/struct/budgetVisibility.dart';
import 'package:cashew_selfhosted/struct/currencyFunctions.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/mainCategoryBudgets.dart';
import 'package:flutter/material.dart' show DateTimeRange;

// Do the budgets for a main category's subcategories still fit inside that
// main category's envelope?
//
// Without this, subcategory budgets can be created without limit and none of
// them affects the main category envelope they sit under, so a household can
// plan 1200 of spending inside a category budgeted at 1000 and find out at the
// end of the month. It is easier to miss once budgets can be personal to one
// member, because then part of the total is not even on screen.
//
// COUNTS WHAT IT CANNOT SHOW. Another member's personal budgets are included
// in the sum. That is the reason personal budgets sync at all rather than
// being kept off the server (see struct/budgetVisibility.dart): a gap the
// viewer cannot see is exactly the gap worth warning about. The figures
// therefore will not always add up to the cards on screen, and the warning
// says so.
//
// UNDER-ALLOCATING IS FINE and never warns. Only committing more than the
// envelope holds is a problem.

/// Converts [amount], which covers [fromDays], into the equivalent over
/// [toDays]. A weekly 100 is 434.5 against a 31-day month.
///
/// Pure, so it can be tested without a database - everything around it needs
/// `getBudgetDate`, which reaches for the `database` global.
double amountOverPeriod(double amount, int fromDays, int toDays) {
  if (fromDays <= 0 || toDays <= 0) return amount;
  if (fromDays == toDays) return amount;
  return amount / fromDays * toDays;
}

/// How many days the budget's current period spans.
int budgetPeriodDays(Budget budget, {DateTime? asOf}) {
  final DateTimeRange range = getBudgetDate(budget, asOf ?? DateTime.now());
  return range.end.difference(range.start).inDays;
}

/// One main category whose subcategory budgets have been measured against its
/// envelope.
class SubCategoryAllocation {
  const SubCategoryAllocation({
    required this.envelope,
    required this.envelopeAmount,
    required this.allocated,
    required this.hiddenAllocated,
    required this.hiddenCount,
  });

  /// The main category's own envelope budget. Its name is the category's name.
  final Budget envelope;

  /// The envelope's target, in the primary currency.
  final double envelopeAmount;

  /// Everything committed to this category's subcategories, in the primary
  /// currency and converted to the envelope's period. Includes [hiddenAllocated].
  final double allocated;

  /// The part of [allocated] that belongs to other household members and is
  /// not drawn anywhere on this device except the manage-budgets screen.
  final double hiddenAllocated;

  /// How many budgets make up [hiddenAllocated].
  final int hiddenCount;

  bool get isOver => allocated > envelopeAmount;

  /// How much more is committed than the envelope holds. Zero when it fits.
  double get excess => isOver ? allocated - envelopeAmount : 0;

  bool get hasHidden => hiddenCount > 0;
}

/// Measures every main category that has an envelope and at least one
/// subcategory budget.
///
/// Expenses only. The point is not over-committing money, and an income
/// category's "you have planned more than the target" reads as good news
/// rather than a warning.
List<SubCategoryAllocation> subCategoryAllocations(
  PlannedBudgetTotals totals,
  AllWallets allWallets, {
  DateTime? asOf,
}) {
  final Map<String, Budget> envelopeByCategoryPk = {};
  final Map<String, List<Budget>> subBudgetsByMainCategoryPk = {};

  for (Budget budget in totals.budgets) {
    // watchPlannedBudgetTotals already hides archived budgets; belt and braces
    // for the one-shot path and for anything that builds totals by hand.
    if (budget.archived || budget.income) continue;
    final List<String>? categoryFks = budget.categoryFks;
    // A budget spanning several categories, or none, cannot be attributed to
    // one parent, so it is left out rather than guessed at.
    if (categoryFks == null || categoryFks.length != 1) continue;

    if (totals.isMainCategoryBudget(budget)) {
      envelopeByCategoryPk[categoryFks.first] = budget;
      continue;
    }
    final String? mainCategoryPk =
        totals.mainCategoryOfSubCategory(categoryFks.first);
    if (mainCategoryPk == null) continue;
    subBudgetsByMainCategoryPk
        .putIfAbsent(mainCategoryPk, () => [])
        .add(budget);
  }

  final List<SubCategoryAllocation> allocations = [];
  envelopeByCategoryPk.forEach((String categoryPk, Budget envelope) {
    final List<Budget> subBudgets =
        subBudgetsByMainCategoryPk[categoryPk] ?? const [];
    if (subBudgets.isEmpty) return;

    final int envelopeDays = budgetPeriodDays(envelope, asOf: asOf);
    double allocated = 0;
    double hiddenAllocated = 0;
    int hiddenCount = 0;

    for (Budget subBudget in subBudgets) {
      final double amount = amountOverPeriod(
        budgetAmountToPrimaryCurrency(allWallets, subBudget),
        budgetPeriodDays(subBudget, asOf: asOf),
        envelopeDays,
      );
      allocated += amount;
      if (isOtherMembersBudget(subBudget)) {
        hiddenAllocated += amount;
        hiddenCount++;
      }
    }

    allocations.add(SubCategoryAllocation(
      envelope: envelope,
      envelopeAmount: budgetAmountToPrimaryCurrency(allWallets, envelope),
      allocated: allocated,
      hiddenAllocated: hiddenAllocated,
      hiddenCount: hiddenCount,
    ));
  });

  return allocations;
}

/// Just the main categories that are over-committed, worst first.
List<SubCategoryAllocation> overAllocatedMainCategories(
  PlannedBudgetTotals totals,
  AllWallets allWallets, {
  DateTime? asOf,
}) {
  final List<SubCategoryAllocation> over =
      subCategoryAllocations(totals, allWallets, asOf: asOf)
          .where((SubCategoryAllocation a) => a.isOver)
          .toList();
  over.sort((a, b) => b.excess.compareTo(a.excess));
  return over;
}

/// The allocation for one main category, or null when it has no envelope or no
/// subcategory budgets. Used after an amount is edited, to re-check just the
/// category that was touched.
SubCategoryAllocation? allocationForMainCategory(
  PlannedBudgetTotals totals,
  AllWallets allWallets,
  String mainCategoryPk, {
  DateTime? asOf,
}) {
  for (SubCategoryAllocation allocation
      in subCategoryAllocations(totals, allWallets, asOf: asOf)) {
    if (allocation.envelope.categoryFks?.first == mainCategoryPk) {
      return allocation;
    }
  }
  return null;
}

/// Raises the main category's envelope so the subcategory budgets fit exactly.
///
/// Written through [withUpdatedAmountHistory], the only sanctioned way to
/// change a budget's amount: setting `amount` directly would retroactively
/// rewrite what every finished period is measured against, which is the whole
/// thing BL-006 exists to prevent.
Future<void> raiseEnvelopeToFitAllocation(
  SubCategoryAllocation allocation,
  AllWallets allWallets,
) async {
  final Budget previous =
      await database.getBudgetInstance(allocation.envelope.budgetPk);
  // allocated is in the primary currency; the envelope stores its amount in
  // its own wallet's currency, so convert back rather than writing a number
  // from a different currency into it.
  final double ratio =
      amountRatioToPrimaryCurrencyGivenPk(allWallets, previous.walletFk);
  final double newAmount =
      ratio == 0 ? allocation.allocated : allocation.allocated / ratio;
  await database.createOrUpdateBudget(withUpdatedAmountHistory(
    previous: previous,
    updated: previous.copyWith(amount: newAmount),
  ));
}
