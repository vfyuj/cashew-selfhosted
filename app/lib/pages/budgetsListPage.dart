import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addBudgetPage.dart';
import 'package:cashew_selfhosted/pages/editBudgetPage.dart';
import 'package:cashew_selfhosted/pages/homePage/homePagePlannedVsActual.dart';
import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/struct/budgetVisibility.dart';
import 'package:cashew_selfhosted/struct/mainCategoryBudgets.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/struct/subCategoryBudgetAllocation.dart';
import 'package:cashew_selfhosted/widgets/budgetContainer.dart';
import 'package:cashew_selfhosted/widgets/statusBox.dart';
import 'package:provider/provider.dart';
import 'package:cashew_selfhosted/widgets/navigationSidebar.dart';
import 'package:cashew_selfhosted/widgets/sliverStickyLabelDivider.dart';
import 'package:cashew_selfhosted/widgets/slidingSelectorIncomeExpense.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart'
    hide SliverReorderableList, ReorderableDelayedDragStartListener;
import 'addButton.dart';

class BudgetsListPage extends StatefulWidget {
  const BudgetsListPage({required this.enableBackButton, Key? key})
      : super(key: key);
  final bool enableBackButton;

  @override
  State<BudgetsListPage> createState() => BudgetsListPageState();
}

class BudgetsListPageState extends State<BudgetsListPage> {
  GlobalKey<PageFrameworkState> pageState = GlobalKey();

  // 0 = budgets locked to a single main category, 1 = every other budget.
  int selectedTabIndex = 0;

  void refreshState() {
    setState(() {});
  }

