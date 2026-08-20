import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addButton.dart';
import 'package:cashew_selfhosted/pages/envelopesPage.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/widgets/envelopePlanBuilder.dart';
import 'package:cashew_selfhosted/widgets/homePageCardCarousel.dart';
import 'package:cashew_selfhosted/widgets/util/keepAliveClientMixin.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// This month's envelopes on the home page, swiped horizontally -- literally the
// same carousel the pinned budgets use (widgets/homePageCardCarousel.dart), and
// the same card the envelopes page draws, so nothing about an envelope looks
// different depending on where you meet it.
//
// **Only envelopes with an amount set for the month appear here.** Every main
// category has an envelope (see docs/app/envelopes.md), which is right for the
// envelopes page and wrong for the home page: a household with twenty
// categories would get twenty cards to swipe through, most of them empty. A
// category with no plan has nothing to track yet, so it waits on its own page.
class HomePageEnvelopes extends StatefulWidget {
  const HomePageEnvelopes({super.key});

  @override
  State<HomePageEnvelopes> createState() => _HomePageEnvelopesState();
}

class _HomePageEnvelopesState extends State<HomePageEnvelopes> {
  // Both sides of the ledger in one query: the card decides what a number means
  // from its category's income flag, not from the query.
  Stream<List<CategoryWithTotal>>? _spent;
  AllWallets? _spentForWallets;
  // The month the query was built for. build() reads "now" every frame, so
  // without this an app left open across midnight on the 1st drew the new
  // month's plan against the old month's spending until it was restarted.
  DateTime? _spentForMonth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureSpentStream(
        Provider.of<AllWallets>(context), envelopePeriodStart(DateTime.now()));
  }

  // Called from build() as well, because nothing notifies a widget that the
  // month has turned over -- the next rebuild for any other reason is where it
  // is noticed. Assigning the field here is safe: it changes what the
  // StreamBuilder below is handed in this same build, not what is on screen
  // already, so it cannot schedule a rebuild of its own.
  void _ensureSpentStream(AllWallets allWallets, DateTime month) {
    if (_spent != null &&
        _spentForWallets == allWallets &&
        _spentForMonth == month) return;
    _spentForWallets = allWallets;
    _spentForMonth = month;
    final DateTimeRange range = envelopeMonthRange(month);
    try {
      _spent = database.watchTotalSpentInEachCategoryInTimeRangeFromCategories(
        allWallets: allWallets,
        start: range.start,
        end: range.end,
        categoryFks: null,
        categoryFksExclude: null,
        budgetTransactionFilters: null,
        memberTransactionFilters: null,
      );
    } catch (e) {
      print("Error building the home page envelope query: " + e.toString());
      _spent = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime month = envelopePeriodStart(DateTime.now());
    _ensureSpentStream(Provider.of<AllWallets>(context), month);

    return KeepAliveClientMixin(
      child: EnvelopePlanBuilder(
        builder: (context, plan) {
          final List<TransactionCategory> planned = plan.categories
              .where((TransactionCategory category) =>
                  plan.amountFor(category.categoryPk, month) != null)
              .toList();

          if (planned.isEmpty) {
            return AddButton(
              onTap: () {
                pushRoute(context, EnvelopesPage(backButton: true));
              },
              height: 160,
              width: null,
              margin: const EdgeInsetsDirectional.only(
                  start: 13, end: 13, bottom: 13),
              labelUnder: "envelopes".tr(),
              icon: Icons.mail_outline_rounded,
            );
          }

          return StreamBuilder<List<CategoryWithTotal>>(
            stream: _spent,
            builder: (context, spentSnapshot) {
              final Map<String, double> spentByCategoryPk = {
                for (CategoryWithTotal entry in spentSnapshot.data ?? [])
                  entry.category.categoryPk: entry.total,
              };

              Widget cardFor(TransactionCategory category) {
                // Expenses are stored signed negative, so flip them for an
                // expense category and leave income as it comes.
                final double raw = spentByCategoryPk[category.categoryPk] ?? 0;
                return EnvelopeEntry(
                  category: category,
                  month: month,
                  plan: plan,
                  spent: category.income ? raw : -raw,
                  // Narrow, like the pinned budgets carousel: the slide is
                  // already inset by the viewport fraction, and the card's own
                  // margin on top of that would close the gap the next card
                  // shows through.
                  horizontalPadding: 3,
                );
              }

              return HomePageCardCarousel(
                measureChild: cardFor(planned.first),
                items: [
                  for (TransactionCategory category in planned)
                    cardFor(category)
                ],
              );
            },
          );
        },
      ),
    );
  }
}
