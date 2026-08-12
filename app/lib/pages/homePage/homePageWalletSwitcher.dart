import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/initializeDefaultDatabase.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addTransactionPage.dart';
import 'package:cashew_selfhosted/pages/addWalletPage.dart';
import 'package:cashew_selfhosted/pages/editBudgetPage.dart';
import 'package:cashew_selfhosted/pages/editWalletsPage.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/perUserViewSettings.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/settingsContainers.dart';
import 'package:cashew_selfhosted/widgets/util/keepAliveClientMixin.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/selectItems.dart';
import 'package:cashew_selfhosted/widgets/walletEntry.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cashew_selfhosted/pages/addButton.dart';

class HomePageWalletSwitcher extends StatelessWidget {
  const HomePageWalletSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return KeepAliveClientMixin(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 13.0),
        child: StreamBuilder<List<WalletWithDetails>>(
          stream: database.watchAllWalletsWithDetails(
              homePageWidgetDisplay: HomePageWidgetDisplay.WalletSwitcher),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (WalletWithDetails walletDetails in snapshot.data!)
                      WalletEntry(
                        selected: Provider.of<SelectedWalletPk>(context)
                                .selectedWalletPk ==
                            walletDetails.wallet.walletPk,
                        walletWithDetails: walletDetails,
                      ),
                    Stack(
                      children: [
                        SizedBox(
                          width: 130,
                          child: IgnorePointer(
                            child: Visibility(
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: Opacity(
                                opacity: 0,
                                child: WalletEntry(
                                  selected: false,
                                  walletWithDetails: WalletWithDetails(
                                    wallet: defaultWallet(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                                start: 6, end: 6),
                            child: AddButton(
                              onTap: () {
                                openBottomSheet(
                                  context,
                                  EditHomePagePinnedWalletsPopup(
                                    homePageWidgetDisplay:
                                        HomePageWidgetDisplay.WalletSwitcher,
                                  ),
                                  useCustomController: true,
                                );
                              },
                              labelUnder: "account".tr(),
                              icon: Icons.format_list_bulleted_add,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                clipBehavior: Clip.none,
                padding: EdgeInsetsDirectional.symmetric(horizontal: 7),
              );
            }
            return Container();
          },
        ),
      ),
    );
  }
}

class EditHomePagePinnedWalletsPopup extends StatelessWidget {
  const EditHomePagePinnedWalletsPopup({
    super.key,
    required this.homePageWidgetDisplay,
    this.includeFramework = true,
    this.highlightSelected = false,
    this.useCheckMarks = false,
    this.onAnySelected,
    this.allSelected = false,
    this.showCyclePicker = false,
  });

  final HomePageWidgetDisplay homePageWidgetDisplay;
  final bool includeFramework;
  final bool highlightSelected;
  final bool useCheckMarks;
  final Function? onAnySelected;
  final bool allSelected;
  final bool showCyclePicker;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransactionWallet>>(
      stream: database.getAllPinnedWallets(homePageWidgetDisplay).$1,
      builder: (context, snapshot2) {
        Map<String, TransactionWallet> walletsIndexedByPk =
            Provider.of<AllWallets>(context).indexedByPk;
        List<String> allWalletsPks = walletsIndexedByPk.keys.toList();
        List<TransactionWallet> allPinnedWallets = snapshot2.data ?? [];
        Widget child = Column(
          children: [
            if (allWalletsPks.length <= 0)
              NoResultsCreate(
                message: "no-accounts-found".tr(),
                buttonLabel: "create-account".tr(),
                route: AddWalletPage(
                  routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                ),
              ),
            if (snapshot2.hasData)
              SelectItems(
                allSelected: allSelected,
                highlightSelected: highlightSelected,
                syncWithInitial: true,
                checkboxCustomIconSelected:
                    useCheckMarks ? null : Icons.push_pin_rounded,
                checkboxCustomIconUnselected:
                    useCheckMarks ? null : Icons.push_pin_outlined,
                items: allWalletsPks,
                getColor: (walletPk, selected) {
                  TransactionWallet? wallet = walletsIndexedByPk[walletPk];
                  return HexColor(wallet?.colour,
                          defaultColor: Theme.of(context).colorScheme.primary)
                      .withOpacity(selected == true ? 0.7 : 0.5);
                },
                displayFilter: (walletPk) {
                  TransactionWallet? wallet = walletsIndexedByPk[walletPk];
                  return wallet?.name;
                },
                initialItems: [
                  for (TransactionWallet wallet in allPinnedWallets)
                    wallet.walletPk.toString()
                ],
                onChangedSingleItem: (walletPk) async {
                  TransactionWallet? wallet = walletsIndexedByPk[walletPk];
                  if (wallet != null) {
                    List<HomePageWidgetDisplay> currentList =
                        wallet.homePageWidgetDisplay ?? [];
                    if (currentList.contains(homePageWidgetDisplay)) {
                      currentList.remove(homePageWidgetDisplay);
                    } else {
                      currentList.add(homePageWidgetDisplay);
                    }
                    await database.createOrUpdateWallet(
                      wallet.copyWith(
                          homePageWidgetDisplay: Value(currentList)),
                    );
                  }
                  if (onAnySelected != null) onAnySelected!();
                },
                onLongPress: (String walletPk) async {
                  TransactionWallet? wallet = walletsIndexedByPk[walletPk];
                  pushRoute(
                    context,
                    AddWalletPage(
                      routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                      wallet: wallet,
                    ),
                  );
                },
              ),
            // Pinning above writes to the wallet row, so it is the household's
            // shared decision about which accounts belong on the home page.
            // This is the personal layer on top: accounts one member does not
            // want on *their* home page, following them between their own
            // devices without touching what anyone else sees. Only offered
            // when there is somebody else to differ from.
            if (perUserViewSettingsApply && allWalletsPks.length > 0)
              HorizontalBreakAbove(
                enabled: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                          start: 20, end: 20, top: 13, bottom: 5),
                      child: TextFont(
                        text: "hidden-from-your-home-page".tr(),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                          start: 20, end: 20, bottom: 8),
                      child: TextFont(
                        text: "hidden-from-your-home-page-description".tr(),
                        fontSize: 13,
                        maxLines: 4,
                        textColor: getColor(context, "textLight"),
                      ),
                    ),
                    SelectItems(
                      syncWithInitial: true,
                      checkboxCustomIconSelected: Icons.visibility_off_rounded,
                      checkboxCustomIconUnselected: Icons.visibility_outlined,
                      items: allWalletsPks,
                      displayFilter: (walletPk) =>
                          walletsIndexedByPk[walletPk]?.name,
                      initialItems: hiddenWalletPks.toList(),
                      onChangedSingleItem: (String walletPk) async {
                        await setWalletHiddenForCurrentUser(
                          walletPk,
                          !isWalletHiddenForCurrentUser(walletPk),
                        );
                        if (onAnySelected != null) onAnySelected!();
                      },
                    ),
                  ],
                ),
              ),
            if (allWalletsPks.length > 0 && includeFramework == true)
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
                openPage: AddWalletPage(
                  routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                ),
                afterOpenPage: () {
                  Future.delayed(Duration(milliseconds: 100), () {
                    bottomSheetControllerGlobalCustomAssigned?.snapToExtent(0);
                  });
                },
              ),
            if (homePageWidgetDisplay == HomePageWidgetDisplay.WalletList &&
                Provider.of<AllWallets>(context).allContainSameCurrency() ==
                    false &&
                Provider.of<AllWallets>(context)
                        .containsMultipleAccountsWithSameCurrency() ==
                    true)
              HorizontalBreakAbove(
                enabled: true,
                child: SettingsContainerSwitch(
                  enableBorderRadius: true,
                  title: "currency-total".tr(),
                  description: "currency-total-description".tr(),
                  onSwitched: (value) {
                    updateSettings("walletsListCurrencyBreakdown", value,
                        updateGlobalState: false, pagesNeedingRefresh: [1]);
                  },
                  initialValue:
                      appStateSettings["walletsListCurrencyBreakdown"],
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.view_list_outlined
                      : Icons.view_list_rounded,
                ),
              ),
            // if (showCyclePicker &&
            //         homePageWidgetDisplay ==
            //             HomePageWidgetDisplay.WalletSwitcher ||
            //     homePageWidgetDisplay == HomePageWidgetDisplay.WalletList)
            //   HorizontalBreakAbove(
            //     enabled: true,
            //     child: Column(
            //       children: [
            //         Padding(
            //           padding: const EdgeInsetsDirectional.only(
            //               bottom: 10, start: 15, end: 15, top: 4),
            //           child: TextFont(
            //             text: "customize-period-for-account-totals".tr(),
            //             textAlign: TextAlign.center,
            //             fontSize: 16,
            //             textColor: getColor(context, "black").withOpacity(0.8),
            //           ),
            //         ),
            //         PeriodCyclePicker(
            //           cycleSettingsExtension: homePageWidgetDisplay ==
            //                   HomePageWidgetDisplay.WalletSwitcher
            //               ? "Wallets"
            //               : homePageWidgetDisplay ==
            //                       HomePageWidgetDisplay.WalletList
            //                   ? "WalletsList"
            //                   : "",
            //         ),
            //       ],
            //     ),
            //   ),
          ],
        );
        if (includeFramework) {
          return PopupFramework(
            title: "select-accounts".tr(),
            outsideExtraWidget: OutsideExtraWidgetIconButton(
              iconData: appStateSettings["outlinedIcons"]
                  ? Icons.edit_outlined
                  : Icons.edit_rounded,
              onPressed: () async {
                pushRoute(context, EditWalletsPage());
              },
            ),
            child: child,
          );
        } else {
          return child;
        }
      },
    );
  }
}
