import 'dart:convert';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/main.dart';
import 'package:cashew_selfhosted/pages/editHomePage.dart';
import 'package:cashew_selfhosted/pages/translationEditorPage.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/transactionEntry/transactionEntry.dart';
import 'package:cashew_selfhosted/widgets/watchAllWallets.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/scheduler.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/defaultPreferences.dart';
import 'package:cashew_selfhosted/struct/perUserViewSettings.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart';
import 'package:cashew_selfhosted/colors.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cashew_selfhosted/struct/languageMap.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/radioItems.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/pages/activityPage.dart';

Map<String, dynamic> appStateSettings = {};
bool isDatabaseCorrupted = false;
String databaseCorruptedError = "";
bool isDatabaseImportedOnThisSession = false;
PackageInfo? packageInfoGlobal;

Future<bool> initializeSettings() async {
  packageInfoGlobal = await PackageInfo.fromPlatform();

  Map<String, dynamic> userSettings = await getUserSettings();
  if (userSettings["databaseJustImported"] == true) {
    isDatabaseImportedOnThisSession = true;
    try {
      print("Settings were loaded from backup, trying to restore");
      String storedSettings = (await database.getSettings()).settingsJSON;
      await sharedPreferences.setString('userSettings', storedSettings);
      print(storedSettings);
      userSettings = json.decode(storedSettings);
      //we need to load any defaults to migrate if on an older version backup restores
      //Set to defaults if a new setting is added, but no entry saved
      Map<String, dynamic> userPreferencesDefault =
          await getDefaultPreferences();
      userPreferencesDefault.forEach((key, value) {
        userSettings = attemptToMigrateCyclePreferences(userSettings, key);
        if (userSettings[key] == null) {
          userSettings[key] = userPreferencesDefault[key];
        }
      });
      // Always reset the language/locale when restoring a backup
      userSettings["locale"] = "System";
      userSettings["databaseJustImported"] = false;
      print("Settings were restored");
    } catch (e) {
      print("Error restoring imported settings " + e.toString());
      if (e is DriftRemoteException) {
        if (e.remoteCause
            .toString()
            .toLowerCase()
            .contains("file is not a database")) {
          isDatabaseCorrupted = true;
          databaseCorruptedError = e.toString();
        }
      } else if (e
          .toString()
          .toLowerCase()
          .contains("file is not a database")) {
        isDatabaseCorrupted = true;
        databaseCorruptedError = e.toString();
      }
    }

    if (isDatabaseCorrupted == false) {
      try {
        // A restore would otherwise carry the other household members' view
        // preferences too -- the backup holds their rows, and the bump below
        // would then stamp those as newest and push them, rearranging
        // everyone's home page because one person restored a backup. Dropped
        // before the bump so there is nothing to stamp.
        await database.dropOtherMembersViewSettings(currentViewSettingsRowPk);
      } catch (e) {
        print("Error clearing other members' view settings after restore " +
            e.toString());
      }
      try {
        // Restored data keeps its original dateTimeModified, which can
        // predate what peers think they've already synced with this
        // device -- without this, the restore would silently never reach
        // them. See bumpAllModifiedTimestampsForResync().
        await database.bumpAllModifiedTimestampsForResync();
      } catch (e) {
        print("Error bumping timestamps for resync after restore " +
            e.toString());
      }
    }
  }

  appStateSettings = userSettings;
  print(
      "App settings loaded: if logging is enabled, logs will now be captured");

  // Do some actions based on loaded settings
  if (appStateSettings["accentSystemColor"] == true) {
    appStateSettings["accentColor"] = await getAccentColorSystemString();
  }

  // Must run before the first frame: the wizard gate reads
  // hasCompletedServerSetup, and an existing install would otherwise be shown
  // the first-run wizard after updating.
  await attemptToMigrateServerSetupWizard();
  await attemptToMigrateSetLongTermLoansAmountTo0();
  attemptToMigrateCustomNumberFormattingSettings();
  await attemptToMigrateUnsupportedLocale();

  // Disable sync every change is not on web
  // It will still sync when user pulls down to refresh
  // if (!kIsWeb) {
  //   appStateSettings["syncEveryChange"] = false;
  // }
  // Instead we now check for web with the setting appStateSettings["syncEveryChange"]

  // Load iOS font when iOS
  // Disable iOS font for now... Avenir looks better
  // if (getPlatform() == PlatformOS.isIOS) {
  //   // appStateSettings["font"] = "SFProText";
  //   appStateSettings["font"] = "Avenir";
  // }

  if (appStateSettings["hasOnboarded"] == true) {
    appStateSettings["numLogins"] = appStateSettings["numLogins"] + 1;
  }

  appStateSettings["appOpenedHour"] = DateTime.now().hour;
  appStateSettings["appOpenedMinute"] = DateTime.now().minute;

  String? retrievedClientID = await sharedPreferences.getString("clientID");
  if (retrievedClientID == null) {
    String systemID = await getDeviceInfo();
    String newClientID = systemID
            .substring(0, (systemID.length > 17 ? 17 : systemID.length))
            .replaceAll("-", "_") +
        "-" +
        DateTime.now().millisecondsSinceEpoch.toString();
    await sharedPreferences.setString("clientID", newClientID);
    clientID = newClientID;
  } else {
    clientID = retrievedClientID;
  }

  timeDilation = double.parse(appStateSettings["animationSpeed"].toString());

  selectedWalletPkController.add(SelectedWalletPk(
      selectedWalletPk: appStateSettings["selectedWalletPk"] ?? "0"));

  Map<String, dynamic> defaultPreferences = await getDefaultPreferences();

  fixHomePageOrder(defaultPreferences, "homePageOrder");
  fixHomePageOrder(defaultPreferences, "homePageOrderFullScreen");

  // save settings
  await sharedPreferences.setString(
      "userSettings", json.encode(appStateSettings));

  try {
    globalCollapsedFutureID.value = (jsonDecode(
                sharedPreferences.getString("globalCollapsedFutureID") ?? "{}")
            as Map<String, dynamic>)
        .map((key, value) {
      return MapEntry(key, value is bool ? value : false);
    });
  } catch (e) {
    print("There was an error restoring globalCollapsedFutureID preference: " +
        e.toString());
  }

  try {
    loadRecentlyDeletedTransactions();
  } catch (e) {
    print("There was an error loading recently deleted transactions map: " +
        e.toString());
  }

  return true;
}

