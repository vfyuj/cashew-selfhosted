import 'dart:async';
import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/generatePreviewData.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/main.dart';
import 'package:cashew_selfhosted/pages/aboutPage.dart';
import 'package:cashew_selfhosted/pages/accountsPage.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/liveSyncClient.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/webdavClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/struct/syncClient.dart';
import 'package:cashew_selfhosted/widgets/animatedExpanded.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/exportCSV.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/importDB.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart';
import 'package:cashew_selfhosted/widgets/navigationSidebar.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/settingsContainers.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/util/saveFile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:io';
import 'package:cashew_selfhosted/struct/randomConstants.dart';

Future<bool> checkConnection() async {
  late bool isConnected;
  if (!kIsWeb) {
    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        isConnected = true;
      }
    } on SocketException catch (e) {
      print(e.toString());
      isConnected = false;
    }
  } else {
    isConnected = true;
  }
  return isConnected;
}

void refreshUIAfterLoginChange() {
  sidebarStateKey.currentState?.refreshState();
  accountsPageStateKey.currentState?.refreshState();
  settingsAccountLoginButtonKey.currentState?.refreshState();
}

/// If already signed in, runs the post-login sync/backup sequence. If not,
/// opens AccountsPage to collect email/password/server URL -- there is no
/// more one-tap OAuth popup to trigger this inline, credentials must come
/// from a form. See specs/03-stage-1-kill-google.md.
Future<bool> signInAndSync(BuildContext context,
    {required dynamic Function() next}) async {
  if (selfHostedSession == null) {
    await Navigator.of(context).push(
      // isPushedRoute so a successful sign-in closes this route and lets the
      // await below resolve. Without it the caller waits forever.
      MaterialPageRoute(builder: (context) => AccountsPage(isPushedRoute: true)),
    );
    next();
    return selfHostedSession != null;
  }
  bool result = await syncAfterLogin(context);
  next();
  return result;
}

Future<bool> syncAfterLogin(BuildContext context) async {
  loadingIndeterminateKey.currentState?.setVisibility(true);
  try {
    await syncData(context);
    loadingIndeterminateKey.currentState?.setVisibility(true);
    await createBackupInBackground(context);
    loadingIndeterminateKey.currentState?.setVisibility(false);
    return true;
  } catch (e) {
    print("Error syncing data after login!");
    print(e.toString());
    loadingIndeterminateKey.currentState?.setVisibility(false);
    return false;
  }
}

Future<void> createBackupInBackground(context) async {
  if (appStateSettings["hasSignedIn"] == false) return;
  if (errorSigningInDuringCloud == true) return;
  if (kIsWeb && !entireAppLoaded) return;
  // print(entireAppLoaded);
  print("Last backup: " + appStateSettings["lastBackup"]);
  //Only run this once, don't run again if the global state changes (e.g. when changing a setting)
  // Update: Does this still run when global state changes? I don't think so...
  // If the entire app is loaded and we want to do an auto backup, lets do it no matter what!
  // if (entireAppLoaded == false || entireAppLoaded) {
  if (appStateSettings["autoBackups"] == true) {
    DateTime lastUpdate = DateTime.parse(appStateSettings["lastBackup"]);
    DateTime nextPlannedBackup = lastUpdate
        .add(Duration(days: appStateSettings["autoBackupsFrequency"]));
    print("next backup planned on " + nextPlannedBackup.toString());
    if (DateTime.now().millisecondsSinceEpoch >=
        nextPlannedBackup.millisecondsSinceEpoch) {
      print("auto backing up");

      if (selfHostedSession == null) {
        return;
      }
      // Silent, non-blocking refresh -- see specs/01-local-first-invariant.md
      await selfHostedRefresh();
      await createBackup(context, silentBackup: true, deleteOldBackups: true);
    } else {
      print("backup already made today");
    }
  }
  // }
  return;
}

Future forceDeleteDB() async {
  if (kIsWeb) {
    final html.Storage localStorage = html.window.localStorage;
    localStorage.clear();
  } else {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dbFolder.path, 'db.sqlite'));
    await dbFile.delete();
  }
}

bool openDatabaseCorruptedPopup(BuildContext context) {
  if (isDatabaseCorrupted) {
    openPopup(
      context,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.heart_broken_outlined
          : Icons.heart_broken_rounded,
      title: "database-corrupted".tr(),
      description: "database-corrupted-description".tr(),
      descriptionWidget: CodeBlock(
        text: databaseCorruptedError,
      ),
      barrierDismissible: false,
      onSubmit: () async {
        popRoute(context);
        await importDB(context, ignoreOverwriteWarning: true);
      },
      onSubmitLabel: "import-backup".tr(),
      onCancel: () async {
        popRoute(context);
        await openLoadingPopupTryCatch(() async {
          await forceDeleteDB();
          await sharedPreferences.clear();
        });
        restartAppPopup(context);
      },
      onCancelLabel: "reset".tr(),
    );
    // Lock the side navigation
    lockAppWaitForRestart = true;
    appStateKey.currentState?.refreshAppState();
    return true;
  }
  return false;
}

