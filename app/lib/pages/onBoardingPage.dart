import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/generatePreviewData.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/pages/addCategoryPage.dart';
import 'package:cashew_selfhosted/pages/addWalletPage.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/languageMap.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/categoryIcon.dart';
import 'package:cashew_selfhosted/widgets/envelopePlanBuilder.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/linearGradientFadedEdges.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/selectAmount.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/viewAllTransactionsButton.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/database/initializeDefaultDatabase.dart';

import 'package:cashew_selfhosted/widgets/pageIndicator.dart';

/// The system-reserved balance-correction / transfer category. It deliberately
/// gets no envelope (`isEnvelopeEligible` in struct/categoryEnvelopes.dart) and
/// is bookkeeping rather than something to plan, so onboarding never shows it.
const String _balanceCorrectionCategoryPk = balanceCorrectionCategoryPk;

class OnBoardingPage extends StatelessWidget {
  const OnBoardingPage({
    Key? key,
    this.popNavigationWhenDone = false,
    this.showPreviewDemoButton = true,
  }) : super(key: key);

  final bool popNavigationWhenDone;
  final bool showPreviewDemoButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        body: OnBoardingPageBody(
            popNavigationWhenDone: popNavigationWhenDone,
            showPreviewDemoButton: showPreviewDemoButton));
  }
}

class OnBoardingPageBody extends StatefulWidget {
  const OnBoardingPageBody({
    Key? key,
    this.popNavigationWhenDone = false,
    this.showPreviewDemoButton = true,
  }) : super(key: key);
  final bool popNavigationWhenDone;
  final bool showPreviewDemoButton;

  @override
  State<OnBoardingPageBody> createState() => OnBoardingPageBodyState();
}

class OnBoardingPageBodyState extends State<OnBoardingPageBody> {
  final PageController controller = PageController();

  bool showImage = false;
  final Image imageLanding1 = Image(
    image: AssetImage("assets/landing/Graph.png"),
  );
  final Image imageLanding2 = Image(
    image: AssetImage("assets/landing/BankOrPig.png"),
  );
  final Image imageLanding3 = Image(
    image: AssetImage("assets/landing/PigBank.png"),
  );

  @override
  void didChangeDependencies() {
    precacheImage(imageLanding1.image, context);
    precacheImage(imageLanding2.image, context);
    precacheImage(imageLanding3.image, context);
    super.didChangeDependencies();
  }

  /// Finishes onboarding.
  ///
  /// Deliberately creates no budget. What the income and spending steps fill in
  /// are envelopes -- one amount per category for this month -- and a catch-all
  /// budget on top of them would just be an extra row on a page this flow never
  /// mentions.
  nextNavigation({bool generatePreview = false}) async {
    if (generatePreview) {
      openLoadingPopup(context);
      await generatePreviewData();
      popRoute(context);
    }
    if (widget.popNavigationWhenDone) {
      popRoute(context);
    } else {
      updateSettings("hasOnboarded", true,
          pagesNeedingRefresh: [], updateGlobalState: true);
    }
  }

  FocusNode _focusNode = FocusNode();
  late FocusAttachment _focusAttachment;