// setAppStateSettings
Future<bool> updateSettings(
  String setting,
  value, {
  required bool updateGlobalState,
  List<int> pagesNeedingRefresh = const [],
  bool forceGlobalStateUpdate = false,
  bool setStateAllPageFrameworks = false,
}) async {
  bool isChanged = appStateSettings[setting] != value;

  appStateSettings[setting] = value;
  await sharedPreferences.setString(
      'userSettings', json.encode(appStateSettings));

  // A handful of settings describe how this person wants their own screens
  // arranged, and follow them to their other devices rather than staying on
  // whichever one they happened to change it on. Mirrored into their row here,
  // centrally, so a new call site cannot forget to. No-ops on a solo account
  // and when the stored value already matches, so this costs nothing on the
  // overwhelming majority of settings writes. See struct/perUserViewSettings.
  if (syncedViewSettingKeys.contains(setting)) {
    try {
      await storeViewSettings();
    } catch (e) {
      // A settings write must never fail because a screen preference could
      // not be recorded for the other device.
      print("Could not store view settings for $setting: $e");
    }
  }

  if (updateGlobalState == true) {
    // Only refresh global state if the value is different
    if (isChanged || forceGlobalStateUpdate) {
      print("Rebuilt Main Request from: " +
          setting.toString() +
          " : " +
          value.toString());
      appStateKey.currentState?.refreshAppState();
    }
  } else {
    if (setStateAllPageFrameworks) {
      refreshPageFrameworks();
      // Since the transactions list page does not use PageFramework!
      transactionsListPageStateKey.currentState?.refreshState();
    }
    //Refresh any pages listed
    for (int page in pagesNeedingRefresh) {
      print("Pages Rebuilt and Refreshed: " + pagesNeedingRefresh.toString());
      if (page == 0) {
        homePageStateKey.currentState?.refreshState();
      } else if (page == 1) {
        transactionsListPageStateKey.currentState?.refreshState();
      } else if (page == 2) {
        budgetsListPageStateKey.currentState?.refreshState();
      } else if (page == 3) {
        settingsPageStateKey.currentState?.refreshState();
        settingsPageFrameworkStateKey.currentState?.refreshState();
      }
    }
  }

  return true;
}

Map<String, dynamic> getSettingConstants(Map<String, dynamic> userSettings) {
  Map<String, dynamic> themeSetting = {
    "system": ThemeMode.system,
    "light": ThemeMode.light,
    "dark": ThemeMode.dark,
    "black": ThemeMode.dark,
  };

  Map<String, dynamic> userSettingsNew = {...userSettings};
  userSettingsNew["theme"] = themeSetting[userSettings["theme"]];
  userSettingsNew["accentColor"] =
      HexColor(userSettings["accentColor"]).withOpacity(1);
  return userSettingsNew;
}

