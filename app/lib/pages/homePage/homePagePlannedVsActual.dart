import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/envelopesPage.dart';
import 'package:cashew_selfhosted/pages/transactionFilters.dart';
import 'package:cashew_selfhosted/pages/transactionsSearchPage.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/widgets/countNumber.dart';
import 'package:cashew_selfhosted/widgets/envelopePlanBuilder.dart';
import 'package:cashew_selfhosted/widgets/openContainerNavigation.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/transactionEntry/incomeAmountArrow.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/util/keepAliveClientMixin.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// One month's cash flow, as two cards tagged Planned and Actual:
//   Planned = the envelopes set for that month (struct/categoryEnvelopes.dart),
//     income and expense side by side
//   Actual  = income and expenses recorded in that calendar month
//
// Income and expenses are shown as two separate figures rather than pre-netted
// into one: testers couldn't tell what a single "planned minus actual" number
// meant. The subtraction still appears, but demoted to a quiet third line under
// a rule, so the card reads top-down like a receipt instead of asking anyone to
// reconstruct the arithmetic.
//
// "Actual" deliberately queries with an explicit forcedDateTimeRange rather than
// following AllSpendingSummary's customisable period-cycle settings - this
// widget is always one whole calendar month, because that is the only period an
// envelope has.
class HomePagePlannedVsActual extends StatelessWidget {
  const HomePagePlannedVsActual({this.month, super.key});

  /// The month to summarise. Null means the current one, which is what the home
  /// page wants; the envelopes page passes whichever month it is showing.
  final DateTime? month;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final DateTime periodStart = envelopePeriodStart(month ?? DateTime.now());
    final DateTimeRange thisMonth = DateTimeRange(
      start: periodStart,
      end: DateTime(periodStart.year, periodStart.month + 1, 0),
    );

    final Widget plannedCard = EnvelopePlanBuilder(
      builder: (context, plan) {
        return _CashFlowCard(
          tag: "planned".tr(),
          expenses: plan.totalPlanned(income: false, periodStart: periodStart),
          income: plan.totalPlanned(income: true, periodStart: periodStart),
          openPage: EnvelopesPage(backButton: true),
        );
      },
    );

    final Widget actualCard = StreamBuilder<TotalWithCount?>(
      stream: database.watchTotalWithCountOfWallet(
        isIncome: true,
        allWallets: allWallets,
        onlyIncomeAndExpense: true,
        forcedDateTimeRange: thisMonth,
      ),
      builder: (context, incomeSnapshot) {
        return StreamBuilder<TotalWithCount?>(
          stream: database.watchTotalWithCountOfWallet(
            isIncome: false,
            allWallets: allWallets,
            onlyIncomeAndExpense: true,
            forcedDateTimeRange: thisMonth,
          ),
          builder: (context, expenseSnapshot) {
            return _CashFlowCard(
              tag: "actual".tr(),
              // Expense amounts are stored signed negative (see
              // determineBudgetPolarity), so negate rather than take the
              // absolute value: a month whose refunds outweigh its spending
              // should read as a negative expense, not flip to a positive one.
              expenses: -(expenseSnapshot.data?.total ?? 0),
              income: incomeSnapshot.data?.total ?? 0,
              openPage: TransactionsSearchPage(
                initialFilters:
                    SearchFilters().copyWith(dateTimeRange: thisMonth),
              ),
            );
          },
        );
      },
    );