/// Picks where a *backup* (not sync -- sync always uses the self-hosted
/// server, see [SelfHostedClient]) is read from / written to, based on the
/// "backupTarget" setting. Returns null if the chosen target isn't usable
/// (not signed in for "server", or WebDAV isn't fully configured) so callers
/// can fail the same way an unreachable server already does.
BackupTransport? getBackupTransport() {
  if (appStateSettings["backupTarget"] == "webdav") {
    final config = WebDavConfig(
      url: (appStateSettings["webdavUrl"] ?? "").toString(),
      username: (appStateSettings["webdavUsername"] ?? "").toString(),
      password: (appStateSettings["webdavPassword"] ?? "").toString(),
      folder: (appStateSettings["webdavFolder"] ?? "").toString().isEmpty
          ? "cashew-backups"
          : appStateSettings["webdavFolder"].toString(),
    );
    if (!config.isConfigured) return null;
    return WebDavClient(config);
  }
  if (selfHostedSession == null) return null;
  return SelfHostedBackupTransport(SelfHostedClient(selfHostedSession!));
}

/// Best-effort safety net before a destructive local DB overwrite (restore
/// or import, see [overwriteDefaultDB]): backs up the current state under
/// its own timestamped filename so it never collides with -- or gets
/// silently replaced by -- the user's regular named device backup. Never
/// blocks or throws: a missing/unreachable backup destination just means no
/// safety net for this restore, not a blocked restore. Per
/// specs/01-local-first-invariant.md, the destructive action the user asked
/// for must still proceed.
Future<void> createSafetyBackupBeforeOverwrite(context) async {
  try {
    final transport = getBackupTransport();
    if (transport == null) return;
    DBFileInfo currentDBFileInfo = await getCurrentDBFileInfo();
    String filename =
        "pre-restore-${getCurrentDeviceName()}-${DateTime.now().millisecondsSinceEpoch}.sqlite";
    await transport.putFile(filename, currentDBFileInfo.dbFileBytes);
    openSnackbar(
      SnackbarMessage(
        title: "safety-backup-created".tr(),
        description: "safety-backup-created-description".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.backup_outlined
            : Icons.backup_rounded,
      ),
    );
  } catch (e) {
    print("Error creating safety backup before overwrite: " + e.toString());
    openSnackbar(
      SnackbarMessage(
        title: "safety-backup-failed".tr(),
        description: e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.warning_outlined
            : Icons.warning_rounded,
      ),
    );
  }
}

Future<void> createBackup(
  context, {
  bool? silentBackup,
  bool deleteOldBackups = false,
  String? clientIDForSync,
}) async {
  try {
    if (silentBackup == false || silentBackup == null) {
      loadingIndeterminateKey.currentState?.setVisibility(true);
    }
    await backupSettings();
  } catch (e) {
    if (silentBackup == false || silentBackup == null) {
      maybePopRoute(context);
    }
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }

  try {
    if (deleteOldBackups)
      await deleteRecentBackups(context, appStateSettings["backupLimit"],
          silentDelete: true);

    DBFileInfo currentDBFileInfo = await getCurrentDBFileInfo();

    String filename = "db-v$schemaVersionGlobal-${getCurrentDeviceName()}.sqlite";
    if (clientIDForSync != null) {
      // Sync always goes through the self-hosted server, never WebDAV --
      // see specs/03-stage-1-kill-google.md.
      if (selfHostedSession == null) throw ("Not signed in to a server");
      final client = SelfHostedClient(selfHostedSession!);
      filename =
          getCurrentDeviceSyncBackupFileName(clientIDForSync: clientIDForSync);
      await client.putFile(filename, currentDBFileInfo.dbFileBytes);
    } else {
      final transport = getBackupTransport();
      if (transport == null) throw ("Backup destination is not configured");
      await transport.putFile(filename, currentDBFileInfo.dbFileBytes);
    }

    if (clientIDForSync == null)
      openSnackbar(
        SnackbarMessage(
          title: "backup-created".tr(),
          description: filename,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.backup_outlined
              : Icons.backup_rounded,
        ),
      );
    if (clientIDForSync == null)
      await updateSettings("lastBackup", DateTime.now().toString(),
          pagesNeedingRefresh: [], updateGlobalState: false);

    if (silentBackup == false || silentBackup == null) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
    }
  } catch (e) {
    if (silentBackup == false || silentBackup == null) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
    }
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
}

