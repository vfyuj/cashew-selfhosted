import 'dart:async';

import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/currencyFunctions.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';

// Budgets that are "locked" to a single main category.
//
// This is derived, never stored. A budget belongs to a main category when it
// targets exactly one category and that category is a main category. Keeping it
// derived is what lets this feature ship without touching the Drift schema,
// which has to stay identical to upstream Cashew's (see CLAUDE.md).
class PlannedBudgetTotals {
  const PlannedBudgetTotals({
    required this.budgets,
    required this.mainCategoryPks,
    this.subCategoryParents = const <String, String>{},
  });

  final List<Budget> budgets;
  final Set<String> mainCategoryPks;

  // subcategory pk -> the main category it belongs under. Carried here so the
  // over-allocation check in struct/subCategoryBudgetAllocation.dart can group
  // budgets by parent without opening its own subscription; this snapshot
  // already holds every budget and is already cached app wide.
  final Map<String, String> subCategoryParents;

  static const PlannedBudgetTotals empty = PlannedBudgetTotals(
    budgets: const [],
    mainCategoryPks: const <String>{},
  );

  bool isMainCategoryBudget(Budget budget) {
    final List<String>? categoryFks = budget.categoryFks;
    if (categoryFks == null || categoryFks.length != 1) return false;
    return mainCategoryPks.contains(categoryFks.first);
  }

  // The main category a subcategory sits under, or null if it isn't a
  // subcategory of one that has an envelope.
  String? mainCategoryOfSubCategory(String categoryPk) =>
      subCategoryParents[categoryPk];

  // Denominator of the share label on the budget card.
  double totalPlannedExpenses(AllWallets allWallets) {
    double total = 0;
    for (Budget budget in budgets) {
      if (budget.income == false && isMainCategoryBudget(budget)) {
        total += budgetAmountToPrimaryCurrency(allWallets, budget);
      }
    }
    return total;
  }

  // What "% of planned income" is a percentage of. Every income budget counts,
  // main category or not, so a single catch-all income budget still works.
  double totalPlannedIncome(AllWallets allWallets) {
    double total = 0;
    for (Budget budget in budgets) {
      if (budget.income == true) {
        total += budgetAmountToPrimaryCurrency(allWallets, budget);
      }
    }
    return total;
  }

  // The budget's share of all planned main category expenses, or null when
  // there is nothing meaningful to show.
  double? sharePercentOfPlannedExpenses(AllWallets allWallets, Budget budget) {
    if (budget.income == true) return null;
    if (isMainCategoryBudget(budget) == false) return null;
    final double total = totalPlannedExpenses(allWallets);
    if (total <= 0) return null;
    return budgetAmountToPrimaryCurrency(allWallets, budget) / total * 100;
  }
}

// The system-reserved wallet/account-correction category (see the "0" note
// in defaultCategories.dart). It is created programmatically by
// initializeBalanceCorrectionCategory() in addWalletPage.dart with a fixed
// pk rather than picked from defaultCategories, so checking the pk - unlike
// matching on a category's name - keeps working for a backup restored from
// a non-English original-Cashew install, where every other default category
// name is translated but this one is generated with a hardcoded pk. The same
// category also stands in for account-to-account transfers
// (createCorrectionTransaction is used by both). Neither a correction nor a
// transfer is a planned expense or income, so this category never gets an
// envelope.
const String _balanceCorrectionCategoryPk = "0";

bool _isEnvelopeEligible(TransactionCategory category) =>
    category.categoryPk != _balanceCorrectionCategoryPk;

StreamController<PlannedBudgetTotals>? _totalsController;
PlannedBudgetTotals? _latestPlannedBudgetTotals;

// The most recent totals, for use as StreamBuilder initialData so a card that
// mounts after the first emit doesn't flash without its label.
PlannedBudgetTotals? get latestPlannedBudgetTotals =>
    _latestPlannedBudgetTotals;

