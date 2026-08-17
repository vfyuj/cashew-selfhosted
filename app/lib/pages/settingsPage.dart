import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart' hide AppSettings;
import 'package:cashew_selfhosted/pages/aboutPage.dart';
import 'package:cashew_selfhosted/pages/addTransactionPage.dart';
import 'package:cashew_selfhosted/pages/billSplitter.dart';
import 'package:cashew_selfhosted/pages/budgetsListPage.dart';
import 'package:cashew_selfhosted/pages/creditDebtTransactionsPage.dart';
import 'package:cashew_selfhosted/pages/editHomePage.dart';
import 'package:cashew_selfhosted/pages/translationEditorPage.dart';
import 'package:cashew_selfhosted/pages/editObjectivesPage.dart';
import 'package:cashew_selfhosted/pages/homePage/homePageNetWorth.dart';
import 'package:cashew_selfhosted/pages/envelopesPage.dart';
import 'package:cashew_selfhosted/pages/objectivesListPage.dart';
import 'package:cashew_selfhosted/pages/transactionsListPage.dart';
import 'package:cashew_selfhosted/pages/upcomingOverdueTransactionsPage.dart';
import 'package:cashew_selfhosted/struct/currencyFunctions.dart';
import 'package:cashew_selfhosted/struct/defaultPreferences.dart';
import 'package:cashew_selfhosted/struct/languageMap.dart';
import 'package:cashew_selfhosted/struct/navBarIconsData.dart';
import 'package:cashew_selfhosted/widgets/animatedExpanded.dart';
import 'package:cashew_selfhosted/widgets/dropdownSelect.dart';
import 'package:cashew_selfhosted/widgets/exportDB.dart';
import 'package:cashew_selfhosted/widgets/importCSV.dart';
import 'package:cashew_selfhosted/widgets/exportCSV.dart';
import 'package:cashew_selfhosted/pages/autoTransactionsPageNotifications.dart';
import 'package:cashew_selfhosted/pages/activityPage.dart';
import 'package:cashew_selfhosted/pages/editAssociatedTitlesPage.dart';
import 'package:cashew_selfhosted/pages/editBudgetPage.dart';
import 'package:cashew_selfhosted/pages/editCategoriesPage.dart';
import 'package:cashew_selfhosted/pages/editWalletsPage.dart';
import 'package:cashew_selfhosted/pages/notificationsPage.dart';
import 'package:cashew_selfhosted/pages/subscriptionsPage.dart';
import 'package:cashew_selfhosted/widgets/accountAndBackup.dart';
import 'package:cashew_selfhosted/widgets/importDB.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart';
import 'package:cashew_selfhosted/widgets/notificationsSettings.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/radioItems.dart';
import 'package:cashew_selfhosted/widgets/restartApp.dart';
import 'package:cashew_selfhosted/widgets/selectAmount.dart';
import 'package:cashew_selfhosted/widgets/selectColor.dart';
import 'package:cashew_selfhosted/widgets/settingsContainers.dart';
import 'package:cashew_selfhosted/pages/walletDetailsPage.dart';
import 'package:cashew_selfhosted/struct/initializeBiometrics.dart';
import 'package:cashew_selfhosted/widgets/sliderSelector.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/util/checkWidgetLaunch.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cashew_selfhosted/main.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:app_settings/app_settings.dart';
import 'package:cashew_selfhosted/widgets/outlinedButtonStacked.dart';

//To get SHA1 Key run
// ./gradlew signingReport
//in budget\Android
//Generate new OAuth and put JSON in budget\android\app folder

class MoreActionsPage extends StatefulWidget {
  const MoreActionsPage({
    Key? key,
  }) : super(key: key);

  @override
  State<MoreActionsPage> createState() => MoreActionsPageState();
}

class MoreActionsPageState extends State<MoreActionsPage> {
  GlobalKey<PageFrameworkState> pageState = GlobalKey();

  void refreshState() {
    print("refresh settings");
    setState(() {});
  }

  void scrollToTop() {
    pageState.currentState?.scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(builder: (context, _) {
      return PageFramework(
        key: pageState,
        title: "more-actions".tr(),
        backButton: false,
        horizontalPaddingConstrained: true,
        actions: [
          CustomPopupMenuButton(
            showButtons: true,
            keepOutFirst: true,
            items: [
              if (appStateSettings["showFAQAndHelpLink"] == true)
                DropdownItemMenu(
                  id: "open-faq",
                  label: "faq".tr(),
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.live_help_outlined
                      : Icons.live_help_rounded,
                  action: () {
                    openUrl("https://cashewapp.web.app/faq.html");
                  },
                ),
            ],
          ),
        ],
        listWidgets: [
          MorePages()
        ],
      );
    });
  }
}

class MorePages extends StatelessWidget {
  const MorePages({super.key});