  @override
  void initState() {
    super.initState();
    _focusAttachment = _focusNode.attach(context, onKeyEvent: (node, event) {
      if (event.logicalKey.keyLabel == "Go Back" ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        if (widget.popNavigationWhenDone) nextNavigation();
      } else if (event.runtimeType == KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        nextOnBoardPage();
      } else if (event.runtimeType == KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        previousOnBoardPage();
      }
      return KeyEventResult.handled;
    });
    _focusNode.requestFocus();

    Future.delayed(Duration.zero, () async {
      // Functions to run after entire UI loaded - landing page
      // Run here too, so the user has an account and the default categories
      // before the steps below try to show them
      // We need to run this after the UI is loaded - after translations are loaded
      await initializeDefaultDatabase();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void nextOnBoardPage() {
    if ((controller.page?.round().toInt() ?? 0) + 1 == numPages) {
      nextNavigation();
    } else {
      controller.nextPage(
        duration: Duration(milliseconds: 1100),
        curve: ElasticOutCurve(1.3),
      );
    }
  }

  void previousOnBoardPage() {
    controller.previousPage(
      duration: Duration(milliseconds: 1100),
      curve: ElasticOutCurve(1.3),
    );
  }

  /// Sets a category's planned amount for this month by writing its envelope.
  ///
  /// Written once after the sheet closes rather than on every keystroke:
  /// `SelectAmount` reports each edit as it is typed, and every write is a row
  /// the sync feed then has to carry.
  Future<void> selectEnvelopeAmount(
      TransactionCategory category, double currentAmount) async {
    double? enteredAmount;
    await openBottomSheet(
      context,
      fullSnap: true,
      PopupFramework(
        title: category.name,
        hasPadding: false,
        underTitleSpace: false,
        child: SelectAmount(
          onlyShowCurrencyIcon: true,
          allowZero: true,
          amountPassed: currentAmount == 0 ? "" : currentAmount.toString(),
          setSelectedAmount: (amount, _) {
            enteredAmount = amount.abs();
          },
          next: () async {
            popRoute(context);
          },
          nextLabel: "set-amount".tr(),
          padding: EdgeInsetsDirectional.symmetric(horizontal: 18),
        ),
      ),
    );
    if (enteredAmount != null && enteredAmount != currentAmount) {
      await database.createOrUpdateCategoryEnvelope(newCategoryEnvelope(
        categoryPk: category.categoryPk,
        periodStart: DateTime.now(),
        amount: enteredAmount!,
        // The pad shows the primary account's currency and there is no picker
        // here on purpose - onboarding is a list of numbers typed quickly, not
        // a place to decide which account each category is planned in.
        walletPk: appStateSettings["selectedWalletPk"],
      ));
    }
  }

  /// Every step after the first is optional, per the onboarding's own rule that
  /// nothing here is mandatory. The forward arrow already does this -- this is
  /// the same action said out loud, so skipping never depends on spotting an
  /// icon.
  ///
  /// Placed inline at the end of a step rather than floated like page one's
  /// buttons: these steps grow with the number of accounts or categories on
  /// screen, and a floating button would sit on top of them.
  Widget skipStepButton() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 25),
      child: LowKeyButton(
        onTap: nextOnBoardPage,
        text: "onboarding-skip-step".tr(),
      ),
    );
  }

