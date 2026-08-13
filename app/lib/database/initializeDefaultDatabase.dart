import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/defaultCategories.dart';
import 'package:cashew_selfhosted/struct/mainCategoryBudgets.dart';

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

  // Runs on every launch, so it backfills the envelope budget for the default
  // categories above, for categories that predate this feature, and for any
  // that arrived over sync. Idempotent, and local only - never blocks on the
  // network, per specs/01-local-first-invariant.md.
  await ensureMainCategoryBudgetsExist();

  // Same idea: subcategories created before color inheritance existed still
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
