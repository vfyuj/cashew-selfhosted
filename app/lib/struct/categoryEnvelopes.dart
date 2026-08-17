import 'package:cashew_selfhosted/database/tables.dart';

// Envelopes: how much a category is meant to get in a given month.
//
// The storage is the fork-owned CategoryEnvelopes table (see tables.dart). This
// file holds everything about envelopes that is a decision rather than a query,
// so it can be tested without a database.
//
// Three rules the previous, budget-based implementation got wrong and this one
// deliberately keeps out of the data:
//
//   * Income or expense is NOT stored. It is read from Categories.income, so
//     the two can never disagree.
//   * A month with no row of its own is not empty and is not created in the
//     background: it resolves to the nearest earlier month that does have one.
//     Open a month you have never opened and it already shows last month's
//     plan, without writing anything.
//   * There is nothing to reconcile. No envelope is ever auto-created, so
//     nothing has to be de-duplicated, repaired or forced back into agreement.

/// The system-reserved balance-correction / transfer category (the "0" note in
/// defaultCategories.dart). It is created programmatically with a fixed pk by
/// initializeBalanceCorrectionCategory() in addWalletPage.dart, so matching on
/// the pk - unlike matching on a name - keeps working for a backup restored
/// from a non-English original-Cashew install. The same category stands in for
/// account-to-account transfers. Neither a correction nor a transfer is planned
/// spending, so it never gets an envelope.
const String balanceCorrectionCategoryPk = "0";

/// Whether [category] can have an envelope at all: main categories only, and
/// never the balance-correction category.
bool isEnvelopeEligible(TransactionCategory category) =>
    category.mainCategoryPk == null &&
    category.categoryPk != balanceCorrectionCategoryPk;

/// The month [date] falls in, as its first day at midnight.
DateTime envelopePeriodStart(DateTime date) =>
    DateTime(date.year, date.month, 1);

/// The primary key of [categoryPk]'s envelope for the month starting at
/// [periodStart].
///
/// Deterministic, so two devices setting an amount for the same category and
/// month write the same row instead of two rows that both count.
String envelopePkFor(String categoryPk, DateTime periodStart) {
  final DateTime month = envelopePeriodStart(periodStart);
  final String monthPadded = month.month.toString().padLeft(2, '0');
  return "$categoryPk:${month.year}-$monthPadded";
}

/// A brand new envelope row for [categoryPk]'s [periodStart] month.
CategoryEnvelope newCategoryEnvelope({
  required String categoryPk,
  required DateTime periodStart,
  required double amount,
}) {
  final DateTime month = envelopePeriodStart(periodStart);
  return CategoryEnvelope(
    envelopePk: envelopePkFor(categoryPk, month),
    categoryFk: categoryPk,
    periodStart: month,
    amount: amount,
    dateTimeModified: null,
  );
}

/// The amount that applies to [periodStart], given every envelope row of one
/// category, or null when that category has no plan yet.
///
/// Carrying the nearest earlier month forward is what makes "same amount every
/// month" cost one row instead of one row per month, and it is resolved here at
/// read time rather than by a background job writing rows for months nobody has
/// looked at. A later row never applies to an earlier month, so opening
/// February after setting March's amount still shows February's own.
double? envelopeAmountForPeriodStart(
    List<CategoryEnvelope> envelopesOfCategory, DateTime periodStart) {
  final DateTime month = envelopePeriodStart(periodStart);
  double? resolved;
  DateTime? resolvedFrom;
  for (CategoryEnvelope envelope in envelopesOfCategory) {
    final DateTime from = envelopePeriodStart(envelope.periodStart);
    if (from.isAfter(month)) continue;
    if (resolvedFrom == null || from.isAfter(resolvedFrom)) {
      resolved = envelope.amount;
      resolvedFrom = from;
    }
  }
  return resolved;
}

/// Every envelope, indexed by category, plus the categories they belong to.
///
/// One snapshot shared by every widget that needs a planned figure, so a screen
/// full of envelope rows is two database reads rather than two per row.
class EnvelopePlan {
  const EnvelopePlan({
    required this.categories,
    required this.envelopesByCategoryPk,
  });

  /// Envelope-eligible main categories, in the order the query returned them.
  final List<TransactionCategory> categories;
  final Map<String, List<CategoryEnvelope>> envelopesByCategoryPk;

  static const EnvelopePlan empty = EnvelopePlan(
    categories: <TransactionCategory>[],
    envelopesByCategoryPk: <String, List<CategoryEnvelope>>{},
  );

  /// The plan for one category and month, or null when it has never been set.
  double? amountFor(String categoryPk, DateTime periodStart) =>
      envelopeAmountForPeriodStart(
          envelopesByCategoryPk[categoryPk] ?? const <CategoryEnvelope>[],
          periodStart);

  /// The row actually stored for that month, if any. Null means the amount on
  /// screen was carried forward from an earlier month.
  CategoryEnvelope? storedEnvelopeFor(String categoryPk, DateTime periodStart) {
    final String pk = envelopePkFor(categoryPk, periodStart);
    for (CategoryEnvelope envelope
        in envelopesByCategoryPk[categoryPk] ?? const <CategoryEnvelope>[]) {
      if (envelope.envelopePk == pk) return envelope;
    }
    return null;
  }

  List<TransactionCategory> categoriesOfType({required bool income}) =>
      categories
          .where((TransactionCategory category) => category.income == income)
          .toList();

  /// Everything planned for one month on one side of the ledger. Income or
  /// expense comes from the category, which is the only place it is recorded.
  double totalPlanned({required bool income, required DateTime periodStart}) {
    double total = 0;
    for (TransactionCategory category in categoriesOfType(income: income)) {
      total += amountFor(category.categoryPk, periodStart) ?? 0;
    }
    return total;
  }
}

/// Groups envelopes under the categories that can have one.
///
/// Pure, and the only place the two halves are put together: widgets/
/// envelopePlanBuilder.dart feeds it two live queries, tests feed it lists.
EnvelopePlan buildEnvelopePlan(
    List<TransactionCategory> categories, List<CategoryEnvelope> envelopes) {
  final List<TransactionCategory> eligible =
      categories.where(isEnvelopeEligible).toList();
  final Set<String> eligiblePks = {
    for (TransactionCategory category in eligible) category.categoryPk
  };
  final Map<String, List<CategoryEnvelope>> byCategory = {};
  for (CategoryEnvelope envelope in envelopes) {
    // A row whose category is gone or is not eligible is ignored rather than
    // deleted: it may simply be a category that has not arrived over sync yet
    // (specs/01-local-first-invariant.md).
    if (!eligiblePks.contains(envelope.categoryFk)) continue;
    byCategory.putIfAbsent(envelope.categoryFk, () => []).add(envelope);
  }
  return EnvelopePlan(
      categories: eligible, envelopesByCategoryPk: byCategory);
}
