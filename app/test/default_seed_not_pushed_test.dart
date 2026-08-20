import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart' as globals;
import 'package:cashew_selfhosted/struct/liveSyncClient.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// That a device's first push does not plant the seeded defaults in the
/// household's feed.
///
/// `initializeDefaultDatabase()` stamps the default wallet and the eleven
/// default categories with `DateTime(0)` to mark them as seeded rather than
/// entered. That marker did nothing: the `getAllNewX` scans compare with `>=`
/// and the starting push cursor was `DateTime(0)` exactly, so the first push
/// sent them all. They then sat in the feed forever -- nothing edits a default
/// category, so nothing supersedes it -- and every device that joined the
/// household later pulled down eleven empty categories as real data.
///
/// Found on a real instance: seven such rows, `modified_at` of
/// -62167224120000, visible only on newly added accounts because the device
/// that pushed them had long since moved its own pull cursor past them.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  late FinanceDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    globals.sharedPreferences = await SharedPreferences.getInstance();
    db = FinanceDatabase(NativeDatabase.memory());
    globals.database = db;
    addTearDown(db.close);
  });

  TransactionCategory category(String pk, {required DateTime modified}) =>
      TransactionCategory(
        categoryPk: pk,
        name: 'Category $pk',
        dateCreated: DateTime(2026, 1, 1),
        dateTimeModified: modified,
        order: 0,
        income: false,
        methodAdded: MethodAdded.csv,
      );

  test('the seeded defaults stay out of the first push', () async {
    // Exactly how initializeDefaultDatabase() writes them.
    await db.createOrUpdateCategory(category('1', modified: DateTime.now()),
        customDateTimeModified: DateTime(0));
    await db.createOrUpdateWallet(
      TransactionWallet(
        walletPk: '0',
        name: 'Default',
        dateCreated: DateTime(2026, 1, 1),
        order: 0,
        currency: 'usd',
        decimals: 2,
      ),
      customDateTimeModified: DateTime(0),
    );

    expect(await db.getAllNewCategories(oldestPushCursor), isEmpty,
        reason: 'a seeded category must not reach the household feed');
    expect(await db.getAllNewWallets(oldestPushCursor), isEmpty,
        reason: 'nor the seeded wallet');
  });

  test('anything the user actually entered still goes', () async {
    await db.createOrUpdateCategory(
        category('groceries', modified: DateTime(2026, 8, 20)));

    final pushed = await db.getAllNewCategories(oldestPushCursor);
    expect(pushed.map((c) => c.categoryPk), ['groceries']);
  });

  test('a row that was never stamped still goes', () async {
    // The scans OR in isNull(), and that has to keep working: an unstamped row
    // is unknown, not known-to-be-seeded.
    await db.createOrUpdateCategory(category('unstamped', modified: DateTime(0)),
        customDateTimeModified: null);

    final pushed = await db.getAllNewCategories(oldestPushCursor);
    expect(pushed.map((c) => c.categoryPk), contains('unstamped'));
  });
}
