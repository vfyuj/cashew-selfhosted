import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addCategoryPage.dart';
import 'package:cashew_selfhosted/pages/envelopesPage.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/struct/spendingSummaryHelper.dart';
import 'package:cashew_selfhosted/widgets/budgetContainer.dart'
    show BudgetProgress;
import 'package:cashew_selfhosted/widgets/categoryEntry.dart';
import 'package:cashew_selfhosted/widgets/swappableTotal.dart';
import 'package:cashew_selfhosted/widgets/dropdownSelect.dart';
import 'package:cashew_selfhosted/widgets/envelopePlanBuilder.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/navigationSidebar.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart'
    show getHorizontalPaddingConstrained;
import 'package:cashew_selfhosted/widgets/openPopup.dart'
    show RoutesToPopAfterDelete;
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
//
// It is also *shaped* like the budget page on purpose: the category's colour
// seeds the theme (CustomColorTheme), the figure and the progress bar sit in a
// block tinted with it, and the breakdown underneath is upstream's own
// CategoryEntry box rather than a hand-rolled list. What it deliberately does
// not borrow is the pie chart and the spending-over-time graph -- an envelope is
// one category for one month, and neither has anything to divide.
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
  DateTimeRange get monthRange => envelopeMonthRange(widget.month);

  // One subscription for the page: the header and the breakdown are two views
  // of the same numbers, and creating the stream in build() would resubscribe
  // on every scroll frame. Rebuilt when the account set changes, because the
  // query spans every wallet and converts each one to the primary currency.
  Stream<List<CategoryWithTotal>>? _totals;
  AllWallets? _totalsForWallets;

  /// The subcategory whose row was tapped, if any. Narrows the transaction list
  /// below, the same way selecting a slice does on the budget page.
  TransactionCategory? selectedCategory;

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

    // Reseeds the whole colour scheme from the category, so secondaryContainer
    // below is a tint of it rather than the app's accent. The Builder is what
    // puts the rest of the page underneath that Theme -- read it from this
    // context and you get the old scheme back.
    return CustomColorTheme(
      accentColor: categoryColor,
      child: Builder(
        builder: (context) => _buildPage(context, categoryColor),
      ),
    );
  }

  Widget _buildPage(BuildContext context, Color categoryColor) {
    final String listID = "envelope-${widget.category.categoryPk}-"
        "${envelopePkFor(widget.category.categoryPk, widget.month)}";
    final DateTime now = DateTime.now();
    final bool isCurrentMonth =
        widget.month.year == now.year && widget.month.month == now.month;
    final Color? pageBackgroundColor =
        Theme.of(context).brightness == Brightness.dark &&
                appStateSettings["forceFullDarkBackground"]
            ? Colors.black
            : appStateSettings["materialYou"]
                ? dynamicPastel(context, Theme.of(context).colorScheme.primary,
                    amount: 0.92)
                : null;

    return EnvelopePlanBuilder(
      builder: (context, plan) {
        return StreamBuilder<List<CategoryWithTotal>>(
          stream: _totals,
          builder: (context, snapshot) {
            final List<CategoryWithTotal> rows = snapshot.data ?? [];
            // Expenses are stored signed negative (determineBudgetPolarity), so
            // an expense category reads positive here and a month of refunds
            // reads negative.
            final TotalSpentCategoriesSummary summary =
                watchTotalSpentInTimeRangeHelper(
              dataInput: rows,
              showAllSubcategories: true,
              multiplyTotalBy: widget.category.income ? 1 : -1,
            );
            final double spent = summary.totalSpent;
            final double? planned =
                plan.amountFor(widget.category.categoryPk, widget.month);
            final double plannedOrZero = planned ?? 0;

            return PageFramework(
              dragDownToDismiss: true,
              title: widget.category.name,
              capitalizeTitle: false,
              belowAppBarPaddingWhenCenteredTitleSmall: 0,
              subtitle: _EnvelopeTotal(
                income: widget.category.income,
                spent: spent,
                planned: planned,
              ),
              subtitleAlignment: AlignmentDirectional.bottomStart,
              subtitleSize: 10,
              backgroundColor: pageBackgroundColor,
              appBarBackgroundColor:
                  Theme.of(context).colorScheme.secondaryContainer,
              appBarBackgroundColorStart:
                  Theme.of(context).colorScheme.secondaryContainer,
              textColor: getColor(context, "black"),
              listID: listID,
              actions: [
                CustomPopupMenuButton(
                  showButtons: enableDoubleColumn(context),
                  keepOutFirst: true,
                  items: [
                    DropdownItemMenu(
                      id: "set-amount",
                      label: "set-amount".tr(),
                      icon: appStateSettings["outlinedIcons"]
                          ? Icons.edit_outlined
                          : Icons.edit_rounded,
                      action: () => enterEnvelopeAmountPopup(
                          context, widget.category, widget.month, plan),
                    ),
                    DropdownItemMenu(
                      id: "edit-category",
                      label: "edit-category".tr(),
                      icon: appStateSettings["outlinedIcons"]
                          ? Icons.category_outlined
                          : Icons.category_rounded,
                      action: () => pushRoute(
                        context,
                        AddCategoryPage(
                          category: widget.category,
                          routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              slivers: [
                // The bar, on the same tint as the app bar above it. The
                // Transform.scale is the budget page's trick for bleeding the
                // colour sideways past the padding, so there is no seam where
                // the app bar ends.
                SliverToBoxAdapter(
                  child: Container(
                    padding: EdgeInsetsDirectional.only(
                        bottom: 20, start: 22, end: 22),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                    ),
                    child: Column(
                      children: [
                        Transform.scale(
                          alignment: AlignmentDirectional.bottomCenter,
                          scale: 1500,
                          child: Container(
                            height: 10,
                            width: 100,
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsetsDirectional.symmetric(
                            horizontal:
                                getHorizontalPaddingConstrained(context),
                          ),
                          child: BudgetProgress(
                            color: categoryColor,
                            percent: plannedOrZero <= 0
                                ? 0
                                : (spent / plannedOrZero) * 100,
                            yourPercent: 0,
                            ghostPercent: 0,
                            todayPercent: isCurrentMonth
                                ? getPercentBetweenDates(monthRange, now)
                                : -1,
                            showToday: isCurrentMonth,
                            large: true,
                          ),
                        ),
                        // Which month this is. Not a timeline: an envelope is
                        // always exactly one calendar month, so there is no
                        // range to draw, only a name to say.
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 8),
                          child: TextFont(
                            text: getMonth(widget.month, includeYear: true),
                            fontSize: 15,
                            textColor: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Where the money went inside the category, in the same box the
                // budget page uses: the ring on each icon is that row's share,
                // and the subcategories sit under their main category.
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SizedBox(height: 20),
                      for (CategoryWithTotal row in rows)
                        if (row.category.mainCategoryPk == null)
                          CategoryEntry(
                            key: ValueKey(row.category.categoryPk),
                            category: row.category,
                            transactionCount: row.transactionCount,
                            categorySpent: row.total.abs(),
                            totalSpent: summary.totalSpent,
                            subcategoriesWithTotalMap: summary
                                .subCategorySpendingIndexedByMainCategoryPk,
                            expandSubcategories: true,
                            selectedSubCategoryPk: selectedCategory?.categoryPk,
                            selected: selectedCategory != null,
                            allSelected: selectedCategory == null,
                            todayPercent: isCurrentMonth
                                ? getPercentBetweenDates(monthRange, now)
                                : null,
                            getPercentageAfterText: (_) =>
                                (widget.category.income
                                        ? "of-total"
                                        : "of-spending")
                                    .tr()
                                    .toLowerCase(),
                            useHorizontalPaddingConstrained: false,
                            onTap: (TransactionCategory tapped, _) {
                              setState(() {
                                selectedCategory =
                                    selectedCategory?.categoryPk ==
                                            tapped.categoryPk
                                        ? null
                                        : tapped;
                              });
                            },
                          ),
                      SizedBox(height: 15),
                    ],
                  ),
                ),

                // The month's transactions in this category, drawn by the same
                // widget the transaction list and the budget page use, so
                // selecting, editing and swiping all behave exactly as they do
                // everywhere else.
                TransactionEntries(
                  monthRange.start,
                  monthRange.end,
                  categoryFks: [
                    selectedCategory?.categoryPk ?? widget.category.categoryPk
                  ],
                  listID: listID,
                  useHorizontalPaddingConstrained: false,
                ),
                SliverToBoxAdapter(child: SizedBox(height: 50)),
              ],
            );
          },
        );
      },
    );
  }

  // One row per subcategory, plus the main category carrying the whole total.
  //
  // `includeAllSubCategories: true` with `countUnassignedTransactions: true` is
  // the pairing watchTotalSpentInTimeRangeHelper is written for (see the note at
  // the top of struct/spendingSummaryHelper.dart), and it is what the budget
  // page uses. The main category's row counts *every* transaction in the
  // category, subcategorised or not, and each subcategory's row counts its own;
  // the helper is what keeps that from being read as double the spending, by
  // summing only rows with no main category of their own. Hand-summing every row
  // instead - which is what this page did before it used the helper - is what
  // makes the pairing look wrong: with that arithmetic it has to be
  // `countUnassignedTransactions: false`, or the total comes out doubled.
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
      countUnassignedTransactions: true,
    );
  }
}

/// The figure at the top of the page: how much, of what, and which way round.
///
/// Tapping swaps between leading with what is left and leading with what has
/// moved, and remembers the choice -- the same affordance, and the same setting,
/// the budget page's own total has (pages/budgetPage.dart TotalSpent).
/// The envelope's headline figure, and the tap that swaps which of its two
/// numbers leads. Shares [SwappableTotal] with the budget page -- what an
/// envelope calls its figures is the only part that differs, and
/// [envelopeHeadline] already owns that.
class _EnvelopeTotal extends StatelessWidget {
  const _EnvelopeTotal({
    required this.income,
    required this.spent,
    required this.planned,
  });

  final bool income;
  final double spent;
  final double? planned;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    return SwappableTotal(
      settingKey: "showTotalSpentForEnvelope",
      pagesNeedingRefresh: const [0, 4],
      contentFor: (_) {
        // envelopeHeadline reads the setting itself, so it already reflects
        // whichever way it was just swapped.
        final EnvelopeHeadline headline = envelopeHeadline(context,
            income: income, spent: spent, planned: planned);
        return SwappableTotalContent(
          amount: headline.amount,
          trailing: " " +
              headline.word.toLowerCase() +
              (planned == null
                  ? ""
                  : "  \u00b7  " +
                      convertToMoney(allWallets, planned!) +
                      " " +
                      "planned".tr().toLowerCase()),
        );
      },
    );
  }
}
