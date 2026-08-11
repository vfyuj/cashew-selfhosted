import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:drift/drift.dart' show Value;

// Per-period budget amounts: what a budget's target was during each of its
// past periods, so that raising this month's number does not silently rewrite
// what every finished month is measured against.
//
// STORAGE: this is kept in `Budgets.sharedAllMembersEver` - see the comment on
// that column in database/tables.dart. Nothing else in the app may read or
// write that column; go through this file. The Drift schema has to stay
// identical to upstream Cashew's so its backups still import (CLAUDE.md), which
// rules out a column or table of our own, and that dead column is the least
// bad home available. See specs/backlog/BL-006-per-period-budget-amounts.md.
//
// MODEL: effective-from. Each entry means "from this period onward, until the
// next entry, the target was this much". `Budget.amount` always equals the
// *current* period's amount, which is what keeps every code path that has not
// been taught about history - plus backups, sync and upstream Cashew - reading
// a correct value.

// One "from this period onward, the target was this much" entry.
class BudgetAmountChange {
  const BudgetAmountChange({required this.from, required this.amount});

  final DateTime from;
  final double amount;
}

// `<periodStartEpochMillis>=<amount>`, e.g. "1751328000000=400.0".
//
// Deliberately strict. An original-Cashew backup has real member IDs in this
// column, and they must be ignored rather than misread as amounts - that is
// what keeps upstream backups importable. Nothing that is not exactly this
// shape is ever parsed.
final RegExp _entryFormat =
    RegExp(r'^(\d+)=(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)$');

// The budget's amount history, oldest first. Empty for a budget whose amount
// has never been changed, and for one carrying upstream member IDs.
List<BudgetAmountChange> budgetAmountHistory(Budget budget) {
  final List<BudgetAmountChange> changes = [];
  for (String entry in budget.sharedAllMembersEver ?? const []) {
    final RegExpMatch? match = _entryFormat.firstMatch(entry);
    if (match == null) continue;
    final int? millis = int.tryParse(match.group(1)!);
    final double? amount = double.tryParse(match.group(2)!);
    if (millis == null || amount == null) continue;
    changes.add(BudgetAmountChange(
      from: DateTime.fromMillisecondsSinceEpoch(millis),
      amount: amount,
    ));
  }
  changes.sort((a, b) => a.from.compareTo(b.from));
  return changes;
}

List<String> encodeAmountHistory(List<BudgetAmountChange> changes) {
  return [
    for (BudgetAmountChange change in changes)
      "${change.from.millisecondsSinceEpoch}=${change.amount}"
  ];
}

// The target that applied during the period containing [forDate].
double budgetAmountForPeriod(Budget budget, DateTime forDate) {
  if ((budget.sharedAllMembersEver ?? const []).isEmpty) return budget.amount;
  return budgetAmountForPeriodStart(budget, getBudgetDate(budget, forDate).start);
}

// The pure half of the resolution, split out so it can be tested without a
// database (getBudgetDate reaches for the `database` global).
double budgetAmountForPeriodStart(Budget budget, DateTime periodStart) {
  final List<BudgetAmountChange> history = budgetAmountHistory(budget);
  if (history.isEmpty) return budget.amount;
  // Anything at or before the first entry keeps the first entry's amount, so a
  // budget's periods from before it was ever adjusted read as they always did.
  BudgetAmountChange resolved = history.first;
  for (BudgetAmountChange change in history) {
    if (change.from.isAfter(periodStart)) break;
    resolved = change;
  }
  return resolved.amount;
}

// Recomputes the history column for a save.
//
// [previous] is the row as it currently exists in the database, or null when
// creating. [updated] is the row about to be written, and is expected to have
// carried [previous]'s history across unchanged.
Budget withUpdatedAmountHistory({
  required Budget? previous,
  required Budget updated,
}) {
  // A new budget has no past, and a budget whose cycle changed no longer has
  // period boundaries its old keys line up with - clearing beats remapping.
  if (previous == null || _cycleChanged(previous, updated)) {
    return updated.copyWith(sharedAllMembersEver: Value(null));
  }
  if (previous.amount == updated.amount) return updated;

  final DateTime currentPeriodStart =
      getBudgetDate(updated, DateTime.now()).start;
  // Backing up a day from a period boundary always lands in the period before
  // it, for every cycle Cashew offers (the shortest is one day). For a custom
  // budget, which has only ever had one period, this returns that same period
  // and the seed below is correctly skipped.
  final DateTime previousPeriodStart = getBudgetDate(
          updated, currentPeriodStart.subtract(const Duration(days: 1)))
      .start;
  final List<BudgetAmountChange> history = budgetAmountHistory(previous);

  // Keyed by period so that changing the amount twice in one month replaces
  // rather than appends. Later writes win, which is why the new amount goes in
  // last.
  final Map<int, double> byPeriodStart = {};
  // The seed. Without it a lone "from April, 500" entry would apply 500 to
  // January too, which is the exact bug this feature exists to fix.
  //
  // It is anchored to the previous period rather than to the budget's own
  // startDate: every envelope BL-001 creates starts on the first of the month
  // it was created in, so a startDate anchor would write no seed at all for a
  // budget adjusted during its first month - and the history view still shows
  // earlier periods for it. Any date strictly before the current period start
  // resolves identically, since anything older falls back to the oldest entry.
  if (history.isEmpty && previousPeriodStart.isBefore(currentPeriodStart)) {
    byPeriodStart[previousPeriodStart.millisecondsSinceEpoch] = previous.amount;
  }
  for (BudgetAmountChange change in history) {
    byPeriodStart[change.from.millisecondsSinceEpoch] = change.amount;
  }
  byPeriodStart[currentPeriodStart.millisecondsSinceEpoch] = updated.amount;

  // Nothing worth storing: the only period on record is the current one, which
  // Budget.amount already says.
  if (byPeriodStart.length <= 1) {
    return updated.copyWith(sharedAllMembersEver: Value(null));
  }

  final List<BudgetAmountChange> changes = [
    for (MapEntry<int, double> entry in byPeriodStart.entries)
      BudgetAmountChange(
        from: DateTime.fromMillisecondsSinceEpoch(entry.key),
        amount: entry.value,
      )
  ]..sort((a, b) => a.from.compareTo(b.from));

  return updated.copyWith(
      sharedAllMembersEver: Value(encodeAmountHistory(changes)));
}

// Whether saving [updated] would throw away a history that actually exists.
//
// Changing the cycle is the only action that destroys the record, and it sits
// on the same edit screen as the amount, so the user is asked before it
// happens rather than finding out afterwards. Returns false when there is no
// history to lose, so the prompt never fires on a budget that has never been
// adjusted.
bool amountHistoryWouldBeCleared({
  required Budget? previous,
  required Budget updated,
}) {
  if (previous == null) return false;
  if (budgetAmountHistory(previous).isEmpty) return false;
  return _cycleChanged(previous, updated);
}

// Whether the period boundaries themselves moved.
bool _cycleChanged(Budget previous, Budget updated) {
  return previous.reoccurrence != updated.reoccurrence ||
      previous.periodLength != updated.periodLength ||
      previous.startDate != updated.startDate;
}