    return KeepAliveClientMixin(
      child: Padding(
        padding:
            const EdgeInsetsDirectional.only(bottom: 13, start: 13, end: 13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Side by side, each card is half of this - and the header row
            // (title plus tag) needs real width before the title starts
            // wrapping into a column of single words. Below the threshold,
            // stack them full width instead of letting both get squeezed.
            if (constraints.maxWidth < 500) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  plannedCard,
                  SizedBox(height: 13),
                  actualCard,
                ],
              );
            }
            // Deliberately no IntrinsicHeight here, however tempting it is for
            // making the pair exactly the same height. The amounts use
            // AutoSizeText, which is built on LayoutBuilder, and LayoutBuilder
            // reports an intrinsic height of 0 - it asserts in debug builds and
            // silently returns 0.0 in release ones. The labelled rows survive
            // that because their label is plain text and sets the row height,
            // but the unlabelled subtraction row measures as zero, so
            // IntrinsicHeight hands the card ~20px less than it needs and the
            // last line is clipped down to a sliver in release builds only.
            // Both cards have identical structure, so plain layout already
            // gives them matching heights.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: plannedCard),
                SizedBox(width: 13),
                Expanded(child: actualCard),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CashFlowCard extends StatelessWidget {
  const _CashFlowCard({
    required this.tag,
    required this.expenses,
    required this.income,
    required this.openPage,
  });

  final String tag;
  final double expenses;
  final double income;
  final Widget openPage;

  @override
  Widget build(BuildContext context) {
    // The app's own surface token: pure white with Material You off, and a
    // lightened accent pastel with it on - so the card follows the theme
    // instead of being tinted or stepped off the background by hand. It is what
    // TransactionsAmountBox and the rest of the home page cards already use.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fillColor = getColor(context, "lightDarkAccentHeavyLight");
    final Color dividerColor = isDark
        ? Colors.white.withOpacity(0.09)
        : Colors.black.withOpacity(0.08);
    final double borderRadius = getPlatform() == PlatformOS.isIOS ? 12 : 18;

    // Income is always green and expenses always red, arrow included, so the
    // two rows read the same way here as they do in the transactions list -
    // they label a direction rather than reporting a result. The one figure
    // that does report a result is the subtraction below them, and it stays
    // neutral unless it goes negative.
    final double net = income - expenses;

    return Container(
      decoration:
          BoxDecoration(boxShadow: boxShadowCheck(boxShadowGeneral(context))),
      child: OpenContainerNavigation(
        closedColor: fillColor,
        openPage: openPage,
        borderRadius: borderRadius,
        button: (openContainer) {
          return Tappable(
            color: fillColor,
            borderRadius: borderRadius,
            onTap: () {
              openContainer();
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFont(
                          text: "monthly-cash-flow".tr(),
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          maxLines: 2,
                        ),
                      ),
                      SizedBox(width: 10),
                      Padding(
                        // Nudge the pill down to sit on the title's baseline
                        // rather than on the top of its line box.
                        padding: const EdgeInsetsDirectional.only(top: 2),
                        child: Container(
                          padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: TextFont(
                            text: tag,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            maxLines: 1,
                            textColor: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 22),
                  _CashFlowRow(
                    label: "income".tr(),
                    amount: income,
                    amountColor: getColor(context, "incomeAmount"),
                    isIncome: true,
                  ),
                  SizedBox(height: 16),
                  _CashFlowRow(
                    label: "expenses".tr(),
                    amount: expenses,
                    amountColor: getColor(context, "expenseAmount"),
                    isIncome: false,
                  ),
                  SizedBox(height: 14),
                  Container(height: 1, color: dividerColor),
                  SizedBox(height: 10),
                  // The subtraction, unlabelled and deliberately quiet - it
                  // lines up under the two amounts above it like the total of
                  // a receipt column. No arrow: it is a balance, not a
                  // direction, and it only takes on colour when it goes
                  // negative and there is something to flag.
                  _CashFlowRow(
                    label: null,
                    amount: net,
                    amountColor: net < 0
                        ? getColor(context, "expenseAmount")
                        : getColor(context, "textLight"),
                    fontSize: 15,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CashFlowRow extends StatelessWidget {
  const _CashFlowRow({
    required this.label,
    required this.amount,
    required this.amountColor,
    this.isIncome,
    this.fontSize = 20,
  });

  final String? label;
  final double amount;
  final Color amountColor;
  // null leaves the arrow off entirely, for the subtraction row.
  final bool? isIncome;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (label != null)
          TextFont(
            text: label!,
            fontSize: 16,
            maxLines: 1,
            textColor: getColor(context, "textLight"),
          ),
        if (label != null) SizedBox(width: 10),
        // Expanded rather than Flexible: the amount takes all the space the
        // label leaves and right-aligns inside it, so the figures line up in a
        // column - including the unlabelled subtraction row, which would
        // otherwise sit against the left edge.
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isIncome != null)
                // Same widget, colour and proportions the transactions list
                // uses at this text size (transactionEntryAmount.dart).
                IncomeOutcomeArrow(
                  isIncome: isIncome!,
                  color: amountColor,
                  width: 15,
                  iconSize: 24,
                ),
              Flexible(
                child: CountNumber(
                  count: amount,
                  duration: Duration(milliseconds: 1000),
                  initialCount: 0,
                  textBuilder: (number) {
                    return TextFont(
                      text: convertToMoney(
                          Provider.of<AllWallets>(context), number,
                          finalNumber: amount),
                      textColor: amountColor,
                      fontWeight: FontWeight.bold,
                      textAlign: TextAlign.end,
                      autoSizeText: true,
                      fontSize: fontSize,
                      maxFontSize: fontSize,
                      minFontSize: 10,
                      maxLines: 1,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
