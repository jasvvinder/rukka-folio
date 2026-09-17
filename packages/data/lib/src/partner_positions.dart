// Put in / took out / share, per partner (13 §3.2 row S14) — derived, never
// stored.
//
// 02 §7.1 🔒 names **three distinct events** that post to a Partner Current
// A/c and says *keeping them distinct is the whole model*:
//
// | Event                                            | Posting                                |
// |--------------------------------------------------|----------------------------------------|
// | Owner pays a business cost from their own pocket  | `Dr Expense · Cr Partner Current`      |
// | Owner takes money out of the business             | `Dr Partner Current · Cr money a/c`    |
// | Profit share credited                             | `Dr Profit Distributed · Cr Partner Current` |
//
// The engine derives settlement capacity and drift (`partners.dart`,
// A-02-62…67) but has no function for this split, so it is derived **here**,
// once, as a pure function of (projected state, chart): S14, S14.1 and any
// export then read the same figures and cannot drift apart, and no widget ever
// classifies a posting.
//
// Pure: no I/O, no clock, no RNG, no Flutter (03 §3.3 — the projector and
// everything derived from it are functions of their inputs).
import 'package:core_ledger/core_ledger.dart';
import 'package:meta/meta.dart';

/// Which of 02 §7.1's three events a Partner Current A/c line belongs to.
enum PartnerFlow {
  /// `Dr Expense · Cr Partner Current` — a business cost paid from their own
  /// pocket. 🔒 *The payer never books an expense in their own book*: this is
  /// a claim on the business, never an expense of theirs.
  putIn,

  /// `Dr Partner Current · Cr money` — money taken out of the business.
  tookOut,

  /// `Dr Profit Distributed · Cr Partner Current` — a profit share, or the
  /// `interest` line of the same entry (02 §7.1 *Interest on capital*). A loss
  /// posts the mirror and reads as a negative share (ADR 2026-09-05e §8).
  share,

  /// Anything 02 §7.1 does not classify.
  ///
  /// ⚠️ SPEC: 02 §7.1 names exactly three events, and two real postings land
  /// outside them — an owner's **cash** contribution
  /// (`Dr money · Cr Partner Current`, the opening contribution of ADR
  /// 2026-09-09c §4) and a **partner-to-partner** settlement
  /// (`Dr {over-funded} · Cr {under-funded}`, §7.1 settlement route 2). 13
  /// §3.2 row S14's *put in* may well be meant to cover the first, but 02
  /// §7.1's row says *pays a business cost*, so folding a cash contribution
  /// into [putIn] would be inventing behaviour. They are named here instead of
  /// being folded silently into one of the three, and reported to the owner.
  other,
}

/// One owner's position, split by the event that posted each line (13 §3.2
/// row S14). Integer paise throughout (CLAUDE.md rule 1).
///
/// Every figure is stated the way the screen says it:
/// * [putIn], [tookOut] are **positive magnitudes** — what they put in, what
///   they took out;
/// * [share] and [other] are **signed as what they added to the business's
///   debt to this owner** — a loss share is negative;
/// * [net] is what the business owes them today, so a **negative** [net] is a
///   Dr balance: *they owe the business* (02 §7.1 🔒 *Debit balances are real
///   and must be shown*).
///
/// The four reconcile to the balance by construction:
/// `net == putIn − tookOut + share + other`, which [reconciles] asserts.
@immutable
final class PartnerLedgerPosition {
  /// Creates a position.
  const PartnerLedgerPosition({
    required this.accountId,
    required this.putIn,
    required this.tookOut,
    required this.share,
    required this.other,
    required this.net,
  });

  /// The Partner Current A/c — the identity 02 §7.1's ratio and remainder rule
  /// both key on (ADR 2026-09-13 §3).
  final String accountId;

  /// Business costs they paid from their own pocket.
  final Paise putIn;

  /// Money they took out of the business.
  final Paise tookOut;

  /// Profit (and interest) credited to them; negative for a loss.
  final Paise share;

  /// Lines 02 §7.1 does not classify — see [PartnerFlow.other].
  final Paise other;

  /// What the business owes them; negative = they owe the business.
  final Paise net;

  /// True when they owe the business (a Dr balance).
  bool get owesBusiness => net.raw < 0;

  /// The reconciliation the split must satisfy.
  bool get reconciles => putIn - tookOut + share + other == net;

  @override
  bool operator ==(Object other) =>
      other is PartnerLedgerPosition &&
      other.accountId == accountId &&
      other.putIn == putIn &&
      other.tookOut == tookOut &&
      other.share == share &&
      other.other == this.other &&
      other.net == net;

