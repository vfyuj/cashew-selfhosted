import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addBudgetPage.dart' show ColumnSliver;
import 'package:cashew_selfhosted/pages/addCategoryPage.dart';
import 'package:cashew_selfhosted/pages/editEnvelopesPage.dart';
import 'package:cashew_selfhosted/pages/envelopeDetailsPage.dart';
import 'package:cashew_selfhosted/pages/homePage/homePagePlannedVsActual.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/budgetContainer.dart'
    show BudgetProgress;
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
import 'package:sliver_tools/sliver_tools.dart';

// The plan for one month, one row per main category.
//
// Envelopes are not budgets and this page is deliberately not the budgets page:
// no cycles, no filters, no wallets, no added-transactions-only. One amount per
// category per month, and whether it counts as income or expense comes from the
// category itself.
//
// There is no list of envelopes to create or delete either: an envelope appears
// the moment a category does and disappears with it. What the pencil in the
// corner opens is a reorder screen and nothing more (editEnvelopesPage.dart),
// and the order it writes is that member's own -- not the household's.
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

  // The order and the total type are settings, not queries, so nothing else
  // tells this page to redraw when one of them changes. updateSettings calls
  // this through pagesNeedingRefresh: [4] (struct/settings.dart).
  void refreshState() {
    setState(() {});
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
      actions: [
        IconButton(
          padding: EdgeInsetsDirectional.all(15),
          tooltip: "edit-envelopes".tr(),
          onPressed: () {
            pushRoute(context, EditEnvelopesPage());
          },
          icon: Icon(
            appStateSettings["outlinedIcons"]
                ? Icons.edit_outlined
                : Icons.edit_rounded,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: MonthSelector(
            month: selectedMonth,
            onChangeMonth: changeMonth,
          ),
        ),
        // One plan for the whole page. Each builder holds two live queries, and
        // three of them side by side meant six subscriptions and three
        // independently-timed rebuilds for one screen's worth of the same two
        // answers.
        EnvelopePlanBuilder(
          builder: (context, plan) {
            return MultiSliver(
              children: [
                SliverToBoxAdapter(
                  child:
                      HomePagePlannedVsActual(month: selectedMonth, plan: plan),
                ),
                EnvelopeSection(
                    month: selectedMonth, income: false, plan: plan),
                EnvelopeSection(month: selectedMonth, income: true, plan: plan),
              ],
            );
          },
        ),
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
// Money going out is *spent in total*, and going past the plan is bad news:
// red, and named *overspent* rather than a bare "over", because the number
// beside it is what you went over BY, not what you spent. Money coming in is
// *received*, and going past the plan is the best thing that can happen to it --
// being paid more than you expected is not an overspend, so it reads green and
// says "above plan".
//
// The expense side also says "in total", because the two figures on a card
// answer different questions -- what is left of the plan, and what has gone out
// altogether -- and the second was being read as another slice of the first.
// The income side is left as it was: "received" was never ambiguous.
String envelopeActionWord(bool income) =>
    income ? "received".tr() : "spent-in-total".tr();

String envelopeStatusWord({required bool income, required bool beyondPlan}) {
  if (beyondPlan) return income ? "above-plan".tr() : "overspent".tr();
  return income ? "still-to-come".tr() : "remaining".tr();
}

/// The two clauses of an envelope's status line, the second one quieter.
///
/// Two sentences on the expense side rather than one comma-spliced phrase: "6,428
/// overspent, 37,232 spent" invited reading the second number as part of the
/// first. A full stop, and the leading clause in bold, make them two separate
/// statements -- which is what they are.
List<TextSpan> envelopeStatusSpans(
  BuildContext context, {
  required EnvelopeHeadline headline,
  required bool income,
  required bool hasPlan,
  required AllWallets allWallets,
  required double fontSize,
}) {
  final TextStyle style = TextStyle(
    color: headline.color,
    fontFamily: appStateSettings["font"],
    fontFamilyFallback: const ['Inter'],
    fontSize: fontSize,
  );
  return [
    TextSpan(
      text: convertToMoney(allWallets, headline.amount) +
          " " +
          headline.word.toLowerCase(),
      style: style.copyWith(fontWeight: FontWeight.bold),
    ),
    // Only a category with a plan has a second figure to report against it.
    if (hasPlan)
      TextSpan(
        text: (income ? ", " : ". ") +
            convertToMoney(allWallets, headline.trailingAmount) +
            " " +
            headline.trailingWord.toLowerCase(),
        style: style,
      ),
  ];
}

Color envelopeStatusColor(BuildContext context,
    {required bool income, required bool beyondPlan}) {
  if (beyondPlan == false) return getColor(context, "textLight");
  return getColor(context, income ? "incomeAmount" : "expenseAmount");
}

/// Which of an envelope's two figures leads, and what each is called.
///
/// An envelope is described by two numbers -- what has moved and what is left --
/// and `showTotalSpentForEnvelope` decides which one is the big one, exactly as
/// `showTotalSpentForBudget` does for a budget. Both figures are always shown;
/// the setting only swaps their billing, so nobody loses a number by changing it.
///
/// One helper for the card and the detail page, so the two can never disagree
/// about which figure is being emphasised.
class EnvelopeHeadline {
  const EnvelopeHeadline({
    required this.amount,
    required this.word,
    required this.trailingAmount,
    required this.trailingWord,
    required this.color,
  });

  /// The figure to show large, and the word for it.
  final double amount;
  final String word;

  /// The other figure, for the quieter line beside it.
  final double trailingAmount;
  final String trailingWord;

  /// Colour for the whole phrase: quiet unless the envelope is past its plan.
  final Color color;
}

EnvelopeHeadline envelopeHeadline(
  BuildContext context, {
  required bool income,
  required double spent,
  required double? planned,
}) {
  final double remaining = (planned ?? 0) - spent;
  final bool beyondPlan = remaining < 0;
  final String spentWord = envelopeActionWord(income);
  final String remainingWord =
      envelopeStatusWord(income: income, beyondPlan: beyondPlan);
  // Only a category with a plan can be measured against one. Money moving in a
  // category nobody planned is just money moving -- there is no "remaining" to
  // lead with, whatever the setting says.
  final Color color = planned == null
      ? getColor(context, "textLight")
      : envelopeStatusColor(context, income: income, beyondPlan: beyondPlan);
  if (planned == null ||
      appStateSettings["showTotalSpentForEnvelope"] == true) {
    return EnvelopeHeadline(
      amount: spent,
      word: spentWord,
      trailingAmount: remaining.abs(),
      trailingWord: remainingWord,
      color: color,
    );
  }
  return EnvelopeHeadline(
    amount: remaining.abs(),
    word: remainingWord,
    trailingAmount: spent,
    trailingWord: spentWord,
    color: color,
  );
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
    required this.plan,
    super.key,
  });

  final DateTime month;
  final bool income;

  /// Handed down from the page rather than fetched here, so both sections and
  /// the Planned vs Actual card above them read one snapshot.
  final EnvelopePlan plan;

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
    final EnvelopePlan plan = widget.plan;
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
    final double percent = amountOrZero <= 0 ? 0 : (spent / amountOrZero) * 100;
    final EnvelopeHeadline headline = envelopeHeadline(context,
        income: category.income, spent: spent, planned: amount);

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
                            // Which figure leads is the reader's choice; see
                            // envelopeHeadline.
                            text: "",
                            richTextSpan: envelopeStatusSpans(
                              context,
                              headline: headline,
                              income: category.income,
                              hasPlan: amount != null,
                              allWallets: allWallets,
                              fontSize: 14,
                            ),
                            fontSize: 14,
                            // Two lines, because the planned amount sits beside
                            // it and a long currency plus two clauses will not
                            // fit on one. Truncating here hides the number the
                            // line exists to show.
                            maxLines: 2,
                            textColor: headline.color,
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
///
/// The number pad works in the amount **as stored**, in its own account's
/// currency - not the converted figure the card shows. Anything else would
/// re-round the plan through today's exchange rate every time the sheet was
/// opened and closed.
Future<void> enterEnvelopeAmountPopup(
  BuildContext context,
  TransactionCategory category,
  DateTime month,
  EnvelopePlan plan,
) async {
  final CategoryEnvelope? current =
      plan.resolvedEnvelopeFor(category.categoryPk, month);
  double amount = current?.amount ?? 0;
  // The account the plan is counted in. An amount already set keeps the account
  // it was set in, even when that is not the primary one today; a new one is
  // planned in the currency the pad is showing.
  String selectedWalletPk =
      current?.walletFk ?? appStateSettings["selectedWalletPk"];
  bool setFromPercent = false;
  // Only "Set amount" writes. Dismissing the sheet has to leave the plan
  // exactly as it was, and the amount alone cannot say which happened: a
  // category with no plan starts this function at 0, and 0 is also a perfectly
  // ordinary amount to type. Without this flag, opening the sheet on an
  // unplanned category and swiping it away stored a real "planned 0" row that
  // then carried forward into every later month.
  bool confirmed = false;

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
        // Only for a household that actually keeps more than one currency; with
        // one, there is nothing to pick and the picker is hidden entirely. Same
        // arrangement as a budget's per-category limit.
        enableWalletPicker: true,
        hideWalletPickerIfOneCurrency: true,
        selectedWalletPk: selectedWalletPk,
        walletPkForCurrency: selectedWalletPk,
        setSelectedWalletPk: (String walletPkPassed) {
          selectedWalletPk = walletPkPassed;
        },
        next: () async {
          confirmed = true;
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
  if (confirmed == false) return;
  // Unchanged in both halves: the same number in the same currency. Changing
  // only the account is a real change - it is what the amount means.
  if (amount == current?.amount && selectedWalletPk == current?.walletFk) {
    return;
  }
  await database.createOrUpdateCategoryEnvelope(newCategoryEnvelope(
    categoryPk: category.categoryPk,
    periodStart: month,
    amount: amount,
    walletPk: selectedWalletPk,
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
  final double plannedIncome =
      plan.totalPlanned(income: true, periodStart: month);
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
  // Same reason as the amount sheet above: dismissing must not write. A
  // percentage that was never typed is 0, and writing that turned a swipe-away
  // into "this category is planned at nothing this month".
  bool confirmed = false;
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
          confirmed = true;
          popRoute(context);
        },
        nextLabel: "set-amount".tr(),
      ),
    ),
  );

  if (confirmed == false) return;
  final double newAmount = selectedPercent / 100 * plannedIncome;
  if (newAmount == plan.amountFor(category.categoryPk, month)) return;
  await database.createOrUpdateCategoryEnvelope(newCategoryEnvelope(
    categoryPk: category.categoryPk,
    periodStart: month,
    amount: newAmount,
    // A share of the planned income, and that total is in the primary currency
    // like everything else the plan hands out - so this amount is too,
    // whichever account the category was planned in before.
    walletPk: appStateSettings["selectedWalletPk"],
  ));
}
