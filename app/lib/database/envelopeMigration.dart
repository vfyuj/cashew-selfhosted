import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:drift/drift.dart' show InsertMode, Value;

// Conversion from the envelopes-as-budgets implementation to the
// CategoryEnvelopes table.
//
// Until this release, a category's monthly plan was a Budget row locked to that
// one category, with its history of past amounts packed into the dead
// `Budgets.sharedAllMembersEver` column. Both are gone: budgets are plain
// upstream budgets again, and the plan lives in its own table.
//
// It converges across devices without any coordination: the envelope pk is
// derived from the category and the month, so two devices converting the same
// household's budgets write the same rows rather than duplicates.

/// `<periodStartEpochMillis>=<amount>`, e.g. "1751328000000=400.0".
///
/// Deliberately strict, and the reason is not tidiness: an original-Cashew
/// backup has real member ids in this column, and misreading one as an amount
/// would invent a plan the household never set. Anything that is not exactly
/// this shape is ignored.
final RegExp _amountHistoryEntry =
    RegExp(r'^(\d+)=(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)$');

/// One "from this month onward, the plan was this much" entry.
class LegacyAmountChange {
  const LegacyAmountChange({required this.from, required this.amount});

  final DateTime from;
  final double amount;
}

/// The amount history packed into [budget]'s dead `sharedAllMembersEver`
/// column, oldest first. Empty for a budget whose amount was never changed and
/// for one carrying upstream member ids.
List<LegacyAmountChange> legacyAmountHistory(Budget budget) {
  final List<LegacyAmountChange> changes = [];
  for (String entry in budget.sharedAllMembersEver ?? const []) {
    final RegExpMatch? match = _amountHistoryEntry.firstMatch(entry);
    if (match == null) continue;
    final int? millis = int.tryParse(match.group(1)!);
    final double? amount = double.tryParse(match.group(2)!);
    if (millis == null || amount == null) continue;
    changes.add(LegacyAmountChange(
      from: DateTime.fromMillisecondsSinceEpoch(millis),
      amount: amount,
    ));
  }
  changes.sort((a, b) => a.from.compareTo(b.from));
  return changes;
}

/// Whether [budget] is one of the envelopes the old implementation created for
/// itself.
///
/// **Identified by `budgetPk == categoryPk`, and only that.** That shape is not
/// something a budget can acquire by accident: `ensureMainCategoryBudgetsExist`
/// deliberately keyed every envelope it created by the category's own pk, while
/// every hand-made budget gets a uuid. So the test is a property of the row
/// rather than a guess about intent, which is what lets this run on every launch
/// instead of once — see [migrateEnvelopeBudgetsToCategoryEnvelopes].
///
/// A budget that merely *targets* one main category is deliberately NOT
/// converted. Under the old implementation such a budget could be adopted as a
/// category's envelope, but it is a budget somebody made by hand, it is a
/// perfectly ordinary upstream budget now, and deleting it would be the one
/// irreversible thing this conversion could do.
///
/// [mainCategoryPks] is every main category that exists **on this device**. A
/// budget whose category is not among them is left completely alone: the
/// category may simply not have arrived over sync yet, and converting on that
/// guess would delete the budget on every device
/// (specs/01-local-first-invariant.md). A later launch, once it has arrived,
/// converts it.
bool isLegacyEnvelopeBudget(Budget budget, Set<String> mainCategoryPks) {
  return mainCategoryPks.contains(budget.budgetPk);
}

/// Which category [budget]'s plan belongs to. Only meaningful for a budget
/// [isLegacyEnvelopeBudget] has already accepted.
///
/// Exactly one category is the shape the old implementation created and the
/// shape it recognised, so that one wins. Anything else - a budget somebody
/// widened to several categories after it was auto-created, or one whose
/// category list was lost - falls back to the pk, which
/// [isLegacyEnvelopeBudget] has already proven is a main category's. Reading
/// `categoryFks.single` here instead threw a StateError on a widened budget,
/// and took the rest of the app's startup down with it.
String legacyEnvelopeCategoryPk(Budget budget) {
  final List<String> categoryFks = budget.categoryFks ?? const [];
  return categoryFks.length == 1 ? categoryFks.first : budget.budgetPk;
}

/// The month a budget with no recorded history converts into.
///
/// The budget's own start, not "today". Two devices converting the same
/// household's budgets in different months would otherwise write two rows in
/// two months, and the plan would exist twice. The budget's start is a property
/// of the row, so both devices land on the same one - and it is also the truer
/// answer: the budget did apply from then, and carry-forward brings the amount
/// up to the present anyway.
///
/// Clamped to [now] because a budget's period can be edited by hand: a start
/// date in the future would put the plan in a month nothing reads back.
DateTime legacyBudgetMonth(Budget budget, DateTime now) {
  final DateTime start = envelopePeriodStart(budget.startDate);
  final DateTime current = envelopePeriodStart(now);
  return start.isAfter(current) ? current : start;
}