  @override
  Widget build(BuildContext context) {
    bool hasSideNavigation = getIsFullScreen(context);

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
      child: Column(
        children: [
          if (hasSideNavigation == false)
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: SettingsContainerOpenPage(
                    openPage: SettingsPageFramework(
                      key: settingsPageFrameworkStateKey,
                    ),
                    title: navBarIconsData["settings"]!.labelLong.tr(),
                    icon: navBarIconsData["settings"]!.iconData,
                    description: appStateSettings["showExtraInfoText"] == false
                        ? null
                        : "settings-and-customization-description".tr(),
                    isOutlined: true,
                    // description: "Theme, Language, CSV Import",
                    isWideOutlined: true,
                  ),
                ),
              ],
            ),
          if (hasSideNavigation == false)
            Row(
              children: [
                Expanded(
                  child: SettingsContainerOpenPage(
                    openPage: WalletDetailsPage(wallet: null),
                    title: navBarIconsData["allSpending"]!.labelLong.tr(),
                    icon: navBarIconsData["allSpending"]!.iconData,
                    description: appStateSettings["showExtraInfoText"] == false
                        ? null
                        : "all-spending-description".tr(),
                    isOutlined: true,
                    isWideOutlined: true,
                  ),
                ),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              appStateSettings["showBillSplitterShortcut"] == true &&
                      hasSideNavigation == false
                  ? Expanded(
                      child: SettingsContainerOpenPage(
                        openPage: BillSplitter(),
                        title: "bill-splitter".tr(),
                        icon: appStateSettings["outlinedIcons"]
                            ? Icons.summarize_outlined
                            : Icons.summarize_rounded,
                        isOutlined: true,
                      ),
                    )
                  : notificationsGlobalEnabled
                      ? Expanded(
                          child: SettingsContainerOpenPage(
                            openPage: NotificationsPage(),
                            title: navBarIconsData["notifications"]!.label.tr(),
                            icon: navBarIconsData["notifications"]!.iconData,
                            isOutlined: true,
                          ),
                        )
                      : SizedBox.shrink(),
              if (hasSideNavigation == false)
                Expanded(
                    child: AccountLoginButton(
                  key: settingsAccountLoginButtonKey,
                )),
            ],
          ),
          if (hasSideNavigation == false)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: SettingsContainerOpenPage(
                    openPage: SubscriptionsPage(),
                    title: navBarIconsData["subscriptions"]!.label.tr(),
                    icon: navBarIconsData["subscriptions"]!.iconData,
                    isOutlined: true,
                  ),
                ),
                Expanded(
                  child: SettingsContainerOpenPage(
                    openPage:
                        UpcomingOverdueTransactions(overdueTransactions: null),
                    title: navBarIconsData["scheduled"]!.label.tr(),
                    icon: navBarIconsData["scheduled"]!.iconData,
                    isOutlined: true,
                  ),
                ),
              ],
            ),
          if (hasSideNavigation == false)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: SettingsContainerOpenPage(
                    openPage: EnvelopesPage(backButton: true),
                    title: navBarIconsData["envelopes"]!.label.tr(),
                    icon: navBarIconsData["envelopes"]!.iconData,
                    isOutlined: true,
                  ),
                ),
                Expanded(
                  child: SettingsContainerOpenPage(
                    openPage: ObjectivesListPage(
                      backButton: true,
                    ),
                    title: navBarIconsData["goals"]!.label.tr(),
                    icon: navBarIconsData["goals"]!.iconData,
                    isOutlined: true,
                  ),
                ),
              ],
            ),
          if (hasSideNavigation == false)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: SettingsContainerOpenPage(
                    openPage: CreditDebtTransactions(isCredit: null),
                    title: navBarIconsData["loans"]!.label.tr(),
                    icon: navBarIconsData["loans"]!.iconData,
                    isOutlined: true,
                  ),
                ),
              ],
            ),
          if (hasSideNavigation == false)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 1,
                  child: SettingsContainerOpenPage(
                    isOutlinedColumn: true,
                    openPage: EditWalletsPage(),
                    title: navBarIconsData["accountDetails"]!.label.tr(),
                    icon: navBarIconsData["accountDetails"]!.iconData,
                    isOutlined: true,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: SettingsContainerOpenPage(
                    isOutlinedColumn: true,
                    // If budget page not pinned to home, open budget list page
                    openPage: appStateSettings["customNavBarShortcut0"] !=
                                "budgets" &&
                            appStateSettings["customNavBarShortcut1"] !=
                                "budgets" &&
                            appStateSettings["customNavBarShortcut2"] !=
                                "budgets"
                        ? BudgetsListPage(enableBackButton: true)
                        : EditBudgetPage(),
                    title: navBarIconsData["budgetDetails"]!.label.tr(),
                    icon: navBarIconsData["budgetDetails"]!.iconData,
                    iconScale: navBarIconsData["budgetDetails"]!.iconScale,
                    isOutlined: true,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: SettingsContainerOpenPage(
                    isOutlinedColumn: true,
                    openPage: EditCategoriesPage(),
                    title: navBarIconsData["categoriesDetails"]!.label.tr(),
                    icon: navBarIconsData["categoriesDetails"]!.iconData,
                    isOutlined: true,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: SettingsContainerOpenPage(
                    isOutlinedColumn: true,
                    openPage: EditAssociatedTitlesPage(),
                    title: navBarIconsData["titlesDetails"]!.label.tr(),
                    icon: navBarIconsData["titlesDetails"]!.iconData,
                    isOutlined: true,
                  ),
                )
              ],
            ),
          if (hasSideNavigation) SettingsPageContent(),
        ],
      ),
    );
  }
}

class EnterName extends StatelessWidget {
  const EnterName({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      title: "username".tr(),
      icon: Icons.edit,
      onTap: () {
        enterNameBottomSheet(context);
      },
    );
  }
}

Future<String> enterNameBottomSheet(context,
    {bool updatePageWhenSet = true}) async {
  return await openBottomSheet(
    context,
    popupWithKeyboard: true,
    PopupFramework(
      title: "enter-name".tr(),
      child: SelectText(
        buttonLabel: "set-name".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.person_outlined
            : Icons.person_rounded,
        setSelectedText: (_) {},
        nextWithInput: (text) {
          updateSettings("username", text.trim(),
              pagesNeedingRefresh: updatePageWhenSet ? [0] : [],
              updateGlobalState: false);
        },
        selectedText: appStateSettings["username"],
        placeholder: "nickname".tr(),
        autoFocus: true,
      ),
    ),
  );
}

class SettingsPageFramework extends StatefulWidget {
  const SettingsPageFramework({super.key});

  @override
  State<SettingsPageFramework> createState() => SettingsPageFrameworkState();
}

class SettingsPageFrameworkState extends State<SettingsPageFramework> {
  void refreshState() {
    print("refresh settings framework");
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "settings".tr(),
      dragDownToDismiss: true,
      listWidgets: [SettingsPageContent()],
    );
  }
}

