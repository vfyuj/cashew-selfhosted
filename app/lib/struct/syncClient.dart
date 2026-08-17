import 'dart:async';
import 'package:async/async.dart';
import 'dart:convert';
import 'package:cashew_selfhosted/database/binary_string_conversion.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/accountAndBackup.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/util/debouncer.dart';
import 'package:cashew_selfhosted/widgets/walletEntry.dart';
// import 'package:drift/web.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

bool isSyncBackupFile(String? backupFileName) {
  if (backupFileName == null) return false;
  return backupFileName.contains("sync-");
}

bool isCurrentDeviceSyncBackupFile(String? backupFileName) {
  if (backupFileName == null) return false;
  return backupFileName == getCurrentDeviceSyncBackupFileName();
}

String getCurrentDeviceSyncBackupFileName({String? clientIDForSync}) {
  if (clientIDForSync == null) clientIDForSync = clientID;
  return "sync-" + clientIDForSync + ".sqlite";
}

String getDeviceFromSyncBackupFileName(String? backupFileName) {
  if (backupFileName == null) return "";
  return (backupFileName).replaceAll("sync-", "").split("-")[0];
}

String getCurrentDeviceName() {
  return sanitizeFilenameComponent((clientID).split("-")[0]);
}

/// Strips everything but alphanumerics/underscores from a device name before
/// it goes into a backup filename. Device names (e.g. macOS's "Macintosh
/// intel m") often contain spaces, and the self-hosted server's file routes
/// store whatever raw path segment they're given rather than URL-decoding
/// it -- so an un-sanitized name round-trips back as a filename with a
/// literal "%20" in it instead of a space.
String sanitizeFilenameComponent(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
}

Future<DateTime> getDateOfLastSyncedWithClient(String clientIDForSync) async {
  String string =
      sharedPreferences.getString("dateOfLastSyncedWithClient") ?? "{}";
  String lastTimeSynced =
      (jsonDecode(string)[clientIDForSync] ?? "").toString();
  if (lastTimeSynced == "") return DateTime(0);
  try {
    return DateTime.parse(lastTimeSynced);
  } catch (e) {
    print("Error getting time of last sync " + e.toString());
    return DateTime(0);
  }
}

Future<bool> setDateOfLastSyncedWithClient(
    String clientIDForSync, DateTime dateTimeSynced) async {
  String string =
      sharedPreferences.getString("dateOfLastSyncedWithClient") ?? "{}";
  dynamic parsed = jsonDecode(string);
  parsed[clientIDForSync] = dateTimeSynced.toString();
  await sharedPreferences.setString(
      "dateOfLastSyncedWithClient", jsonEncode(parsed));
  return true;
}

// if changeMadeSync show loading and check if syncEveryChange is turned on
Timer? syncTimeoutTimer;
Debouncer backupDebounce = Debouncer(milliseconds: 5000);
Future<bool> createSyncBackup(
    {bool changeMadeSync = false,
    bool changeMadeSyncWaitForDebounce = true}) async {
  if (appStateSettings["hasSignedIn"] == false) return false;
  if (errorSigningInDuringCloud == true) return false;
  if (appStateSettings["backupSync"] == false) return false;
  if (changeMadeSync == true && appStateSettings["syncEveryChange"] == false)
    return false;
  // create the auto syncs after 10 seconds of no changes
  if (changeMadeSync == true &&
      (appStateSettings["syncEveryChange"] == true && kIsWeb) &&
      changeMadeSyncWaitForDebounce == true) {
    print("Running sync debouncer");
    backupDebounce.run(() {
      createSyncBackup(
          changeMadeSync: true, changeMadeSyncWaitForDebounce: false);
    });
  }

  print("Creating sync backup");
  if (changeMadeSync)
    loadingIndeterminateKey.currentState?.setVisibility(true, opacity: 0.4);
  if (syncTimeoutTimer?.isActive == true) {
    // openSnackbar(SnackbarMessage(title: "Please wait..."));
    if (changeMadeSync)
      loadingIndeterminateKey.currentState?.setVisibility(false);
    return false;
  } else {
    syncTimeoutTimer = Timer(Duration(milliseconds: 5000), () {
      syncTimeoutTimer!.cancel();
    });
  }

  if (selfHostedSession == null) {
    if (changeMadeSync)
      loadingIndeterminateKey.currentState?.setVisibility(false);
    return false;
  }
  // Silent, non-blocking refresh -- see specs/01-local-first-invariant.md
  await selfHostedRefresh();

  SelfHostedClient client = SelfHostedClient(selfHostedSession!);

  List<SyncFile> files = await client.listFiles();

  for (SyncFile file in files) {
    if (isCurrentDeviceSyncBackupFile(file.name)) {
      try {
        await client.deleteFile(file.name);
      } catch (e) {
        print(e.toString());
      }
    }
  }
  await createBackup(null,
      silentBackup: true, deleteOldBackups: true, clientIDForSync: clientID);
  if (changeMadeSync)
    loadingIndeterminateKey.currentState?.setVisibility(false);
  return true;
}