  @override
  int get hashCode => Object.hash(accountId, putIn, tookOut, share, other, net);

  @override
  String toString() =>
      'PartnerLedgerPosition($accountId, in ${putIn.raw}, out ${tookOut.raw}, '
      'share ${share.raw}, other ${other.raw}, net ${net.raw})';
}

/// Which event posted [line] of [entry] to a Partner Current A/c (02 §7.1).
///
/// Read from the entry itself — the accounts on the other side, and the
/// `share` / `interest` tags `Verbs.profitDistribution` writes — never from a
/// kind label, because 02 fixes six kinds and several partner postings share
/// one (`took_credit` carries a cost paid from pocket, `money_out` a drawing).
/// A line whose counterpart is not in [chart] is [PartnerFlow.other]: an
/// unreadable counterpart is never guessed at.
PartnerFlow classifyPartnerLine({
  required Entry entry,
  required Line line,
  required Chart chart,
}) {
  // Interest and share are two lines of one distribution entry (02 §7.1
  // *Order of operations*) and both are the third event.
  if (line.tag == 'share' || line.tag == 'interest') return PartnerFlow.share;
  final counterparts = <Account>[];
  for (final l in entry.lines) {
    if (identical(l, line) || l.accountId == line.accountId) continue;
    final a = chart.maybeAccount(l.accountId);
    if (a == null) return PartnerFlow.other;
    counterparts.add(a);
  }
  if (counterparts.isEmpty) return PartnerFlow.other;
  if (counterparts.any(
    (a) =>
        a.accountClass == AccountClass.equitySystem &&
        a.systemRole == SystemRole.profitDistributed,
  )) {
    return PartnerFlow.share;
  }
  if (line.amount.isCredit &&
      counterparts.every(
        (a) => a.accountClass == AccountClass.categoryExpense,
      )) {
    return PartnerFlow.putIn;
  }
  if (line.amount.isDebit && counterparts.every((a) => a.isMoney)) {
    return PartnerFlow.tookOut;
  }
  return PartnerFlow.other;
}

/// Every Partner Current A/c of [chart], split by 02 §7.1's three events, in
/// the chart's creation order (the order S14 lists owners in, and the tiebreak
/// of §7.1's remainder rule).
///
/// Reads only the **counted** entries (02 §9: heads of accepted amend chains,
/// advance requests still pending excluded) and the certified opening vector,
/// so a reversal and its mirror net to zero here exactly as they do in the
/// balance. A book with no partner accounts — every *Just me* business (02
/// §7.1 🔒 *Shared ownership is optional*) — has no positions at all, which is
/// how a caller learns not to say the word *partner*.
///
/// A certified opening balance on a Partner Current A/c (02 §8.1 carry
/// forward) rides in [PartnerLedgerPosition.other]: the events behind it were
/// counted in a closed year and are no longer in `counted`, so classifying it
/// as one of the three would be a guess.
List<PartnerLedgerPosition> partnerPositions(LedgerState state, Chart chart) {
  final partners = chart.byClass(AccountClass.partner);
  if (partners.isEmpty) return const [];
  final putIn = <String, Paise>{};
  final tookOut = <String, Paise>{};
  final share = <String, Paise>{};
  final other = <String, Paise>{};
  for (final p in partners) {
    putIn[p.id] = Paise.zero;
    tookOut[p.id] = Paise.zero;
    share[p.id] = Paise.zero;
    other[p.id] = -state.opening[p.id];
  }
  for (final projected in state.counted) {
    for (final line in projected.entry.lines) {
      final id = line.accountId;
      if (!putIn.containsKey(id)) continue;
      switch (classifyPartnerLine(
        entry: projected.entry,
        line: line,
        chart: chart,
      )) {
        // A credit adds to what the business owes them; the bucket states the
        // magnitude, so the sign is flipped once, here.
        case PartnerFlow.putIn:
          putIn[id] = putIn[id]! - line.amount;
        case PartnerFlow.tookOut:
          tookOut[id] = tookOut[id]! + line.amount;
        case PartnerFlow.share:
          share[id] = share[id]! - line.amount;
        case PartnerFlow.other:
          other[id] = other[id]! - line.amount;
      }
    }
  }
  return [
    for (final p in partners)
      PartnerLedgerPosition(
        accountId: p.id,
        putIn: putIn[p.id]!,
        tookOut: tookOut[p.id]!,
        share: share[p.id]!,
        other: other[p.id]!,
        net: -state.balances[p.id],
      ),
  ];
}