// Cached app wide so every budget card on screen shares one pair of database
// reads instead of opening its own. The underlying subscription is deliberately
// never cancelled - it lives as long as the app does.
Stream<PlannedBudgetTotals> watchPlannedBudgetTotals() {
  if (_totalsController == null) {
    _totalsController = StreamController<PlannedBudgetTotals>.broadcast();
    database
        .watchAllBudgets(hideArchived: true)
        .listen((List<Budget> budgets) async {
      _totalsController?.add(await _totalsForBudgets(budgets));
    });
  }
  return _totalsController!.stream;
}

// One shot version, for code that needs the totals outside a widget tree.
Future<PlannedBudgetTotals> getPlannedBudgetTotals() async {
  final List<Budget> budgets = await database.getAllBudgets();
  return _totalsForBudgets(
      budgets.where((Budget budget) => budget.archived == false).toList());
}

// Every main category gets exactly one budget - its envelope. A newly
// auto-created envelope's pk is the category's pk, which is what makes
// concurrent devices converge on one row instead of each generating its own
// uuid and silently doubling the planned totals once they sync. But a
// category can already have a dedicated budget predating this feature -
// created by hand, with whatever uuid it was given at the time - and that one
// is adopted as-is rather than duplicated. "Has an envelope" is therefore
// judged the same way isMainCategoryBudget is: by categoryFks, not by pk.
//
// This reconciles rather than hooking category creation, which buys three
// things for the same code: it is idempotent, it picks up categories that
// arrived over sync rather than being created here, and it doubles as the one
// time backfill for categories that predate the feature. A category budget
// deleted by hand comes back on the next reconcile, which is the intended
// behaviour for an envelope system where every category has a budget.
Future<int> ensureMainCategoryBudgetsExist() async {
  final List<TransactionCategory> mainCategories =
      await database.getAllCategories(includeSubCategories: false);
  final List<Budget> allBudgets = await database.getAllBudgets();

  final Map<String, List<Budget>> envelopesByCategoryPk = {};
  for (Budget budget in allBudgets) {
    final List<String>? categoryFks = budget.categoryFks;
    if (categoryFks == null || categoryFks.length != 1) continue;
    envelopesByCategoryPk.putIfAbsent(categoryFks.first, () => []).add(budget);
  }

  int createdCount = 0;
  for (TransactionCategory category in mainCategories) {
    final List<Budget> envelopes =
        envelopesByCategoryPk[category.categoryPk] ?? [];

    if (!_isEnvelopeEligible(category)) {
      // Remove an envelope this function itself created before the category
      // was excluded, identified the same way the duplicate cleanup below
      // identifies one: budgetPk == categoryPk. A hand-made budget that
      // happens to target only this category is left alone - it simply stops
      // counting as a main-category envelope (see isMainCategoryBudget) and
      // falls back to the Custom tab.
      for (Budget envelope in envelopes) {
        if (envelope.budgetPk == category.categoryPk) {
          await database.deleteBudget(null, envelope);
        }
      }
      continue;
    }

    if (envelopes.length > 1) {
      // A duplicate left over from before this function recognised a
      // hand-made budget as already covering the category, and created a
      // second, auto-created one alongside it (auto-created envelopes are
      // always keyed budgetPk == categoryPk, so a stray one from that bug is
      // identifiable on sight). Clean it up: keep whichever envelope predates
      // this feature; only if every envelope for this category happens to be
      // auto-created (impossible in practice, since budgetPk is the primary
      // key and only one row can hold a given pk) fall back to keeping the
      // oldest.
      final List<Budget> handMade = envelopes
          .where((Budget budget) => budget.budgetPk != category.categoryPk)
          .toList();
      final List<Budget> redundant = handMade.isNotEmpty
          ? envelopes
              .where((Budget budget) => budget.budgetPk == category.categoryPk)
              .toList()
          : (List<Budget>.from(envelopes)
                ..sort((a, b) => a.dateCreated.compareTo(b.dateCreated)))
              .sublist(1);
      for (Budget duplicate in redundant) {
        // deleteBudget's context parameter goes unused for a budget that was
        // never shared and has no added/excluded transactions - both true for
        // anything this function itself created.
        await database.deleteBudget(null, duplicate);
      }
      continue;
    }

    if (envelopes.isNotEmpty) {
      // The envelope already exists - but its income/expense flag has to
      // keep tracking the category's, not just start out matching it at
      // creation. Without this, editing a category's type after its envelope
      // already exists (or reconciliation adopting a pre-existing hand-made
      // budget whose income flag disagreed with the category) leaves the
      // envelope permanently mis-sorted between the Main Categories tab's
      // Income and Expense sections - and its "actual spent" query silently
      // wrong, since that query filters transactions by the budget's own
      // income flag, not the category's.
      final Budget envelope = envelopes.single;
      if (envelope.income != category.income) {
        await database.createOrUpdateBudget(
          envelope.copyWith(income: category.income),
        );
      }
      continue;
    }

    await database.createOrUpdateBudget(
      budgetForMainCategory(category),
      // Never route an auto created budget through the shared/Firestore branch
      // of createOrUpdateBudget - it is dead in this fork.
      //
      // Stamped at the epoch so it always loses last-write-wins, the same
      // reason initializeDefaultDatabase does it for the default wallet and
      // categories. This runs before the first sync of a launch, so a device
      // that has just signed in to an account which already has data creates
      // its own amount: 0 envelopes for any category it shares a pk with -
      // the default categories "1".."11" - before hearing about the real ones.
      // Stamped "now" those zeroes would win the merge and wipe both the
      // household's targets and the per-period history in
      // Budgets.sharedAllMembersEver. Every real edit still stamps now via
      // createOrUpdateBudget's default. Two devices independently creating the
      // same envelope at the epoch is a no-op, not a conflict.
      customDateTimeModified: DateTime(0),
    );
    createdCount++;
  }
  return createdCount;
}

