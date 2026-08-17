import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/database/envelopeMigration.dart';
import 'package:cashew_selfhosted/struct/defaultCategories.dart';

//Initialize default values in database
Future<bool> initializeDefaultDatabase() async {
  //Initialize default categories, but not after a backup load
  if (isDatabaseImportedOnThisSession != true &&
      (await database.getAllCategories()).length <= 0) {
    await createDefaultCategories();
  }

  if ((await database.getAllWallets()).length <= 0) {
    await database.createOrUpdateWallet(
      defaultWallet(),
      customDateTimeModified: DateTime(0),
    );
  }

  // Converts the budgets that used to stand in for envelopes into rows of the
  // CategoryEnvelopes table. Deliberately runs on every launch rather than once
  // per device -- the data can arrive long after the app does, via an imported
  // backup or a sync pull. Local only, and never blocks on the network, per
  // specs/01-local-first-invariant.md.
  await migrateEnvelopeBudgetsToCategoryEnvelopes();

  // Subcategories created before color inheritance existed still
  // carry their own stale color until this runs once.
  await database.reconcileSubCategoryColors();
  return true;
}

Future<bool> createDefaultCategories() async {
  print("Creating default categories");
  for (TransactionCategory category in defaultCategories()) {
    try {
      await database.getCategory(category.categoryPk).$2;
    } catch (e) {
      print(
          e.toString() + " default category does not already exist, creating");
      await database.createOrUpdateCategory(category,
          customDateTimeModified: DateTime(0));
    }
  }
  return true;
}

TransactionWallet defaultWallet() {
  return TransactionWallet(
    walletPk: "0",
    name: "default-account-name".tr(),
    dateCreated: DateTime.now(),
    order: 0,
    currency: getDevicesDefaultCurrencyCode(),
    dateTimeModified: null,
    decimals: 2,
    homePageWidgetDisplay: defaultWalletHomePageWidgetDisplay,
  );
}