/// The settings landing page: a few grouped cards of "open a sub-page" rows,
/// rather than one long scroll of every individual toggle. Each row names what
/// is inside it, so finding a setting is one read plus one tap.
///
/// Every setting the app had still exists -- this regrouped them, it did not
/// remove any. AccentColorSetting/ThemeSettingsDropdown and friends all moved
/// into the sub-pages below.
class SettingsPageContent extends StatelessWidget {
  const SettingsPageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          children: [
            SettingsContainerOpenPage(
              openPage: GeneralSettingsPage(),
              title: "general-settings".tr(),
              description: "general-settings-description".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.settings_outlined
                  : Icons.settings_rounded,
            ),
            SettingsContainerOpenPage(
              openPage: ThemeAndStyleSettingsPage(),
              title: "theme-and-style".tr(),
              description: "theme-and-style-description".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.palette_outlined
                  : Icons.palette_rounded,
            ),
            SettingsContainerOpenPage(
              openPage: TransactionsSettingsPage(),
              title: "transactions".tr(),
              description: "transactions-settings-description".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.receipt_long_outlined
                  : Icons.receipt_long_rounded,
            ),
            SettingsContainerOpenPage(
              openPage: LocalizationSettingsPage(),
              title: "localization-and-formatting".tr(),
              description: "localization-and-formatting-description".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.language_outlined
                  : Icons.language_rounded,
            ),
            SettingsContainerOpenPage(
              openPage: ImportExportSettingsPage(),
              title: "import-and-export-data".tr(),
              description: "import-and-export-data-description".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.save_outlined
                  : Icons.save_rounded,
            ),
            SettingsContainerOpenPage(
              openPage: AboutPage(),
              title: "about-app".tr(namedArgs: {"app": globalAppName}),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.info_outlined
                  : Icons.info_rounded,
            ),
          ],
        ),
        SettingsHeader(title: "tools-and-extras".tr()),
        SettingsGroup(
          children: [
            SettingsContainerOpenPage(
              openPage: BillSplitter(),
              title: "bill-splitter".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.summarize_outlined
                  : Icons.summarize_rounded,
            ),
            SettingsContainerOpenPage(
              openPage: ActivityPage(),
              title: "transaction-activity-log".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.ballot_outlined
                  : Icons.ballot_rounded,
            ),
            // Android-only, and behind the notification-scanning debug flag.
            // Null rather than SizedBox.shrink() so SettingsGroup drops it
            // without leaving a divider behind.
            appStateSettings["notificationScanningDebug"] == true &&
                    getPlatform(ignoreEmulation: true) == PlatformOS.isAndroid
                ? SettingsContainerOpenPage(
                    title: "Notification Transactions",
                    openPage: AutoTransactionsPageNotifications(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.edit_notifications_outlined
                        : Icons.edit_notifications_rounded,
                  )
                : null,
          ],
        ),
        SizedBox(height: 8),
      ],
    );
  }
}

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "general-settings".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        SettingsContainerOpenPage(
          openPage: EditHomePage(),
          title: "edit-home-page".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.home_outlined
              : Icons.home_rounded,
        ),
        notificationsGlobalEnabled && getIsFullScreen(context) == false
            ? SettingsContainerOpenPage(
                openPage: NotificationsPage(),
                title: "notifications".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.notifications_outlined
                    : Icons.notifications_rounded,
              )
            : SizedBox.shrink(),
        BiometricsSettingToggle(),
        WidgetSettings(),
      ],
    );
  }
}

class ThemeAndStyleSettingsPage extends StatelessWidget {
  const ThemeAndStyleSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "theme-and-style".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        SettingsHeader(title: "theme".tr()),
        AccentColorSetting(),
        getPlatform() == PlatformOS.isIOS
            ? SizedBox.shrink()
            : SettingsContainerSwitch(
                title: "material-you".tr(),
                description: "material-you-description".tr(),
                onSwitched: (value) {
                  updateSettings("materialYou", value, updateGlobalState: true);
                },
                initialValue: appStateSettings["materialYou"],
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.brush_outlined
                    : Icons.brush_rounded,
              ),
        ThemeSettingsDropdown(),
        SettingsHeader(title: "style".tr()),
        HeaderHeightSetting(),
        OutlinedIconsSetting(),
        FontPickerSetting(),
        AppAnimationSetting(),
        CountingNumberAnimationSetting(),
        IncreaseTextContrastSetting(),
      ],
    );
  }
}

class TransactionsSettingsPage extends StatelessWidget {
  const TransactionsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "transactions".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        SettingsHeader(title: "transactions".tr()),
        TransactionsSettings(),
        SettingsHeader(title: "accounts".tr()),
        WalletsSettings(),
        SettingsHeader(title: "budgets".tr()),
        BudgetSettings(),
        SettingsHeader(title: "goals".tr()),
        ObjectiveSettings(),
        SettingsHeader(title: "titles".tr()),
        TitlesSettings(),
      ],
    );
  }
}

class LocalizationSettingsPage extends StatelessWidget {
  const LocalizationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "localization-and-formatting".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        LanguageSetting(),
        // Raw English, like the page it opens -- this is the way back from a
        // translation someone has made unreadable.
        SettingsContainerOpenPage(
          openPage: const TranslationEditorPage(),
          title: "Edit translations",
          description: "Reword any text in the app",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.translate_outlined
              : Icons.translate_rounded,
        ),
        PrimaryCurrencySetting(),
        SettingsHeader(title: "formatting".tr()),
        NumberFormattingSetting(),
        PercentagePrecisionSetting(),
        Time24HourFormatSetting(),
        FirstDayOfWeekSetting(updateHomePage: true),
        NumberPadFormatSetting(),
      ],
    );
  }
}

class ImportExportSettingsPage extends StatelessWidget {
  const ImportExportSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "import-and-export-data".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        SettingsHeader(title: "import-and-export".tr()),
        ExportCSV(),
        ImportCSV(),
        SettingsHeader(title: "backups".tr()),
        ExportDB(),
        ImportDB(),
        AccountLoginButton(
          isOutlinedButton: false,
          forceButtonName: "self-hosted-backup".tr(),
        ),
      ],
    );
  }
}

/// The accent-colour row, lifted out of the old landing page unchanged so it
/// can live on the Theme & Style page.
class AccentColorSetting extends StatelessWidget {
  const AccentColorSetting({super.key});