Future<Map<String, dynamic>> getUserSettings() async {
  Map<String, dynamic> userPreferencesDefault = await getDefaultPreferences();

  String? userSettings = sharedPreferences.getString('userSettings');
  try {
    if (userSettings == null) {
      throw ("no settings on file");
    }
    print("Found user settings on file");

    Map<String, dynamic> userSettingsJSON = json.decode(userSettings);

    //Set to defaults if a new setting is added, but no entry saved
    userPreferencesDefault.forEach((key, value) {
      userSettingsJSON =
          attemptToMigrateCyclePreferences(userSettingsJSON, key);
      if (userSettingsJSON[key] == null) {
        userSettingsJSON[key] = userPreferencesDefault[key];
      }
    });
    return userSettingsJSON;
  } catch (e) {
    print("There was an error, settings corrupted: " + e.toString());
    await sharedPreferences.setString(
        'userSettings', json.encode(userPreferencesDefault));
    return userPreferencesDefault;
  }
}

// Returns the name of the language given a key, if key is System will return system translated label
String languageDisplayFilter(String languageKey) {
  if (languageNamesJSON[languageKey] != null) {
    return languageNamesJSON[languageKey].toString().capitalizeFirstofEach;
  }
  // if (supportedLanguagesSet.contains(item))
  //   return supportedLanguagesSet[item];
  if (languageKey == "System") return "system".tr();
  return languageKey;
}

void openLanguagePicker(BuildContext context) {
  print(appStateSettings["locale"]);
  openBottomSheet(
    context,
    PopupFramework(
      title: "language".tr(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 10),
            child: TranslationsEditorTile(),
          ),
          RadioItems(
            items: [
              "System",
              for (String localeKey in supportedLocales.keys) localeKey,
            ],
            initial: appStateSettings["locale"].toString(),
            displayFilter: languageDisplayFilter,
            onChanged: (value) async {
              // Need to update this value first because our RootBundleAssetLoaderCustomLocaleLoader
              // makes use of this value for some languages
              appStateSettings["locale"] = value;
              if (value == "System") {
                context.resetLocale();
              } else {
                if (supportedLocales[value] != null)
                  context.setLocale(supportedLocales[value]!);
              }
              updateSettings(
                "locale",
                value,
                pagesNeedingRefresh: [3],
                updateGlobalState: false,
              );
              await Future.delayed(Duration(milliseconds: 50));
              initializeLocalizedMonthNames();
              popRoute(context);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> resetLanguageToSystem(BuildContext context) async {
  if (appStateSettings["locale"].toString() == "System") return;
  context.resetLocale();
  await updateSettings(
    "locale",
    "System",
    pagesNeedingRefresh: [],
    updateGlobalState: false,
  );
}

// Backup user settings by creating an entry in the db
Future backupSettings() async {
  String userSettings = sharedPreferences.getString('userSettings') ?? "";
  if (userSettings == "") throw ("No settings stored");
  await database.createOrUpdateSettings(
    AppSetting(
      settingsPk: 0,
      settingsJSON: userSettings,
      dateUpdated: DateTime.now(),
    ),
  );
  print("Created settings entry in DB");
}

/// Offers the in-app translation editor wherever languages come up.
///
/// This used to be upstream's "email me your translations" card, pointing at
/// the original author's personal address -- which for a fork is somebody
/// else's inbox receiving corrections to strings they never wrote. There is
/// nowhere to send them here, so the fix is to edit them in place instead.
///
/// Raw English on purpose, like the editor it opens: see
/// lib/pages/translationEditorPage.dart.
class TranslationsEditorTile extends StatelessWidget {
  const TranslationsEditorTile({
    super.key,
    this.showIcon = true,
    this.backgroundColor,
  });

  final bool showIcon;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: () {
        pushRoute(context, const TranslationEditorPage());
      },
      color: backgroundColor ??
          Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7),
      borderRadius: getPlatform() == PlatformOS.isIOS ? 10 : 15,
      child: Padding(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            if (showIcon)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Icon(
                  appStateSettings["outlinedIcons"]
                      ? Icons.translate_outlined
                      : Icons.translate_rounded,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 31,
                ),
              ),
            Expanded(
              child: TextFont(
                text: "Something worded badly? Edit any of the app's own text "
                    "here, in any language.",
                textColor: getColor(context, "black"),
                textAlign:
                    showIcon == true ? TextAlign.start : TextAlign.center,
                maxLines: 5,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
