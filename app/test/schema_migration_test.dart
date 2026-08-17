import 'dart:io';

import 'package:cashew_selfhosted/database/envelopeMigration.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart' as globals;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';

/// Runs the real migration against a real SQLite database.
///
/// The fork's first schema change since forking adds a table, and a table that
/// is not created is not a visible failure: every query against it throws
/// inside a stream, the screen that reads it renders empty, and nothing says
/// why. `migrateAndValidate` compares the migrated database against the
/// generated definition of the target version, so a step that silently did
/// nothing fails here instead.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SchemaVerifier verifier;

  setUpAll(() async {
    verifier = SchemaVerifier(GeneratedHelper());
    // deleteBudget writes a delete log, and that path reaches the app's
    // globals. Point them at the test's own database and an empty preference
    // store rather than mocking them out -- the point of this file is to run
    // the real code.
    SharedPreferences.setMockInitialValues({});
    globals.sharedPreferences = await SharedPreferences.getInstance();
  });

  test('46 to 47 creates the fork-owned envelopes table', () async {
    final connection = await verifier.startAt(46);
    final db = FinanceDatabase(connection);
    globals.database = db;
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 47);

    // Not just present in the schema -- actually usable, which is what the
    // envelopes screen needs on the very first launch after an upgrade or a
    // restored backup.
    expect(await db.getAllCategoryEnvelopes(), isEmpty);
  });

  test('a backup from a newer upstream Cashew still gets the envelopes table',
      () async {
    // Upstream Cashew did not stop at the release this fork branched from: its
    // 6.x backups declare schema 48, above the fork's 47. Drift runs migrations
    // upward only, so opening one runs no step at all -- and none of those
    // backups has the fork's own table in it, because it is the fork's.
    //
    // This was not hypothetical. It is what an owner's imported backup did:
    // "Migrating from: 48 to 47", then an envelopes screen that read empty and
    // swallowed every amount typed into it.
    final Directory directory =
        Directory.systemTemp.createTempSync('envelopes_downgrade');
    addTearDown(() => directory.deleteSync(recursive: true));
    final File file = File('${directory.path}/db.sqlite');

    // A database in the shape a newer upstream leaves behind: no
    // category_envelopes, and a version number above ours.
    final setup = FinanceDatabase(NativeDatabase(file));
    await setup.customStatement('DROP TABLE IF EXISTS category_envelopes');
    await setup.customStatement('PRAGMA user_version = 48');
    await setup.close();

    final db = FinanceDatabase(NativeDatabase(file));
    globals.database = db;
    addTearDown(db.close);

    // Usable, not merely declared: this is the exact call the envelopes screen
    // makes, and the one that used to throw.
    expect(await db.getAllCategoryEnvelopes(), isEmpty);
    await db.createOrUpdateCategory(TransactionCategory(
      categoryPk: 'cat',
      name: 'Groceries',
      dateCreated: DateTime(2026, 1, 1),
      order: 0,
      income: false,
      methodAdded: MethodAdded.csv,
    ));
    await db.createOrUpdateCategoryEnvelope(newCategoryEnvelope(
        categoryPk: 'cat', periodStart: DateTime(2026, 8, 1), amount: 500));
    expect((await db.getAllCategoryEnvelopes()).single.amount, 500);
  });

  test('a 1.1.x database converts its envelope budgets on first open',
      () async {
    // The scenario this release is actually judged on: a backup taken by the
    // previous version, where every main category has an auto-created envelope
    // budget, opened by this one.
    final connection = await verifier.startAt(46);
    final db = FinanceDatabase(connection);
    globals.database = db;
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 47);

    await db.createOrUpdateCategory(TransactionCategory(
      categoryPk: 'cat-groceries',
      name: 'Groceries',
      dateCreated: DateTime(2026, 1, 1),
      order: 0,
      income: false,
      methodAdded: MethodAdded.csv,
    ));
    await db.createOrUpdateBudget(Budget(
      // The shape ensureMainCategoryBudgetsExist wrote: pk == category pk.
      budgetPk: 'cat-groceries',
      name: 'Groceries',
      amount: 500,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      categoryFks: const ['cat-groceries'],
      income: false,
      archived: false,
      addedTransactionsOnly: false,
      periodLength: 1,
      reoccurrence: BudgetReoccurence.monthly,
      dateCreated: DateTime(2026, 1, 1),
      pinned: false,
      order: 0,
      walletFk: '0',
      // What the withdrawn per-period-amounts feature left behind: 400 from
      // June, 500 from August.
      sharedAllMembersEver: [
        '${DateTime(2026, 6, 1).millisecondsSinceEpoch}=400',
        '${DateTime(2026, 8, 1).millisecondsSinceEpoch}=500',
      ],
      isAbsoluteSpendingLimit: false,
    ));

    await migrateEnvelopeBudgetsToCategoryEnvelopes();

    final List<CategoryEnvelope> envelopes = await db.getAllCategoryEnvelopes();
    expect(envelopes.map((e) => e.envelopePk),
        ['cat-groceries:2026-06', 'cat-groceries:2026-08']);
    expect(envelopes.map((e) => e.amount), [400, 500]);

    // The budget is gone, and gone with a tombstone so the household's other
    // devices lose it too.
    expect(await db.getAllBudgets(), isEmpty);
    expect(
      (await db.getAllNewDeleteLogs(DateTime(2020)))
          .where((log) => log.type == DeleteLogType.Budget)
          .map((log) => log.entryPk),
      ['cat-groceries'],
    );

    // Running again is a no-op rather than a second conversion.
    await migrateEnvelopeBudgetsToCategoryEnvelopes();
    expect((await db.getAllCategoryEnvelopes()).length, 2);
  });

  test('the plan follows the category list through every change', () async {
    // What the envelopes screen renders is derived from the categories, so
    // these are the cases where a row has to appear, disappear or come back
    // without anybody reconciling anything.
    final connection = await verifier.startAt(46);
    final db = FinanceDatabase(connection);
    globals.database = db;
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 47);

    Future<TransactionCategory> category(String pk,
        {String? mainCategoryPk}) async {
      final TransactionCategory category = TransactionCategory(
        categoryPk: pk,
        name: pk,
        dateCreated: DateTime(2026, 1, 1),
        order: 0,
        income: false,
        mainCategoryPk: mainCategoryPk,
        methodAdded: MethodAdded.csv,
      );
      await db.createOrUpdateCategory(category);
      return category;
    }

    Future<EnvelopePlan> plan() async => buildEnvelopePlan(
        await db.getAllCategories(), await db.getAllCategoryEnvelopes());

    final DateTime august = DateTime(2026, 8, 1);

    // A category created now is planned for now -- no envelope row required.
    await category('groceries');
    expect((await plan()).categories.map((c) => c.categoryPk), ['groceries']);
    expect((await plan()).amountFor('groceries', august), isNull);

    await db.createOrUpdateCategoryEnvelope(newCategoryEnvelope(
        categoryPk: 'groceries', periodStart: august, amount: 500));
    expect((await plan()).amountFor('groceries', august), 500);

    // Demoted to a subcategory: it stops being something you plan, but its
    // amounts are kept rather than deleted...
    await category('groceries', mainCategoryPk: 'food');
    expect((await plan()).categories, isEmpty);
    expect((await db.getAllCategoryEnvelopes()).length, 1);

    // ...so promoting it back restores the plan it had.
    await category('groceries');
    expect((await plan()).amountFor('groceries', august), 500);

    // Deleting the category takes its envelopes with it, tombstones included,
    // so the household's other devices drop them too.
    await db.deleteCategory('groceries', 0);
    expect(await db.getAllCategoryEnvelopes(), isEmpty);
    expect(
      (await db.getAllNewDeleteLogs(DateTime(2020)))
          .where((log) => log.type == DeleteLogType.CategoryEnvelope)
          .map((log) => log.entryPk),
      ['groceries:2026-08'],
    );
  });

  test('a budget somebody made by hand survives every launch', () async {
    // The conversion runs on every launch, so this is the case that has to hold
    // forever, not just once: an ordinary budget that happens to target a
    // single main category must never be converted away.
    final connection = await verifier.startAt(46);
    final db = FinanceDatabase(connection);
    globals.database = db;
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 47);

    await db.createOrUpdateCategory(TransactionCategory(
      categoryPk: 'cat-groceries',
      name: 'Groceries',
      dateCreated: DateTime(2026, 1, 1),
      order: 0,
      income: false,
      methodAdded: MethodAdded.csv,
    ));
    await db.createOrUpdateBudget(Budget(
      budgetPk: 'a-real-uuid',
      name: 'Groceries overspend watch',
      amount: 500,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      categoryFks: const ['cat-groceries'],
      income: false,
      archived: false,
      addedTransactionsOnly: false,
      periodLength: 1,
      reoccurrence: BudgetReoccurence.monthly,
      dateCreated: DateTime(2026, 1, 1),
      pinned: false,
      order: 0,
      walletFk: '0',
      // Left over from the withdrawn personal-budgets feature.
      sharedMembers: const ['7'],
      isAbsoluteSpendingLimit: false,
    ));

    await migrateEnvelopeBudgetsToCategoryEnvelopes();
    await migrateEnvelopeBudgetsToCategoryEnvelopes();

    final List<Budget> budgets = await db.getAllBudgets();
    expect(budgets.map((b) => b.budgetPk), ['a-real-uuid']);
    // The dead column is cleared on the way past, which is what makes it a
    // plain upstream budget again.
    expect(budgets.single.sharedMembers, isNull);
    expect(await db.getAllCategoryEnvelopes(), isEmpty);
  });
}