  @override
  Widget build(BuildContext context) {
    late Color? selectedColor = HexColor(appStateSettings["accentColor"]);
    return SettingsContainer(
      onTap: () {
        openBottomSheet(
          context,
          useParentContextForTheme: false,
          PopupFramework(
            title: "select-color".tr(),
            child: Column(
              children: [
                getPlatform() == PlatformOS.isIOS
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: 8.0),
                        child: SettingsContainerSwitch(
                          title: "colorful-interface".tr(),
                          onSwitched: (value) {
                            updateSettings("materialYou", value,
                                updateGlobalState: true);
                          },
                          initialValue: appStateSettings["materialYou"],
                          icon: appStateSettings["outlinedIcons"]
                              ? Icons.brush_outlined
                              : Icons.brush_rounded,
                          enableBorderRadius: true,
                        ),
                      )
                    : SizedBox.shrink(),
                SelectColor(
                  selectableColorsList: selectableAccentColors(context),
                  includeThemeColor: false,
                  selectedColor: selectedColor,
                  setSelectedColor: (color) {
                    selectedColor = color;
                    updateSettings("accentColor", toHexString(color),
                        updateGlobalState: true);
                    updateSettings("accentSystemColor", false,
                        updateGlobalState: true);
                    updateWidgetColorsAndText(context);
                  },
                  useSystemColorPrompt: true,
                ),
              ],
            ),
          ),
        );
      },
      title: "accent-color".tr(),
      description: "accent-color-description".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.color_lens_outlined
          : Icons.color_lens_rounded,
      // Swatch of the colour currently in use, so the row shows what it is
      // set to without having to open the picker.
      afterWidget: Container(
        width: 27,
        height: 27,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selectedColor ?? Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// The language row, lifted out of the old landing page unchanged.
class LanguageSetting extends StatelessWidget {
  const LanguageSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      title: "language".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.language_outlined
          : Icons.language_rounded,
      afterWidget: Tappable(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: 10,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16, vertical: 10),
          child: TextFont(
            text: languageDisplayFilter(appStateSettings["locale"].toString()),
            fontSize: 14,
          ),
        ),
      ),
      onTap: () {
        openLanguagePicker(context);
      },
    );
  }
}

class ThemeSettingsDropdown extends StatefulWidget {
  const ThemeSettingsDropdown({super.key});

  @override
  State<ThemeSettingsDropdown> createState() => _ThemeSettingsDropdownState();
}

class _ThemeSettingsDropdownState extends State<ThemeSettingsDropdown> {
  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      key: ValueKey(appStateSettings["materialYou"].toString()),
      title: "theme-mode".tr(),
      icon: Theme.of(context).brightness == Brightness.light
          ? appStateSettings["outlinedIcons"]
              ? Icons.lightbulb_outlined
              : Icons.lightbulb_rounded
          : appStateSettings["outlinedIcons"]
              ? Icons.dark_mode_outlined
              : Icons.dark_mode_rounded,
      initial: appStateSettings["theme"].toString() == "black" &&
              appStateSettings["materialYou"] == false
          ? "dark"
          : appStateSettings["theme"].toString(),
      items: [
        "system",
        "light",
        "dark",
        if (appStateSettings["materialYou"] == true) "black"
      ],
      faintValues: [
        if (appStateSettings["materialYou"] == true &&
            appStateSettings["theme"].toString() == "system")
          appStateSettings["forceFullDarkBackground"] == true ? "dark" : "black"
      ],
      onChanged: (value) async {
        if (value == "black") {
          await updateSettings("forceFullDarkBackground", true,
              updateGlobalState: false);
        } else if (value == "dark") {
          await updateSettings("forceFullDarkBackground", false,
              updateGlobalState: false);
        }
        setState(() {});
        await updateSettings("theme", value, updateGlobalState: true);
        updateWidgetColorsAndText(context);
      },
      getLabel: (item) {
        return item.tr();
      },
    );
  }
}

class WidgetSettings extends StatelessWidget {
  const WidgetSettings({super.key});

  @override
  Widget build(BuildContext context) {
    if (getPlatform(ignoreEmulation: true) != PlatformOS.isAndroid)
      return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsContainer(
          title: "net-worth-total-widget".tr(),
          description: "select-accounts-and-time-period".tr(),
          onTap: () async {
            await openNetWorthSettings(context);
            // We need to resfresh the widget rendering since it exists on the homepage!
            homePageStateKey.currentState?.refreshState();
          },
          icon: appStateSettings["outlinedIcons"]
              ? Icons.area_chart_outlined
              : Icons.area_chart_rounded,
        ),
        SettingsContainerDropdown(
          title: "widget-theme".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.contrast_outlined
              : Icons.contrast_rounded,
          initial: appStateSettings["widgetTheme"].toString(),
          items: ["app", "light", "dark"],
          onChanged: (value) async {
            if (value == "app") value = "system";
            await updateSettings("widgetTheme", value,
                updateGlobalState: false);
            updateWidgetColorsAndText(context);
          },
          getLabel: (item) {
            return item.tr();
          },
        ),
        SettingsContainer(
          title: "widget-background-opacity".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.blur_on_outlined
              : Icons.blur_on_rounded,
          descriptionWidget: Container(
            height: 28,
            padding: EdgeInsetsDirectional.only(end: 10),
            child: SliderTheme(
              data: SliderThemeData(
                trackShape: CustomTrackShape(),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 9),
              ),
              child: SliderSelector(
                min: 0,
                max: 1,
                initialValue:
                    (appStateSettings["widgetOpacity"] ?? 1).toDouble(),
                onChange: (value) {},
                divisions: 20,
                onFinished: (value) {
                  updateSettings("widgetOpacity", value,
                      updateGlobalState: false);
                  updateWidgetColorsAndText(context);
                },
                displayFilter: (double number) {
                  return convertToPercent(number * 100, numberDecimals: 0);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight;
    final trackLeft = offset.dx;
    final trackTop =
        offset.dy + (parentBox.size.height - (trackHeight ?? 0)) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, (trackHeight ?? 0));
  }
}

class BiometricsSettingToggle extends StatefulWidget {
  const BiometricsSettingToggle({super.key});

  @override
  State<BiometricsSettingToggle> createState() =>
      _BiometricsSettingToggleState();
}

class _BiometricsSettingToggleState extends State<BiometricsSettingToggle> {
  bool isLocked = appStateSettings["requireAuth"];
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        authAvailable || isLocked
            ? SettingsContainerSwitch(
                title: "biometric-lock".tr(),
                description: "biometric-lock-description".tr(),
                onSwitched: (value) async {
                  AuthResult authResult =
                      await checkBiometrics(checkAlways: true);
                  if (authResult == AuthResult.error) {
                    openPopup(
                      context,
                      icon: appStateSettings["outlinedIcons"]
                          ? Icons.warning_outlined
                          : Icons.warning_rounded,
                      title: getPlatform() == PlatformOS.isIOS
                          ? "biometrics-disabled".tr()
                          : "biometrics-error".tr(),
                      description: getPlatform() == PlatformOS.isIOS
                          ? "biometrics-disabled-description".tr()
                          : "biometrics-error-description".tr(),
                      onCancelLabel:
                          getPlatform() == PlatformOS.isIOS ? "ok".tr() : null,
                      onCancel: () {
                        popRoute(context);
                      },
                      onSubmitLabel: getPlatform() == PlatformOS.isIOS
                          ? "open-settings".tr()
                          : "ok".tr(),
                      onSubmit: () {
                        updateSettings("requireAuth", false,
                            updateGlobalState: false);
                        setState(() {
                          isLocked = false;
                        });
                        popRoute(context);
                        // On iOS the notification app settings page also has
                        // the permission for biometrics
                        if (getPlatform() == PlatformOS.isIOS) {
                          AppSettings.openAppSettings(
                              type: AppSettingsType.notification);
                        }
                      },
                    );
                  } else if (authResult == AuthResult.authenticated) {
                    updateSettings("requireAuth", value,
                        updateGlobalState: false);
                    setState(() {
                      isLocked = value;
                    });
                  }
                  return authResult == AuthResult.authenticated;
                },
                initialValue: isLocked,
                icon: isLocked
                    ? appStateSettings["outlinedIcons"]
                        ? Icons.lock_outlined
                        : Icons.lock_rounded
                    : appStateSettings["outlinedIcons"]
                        ? Icons.lock_open_outlined
                        : Icons.lock_open_rounded,
              )
            : SizedBox.shrink(),
      ],
    );
  }
}

