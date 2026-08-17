import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addBudgetPage.dart' show ColumnSliver;
import 'package:cashew_selfhosted/pages/addCategoryPage.dart';
import 'package:cashew_selfhosted/pages/envelopeDetailsPage.dart';
import 'package:cashew_selfhosted/pages/homePage/homePagePlannedVsActual.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/budgetContainer.dart' show BudgetProgress;
import 'package:cashew_selfhosted/widgets/categoryIcon.dart';
import 'package:cashew_selfhosted/widgets/envelopePlanBuilder.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/navigationSidebar.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/selectAmount.dart';
import 'package:cashew_selfhosted/widgets/settingsContainers.dart';
import 'package:cashew_selfhosted/widgets/sliverStickyLabelDivider.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/tappableTextEntry.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// The plan for one month, one row per main category.
//
// Envelopes are not budgets and this page is deliberately not the budgets page:
// no cycles, no filters, no wallets, no added-transactions-only. One amount per
// category per month, and whether it counts as income or expense comes from the
// category itself.
//
// There is no list of envelopes to order or hide either. The order and the
// selection are the category list's, so an envelope appears the moment a
// category does and disappears with it.
class EnvelopesPage extends StatefulWidget {
  const EnvelopesPage({required this.backButton, Key? key}) : super(key: key);
  final bool backButton;

  @override
  State<EnvelopesPage> createState() => EnvelopesPageState();
}

class EnvelopesPageState extends State<EnvelopesPage> {
  GlobalKey<PageFrameworkState> pageState = GlobalKey();

  DateTime selectedMonth = envelopePeriodStart(DateTime.now());

  void scrollToTop() {
    pageState.currentState?.scrollToTop();
  }