class SyncLog {
  SyncLog({
    this.deleteLogType,
    this.updateLogType,
    required this.transactionDateTime,
    required this.pk,
    this.itemToUpdate,
  });

  DeleteLogType? deleteLogType;
  UpdateLogType? updateLogType;
  DateTime? transactionDateTime;
  String pk;
  dynamic itemToUpdate;

  @override
  String toString() {
    return "SyncLog(deleteLogType: $deleteLogType, updateLogType: $updateLogType, transactionDateTime: $transactionDateTime, pk: $pk, itemToUpdate: $itemToUpdate)";
  }
}

// Only allow one sync at a time
bool canSyncData = true;

bool requestSyncDataCancel = false;

CancelableCompleter<bool> syncDataCompleter = CancelableCompleter(onCancel: () {
  requestSyncDataCancel = true;
});

Future<dynamic> cancelAndPreventSyncOperation() async {
  requestSyncDataCancel = true;
  return await syncDataCompleter.operation.cancel();
}

Future<bool> runForceSignIn(BuildContext context) async {
  if (appStateSettings["forceAutoLogin"] == false) return false;
  if (appStateSettings["hasSignedIn"] == false) return false;
  if (selfHostedSession == null) return false;
  return await selfHostedRefresh();
}

Future<bool> syncData(BuildContext context) async {
  // Create a new instance of the completer
  if (syncDataCompleter.isCompleted) {
    syncDataCompleter = CancelableCompleter(onCancel: () {
      requestSyncDataCancel = true;
    });
  }

  syncDataCompleter.complete(Future.value(_syncData(context)));
  return syncDataCompleter.operation.value;
}