class HeaderHeightSetting extends StatelessWidget {
  const HeaderHeightSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedExpanded(
      // Indicates if it is enabled by default per device height
      expand: MediaQuery.sizeOf(context).height > MIN_HEIGHT_FOR_HEADER &&
          getPlatform() != PlatformOS.isIOS,
      child: SettingsContainerDropdown(
        title: "header-height".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.subtitles_outlined
            : Icons.subtitles_rounded,
        initial: appStateSettings["forceSmallHeader"].toString(),
        items: ["true", "false"],
        onChanged: (value) async {
          bool boolValue = false;
          if (value == "true") {
            boolValue = true;
          } else if (value == "false") {
            boolValue = false;
          }
          await updateSettings(
            "forceSmallHeader",
            boolValue,
            updateGlobalState: false,
            setStateAllPageFrameworks: true,
            pagesNeedingRefresh: [0],
          );
        },
        getLabel: (item) {
          if (item == "true") return "short".tr();
          if (item == "false") return "tall".tr();
        },
      ),
    );
  }
}

// Changing this setting needs to update the UI, that's not something that happens when setting global state
class OutlinedIconsSetting extends StatelessWidget {
  const OutlinedIconsSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      items: ["rounded", "outlined"],
      onChanged: (value) async {
        if (value == "rounded") {
          await updateSettings("outlinedIcons", false,
              updateGlobalState: false);
        } else {
          await updateSettings(
            "outlinedIcons",
            true,
            updateGlobalState: false,
          );
        }
        navBarIconsData = getNavBarIconsData();
        RestartApp.restartApp(context);
      },
      getLabel: (value) {
        return value.tr();
      },
      initial:
          appStateSettings["outlinedIcons"] == true ? "outlined" : "rounded",
      title: "icon-style".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.star_outline
          : Icons.star_rounded,
    );
  }
}

class CountingNumberAnimationSetting extends StatelessWidget {
  const CountingNumberAnimationSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      title: "number-animation".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.pin_outlined
          : Icons.pin_rounded,
      initial: appStateSettings["numberCountUpAnimation"] == true
          ? "count-up"
          : "disabled",
      items: ["count-up", "disabled"],
      onChanged: (value) async {
        await updateSettings(
          "numberCountUpAnimation",
          value == "count-up" ? true : false,
          updateGlobalState: false,
        );
      },
      getLabel: (item) {
        return item.tr();
      },
    );
  }
}

class AppAnimationSetting extends StatelessWidget {
  const AppAnimationSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      title: "app-animations".tr(),
      description: "app-animations-description".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.animation_outlined
          : Icons.animation_rounded,
      initial: appStateSettings["appAnimations"] == AppAnimations.all.index
          ? "all"
          : appStateSettings["appAnimations"] == AppAnimations.minimal.index
              ? "minimal"
              : appStateSettings["appAnimations"] ==
                      AppAnimations.disabled.index
                  ? "disabled"
                  : "all",
      items: ["all", "minimal"], // "disabled" is not yet supported
      onChanged: (value) async {
        await updateSettings(
          "appAnimations",
          value == "all"
              ? AppAnimations.all.index
              : value == "minimal"
                  ? AppAnimations.minimal.index
                  : value == "disabled"
                      ? AppAnimations.disabled.index
                      : "all",
          updateGlobalState: false,
          setStateAllPageFrameworks: true,
        );
        appStateKey.currentState?.refreshAppState();
      },
      getLabel: (item) {
        return item.tr();
      },
    );
  }
}

class IncreaseTextContrastSetting extends StatelessWidget {
  const IncreaseTextContrastSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainerSwitch(
      title: "increase-text-contrast".tr(),
      description: "increase-text-contrast-description".tr(),
      onSwitched: (value) async {
        await updateSettings("increaseTextContrast", value,
            updateGlobalState: true);
      },
      initialValue: appStateSettings["increaseTextContrast"],
      icon: appStateSettings["outlinedIcons"]
          ? Icons.exposure_outlined
          : Icons.exposure_rounded,
      descriptionColor: appStateSettings["increaseTextContrast"]
          ? getColor(context, "black").withOpacity(0.84)
          : Theme.of(context).colorScheme.secondary.withOpacity(0.45),
    );
  }
}

class FontPickerSetting extends StatelessWidget {
  const FontPickerSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      title: "font".tr().capitalizeFirst,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.font_download_outlined
          : Icons.font_download_rounded,
      afterWidget: Tappable(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: 10,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16, vertical: 10),
          child: Builder(builder: (context) {
            String displayFontName =
                fontNameDisplayFilter(appStateSettings["font"].toString());
            return TextFont(
              text: displayFontName,
              fontSize: 14,
            );
          }),
        ),
      ),
      onTap: () {
        openFontPicker(context);
      },
    );
  }
}

