import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:drift/drift.dart' show Value;

// Per-budget visibility: which household member a budget belongs to, so that
// one member's own budgets do not clutter the other's screen.
//
// STORAGE: this is kept in `Budgets.sharedMembers` - see the comment on that
// column in database/tables.dart. Nothing else in the app may read or write
// that column; go through this file. Same reasoning as
// struct/budgetPeriodAmounts.dart, which borrowed the neighbouring
// `sharedAllMembersEver` for the same reason: the Drift schema stays identical
// to upstream Cashew's so its backups still import (CLAUDE.md), which rules out
// a column of our own, and these columns have been dead since the Firestore
// sharing they belonged to was removed.
//
// MODEL: a single owner, stored as the owner's server user id.
//
//   null / empty  -> shared with the whole household
//   ["7"]         -> personal to user 7
//
// WHAT THIS IS NOT: privacy. A personal budget still syncs, and its row is
// physically present in every household member's database - it is filtered out
// when drawing the screen, nowhere else. That is deliberate, not an oversight:
// the over-allocation check in struct/mainCategoryBudgets.dart has to count
// budgets the viewer cannot see, or a household could silently over-commit a
// main category. It hides a budget from the app, not from a person with a
// SQLite browser.

// WHY THIS COLUMN AND NOT `sharedKey`: the two surviving bits of Firestore UI
// that would render this data - the "Created by" line on budgetPage and the
// payer chips on addTransactionPage - are both gated on `sharedKey != null`,
// and nothing writes sharedKey. Borrowing sharedMembers leaves both of those
// dead paths dead. Writing sharedKey would wake them up and show a raw user id
// on screen.

/// Budgets whose owner cannot be resolved are shared. Anything that is not
/// exactly one entry of digits is not something this file wrote - an
/// original-Cashew backup has real member IDs here, and those must read as
/// "shared" rather than being mistaken for a user id.
final RegExp _ownerFormat = RegExp(r'^\d+$');

/// The server user id this budget is personal to, or null when it is shared.
int? budgetOwner(Budget budget) {
  final List<String> members = budget.sharedMembers ?? const [];
  if (members.length != 1) return null;
  final RegExpMatch? match = _ownerFormat.firstMatch(members.first);
  if (match == null) return null;
  return int.tryParse(members.first);
}

/// Whether [budget] is personal to somebody.
bool isPersonalBudget(Budget budget) => budgetOwner(budget) != null;

/// Returns a copy owned by [ownerUserId], or shared when that is null.
Budget withBudgetOwner(Budget budget, int? ownerUserId) {
  return budget.copyWith(
    sharedMembers: Value(ownerUserId == null ? null : ['$ownerUserId']),
  );
}

/// The signed-in account's server user id, or null when signed out.
///
/// Read from the cached profile rather than fetched, so this never blocks and
/// keeps working offline - the same reason the account page reads it.
int? get currentBudgetViewerId => cachedServerProfile?.id;

/// Whether this account shares its data with anyone, and so has anybody to
/// hide a budget from.
bool get budgetVisibilityApplies =>
    cachedServerProfile?.sharesHousehold == true;

/// Who a newly created custom budget belongs to.
///
/// Null unless the account actually shares a household. Marking a solo
/// account's budgets as personal would be invisible to them -- the switch is
/// not even drawn -- and would then hide every one of them the moment a second
/// member was added. This way a household starts out seeing everything that
/// already existed, and only budgets created afterwards default to personal.
int? get defaultOwnerForNewBudget =>
    budgetVisibilityApplies ? currentBudgetViewerId : null;

/// Whether [budget] should be drawn for [viewerUserId].
///
/// A budget with no owner is everyone's. A personal budget is only its owner's.
/// Signed out, everything is visible: there is no "somebody else" to hide from,
/// and hiding rows on a device with no account would just lose them.
bool isBudgetVisibleTo(Budget budget, int? viewerUserId) {
  final int? owner = budgetOwner(budget);
  if (owner == null) return true;
  if (viewerUserId == null) return true;
  return owner == viewerUserId;
}

/// Whether [budget] should be drawn for the signed-in account.
bool isBudgetVisibleToCurrentUser(Budget budget) =>
    isBudgetVisibleTo(budget, currentBudgetViewerId);

/// Drops the budgets belonging to other household members.
///
/// For **display only**. Never filter a list that feeds a total: the whole
/// point of syncing personal budgets is that they still count towards their
/// main category's allocation.
List<Budget> visibleBudgets(List<Budget> budgets) =>
    budgets.where(isBudgetVisibleToCurrentUser).toList();

/// [visibleBudgets] over a stream, for wrapping a query feeding a list widget.
Stream<List<Budget>> visibleBudgetsStream(Stream<List<Budget>> source) =>
    source.map(visibleBudgets);

/// Whether [budget] belongs to somebody else, and so may be listed but never
/// opened, edited, reordered or unhidden.
bool isOtherMembersBudget(Budget budget) =>
    !isBudgetVisibleToCurrentUser(budget);
