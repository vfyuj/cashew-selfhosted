import 'dart:io';

import 'package:cashew_selfhosted/database/envelopeMigration.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart' as globals;
import 'package:cashew_selfhosted/struct/settings.dart';
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

  test('46 to 48 creates the fork-owned envelopes table, with its account',
      () async {
    final connection = await verifier.startAt(46);
    final db = FinanceDatabase(connection);
    globals.database = db;
    addTearDown(db.close);

    await migrateAndValidateIgnoringClockSkew(verifier, db, 48);

    // Not just present in the schema -- actually usable, which is what the
    // envelopes screen needs on the very first launch after an upgrade or a
    // restored backup.
    expect(await db.getAllCategoryEnvelopes(), isEmpty);
  });

  test('a run that straddles a second boundary still validates', () async {
    // The flake this file used to have, made deterministic. Ten of upstream's
    // columns default to the moment their table was created, so the verifier's
    // reference schema and the migrated schema disagree by a second whenever
    // the two are built either side of one. Sleeping past a boundary makes that
    // happen every run instead of roughly one in thirty.
    final connection = await verifier.startAt(46);
    final db = FinanceDatabase(connection);
    globals.database = db;
    addTearDown(db.close);

    await Future.delayed(const Duration(milliseconds: 1100));

    await migrateAndValidateIgnoringClockSkew(verifier, db, 48);
  });

  test('the tolerance forgives the clock and nothing else', () {
    // What [migrateAndValidateIgnoringClockSkew] is allowed to swallow, pinned
    // line by line, because the cost of it widening is a schema change that
    // stops being noticed.
    expect(
      _isRealDifference('     Not equal: `NULL DEFAULT 1787185626` (expected) '
          'and `NULL DEFAULT 1787185625` (actual)'),
      false,
      reason: 'the same clock, read a second apart',
    );
    expect(
      _isRealDifference('     Not equal: `NULL DEFAULT 0` (expected) '
          'and `NULL DEFAULT 1` (actual)'),
      true,
      reason: 'a default that genuinely changed',
    );
    expect(
      _isRealDifference('     Not equal: `NULL DEFAULT 1787185626` (expected) '
          'and `NULL DEFAULT 1600000000` (actual)'),
      true,
      reason: 'both epoch-shaped, but years apart',
    );
    expect(
      _isRealDifference(
          '     Not equal: `NOT NULL DEFAULT 1787185626` (expected) '
          'and `NULL DEFAULT 1787185625` (actual)'),
      true,
      reason: 'the clock moved and so did the nullability',
    );
    expect(
      _isRealDifference('     Different types: Expected TEXT, got INT'),
      true,
    );
    expect(
      _isRealDifference('   The actual schema does not contain anything '
          'with this name.'),
      true,
    );
    expect(_isRealDifference('  date_time_modified:'), false);
    expect(_isRealDifference(''), false);
  });

  test('a 1.2.0 database stamps its envelopes with the primary account',
      () async {
    // 47 to 48 adds the column that says which account's currency an amount is
    // counted in. Every envelope written before it existed was a bare number in
    // whatever the primary account was at the time, so that is what it gets
    // stamped with -- which is what makes a plan read the same after the
    // upgrade as it did before it.
    final Directory directory =
        Directory.systemTemp.createTempSync('envelopes_wallet_fk');
    addTearDown(() => directory.deleteSync(recursive: true));
    final File file = File('${directory.path}/db.sqlite');

    // A database in the shape 1.2.0 left behind: an envelopes table with no
    // wallet_fk, a row in it, and the version number of the day.
    final setup = FinanceDatabase(NativeDatabase(file));
    await setup.customStatement('DROP TABLE IF EXISTS category_envelopes');
    await setup.customStatement(
      'CREATE TABLE category_envelopes ('
      'envelope_pk TEXT NOT NULL, '
      'category_fk TEXT NOT NULL REFERENCES categories (category_pk), '
      'period_start INTEGER NOT NULL, '
      'amount REAL NOT NULL, '
      'date_time_modified INTEGER, '
      'PRIMARY KEY (envelope_pk))',
    );
    await setup.customStatement(
      "INSERT INTO category_envelopes "
      '(envelope_pk, category_fk, period_start, amount) '
      "VALUES ('groceries:2026-08', 'groceries', 0, 50000)",
    );
    await setup.customStatement('PRAGMA user_version = 47');
    await setup.close();

    appStateSettings['selectedWalletPk'] = 'rubles';
    addTearDown(() => appStateSettings.remove('selectedWalletPk'));

    final db = FinanceDatabase(NativeDatabase(file));
    globals.database = db;
    addTearDown(db.close);

    final List<CategoryEnvelope> envelopes = await db.getAllCategoryEnvelopes();
    expect(envelopes.single.amount, 50000);
    expect(envelopes.single.walletFk, 'rubles');
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
        categoryPk: 'cat',
        periodStart: DateTime(2026, 8, 1),
        amount: 500,
        walletPk: '0'));
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
    await migrateAndValidateIgnoringClockSkew(verifier, db, 48);

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
    await migrateAndValidateIgnoringClockSkew(verifier, db, 48);

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
        categoryPk: 'groceries',
        periodStart: august,
        amount: 500,
        walletPk: '0'));
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
    await migrateAndValidateIgnoringClockSkew(verifier, db, 48);

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

