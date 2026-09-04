import 'accounts.dart';
import 'local_date.dart';
import 'money.dart';
import 'projection.dart';

/// An open advance (02 §7): balance > 0, with ageing = days since the oldest
/// unsettled debit (FIFO: credits settle the oldest handed-out amounts first).
final class OpenAdvance {
  const OpenAdvance._({
    required this.accountId,
    required this.memberId,
    required this.balance,
    required this.oldestUnsettled,
    required this.ageDays,
  });

  /// `Advance – {member}` account.
  final String accountId;

  /// The holder.
  final String? memberId;

  /// Money still out with the person.
  final Paise balance;

  /// Date of the oldest debit not yet fully settled.
  final LocalDate oldestUnsettled;

  /// Days from [oldestUnsettled] to the as-of date.
  final int ageDays;
}

/// Every open advance in the book as of [asOf] — *money out with people*, aged.
/// Derives purely from `advance` account balances: no separate state to drift.
List<OpenAdvance> openAdvances(
  LedgerState state,
  Chart chart, {
  required LocalDate asOf,
}) {
  final out = <OpenAdvance>[];
  for (final a in chart.byClass(AccountClass.advance)) {
    final balance = state.balances[a.id];
    if (!balance.isDebit) continue;
    // FIFO settlement over counted lines in statement order.
    final debits = <({LocalDate date, int remaining})>[];
    final carried = state
        .opening[a.id]
        .raw; // a certified opening behaves as the oldest debit
    if (carried > 0) {
      debits.add((date: LocalDate.fromEpochDays(-1 << 40), remaining: carried));
    }
    for (final p in state.counted) {
      for (final l in p.entry.lines) {
        if (l.accountId != a.id) continue;
        if (l.amount.isDebit) {
          debits.add((date: p.entry.accountingDate, remaining: l.amount.raw));
        } else {
          var credit = -l.amount.raw;
          for (var i = 0; i < debits.length && credit > 0; i++) {
            final take = credit < debits[i].remaining
                ? credit
                : debits[i].remaining;
            debits[i] = (
              date: debits[i].date,
              remaining: debits[i].remaining - take,
            );
            credit -= take;
          }
        }
      }
    }
    final oldest = debits.firstWhere((d) => d.remaining > 0);
    final since = oldest.date.toEpochDays() < -1000000 ? asOf : oldest.date;
    out.add(
      OpenAdvance._(
        accountId: a.id,
        memberId: a.memberId,
        balance: balance,
        oldestUnsettled: since,
        ageDays: since.daysUntil(asOf),
      ),
    );
  }
  return out;
}
