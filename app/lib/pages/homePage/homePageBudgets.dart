import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addBudgetPage.dart';
import 'package:cashew_selfhosted/pages/editBudgetPage.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/homePageCardCarousel.dart';
import 'package:cashew_selfhosted/widgets/util/keepAliveClientMixin.dart';
import 'package:cashew_selfhosted/widgets/budgetContainer.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/selectItems.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cashew_selfhosted/pages/addButton.dart';

class HomePageBudgets extends StatefulWidget {
  const HomePageBudgets({super.key});

  @override
  State<HomePageBudgets> createState() => _HomePageBudgetsState();
}

class _HomePageBudgetsState extends State<HomePageBudgets> {
  @override
  Widget build(BuildContext context) {
    return KeepAliveClientMixin(
      child: StreamBuilder<List<Budget>>(
        stream: database.getAllPinnedBudgets().$1,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            if (snapshot.data?.length == 0) {
              return AddButton(
                onTap: () {
                  openBottomSheet(
                    context,
                    EditHomePagePinnedBudgetsPopup(
                      showBudgetsTotalLabelSetting: false,
                    ),
                    useCustomController: true,
                  );
                },
                height: 160,
                width: null,
                margin: const EdgeInsetsDirectional.only(
                    start: 13, end: 13, bottom: 13),
                labelUnder: "budget".tr(),
                icon: Icons.format_list_bulleted_add,
              );
            }
            // if (snapshot.data!.length == 1) {
            //   return Padding(
            //     padding: const EdgeInsetsDirectional.only(
            //         start: 13, end: 13, bottom: 13),
            //     child: BudgetContainer(
            //       budget: snapshot.data![0],
            //     ),
            //   );
            // }
            List<Widget> budgetItems = [
              ...(snapshot.data?.map((Budget budget) {
                    return Padding(
                      padding:
                          const EdgeInsetsDirectional.symmetric(horizontal: 3),
                      child: BudgetContainer(
                        intermediatePadding: false,
                        budget: budget,
                      ),
                    );
                  }).toList() ??
                  []),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 3, end: 3),
                child: AddButton(
                  onTap: () {
                    openBottomSheet(
                      context,
                      EditHomePagePinnedBudgetsPopup(
                        showBudgetsTotalLabelSetting: false,
                      ),
                      useCustomController: true,
                    );
                  },
                  height: null,
                  width: null,
                  margin: EdgeInsetsDirectional.all(0),
                  labelUnder: "budget".tr(),
                  icon: Icons.format_list_bulleted_add,
                ),
              ),
            ];
            // The measured card is a real one rather than the whole list's
            // first item, which may be the "add budget" button -- shorter than
            // a budget card, and measuring it would clip every real card.
            return HomePageCardCarousel(
              measureChild: BudgetContainer(budget: snapshot.data![0]),
              items: budgetItems,
              listItemPadding: const EdgeInsetsDirectional.only(end: 7),
            );
          } else {
            return SizedBox.shrink();
          }
        },
      ),
    );
  }
}

class EditHomePagePinnedBudgetsPopup extends StatelessWidget {
  const EditHomePagePinnedBudgetsPopup(
      {super.key, required this.showBudgetsTotalLabelSetting});
  final bool showBudgetsTotalLabelSetting;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Budget>>(
        stream: database.watchAllBudgets(),
        builder: (context, snapshot) {
          List<Budget> allBudgets = snapshot.data ?? [];
          return PopupFramework(
            title: "select-budgets".tr(),
            outsideExtraWidget: OutsideExtraWidgetIconButton(
              iconData: appStateSettings["outlinedIcons"]
                  ? Icons.edit_outlined
                  : Icons.edit_rounded,
              onPressed: () async {
                pushRoute(context, EditBudgetPage());
              },
            ),
            child: Column(
              children: [
                if (showBudgetsTotalLabelSetting)
                  ClipRRect(
                    borderRadius: BorderRadiusDirectional.circular(15),
                    child: TotalSpentToggle(),
                  ),
                if (allBudgets.length <= 0)
                  NoResultsCreate(
                    message: "no-budgets-found".tr(),
                    buttonLabel: "create-budget".tr(),
                    route: AddBudgetPage(
                      routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                    ),
                  ),
                SelectItems(
                  syncWithInitial: true,
                  checkboxCustomIconSelected: Icons.push_pin_rounded,
                  checkboxCustomIconUnselected: Icons.push_pin_outlined,
                  items: [
                    for (Budget budget in allBudgets) budget.budgetPk.toString()
                  ],
                  getColor: (budgetPk, selected) {
                    for (Budget budget in allBudgets)
                      if (budget.budgetPk.toString() == budgetPk.toString()) {
                        return HexColor(budget.colour,
                                defaultColor:
                                    Theme.of(context).colorScheme.primary)
                            .withOpacity(selected == true ? 0.7 : 0.5);
                      }
                    return null;
                  },
                  displayFilter: (budgetPk) {
                    for (Budget budget in allBudgets)
                      if (budget.budgetPk.toString() == budgetPk.toString()) {
                        return budget.name;
                      }
                    return "";
                  },
                  initialItems: [
                    for (Budget budget in allBudgets)
                      if (budget.pinned) budget.budgetPk.toString()
                  ],
                  onChangedSingleItem: (value) async {
                    Budget budget = allBudgets[allBudgets
                        .indexWhere((item) => item.budgetPk == value)];
                    Budget budgetToUpdate =
                        await database.getBudgetInstance(budget.budgetPk);
                    await database.createOrUpdateBudget(
                      budgetToUpdate.copyWith(pinned: !budgetToUpdate.pinned),
                    );
                  },
                  onLongPress: (String budgetPk) async {
                    Budget budget = await database.getBudgetInstance(budgetPk);
                    pushRoute(
                      context,
                      AddBudgetPage(
                        routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                        budget: budget,
                      ),
                    );
                  },
                ),
                if (allBudgets.length > 0)
                  AddButton(
                    onTap: () {},
                    height: 50,
                    width: null,
                    margin: const EdgeInsetsDirectional.only(
                      start: 13,
                      end: 13,
                      bottom: 13,
                      top: 13,
                    ),
                    openPage: AddBudgetPage(
                      routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                    ),
                    afterOpenPage: () {
                      Future.delayed(Duration(milliseconds: 100), () {
                        bottomSheetControllerGlobalCustomAssigned
                            ?.snapToExtent(0);
                      });
                    },
                  ),
              ],
            ),
          );
        });
  }
}
