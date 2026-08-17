// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
//@dart=2.12
import 'package:drift/drift.dart';

class Wallets extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Wallets(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> walletPk = GeneratedColumn<String>(
      'wallet_pk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<String> colour = GeneratedColumn<String>(
      'colour', aliasedName, true,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: false);
  late final GeneratedColumn<String> iconName = GeneratedColumn<String>(
      'icon_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'date_created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
      'order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<int> decimals = GeneratedColumn<int>(
      'decimals', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: Constant(2));
  late final GeneratedColumn<String> homePageWidgetDisplay =
      GeneratedColumn<String>('home_page_widget_display', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant(null));
  @override
  List<GeneratedColumn> get $columns => [
        walletPk,
        name,
        colour,
        iconName,
        dateCreated,
        dateTimeModified,
        order,
        currency,
        decimals,
        homePageWidgetDisplay
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallets';
  @override
  Set<GeneratedColumn> get $primaryKey => {walletPk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Wallets createAlias(String alias) {
    return Wallets(attachedDatabase, alias);
  }
}

class Categories extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Categories(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> categoryPk = GeneratedColumn<String>(
      'category_pk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<String> colour = GeneratedColumn<String>(
      'colour', aliasedName, true,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: false);
  late final GeneratedColumn<String> iconName = GeneratedColumn<String>(
      'icon_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> emojiIconName = GeneratedColumn<String>(
      'emoji_icon_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'date_created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
      'order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<bool> income = GeneratedColumn<bool>(
      'income', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("income" IN (0, 1))'),
      defaultValue: const Constant(false));
  late final GeneratedColumn<int> methodAdded = GeneratedColumn<int>(
      'method_added', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<String> mainCategoryPk = GeneratedColumn<String>(
      'main_category_pk', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES categories (category_pk)'),
      defaultValue: const Constant(null));
  @override
  List<GeneratedColumn> get $columns => [
        categoryPk,
        name,
        colour,
        iconName,
        emojiIconName,
        dateCreated,
        dateTimeModified,
        order,
        income,
        methodAdded,
        mainCategoryPk
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  Set<GeneratedColumn> get $primaryKey => {categoryPk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Categories createAlias(String alias) {
    return Categories(attachedDatabase, alias);
  }
}

class Objectives extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Objectives(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> objectivePk = GeneratedColumn<String>(
      'objective_pk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
      'order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<String> colour = GeneratedColumn<String>(
      'colour', aliasedName, true,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'date_created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  late final GeneratedColumn<String> iconName = GeneratedColumn<String>(
      'icon_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> emojiIconName = GeneratedColumn<String>(
      'emoji_icon_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<bool> income = GeneratedColumn<bool>(
      'income', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("income" IN (0, 1))'),
      defaultValue: const Constant(false));
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
      'pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("pinned" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns => [
        objectivePk,
        name,
        amount,
        order,
        colour,
        dateCreated,
        dateTimeModified,
        iconName,
        emojiIconName,
        income,
        pinned
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'objectives';
  @override
  Set<GeneratedColumn> get $primaryKey => {objectivePk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Objectives createAlias(String alias) {
    return Objectives(attachedDatabase, alias);
  }
}

class Transactions extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Transactions(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> transactionPk = GeneratedColumn<String>(
      'transaction_pk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<String> categoryFk = GeneratedColumn<String>(
      'category_fk', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES categories (category_pk)'));
  late final GeneratedColumn<String> subCategoryFk = GeneratedColumn<String>(
      'sub_category_fk', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES categories (category_pk)'),
      defaultValue: const Constant(null));
  late final GeneratedColumn<String> walletFk = GeneratedColumn<String>(
      'wallet_fk', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES wallets (wallet_pk)'));
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'date_created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  late final GeneratedColumn<DateTime> originalDateDue =
      GeneratedColumn<DateTime>('original_date_due', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  late final GeneratedColumn<bool> income = GeneratedColumn<bool>(
      'income', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("income" IN (0, 1))'),
      defaultValue: const Constant(false));
  late final GeneratedColumn<int> periodLength = GeneratedColumn<int>(
      'period_length', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<int> reoccurrence = GeneratedColumn<int>(
      'reoccurrence', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<bool> upcomingTransactionNotification =
      GeneratedColumn<bool>(
          'upcoming_transaction_notification', aliasedName, true,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("upcoming_transaction_notification" IN (0, 1))'),
          defaultValue: const Constant(true));
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
      'type', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<bool> paid = GeneratedColumn<bool>(
      'paid', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("paid" IN (0, 1))'),
      defaultValue: const Constant(false));
  late final GeneratedColumn<bool> createdAnotherFutureTransaction =
      GeneratedColumn<bool>(
          'created_another_future_transaction', aliasedName, true,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("created_another_future_transaction" IN (0, 1))'),
          defaultValue: const Constant(false));
  late final GeneratedColumn<bool> skipPaid = GeneratedColumn<bool>(
      'skip_paid', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("skip_paid" IN (0, 1))'),
      defaultValue: const Constant(false));
  late final GeneratedColumn<int> methodAdded = GeneratedColumn<int>(
      'method_added', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<String> transactionOwnerEmail =
      GeneratedColumn<String>('transaction_owner_email', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> transactionOriginalOwnerEmail =
      GeneratedColumn<String>(
          'transaction_original_owner_email', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> sharedKey = GeneratedColumn<String>(
      'shared_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> sharedOldKey = GeneratedColumn<String>(
      'shared_old_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<int> sharedStatus = GeneratedColumn<int>(
      'shared_status', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> sharedDateUpdated =
      GeneratedColumn<DateTime>('shared_date_updated', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<String> sharedReferenceBudgetPk =
      GeneratedColumn<String>('shared_reference_budget_pk', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> objectiveFk = GeneratedColumn<String>(
      'objective_fk', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES objectives (objective_pk)'));
  @override
  List<GeneratedColumn> get $columns => [
        transactionPk,
        name,
        amount,
        note,
        categoryFk,
        subCategoryFk,
        walletFk,
        dateCreated,
        dateTimeModified,
        originalDateDue,
        income,
        periodLength,
        reoccurrence,
        upcomingTransactionNotification,
        type,
        paid,
        createdAnotherFutureTransaction,
        skipPaid,
        methodAdded,
        transactionOwnerEmail,
        transactionOriginalOwnerEmail,
        sharedKey,
        sharedOldKey,
        sharedStatus,
        sharedDateUpdated,
        sharedReferenceBudgetPk,
        objectiveFk
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  Set<GeneratedColumn> get $primaryKey => {transactionPk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Transactions createAlias(String alias) {
    return Transactions(attachedDatabase, alias);
  }
}

class Budgets extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Budgets(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> budgetPk = GeneratedColumn<String>(
      'budget_pk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  late final GeneratedColumn<String> colour = GeneratedColumn<String>(
      'colour', aliasedName, true,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
      'start_date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
      'end_date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<String> categoryFks = GeneratedColumn<String>(
      'category_fks', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> categoryFksExclude =
      GeneratedColumn<String>('category_fks_exclude', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<bool> addedTransactionsOnly =
      GeneratedColumn<bool>('added_transactions_only', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("added_transactions_only" IN (0, 1))'),
          defaultValue: const Constant(false));
  late final GeneratedColumn<int> periodLength = GeneratedColumn<int>(
      'period_length', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<int> reoccurrence = GeneratedColumn<int>(
      'reoccurrence', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'date_created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
      'pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("pinned" IN (0, 1))'),
      defaultValue: const Constant(false));
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
      'order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<String> walletFk = GeneratedColumn<String>(
      'wallet_fk', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES wallets (wallet_pk)'));
  late final GeneratedColumn<String> budgetTransactionFilters =
      GeneratedColumn<String>('budget_transaction_filters', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant(null));
  late final GeneratedColumn<String> memberTransactionFilters =
      GeneratedColumn<String>('member_transaction_filters', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant(null));
  late final GeneratedColumn<String> sharedKey = GeneratedColumn<String>(
      'shared_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<int> sharedOwnerMember = GeneratedColumn<int>(
      'shared_owner_member', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> sharedDateUpdated =
      GeneratedColumn<DateTime>('shared_date_updated', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<String> sharedMembers = GeneratedColumn<String>(
      'shared_members', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> sharedAllMembersEver =
      GeneratedColumn<String>('shared_all_members_ever', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<bool> isAbsoluteSpendingLimit =
      GeneratedColumn<bool>('is_absolute_spending_limit', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("is_absolute_spending_limit" IN (0, 1))'),
          defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        budgetPk,
        name,
        amount,
        colour,
        startDate,
        endDate,
        categoryFks,
        categoryFksExclude,
        addedTransactionsOnly,
        periodLength,
        reoccurrence,
        dateCreated,
        dateTimeModified,
        pinned,
        order,
        walletFk,
        budgetTransactionFilters,
        memberTransactionFilters,
        sharedKey,
        sharedOwnerMember,
        sharedDateUpdated,
        sharedMembers,
        sharedAllMembersEver,
        isAbsoluteSpendingLimit
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets';
  @override
  Set<GeneratedColumn> get $primaryKey => {budgetPk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Budgets createAlias(String alias) {
    return Budgets(attachedDatabase, alias);
  }
}

class CategoryBudgetLimits extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CategoryBudgetLimits(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> categoryLimitPk = GeneratedColumn<String>(
      'category_limit_pk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> categoryFk = GeneratedColumn<String>(
      'category_fk', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES categories (category_pk)'));
  late final GeneratedColumn<String> budgetFk = GeneratedColumn<String>(
      'budget_fk', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES budgets (budget_pk)'));
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  @override
  List<GeneratedColumn> get $columns =>
      [categoryLimitPk, categoryFk, budgetFk, amount, dateTimeModified];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'category_budget_limits';
  @override
  Set<GeneratedColumn> get $primaryKey => {categoryLimitPk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  CategoryBudgetLimits createAlias(String alias) {
    return CategoryBudgetLimits(attachedDatabase, alias);
  }
}

class AssociatedTitles extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AssociatedTitles(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> associatedTitlePk =
      GeneratedColumn<String>('associated_title_pk', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> categoryFk = GeneratedColumn<String>(
      'category_fk', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES categories (category_pk)'));
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'date_created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
      'order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<bool> isExactMatch = GeneratedColumn<bool>(
      'is_exact_match', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_exact_match" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        associatedTitlePk,
        categoryFk,
        title,
        dateCreated,
        dateTimeModified,
        order,
        isExactMatch
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'associated_titles';
  @override
  Set<GeneratedColumn> get $primaryKey => {associatedTitlePk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AssociatedTitles createAlias(String alias) {
    return AssociatedTitles(attachedDatabase, alias);
  }
}

class AppSettings extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AppSettings(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> settingsPk = GeneratedColumn<int>(
      'settings_pk', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  late final GeneratedColumn<String> settingsJSON = GeneratedColumn<String>(
      'settings_j_s_o_n', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateUpdated = GeneratedColumn<DateTime>(
      'date_updated', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [settingsPk, settingsJSON, dateUpdated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  Set<GeneratedColumn> get $primaryKey => {settingsPk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AppSettings createAlias(String alias) {
    return AppSettings(attachedDatabase, alias);
  }
}

class ScannerTemplates extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ScannerTemplates(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> scannerTemplatePk =
      GeneratedColumn<String>('scanner_template_pk', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'date_created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  late final GeneratedColumn<String> templateName = GeneratedColumn<String>(
      'template_name', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<String> contains = GeneratedColumn<String>(
      'contains', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  late final GeneratedColumn<String> titleTransactionBefore =
      GeneratedColumn<String>('title_transaction_before', aliasedName, false,
          additionalChecks: GeneratedColumn.checkTextLength(),
          type: DriftSqlType.string,
          requiredDuringInsert: true);
  late final GeneratedColumn<String> titleTransactionAfter =
      GeneratedColumn<String>('title_transaction_after', aliasedName, false,
          additionalChecks: GeneratedColumn.checkTextLength(),
          type: DriftSqlType.string,
          requiredDuringInsert: true);
  late final GeneratedColumn<String> amountTransactionBefore =
      GeneratedColumn<String>('amount_transaction_before', aliasedName, false,
          additionalChecks: GeneratedColumn.checkTextLength(),
          type: DriftSqlType.string,
          requiredDuringInsert: true);
  late final GeneratedColumn<String> amountTransactionAfter =
      GeneratedColumn<String>('amount_transaction_after', aliasedName, false,
          additionalChecks: GeneratedColumn.checkTextLength(),
          type: DriftSqlType.string,
          requiredDuringInsert: true);
  late final GeneratedColumn<String> defaultCategoryFk =
      GeneratedColumn<String>('default_category_fk', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: true,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'REFERENCES categories (category_pk)'));
  late final GeneratedColumn<String> walletFk = GeneratedColumn<String>(
      'wallet_fk', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES wallets (wallet_pk)'));
  late final GeneratedColumn<bool> ignore = GeneratedColumn<bool>(
      'ignore', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("ignore" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        scannerTemplatePk,
        dateCreated,
        dateTimeModified,
        templateName,
        contains,
        titleTransactionBefore,
        titleTransactionAfter,
        amountTransactionBefore,
        amountTransactionAfter,
        defaultCategoryFk,
        walletFk,
        ignore
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scanner_templates';
  @override
  Set<GeneratedColumn> get $primaryKey => {scannerTemplatePk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ScannerTemplates createAlias(String alias) {
    return ScannerTemplates(attachedDatabase, alias);
  }
}

class DeleteLogs extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DeleteLogs(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> deleteLogPk = GeneratedColumn<String>(
      'delete_log_pk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> entryPk = GeneratedColumn<String>(
      'entry_pk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
      'type', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> dateTimeModified =
      GeneratedColumn<DateTime>('date_time_modified', aliasedName, false,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: Constant(DateTime.now()));
  @override
  List<GeneratedColumn> get $columns =>
      [deleteLogPk, entryPk, type, dateTimeModified];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'delete_logs';
  @override
  Set<GeneratedColumn> get $primaryKey => {deleteLogPk};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DeleteLogs createAlias(String alias) {
    return DeleteLogs(attachedDatabase, alias);
  }
}

class DatabaseAtV42 extends GeneratedDatabase {
  DatabaseAtV42(QueryExecutor e) : super(e);
  late final Wallets wallets = Wallets(this);
  late final Categories categories = Categories(this);
  late final Objectives objectives = Objectives(this);
  late final Transactions transactions = Transactions(this);
  late final Budgets budgets = Budgets(this);
  late final CategoryBudgetLimits categoryBudgetLimits =
      CategoryBudgetLimits(this);
  late final AssociatedTitles associatedTitles = AssociatedTitles(this);
  late final AppSettings appSettings = AppSettings(this);
  late final ScannerTemplates scannerTemplates = ScannerTemplates(this);
  late final DeleteLogs deleteLogs = DeleteLogs(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        wallets,
        categories,
        objectives,
        transactions,
        budgets,
        categoryBudgetLimits,
        associatedTitles,
        appSettings,
        scannerTemplates,
        deleteLogs
      ];
  @override
  int get schemaVersion => 42;
}