/// The envelope rows [budget]'s history and current amount become.
///
/// Pure, so the conversion can be tested without a database. [now] is the
/// upper bound for a budget with no recorded history - see [legacyBudgetMonth].
List<CategoryEnvelope> envelopesForLegacyBudget(
  Budget budget,
  String categoryPk, {
  required DateTime now,
}) {
  final List<LegacyAmountChange> history = legacyAmountHistory(budget);
  if (history.isEmpty) {
    // Nothing was ever planned here. Writing a zero row would claim the
    // household deliberately budgeted nothing this month, which is not the
    // same thing as never having filled it in.
    if (budget.amount == 0) return [];
    return [
      newCategoryEnvelope(
        categoryPk: categoryPk,
        periodStart: legacyBudgetMonth(budget, now),
        amount: budget.amount,
      )
    ];
  }
  // Keyed by month so two changes inside one month collapse to the last one,
  // exactly as the old format resolved them.
  final Map<String, CategoryEnvelope> byMonth = {};
  for (LegacyAmountChange change in history) {
    final CategoryEnvelope envelope = newCategoryEnvelope(
      categoryPk: categoryPk,
      periodStart: change.from,
      amount: change.amount,
    );
    byMonth[envelope.envelopePk] = envelope;
  }
  return byMonth.values.toList()
    ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
}

/// Converts whatever envelope budgets are in front of it, on every launch.
///
/// Deliberately **not** gated on a "this device has migrated" flag. A flag is a
/// statement about the device, and the data does not arrive with the device:
/// it arrives when a backup is imported, when the first sync pull lands, or
/// when a household member still on the old version recreates an envelope
/// budget. A device that had converted an empty database would then never look
/// again, and the household's envelopes would sit there as budgets forever.
///
/// Running every launch is safe because [isLegacyEnvelopeBudget] tests a
/// property of the row rather than a moment in time, and because envelope rows
/// are written insertOrIgnore. Once the conversion is done there is nothing
/// left that matches, so the steady-state cost is two queries.
Future<void> migrateEnvelopeBudgetsToCategoryEnvelopes() async {
  // Nothing in here may throw out of this function. It is awaited on the app's
  // startup path (initializeDefaultDatabase, called from navigationFramework's
  // initState), and everything after it in that chain - starting the first
  // sync - is skipped if it does. A conversion that cannot make progress has to
  // fail quietly and be retried next launch, per
  // specs/01-local-first-invariant.md.
  try {
    final Set<String> mainCategoryPks = {
      for (TransactionCategory category
          in await database.getAllCategories(includeSubCategories: false))
        if (isEnvelopeEligible(category)) category.categoryPk
    };
    final List<Budget> allBudgets = await database.getAllBudgets();
    final DateTime now = DateTime.now();

    for (Budget budget in allBudgets) {
      // Per budget as well as around the whole thing: one row the conversion
      // cannot make sense of must not stop the rest of the household's
      // envelopes from arriving.
      try {
        await _convertOneBudget(budget, mainCategoryPks, now);
      } catch (e) {
        print("Error converting budget " + budget.budgetPk + ": " +
            e.toString());
      }
    }
  } catch (e) {
    print("Error converting envelope budgets: " + e.toString());
  }
}

Future<void> _convertOneBudget(
  Budget budget,
  Set<String> mainCategoryPks,
  DateTime now,
) async {
  if (isLegacyEnvelopeBudget(budget, mainCategoryPks) == false) {
    // A plain budget. It stays exactly as it is, minus whatever the withdrawn
    // fork features left in the two dead columns - see the comment on them in
    // tables.dart. Clearing them needs release A's sync fix to reach the
    // other devices at all: an update carrying a null used to drop that
    // column from the statement entirely.
    if (budget.sharedMembers != null || budget.sharedAllMembersEver != null) {
      await database.createOrUpdateBudget(budget.copyWith(
        sharedMembers: const Value(null),
        sharedAllMembersEver: const Value(null),
      ));
    }
    return;
  }

  final String categoryPk = legacyEnvelopeCategoryPk(budget);
  for (CategoryEnvelope envelope
      in envelopesForLegacyBudget(budget, categoryPk, now: now)) {
    // insertOrIgnore: a device converting late must not overwrite an envelope
    // the household has already edited on the new version. The pk is derived
    // from the category and the month, so "already converted" is simply "the
    // row is there".
    await database.createOrUpdateCategoryEnvelope(
      envelope,
      mode: InsertMode.insertOrIgnore,
    );
  }
  // Writes a tombstone, which is what removes it from the other devices too.
  await database.deleteBudget(null, budget);
}