  void changeMonth(int delta) {
    setState(() {
      selectedMonth =
          DateTime(selectedMonth.year, selectedMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      key: pageState,
      dragDownToDismiss: true,
      title: "envelopes".tr(),
      backButton: widget.backButton,
      horizontalPaddingConstrained: enableDoubleColumn(context) == false,
      slivers: [
        SliverToBoxAdapter(
          child: MonthSelector(
            month: selectedMonth,
            onChangeMonth: changeMonth,
          ),
        ),
        SliverToBoxAdapter(
          child: HomePagePlannedVsActual(month: selectedMonth),
        ),
        EnvelopeSection(month: selectedMonth, income: false),
        EnvelopeSection(month: selectedMonth, income: true),
        SliverToBoxAdapter(child: SizedBox(height: 50)),
      ],
    );
  }
}

// Which month the page is showing, with a way back and forward. There is no
// upper bound: planning next month before it starts is the point of an
// envelope, and a month with no rows of its own simply shows what the last one
// it does have carried forward.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    required this.month,
    required this.onChangeMonth,
    super.key,
  });

  final DateTime month;
  final Function(int delta) onChangeMonth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: 10,
        bottom: 5,
        start: getHorizontalPaddingConstrained(context) + 13,
        end: getHorizontalPaddingConstrained(context) + 13,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: "previous".tr(),
            onPressed: () => onChangeMonth(-1),
            icon: Icon(appStateSettings["outlinedIcons"]
                ? Icons.chevron_left_outlined
                : Icons.chevron_left_rounded),
          ),
          Expanded(
            child: TextFont(
              text: getMonth(month, includeYear: true),
              fontSize: 20,
              fontWeight: FontWeight.bold,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
          IconButton(
            tooltip: "next".tr(),
            onPressed: () => onChangeMonth(1),
            icon: Icon(appStateSettings["outlinedIcons"]
                ? Icons.chevron_right_outlined
                : Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}


// The words and the colour an envelope uses depend on which side of the ledger
// its category is on, and they are not symmetrical.
//
// Money going out is *spent*, and going past the plan is bad news: red. Money
// coming in is *received*, and going past the plan is the best thing that can
// happen to it -- being paid more than you expected is not an overspend, so it
// reads green and says "above plan" rather than "over".
String envelopeActionWord(bool income) =>
    income ? "received".tr() : "spent".tr();

String envelopeStatusWord({required bool income, required bool beyondPlan}) {
  if (beyondPlan) return income ? "above-plan".tr() : "over".tr();
  return income ? "still-to-come".tr() : "remaining".tr();
}

Color envelopeStatusColor(BuildContext context,
    {required bool income, required bool beyondPlan}) {
  if (beyondPlan == false) return getColor(context, "textLight");
  return getColor(context, income ? "incomeAmount" : "expenseAmount");
}

// One half of the plan: every main expense category, or every main income one.
//
// The rows come from the category list and nothing else, so this section can
// only be empty when the household genuinely has no categories on this side.
// What each row is *measured against* -- the amount planned, the amount spent --
// arrives from two further queries, and neither can take a row off the screen:
// a missing envelope reads as "no plan yet" and a missing total reads as zero.
class EnvelopeSection extends StatefulWidget {
  const EnvelopeSection({
    required this.month,
    required this.income,
    super.key,
  });

  final DateTime month;
  final bool income;

  @override
  State<EnvelopeSection> createState() => _EnvelopeSectionState();
}

class _EnvelopeSectionState extends State<EnvelopeSection> {
  // Created once per month/account set rather than in build(), so scrolling and
  // typing an amount do not resubscribe a query that spans every wallet.
  Stream<List<CategoryWithTotal>>? _spent;
  AllWallets? _spentForWallets;
  DateTime? _spentForMonth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    if (_spent != null &&
        _spentForWallets == allWallets &&
        _spentForMonth == widget.month) return;
    _spentForWallets = allWallets;
    _spentForMonth = widget.month;
    // Guarded because this is the one query here with real machinery behind it
    // -- it spans every wallet and every transaction filter. If constructing it
    // ever throws, the section must still draw its rows; "spent" simply shows
    // as zero, which is visibly wrong rather than invisibly missing.
    try {
      _spent = database.watchTotalSpentInEachCategoryInTimeRangeFromCategories(
        allWallets: allWallets,
        start: widget.month,
        end: DateTime(widget.month.year, widget.month.month + 1, 0),
        categoryFks: null,
        categoryFksExclude: null,
        budgetTransactionFilters: null,
        memberTransactionFilters: null,
        isIncome: widget.income,
      );
    } catch (e) {
      print("Error building the envelope spending query: " + e.toString());
      _spent = null;
    }
  }

  @override
  void didUpdateWidget(EnvelopeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    return EnvelopePlanBuilder(
      builder: (context, plan) {
        final List<TransactionCategory> categories =
            plan.categoriesOfType(income: widget.income);
        if (categories.isEmpty) return SliverToBoxAdapter();

        return StreamBuilder<List<CategoryWithTotal>>(
          stream: _spent,
          builder: (context, spentSnapshot) {
            final Map<String, double> spentByCategoryPk = {
              for (CategoryWithTotal entry in spentSnapshot.data ?? [])
                // Expenses are stored signed negative (determineBudgetPolarity),
                // so flip them: a month whose refunds outweigh its spending
                // reads as negative spending rather than flipping to positive.
                entry.category.categoryPk:
                    widget.income ? entry.total : -entry.total,
            };
            double planned = 0;
            for (TransactionCategory category in categories) {
              planned += plan.amountFor(category.categoryPk, widget.month) ?? 0;
            }

            return SliverStickyLabelDivider(
              info: widget.income ? "income".tr() : "expense".tr(),
              extraInfo: convertToMoney(allWallets, planned),
              sliver: ColumnSliver(
                children: [
                  SizedBox(height: 5),
                  for (TransactionCategory category in categories)
                    EnvelopeEntry(
                      key: ValueKey(category.categoryPk),
                      category: category,
                      month: widget.month,
                      plan: plan,
                      spent: spentByCategoryPk[category.categoryPk] ?? 0,
                    ),
                  SizedBox(height: 5),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class EnvelopeEntry extends StatelessWidget {
  const EnvelopeEntry({
    required this.category,
    required this.month,
    required this.plan,
    required this.spent,
    this.horizontalPadding = 13,
    super.key,
  });

  final TransactionCategory category;
  final DateTime month;
  final EnvelopePlan plan;
  final double spent;

  /// Space around the card. The list wants the page's own margin; a carousel
  /// wants almost none, because the gap between slides is what lets the next
  /// card peek in at the edge and say there is more to swipe to.
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final double? amount = plan.amountFor(category.categoryPk, month);
    final double amountOrZero = amount ?? 0;
    final double percent =
        amountOrZero <= 0 ? 0 : (spent / amountOrZero) * 100;
    final double remaining = amountOrZero - spent;

    // The month on screen, and how far into it we are. A month that has ended
    // or has not started gets no "today" marker, because there is no today in
    // it to mark -- the same reason the budget card only shows it on the
    // current period.
    final DateTime now = DateTime.now();
    final DateTimeRange monthRange = DateTimeRange(
      start: month,
      end: DateTime(month.year, month.month + 1, 0),
    );
    final bool isCurrentMonth =
        month.year == now.year && month.month == now.month;

    final Color categoryColor = HexColor(category.colour,
        defaultColor: Theme.of(context).colorScheme.primary);
    final double borderRadius = getPlatform() == PlatformOS.isIOS ? 14 : 20;

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
          horizontal: horizontalPadding, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          // The envelope itself is the app's plain surface -- white, or the
          // lightened accent under Material You. What tells the categories
          // apart is the shadow underneath, tinted to the category's own colour
          // so the card looks lit from below rather than painted over.
          boxShadow: boxShadowCheck([
            BoxShadow(
              color: categoryColor.withOpacity(
                  Theme.of(context).brightness == Brightness.light ? 0.4 : 0.5),
              blurRadius: 15,
              spreadRadius: -4,
              offset: Offset(0, 5),
            ),
          ]),
        ),
        child: Tappable(
          color: getColor(context, "lightDarkAccentHeavyLight"),
          borderRadius: borderRadius,
          // The card opens the category's month: what was spent, split by
          // subcategory, and the transactions behind it. Setting the amount is
          // the number on the right, which has its own tap target.
          onTap: () {
            pushRoute(
              context,
              EnvelopeDetailsPage(category: category, month: month),
            );
          },
          onLongPress: () {
            pushRoute(
              context,
              AddCategoryPage(
                category: category,
                routesToPopAfterDelete: RoutesToPopAfterDelete.One,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 16, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
              children: [
                    CategoryIcon(
                      category: category,
                      categoryPk: category.categoryPk,
                      size: 26,
                      sizePadding: 14,
                      margin: EdgeInsetsDirectional.zero,
                      canEditByLongPress: false,
                    ),
                    SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFont(
                              text: category.name, fontSize: 17, maxLines: 1),
                          SizedBox(height: 1),
                          TextFont(
                            text: convertToMoney(allWallets, spent) +
                                " " +
                                envelopeActionWord(category.income)
                                    .toLowerCase() +
                                (amount == null
                                    ? ""
                                    : ", " +
                                        convertToMoney(
                                            allWallets, remaining.abs()) +
                                        " " +
                                        envelopeStatusWord(
                                          income: category.income,
                                          beyondPlan: remaining < 0,
                                        ).toLowerCase()),
                            fontSize: 14,
                            // Two lines, because the planned amount sits beside
                            // it and a long currency plus two clauses will not
                            // fit on one. Truncating here hides the number the
                            // line exists to show.
                            maxLines: 2,
                            // Only a category with a plan can be measured
                            // against one. Money moving in a category nobody
                            // planned is just money moving.
                            textColor: amount == null
                                ? getColor(context, "textLight")
                                : envelopeStatusColor(context,
                                    income: category.income,
                                    beyondPlan: remaining < 0),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 10),
                    TappableTextEntry(
                      title: convertToMoney(allWallets, amountOrZero),
                      placeholder: convertToMoney(allWallets, 0),
                      // An amount carried forward from an earlier month is
                      // still the plan for this one, so it shows as a real
                      // number. Only a category with no plan at all reads as a
                      // placeholder.
                      showPlaceHolderWhenTextEquals:
                          amount == null ? convertToMoney(allWallets, 0) : null,
                      onTap: () => enterEnvelopeAmountPopup(
                          context, category, month, plan),
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      internalPadding: EdgeInsetsDirectional.symmetric(
                          vertical: 2, horizontal: 4),
                      padding: EdgeInsetsDirectional.symmetric(
                          vertical: 6, horizontal: 3),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                // The budget card's own progress bar, reused rather than
                // reimplemented: same colours, same percent label inside it,
                // same shake when the category goes over.
                BudgetProgress(
                  color: categoryColor,
                  percent: percent,
                  yourPercent: 0,
                  ghostPercent: 0,
                  todayPercent: isCurrentMonth
                      ? getPercentBetweenDates(monthRange, now)
                      : -1,
                  showToday: isCurrentMonth,
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

/// Sets one category's plan for one month.
///
/// Written once, after the sheet closes, rather than on every keystroke:
/// SelectAmount reports each edit as it is typed and every write is a row the
/// sync feed then has to carry.
Future<void> enterEnvelopeAmountPopup(
  BuildContext context,
  TransactionCategory category,
  DateTime month,
  EnvelopePlan plan,
) async {
  final double? current = plan.amountFor(category.categoryPk, month);
  double amount = current ?? 0;
  bool setFromPercent = false;

  await openBottomSheet(
    context,
    fullSnap: true,
    PopupFramework(
      title: category.name,
      subtitle: getMonth(month, includeYear: true),
      hasPadding: false,
      underTitleSpace: false,
      // Tapping the icon leaves the plan and opens the category itself -- its
      // name, colour, icon, subcategories. Same affordance as the category
      // limit popup, so it behaves the way it does everywhere else.
      icon: CategoryIcon(
        categoryPk: category.categoryPk,
        size: 35,
        borderRadius: 500,
        margin: EdgeInsetsDirectional.zero,
        canEditByLongPress: false,
        onTap: () {
          popRoute(context);
          pushRoute(
            context,
            AddCategoryPage(
              category: category,
              routesToPopAfterDelete: RoutesToPopAfterDelete.One,
            ),
          );
        },
      ),
      child: SelectAmount(
        onlyShowCurrencyIcon: true,
        allowZero: true,
        amountPassed: amount == 0 ? "" : amount.toString(),
        setSelectedAmount: (double selectedAmount, _) {
          amount = selectedAmount.abs();
        },
        next: () async {
          popRoute(context);
        },
        nextLabel: "set-amount".tr(),
        padding: EdgeInsetsDirectional.symmetric(horizontal: 18),
        // Income is planned as a number, never as a share of itself.
        extraWidgetAboveNumbers: category.income
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 18, vertical: 5),
                child: SettingsContainer(
                  isOutlined: true,
                  isWideOutlined: true,
                  iconScale: 1,
                  title: "set-as-percent-of-planned-income".tr(),
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.percent_outlined
                      : Icons.percent_rounded,
                  onTap: () {
                    setFromPercent = true;
                    popRoute(context);
                  },
                ),
              ),
      ),
    ),
  );

  if (setFromPercent) {
    await _setAmountFromPercentOfPlannedIncome(context, category, month, plan);
    return;
  }
  if (amount == current) return;
  await database.createOrUpdateCategoryEnvelope(newCategoryEnvelope(
    categoryPk: category.categoryPk,
    periodStart: month,
    amount: amount,
  ));
}

/// "% of planned income" is a one shot convenience, not a stored setting: the
/// percentage is resolved against this month's planned income and the plain
/// amount it comes to is what gets saved, indistinguishable from a number typed
/// by hand.
Future<void> _setAmountFromPercentOfPlannedIncome(
  BuildContext context,
  TransactionCategory category,
  DateTime month,
  EnvelopePlan plan,
) async {
  final AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
  final double plannedIncome = plan.totalPlanned(income: true, periodStart: month);
  if (plannedIncome <= 0) {
    openPopup(
      context,
      title: "no-planned-income".tr(),
      description: "no-planned-income-description".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.info_outlined
          : Icons.info_rounded,
      onSubmit: () {
        popRoute(context);
      },
      onSubmitLabel: "ok".tr(),
    );
    return;
  }

  double selectedPercent = 0;
  await openBottomSheet(
    context,
    PopupFramework(
      title: "set-as-percent-of-planned-income".tr(),
      subtitle: "planned-income".tr() +
          ": " +
          convertToMoney(allWallets, plannedIncome),
      child: SelectAmountValue(
        amountPassed: "",
        allowZero: true,
        suffix: "%",
        setSelectedAmount: (double amount, _) {
          selectedPercent = amount.abs() > 100 ? 100 : amount.abs();
        },
        next: () async {
          popRoute(context);
        },
        nextLabel: "set-amount".tr(),
      ),
    ),
  );

  await database.createOrUpdateCategoryEnvelope(newCategoryEnvelope(
    categoryPk: category.categoryPk,
    periodStart: month,
    amount: selectedPercent / 100 * plannedIncome,
  ));
}
