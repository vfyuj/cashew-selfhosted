import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addBudgetPage.dart' show ColumnSliver;
import 'package:cashew_selfhosted/pages/envelopesPage.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/widgets/budgetContainer.dart'
    show BudgetProgress;
import 'package:cashew_selfhosted/widgets/categoryIcon.dart';
import 'package:cashew_selfhosted/widgets/envelopePlanBuilder.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/sliverStickyLabelDivider.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/transactionEntries.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// One envelope, one month: what was planned, what was spent, where it went and
// which transactions it was.
//
// Everything on this page is a read of data that already exists -- the same
// queries the budget page uses, pointed at one main category and one calendar
// month. The envelope contributes only the planned amount at the top.
class EnvelopeDetailsPage extends StatefulWidget {
  const EnvelopeDetailsPage({
    required this.category,
    required this.month,
    super.key,
  });

  final TransactionCategory category;
  final DateTime month;

  @override
  State<EnvelopeDetailsPage> createState() => _EnvelopeDetailsPageState();
}

class _EnvelopeDetailsPageState extends State<EnvelopeDetailsPage> {
  DateTimeRange get monthRange => DateTimeRange(
        start: widget.month,
        end: DateTime(widget.month.year, widget.month.month + 1, 0),
      );

  // One subscription for the page: the header and the breakdown are two views
  // of the same numbers, and creating the stream in build() would resubscribe
  // on every scroll frame. Rebuilt when the account set changes, because the
  // query spans every wallet and converts each one to the primary currency.
  Stream<List<CategoryWithTotal>>? _totals;
  AllWallets? _totalsForWallets;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    if (_totals != null && _totalsForWallets == allWallets) return;
    _totalsForWallets = allWallets;
    _totals = _watchTotalsBySubCategory(allWallets);
  }

  @override
  Widget build(BuildContext context) {
    final Color categoryColor = HexColor(widget.category.colour,
        defaultColor: Theme.of(context).colorScheme.primary);
    final String listID = "envelope-${widget.category.categoryPk}-"
        "${envelopePkFor(widget.category.categoryPk, widget.month)}";

    return PageFramework(
      dragDownToDismiss: true,
      title: widget.category.name,
      subtitle: TextFont(
        text: getMonth(widget.month, includeYear: true),
        fontSize: 15,
        textColor: getColor(context, "textLight"),
      ),
      slivers: [
        // The card again, so the number you came here to understand is still on
        // screen, and still tappable to change.
        SliverToBoxAdapter(
          child: EnvelopePlanBuilder(
            builder: (context, plan) {
              return StreamBuilder<List<CategoryWithTotal>>(
                stream: _totals,
                builder: (context, snapshot) {
                  return _Header(
                    category: widget.category,
                    month: widget.month,
                    plan: plan,
                    spent: _spentTotal(snapshot.data ?? []),
                    color: categoryColor,
                  );
                },
              );
            },
          ),
        ),

        // Where the money went inside the category. Only drawn when the
        // category actually has subcategories -- one row saying "everything
        // went to the category itself" is noise.
        StreamBuilder<List<CategoryWithTotal>>(
          stream: _totals,
          builder: (context, snapshot) {
            final List<CategoryWithTotal> totals = (snapshot.data ?? [])
                .where((entry) => entry.total != 0)
                .toList()
              ..sort((a, b) => b.total.abs().compareTo(a.total.abs()));
            if (totals.length <= 1) return SliverToBoxAdapter();

            final double spent = _spentTotal(totals);
            return SliverStickyLabelDivider(
              info: "subcategories".tr(),
              extraInfo: convertToMoney(
                  Provider.of<AllWallets>(context), spent),
              sliver: ColumnSliver(
                children: [
                  SizedBox(height: 5),
                  for (CategoryWithTotal entry in totals)
                    _SubCategoryRow(
                      key: ValueKey(entry.category.categoryPk),
                      entry: entry,
                      // Its share of what this category spent, so the rows add
                      // up to 100% rather than to the envelope. Signed the same
                      // way the amount beside it is: expenses are stored
                      // negative and income positive, so flipping
                      // unconditionally made every income envelope's rows read
                      // as negative percentages.
                      percent: spent == 0
                          ? 0
                          : (entry.total * (widget.category.income ? 1 : -1)) /
                              spent *
                              100,
                      mainCategory: widget.category,
                    ),
                  SizedBox(height: 5),
                ],
              ),
            );
          },
        ),

        SliverStickyLabelDivider(
            info: "transactions".tr(), sliver: SliverToBoxAdapter()),
        // The month's transactions in this category, drawn by the same widget
        // the transaction list and the budget page use, so selecting, editing
        // and swiping all behave exactly as they do everywhere else.
        TransactionEntries(
          monthRange.start,
          monthRange.end,
          categoryFks: [widget.category.categoryPk],
          listID: listID,
          useHorizontalPaddingConstrained: false,
        ),
        SliverToBoxAdapter(child: SizedBox(height: 50)),
      ],
    );
  }

  // One row per subcategory, plus one row for the transactions filed straight
  // under the category itself.
  //
  // `includeAllSubCategories: true` with `countUnassignedTransactions: false`
  // is the combination that partitions rather than overlaps: a transaction with
  // a subcategory joins only its subcategory, and one without joins only the
  // main category (`subCategoryFk IS NULL`). Setting countUnassigned to true
  // instead makes the main category match *every* transaction as well, and the
  // page then reports exactly double what was spent -- which is what the first
  // version of this did.
  //
  // `isIncome` matters as much: it is what the envelopes list filters its own
  // "spent" by, and leaving it off here netted a refund off the total on this
  // page while the card that opened it still counted the full amount. Two
  // numbers for one month is worse than either of them being arguable.
  Stream<List<CategoryWithTotal>> _watchTotalsBySubCategory(
      AllWallets allWallets) {
    return database.watchTotalSpentInEachCategoryInTimeRangeFromCategories(
      allWallets: allWallets,
      start: monthRange.start,
      end: monthRange.end,
      categoryFks: [widget.category.categoryPk],
      categoryFksExclude: null,
      budgetTransactionFilters: null,
      memberTransactionFilters: null,
      isIncome: widget.category.income,
      includeAllSubCategories: true,
      countUnassignedTransactions: false,
    );
  }

  // Expenses are stored signed negative (determineBudgetPolarity), so an
  // expense category reads positive here and a month of refunds reads negative.
  double _spentTotal(List<CategoryWithTotal> totals) {
    double total = 0;
    for (CategoryWithTotal entry in totals) {
      total += entry.total;
    }
    return widget.category.income ? total : -total;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.category,
    required this.month,
    required this.plan,
    required this.spent,
    required this.color,
  });

  final TransactionCategory category;
  final DateTime month;
  final EnvelopePlan plan;
  final double spent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final double? amount = plan.amountFor(category.categoryPk, month);
    final double amountOrZero = amount ?? 0;
    final double remaining = amountOrZero - spent;
    final DateTime now = DateTime.now();
    final bool isCurrentMonth =
        month.year == now.year && month.month == now.month;

    return Padding(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 13, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
              getPlatform() == PlatformOS.isIOS ? 14 : 20),
          boxShadow: boxShadowCheck([
            BoxShadow(
              color: color.withOpacity(
                  Theme.of(context).brightness == Brightness.light ? 0.4 : 0.5),
              blurRadius: 15,
              spreadRadius: -4,
              offset: Offset(0, 5),
            ),
          ]),
        ),
        child: Tappable(
          color: getColor(context, "lightDarkAccentHeavyLight"),
          borderRadius: getPlatform() == PlatformOS.isIOS ? 14 : 20,
          onTap: () => enterEnvelopeAmountPopup(context, category, month, plan),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CategoryIcon(
                      category: category,
                      categoryPk: category.categoryPk,
                      size: 34,
                      sizePadding: 16,
                      margin: EdgeInsetsDirectional.zero,
                      canEditByLongPress: false,
                    ),
                    SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFont(
                            text: convertToMoney(allWallets, spent),
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            maxLines: 1,
                          ),
                          TextFont(
                            text: amount == null
                                ? envelopeActionWord(category.income)
                                : convertToMoney(allWallets, remaining.abs()) +
                                    " " +
                                    envelopeStatusWord(
                                      income: category.income,
                                      beyondPlan: remaining < 0,
                                    ).toLowerCase() +
                                    "  ·  " +
                                    convertToMoney(allWallets, amountOrZero) +
                                    " " +
                                    "planned".tr().toLowerCase(),
                            fontSize: 15,
                            maxLines: 2,
                            textColor: amount == null
                                ? getColor(context, "textLight")
                                : envelopeStatusColor(context,
                                    income: category.income,
                                    beyondPlan: remaining < 0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                BudgetProgress(
                  color: color,
                  percent:
                      amountOrZero <= 0 ? 0 : (spent / amountOrZero) * 100,
                  yourPercent: 0,
                  ghostPercent: 0,
                  todayPercent: isCurrentMonth
                      ? getPercentBetweenDates(
                          DateTimeRange(
                            start: month,
                            end: DateTime(month.year, month.month + 1, 0),
                          ),
                          now)
                      : -1,
                  showToday: isCurrentMonth,
                  large: true,
                  padding: EdgeInsetsDirectional.zero,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubCategoryRow extends StatelessWidget {
  const _SubCategoryRow({
    required this.entry,
    required this.percent,
    required this.mainCategory,
    super.key,
  });

  final CategoryWithTotal entry;
  final double percent;
  final TransactionCategory mainCategory;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final bool isTheCategoryItself =
        entry.category.categoryPk == mainCategory.categoryPk;
    return Padding(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 25, vertical: 6),
      child: Row(
        children: [
          CategoryIcon(
            category: entry.category,
            categoryPk: entry.category.categoryPk,
            size: 24,
            sizePadding: 12,
            margin: EdgeInsetsDirectional.zero,
            canEditByLongPress: false,
          ),
          SizedBox(width: 13),
          Expanded(
            child: TextFont(
              // A transaction filed straight under the main category has no
              // subcategory to name, so say that rather than repeating the
              // category's own name back at the reader.
              text: isTheCategoryItself
                  ? "no-subcategory".tr()
                  : entry.category.name,
              fontSize: 16,
              maxLines: 2,
            ),
          ),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextFont(
                text: convertToMoney(
                    allWallets, entry.total * (mainCategory.income ? 1 : -1)),
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              TextFont(
                text: convertToPercent(percent,
                    numberDecimals: 0, shouldRemoveTrailingZeroes: true),
                fontSize: 13,
                textColor: getColor(context, "textLight"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
