import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart' as globals;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// That the fork's own table is actually enrolled in sync.
///
/// `CategoryEnvelopes` arrived in 1.2.0 and two table enumerations were not
/// updated with it, which is the quietest possible failure: every screen keeps
/// working, every amount saves, and the plan simply never leaves the device it
/// was typed on. The household sees zeroes and nothing anywhere says why.
///
/// These are the two lists. Adding another fork-owned table means adding it to
/// both, and to this file.
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

  test('a restored backup pushes its envelopes, not just everything else',
      () async {
    // The shape a restore leaves behind: rows carrying the timestamps they were
    // exported with, which predate what peers think they already have from this
    // device. bumpAllModifiedTimestampsForResync exists to make them new again.
    final DateTime longBeforeTheLastSync = DateTime(2020, 1, 1);
    await db.createOrUpdateCategoryEnvelope(
      newCategoryEnvelope(
        categoryPk: '7',
        periodStart: DateTime(2026, 8, 1),
        amount: 23000,
        walletPk: '0',
      ),
      customDateTimeModified: longBeforeTheLastSync,
    );

    // Nothing to push: the row is older than the watermark, as a restored row
    // always is.
    expect(
      await db.getAllNewCategoryEnvelopes(DateTime(2026, 1, 1)),
      isEmpty,
      reason: 'a restored row starts out older than this device has synced to',
    );

    await db.bumpAllModifiedTimestampsForResync();

    expect(
      (await db.getAllNewCategoryEnvelopes(DateTime(2026, 1, 1)))
          .map((e) => e.envelopePk),
      ['7:2026-08'],
      reason: 'the restore must carry the plan to the household, like every '
          'other table it bumps',
    );
  });

  test('typing an amount wakes a sync cycle', () async {
    // watchAllForAutoSync is what turns a local write into a push. Left out of
    // it, an envelope only travelled when some unrelated table happened to be
    // written -- so a plan set and then left alone could sit on one device
    // indefinitely.
    final Future<void> woken = db.watchAllForAutoSync().first;

    await db.createOrUpdateCategoryEnvelope(newCategoryEnvelope(
      categoryPk: '7',
      periodStart: DateTime(2026, 8, 1),
      amount: 23000,
      walletPk: '0',
    ));

    await expectLater(
      woken.timeout(const Duration(seconds: 5)),
      completes,
    );
  });
}