  Widget onBoardingTitle(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
      child: TextFont(
        text: text,
        fontWeight: FontWeight.bold,
        textAlign: TextAlign.center,
        fontSize: 25,
        maxLines: 5,
      ),
    );
  }

  /// Explanatory copy.
  ///
  /// Width-capped rather than left to fill the window: on a desktop browser an
  /// unconstrained paragraph runs the full width of the screen, which is
  /// unreadable next to the narrow controls under it. The copy itself puts each
  /// sentence on its own line (literal newlines in the strings), so `maxLines`
  /// has to allow for wrapping on top of those breaks.
  Widget onBoardingBody(String text) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
          child: TextFont(
            text: text,
            textAlign: TextAlign.center,
            fontSize: 16,
            maxLines: 12,
          ),
        ),
      ),
    );
  }

  Widget onBoardingFootnote(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
      child: TextFont(
        text: text,
        textAlign: TextAlign.center,
        fontSize: 15,
        maxLines: 5,
        textColor: getColor(context, "black").withOpacity(0.35),
      ),
    );
  }

  Widget onBoardingImage(Image image) {
    return Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).height <=
                  MediaQuery.sizeOf(context).width
              ? MediaQuery.sizeOf(context).height * 0.5
              : 300),
      child: image,
    );
  }

  /// Keeps the interactive lists on the account, category and planning steps
  /// from stretching edge to edge on a desktop window, where the rest of the
  /// onboarding copy is already centered and narrow.
  Widget constrainedColumn(List<Widget> children) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  Color get rowColor => appStateSettings["materialYou"]
      ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5)
      : getColor(context, "lightDarkAccent");

  Widget accountRow(WalletWithDetails walletWithDetails) {
    final TransactionWallet wallet = walletWithDetails.wallet;
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Tappable(
        color: rowColor,
        borderRadius: 15,
        onTap: () {
          pushRoute(
            context,
            AddWalletPage(
              wallet: wallet,
              routesToPopAfterDelete: RoutesToPopAfterDelete.One,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 15, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFont(
                      text: wallet.name,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      maxLines: 2,
                    ),
                    // Shown in the account's own currency, not converted:
                    // this is "what is in this account", and the row already
                    // names the currency it is counted in.
                    TextFont(
                      text: convertToMoney(
                            allWallets,
                            walletWithDetails.totalSpent ?? 0,
                            currencyKey: wallet.currency,
                            decimals: wallet.decimals,
                          ) +
                          " " +
                          (wallet.currency ?? "").toUpperCase(),
                      fontSize: 14,
                      textColor: getColor(context, "black").withOpacity(0.5),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                appStateSettings["outlinedIcons"]
                    ? Icons.edit_outlined
                    : Icons.edit_rounded,
                size: 18,
                color: getColor(context, "black").withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget envelopeRow(TransactionCategory category, double amount) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Tappable(
        color: rowColor,
        borderRadius: 15,
        onTap: () => selectEnvelopeAmount(category, amount),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 12, vertical: 6),
          child: Row(
            children: [
              CategoryIcon(
                category: category,
                size: 24,
                sizePadding: 12,
                margin: EdgeInsetsDirectional.zero,
                canEditByLongPress: false,
              ),
              SizedBox(width: 12),
              Expanded(
                child: TextFont(
                  text: category.name,
                  fontSize: 16,
                  maxLines: 2,
                ),
              ),
              SizedBox(width: 8),
              TextFont(
                text: convertToMoney(allWallets, amount),
                fontSize: 17,
                fontWeight: FontWeight.bold,
                textColor: amount == 0
                    ? getColor(context, "black").withOpacity(0.35)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A line in the plan summary. [signed] colours the amount by its sign --
  /// green when the plan leaves something over, red when it is overcommitted.
  Widget totalRow(String label, double amount, {bool signed = false}) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TextFont(
              text: label,
              fontSize: signed ? 16 : 15,
              fontWeight: signed ? FontWeight.bold : FontWeight.normal,
              maxLines: 2,
              textColor:
                  signed ? null : getColor(context, "black").withOpacity(0.6),
            ),
          ),
          SizedBox(width: 8),
          TextFont(
            text: convertToMoney(allWallets, amount),
            fontSize: signed ? 16 : 15,
            fontWeight: signed ? FontWeight.bold : FontWeight.normal,
            textColor: signed
                ? (amount < 0
                    ? getColor(context, "expenseAmount")
                    : getColor(context, "incomeAmount"))
                : getColor(context, "black").withOpacity(0.6),
          ),
        ],
      ),
    );
  }

  /// One half of the plan -- income categories or expense categories -- as one
  /// row per main category, each writing that category's envelope for this
  /// month.
  ///
  /// [footerBuilder] receives the total of the rows shown and the whole of this
  /// month's planned income.
  Widget envelopeList({
    required bool income,
    Widget Function(double listedTotal, double plannedIncome)? footerBuilder,
  }) {
    final DateTime thisMonth = envelopePeriodStart(DateTime.now());
    return EnvelopePlanBuilder(
      builder: (context, plan) {
        final List<TransactionCategory> categories =
            plan.categoriesOfType(income: income);

        double listedTotal = 0;
        final List<Widget> rows = [];
        for (TransactionCategory category in categories) {
          final double amount =
              plan.amountFor(category.categoryPk, thisMonth) ?? 0;
          listedTotal += amount;
          rows.add(envelopeRow(category, amount));
        }

        final double plannedIncome =
            plan.totalPlanned(income: true, periodStart: thisMonth);

        // Deleting every income category on the previous step is allowed, and
        // leaves this step with nothing to fill in and no explanation of why.
        // Say so, and offer the way back rather than a blank space.
        if (rows.isEmpty) {
          return constrainedColumn([
            onBoardingFootnote(income
                ? "onboarding-no-income-categories".tr()
                : "onboarding-no-expense-categories".tr()),
            SizedBox(height: 12),
            LowKeyButton(
              onTap: () {
                pushRoute(
                  context,
                  AddCategoryPage(
                    routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                    initiallyIsExpense: income == false,
                  ),
                );
              },
              text: income
                  ? "onboarding-add-income-category".tr()
                  : "onboarding-add-expense-category".tr(),
            ),
          ]);
        }

        return constrainedColumn([
          ...rows,
          if (footerBuilder != null) footerBuilder(listedTotal, plannedIncome),
        ]);
      },
    );
  }

  int numPages = 5;
  @override
  Widget build(BuildContext context) {
    _focusAttachment.reparent();
    final List<Widget> children = [
      OnBoardPage(
        widgets: [
          onBoardingImage(imageLanding1),
          SizedBox(height: 15),
          onBoardingTitle(
              "onboarding-title-1".tr(namedArgs: {"app": globalAppName})),
          SizedBox(height: 15),
          onBoardingBody("onboarding-info-1".tr()),
          // Reserves room for the two floating buttons below.
          SizedBox(height: 110),
        ],
        bottomWidget: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showPreviewDemoButton)
              PreviewDemoButton(
                nextNavigation: nextNavigation,
              ),
            if (widget.showPreviewDemoButton) SizedBox(height: 10),
            // Ends onboarding outright, rather than advancing a page. Everything
            // the remaining steps set up has a sane default already, so there is
            // no reason to make someone tap through five screens to reach the app.
            LowKeyButton(
              onTap: () => nextNavigation(),
              text: "onboarding-skip-setup".tr(),
            ),
          ],
        ),
      ),
      OnBoardPage(
        widgets: [
          onBoardingImage(imageLanding2),
          SizedBox(height: 15),
          onBoardingTitle("onboarding-title-2".tr()),
          SizedBox(height: 15),
          onBoardingBody("onboarding-account-explainer".tr()),
          SizedBox(height: 20),
          StreamBuilder<List<WalletWithDetails>>(
            stream: database.watchAllWalletsWithDetails(),
            builder: (context, snapshot) {
              // initializeDefaultDatabase() creates the first account off the
              // first frame, so an empty list here is the normal state for a
              // moment -- render the add button and let the stream fill in.
              return constrainedColumn([
                for (WalletWithDetails wallet in snapshot.data ?? [])
                  accountRow(wallet),
                SizedBox(height: 7),
                LowKeyButton(
                  onTap: () {
                    pushRoute(
                      context,
                      AddWalletPage(
                        routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                      ),
                    );
                  },
                  text: "add-account".tr(),
                ),
              ]);
            },
          ),
          SizedBox(height: 20),
          onBoardingFootnote("onboarding-info-2-1".tr()),
          skipStepButton(),
        ],
      ),
      // Categories come before the two planning steps on purpose: every main
      // category has exactly one budget, so this list *is* the shape of the plan
      // the next two steps fill in.
      OnBoardPage(
        widgets: [
          SizedBox(height: 15),
          onBoardingTitle("onboarding-title-categories".tr()),
          SizedBox(height: 15),
          onBoardingBody("onboarding-info-categories".tr()),
          SizedBox(height: 15),
          StreamBuilder<List<TransactionCategory>>(
            stream: database.watchAllCategories(),
            builder: (context, snapshot) {
              List<TransactionCategory> categories = (snapshot.data ?? [])
                  .where((category) =>
                      category.categoryPk != _balanceCorrectionCategoryPk)
                  .toList();
              return constrainedColumn([
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (TransactionCategory category in categories)
                      CategoryIcon(
                        key: ValueKey(category.categoryPk),
                        category: category,
                        size: 32,
                        sizePadding: 16,
                        label: true,
                        labelSize: 11,
                        canEditByLongPress: false,
                        onTap: () {
                          pushRoute(
                            context,
                            AddCategoryPage(
                              category: category,
                              routesToPopAfterDelete:
                                  RoutesToPopAfterDelete.One,
                            ),
                          );
                        },
                      ),
                  ],
                ),
                SizedBox(height: 12),
                LowKeyButton(
                  onTap: () {
                    pushRoute(
                      context,
                      AddCategoryPage(
                        routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                      ),
                    );
                  },
                  text: "add-category".tr(),
                ),
              ]);
            },
          ),
          SizedBox(height: 20),
          onBoardingFootnote("onboarding-info-2-1".tr()),
          skipStepButton(),
        ],
      ),
      OnBoardPage(
        widgets: [
          onBoardingImage(imageLanding3),
          SizedBox(height: 15),
          onBoardingTitle("onboarding-title-income".tr()),
          SizedBox(height: 15),
          onBoardingBody("onboarding-info-income".tr()),
          SizedBox(height: 20),
          envelopeList(income: true),
          SizedBox(height: 20),
          onBoardingFootnote("onboarding-info-2-1".tr()),
          skipStepButton(),
        ],
      ),
      OnBoardPage(
        widgets: [
          SizedBox(height: 15),
          onBoardingTitle("onboarding-title-budget".tr()),
          SizedBox(height: 15),
          onBoardingBody("onboarding-info-budget".tr()),
          SizedBox(height: 20),
          envelopeList(
            income: false,
            footerBuilder: (double plannedExpenses, double plannedIncome) =>
                Padding(
              padding: const EdgeInsetsDirectional.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  totalRow("onboarding-planned-expenses".tr(), plannedExpenses),
                  SizedBox(height: 4),
                  totalRow("planned-income".tr(), plannedIncome),
                  SizedBox(height: 8),
                  totalRow("onboarding-budget-plan-balance".tr(),
                      plannedIncome - plannedExpenses,
                      signed: true),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),
          onBoardingFootnote("onboarding-info-2-1".tr()),
          SizedBox(height: 25),
          IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 8.0),
              child: Button(
                label: "lets-go".tr(),
                onTap: () {
                  nextNavigation();
                },
                expandedLayout: false,
              ),
            ),
          ),
        ],
      ),
    ];

    if (numPages != children.length)
      print("Error: onboarding pages mismatch in length!");

    return Stack(
      children: [
        PageView(
          controller: controller,
          children: children,
        ),
        PositionedDirectional(
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 100,
              width: 1000,
              foregroundDecoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.background.withOpacity(0.0),
                    Theme.of(context).colorScheme.background,
                  ],
                  begin: AlignmentDirectional.topCenter,
                  end: AlignmentDirectional.bottomCenter,
                  stops: [0.1, 1],
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.bottomCenter,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 18,
                vertical: 15,
              ),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedBuilder(
                      animation: controller,
                      builder: (BuildContext context, Widget? child) {
                        int currentIndex =
                            controller.page?.round().toInt() ?? 0;
                        return AnimatedOpacity(
                          opacity: currentIndex <= 0 ? 0 : 1,
                          duration: Duration(milliseconds: 200),
                          child: ButtonIcon(
                            onTap: () {
                              previousOnBoardPage();
                            },
                            icon: getPlatform() == PlatformOS.isIOS
                                ? appStateSettings["outlinedIcons"]
                                    ? Icons.chevron_left_outlined
                                    : Icons.chevron_left_rounded
                                : appStateSettings["outlinedIcons"]
                                    ? Icons.arrow_back_outlined
                                    : Icons.arrow_back_rounded,
                            size: 50,
                            padding: getIsFullScreen(context) == false
                                ? EdgeInsetsDirectional.all(3)
                                : EdgeInsetsDirectional.all(6),
                          ),
                        );
                      },
                    ),
                    PageIndicator(
                        controller: controller, itemCount: children.length),
                    AnimatedBuilder(
                      animation: controller,
                      builder: (BuildContext context, Widget? child) {
                        int currentIndex =
                            controller.page?.round().toInt() ?? 0;
                        return AnimatedOpacity(
                          opacity: getPlatform() == PlatformOS.isIOS
                              ? 1
                              : currentIndex >= children.length - 1
                                  ? 0
                                  : 1,
                          duration: Duration(milliseconds: 200),
                          child: ButtonIcon(
                            onTap: () => nextOnBoardPage(),
                            icon: getPlatform() == PlatformOS.isIOS
                                ? appStateSettings["outlinedIcons"]
                                    ? Icons.chevron_right_outlined
                                    : Icons.chevron_right_rounded
                                : appStateSettings["outlinedIcons"]
                                    ? Icons.arrow_forward_outlined
                                    : Icons.arrow_forward_rounded,
                            size: 50,
                            padding: getIsFullScreen(context) == false
                                ? EdgeInsetsDirectional.all(3)
                                : EdgeInsetsDirectional.all(6),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class OnBoardPage extends StatelessWidget {
  const OnBoardPage({Key? key, required this.widgets, this.bottomWidget})
      : super(key: key);
  final List<Widget> widgets;
  final Widget? bottomWidget;
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: LinearGradientFadedEdges(
            gradientSize: 20,
            enableTop: getPlatform() == PlatformOS.isIOS,
            enableBottom: getPlatform() == PlatformOS.isIOS,
            enableStart: false,
            enableEnd: false,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                Column(
                  children: [
                    SizedBox(height: 20),
                    ...widgets,
                    SizedBox(height: 80),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
              bottom: 60 + MediaQuery.paddingOf(context).bottom),
          child: Align(
            alignment: AlignmentDirectional.bottomCenter,
            child: bottomWidget ?? SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