Future<void> deleteRecentBackups(context, amountToKeep,
    {bool? silentDelete}) async {
  try {
    if (silentDelete == false || silentDelete == null) {
      loadingIndeterminateKey.currentState?.setVisibility(true);
    }

    final transport = getBackupTransport();
    if (transport == null) throw ("Backup destination is not configured");

    List<SyncFile> files = await transport.listFiles();

    int index = 0;
    files.forEach((file) {
      // subtract 1 because we just made a backup
      if (index >= amountToKeep - 1) {
        transport.deleteFile(file.name);
      }
      index++;
    });
    if (silentDelete == false || silentDelete == null) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
    }
  } catch (e) {
    if (silentDelete == false || silentDelete == null) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
    }
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
}

Future<void> deleteBackup(BackupTransport client, String filename,
    {bool isSync = false}) async {
  try {
    await client.deleteFile(filename);
  } catch (e) {
    openSnackbar(SnackbarMessage(title: e.toString()));
  }
}

Future<void> chooseBackup(context,
    {bool isManaging = false,
    bool isClientSync = false,
    bool hideDownloadButton = false}) async {
  try {
    openBottomSheet(
      context,
      BackupManagement(
        isManaging: isManaging,
        isClientSync: isClientSync,
        hideDownloadButton: hideDownloadButton,
      ),
    );
  } catch (e) {
    popRoute(context);
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
}

Future<void> loadBackup(BuildContext context, BackupTransport client,
    SyncFile file, {bool isSync = false}) async {
  try {
    openLoadingPopup(context);

    await cancelAndPreventSyncOperation();

    await createSafetyBackupBeforeOverwrite(context);

    List<int> dataStore = await client.getFile(file.name);
    await overwriteDefaultDB(Uint8List.fromList(dataStore));

    // if this is added, it doesn't restore the database properly on web
    // await database.close();
    popRoute(context);
    await resetLanguageToSystem(context);
    await updateSettings("databaseJustImported", true,
        pagesNeedingRefresh: [], updateGlobalState: false);
    print(appStateSettings);
    openSnackbar(
      SnackbarMessage(
          title: "backup-restored".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.settings_backup_restore_outlined
              : Icons.settings_backup_restore_rounded),
    );
    popRoute(context);
    restartAppPopup(
      context,
      description: kIsWeb
          ? "refresh-required-to-load-backup".tr()
          : "restart-required-to-load-backup".tr(),
    );
  } catch (e) {
    popRoute(context);
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
}

class AccountLoginButton extends StatefulWidget {
  const AccountLoginButton({
    super.key,
    this.navigationSidebarButton = false,
    this.isButtonSelected = false,
    this.isOutlinedButton = true,
    this.forceButtonName,
  });
  final bool navigationSidebarButton;
  final bool isButtonSelected;
  final bool isOutlinedButton;
  final String? forceButtonName;

  @override
  State<AccountLoginButton> createState() =>
      AccountLoginButtonState();
}

class AccountLoginButtonState extends State<AccountLoginButton> {
  void refreshState() {
    setState(() {});
  }

  void openPage({VoidCallback? onNext}) {
    if (widget.navigationSidebarButton) {
      // currentState is null when PageNavigationFramework isn't mounted --
      // during onboarding and the first-run wizard. Force-unwrapping it here
      // used to throw instead of doing nothing.
      pageNavigationFrameworkKey.currentState
          ?.changePage(8, switchNavbar: true);
      appStateKey.currentState?.refreshAppState();
    } else {
      if (onNext != null) onNext();
    }
  }

  void loginWithSync({VoidCallback? onNext}) {
    signInAndSync(
      widget.navigationSidebarButton
          ? navigatorKey.currentContext ?? context
          : context,
      next: () {
        setState(() {});
        openPage(onNext: onNext);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.navigationSidebarButton == true) {
      return AnimatedSwitcher(
        duration: Duration(milliseconds: 600),
        child: selfHostedSession == null
            ? NavigationSidebarButton(
                key: ValueKey("login"),
                label: "login".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.cloud_outlined
                    : Icons.cloud_rounded,
                onTap: loginWithSync,
                isSelected: false,
              )
            : NavigationSidebarButton(
                key: ValueKey("user"),
                label: selfHostedSession!.email,
                icon: widget.forceButtonName == null
                    ? appStateSettings["outlinedIcons"]
                        ? Icons.person_outlined
                        : Icons.person_rounded
                    : appStateSettings["outlinedIcons"]
                        ? Icons.cloud_outlined
                        : Icons.cloud_rounded,
                iconScale: widget.forceButtonName == null ? 1 : 0.87,
                onTap: openPage,
                isSelected: widget.isButtonSelected,
              ),
      );
    }
    return selfHostedSession == null
        ? SettingsContainerOpenPage(
            openPage: AccountsPage(),
            isOutlined: widget.isOutlinedButton,
            onTap: (openContainer) {
              loginWithSync(onNext: openContainer);
            },
            title: widget.forceButtonName ?? "login".tr(),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.cloud_outlined
                : Icons.cloud_rounded,
          )
        : SettingsContainerOpenPage(
            openPage: AccountsPage(),
            title: widget.forceButtonName ??
                cachedServerProfile?.displayName ??
                selfHostedSession!.email,
            icon: widget.forceButtonName == null
                ? appStateSettings["outlinedIcons"]
                    ? Icons.person_outlined
                    : Icons.person_rounded
                : appStateSettings["outlinedIcons"]
                    ? Icons.cloud_outlined
                    : Icons.cloud_rounded,
            isOutlined: widget.isOutlinedButton,
          );
  }
}

Future<(BackupTransport? client, List<SyncFile>?)> getBackupFiles() async {
  final transport = getBackupTransport();
  if (transport == null) return (null, null);
  try {
    return (transport, await transport.listFiles());
  } catch (e) {
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
  return (null, null);
}

Future<(BackupTransport? client, List<SyncFile>?)> getSyncFiles() async {
  if (selfHostedSession == null) return (null, null);
  try {
    final client = SelfHostedClient(selfHostedSession!);
    return (client, await client.listFiles());
  } catch (e) {
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
  return (null, null);
}

class BackupManagement extends StatefulWidget {
  const BackupManagement({
    Key? key,
    required this.isManaging,
    required this.isClientSync,
    this.hideDownloadButton = false,
  }) : super(key: key);

  final bool isManaging;
  final bool isClientSync;
  final bool hideDownloadButton;

  @override
  State<BackupManagement> createState() => _BackupManagementState();
}

class _BackupManagementState extends State<BackupManagement> {
  List<SyncFile> filesState = [];
  List<int> deletedIndices = [];
  late BackupTransport clientState;
  UniqueKey dropDownKey = UniqueKey();
  bool isLoading = true;
  bool autoBackups = appStateSettings["autoBackups"];
  bool backupSync = appStateSettings["backupSync"];

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      (BackupTransport?, List<SyncFile>?) result =
          widget.isClientSync ? await getSyncFiles() : await getBackupFiles();
      BackupTransport? client = result.$1;
      List<SyncFile>? files = result.$2;
      if (files == null || client == null) {
        setState(() {
          filesState = [];
          isLoading = false;
        });
      } else {
        setState(() {
          filesState = files;
          clientState = client;
          isLoading = false;
        });
        bottomSheetControllerGlobal.snapToExtent(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isClientSync) {
      if (filesState.length > 0) {
        print(appStateSettings["devicesHaveBeenSynced"]);
        updateSettings("devicesHaveBeenSynced", filesState.length,
            updateGlobalState: false);
      }
    } else {
      if (filesState.length > 0) {
        updateSettings("numBackups", filesState.length,
            updateGlobalState: false);
      }
    }
    Iterable<MapEntry<int, SyncFile>> filesMap = filesState.asMap().entries;
    return PopupFramework(
      title: widget.isClientSync
          ? "devices".tr().capitalizeFirst
          : widget.isManaging
              ? "backups".tr()
              : "restore-a-backup".tr(),
      subtitle: widget.isClientSync
          ? "manage-syncing-info".tr()
          : widget.isManaging
              ? appStateSettings["backupLimit"].toString() +
                  " " +
                  "stored-backups".tr()
              : "overwrite-warning".tr(),
      child: Column(
        children: [
          widget.isClientSync && kIsWeb == false
              ? Row(
                  children: [
                    Expanded(
                      child: AboutInfoBox(
                        title: "web-app".tr(),
                        link: "https://budget-track.web.app/",
                        color: appStateSettings["materialYou"]
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : getColor(context, "lightDarkAccentHeavyLight"),
                        padding: EdgeInsetsDirectional.only(
                          start: 5,
                          end: 5,
                          bottom: 10,
                          top: 5,
                        ),
                      ),
                    ),
                  ],
                )
              : SizedBox.shrink(),
          widget.isManaging && widget.isClientSync == false
              ? SettingsContainerSwitch(
                  enableBorderRadius: true,
                  onSwitched: (value) async {
                    await updateSettings("autoBackups", value,
                        pagesNeedingRefresh: [], updateGlobalState: false);
                    setState(() {
                      autoBackups = value;
                    });
                  },
                  initialValue: appStateSettings["autoBackups"],
                  title: "auto-backups".tr(),
                  description: "auto-backups-description".tr(),
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_done_rounded,
                )
              : SizedBox.shrink(),
          widget.isClientSync
              ? SettingsContainerSwitch(
                  enableBorderRadius: true,
                  onSwitched: (value) async {
                    // Only update global is the sidebar is shown
                    await updateSettings("backupSync", value,
                        pagesNeedingRefresh: [], updateGlobalState: false);
                    sidebarStateKey.currentState?.refreshState();
                    setState(() {
                      backupSync = value;
                    });
                    // Future.delayed(Duration(milliseconds: 100), () {
                    //   bottomSheetControllerGlobal.snapToExtent(0);
                    // });
                  },
                  initialValue: appStateSettings["backupSync"],
                  title: "sync-data".tr(),
                  description: "sync-data-description".tr(),
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.cloud_sync_outlined
                      : Icons.cloud_sync_rounded,
                )
              : SizedBox.shrink(),
          // Only allow sync on every change for web
          // Only on web, disabled automatically in initializeSettings if not web
          widget.isClientSync && kIsWeb
              ? AnimatedExpanded(
                  expand: backupSync,
                  child: SettingsContainerSwitch(
                    enableBorderRadius: true,
                    onSwitched: (value) async {
                      await updateSettings("syncEveryChange", value,
                          pagesNeedingRefresh: [], updateGlobalState: false);
                    },
                    initialValue: appStateSettings["syncEveryChange"],
                    title: "sync-every-change".tr(),
                    descriptionWithValue: (value) {
                      return value
                          ? "sync-every-change-description1".tr()
                          : "sync-every-change-description2".tr();
                    },
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.all_inbox_outlined
                        : Icons.all_inbox_rounded,
                  ),
                )
              : SizedBox.shrink(),
          // Reset Sync -- the escape hatch upstream Cashew also ships. A change
          // feed can end up in a state no client can make progress against,
          // and without this the only remedy is editing the server database by
          // hand. See specs/04-stage-2-instant-sync.md.
          // English literals rather than .tr() keys: assets/translations is
          // regenerated from upstream Cashew's Google Sheet, which would drop
          // any fork-local key on the next run. Same choice liveSyncClient.dart
          // already makes for its snackbars. "reset"/"cancel" are existing
          // upstream keys, so those stay translated.
          widget.isClientSync
              ? SettingsContainer(
                  enableBorderRadius: true,
                  title: "Reset Sync",
                  description: "Reset the remote sync database",
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.restart_alt_outlined
                      : Icons.restart_alt_rounded,
                  onTap: () {
                    openPopup(
                      context,
                      icon: appStateSettings["outlinedIcons"]
                          ? Icons.restart_alt_outlined
                          : Icons.restart_alt_rounded,
                      title: "Reset Sync",
                      description:
                          "Clears the server sync database to reinitialize syncing between devices. "
                          "This device's data is then uploaded as the new baseline. "
                          "Local data and stored backups remain intact.",
                      onSubmit: () async {
                        popRoute(context);
                        await openLoadingPopupTryCatch(() async {
                          final success = await resetLiveSync();
                          if (success == false) {
                            throw "Could not reach the server to reset syncing.";
                          }
                          openSnackbar(SnackbarMessage(
                            title: "Sync reset",
                            description:
                                "Other devices will re-sync automatically",
                            icon: appStateSettings["outlinedIcons"]
                                ? Icons.check_circle_outlined
                                : Icons.check_circle_rounded,
                          ));
                        });
                      },
                      onSubmitLabel: "reset".tr(),
                      onCancel: () => popRoute(context),
                      onCancelLabel: "cancel".tr(),
                    );
                  },
                )
              : SizedBox.shrink(),
          widget.isManaging && widget.isClientSync == false
              ? AnimatedExpanded(
                  expand: autoBackups,
                  child: SettingsContainerDropdown(
                    enableBorderRadius: true,
                    items: ["1", "2", "3", "7", "10", "14"],
                    onChanged: (value) async {
                      await updateSettings(
                          "autoBackupsFrequency", int.parse(value),
                          pagesNeedingRefresh: [], updateGlobalState: false);
                    },
                    initial:
                        appStateSettings["autoBackupsFrequency"].toString(),
                    title: "backup-frequency".tr(),
                    description: "number-of-days".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.event_repeat_outlined
                        : Icons.event_repeat_rounded,
                  ),
                )
              : SizedBox.shrink(),
          widget.isManaging &&
                  widget.isClientSync == false &&
                  appStateSettings["showBackupLimit"]
              ? SettingsContainerDropdown(
                  enableBorderRadius: true,
                  key: dropDownKey,
                  verticalPadding: 5,
                  title: "backup-limit".tr(),
                  icon: Icons.format_list_numbered_rtl_outlined,
                  initial: appStateSettings["backupLimit"].toString(),
                  items: ["10", "15", "20", "30"],
                  onChanged: (value) async {
                    if (int.parse(value) < appStateSettings["backupLimit"]) {
                      openPopup(
                        context,
                        icon: appStateSettings["outlinedIcons"]
                            ? Icons.delete_outlined
                            : Icons.delete_rounded,
                        title: "change-limit".tr(),
                        description: "change-limit-warning".tr(),
                        onSubmit: () async {
                          await updateSettings("backupLimit", int.parse(value),
                              updateGlobalState: false);
                          popRoute(context);
                        },
                        onSubmitLabel: "change".tr(),
                        onCancel: () {
                          popRoute(context);
                          setState(() {
                            dropDownKey = UniqueKey();
                          });
                        },
                        onCancelLabel: "cancel".tr(),
                      );
                    } else {
                      await updateSettings("backupLimit", int.parse(value),
                          updateGlobalState: false);
                    }
                  },
                )
              : SizedBox.shrink(),
          if ((widget.isManaging == false && widget.isClientSync == false) ==
              false)
            SizedBox(height: 10),
          isLoading
              ? Column(
                  children: [
                    for (int i = 0;
                        i <
                            (widget.isClientSync
                                ? appStateSettings["devicesHaveBeenSynced"]
                                : appStateSettings["numBackups"]);
                        i++)
                      LoadingShimmerDriveFiles(
                          isManaging: widget.isManaging, i: i),
                  ],
                )
              : SizedBox.shrink(),
          ...filesMap
              .map(
                (MapEntry<int, SyncFile> file) => AnimatedSizeSwitcher(
                  child: deletedIndices.contains(file.key)
                      ? Container(
                          key: ValueKey(1),
                        )
                      : Padding(
                          padding:
                              const EdgeInsetsDirectional.only(bottom: 8.0),
                          child: Tappable(
                            onTap: () async {
                              if (!widget.isManaging) {
                                final result = await openPopup(
                                  context,
                                  title: "load-backup".tr(),
                                  subtitle: getWordedDateShortMore(
                                        (file.value.modifiedTime ??
                                                DateTime.now())
                                            .toLocal(),
                                        includeTime: true,
                                        includeYear: true,
                                        showTodayTomorrow: false,
                                      ) +
                                      "\n" +
                                      getWordedTime(
                                          navigatorKey.currentContext?.locale
                                              .toString(),
                                          (file.value.modifiedTime ??
                                                  DateTime.now())
                                              .toLocal()),
                                  beforeDescriptionWidget: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      top: 8,
                                      bottom: 5,
                                    ),
                                    child: CodeBlock(
                                        text: (file.value.name ?? "No name")),
                                  ),
                                  description: "load-backup-warning".tr(),
                                  icon: appStateSettings["outlinedIcons"]
                                      ? Icons.warning_outlined
                                      : Icons.warning_rounded,
                                  onSubmit: () async {
                                    popRoute(context, true);
                                  },
                                  onSubmitLabel: "load".tr(),
                                  onCancelLabel: "cancel".tr(),
                                  onCancel: () {
                                    popRoute(context);
                                  },
                                );
                                if (result == true)
                                  loadBackup(
                                      context, clientState, file.value,
                                      isSync: widget.isClientSync);
                              }
                              // else {
                              //   await openPopup(
                              //     context,
                              //     title: "Backup Details",
                              //     description: (file.value.name ?? "") +
                              //         "\n" +
                              //         (file.value.size ?? "") +
                              //         "\n" +
                              //         (file.value.description ?? ""),
                              //     icon: appStateSettings["outlinedIcons"] ? Icons.warning_outlined : Icons.warning_rounded,
                              //     onSubmit: () async {
                              //       popRoute(context, true);
                              //     },
                              //     onSubmitLabel: "Close",
                              //   );
                              // }
                            },
                            borderRadius: 15,
                            color: widget.isClientSync &&
                                    isCurrentDeviceSyncBackupFile(
                                        file.value.name)
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.4)
                                : appStateSettings["materialYou"]
                                    ? Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer
                                    : getColor(
                                        context, "lightDarkAccentHeavyLight"),
                            child: Container(
                              padding: EdgeInsetsDirectional.symmetric(
                                  horizontal: 20, vertical: 15),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          widget.isClientSync
                                              ? appStateSettings[
                                                      "outlinedIcons"]
                                                  ? Icons.devices_outlined
                                                  : Icons.devices_rounded
                                              : appStateSettings[
                                                      "outlinedIcons"]
                                                  ? Icons.description_outlined
                                                  : Icons.description_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          size: 30,
                                        ),
                                        SizedBox(
                                            width:
                                                widget.isClientSync ? 17 : 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              TextFont(
                                                text: getTimeAgo(
                                                  (file.value.modifiedTime ??
                                                          DateTime.now())
                                                      .toLocal(),
                                                ).capitalizeFirst,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                maxLines: 2,
                                              ),
                                              TextFont(
                                                text: (isSyncBackupFile(
                                                        file.value.name)
                                                    ? getDeviceFromSyncBackupFileName(
                                                            file.value.name) +
                                                        " " +
                                                        "sync"
                                                    : file.value.name ??
                                                        "No name"),
                                                fontSize: 14,
                                                maxLines: 2,
                                              ),
                                              // isSyncBackupFile(
                                              //         file.value.name)
                                              //     ? Padding(
                                              //         padding:
                                              //             const EdgeInsetsDirectional
                                              //                 .only(top: 3),
                                              //         child: TextFont(
                                              //           text:
                                              //               file.value.name ??
                                              //                   "",
                                              //           fontSize: 11,
                                              //           maxLines: 2,
                                              //         ),
                                              //       )
                                              //     : SizedBox.shrink()
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  widget.isManaging
                                      ? Row(
                                          children: [
                                            widget.hideDownloadButton
                                                ? SizedBox.shrink()
                                                : Padding(
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .only(
                                                      start: 8.0,
                                                    ),
                                                    child: Builder(
                                                        builder: (boxContext) {
                                                      return ButtonIcon(
                                                        color: appStateSettings[
                                                                "materialYou"]
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .onSecondaryContainer
                                                                .withOpacity(
                                                                    0.08)
                                                            : getColor(context,
                                                                    "lightDarkAccentHeavy")
                                                                .withOpacity(
                                                                    0.7),
                                                        onTap: () {
                                                          saveDriveFileToDevice(
                                                            boxContext:
                                                                boxContext,
                                                            client:
                                                                clientState,
                                                            fileToSave:
                                                                file.value,
                                                            isSync: widget
                                                                .isClientSync,
                                                          );
                                                        },
                                                        icon: Icons
                                                            .download_rounded,
                                                      );
                                                    }),
                                                  ),
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .only(start: 5),
                                              child: ButtonIcon(
                                                color: appStateSettings[
                                                        "materialYou"]
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .onSecondaryContainer
                                                        .withOpacity(0.08)
                                                    : getColor(context,
                                                            "lightDarkAccentHeavy")
                                                        .withOpacity(0.7),
                                                onTap: () {
                                                  openPopup(
                                                    context,
                                                    icon: appStateSettings[
                                                            "outlinedIcons"]
                                                        ? Icons.delete_outlined
                                                        : Icons.delete_rounded,
                                                    title: "delete-backup".tr(),
                                                    subtitle:
                                                        getWordedDateShortMore(
                                                              (file.value.modifiedTime ??
                                                                      DateTime
                                                                          .now())
                                                                  .toLocal(),
                                                              includeTime: true,
                                                              includeYear: true,
                                                              showTodayTomorrow:
                                                                  false,
                                                            ) +
                                                            "\n" +
                                                            getWordedTime(
                                                                navigatorKey
                                                                    .currentContext
                                                                    ?.locale
                                                                    .toString(),
                                                                (file.value.modifiedTime ??
                                                                        DateTime
                                                                            .now())
                                                                    .toLocal()),
                                                    beforeDescriptionWidget:
                                                        Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .only(
                                                        top: 8,
                                                        bottom: 5,
                                                      ),
                                                      child: CodeBlock(
                                                        text: file.value.name +
                                                            "\n" +
                                                            convertBytesToMB(
                                                                    (file.value
                                                                                .size ??
                                                                            0)
                                                                        .toString())
                                                                .toStringAsFixed(
                                                                    2) +
                                                            " MB",
                                                      ),
                                                    ),
                                                    description: (widget
                                                            .isClientSync
                                                        ? "delete-sync-backup-warning"
                                                            .tr()
                                                        : null),
                                                    onSubmit: () async {
                                                      popRoute(context);
                                                      loadingIndeterminateKey
                                                          .currentState
                                                          ?.setVisibility(true);
                                                      await deleteBackup(
                                                          clientState,
                                                          file.value.id,
                                                          isSync: widget
                                                              .isClientSync);
                                                      openSnackbar(
                                                        SnackbarMessage(
                                                            title:
                                                                "deleted-backup"
                                                                    .tr(),
                                                            description: (file
                                                                    .value
                                                                    .name ??
                                                                "No name"),
                                                            icon: Icons
                                                                .delete_rounded),
                                                      );
                                                      setState(() {
                                                        deletedIndices
                                                            .add(file.key);
                                                      });
                                                      // bottomSheetControllerGlobal
                                                      //     .snapToExtent(0);
                                                      if (widget.isClientSync)
                                                        await updateSettings(
                                                            "devicesHaveBeenSynced",
                                                            appStateSettings[
                                                                    "devicesHaveBeenSynced"] -
                                                                1,
                                                            updateGlobalState:
                                                                false);
                                                      if (widget.isManaging) {
                                                        await updateSettings(
                                                            "numBackups",
                                                            appStateSettings[
                                                                    "numBackups"] -
                                                                1,
                                                            updateGlobalState:
                                                                false);
                                                      }
                                                      loadingIndeterminateKey
                                                          .currentState
                                                          ?.setVisibility(
                                                              false);
                                                    },
                                                    onSubmitLabel:
                                                        "delete".tr(),
                                                    onCancel: () {
                                                      popRoute(context);
                                                    },
                                                    onCancelLabel:
                                                        "cancel".tr(),
                                                  );
                                                },
                                                icon: appStateSettings[
                                                        "outlinedIcons"]
                                                    ? Icons.close_outlined
                                                    : Icons.close_rounded,
                                              ),
                                            ),
                                          ],
                                        )
                                      : SizedBox.shrink(),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              )
              .toList(),
        ],
      ),
    );
  }
}

double convertBytesToMB(String bytesString) {
  try {
    int bytes = int.parse(bytesString);
    double megabytes = bytes / (1024 * 1024);
    return megabytes;
  } catch (e) {
    print("Error parsing bytes string: $e");
    return 0.0; // or throw an exception, depending on your requirements
  }
}

class LoadingShimmerDriveFiles extends StatelessWidget {
  const LoadingShimmerDriveFiles({
    Key? key,
    required this.isManaging,
    required this.i,
  }) : super(key: key);

  final bool isManaging;
  final int i;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      period:
          Duration(milliseconds: (1000 + randomDouble[i % 10] * 520).toInt()),
      baseColor: appStateSettings["materialYou"]
          ? Theme.of(context).colorScheme.secondaryContainer
          : getColor(context, "lightDarkAccentHeavyLight"),
      highlightColor: appStateSettings["materialYou"]
          ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.2)
          : getColor(context, "lightDarkAccentHeavy").withAlpha(20),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8.0),
        child: Tappable(
          onTap: () {},
          borderRadius: 15,
          color: appStateSettings["materialYou"]
              ? Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withOpacity(0.5)
              : getColor(context, "lightDarkAccentHeavy").withOpacity(0.5),
          child: Container(
              padding:
                  EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          appStateSettings["outlinedIcons"]
                              ? Icons.description_outlined
                              : Icons.description_rounded,
                          color: Theme.of(context).colorScheme.secondary,
                          size: 30,
                        ),
                        SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadiusDirectional.all(
                                      Radius.circular(5)),
                                  color: Colors.white,
                                ),
                                height: 20,
                                width: 70 + randomDouble[i % 10] * 120 + 13,
                              ),
                              SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadiusDirectional.all(
                                      Radius.circular(5)),
                                  color: Colors.white,
                                ),
                                height: 14,
                                width: 90 + randomDouble[i % 10] * 120,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 13),
                  isManaging
                      ? Row(
                          children: [
                            ButtonIcon(
                                onTap: () {},
                                icon: appStateSettings["outlinedIcons"]
                                    ? Icons.close_outlined
                                    : Icons.close_rounded),
                            SizedBox(width: 5),
                            ButtonIcon(
                                onTap: () {},
                                icon: appStateSettings["outlinedIcons"]
                                    ? Icons.close_outlined
                                    : Icons.close_rounded),
                          ],
                        )
                      : SizedBox.shrink(),
                ],
              )),
        ),
      ),
    );
  }
}

