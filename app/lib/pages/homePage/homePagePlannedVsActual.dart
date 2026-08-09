import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/budgetsListPage.dart';
import 'package:cashew_selfhosted/pages/transactionFilters.dart';
import 'package:cashew_selfhosted/pages/transactionsSearchPage.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/mainCategoryBudgets.dart';
import 'package:cashew_selfhosted/widgets/countNumber.dart';
import 'package:cashew_selfhosted/widgets/openContainerNavigation.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/util/keepAliveClientMixin.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// This month's plan against what actually happened:
//   planned = planned income - planned main-category expenses (PlannedBudgetTotals,
//     the same totals the budgets list and share-of-plan labels already read)
//   actual  = actual income - actual expenses, for the current calendar month
// "Actual" deliberately queries with an explicit forcedDateTimeRange rather than
// following AllSpendingSummary's customisable period-cycle settings - this
// widget is always "this calendar month", to match what the envelopes it
// summarises default to.
class HomePagePlannedVsActual extends StatelessWidget {
  const HomePagePlannedVsActual({super.key});

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final DateTime now = DateTime.now();
    final DateTimeRange thisMonth = DateTimeRange(
      start: now.firstDayOfMonth(),
      end: DateTime(now.year, now.month + 1, 0),
    );

    return KeepAliveClientMixin(
      child: Padding(
        padding:
            const EdgeInsetsDirectional.only(bottom: 13, start: 13, end: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: StreamBuilder<PlannedBudgetTotals>(
                stream: watchPlannedBudgetTotals(),
                initialData: latestPlannedBudgetTotals,
                builder: (context, snapshot) {
                  final PlannedBudgetTotals? totals = snapshot.data;
                  final double planned = totals == null
                      ? 0
                      : totals.totalPlannedIncome(allWallets) -
                          totals.totalPlannedExpenses(allWallets);
                  return _PlannedVsActualBox(
                    label: "planned".tr(),
                    amount: planned,
                    openPage: BudgetsListPage(enableBackButton: true),
                  );
                },
              ),
            ),
            SizedBox(width: 13),
            Expanded(
              child: StreamBuilder<TotalWithCount?>(
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
                      // Expense amounts are already stored signed negative
                      // (see determineBudgetPolarity), so adding the two
                      // totals nets them - no separate subtraction needed.
                      final double actual =
                          (incomeSnapshot.data?.total ?? 0) +
                              (expenseSnapshot.data?.total ?? 0);
                      return _PlannedVsActualBox(
                        label: "actual".tr(),
                        amount: actual,
                        openPage: TransactionsSearchPage(
                          initialFilters: SearchFilters()
                              .copyWith(dateTimeRange: thisMonth),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlannedVsActualBox extends StatelessWidget {
  const _PlannedVsActualBox({
    required this.label,
    required this.amount,
    required this.openPage,
  });

  final String label;
  final double amount;
  final Widget openPage;

  @override
  Widget build(BuildContext context) {
    final Color color = amount >= 0
        ? getColor(context, "incomeAmount")
        : getColor(context, "expenseAmount");
    return Container(
      decoration:
          BoxDecoration(boxShadow: boxShadowCheck(boxShadowGeneral(context))),
      child: OpenContainerNavigation(
        closedColor: getColor(context, "lightDarkAccentHeavyLight"),
        openPage: openPage,
        borderRadius: 15,
        button: (openContainer) {
          return Tappable(
            color: getColor(context, "lightDarkAccentHeavyLight"),
            onTap: () {
              openContainer();
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 15, vertical: 17),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFont(
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    text: label,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  SizedBox(height: 6),
                  CountNumber(
                    count: amount,
                    duration: Duration(milliseconds: 1000),
                    initialCount: 0,
                    textBuilder: (number) {
                      return TextFont(
                        text: convertToMoney(
                            Provider.of<AllWallets>(context), number,
                            finalNumber: amount),
                        textColor: color,
                        fontWeight: FontWeight.bold,
                        textAlign: TextAlign.center,
                        autoSizeText: true,
                        fontSize: 21,
                        maxFontSize: 21,
                        minFontSize: 10,
                        maxLines: 1,
                      );
                    },
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
