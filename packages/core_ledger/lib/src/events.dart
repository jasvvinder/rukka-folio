import 'balances.dart';
import 'hlc.dart';
import 'local_date.dart';
import 'money.dart';

/// Anything that travels as a signed envelope and feeds the projector (03 §3.3):
/// entries, approval decisions, period locks/unlocks, year closes, cash counts.
abstract interface class LedgerEvent {
  /// Envelope id.
  String get id;

  /// Book the event belongs to.
  String get bookId;

  /// Ordering authority; projection order is `(hlc, id)`.
  Hlc get hlc;

  /// The authoring device (05 §4, ADR 2026-09-05b §3). `null` on a legacy
  /// envelope written before per-author sequencing existed.
  String? get authorDevice;

  /// Per-`(book, device)` sequence, monotone from 1, carried **inside** the
  /// ciphertext so the server can neither see nor alter it (ADR 2026-09-05b §3).
  /// Readers track the highest contiguous value per author; a gap means an
  /// envelope is being withheld. `null` = legacy, not tracked.
  int? get authorSeq;
}

/// Approve or reject.
enum Decision {
  /// Clears a review flag, or releases an advance request (02 §3, §7).
  approve,

  /// Rejects: the approver's client also posts the mirror reversal (02 §3), or
  /// the advance request never moves money (02 §7).
  reject,
}

/// A signed decision on one entry (03 §3.3.5). Folded in `(hlc, id)` order,
/// last one winning. Never clears the author's own flag (02 §7.2 item 1).
final class ApprovalDecision implements LedgerEvent {
  /// Creates a decision.
  const ApprovalDecision({
    required this.id,
    required this.bookId,
    required this.entryId,
    required this.decision,
    required this.byUser,
    required this.hlc,
    this.reason,
    this.authorDevice,
    this.authorSeq,
  });

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;
  @override
  final String? authorDevice;
  @override
  final int? authorSeq;

  /// The entry decided on.
  final String entryId;

  /// Approve or reject.
  final Decision decision;

  /// Who decided.
  final String byUser;

  /// Required on reject (02 §3).
  final String? reason;
}

/// A period lock (02 §8): "an entry whose accounting_date falls in period P is
/// valid only if its HLC precedes the HLC of P's lock." Carries the close
/// wizard's declared balances and the client-computed balance vector for every
/// other device to re-verify (02 §8 step 4).
final class PeriodLock implements LedgerEvent {
  /// Creates a lock.
  const PeriodLock({
    required this.id,
    required this.bookId,
    required this.period,
    required this.byUser,
    required this.hlc,
    this.declaredBalances,
    this.vectorCanonical,
    this.projectorVersion,
    this.authorDevice,
    this.authorSeq,
  });

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;
  @override
  final String? authorDevice;
  @override
  final int? authorSeq;

  /// The month locked.
  final YearMonth period;

  /// Who locked (routine admin action, 02 §7.2.1).
  final String byUser;

  /// Balances the closer confirmed (cash count, bank confirmations).
  final Map<String, Paise>? declaredBalances;

  /// The canonical balance vector at close, for independent re-verification.
  final String? vectorCanonical;

  /// The `projectorVersion` that computed [vectorCanonical] (ADR 2026-09-05c §3):
  /// an older reader shows *update to verify* instead of a false mismatch.
  /// `null` on a lock written before versions were recorded.
  final int? projectorVersion;
}

/// Re-opening a locked month (02 §8: admin, logged, requires re-close).
final class PeriodUnlock implements LedgerEvent {
  /// Creates an unlock.
  const PeriodUnlock({
    required this.id,
    required this.bookId,
    required this.period,
    required this.byUser,
    required this.reason,
    required this.hlc,
    this.authorDevice,
    this.authorSeq,
  });

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;
  @override
  final String? authorDevice;
  @override
  final int? authorSeq;

  /// The month re-opened.
  final YearMonth period;

  /// Who re-opened.
  final String byUser;

  /// Why — this joins the admin-actions feed (02 §7.2 item 3).
  final String reason;
}

/// The Year Close ceremony envelope (02 §8.1): the closing balance vector of
/// every **balance-sheet** account as of the FY's last day (ADR 2026-09-05e §2),
/// published by the closer and re-verified by every member.
final class YearClose implements LedgerEvent {
  /// Creates a year close.
  const YearClose({
    required this.id,
    required this.bookId,
    required this.financialYear,
    required this.vector,
    required this.byUser,
    required this.hlc,
    this.projectorVersion,
    this.authorDevice,
    this.authorSeq,
  });

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;
  @override
  final String? authorDevice;
  @override
  final int? authorSeq;

  /// The year closed.
  final FinancialYear financialYear;

  /// Closing balances — the certified opening (b/f) of the next FY.
  final BalanceVector vector;

  /// Who closed.
  final String byUser;

  /// The `projectorVersion` that computed [vector] (ADR 2026-09-05c §3).
  final int? projectorVersion;
}
