import 'accounts.dart';
import 'local_date.dart';
import 'money.dart';
import 'projection.dart';
import 'verbs.dart';

/// Interest on capital (02 §7.1, optional, off by default): per partner,
/// `average daily balance × rate × days ÷ 365`, computed from the ledger — never
/// typed — and rounded **half-up to the nearest paisa**. Only credit balances
/// earn; a debit balance is charged at the same rate unless
/// [chargeDebitBalances] is false. Days are counted inclusively over
/// [from]..[to], using each day's end-of-day balance. Returns signed paise per
/// partner account id (negative = charged).
Map<String, Paise> interestOnCapital(
  LedgerState state,
  Chart chart, {
  required List<PartnerShare> partners,
  required LocalDate from,
  required LocalDate to,
  required int rateBasisPoints,
  bool chargeDebitBalances = true,
}) {
  if (rateBasisPoints < 0) {
    throw ArgumentError.value(rateBasisPoints, 'rateBasisPoints');
  }
  if (to.isBefore(from)) throw ArgumentError('to precedes from');
  final out = <String, Paise>{};
  for (final p in partners) {
    final id = p.account.id;
    // Balance carried into `from`: certified opening plus every counted line dated before it.
    var balance = state.opening[id];
    final byDay = <int, Paise>{}; // epoch day → net change that day
    for (final pe in state.counted) {
      for (final l in pe.entry.lines) {
        if (l.accountId != id) continue;
        final date = pe.entry.accountingDate;
        if (date.isBefore(from)) {
          balance += l.amount;
        } else if (!date.isAfter(to)) {
          final k = date.toEpochDays();
          byDay[k] = (byDay[k] ?? Paise.zero) + l.amount;
        }
      }
    }
    // Σ credit-balance-days (credit positive), in paise·days.
    var creditDays = 0;
    for (var day = from.toEpochDays(); day <= to.toEpochDays(); day++) {
      balance += byDay[day] ?? Paise.zero;
      final credit = -balance.raw;
      creditDays += (credit < 0 && !chargeDebitBalances) ? 0 : credit;
    }
    out[id] = Paise(
      roundHalfUp(
        numerator: creditDays * rateBasisPoints,
        denominator: 10000 * 365,
      ),
    );
  }
  return out;
}

/// Whether the business could pay every partner out today (02 §7.1 *Settlement
/// capacity*): money accounts against total partner credit balances.
final class SettlementCapacity {
  const SettlementCapacity._(this.moneyTotal, this.partnerCreditTotal);

  /// Sum of every money account (signed; an overdraft reduces it).
  final Paise moneyTotal;

  /// Sum of partner **credit** balances — what the business owes its owners.
  /// Partners in debit owe the business and are not owed anything.
  final Paise partnerCreditTotal;

  /// "The business can settle all partner balances today."
  bool get canSettleAll => moneyTotal >= partnerCreditTotal;

  /// "Short by ₹X to settle all balances." Zero when [canSettleAll].
  Paise get shortBy =>
      canSettleAll ? Paise.zero : partnerCreditTotal - moneyTotal;
}

/// Computes [SettlementCapacity].
SettlementCapacity settlementCapacity(LedgerState state, Chart chart) {
  var money = Paise.zero;
  var owed = Paise.zero;
  for (final a in chart.accounts) {
    final b = state.balances[a.id];
    if (a.isMoney) money += b;
    if (a.accountClass == AccountClass.partner && b.isCredit) owed += -b;
  }
  return SettlementCapacity._(money, owed);
}

/// One partner whose balance exceeds the group average by more than the margin
/// (02 §7.1 *Drift visibility*): informational, never a demand.
final class PartnerDrift {
  const PartnerDrift._(this.accountId, this.owed, this.aboveAverage);

  /// The Partner Current A/c.
  final String accountId;

  /// What the business owes them (credit positive; negative = they owe it).
  final Paise owed;

  /// How far above the average of all partners.
  final Paise aboveAverage;
}

/// Partners more than [margin] above the group average of *business owes them*.
List<PartnerDrift> partnerDrift(
  LedgerState state,
  Chart chart, {
  required Paise margin,
}) {
  final partners = chart.byClass(AccountClass.partner);
  if (partners.isEmpty) return const [];
  final owed = {for (final p in partners) p.id: -state.balances[p.id]};
  final average = Paise(floorDiv(Paise.sum(owed.values).raw, partners.length));
  return [
    for (final p in partners)
      if (owed[p.id]! - average > margin)
        PartnerDrift._(p.id, owed[p.id]!, owed[p.id]! - average),
  ];
}