// The envelope a main category starts life with: same name and colour as the
// category, no target yet, one calendar month, ordered to mirror the category
// list rather than piling up at the end of the budgets list.
Budget budgetForMainCategory(TransactionCategory category) {
  return Budget(
    budgetPk: category.categoryPk,
    name: category.name,
    amount: 0,
    colour: category.colour,
    startDate: DateTime.now().firstDayOfMonth(),
    endDate: DateTime.now(),
    categoryFks: [category.categoryPk],
    categoryFksExclude: null,
    income: category.income,
    archived: false,
    addedTransactionsOnly: false,
    periodLength: 1,
    reoccurrence: BudgetReoccurence.monthly,
    dateCreated: DateTime.now(),
    dateTimeModified: null,
    pinned: false,
    order: category.order,
    walletFk: appStateSettings["selectedWalletPk"],
    isAbsoluteSpendingLimit: false,
  );
}

Future<PlannedBudgetTotals> _totalsForBudgets(List<Budget> budgets) async {
  final List<TransactionCategory> allCategories =
      await database.getAllCategories(includeSubCategories: true);
  final Set<String> mainCategoryPks = {
    for (TransactionCategory category in allCategories)
      if (category.mainCategoryPk == null && _isEnvelopeEligible(category))
        category.categoryPk
  };
  final PlannedBudgetTotals totals = PlannedBudgetTotals(
    budgets: budgets,
    mainCategoryPks: mainCategoryPks,
    // Only parents that are themselves envelope-eligible: a subcategory of the
    // excluded correction category has no envelope to be measured against.
    subCategoryParents: {
      for (TransactionCategory category in allCategories)
        if (category.mainCategoryPk != null &&
            mainCategoryPks.contains(category.mainCategoryPk))
          category.categoryPk: category.mainCategoryPk!
    },
  );
  _latestPlannedBudgetTotals = totals;
  return totals;
}