void openFontPicker(BuildContext context) {
  openBottomSheet(
    context,
    PopupFramework(
      title: "font".tr(),
      child: RadioItems(
        itemsAreFonts: true,
        items: [
          // These values match that of pubspec font family
          "Avenir",
          "DMSans",
          "Metropolis",
          // SF Pro removed - users on iOS can just select Platform font
          // Inter is the font family fallback
          "RobotoCondensed",
          "Inconsolata",
          "(Platform)",
        ],
        initial: appStateSettings["font"].toString(),
        displayFilter: fontNameDisplayFilter,
        onChanged: (value) async {
          updateSettings("font", value, updateGlobalState: true);
          await Future.delayed(Duration(milliseconds: 50));
          popRoute(context);
        },
      ),
    ),
  );
}

String fontNameDisplayFilter(String value) {
  if (value == "Avenir") {
    return "default".tr().capitalizeFirst;
  } else if (value == "(Platform)") {
    return "platform".tr().capitalizeFirst;
  } else if (value == "DMSans") {
    return "DM Sans";
  } else if (value == "RobotoCondensed") {
    return "Roboto Condensed";
  } else if (value == "Inconsolata") {
    return "Inconsolata Monospace";
  }
  return value.toString();
}

class NumberFormattingSetting extends StatelessWidget {
  const NumberFormattingSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      title: "number-format".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.one_x_mobiledata_outlined
          : Icons.one_x_mobiledata_rounded,
      afterWidget: IgnorePointer(
        child: Tappable(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: 10,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 16, vertical: 10),
            child: TextFont(
              text: convertToMoney(
                Provider.of<AllWallets>(context, listen: true),
                1234.56,
              ),
              fontSize: 14,
            ),
          ),
        ),
      ),
      onTap: () async {
        String originalSetting =
            appStateSettings["customNumberFormat"].toString() +
                appStateSettings["numberFormatDelimiter"].toString() +
                appStateSettings["numberFormatDecimal"].toString() +
                appStateSettings["numberFormatCurrencyFirst"].toString();
        await openBottomSheet(
          context,
          fullSnap: true,
          SetNumberFormatPopup(),
        );
        String newSetting = appStateSettings["customNumberFormat"].toString() +
            appStateSettings["numberFormatDelimiter"].toString() +
            appStateSettings["numberFormatDecimal"].toString() +
            appStateSettings["numberFormatCurrencyFirst"].toString();
        await updateSettings(
          "customNumberFormat",
          appStateSettings["customNumberFormat"],
          updateGlobalState: true,
          forceGlobalStateUpdate: originalSetting != newSetting,
        );
      },
    );
  }
}

class Time24HourFormatSetting extends StatelessWidget {
  const Time24HourFormatSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      title: "clock-format".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.history_toggle_off_outlined
          : Icons.history_toggle_off_rounded,
      initial: appStateSettings["use24HourFormat"].toString(),
      items: ["system", "12-hour", "24-hour"],
      onChanged: (value) async {
        await updateSettings("use24HourFormat", value, updateGlobalState: true);
      },
      getLabel: (item) {
        return item.tr();
      },
    );
  }
}

class SetNumberFormatPopup extends StatefulWidget {
  const SetNumberFormatPopup({super.key});

  @override
  State<SetNumberFormatPopup> createState() => _SetNumberFormatPopupState();
}

