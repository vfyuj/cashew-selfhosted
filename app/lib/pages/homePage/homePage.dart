import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/generatePreviewData.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageHeatmap.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageLineGraph.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageNetWorth.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageObjectives.dart';
import 'package:cashew_selfhosted/pages/homePage/homePagePieChart.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageWalletList.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageWalletSwitcher.dart';
import 'package:cashew_selfhosted/pages/homePage/homeTransactions.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageUsername.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageBudgets.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageUpcomingTransactions.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageAllSpendingSummary.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageEnvelopes.dart';
import 'package:cashew_selfhosted/pages/homePage/homePagePlannedVsActual.dart';
import 'package:cashew_selfhosted/pages/editHomePage.dart';
import 'package:cashew_selfhosted/pages/settingsPage.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageCreditDebts.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/animatedExpanded.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/selectedTransactionsAppBar.dart';
import 'package:cashew_selfhosted/widgets/util/keepAliveClientMixin.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/transactionEntry/swipeToSelectTransactions.dart';
import 'package:cashew_selfhosted/widgets/viewAllTransactionsButton.dart';
import 'package:cashew_selfhosted/widgets/navigationSidebar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cashew_selfhosted/widgets/scrollbarWrap.dart';
import 'package:cashew_selfhosted/widgets/slidingSelectorIncomeExpense.dart';
import 'package:cashew_selfhosted/widgets/linearGradientFadedEdges.dart';
import 'package:cashew_selfhosted/widgets/pullDownToRefreshSync.dart';
import 'package:cashew_selfhosted/widgets/util/rightSideClipper.dart';
import 'package:flutter/services.dart';
import 'package:cashew_selfhosted/widgets/util/checkWidgetLaunch.dart';
import 'package:flutter/foundation.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    Key? key,
  }) : super(key: key);

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with TickerProviderStateMixin {
  void refreshState() {
    setState(() {});
  }

  void scrollToTop({int duration = 1200}) {
    // if (_scrollController.offset <= 0) {
    //   pushRoute(context, EditHomePage());
    // } else {

    // }
    _scrollController.animateTo(0,
        duration: Duration(
            milliseconds:
                (getPlatform() == PlatformOS.isIOS ? duration * 0.2 : duration)
                    .round()),
        curve: getPlatform() == PlatformOS.isIOS
            ? Curves.easeInOut
            : Curves.elasticOut);
  }

  bool showElevation = false;
  late ScrollController _scrollController;
  late AnimationController _animationControllerHeader;
  late AnimationController _animationControllerHeader2;
  int selectedSlidingSelector = 1;

  void initState() {
    super.initState();
    _animationControllerHeader = AnimationController(vsync: this, value: 1);
    _animationControllerHeader2 = AnimationController(vsync: this, value: 1);

    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
  }

  _scrollListener() {
    double percent = _scrollController.offset / (200);
    if (percent <= 1) {
      double offset = _scrollController.offset;
      if (percent >= 1) offset = 0;
      _animationControllerHeader.value = 1 - offset / (200);
      _animationControllerHeader2.value = 1 - offset * 2 / (200);
    }
  }

  @override
  void dispose() {
    _animationControllerHeader.dispose();
    _animationControllerHeader2.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool areAllDisabledAfterTransactionsList(
      Map<String, Widget?> homePageSections) {
    int countAfter = -1;
    for (String sectionKey in appStateSettings["homePageOrder"]) {
      if (sectionKey == "transactionsList" &&
          homePageSections[sectionKey] != null) {
        countAfter = 0;
      } else if (countAfter == 0 && homePageSections[sectionKey] != null) {
        countAfter++;
      }
    }
    return countAfter == 0;
  }

  @override
  Widget build(BuildContext context) {
    bool showUsername = appStateSettings["username"] != "";
    bool showGreeting = appStateSettings["enableGreetingMessage"] == true;
    Widget slidingSelector = GestureDetector(
      onLongPress: () async {
        HapticFeedback.heavyImpact();
        await openBottomSheet(
          context,
          TransactionsListHomePageBottomSheetSettings(),
        );
        homePageStateKey.currentState?.refreshState();
      },
      child: SlidingSelectorIncomeExpense(
          options: appStateSettings[
                      "homePageTransactionsListIncomeAndExpenseOnly"] ==
                  true
              ? null
              : ["all", "outgoing", "incoming"],
          useHorizontalPaddingConstrained: false,
          onSelected: (index) {
            setState(() {
              selectedSlidingSelector = index;
            });
          }),
    );
    Widget? homePageTransactionsList =
        isHomeScreenSectionEnabled(context, "showTransactionsList") == true
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  slidingSelector,
                  SizedBox(height: 8),
                  HomeTransactions(
                      selectedSlidingSelector: selectedSlidingSelector),
                  SizedBox(height: 7),
                  Center(
                    child: ViewAllTransactionsButton(),
                  ),
                  if (enableDoubleColumn(context)) SizedBox(height: 35),
                ],
              )
            : null;
    if (homePageTransactionsList != null)
      homePageTransactionsList = enableDoubleColumn(context)
          ? KeepAliveClientMixin(
              child: homePageTransactionsList,
            )
          : KeepAliveClientMixin(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 15),
                child: homePageTransactionsList,
              ),
            );

    Map<String, Widget?> homePageSections = {
      "wallets": isHomeScreenSectionEnabled(context, "showWalletSwitcher")
          ? HomePageWalletSwitcher()
          : null,
      "walletsList": isHomeScreenSectionEnabled(context, "showWalletList")
          ? HomePageWalletList()
          : null,
      "budgets": isHomeScreenSectionEnabled(context, "showPinnedBudgets")
          ? HomePageBudgets()
          : null,
      "envelopes": isHomeScreenSectionEnabled(context, "showEnvelopes")
          ? HomePageEnvelopes()
          : null,
      "plannedVsActual":
          isHomeScreenSectionEnabled(context, "showPlannedVsActual")
              ? HomePagePlannedVsActual()
              : null,
      "overdueUpcoming":
          isHomeScreenSectionEnabled(context, "showOverdueUpcoming")
              ? HomePageUpcomingTransactions()
              : null,
      "allSpendingSummary":
          isHomeScreenSectionEnabled(context, "showAllSpendingSummary")
              ? HomePageAllSpendingSummary()
              : null,
      "netWorth": isHomeScreenSectionEnabled(context, "showNetWorth")
          ? HomePageNetWorth()
          : null,
      "objectives": isHomeScreenSectionEnabled(context, "showObjectives")
          ? HomePageObjectives(objectiveType: ObjectiveType.goal)
          : null,
      "creditDebts": isHomeScreenSectionEnabled(context, "showCreditDebt")
          ? HomePageCreditDebts()
          : null,
      "objectiveLoans":
          isHomeScreenSectionEnabled(context, "showObjectiveLoans")
              ? HomePageObjectives(objectiveType: ObjectiveType.loan)
              : null,
      "spendingGraph": isHomeScreenSectionEnabled(context, "showSpendingGraph")
          ? HomePageLineGraph(selectedSlidingSelector: selectedSlidingSelector)
          : null,
      "pieChart": isHomeScreenSectionEnabled(context, "showPieChart")
          ? HomePagePieChart()
          : null,
      "heatMap": isHomeScreenSectionEnabled(context, "showHeatMap")
          ? HomePageHeatMap()
          : null,
      "transactionsList": homePageTransactionsList ?? SizedBox.shrink(),
    };
    bool showWelcomeBanner =
        isHomeScreenSectionEnabled(context, "showUsernameWelcomeBanner");
    bool useSmallBanner = showWelcomeBanner == false;

    List<String> homePageSectionsFullScreenCenter = [];
    List<String> homePageSectionsFullScreenLeft = [];
    List<String> homePageSectionsFullScreenRight = [];

    String section = "";

    for (String item
        in appStateSettings[getHomePageOrderSettingsKey(context)]) {
      if (item == "ORDER:LEFT") {
        section = item;
      } else if (item == "ORDER:RIGHT") {
        section = item;
      } else if (section == "ORDER:LEFT") {
        homePageSectionsFullScreenLeft.add(item);
      } else if (section == "ORDER:RIGHT") {
        homePageSectionsFullScreenRight.add(item);
      } else {
        homePageSectionsFullScreenCenter.add(item);
      }
    }

    return SwipeToSelectTransactions(
      listID: "0",
      child: PullDownToRefreshSync(
        scrollController: _scrollController,
        child: Stack(
          children: [
            AndroidOnly(child: CheckWidgetLaunch()),
            AndroidOnly(child: RenderHomePageWidgets()),
            Scaffold(
              resizeToAvoidBottomInset: false,
              body: ScrollbarWrap(
                scrollController: _scrollController,
                child: ListView(
                  controller: _scrollController,
                  children: [
                    PreviewDemoWarning(),
                    if (useSmallBanner) SizedBox(height: 13),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        useSmallBanner
                            ? Expanded(
                                child: HomePageWelcomeBannerSmall(
                                  showUsername: showUsername,
                                  showGreeting: showGreeting,
                                  username: appStateSettings["username"] ?? "",
                                ),
                              )
                            : SizedBox.shrink(),
                        Tooltip(
                          message: "edit-home".tr(),
                          child: IconButton(
                            padding: EdgeInsetsDirectional.all(15),
                            onPressed: () {
                              pushRoute(context, EditHomePage());
                            },
                            icon: Icon(appStateSettings["outlinedIcons"]
                                ? Icons.more_vert_outlined
                                : Icons.more_vert_rounded),
                          ),
                        ),
                      ],
                    ),
                    // Wipe all remaining pixels off - sometimes graphics artifacts are left behind
                    Container(
                        height: 1,
                        color: Theme.of(context).colorScheme.background),

                    showWelcomeBanner
                        ? ConstrainedBox(
                            constraints: BoxConstraints(
                                minHeight: getExpandedHeaderHeight(
                                        context, null,
                                        isHomePageSpace: true) /
                                    1.34),
                            child: Container(
                              // Subtract one (1) here because of the thickness of the wiper above
                              alignment: AlignmentDirectional.bottomStart,
                              padding: EdgeInsetsDirectional.only(
                                  start: 9,
                                  bottom: enableDoubleColumn(context) ? 10 : 17,
                                  end: 9),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  HomePageUsername(
                                    animationControllerHeader:
                                        _animationControllerHeader,
                                    animationControllerHeader2:
                                        _animationControllerHeader2,
                                    showUsername: showUsername,
                                    showGreeting: showGreeting,
                                    enterNameBottomSheet: enterNameBottomSheet,
                                    username:
                                        appStateSettings["username"] ?? "",
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SizedBox(height: 5),
                    // Not full screen
                    if (enableDoubleColumn(context) != true) ...[
                      for (String sectionKey
                          in appStateSettings["homePageOrder"])
                        homePageSections[sectionKey] ?? SizedBox.shrink(),
                    ],
                    // Full screen top section
                    if (enableDoubleColumn(context) == true) ...[
                      for (String sectionKey
                          in appStateSettings["homePageOrderFullScreen"])
                        if (homePageSectionsFullScreenCenter
                            .contains(sectionKey))
                          homePageSections[sectionKey] ?? SizedBox.shrink()
                    ],
                    // Full screen bottom split section
                    if (enableDoubleColumn(context) == true)
                      LayoutBuilder(builder: (context, constraints) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Column(
                                children: [
                                  for (String sectionKey in appStateSettings[
                                      "homePageOrderFullScreen"])
                                    if (homePageSectionsFullScreenLeft
                                        .contains(sectionKey))
                                      LinearGradientFadedEdges(
                                        enableStart: false,
                                        enableBottom: false,
                                        enableTop: false,
                                        child: ClipRRect(
                                          clipper: RightSideClipper(),
                                          child: homePageSections[sectionKey] ??
                                              SizedBox.shrink(),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: Column(
                                children: [
                                  for (String sectionKey in appStateSettings[
                                      "homePageOrderFullScreen"])
                                    if (homePageSectionsFullScreenRight
                                        .contains(sectionKey))
                                      LinearGradientFadedEdges(
                                        enableEnd: false,
                                        enableBottom: false,
                                        enableTop: false,
                                        child: ClipRRect(
                                          clipper: RightSideClipper(),
                                          child: homePageSections[sectionKey] ??
                                              SizedBox.shrink(),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    SizedBox(
                      height: enableDoubleColumn(context) == true
                          ? 40
                          : areAllDisabledAfterTransactionsList(
                                  homePageSections)
                              ? 25
                              : 73,
                    ),
                    // Wipe all remaining pixels off - sometimes graphics artifacts are left behind
                    Container(
                        height: 1,
                        color: Theme.of(context).colorScheme.background),
                  ],
                ),
              ),
            ),
            SelectedTransactionsAppBar(
              pageID: "0",
            ),
          ],
        ),
      ),
    );
  }
}