  void scrollToTop() {
    pageState.currentState?.scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      key: pageState,
      title: "budgets".tr(),
      backButton: widget.enableBackButton,
      dragDownToDismiss: widget.enableBackButton,
      horizontalPaddingConstrained: enableDoubleColumn(context) == false,
      actions: [
        IconButton(
          padding: EdgeInsetsDirectional.all(15),
          tooltip: "edit-budgets".tr(),
          onPressed: () {
            pushRoute(
              context,
              EditBudgetPage(),
            );
          },
          icon: Icon(
            appStateSettings["outlinedIcons"]
                ? Icons.edit_outlined
                : Icons.edit_rounded,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
        if (getIsFullScreen(context))
          IconButton(
            padding: EdgeInsetsDirectional.all(15),
            tooltip: "add-budget".tr(),
            onPressed: () {
              pushRoute(
                context,
                AddBudgetPage(
                    routesToPopAfterDelete: RoutesToPopAfterDelete.None),
              );
            },
            icon: Icon(
              appStateSettings["outlinedIcons"]
                  ? Icons.add_outlined
                  : Icons.add_rounded,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            // Slivers clip on the scroll axis, and this selector is the very
            // first sliver in the page - so its top padding alone has to clear
            // however far boxShadowGeneral's blur+spread actually reaches, with
            // real margin to spare, or the top of the shadow gets sliced flat.
            padding: EdgeInsetsDirectional.only(
              top: 34,
              bottom: 20,
              start: getHorizontalPaddingConstrained(context),
              end: getHorizontalPaddingConstrained(context),
            ),
            child: Row(
              children: [
                SizedBox(width: 13),
                Flexible(
                  child: SlidingSelectorIncomeExpense(
                    useHorizontalPaddingConstrained: false,
                    customPadding: EdgeInsetsDirectional.zero,
                    options: const ["main-categories", "custom-budgets"],
                    initialIndex: selectedTabIndex,
                    onSelected: (int index) {
                      setState(() {
                        // This selector reports its tabs one based.
                        selectedTabIndex = index - 1;
                      });
                    },
                  ),
                ),
                SizedBox(width: 13),
              ],
            ),
          ),
        ),
        if (selectedTabIndex == 0) ...[
          // Deliberately not constrained the way the selector above it is: tied
          // to the selector's narrow column the pair turns square on a wide
          // window, which reads badly against a flat tab bar. Left full width it
          // follows the screen, matching the envelope sections below and the
          // home page, where the widget's own 13px padding is all it gets.
          SliverToBoxAdapter(child: HomePagePlannedVsActual()),
          _overAllocationWarning(context),
          _mainCategorySection(context, wantIncome: false, titleKey: "expense"),
          _mainCategorySection(context, wantIncome: true, titleKey: "income"),
        ] else
          _customBudgetsSliver(context),
        SliverToBoxAdapter(
          child: SizedBox(height: 50),
        ),
      ],
    );
  }

  // Warns when a main category's subcategory budgets add up to more than the
  // category's own envelope, so the household does not commit 1200 inside a
  // category budgeted at 1000 without noticing. Nothing is drawn while
  // everything fits - under-allocating is fine.
  //
  // The totals include budgets belonging to other household members, which are
  // not on this screen. That is deliberate (see subCategoryBudgetAllocation),
  // and the copy says so when it applies, because otherwise the numbers would
  // not add up against the visible cards and would read like a bug.
  Widget _overAllocationWarning(BuildContext context) {
    return StreamBuilder<PlannedBudgetTotals>(
      stream: watchPlannedBudgetTotals(),
      initialData: latestPlannedBudgetTotals,
      builder: (context, snapshot) {
        final PlannedBudgetTotals? totals = snapshot.data;
        if (totals == null) return SliverToBoxAdapter();
        final AllWallets allWallets = Provider.of<AllWallets>(context);
        final List<SubCategoryAllocation> over =
            overAllocatedMainCategories(totals, allWallets);
        if (over.isEmpty) return SliverToBoxAdapter();

        final SubCategoryAllocation worst = over.first;
        final String description = over.length == 1
            ? "over-allocated-description".tr(namedArgs: {
                "category": worst.envelope.name,
                "allocated": convertToMoney(allWallets, worst.allocated),
                "budgeted": convertToMoney(allWallets, worst.envelopeAmount),
              })
            : "over-allocated-description-multiple".tr(namedArgs: {
                "count": over.length.toString(),
              });
        final bool anyHidden =
            over.any((SubCategoryAllocation a) => a.hasHidden);

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 13, vertical: 7),
            child: StatusBox(
              title: "over-allocated".tr(),
              description: anyHidden
                  ? description + " " + "over-allocated-includes-hidden".tr()
                  : description,
              color: getColor(context, "expenseAmount"),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.warning_outlined
                  : Icons.warning_rounded,
              onTap: () => _offerToRaiseEnvelopes(context, over, allWallets),
            ),
          ),
        );
      },
    );
  }

  // Tapping the warning offers to raise each over-committed envelope so its
  // subcategory budgets fit exactly. Confirmed one category at a time, and
  // never automatic - it is the household's plan, not a number to correct
  // behind their back.
  Future<void> _offerToRaiseEnvelopes(
    BuildContext context,
    List<SubCategoryAllocation> over,
    AllWallets allWallets,
  ) async {
    for (final SubCategoryAllocation allocation in over) {
      final dynamic raise = await openPopup(
        context,
        title: allocation.envelope.name,
        description: "raise-budget-to-fit-description".tr(namedArgs: {
          "budgeted": convertToMoney(allWallets, allocation.envelopeAmount),
          "allocated": convertToMoney(allWallets, allocation.allocated),
        }),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.trending_up_outlined
            : Icons.trending_up_rounded,
        onSubmitLabel: "raise-budget-to-fit".tr(),
        onSubmit: () => popRoute(context, true),
        onCancelLabel: "keep".tr(),
        onCancel: () => popRoute(context, false),
      );
      if (raise == true) {
        // Routed through withUpdatedAmountHistory, so periods that have
        // already ended keep the target they were set to at the time.
        await raiseEnvelopeToFitAllocation(allocation, allWallets);
      }
    }
  }

  // One of the two stacked sections on the Main Categories tab - expense
  // envelopes above, income envelopes below. Renders nothing when the section
  // has no envelopes, rather than showing an empty header.
  Widget _mainCategorySection(
    BuildContext context, {
    required bool wantIncome,
    required String titleKey,
  }) {
    return StreamBuilder<PlannedBudgetTotals>(
      stream: watchPlannedBudgetTotals(),
      initialData: latestPlannedBudgetTotals,
      builder: (context, snapshot) {
        final PlannedBudgetTotals? totals = snapshot.data;
        if (totals == null) return SliverToBoxAdapter();
        final List<Budget> budgets = totals.budgets
            .where((Budget budget) =>
                budget.income == wantIncome &&
                totals.isMainCategoryBudget(budget))
            .toList();
        if (budgets.isEmpty) return SliverToBoxAdapter();
        return SliverStickyLabelDivider(
          info: titleKey.tr(),
          sliver: SliverPadding(
            padding:
                EdgeInsetsDirectional.symmetric(vertical: 7, horizontal: 13),
            sliver: _budgetsGrid(context, budgets, showAddButton: false),
          ),
        );
      },
    );
  }

  // The Custom tab: every budget that isn't a single-category envelope,
  // flat - not split into expense/income, since a custom budget can span both.
  Widget _customBudgetsSliver(BuildContext context) {
    return StreamBuilder<PlannedBudgetTotals>(
      stream: watchPlannedBudgetTotals(),
      initialData: latestPlannedBudgetTotals,
      builder: (context, snapshot) {
        final PlannedBudgetTotals? totals = snapshot.data;
        if (totals == null) return SliverToBoxAdapter();
        // visibleBudgets drops the other household members' personal budgets.
        // Filtering here, at the point of drawing, rather than in the query --
        // totals.budgets still holds every budget, which is what lets the
        // over-allocation check count allocations the viewer cannot see.
        final List<Budget> budgets = visibleBudgets(totals.budgets
            .where(
                (Budget budget) => totals.isMainCategoryBudget(budget) == false)
            .toList());
        if (budgets.isEmpty) {
          return SliverPadding(
            padding:
                EdgeInsetsDirectional.symmetric(vertical: 7, horizontal: 13),
            sliver: SliverToBoxAdapter(
              child: AddButton(
                onTap: () {},
                openPage: AddBudgetPage(
                  routesToPopAfterDelete: RoutesToPopAfterDelete.PreventDelete,
                ),
                height: 180,
              ),
            ),
          );
        }
        return SliverPadding(
          padding: EdgeInsetsDirectional.symmetric(vertical: 7, horizontal: 13),
          sliver: _budgetsGrid(context, budgets, showAddButton: true),
        );
      },
    );
  }

  Widget _budgetsGrid(
    BuildContext context,
    List<Budget> budgets, {
    required bool showAddButton,
  }) {
    final int itemCount = budgets.length + (showAddButton ? 1 : 0);
    Widget addButton({double? height}) {
      return AddButton(
        onTap: () {},
        openPage: AddBudgetPage(
          routesToPopAfterDelete: RoutesToPopAfterDelete.PreventDelete,
        ),
        height: height,
      );
    }

    if (enableDoubleColumn(context)) {
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 600.0,
          mainAxisExtent: 190,
          mainAxisSpacing: 15.0,
          crossAxisSpacing: 15.0,
          childAspectRatio: 5,
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            if (showAddButton && index == budgets.length) return addButton();
            return BudgetContainer(budget: budgets[index]);
          },
          childCount: itemCount,
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          if (showAddButton && index == budgets.length) {
            return addButton(height: 180);
          }
          return Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 16.0),
            child: BudgetContainer(
              budget: budgets[index],
              squishInactiveBudgetContainerHeight: true,
            ),
          );
        },
        childCount: itemCount,
      ),
    );
  }
}