Future<bool> saveDriveFileToDevice({
  required BuildContext boxContext,
  required BackupTransport client,
  required SyncFile fileToSave,
  bool isSync = false,
}) async {
  List<int> dataStore = await client.getFile(fileToSave.name);
  String fileName = "cashew-" +
      (fileToSave.name +
              cleanFileNameString(
                  (fileToSave.modifiedTime ?? DateTime.now()).toString()))
          .replaceAll(".sqlite", "") +
      ".sql";

  return await saveFile(
    boxContext: boxContext,
    dataStore: dataStore,
    dataString: null,
    fileName: fileName,
    successMessage: "backup-downloaded-success".tr(),
    errorMessage: "error-downloading".tr(),
  );
}

bool openBackupReminderPopupCheck(BuildContext context) {
  if ((appStateSettings["currentUserEmail"] == null ||
          appStateSettings["currentUserEmail"] == "") &&
      ((appStateSettings["numLogins"] + 1) % 7 == 0) &&
      appStateSettings["canShowBackupReminderPopup"] == true) {
    openPopup(
      context,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.cloud_outlined
          : Icons.cloud_rounded,
      iconScale: 0.9,
      title: "backup-your-data-reminder".tr(),
      description: "backup-your-data-reminder-description".tr() +
          " " +
          "self-hosted-backup".tr(),
      onSubmitLabel: "backup".tr().capitalizeFirst,
      onSubmit: () async {
        popRoute(context);
        await signInAndSync(context, next: () {});
      },
      onCancelLabel: "never".tr().capitalizeFirst,
      onCancel: () async {
        popRoute(context);
        await updateSettings("canShowBackupReminderPopup", false,
            updateGlobalState: false);
      },
      onExtraLabel: "later".tr().capitalizeFirst,
      onExtra: () {
        popRoute(context);
      },
    );
    return true;
  }
  return false;
}