/// [SchemaVerifier.migrateAndValidate], minus the one difference it reports
/// that is not one.
///
/// Ten columns across nine of upstream's tables are declared
/// `dateTime().withDefault(Constant(DateTime.now()))`, and drift bakes that
/// into the DDL as a literal epoch second: the moment that table happened to be
/// created. The verifier builds its reference schema and the migrated schema at
/// two different moments, so a run that straddles a second boundary finds every
/// one of those columns "different" by exactly one second. Measured at about
/// one run in thirty, and on upstream's tables as readily as on the fork's own
/// -- forcing a boundary between the two makes all ten report at once.
///
/// The defaults are not available to fix: they are upstream's columns, and
/// those stay identical column for column (CLAUDE.md). So the comparison is
/// what gives, and only for exactly this -- two current-era epoch seconds
/// within a minute of each other in the same `DEFAULT`. Every other difference
/// still fails the test, and so does a drift release that words its report
/// differently: a line this does not recognise is a line it does not forgive.
Future<void> migrateAndValidateIgnoringClockSkew(
  SchemaVerifier verifier,
  FinanceDatabase db,
  int expectedVersion,
) async {
  try {
    await verifier.migrateAndValidate(db, expectedVersion);
  } on SchemaMismatch catch (mismatch) {
    if (mismatch.explanation.split('\n').any(_isRealDifference)) rethrow;
  }
}

final RegExp _notEqual =
    RegExp(r'^Not equal: `(.*)` \(expected\) and `(.*)` \(actual\)$');

/// An epoch second of the current era -- ten digits, so 2001 to 2065 -- as
/// drift renders `DateTime.now()` into a column's `DEFAULT`. Narrow on purpose:
/// an ordinary integer default such as `DEFAULT 0` must keep counting as
/// itself.
final RegExp _clockDefault = RegExp(r'DEFAULT ([12]\d{9})\b');

/// Whether one line of a schema report says something actually went wrong.
///
/// The report is headings (`category_envelopes:`, ` columns:`,
/// `  date_time_modified:`), blank lines, and findings. A finding is forgiven
/// only when [_isClockSkew] recognises it; a line in no shape this knows counts
/// as a real difference, which is what stops this from quietly widening.
bool _isRealDifference(String line) {
  final String trimmed = line.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.endsWith(':')) return false;
  final RegExpMatch? notEqual = _notEqual.firstMatch(trimmed);
  if (notEqual == null) return true;
  return _isClockSkew(notEqual.group(1)!, notEqual.group(2)!) == false;
}

/// Whether [expected] and [actual] are the same column constraints, differing
/// only in when the clock baked into a `DEFAULT` was read.
bool _isClockSkew(String expected, String actual) {
  final List<int> expectedClocks = [];
  final List<int> actualClocks = [];
  String withoutClocks(String constraints, List<int> found) =>
      constraints.replaceAllMapped(_clockDefault, (Match match) {
        found.add(int.parse(match.group(1)!));
        return 'DEFAULT <clock>';
      });
  if (withoutClocks(expected, expectedClocks) !=
      withoutClocks(actual, actualClocks)) {
    return false;
  }
  // Nothing clock-shaped in a difference the verifier did report means the
  // difference is somewhere this cannot see. Not ours to forgive.
  if (expectedClocks.isEmpty) return false;
  for (int i = 0; i < expectedClocks.length; i++) {
    if ((expectedClocks[i] - actualClocks[i]).abs() > 60) return false;
  }
  return true;
}