class _SetNumberFormatPopupState extends State<SetNumberFormatPopup> {
  bool customNumberFormat = appStateSettings["customNumberFormat"] == true;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    return PopupFramework(
      title: "number-format".tr(),
      child: Column(
        children: [
          SettingsContainerSwitch(
            title: "short-number-format".tr(),
            onSwitched: (value) {
              updateSettings(
                "shortNumberFormat",
                value ? "compact" : null,
                updateGlobalState: true,
              );
            },
            initialValue: appStateSettings["shortNumberFormat"] == "compact",
            enableBorderRadius: true,
            icon: appStateSettings["outlinedIcons"]
                ? Icons.one_k_outlined
                : Icons.one_k_rounded,
          ),
          HorizontalBreak(),
          SizedBox(height: 10),
          AnimatedOpacity(
            duration: Duration(milliseconds: 500),
            opacity: customNumberFormat == false ? 1 : 0.5,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButtonStacked(
                    filled: customNumberFormat == false,
                    alignStart: true,
                    alignBeside: true,
                    padding: EdgeInsetsDirectional.symmetric(
                        horizontal: 20, vertical: 20),
                    text: "default".tr(),
                    afterWidget: Padding(
                      padding:
                          const EdgeInsetsDirectional.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextFont(
                            textAlign: TextAlign.center,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            text: convertToMoney(
                              allWallets,
                              -1234.56,
                              forceNonCustomNumberFormat: true,
                              addCurrencyName: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    iconData: appStateSettings["outlinedIcons"]
                        ? Icons.check_circle_outlined
                        : Icons.check_circle_rounded,
                    onTap: () {
                      updateSettings("customNumberFormat", false,
                          updateGlobalState: false);
                      setState(() {
                        customNumberFormat = false;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 13),
          AnimatedOpacity(
            duration: Duration(milliseconds: 500),
            opacity: customNumberFormat == true ? 1 : 0.5,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButtonStacked(
                    filled: customNumberFormat == true,
                    alignStart: true,
                    alignBeside: true,
                    padding: EdgeInsetsDirectional.symmetric(
                        horizontal: 20, vertical: 20),
                    text: "custom".tr(),
                    afterWidget: CustomNumberFormatPopup(onChangeAnyOption: () {
                      updateSettings("customNumberFormat", true,
                          updateGlobalState: false);
                      setState(() {
                        customNumberFormat = true;
                      });
                    }),
                    iconData: appStateSettings["outlinedIcons"]
                        ? Icons.tune_outlined
                        : Icons.tune_rounded,
                    onTap: () {
                      updateSettings("customNumberFormat", true,
                          updateGlobalState: false);
                      setState(() {
                        customNumberFormat = true;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 5),
          Tappable(
            borderRadius: 10,
            color: Colors.transparent,
            onTap: () {
              popRoute(context);
              pushRoute(context, EditWalletsPage());
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                  start: 8, end: 8, top: 5, bottom: 5),
              child: TextFont(
                text: "decimal-precision-edit-account-info".tr(),
                fontSize: 14,
                maxLines: 10,
                textColor: getColor(context, "textLight"),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomNumberFormatPopup extends StatefulWidget {
  const CustomNumberFormatPopup({super.key, this.onChangeAnyOption});
  final VoidCallback? onChangeAnyOption;

  @override
  State<CustomNumberFormatPopup> createState() =>
      _CustomNumberFormatPopupState();
}

class _CustomNumberFormatPopupState extends State<CustomNumberFormatPopup> {
  String customDelimiter = appStateSettings["numberFormatDelimiter"];
  String customDecimal = appStateSettings["numberFormatDecimal"];
  bool numberFormatCurrencyFirst =
      appStateSettings["numberFormatCurrencyFirst"];
  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    String formattedNumber = convertToMoney(
      allWallets,
      -1234.56,
      forceCustomNumberFormat: true,
      addCurrencyName: true,
      customSymbol: getCurrencyString(allWallets) == ""
          ? "⬚"
          : getCurrencyString(allWallets),
    );
    return Column(
      children: [
        SizedBox(height: 20),
        AnimatedSizeSwitcher(
          child: TextFont(
            key: ValueKey(formattedNumber),
            textAlign: TextAlign.center,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            text: formattedNumber,
          ),
        ),
        SizedBox(height: 30),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SettingsContainer(
                isOutlined: true,
                isOutlinedColumn: true,
                title: "delimiter".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Symbols.decimal_decrease_sharp
                    : Symbols.decimal_decrease_rounded,
                onTap: () {
                  if (widget.onChangeAnyOption != null)
                    widget.onChangeAnyOption!();
                  openBottomSheet(
                    context,
                    popupWithKeyboard: true,
                    PopupFramework(
                      title: "set-delimiter".tr(),
                      child: SelectText(
                        maxLength: 5,
                        buttonLabel: "set-delimiter".tr(),
                        popContext: false,
                        setSelectedText: (_) {},
                        placeholder: "delimiter-symbol".tr(),
                        icon: appStateSettings["outlinedIcons"]
                            ? Symbols.decimal_decrease_sharp
                            : Symbols.decimal_decrease_rounded,
                        selectedText: customDelimiter,
                        nextWithInput: (text) async {
                          setState(() {
                            customDelimiter = text;
                          });
                          updateSettings("numberFormatDelimiter", text,
                              updateGlobalState: false);
                          popRoute(context);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: SettingsContainer(
                isOutlined: true,
                isOutlinedColumn: true,
                title: "symbol".tr() +
                    "\n" +
                    (numberFormatCurrencyFirst
                        ? "before".tr().capitalizeFirst
                        : "after".tr().capitalizeFirst),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.monetization_on_outlined
                    : Icons.monetization_on_rounded,
                onTap: () {
                  if (widget.onChangeAnyOption != null)
                    widget.onChangeAnyOption!();
                  setState(() {
                    numberFormatCurrencyFirst = !numberFormatCurrencyFirst;
                  });
                  updateSettings(
                      "numberFormatCurrencyFirst", numberFormatCurrencyFirst,
                      updateGlobalState: false);
                },
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: SettingsContainer(
                isOutlined: true,
                isOutlinedColumn: true,
                title: "decimal".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Symbols.decimal_increase_sharp
                    : Symbols.decimal_increase_rounded,
                onTap: () {
                  if (widget.onChangeAnyOption != null)
                    widget.onChangeAnyOption!();
                  openBottomSheet(
                    context,
                    popupWithKeyboard: true,
                    PopupFramework(
                      title: "set-decimal".tr(),
                      child: SelectText(
                        maxLength: 5,
                        buttonLabel: "set-decimal".tr(),
                        popContext: false,
                        setSelectedText: (_) {},
                        placeholder: "decimal-symbol".tr(),
                        icon: appStateSettings["outlinedIcons"]
                            ? Symbols.decimal_increase_sharp
                            : Symbols.decimal_increase_rounded,
                        selectedText: customDecimal,
                        nextWithInput: (text) async {
                          setState(() {
                            customDecimal = text;
                          });
                          updateSettings("numberFormatDecimal", text,
                              updateGlobalState: false);
                          popRoute(context);
                        },
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ],
    );
  }
}

class NumberPadFormatSetting extends StatelessWidget {
  const NumberPadFormatSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      title: "number-pad-format".tr(),
      onTap: () {
        openBottomSheet(
          context,
          NumberPadFormatSettingPopup(),
        );
      },
      icon: appStateSettings["outlinedIcons"]
          ? Icons.dialpad_sharp
          : Icons.dialpad_rounded,
    );
  }
}

class NumberPadFormatSettingPopup extends StatefulWidget {
  const NumberPadFormatSettingPopup({super.key});

  @override
  State<NumberPadFormatSettingPopup> createState() =>
      _NumberPadFormatSettingPopupState();
}

class _NumberPadFormatSettingPopupState
    extends State<NumberPadFormatSettingPopup> {
  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: "number-pad-format".tr(),
      child: Column(
        children: [
          ExtraZerosButtonSetting(
            enableBorderRadius: true,
            onChange: () {
              setState(() {});
            },
          ),
          NumberPadHapticFeedbackSetting(
            enableBorderRadius: true,
          ),
          HorizontalBreak(),
          SizedBox(height: 10),
          NumberPadFormatPicker(),
        ],
      ),
    );
  }
}

class NumberPadFormatPicker extends StatefulWidget {
  const NumberPadFormatPicker({super.key});

  @override
  State<NumberPadFormatPicker> createState() => _NumberPadFormatPickerState();
}

class _NumberPadFormatPickerState extends State<NumberPadFormatPicker> {
  NumberPadFormat selectedNumberPadFormat = getNumberPadFormat();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AnimatedOpacity(
                duration: Duration(milliseconds: 500),
                opacity: selectedNumberPadFormat == NumberPadFormat.format123
                    ? 1
                    : 0.5,
                child: OutlinedButtonStacked(
                  filled: selectedNumberPadFormat == NumberPadFormat.format123,
                  alignStart: true,
                  alignBeside: true,
                  text: null,
                  afterWidget: IgnorePointer(
                    child: NumberPadAmount(
                      extraWidgetAboveNumbers: null,
                      addToAmount: (_) {},
                      enableDecimal: true,
                      removeToAmount: () {},
                      removeAll: () {},
                      canChange: () => true,
                      enableCalculator: true,
                      padding: EdgeInsetsDirectional.zero,
                      setState: () {},
                      format: NumberPadFormat.format123,
                    ),
                  ),
                  padding: EdgeInsetsDirectional.only(
                      start: 20, end: 15, top: 10, bottom: 15),
                  iconData: null,
                  onTap: () {
                    setState(() {
                      selectedNumberPadFormat = NumberPadFormat.format123;
                    });
                    updateSettings(
                        "numberPadFormat", NumberPadFormat.format123.index,
                        updateGlobalState: false);
                  },
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AnimatedOpacity(
                duration: Duration(milliseconds: 500),
                opacity: selectedNumberPadFormat == NumberPadFormat.format789
                    ? 1
                    : 0.5,
                child: OutlinedButtonStacked(
                  filled: selectedNumberPadFormat == NumberPadFormat.format789,
                  alignStart: true,
                  alignBeside: true,
                  text: null,
                  afterWidget: IgnorePointer(
                    child: NumberPadAmount(
                      extraWidgetAboveNumbers: null,
                      addToAmount: (_) {},
                      enableDecimal: true,
                      removeToAmount: () {},
                      removeAll: () {},
                      canChange: () => true,
                      enableCalculator: true,
                      padding: EdgeInsetsDirectional.zero,
                      setState: () {},
                      format: NumberPadFormat.format789,
                    ),
                  ),
                  padding: EdgeInsetsDirectional.only(
                      start: 20, end: 15, top: 10, bottom: 15),
                  iconData: null,
                  onTap: () {
                    setState(() {
                      selectedNumberPadFormat = NumberPadFormat.format789;
                    });
                    updateSettings(
                        "numberPadFormat", NumberPadFormat.format789.index,
                        updateGlobalState: false);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ExtraZerosButtonSetting extends StatelessWidget {
  const ExtraZerosButtonSetting(
      {this.onChange, this.enableBorderRadius = false, super.key});
  final bool enableBorderRadius;
  final VoidCallback? onChange;
  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      enableBorderRadius: enableBorderRadius,
      title: "extra-zeros-button".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Symbols.counter_0_sharp
          : Symbols.counter_0_rounded,
      initial: appStateSettings["extraZerosButton"].toString(),
      items: ["", "00", "000"],
      onChanged: (value) async {
        await updateSettings(
          "extraZerosButton",
          value == "" ? null : value,
          updateGlobalState: false,
        );
        if (onChange != null) onChange!();
      },
      getLabel: (item) {
        if (item == "") return "none".tr().capitalizeFirst;
        return item;
      },
    );
  }
}

class NumberPadHapticFeedbackSetting extends StatelessWidget {
  const NumberPadHapticFeedbackSetting(
      {this.enableBorderRadius = false, super.key});
  final bool enableBorderRadius;
  @override
  Widget build(BuildContext context) {
    return SettingsContainerSwitch(
      enableBorderRadius: enableBorderRadius,
      title: "haptic-feedback".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.vibration_outlined
          : Symbols.vibration_rounded,
      initialValue: appStateSettings["numberPadHapticFeedback"] == true,
      onSwitched: (value) async {
        if (value == true) HapticFeedback.heavyImpact();
        await updateSettings(
          "numberPadHapticFeedback",
          value,
          updateGlobalState: false,
        );
      },
    );
  }
}

class PercentagePrecisionSetting extends StatelessWidget {
  const PercentagePrecisionSetting({super.key});
  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      title: "percentage-precision".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.percent_outlined
          : Icons.percent_rounded,
      initial: appStateSettings["percentagePrecision"] == 2
          ? "2-decimals"
          : appStateSettings["percentagePrecision"] == 1
              ? "1-decimal"
              : "0-decimals",
      items: ["0-decimals", "1-decimal", "2-decimals"],
      onChanged: (value) async {
        updateSettings(
          "percentagePrecision",
          value == "2-decimals"
              ? 2
              : value == "1-decimal"
                  ? 1
                  : 0,
          updateGlobalState: true,
        );
      },
      getLabel: (item) {
        return item.tr();
      },
    );
  }
}

void savingHapticFeedback() {
  if (appStateSettings["savingHapticFeedback"] == true) {
    HapticFeedback.lightImpact();
  }
}

class FirstDayOfWeekSetting extends StatelessWidget {
  const FirstDayOfWeekSetting({required this.updateHomePage, super.key});
  final bool updateHomePage;
  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      title: "first-weekday".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.calendar_month_outlined
          : Icons.calendar_month_rounded,
      initial: appStateSettings["firstDayOfWeek"].toString(),
      items: ["-1", "0", "1"],
      onChanged: (value) async {
        int intValue = int.tryParse(value) ?? -1;
        await updateSettings(
          "firstDayOfWeek",
          intValue,
          updateGlobalState: false,
          pagesNeedingRefresh: updateHomePage ? [0] : [],
        );
      },
      getLabel: (item) {
        List<String> weekDayNames = getWeekdayNames();
        if (item == "-1") return "default".tr();
        if (item == "0") return weekDayNames[0];
        if (item == "1") return weekDayNames[1];
      },
    );
  }
}

List<String> getWeekdayNames() {
  List<String> localizedWeekdayNames = [];
  final String? locale = navigatorKey.currentContext?.locale.toString();

  // Use a fixed date that is not affected by daylight saving time.
  // December 31st, 2023, is a Sunday
  final DateTime baseDate = DateTime.utc(2023, 12, 31, 12, 0, 0);

  for (int i = 0; i < 7; i++) {
    final DateTime date = baseDate.add(Duration(days: i));
    final String weekdayName = DateFormat.EEEE(locale).format(date);
    localizedWeekdayNames.add(weekdayName);
  }

  return localizedWeekdayNames;
}