// load the latest backup and import any newly modified data into the db
Future<bool> _syncData(BuildContext context) async {
  if (canSyncData == false) return false;
  // Syncing data seems to fail on iOS debug mode (at least on iPad).
  // When actually creating the entries, it seems the device disconnects.
  // It works on release though.

  if (appStateSettings["backupSync"] == false) return false;
  if (appStateSettings["hasSignedIn"] == false) return false;
  if (errorSigningInDuringCloud == true) return false;

  // We only want to prevent this if silent sign in, otherwise we can show the user the google login popup every time on web?
  // Prevent sign-in on web - background sign-in cannot access Google Drive etc.
  if (kIsWeb &&
      !entireAppLoaded &&
      appStateSettings["webForceLoginPopupOnLaunch"] != true) return false;

  canSyncData = false;

  if (selfHostedSession == null) {
    canSyncData = true;
    return false;
  }
  // Silent, non-blocking refresh -- see specs/01-local-first-invariant.md
  await selfHostedRefresh();

  SelfHostedClient client = SelfHostedClient(selfHostedSession!);

  await createSyncBackup();

  List<SyncFile> filesToDownloadSyncChanges = await client.listFiles();

  print("LOADING SYNC DB");
  DateTime syncStarted = DateTime.now();
  List<SyncLog> syncLogs = [];
  List<SyncFile> filesSyncing = [];

  int currentFileIndex = 0;
  loadingProgressKey.currentState?.setProgressPercentage(0);
  for (SyncFile file in filesToDownloadSyncChanges) {
    if (requestSyncDataCancel == true) {
      loadingProgressKey.currentState?.setProgressPercentage(0);
      loadingIndeterminateKey.currentState?.setVisibility(false);
      print("Cancelling sync!");
      requestSyncDataCancel = false;
      return false;
    }

    loadingIndeterminateKey.currentState?.setVisibility(true);

    // we don't want to restore this clients backup
    if (isCurrentDeviceSyncBackupFile(file.name)) continue;

    // check if this is a new sync from this specific client
    DateTime lastSynced = await getDateOfLastSyncedWithClient(
        getDeviceFromSyncBackupFileName(file.name));

    print("COMPARING TIMES");
    print(file.modifiedTime?.toLocal());
    print(lastSynced);
    print(lastSynced != file.modifiedTime!.toLocal());
    if (file.modifiedTime == null ||
        lastSynced.isAfter(file.modifiedTime!.toLocal()) ||
        lastSynced == file.modifiedTime!.toLocal()) {
      print(
          "no need to restore backup from this client, no new backup file to pull data from");
      continue;
    }

    print("SYNCING WITH " + file.name);
    filesSyncing.add(file);

    List<int> dataStore = await client.getFile(file.name);

    FinanceDatabase databaseSync;

    if (kIsWeb) {
      String dataEncoded = bin2str.encode(Uint8List.fromList(dataStore));

      try {
        databaseSync = await constructDb('syncdb',
            initialDataWeb: Uint8List.fromList(dataStore));
      } catch (e) {
        double megabytes = dataEncoded.length / (1024 * 1024);
        await openPopup(
          context,
          title: "syncing-failed".tr(),
          description: e.toString() +
              "\n\n" +
              megabytes.toString() +
              " MB in size" +
              " when syncing with " +
              file.name.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.sync_problem_outlined
              : Icons.sync_problem_rounded,
          onSubmit: () {
            popRoute(context);
          },
          onSubmitLabel: "ok".tr(),
        );
        // final html.Storage localStorage = html.window.localStorage;
        // localStorage["moor_db_str_syncdb"] = "";
        throw (e);
      }
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dbFolder.path, 'syncdb.sqlite'));
      await dbFile.writeAsBytes(dataStore);
      databaseSync = await constructDb('syncdb');
    }

    try {
      List<TransactionWallet> newWallets =
          await databaseSync.getAllNewWallets(lastSynced);
      for (TransactionWallet newEntry in newWallets) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.TransactionWallet,
          pk: newEntry.walletPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }
      print("NEW WALLETS");
      print(newWallets);

      List<TransactionCategory> newCategories =
          await databaseSync.getAllNewCategories(lastSynced);
      for (TransactionCategory newEntry in newCategories) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.TransactionCategory,
          pk: newEntry.categoryPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }
      print("NEW CATEGORIES");
      print(newCategories);

      List<Budget> newBudgets = await databaseSync.getAllNewBudgets(lastSynced);
      for (Budget newEntry in newBudgets) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.Budget,
          pk: newEntry.budgetPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }
      print("NEW BUDGETS");
      print(newBudgets);

      List<CategoryBudgetLimit> newCategoryBudgetLimits =
          await databaseSync.getAllNewCategoryBudgetLimits(lastSynced);
      for (CategoryBudgetLimit newEntry in newCategoryBudgetLimits) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.CategoryBudgetLimit,
          pk: newEntry.categoryLimitPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }
      print("NEW CATEGORY LIMITS");
      print(newCategoryBudgetLimits);

      // Fork-owned table -- see the CategoryEnvelopes comment in tables.dart.
      // Collected here as well as in liveSyncClient because this legacy
      // whole-database path is still reachable from "manage synced devices".
      List<CategoryEnvelope> newCategoryEnvelopes =
          await databaseSync.getAllNewCategoryEnvelopes(lastSynced);
      for (CategoryEnvelope newEntry in newCategoryEnvelopes) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.CategoryEnvelope,
          pk: newEntry.envelopePk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      List<Transaction> newTransactions =
          await databaseSync.getAllNewTransactions(lastSynced);
      for (Transaction newEntry in newTransactions) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.Transaction,
          pk: newEntry.transactionPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }
      print("NEW TRANSACTIONS");
      print(newTransactions);

      List<TransactionAssociatedTitle> newTitles =
          await databaseSync.getAllNewAssociatedTitles(lastSynced);
      for (TransactionAssociatedTitle newEntry in newTitles) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.TransactionAssociatedTitle,
          pk: newEntry.associatedTitlePk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }
      print("NEW TITLES");
      print(newTitles);

      for (ScannerTemplate newEntry
          in (await databaseSync.getAllNewScannerTemplates(lastSynced))) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.ScannerTemplate,
          pk: newEntry.scannerTemplatePk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      List<Objective> newObjectives =
          await databaseSync.getAllNewObjectives(lastSynced);
      for (Objective newEntry in newObjectives) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.Objective,
          pk: newEntry.objectivePk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }
      print("NEW OBJECTIVES");
      print(newObjectives);

      List<DeleteLog> deleteLogs =
          await databaseSync.getAllNewDeleteLogs(lastSynced);

      for (DeleteLog deleteLog in deleteLogs) {
        syncLogs.add(SyncLog(
          deleteLogType: deleteLog.type,
          updateLogType: null,
          pk: deleteLog.entryPk,
          transactionDateTime: deleteLog.dateTimeModified,
        ));
      }

      print("DELETE LOGS");
      print(deleteLogs);
    } catch (e) {
      print("Syncing error and failed: " + e.toString());
      filesSyncing.remove(file);
      await databaseSync.close();
      loadingProgressKey.currentState?.setProgressPercentage(1);
      canSyncData = true;
      await openPopup(
        context,
        title: "syncing-failed".tr(),
        description: "sync-fail-reason".tr() + "\n\n" + file.name.toString(),
        descriptionWidget: Padding(
          padding: const EdgeInsetsDirectional.only(top: 8, bottom: 12),
          child: CodeBlock(text: e.toString()),
        ),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.sync_problem_outlined
            : Icons.sync_problem_rounded,
        onCancel: () {
          popRoute(context);
        },
        onCancelLabel: "close".tr(),
        onSubmit: () {
          chooseBackup(context, isManaging: true, isClientSync: true);
        },
        onSubmitLabel: "manage".tr(),
      );
      // By returning we do not update the time last synced!
      return false;
    }

    currentFileIndex = currentFileIndex + 1;
    loadingProgressKey.currentState?.setProgressPercentage(
        currentFileIndex / filesToDownloadSyncChanges.length);

    await databaseSync.close();
  }

  await database.processSyncLogs(syncLogs);
  for (SyncFile file in filesSyncing)
    setDateOfLastSyncedWithClient(getDeviceFromSyncBackupFileName(file.name),
        file.modifiedTime?.toLocal() ?? DateTime(0));

  try {
    print("UPDATED WALLET CURRENCY");
    await database.getWalletInstance(appStateSettings["selectedWalletPk"]);
  } catch (e) {
    print("Selected wallet not found: " + e.toString());
    await setPrimaryWallet((await database.getAllWallets())[0].walletPk);
  }

  updateSettings(
    "lastSynced",
    syncStarted.toString(),
    pagesNeedingRefresh: [],
    updateGlobalState: getIsFullScreen(context) ? true : false,
  );

  loadingProgressKey.currentState?.setProgressPercentage(0.999);

  Future.delayed(Duration(milliseconds: 300), () {
    loadingProgressKey.currentState?.setProgressPercentage(1);
  });

  canSyncData = true;

  print("DONE SYNCING");
  return true;
}
