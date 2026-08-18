import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/currencyFunctions.dart';

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
///
/// [walletPk] is the account whose currency [amount] is counted in - normally
/// the primary account, since that is the currency the number pad was showing.
/// Required rather than defaulted: an envelope with the wrong account behind it
/// is a plan that silently means something else, and there is no answer that is
/// right for every caller.
CategoryEnvelope newCategoryEnvelope({
  required String categoryPk,
  required DateTime periodStart,
  required double amount,
  required String walletPk,
}) {
  final DateTime month = envelopePeriodStart(periodStart);
  return CategoryEnvelope(
    envelopePk: envelopePkFor(categoryPk, month),
    categoryFk: categoryPk,
    periodStart: month,
    amount: amount,
    dateTimeModified: null,
    walletFk: walletPk,
  );
}

/// The envelope row that applies to [periodStart], given every row of one
/// category, or null when that category has no plan yet.
///
/// Carrying the nearest earlier month forward is what makes "same amount every
/// month" cost one row instead of one row per month, and it is resolved here at
/// read time rather than by a background job writing rows for months nobody has
/// looked at. A later row never applies to an earlier month, so opening
/// February after setting March's amount still shows February's own.
CategoryEnvelope? envelopeForPeriodStart(
    List<CategoryEnvelope> envelopesOfCategory, DateTime periodStart) {
  final DateTime month = envelopePeriodStart(periodStart);
  CategoryEnvelope? resolved;
  DateTime? resolvedFrom;
  for (CategoryEnvelope envelope in envelopesOfCategory) {
    final DateTime from = envelopePeriodStart(envelope.periodStart);
    if (from.isAfter(month)) continue;
    if (resolvedFrom == null || from.isAfter(resolvedFrom)) {
      resolved = envelope;
      resolvedFrom = from;
    }
  }
  return resolved;
}

/// The stored amount that applies to [periodStart]. **In the row's own
/// account's currency**, not necessarily the primary one - see [EnvelopePlan].
double? envelopeAmountForPeriodStart(
        List<CategoryEnvelope> envelopesOfCategory, DateTime periodStart) =>
    envelopeForPeriodStart(envelopesOfCategory, periodStart)?.amount;

/// Every envelope, indexed by category, plus the categories they belong to.
///
/// One snapshot shared by every widget that needs a planned figure, so a screen
/// full of envelope rows is two database reads rather than two per row.
///
/// **Every amount this hands out is in the primary account's currency**, the
/// one everything else on screen is counted in. Each row carries the account
/// its number was typed in ([CategoryEnvelope.walletFk]) and [allWallets] is
/// what converts it, so switching the primary account to another currency moves
/// the plan with the spending instead of leaving a ruble figure wearing a
/// dollar sign. Read [resolvedEnvelopeFor] instead when you need the number as
/// stored - the amount sheet does, because that is what it puts on the pad.
class EnvelopePlan {
  const EnvelopePlan({
    required this.categories,
    required this.envelopesByCategoryPk,
    this.allWallets,
  });

  /// Envelope-eligible main categories, in the order the query returned them.
  final List<TransactionCategory> categories;
  final Map<String, List<CategoryEnvelope>> envelopesByCategoryPk;

  /// The accounts, for converting each row into the primary currency. Null only
  /// where there is no such thing - the pure tests in
  /// test/category_envelopes_test.dart - and amounts then come back as stored.
  final AllWallets? allWallets;

  static const EnvelopePlan empty = EnvelopePlan(
    categories: <TransactionCategory>[],
    envelopesByCategoryPk: <String, List<CategoryEnvelope>>{},
  );

  /// The plan for one category and month **in the primary currency**, or null
  /// when it has never been set.
  double? amountFor(String categoryPk, DateTime periodStart) {
    final CategoryEnvelope? envelope =
        resolvedEnvelopeFor(categoryPk, periodStart);
    if (envelope == null) return null;
    if (allWallets == null) return envelope.amount;
    return envelopeAmountToPrimaryCurrency(allWallets!, envelope);
  }

  /// The row that applies to that month, as stored - its own amount, in its own
  /// account's currency. The month it came from may be an earlier one.
  CategoryEnvelope? resolvedEnvelopeFor(
          String categoryPk, DateTime periodStart) =>
      envelopeForPeriodStart(
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

  /// Everything planned for one month on one side of the ledger, in the primary
  /// currency. Income or expense comes from the category, which is the only
  /// place it is recorded.
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
/// envelopePlanBuilder.dart feeds it two live queries and the accounts, tests
/// feed it lists.
EnvelopePlan buildEnvelopePlan(
    List<TransactionCategory> categories, List<CategoryEnvelope> envelopes,
    {AllWallets? allWallets}) {
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
      categories: eligible,
      envelopesByCategoryPk: byCategory,
      allWallets: allWallets);
}
