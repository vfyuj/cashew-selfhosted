import 'package:carousel_slider/carousel_slider.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addButton.dart';
import 'package:cashew_selfhosted/pages/envelopesPage.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/widgets/envelopePlanBuilder.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart' show getIsFullScreen;
import 'package:cashew_selfhosted/widgets/util/keepAliveClientMixin.dart';
import 'package:cashew_selfhosted/widgets/util/widgetSize.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// This month's envelopes on the home page, swiped horizontally -- the same
// shape the pinned budgets carousel has, and the same card the envelopes page
// draws, so nothing about an envelope looks different depending on where you
// meet it.
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
  double height = 0;

  // Both sides of the ledger in one query: the card decides what a number means
  // from its category's income flag, not from the query.
  Stream<List<CategoryWithTotal>>? _spent;
  AllWallets? _spentForWallets;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    if (_spent != null && _spentForWallets == allWallets) return;
    _spentForWallets = allWallets;
    final DateTime month = envelopePeriodStart(DateTime.now());
    try {
      _spent = database.watchTotalSpentInEachCategoryInTimeRangeFromCategories(
        allWallets: allWallets,
        start: month,
        end: DateTime(month.year, month.month + 1, 0),
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

              return Stack(
                children: [
                  // Measures one real card off screen, the same trick the
                  // pinned budgets carousel uses: the carousel needs a fixed
                  // height and the card's is whatever its text wraps to.
                  IgnorePointer(
                    child: Visibility(
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Opacity(
                        opacity: 0,
                        child: WidgetSize(
                          onChange: (Size size) {
                            if (size.height == height) return;
                            setState(() {
                              height = size.height;
                            });
                          },
                          child: cardFor(planned.first),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 13),
                    child: getIsFullScreen(context)
                        ? SizedBox(
                            height: height,
                            child: ListView(
                              addAutomaticKeepAlives: true,
                              clipBehavior: Clip.none,
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsetsDirectional.symmetric(
                                  horizontal: 10),
                              children: [
                                for (TransactionCategory category in planned)
                                  SizedBox(width: 500, child: cardFor(category))
                              ],
                            ),
                          )
                        : CarouselSlider(
                            options: CarouselOptions(
                              height: height,
                              enableInfiniteScroll: false,
                              enlargeCenterPage: true,
                              enlargeStrategy: CenterPageEnlargeStrategy.zoom,
                              viewportFraction: 0.95,
                              clipBehavior: Clip.none,
                              enlargeFactor: 0.3,
                            ),
                            items: [
                              for (TransactionCategory category in planned)
                                cardFor(category)
                            ],
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
