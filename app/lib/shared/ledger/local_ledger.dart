// The app's one door to the ledger: `LocalLedger` composes the real packages
// (core_ledger 02 · core_crypto 04 · data 03) over the `KeyStore` seam so a
// screen never touches an envelope, a key or a projector directly.
//
// Write path (the harness's SimulatedDevice with real envelopes): the event is
// checked against 02 §1.4/§2 shapes, given this device's next `author_seq`
// from the mirror (ADR 2026-09-05b §3) and an HLC ticked from the injected
// clock, sealed with `EnvelopeBuilder.seal` under the book's current key,
// appended to `envelopes_local`, queued in `outbox`, and the book's
// projections are rebuilt by `Recompute` — the only place rows are written.
//
// Read path: Drift streams over Layer 2 (03 §3.2) shaped for 07 §4 / §6 / §7.
// Every amount is signed integer paise with the engine's convention (+ = Dr,
// − = Cr); the vocabulary a screen speaks is decided in `shared/format`
// (02 §10 🔒) — nothing here bends to it.
//
// Rules kept: no `DateTime.now()` (clock injected), no `Random()` (ids from the
// suite's libsodium CSPRNG), append-only (never UPDATE/DELETE an envelope),
// unknown fields round-trip (amend/reverse copy the projected `Entry`, which
// carries `extra`), keys only through `KeyStore`, book keys wrapped to a
// *verified* UMK only (04 §8.2 — the type system insists).
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:core_ledger/core_ledger.dart'
    as engine
    show openAdvances, yearClosePreconditions;
import 'package:data/data.dart';
import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart'
    show AcceptedBookKey, AcceptedKeySink, BookKeyStore, VerifiedUmkSource;

import '../seams/key_store.dart';
import '../seams/review_policy.dart';
import 'device_certification.dart';
import 'ledger_identity.dart';
import 'verified_members.dart';

export '../seams/review_policy.dart' show ReviewPolicy, noReviewPolicy;
export 'device_certification.dart'
    show DeviceCertOffer, DeviceCertifier, umkKeyVersionFirst;
export 'ledger_identity.dart'
    show LedgerIdentity, LocalLedgerKeys, readStoredIdentity;
export 'verified_members.dart'
    show
        VerificationPayload,
        VerifiedMember,
        VerifiedMemberDirectory,
        VerifiedMemberSink;

/// One seeded income or expense category (ADR 2026-09-09c §1's third column).
///
/// These are **account names** — user data the user may rename — not UI
/// labels, so they never become ARB keys; the UI loads the tree for the book
/// type and locale and passes it to [LocalLedger.createBook]
/// (docs/reference/seed-category-trees.md).
final class SeedCategory {
  /// Creates a seeded category.
  const SeedCategory(this.name, this.accountClass)
    : assert(
        accountClass == AccountClass.categoryIncome ||
            accountClass == AccountClass.categoryExpense,
        'a seeded category is an income or expense account (02 §1.2)',
      );

  /// The seeded, editable account name.
  final String name;

  /// [AccountClass.categoryIncome] or [AccountClass.categoryExpense].
  final AccountClass accountClass;

  @override
  bool operator ==(Object other) =>
      other is SeedCategory &&
      other.name == name &&
      other.accountClass == accountClass;

  @override
  int get hashCode => Object.hash(name, accountClass);

  @override
  String toString() => 'SeedCategory($name, ${accountClass.name})';
}

/// A posting the engine refused *before* it was sealed (02 §1.4, §2, §5).
/// Nothing was appended; the caller shows the reasons (07 §1 rule 6: explain
/// and offer the path — e.g. `periodLocked` → *Fix an old entry*).
final class PostRejected implements Exception {
  /// Creates the rejection.
  const PostRejected(this.entryId, this.violations);

  /// The draft's id.
  final String entryId;

  /// Why — never empty.
  final List<Violation> violations;

  /// True when any violation is of [kind].
  bool has(ViolationKind kind) => violations.any((v) => v.kind == kind);

  @override
  String toString() => 'PostRejected($entryId: ${violations.join('; ')})';
}

/// A count the engine refused (`validateCount`, 02 §8.2 🔒). Nothing was
/// authored: no count envelope, no entry.
///
/// Typed like [PostRejected] and for the same reason — the caller shows the
/// sentence the rule asks for (07 §1 rule 6), rather than reading a string.
final class CountRejected implements Exception {
  /// Creates the refusal.
  const CountRejected(this.accountId, this.violations);

  /// The account being counted.
  final String accountId;

  /// What the engine objected to — a missing denomination sheet in a trust
  /// book, a collection count without two names, a sheet that does not add up.
  final List<Violation> violations;

  /// True when [kind] is among them.
  bool has(ViolationKind kind) => violations.any((v) => v.kind == kind);

  @override
  String toString() => 'CountRejected($accountId: ${violations.join('; ')})';
}

/// One recorded cash count and what it meant for the books (02 §8.2 🔒).
final class RecordedCashCount {
  /// Creates the record.
  const RecordedCashCount({
    required this.count,
    required this.outcome,
    this.entry,
  });

  /// The count as authored — a memo envelope that moves no money.
  final CashCount count;

  /// The engine's decision, carried back unchanged: `CountVerified`,
  /// `CountAdjustment` or `CountRecognition`.
  final CountOutcome outcome;

  /// The adjustment or recognition entry, when one was posted. Null for a
  /// verification: an equal count posts nothing.
  final Entry? entry;
}

/// What the S5.5 count sheet and the S4 statement header read about one
/// countable account (02 §8.2).
final class CashCountReading {
  /// Creates the reading.
  const CashCountReading({
    required this.bookId,
    required this.bookType,
    required this.account,
    required this.bookBalance,
    required this.incomeAccounts,
    this.lastCount,
  });

  /// The book the account belongs to.
  final String bookId;

  /// Its type — `organization` makes the denomination sheet mandatory for
  /// every cash account (02 §8.2 🔒). Read by `countPolicy`, not by a widget.
  final BookType bookType;

  /// The account, whose subtype chooses the mode: `cash` → verify,
  /// `cash_collection` → collect.
  final Account account;

  /// What the entries say is there (engine sign). In collect mode this is
  /// *what is still in the box*, never something to check a count against.
  final Paise bookBalance;

  /// The book's income categories — collect mode's *Record it as* picker.
  final List<Account> incomeAccounts;

  /// The previous count, if any.
  final CashCount? lastCount;
}

/// The facade was used before [LocalLedger.bootstrapSolo] (or `open`).
final class LedgerNotOpen implements Exception {
  /// Creates the error.
  const LedgerNotOpen();

  @override
  String toString() => 'LedgerNotOpen: call bootstrapSolo() first';
}

/// One line of the Home position card (07 §4; 02 §9). Every figure is signed
/// integer paise in the engine's convention.
final class Position {
  /// Creates the position.
  const Position({
    required this.bookId,
    required this.totalMoneyPaise,
    required this.cashPaise,
    required this.banks,
    required this.youWillGetPaise,
    required this.youWillGivePaise,
    required this.advancesOutPaise,
    required this.inTransitPaise,
  });

  /// Book.
  final String bookId;

  /// *Total money you have*: Σ every `money` account (overdrafts subtract).
  final int totalMoneyPaise;

  /// Σ `money` accounts of subtype `cash`.
  final int cashPaise;

  /// Each non-cash `money` account (banks, cards, loans, wallets) and its
  /// balance, in creation order.
  final List<AccountBalance> banks;

  /// Σ Dr party balances (they owe you) — positive or zero.
  final int youWillGetPaise;

  /// Σ |Cr party balances| (you owe them) — positive or zero.
  final int youWillGivePaise;

  /// Σ `advance` balances (advances given out, awaiting spend or return).
  final int advancesOutPaise;

  /// Σ *Due to/from* balances — money between your books (02 §6), signed.
  final int inTransitPaise;
}

/// An account with its live balance — one row of the A–Z Ledger index (07 §6).
final class AccountBalance {
  /// Creates the row.
  const AccountBalance({
    required this.account,
    required this.balancePaise,
    required this.archived,
    this.usualCategoryId,
  });

  /// The engine account (class, subtype, role).
  final Account account;

  /// Signed paise (+ = Dr).
  final int balancePaise;

  /// Hidden from pickers (02 §1.2).
  final bool archived;

  /// Quick-entry default for a party (02 §1.2).
  final String? usualCategoryId;
}

// ── the review queue (02 §3 🔒 post-then-review) ─────────────────────────────
// The money is already in the book. A flag is a threshold, not a gate: approval
// clears it and moves nothing; rejection posts the mirror reversal of 02 §5
// with the reason, and both entries stay in history. `review_state` itself is
// never stored on an envelope — it folds from `approval_decision` envelopes in
// `(hlc, envelope_id)` order, last one winning (03 §3.3 rule 5 🔒), which is
// why nothing here writes it and everything here reads it back.

/// One line of a flagged entry, with the account's own name resolved — what
/// S6.1's expandable list and S6.2's stepper show beside the amount.
final class FlaggedLine {
  /// Creates the line.
  const FlaggedLine({
    required this.accountId,
    required this.accountName,
    required this.amount,
  });

  /// The account moved.
  final String accountId;

  /// Its display name, or the id when the chart has no row for it.
  final String accountName;

  /// Signed paise: + debit, − credit (02 §1.3).
  final Paise amount;
}

/// One entry still carrying an **open** review flag (02 §3, 03 §3.3 rule 5).
///
/// It is posted and counted — every balance already includes it — so nothing
/// above this may draw it as pending, held or waiting.
final class FlaggedEntry {
  /// Creates the row.
  const FlaggedEntry({
    required this.entryId,
    required this.bookId,
    required this.kind,
    required this.accountingDate,
    required this.lines,
    required this.hlc,
    this.note,
    this.createdByUser,
    this.approver,
  });

  /// The entry's envelope id.
  final String entryId;

  /// The book it landed in.
  final String bookId;

  /// The verb (02 §2).
  final EntryKind kind;

  /// The user-visible date (03 §1: a calendar day, not an instant).
  final LocalDate accountingDate;

  /// Its lines, in authored order.
  final List<FlaggedLine> lines;

  /// The author's HLC — when they saved it, as 03 §1 records it.
  final int hlc;

  /// The author's own narration, when they wrote one.
  final String? note;

  /// Who authored it. Never the reader on a well-formed queue: nobody decides
  /// on their own entry (02 §7.2 item 1 🔒).
  final String? createdByUser;

  /// Who must act, as the authoring client wrote it (02 §1.3 `review_approver`).
  final String? approver;

  /// The credit side — where the money came from.
  List<FlaggedLine> get from => [
    for (final l in lines)
      if (l.amount.raw < 0) l,
  ];

  /// The debit side — where it went.
  List<FlaggedLine> get to => [
    for (final l in lines)
      if (l.amount.raw > 0) l,
  ];

  /// Total of the debit side, in paise — the entry's magnitude.
  int get amountPaise => to.fold(0, (sum, l) => sum + l.amount.raw);
}

/// Why a review decision was refused, authoring nothing.
enum ReviewRefusal {
  /// No such entry on this device.
  unknownEntry,

  /// `status = pending`: an advance request (02 §7), whose approval *moves
  /// money* and whose path is [LocalLedger.approveAdvance] — never this one.
  pendingAdvance,

  /// The entry never carried a flag (`review_state = 'none'`).
  notFlagged,

  /// A decision has already folded onto it (`approved` or `rejected`).
  alreadyDecided,

  /// It was amended away, or is not the head of its chain — decide on the head.
  notHead,

  /// The reader authored it. Nobody clears their own flag (02 §7.2 item 1 🔒,
  /// enforced again by the projector as `ViolationKind.selfApproval`).
  selfApproval,

  /// Rejection only: the entry already has its mirror reversal (02 §5).
  alreadyReversed,

  /// Rejection only: the auto-reversal of 02 §5 could not be posted, so the
  /// decision was not authored either — a rejection without its reversal
  /// would be a flag cleared over money that never came back.
  reversalRefused,
}

/// A review decision this device would not author (02 §3). Carries no
/// plaintext financial data (CLAUDE.md rule 4).
final class ReviewRefused implements Exception {
  /// Creates the refusal.
  const ReviewRefused(
    this.entryId,
    this.refusal, [
    this.violations = const <Violation>[],
  ]);

  /// The entry that was not decided on.
  final String entryId;

  /// Why.
  final ReviewRefusal refusal;

  /// The engine's own reasons, for [ReviewRefusal.reversalRefused] only.
  final List<Violation> violations;

  @override
  String toString() => 'ReviewRefused($entryId: ${refusal.name})';
}

/// One decided flag, **read back out of the rebuilt projection** — so the
/// caller shows a state the projector agrees with rather than assuming the
/// write landed.
final class ReviewDecided {
  /// Creates the result.
  const ReviewDecided({
    required this.decision,
    required this.reviewState,
    this.decidedHlc,
    this.reason,
    this.reversal,
  });

  /// The `approval_decision` envelope this device authored — exactly one.
  final ApprovalDecision decision;

  /// The head's `review_state` as re-projected: `approved` or `rejected`
  /// unless a later decision from another device already folded over it.
  final String reviewState;

  /// The HLC of the decision that won the fold (03 §3.3 rule 5).
  final int? decidedHlc;

  /// The winning decision's reason — required on `rejected` (03 §3.2).
  final String? reason;

  /// The auto-reversal 02 §3 posts on a rejection; null on an approval.
  final Entry? reversal;
}

/// One row of an A/C statement (07 §6, design-system §5): the account's own
/// line of an entry, the other side(s), and the running balance after it.
/// Both vocabularies read from the same figures: consumer surfaces take
/// [amountPaise] (signed); professional surfaces take [debitPaise] /
/// [creditPaise] (absolute, one of them zero) — 02 §10, A-02-10.
/// One account's statement over a period (07 §6, ADR 2026-09-09 §4): the
/// balance the period opens on (**b/f**), the rows inside it, and the balance
/// it closes at (**c/f**).
///
/// Until Year Close lands (M9) the b/f is **computed** — the sum of this
/// account's lines dated before the period — which is correct for a
/// continuous ledger (02 §8.1, ADR 2026-09-09 §4). When S10.4 exists the
/// certified opening vector replaces the computed figure.
///
/// It *is* the list of rows, so a caller that wants only the rows keeps
/// reading it as one.
final class Statement extends ListBase<StatementRow> {
  /// Creates the statement.
  Statement({
    required this.accountId,
    required List<StatementRow> rows,
    required this.openingPaise,
    this.from,
    this.to,
  }) : _rows = List.unmodifiable(rows);

  final List<StatementRow> _rows;

  /// The account this is the statement of.
  final String accountId;

  /// First day of the period, or null for the whole history.
  final LocalDate? from;

  /// Last day of the period, or null for *up to the latest entry*.
  final LocalDate? to;

  /// **b/f** — the balance carried into [from], signed paise (+ = Dr).
  final int openingPaise;

  /// **c/f** — the balance the period closes at, signed paise.
  int get closingPaise =>
      _rows.isEmpty ? openingPaise : _rows.last.runningBalancePaise;

  @override
  int get length => _rows.length;

  @override
  set length(int value) =>
      throw UnsupportedError('A statement is a read-only view');

  @override
  StatementRow operator [](int index) => _rows[index];

  @override
  void operator []=(int index, StatementRow value) =>
      throw UnsupportedError('A statement is a read-only view');
}

/// A held envelope as the mirror recorded it (ADR 2026-09-05b §4): verified,
/// not projected, not counted — and, when the mirror knows it, the target it
/// is waiting for. Held is never an error.
final class HeldObject {
  /// Creates the record.
  const HeldObject({required this.objectId, this.waitingForId});

  /// The object id the envelope carries (an entry id, for S4.1).
  final String objectId;

  /// `envelopes_local.held_for` — the target that has not arrived, if known.
  final String? waitingForId;
}

/// A month locked (02 §8 step 4 🔒): the signed envelope, and this device's
/// own verdict on the vector it just published.
final class LockedMonth {
  /// Creates the result.
  const LockedMonth({required this.lock, this.verification});

  /// The `period_lock` envelope as authored — declared balances, the
  /// projector's canonical vector, and the `projector_version` that computed
  /// it.
  final PeriodLock lock;

  /// This reader's replay of that vector, read back out of the rebuilt
  /// projection. [CloseVerification.readerOutdated] is a state, not an error
  /// (ADR 2026-09-05c §3); null when the projection published no verdict.
  final CloseVerification? verification;
}

/// The lock was refused: `monthLockPreconditions` was not empty (02 §8 step 3
/// 🔒). Nothing was appended.
///
/// It carries the **engine's own** [CloseBlockerItem]s rather than a sentence,
/// so no layer above can quietly demote a blocker to a warning or invent one.
final class MonthLockRefused implements Exception {
  /// Creates the refusal.
  const MonthLockRefused(this.bookId, this.period, this.blockers);

  /// The book whose month stayed open.
  final String bookId;

  /// The month.
  final YearMonth period;

  /// What the engine objected to, in its own terms.
  final List<CloseBlockerItem> blockers;

  @override
  String toString() =>
      'MonthLockRefused($bookId $period: '
      '${blockers.map((b) => b.kind.name).join(', ')})';
}

/// A financial year certified (02 §8.1 🔒): the signed `year_close` envelope,
/// and this device's own verdict on the closing vector it just published.
///
/// The twin of [LockedMonth], and deliberately the same shape — a close is a
/// lock's big brother, not a different kind of thing.
final class ClosedYearResult {
  /// Creates the result.
  const ClosedYearResult({required this.close, this.verification});

  /// The `year_close` envelope as authored — the closing balance vector the
  /// **projector** computed, and the `projectorVersion` that computed it
  /// (02 §8.1 🔒, ADR 2026-09-05c §3).
  final YearClose close;

  /// This reader's replay of that vector, read back out of the rebuilt
  /// projection. [CloseVerification.readerOutdated] is a state, not an error
  /// (ADR 2026-09-05c §3); null when the projection published no verdict.
  final CloseVerification? verification;
}

/// The Year Close ceremony was refused: [LocalLedger.yearClosePreconditions]
/// was not empty (02 §8.1 🔒). Nothing was appended.
///
/// It carries the **engine's own** [CloseBlockerItem]s rather than a sentence,
/// so no layer above can quietly demote a blocker to a warning or invent one.
///
/// Named for the *certify* step rather than `YearCloseRefused` on purpose:
/// `features/close`'s seam already owns that name for the screen-facing
/// refusal, and an adapter has to hold both at once.
final class YearCertifyRefused implements Exception {
  /// Creates the refusal.
  const YearCertifyRefused(this.bookId, this.financialYear, this.blockers);

  /// The book whose year stayed open.
  final String bookId;

  /// The year.
  final FinancialYear financialYear;

  /// What the engine objected to, in its own terms.
  final List<CloseBlockerItem> blockers;

  @override
  String toString() =>
      'YearCertifyRefused($bookId ${financialYear.label}: '
      '${blockers.map((b) => b.kind.name).join(', ')})';
}

/// The year is already sealed, so [LocalLedger.closeYear] appended nothing.
///
/// 02 §8.1 🔒 gives a certified year exactly one way back — re-opening a month
/// inside it, which voids the certificate — so certifying twice is never a
/// silent second envelope. This is the backstop under the screen, which shows
/// the certificate rather than the action once a year is closed.
final class YearAlreadyClosed implements Exception {
  /// Creates the refusal.
  const YearAlreadyClosed(this.bookId, this.financialYear, this.status);

  /// The book.
  final String bookId;

  /// The year that is already sealed.
  final FinancialYear financialYear;

  /// [YearStatus.closed] — or [YearStatus.uncertified], which is a *voided*
  /// certificate and is re-certified by closing the months again in order, not
  /// by a second close of the same state.
  final YearStatus status;

  @override
  String toString() =>
      'YearAlreadyClosed($bookId ${financialYear.label}: ${status.name})';
}

/// One financial year this book has closed, as the FY switcher and S10.4 need
/// it (ADR 2026-09-09 §4 🔒).
///
/// It carries the **whole certified vector** rather than one figure from it,
/// because its two readers want different lines out of it: S10.4 shows the
/// book's carried-forward total, and S4's switcher shows the b/f of the one
/// A/C on screen. Taking either here would make the other recompute a figure
/// the projector already published (02 §9: balances are derived once).
final class CertifiedYearRow {
  /// Creates the row.
  const CertifiedYearRow({
    required this.year,
    required this.status,
    this.vector,
    this.verification,
  });

  /// The year.
  final FinancialYear year;

  /// [YearStatus.closed], or [YearStatus.uncertified] once a month inside it
  /// (or an earlier year) was re-opened (02 §8.1 🔒).
  final YearStatus status;

  /// The certified closing vector — the b/f the next year opens on. Null for a
  /// row whose vector this device has not got (a `year_close_p` row written by
  /// a build that recorded none).
  final BalanceVector? vector;

  /// This device's verification of that vector (ADR 2026-09-05c §3 🔒).
  final CloseVerification? verification;

  /// The book's balance-sheet total carried forward — debits and credits are
  /// equal in a balanced vector, so one figure states it.
  Paise get carriedForward => vector?.totalDebits ?? Paise.zero;

  /// The b/f of one A/C, signed engine paise (+ = Dr) — what S4's switcher
  /// puts against the year it offers.
  Paise carriedForwardFor(String accountId) =>
      vector == null ? Paise.zero : vector![accountId];
}

/// Where a closer had got to, as this **phone** saved it (07 §13 *Resumable*
/// 🔒).
///
/// Deliberately not the wizard's own `CloseProgress`: the step is carried as
/// the plain name the UI gave it, so `shared/ledger` stores the wizard's
/// place without knowing the wizard's shape — and an unknown name read back
/// from an older or newer build is the caller's to resolve, not a crash here.
final class SavedCloseProgress {
  /// Creates the record.
  const SavedCloseProgress({
    required this.step,
    this.confirmedAccountIds = const {},
  });

  /// The wizard step reached, by name.
  final String step;

  /// The money A/Cs already confirmed at step 2.
  final Set<String> confirmedAccountIds;

  @override
  bool operator ==(Object other) =>
      other is SavedCloseProgress &&
      other.step == step &&
      other.confirmedAccountIds.length == confirmedAccountIds.length &&
      other.confirmedAccountIds.containsAll(confirmedAccountIds);

  @override
  int get hashCode =>
      Object.hash(step, Object.hashAllUnordered(confirmedAccountIds));

  @override
  String toString() => 'SavedCloseProgress($step, $confirmedAccountIds)';
}

// ── late arrivals (02 §8 🔒, ADR 2026-09-05e §3, §10) ────────────────────────

/// One line of a late arrival, with the A/C's name already resolved so the
/// tray can name both sides without a second read.
final class LateArrivalLine {
  /// Creates the line.
  const LateArrivalLine({
    required this.accountId,
    required this.accountName,
    required this.amount,
  });

  /// The A/C.
  final String accountId;

  /// Its name, as the user wrote it.
  final String accountName;

  /// Engine sign, integer paise (CLAUDE.md rule 1): + is Dr, − is Cr. The
  /// words beside it on a consumer surface are *Money in / Money out*
  /// (02 §10 🔒) — that translation is the screen's, never this file's.
  final Paise amount;
}

/// One entry sitting in the closer's **Late Arrivals tray** (02 §8 🔒).
///
/// It is *valid*, it **counts in every live balance already** (02 §3 🔒), and
/// it leaves the certified month untouched. Nothing here may be drawn as
/// money that has not moved — the tray is a closer's decision, not a gate.
///
/// [lockedPeriod] and [lockedAtHlc] are the *why it is here* 07 §13 🔒 asks
/// each item to state: the month this entry is dated into, and the lock that
/// was already in force when it landed.
final class LateArrival {
  /// Creates the tray item.
  const LateArrival({
    required this.entryId,
    required this.bookId,
    required this.kind,
    required this.accountingDate,
    required this.lockedPeriod,
    required this.lines,
    this.lockedAtHlc,
    this.note,
    this.createdByUser,
    this.hlc = 0,
  });

  /// The entry — the head of its amend chain.
  final String entryId;

  /// The book it belongs to.
  final String bookId;

  /// The verb (02 §2).
  final EntryKind kind;

  /// The date it carries — inside [lockedPeriod], which is what puts it here.
  final LocalDate accountingDate;

  /// The locked month it is dated into.
  final YearMonth lockedPeriod;

  /// Its lines, in entry order, each with the A/C's name.
  final List<LateArrivalLine> lines;

  /// The HLC of the lock in force over [lockedPeriod] — *when it locked*.
  /// Null when the projection has no lock row for the month (a re-opened
  /// month still holding a tray item, ADR 2026-09-05e §5).
  final int? lockedAtHlc;

  /// The author's own narration, when they wrote one.
  final String? note;

  /// Who saved it.
  final String? createdByUser;

  /// The entry's own HLC — earlier than [lockedAtHlc] by 02 §8's rule, which
  /// is exactly what makes it a *valid* late arrival rather than a violation.
  final int hlc;

  /// What moved, as a positive figure: the sum of the debit side. An entry
  /// balances (02 §1.4), so this is the magnitude of the movement whichever
  /// side you read it from.
  Paise get amount => lines
      .where((l) => l.amount.raw > 0)
      .fold(Paise.zero, (sum, l) => sum + l.amount);

  /// The A/Cs money left, in line order — the *from* side.
  List<LateArrivalLine> get from => [
    for (final l in lines)
      if (l.amount.raw < 0) l,
  ];

  /// The A/Cs money reached — the *to* side.
  List<LateArrivalLine> get to => [
    for (final l in lines)
      if (l.amount.raw > 0) l,
  ];
}

/// Why [LocalLedger.unlockMonth] authored nothing.
enum MonthUnlockRefusal {
  /// The month is not locked, so there is nothing to re-open.
  notLocked,

  /// The month sits inside a **closed** financial year. Unlocking it would
  /// void that year's certificate and every later one (02 §8.1 🔒), which is
  /// the **structural** `year_reopen` of 02 §7.2.1 🔒 — a quorum act, not this
  /// routine one. The caller sends the closer to the year-close ceremony.
  closedYear,
}

/// The typed refusal of a re-open, thrown **before** anything is authored.
final class MonthUnlockRefused implements Exception {
  /// Creates the refusal.
  const MonthUnlockRefused(this.bookId, this.period, this.reason);

  /// The book whose month stayed locked.
  final String bookId;

  /// The month.
  final YearMonth period;

  /// Why.
  final MonthUnlockRefusal reason;

  @override
  String toString() => 'MonthUnlockRefused($bookId $period: ${reason.name})';
}

final class StatementRow {
  /// Creates the row.
  const StatementRow({
    required this.entryId,
    required this.accountId,
    required this.date,
    required this.kind,
    required this.status,
    required this.reviewState,
    required this.amountPaise,
    required this.runningBalancePaise,
    required this.counterAccountIds,
    required this.hlc,
    this.note,
    this.channel,
  });

  /// Entry.
  final String entryId;

  /// The account whose statement this is.
  final String accountId;

  /// `accounting_date`.
  final LocalDate date;

  /// Verb.
  final EntryKind kind;

  /// Effective status as projected (`posted`, `void`, `in_tray` …).
  final String status;

  /// `none | open | approved | rejected` (03 §3.3.5).
  final String reviewState;

  /// This account's signed line (+ = Dr, − = Cr).
  final int amountPaise;

  /// Balance after this row, ordered by `(accounting_date, hlc, entry_id)`
  /// (02 §9).
  final int runningBalancePaise;

  /// The other account(s) of the entry — the *particulars* column.
  final List<String> counterAccountIds;

  /// Entry HLC.
  final int hlc;

  /// Note.
  final String? note;

  /// `upi | card | netbanking | cash` (02 §1.3).
  final String? channel;

  /// Debit column figure (absolute), zero when the line is a credit.
  int get debitPaise => amountPaise > 0 ? amountPaise : 0;

  /// Credit column figure (absolute), zero when the line is a debit.
  int get creditPaise => amountPaise < 0 ? -amountPaise : 0;

  /// Ledger side of this line.
  Side? get side => Paise(amountPaise).side;
}

/// An entry as the Ledger tab shows it (audit trail one tap away, 07 §1
/// rule 8): the projected row plus its lines.
final class EntryView {
  /// Creates the view.
  const EntryView({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.status,
    required this.date,
    required this.lines,
    required this.reviewState,
    required this.createdByUser,
    required this.hlc,
    this.note,
    this.channel,
    this.partyId,
    this.amends,
    this.reverses,
    this.supersededBy,
  });

  /// Entry id.
  final String id;

  /// Book.
  final String bookId;

  /// Verb.
  final EntryKind kind;

  /// Effective status wire (`posted`, `void`, `superseded`, …).
  final String status;

  /// `accounting_date`.
  final LocalDate date;

  /// Lines in order.
  final List<Line> lines;

  /// Review flag state.
  final String reviewState;

  /// Author.
  final String createdByUser;

  /// HLC.
  final int hlc;

  /// Note.
  final String? note;

  /// Channel tag.
  final String? channel;

  /// Party, when the verb touched one.
  final String? partyId;

  /// `refs.amends`.
  final String? amends;

  /// `refs.reverses`.
  final String? reverses;

  /// The amendment that replaced this entry, if any (02 §5).
  final String? supersededBy;

  /// Head of its amend chain — the version views show.
  bool get isHead => supersededBy == null;
}

/// What S1.4 / the sync chip need about a book's projection (07 §1 rule 7,
/// ADR 2026-09-05b §3–4, 05c §6).
/// Why [LocalLedger.approveAdvance] refused (02 §7, §7.2 item 1 🔒). Nothing
/// is authored on any of these — a refused decision writes no envelope.
enum AdvanceRefusal {
  /// No such entry on this phone.
  unknownEntry,

  /// The entry is not an advance request awaiting approval (02 §1.3: `pending`
  /// is only that).
  notAPendingRequest,

  /// Already approved or rejected — the approval moves the money exactly once.
  alreadyDecided,

  /// The approver is the requester. 02 §7.2 item 1 🔒: nobody decides on their
  /// own entry, and the projector quarantines a self-approval, so authoring
  /// one would write an envelope no reader on any device would ever count.
  selfApproval,
}

/// [LocalLedger.approveAdvance] declined to author a decision.
final class AdvanceRefused implements Exception {
  /// Creates the refusal.
  const AdvanceRefused(this.entryId, this.refusal);

  /// The request that was not decided.
  final String entryId;

  /// Why.
  final AdvanceRefusal refusal;

  @override
  String toString() => 'AdvanceRefused($entryId: ${refusal.name})';
}

/// One **open** advance for S5 (07 §8) — an `advance` account with a debit
/// balance, its ageing, and the spent/returned split behind the bar.
///
/// Derived purely from `advance` account balances and the counted entries that
/// moved them (02 §7 last bullet 🔒): both dashboards — *money you are
/// holding* and *money out with people* — read this, and there is no separate
/// advance state anywhere to drift from the ledger.
final class AdvanceView {
  /// Creates the view.
  const AdvanceView({
    required this.bookId,
    required this.accountId,
    required this.accountName,
    required this.memberId,
    required this.givenPaise,
    required this.spentPaise,
    required this.returnedPaise,
    required this.remainingPaise,
    required this.takenDate,
    required this.ageDays,
    required this.purpose,
  });

  /// The book the advance came out of.
  final String bookId;

  /// The `Advance – {member}` account.
  final String accountId;

  /// Its name, as the chart holds it.
  final String accountName;

  /// The holder, when the account names one.
  final String? memberId;

  /// Σ debits to the account — everything handed out, ever.
  final int givenPaise;

  /// Σ credits that went to an expense category (`Dr expense · Cr Advance`).
  final int spentPaise;

  /// Σ credits that went back to money (`Dr money · Cr Advance`).
  final int returnedPaise;

  /// The debit balance still out with the holder — [givenPaise] less
  /// [spentPaise] and [returnedPaise]. Open while this is > 0 (02 §7).
  final int remainingPaise;

  /// The date of the oldest unsettled debit — *taken on* (02 §7 ageing).
  final LocalDate takenDate;

  /// Days from [takenDate] to the as-of date.
  final int ageDays;

  /// The purpose text of the request still open, when one was given
  /// (02 §7 requires it on every request).
  final String? purpose;
}

final class BookHealth {
  /// Creates the report.
  const BookHealth({
    required this.bookId,
    required this.integrityOk,
    required this.needsRebootstrap,
    required this.heldCount,
    required this.authorGapCount,
    required this.quarantinedCount,
  });

  /// Book.
  final String bookId;

  /// `books_p.integrity_ok`.
  final bool integrityOk;

  /// Blob hash failed — re-bootstrap (ADR 05c §6).
  final bool needsRebootstrap;

  /// Envelopes waiting for a target that has not arrived (`held`).
  final int heldCount;

  /// Open `author_seq` holes — *Waiting for entries from {name}'s phone*.
  final int authorGapCount;

  /// Envelopes an honest reader refused.
  final int quarantinedCount;

  /// The projection is provisional (02 §5, 07 §1 rule 7).
  bool get isProvisional => heldCount > 0 || authorGapCount > 0;
}

/// Everything a reader of this install's envelopes needs, as one value: the
/// consumer is `sync_engine`'s `EnvelopeGuard` (05 §1, §4, §5), which opens
/// pulled envelopes, re-seals outbox rows after a key rotation and unwraps
/// `wrapped_keys` rows.
///
/// This is a **borrowed** view, never a copy. [device], [umk] and [bookKeys]
/// are the live objects [LocalLedger] owns and zeroises in
/// [LocalLedger.dispose]; the holder must not dispose them, and after the
/// ledger is disposed a retained reference is empty rather than dangerous.
///
/// What it permits: opening, verifying and re-sealing this tenant's
/// envelopes; unwrapping `wrapped_keys` rows addressed to this user (05 §5);
/// and believing this user's own signature chain (04 §3.4).
///
/// What it does not permit: believing anybody a **ceremony** has not bound.
/// [verifiedUmkOf] answers for this install's own user, whose fingerprint the
/// ledger checked byte-for-byte at bootstrap, and for the members a
/// `verification_event` signed record proves (04 §6.4; ADR 2026-09-05d §7) —
/// and for nobody else. It answers with [VerifiedUmkPublic], never with bytes
/// and a flag, so no book key and no guardian share can be sealed to an
/// unverified fingerprint through this seam (04 §8.2 🔒, rule 5). It carries
/// no ledger write path either: posting, book creation and key minting stay
/// behind [LocalLedger]'s own methods, and a key gets *in* only through
/// [LocalLedger.verifiedMembers].
final class LedgerKeyMaterial implements VerifiedUmkSource {
  const LedgerKeyMaterial._({
    required this.userId,
    required this.device,
    required this.umk,
    required this.bookKeys,
    required VerifiedUmkPublic ownUmk,
    required VerifiedUmkSource others,
  }) : _ownUmk = ownUmk, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _others = others;

  /// The user every key here belongs to (`created_by_user`, 04 §4).
  final String userId;

  /// This device's Ed25519 + X25519 pair: signs envelopes and records, and
  /// opens the wrapped UMK.
  final DeviceKeyPair device;

  /// This user's UMK — what opens a `wrapped_keys` row (05 §5).
  final UmkKeyPair umk;

  /// The **live** book-key store, shared with the ledger's own projector: a
  /// key the guard unwraps during a pull is visible to [LocalLedger.recompute]
  /// in the same round, which is what lets `key_wait` drain once (05 §4)
  /// instead of decrypting for the guard and quarantining for the projector.
  final BookKeyStore bookKeys;

  final VerifiedUmkPublic _ownUmk;

  /// The other members, from the ledger's [VerifiedMemberDirectory] — read
  /// live, so a ceremony that completes mid-session is believed at once.
  final VerifiedUmkSource _others;

  /// The ceremony-verified UMK of [userId]: this install's own user, whose
  /// fingerprint it checked byte-for-byte at bootstrap (04 §3.4), or a member
  /// a ceremony on this device bound to a human and a signed record proves
  /// (04 §6.4, §8.2 🔒). Null for everybody else — a member is never believed
  /// because this device happens to know their id, or because the server said
  /// so (C-05d-7).
  ///
  /// The install's own key wins over any record naming it: this device's own
  /// UMK is the one it holds, not one it was told about.
  @override
  VerifiedUmkPublic? verifiedUmkOf(String userId) =>
      userId == this.userId ? _ownUmk : _others.verifiedUmkOf(userId);
}

/// The ledger's [KeySource] over the one [BookKeyStore] the sync engine's
/// guard also holds (05 §5). Two stores would mean a key that arrives on a
/// pull opens envelopes for the guard and not for the projector; the book →
/// tenant map stays here because a book's tenant is its own row's
/// (`books_p.tenant_id`), not the store's single tenant — the store answers
/// only for books this install learned about through sync.
final class _SharedKeySource implements KeySource {
  BookKeyStore? store;

  final Map<String, String> tenants = {};

  /// The store, or [LedgerNotOpen] before bootstrap.
  BookKeyStore get required => store ?? (throw const LedgerNotOpen());

  @override
  BookKey? bookKey(BookKeyRef ref) => store?.bookKey(ref);

  @override
  String? tenantIdOf(String bookId) =>
      tenants[bookId] ?? store?.tenantIdOf(bookId);
}

// ── inter-book movement (02 §6 🔒) ─────────────────────────────────────────

/// Why an inter-book action was refused (02 §6 🔒). Typed like
/// [AdvanceRefusal] and for the same reason: a refusal authors **nothing**,
/// so the caller is told which sentence to show (07 §1 rule 6) rather than
/// left to read an error string.
enum InterBookRefusal {
  /// Both sides named the same book — an inter-book movement needs two.
  sameBook,

  /// A book this install holds no key for. Half a pair cannot be authored
  /// into a book the device cannot open (04 §5.2).
  bookNotHeld,

  /// The account named on a money side is not a money account.
  notAMoneyAccount,

  /// The payee side of a pocket expense is not an expense category (02 §6).
  notAnExpenseCategory,

  /// Zero or negative paise. Money is integer paise and a movement moves some.
  amountNotPositive,
}

/// An inter-book action [LocalLedger] declined. Nothing was appended.
final class InterBookRefused implements Exception {
  /// Creates the refusal.
  const InterBookRefused(this.refusal, this.detail);

  /// Which rule refused it.
  final InterBookRefusal refusal;

  /// What was wrong, for the log — never a figure (CLAUDE.md rule 4).
  final String detail;

  @override
  String toString() => 'InterBookRefused(${refusal.name}: $detail)';
}

/// The two posted halves of one inter-book action (02 §6): one envelope per
/// book, sharing [transferGroup].
final class InterBookMovement {
  /// Creates the movement.
  const InterBookMovement({
    required this.from,
    required this.to,
    required this.transferGroup,
  });

  /// The half in the paying / spending-on-behalf book.
  final Entry from;

  /// The half in the receiving / expense-carrying book.
  final Entry to;

  /// `refs.transfer_group`, shared by both halves.
  final String transferGroup;
}

/// One entry composing a reconciliation pair — the rows S8.3 lists under a
/// pair that does not net to zero (02 §6 🔒).
final class ReconciliationEntry {
  /// Creates the row.
  const ReconciliationEntry({
    required this.entryId,
    required this.bookId,
    required this.bookName,
    required this.date,
    required this.amountPaise,
    required this.inTransit,
    this.note,
  });

  /// The entry, so a reader can open it (07 §1 rule 8).
  final String entryId;

  /// The book this half sits in.
  final String bookId;

  /// That book's name.
  final String bookName;

  /// Accounting date.
  final LocalDate date;

  /// This half's `Due to/from` line, signed integer paise in the engine's
  /// convention (+ = Dr, − = Cr).
  final int amountPaise;

  /// True while this half's review flag is open — the engine's own predicate
  /// ([InterBook.isInTransit]), never a second derivation.
  final bool inTransit;

  /// The entry's note, if it carries one.
  final String? note;
}

/// One row of the Family Reconciliation report (S8.3; 02 §6 🔒, ADR
/// 2026-09-05e §7 🔒): the paired `Due to/from` accounts of two books, what
/// they net to, and the entries composing them.
///
/// [status] is the engine's ([PairStatus]) and only ever one of three things:
/// *balanced*, *mismatch* (non-zero, listed with its entries), or
/// **unconfirmed** — a side inside a book this reader cannot open, which is
/// never reported as a mismatch.
final class ReconciliationPair {
  /// Creates the row.
  const ReconciliationPair({
    required this.bookId,
    required this.bookName,
    required this.accountId,
    required this.status,
    required this.netPaise,
    required this.sidePaise,
    required this.inTransit,
    required this.entries,
    this.counterpartBookId,
    this.counterpartBookName,
    this.counterpartAccountId,
  });

  /// The side the reader holds and the report is written from.
  final String bookId;

  /// [bookId]'s name.
  final String bookName;

  /// [bookId]'s `Due to/from {counterpart}` account.
  final String accountId;

  /// The other book, when the account names one.
  final String? counterpartBookId;

  /// The other book's name — **null when this reader does not hold it**,
  /// which is exactly the case 02 §6 calls *one-sided · unconfirmed*.
  final String? counterpartBookName;

  /// The other book's `Due to/from` account, when it is readable.
  final String? counterpartAccountId;

  /// Balanced · mismatch · unconfirmed (the engine's).
  final PairStatus status;

  /// `balance(A→B) + balance(B→A)` when both sides are readable; the readable
  /// side's balance alone when one is sealed. Signed integer paise.
  final int netPaise;

  /// [bookId]'s own side of the pair, signed integer paise — what this book
  /// says it owes to (−) or is owed by (+) the other.
  final int sidePaise;

  /// True while any half of this pair carries an open review flag: 07 §10's
  /// *In transit*.
  final bool inTransit;

  /// The entries composing both sides, oldest first (02 §6 🔒: a non-zero
  /// pair is listed *with the entries composing it*).
  final List<ReconciliationEntry> entries;

  /// True when both sides are readable and they net to zero — the single
  /// green ✓ the report normally is (07 §10).
  bool get isBalanced => status == PairStatus.balanced;

  /// True when a side is sealed, so the check could not run (ADR
  /// 2026-09-05e §7 🔒).
  bool get isUnconfirmed => status == PairStatus.unconfirmed;
}

// ── profit distribution (02 §7.1 🔒, 13 §3.2 row S14.1) ─────────────────────

/// The `business_setting` key that turns **interest on capital** on (02 §7.1
/// 🔒 — *optional, off by default*).
///
/// ⚠️ SPEC (🔒, for the 02 / 03 owner): 02 §7.1 makes interest on capital *a
/// per-business setting … recorded as a dated business-setting envelope*, and
/// ADR 2026-09-05e §11 lists *interest terms* among what `business_setting`
/// carries — but **no doc names the wire key**, and `structuralSettingKeys`
/// (`packages/data`) holds only `partner_shares` and `structural_quorum`, so
/// the deed cannot carry it either. These two names are this lane's reading,
/// and [interestOnCapitalInForce] reads them conservatively in one direction
/// only: absent, of the wrong type, or uninterpretable means **off**, which is
/// the documented default. A later ruling that renames the key can therefore
/// only ever switch a book *on* that reads as off today — never the reverse.
/// Nothing in the app writes them: enabling is the structural action of
/// 02 §7.2.1 and no screen owns it yet. Reported in the lane report.
const String interestOnCapitalKey = 'interest_on_capital';

/// The rate in **basis points** that goes with [interestOnCapitalKey] (8 % =
/// 800). Basis points, not a float: a rate is money arithmetic (CLAUDE.md
/// rule 1) and `interestOnCapital` takes `rateBasisPoints`.
const String interestOnCapitalRateKey = 'interest_on_capital_rate_bp';

/// The interest-on-capital terms in force, read off the structural settings
/// fold (ADR 2026-09-14b §2). Off unless the book says otherwise, in the
/// shapes [interestOnCapitalKey] documents.
({bool enabled, int rateBasisPoints}) interestOnCapitalInForce(
  Map<String, Object?> inForce,
) {
  final on = inForce[interestOnCapitalKey];
  final rate = inForce[interestOnCapitalRateKey];
  if (on is! bool || !on || rate is! int || rate <= 0) {
    return (enabled: false, rateBasisPoints: 0);
  }
  return (enabled: true, rateBasisPoints: rate);
}

/// Why a distribution cannot be made (02 §7.1 🔒, ADR 2026-09-05e §8).
///
/// Every value is a **state the wizard shows**, never a thrown string: S14.1
/// explains it and offers the way on (07 §1 rule 6). The app decides none of
/// the arithmetic behind them — the ceiling is `distributionHeadroom`'s
/// verdict and the ratio is the structural reader's.
enum DistributionRefusal {
  /// The book is not a shared business — a *Just me* business or a personal
  /// book never mentions partners, ratios or distribution (ADR 2026-09-09b 🔒).
  notShared,

  /// A shared business whose Partner Current A/cs are not seeded yet.
  noPartnerAccounts,

  /// No `Profit Distributed` account: the appropriation has nowhere to post
  /// and 02 §7.1's no-closing-entries rule forbids inventing one here.
  noProfitDistributedAccount,

  /// `partner_shares` is absent or empty. 02 §7.1 🔒: that means the ratio was
  /// **never recorded** — never that the shares are equal.
  ratioNotRecorded,

  /// The ratio in force does not name every Partner Current A/c of the book
  /// (or names one that is not a partner account). Distributing would silently
  /// leave an owner out, so nothing is divided.
  ratioIncomplete,

  /// A `book_config` version or a `business_setting` record was quarantined,
  /// so the terms in force cannot be trusted (ADR 2026-09-14b §2, §5). The
  /// deed alone is the wrong answer once a change exists that cannot be read.
  termsUnverified,

  /// Net profit for the year is exactly zero: there is nothing to appropriate
  /// and `Verbs.profitDistribution` refuses a zero entry.
  nothingToDistribute,

  /// Cumulative distributions would exceed accumulated surplus (ADR
  /// 2026-09-05e §8) — [DistributionRefused.excess] says by how much.
  ceiling,

  /// `checkStructuralRequest` refused the request itself; the engine's own
  /// reason rides in [DistributionRefused.structural].
  structural,
}

/// A distribution the facade declined. **Nothing was authored** — no entry, no
/// request envelope.
final class DistributionRefused implements Exception {
  /// Creates the refusal.
  const DistributionRefused(
    this.bookId,
    this.refusal, {
    this.excess = Paise.zero,
    this.structural,
  });

  /// The book.
  final String bookId;

  /// Which rule refused.
  final DistributionRefusal refusal;

  /// For [DistributionRefusal.ceiling]: how far over the ceiling the proposal
  /// is — 02 §7.1 🔒 *the wizard refuses and says by how much*.
  final Paise excess;

  /// For [DistributionRefusal.structural]: the engine's own reason.
  final StructuralRefusal? structural;

  @override
  String toString() => 'DistributionRefused($bookId: ${refusal.name})';
}

/// One owner's two lines in the preview (02 §7.1 🔒 *The distribution preview
/// shows both lines per partner — interest and share*).
///
/// Both figures are read **off the engine's own lines**; nothing here divides
/// anything. [interest] is `interestOnCapital`'s result and [share] is what
/// `Verbs.profitDistribution` assigned after the remainder rule, both signed
/// as *what is credited to this owner* (negative = charged / a loss shared).
final class DistributionShare {
  /// Creates the row.
  const DistributionShare({
    required this.accountId,
    required this.name,
    required this.ratioWeight,
    required this.interest,
    required this.share,
  });

  /// The Partner Current A/c — the identity the ratio and the remainder rule
  /// both key on (02 §7.1 🔒).
  final String accountId;

  /// The account's name as the chart carries it.
  final String name;

  /// This owner's whole-number weight in the ratio **in force** (ADR
  /// 2026-09-14b §6), never a percentage.
  final int ratioWeight;

  /// Interest on capital credited (negative = charged on a debit balance).
  /// Zero when the setting is off, which is the default.
  final Paise interest;

  /// The ratio share of what remains after interest (negative = a loss share).
  final Paise share;

  /// What this entry credits them in total.
  Paise get total => interest + share;
}

/// Everything S14.1 draws before anything is posted (13 §3.2 row S14.1:
/// *period profit → ratio preview (incl. interest lines) → one multi-line
/// entry*).
///
/// Every figure on it came out of `core_ledger` or `packages/data`: net profit
/// from `netProfit`, the ceiling from `distributionHeadroom`, the ratio from
/// `partnerSharesInForce(structuralSettingsInForce(…))`, interest from
/// `interestOnCapital`, and the split from `Verbs.profitDistribution`'s lines.
/// The facade adds names and nothing else.
final class DistributionPreview {
  /// Creates the preview.
  const DistributionPreview({
    required this.bookId,
    required this.financialYear,
    required this.from,
    required this.to,
    required this.netProfit,
    required this.shares,
    required this.interest,
    required this.lines,
    required this.headroom,
    required this.excess,
    required this.interestEnabled,
    required this.rateBasisPoints,
    required this.ownerSetVersion,
    required this.approvalsRequired,
    this.refusal,
  });

  /// The book.
  final String bookId;

  /// The open financial year the profit figure is scoped to (ADR
  /// 2026-09-05e §8: net profit is **FY-scoped**, whatever period the interest
  /// covers).
  final FinancialYear financialYear;

  /// First day of the interest period (default: the FY's first day).
  final LocalDate from;

  /// Last day of the interest period (default: today).
  final LocalDate to;

  /// The FY's income − expense − distributions already posted in it. Positive
  /// = profit, negative = a loss to be shared by the mirror posting.
  final Paise netProfit;

  /// One row per owner, in Partner Current A/c creation order — the order
  /// 02 §7.1 🔒's tie-break and `Verbs.profitDistribution` both require.
  final List<DistributionShare> shares;

  /// `interestOnCapital`'s raw result, by partner account id; empty when the
  /// setting is off.
  final Map<String, Paise> interest;

  /// The one multi-line entry's lines, exactly as the engine built them —
  /// `Dr Profit Distributed · Cr each Partner Current`, `interest` lines
  /// before `share` lines. Empty when [refusal] is set.
  final List<Line> lines;

  /// What may still be distributed today (ADR 2026-09-05e §8).
  final Paise headroom;

  /// How far [netProfit] overshoots [headroom]; zero when it fits.
  final Paise excess;

  /// Whether interest on capital is on for this book (02 §7.1 🔒 — off by
  /// default).
  final bool interestEnabled;

  /// The rate in basis points when [interestEnabled]; zero otherwise.
  final int rateBasisPoints;

  /// The owner-set version a request would be counted under (ADR
  /// 2026-09-14b §3). 1 — the founding set — when no later version is
  /// derivable.
  final int ownerSetVersion;

  /// Signed approvals a request needs (02 §7.2.1 🔒). 1 is the single-owner
  /// book's quorum of one, where the concept is invisible.
  final int approvalsRequired;

  /// Why nothing can be distributed, or null when it can.
  final DistributionRefusal? refusal;

  /// True when this book posts the entry now rather than proposing it
  /// (02 §7.2.1 🔒 *Single-owner books … have a quorum of one*).
  bool get quorumOfOne => approvalsRequired <= 1;

  /// Total interest credited across the owners.
  Paise get interestTotal => Paise.sum([for (final s in shares) s.interest]);

  /// Total shared by the ratio after interest.
  Paise get shareTotal => Paise.sum([for (final s in shares) s.share]);

  /// The period is a loss: the mirror posting of ADR 2026-09-05e §8.
  bool get isLoss => netProfit.isCredit;

  /// Interest is owed even though it is more than the profit (02 §7.1 🔒 —
  /// *interest is credited in full … the remaining negative figure is then
  /// shared as a loss*).
  bool get interestExceedsProfit =>
      interestTotal.raw > 0 && interestTotal.raw > netProfit.raw;

  /// Nothing stands in the way.
  bool get canDistribute => refusal == null;
}

/// What [LocalLedger.proposeDistribution] did.
sealed class DistributionOutcome {
  const DistributionOutcome();
}

/// A quorum-of-one book: the one multi-line entry is posted (02 §7.1 🔒).
final class DistributionPosted extends DistributionOutcome {
  /// Creates the outcome.
  const DistributionPosted(this.entry);

  /// The posted entry.
  final Entry entry;
}

/// A shared book: one signed `structural_request` envelope is authored and
/// **nothing is applied** (02 §7.2.1 🔒 *Nothing is applied early*). Approval
/// counting and application belong to the Inbox side.
final class DistributionProposed extends DistributionOutcome {
  /// Creates the outcome.
  const DistributionProposed(this.request);

  /// The request as authored.
  final StructuralRequest request;
}

/// The `structural_approval` wire form of a request (03 §2.3 registry; ADR
/// 2026-09-05e §11 — *one type, a `phase` field*).
///
/// ⚠️ SPEC (🔒, for the 03 / ADR owner): ADR 2026-09-14b §5 fixed the
/// `business_setting` wire shape and **no doc fixes this one**;
/// `packages/data`'s `payload_codec.dart` has neither an encoder nor a decoder
/// for `structural_approval`, so `readStructuralState` has no way to be fed
/// from the mirror. This is that codec, written to the same M2 conventions the
/// ADR used for its sibling (snake_case, ids as strings, `hlc` as the raw
/// int), carrying exactly the fields `StructuralRequest` declares plus the
/// `phase` discriminator. It belongs in `packages/data` beside
/// `BusinessSetting`; it lives here only because that package is another
/// lane's. Reported in the lane report.
Map<String, Object?> encodeStructuralEvent(StructuralEvent event) =>
    switch (event) {
      StructuralRequest() => {
        'id': event.id,
        'book_id': event.bookId,
        'hlc': event.hlc.raw,
        'phase': 'initiation',
        'action': event.action.wire,
        'by_user': event.byUser,
        'owner_set_version': event.ownerSetVersion,
        'payload': event.payload,
      },
      StructuralApproval() => {
        'id': event.id,
        'book_id': event.bookId,
        'hlc': event.hlc.raw,
        'phase': 'approval',
        'request_id': event.requestId,
        'by_user': event.byUser,
        'owner_set_version': event.ownerSetVersion,
      },
      StructuralVeto() => {
        'id': event.id,
        'book_id': event.bookId,
        'hlc': event.hlc.raw,
        'phase': 'veto',
        'request_id': event.requestId,
        'by_user': event.byUser,
        'owner_set_version': event.ownerSetVersion,
        'reason': event.reason,
      },
      StructuralLapse() => {
        'id': event.id,
        'book_id': event.bookId,
        'hlc': event.hlc.raw,
        'phase': 'lapse',
        'request_id': event.requestId,
        'by_user': event.byUser,
      },
    };

/// Reads a `structural_approval` payload back, or null when this build cannot
/// interpret it — an unknown `phase`, or an action outside 02 §7.2.1's 🔒 set.
///
/// Null is never silence with consequences: an unreadable structural envelope
/// leaves the owner fold exactly where it was, which is the strictest reading
/// (nothing is approved by something nobody can read).
StructuralEvent? decodeStructuralEvent(
  Map<String, Object?> json, {
  String? authorDevice,
  int? authorSeq,
}) {
  final id = json['id'];
  final bookId = json['book_id'];
  final hlc = json['hlc'];
  final byUser = json['by_user'];
  if (id is! String || bookId is! String || hlc is! int || byUser is! String) {
    return null;
  }
  final requestId = json['request_id'];
  final version = json['owner_set_version'];
  switch (json['phase']) {
    case 'initiation':
      final action = StructuralAction.fromWire(json['action']);
      if (action == null || version is! int) return null;
      final payload = json['payload'];
      return StructuralRequest(
        id: id,
        bookId: bookId,
        hlc: Hlc(hlc),
        action: action,
        byUser: byUser,
        ownerSetVersion: version,
        payload: payload is Map<String, Object?>
            ? Map<String, Object?>.unmodifiable(payload)
            : const {},
        authorDevice: authorDevice,
        authorSeq: authorSeq,
      );
    case 'approval':
      if (requestId is! String || version is! int) return null;
      return StructuralApproval(
        id: id,
        bookId: bookId,
        hlc: Hlc(hlc),
        requestId: requestId,
        byUser: byUser,
        ownerSetVersion: version,
        authorDevice: authorDevice,
        authorSeq: authorSeq,
      );
    case 'veto':
      final reason = json['reason'];
      if (requestId is! String ||
          version is! int ||
          reason is! String ||
          reason.trim().isEmpty) {
        return null;
      }
      return StructuralVeto(
        id: id,
        bookId: bookId,
        hlc: Hlc(hlc),
        requestId: requestId,
        byUser: byUser,
        ownerSetVersion: version,
        reason: reason,
        authorDevice: authorDevice,
        authorSeq: authorSeq,
      );
    case 'lapse':
      if (requestId is! String) return null;
      return StructuralLapse(
        id: id,
        bookId: bookId,
        hlc: Hlc(hlc),
        requestId: requestId,
        byUser: byUser,
        authorDevice: authorDevice,
        authorSeq: authorSeq,
      );
    default:
      return null;
  }
}

/// The local ledger.
final class LocalLedger implements DeviceCertifier, AcceptedKeySink {
  /// Creates the facade. [suite] is the app's libsodium binding wrapped in a
  /// [CryptoSuite]; [now] is the injected wall clock the HLC ticks against.
  LocalLedger({
    required this.db,
    required this.keys,
    required this.suite,
    required this.now,
    this.reviewPolicy = noReviewPolicy,
  }) : mirror = Mirror(db, hasher: blake2bHasher(suite)) {
    recompute = Recompute(
      db,
      mirror: mirror,
      opener: CryptoPayloadOpener(suite, _keySource),
    );
  }

  /// The open database (03).
  final LedgerDatabase db;

  /// Secrets at rest (04 §3.3).
  final KeyStore keys;

  /// libsodium + CSPRNG.
  final CryptoSuite suite;

  /// Injected clock (09 §1).
  final DateTime Function() now;

  /// The auto-post limit this client measures its own entries against
  /// (02 §3 🔒, 03 §3.3 rule 5 🔒). Defaults to [noReviewPolicy] — *no limit
  /// anywhere*, which is what the app did before the seam existed, so every
  /// existing caller and test is unchanged.
  ///
  /// Mutable, like [onOwnCert], because the composition root builds this
  /// ledger *before* the members repository that answers it: the repository
  /// needs `identity.tenantId` / `identity.userId`, which only exist once this
  /// ledger has bootstrapped. `bootstrap.dart` installs the real policy a few
  /// lines later, in the same synchronous stretch, before `runApp`.
  ReviewPolicy reviewPolicy;

  /// Envelope mirror + outbox (03 §3.1).
  final Mirror mirror;

  /// Projection rebuilder (03 §3.3).
  late final Recompute recompute;

  final _SharedKeySource _keySource = _SharedKeySource();
  final Map<String, BookRecompute> _last = {};

  LedgerIdentity? _identity;
  DeviceKeyPair? _device;
  UmkKeyPair? _umk;
  VerifiedUmkPublic? _umkVerified;
  VerifiedMemberDirectory? _verifiedMembers;
  DeviceCert? _ownCert;
  Hlc _clock = const Hlc(0);

  /// Called with this device's own certificate the moment it is filed —
  /// [installOwnCert] at activation, and again at open when one was already
  /// stored. The composition root's one late binding: the trust store the
  /// sync engine reads is built *from* this ledger's key material, so it
  /// cannot be handed to this constructor (`bootstrap.dart`).
  void Function(DeviceCert cert)? onOwnCert;

  /// True after [bootstrapSolo] (or a successful re-open).
  bool get isOpen => _identity != null;

  /// This install's ids; throws [LedgerNotOpen] before bootstrap.
  LedgerIdentity get identity => _identity ?? (throw const LedgerNotOpen());

  /// The last Recompute report for [bookId] (S1.4), if the book was rebuilt
  /// in this process.
  BookRecompute? lastRecompute(String bookId) => _last[bookId];

  /// The one seam through which this install's key material leaves the
  /// ledger: [LedgerKeyMaterial], read by `sync_engine`'s `CryptoGuard` and
  /// nothing else. One accessor rather than three getters so a caller takes
  /// the whole coherent set (device + UMK + the live book keys of *this*
  /// install) or none of it — a guard built from half of another device's
  /// material would decrypt nothing and verify everything.
  ///
  /// Borrowed, not copied: the returned value holds the ledger's own objects
  /// and no copy of any secret byte, so [dispose] zeroises what a holder
  /// still points at. Throws [LedgerNotOpen] before [bootstrapSolo].
  LedgerKeyMaterial get keyMaterial {
    _requireOpen();
    return LedgerKeyMaterial._(
      userId: _identity!.userId,
      device: _device!,
      umk: _umk!,
      bookKeys: _keySource.required,
      ownUmk: _umkVerified!,
      others: _verifiedMembers!,
    );
  }

  /// The members a ceremony on this device confirmed (04 §6.4), and the one
  /// door a completed ceremony persists a key through — `features/ceremony`
  /// takes this as its [VerifiedMemberSink]. Throws [LedgerNotOpen] before
  /// bootstrap.
  ///
  /// Read through [keyMaterial] by everything that seals: a guardian share
  /// (04 §7.3) and a book key (04 §5.1) reach a member only as the
  /// [VerifiedUmkPublic] a record here proves.
  VerifiedMemberDirectory get verifiedMembers =>
      _verifiedMembers ?? (throw const LedgerNotOpen());

  // ── device certificate (04 §3.4 🔒 · 06 §3 step 3) ────────────────────────

  /// This install's own certificate, or null while it is uncertified.
  @override
  DeviceCert? get ownDeviceCert => _ownCert;

  /// Self-certifies this device under its own UMK (04 §3.4: *at signup, the
  /// first device holds the UMK and self-certifies*).
  ///
  /// The signed bytes are `DeviceCert.signedBytes` — `uuid16(device_id) ‖
  /// device_pub_ed ‖ device_pub_x ‖ i64be(issued_at_ms)`, the 🔒 order — over
  /// **this ledger's** device id (ADR 2026-09-16 §1: there is no other one)
  /// and the public halves of the pair whose seeds sit in [keys]. The clock is
  /// the injected one (rule 3); nothing secret leaves.
  ///
  /// The certificate is not filed here: [installOwnCert] does that, once the
  /// server has accepted it.
  @override
  DeviceCertOffer issueOwnCert() {
    _requireOpen();
    final umk = _umk!;
    return DeviceCertOffer(
      cert: DeviceCert.issue(
        suite,
        issuer: umk,
        userId: _identity!.userId,
        device: _device!.public,
        issuedAtMs: now().millisecondsSinceEpoch,
      ),
      umkPubEd: umk.public.ed25519,
    );
  }

  /// Files [cert] as this device's own (see [DeviceCertifier.installOwnCert]).
  ///
  /// Checked before it is believed, even though this device issued it: it must
  /// name this device, carry its public halves, and verify under this
  /// install's own UMK. A certificate that fails any of those is not this
  /// device's and is refused — the trust chain never widens by accident
  /// (04 §8.2 🔒).
  @override
  Future<void> installOwnCert(DeviceCert cert) async {
    _requireOpen();
    final device = _device!.public;
    if (cert.device != device) {
      throw ArgumentError.value(
        cert.deviceId,
        'cert',
        'is not this device (04 §3.4)',
      );
    }
    if (cert.userId != _identity!.userId || !cert.verify(suite, _umk!.public)) {
      throw ArgumentError.value(
        cert.deviceId,
        'cert',
        'does not verify under this install\'s UMK',
      );
    }
    await keys.write(LocalLedgerKeys.deviceCert, encodeDeviceCert(cert));
    _ownCert = cert;
    onOwnCert?.call(cert);
  }

  /// Reads a filed certificate back at open. A record that will not parse, or
  /// that no longer matches this device (a re-keyed install), is ignored: the
  /// device reads as uncertified, which is the recoverable state 06 §3 step 3
  /// already describes. Nothing is deleted (ADR 05b §2 — a wipe needs a signed
  /// record).
  Future<void> _loadOwnCert() async {
    final raw = await keys.read(LocalLedgerKeys.deviceCert);
    if (raw == null) return;
    final cert = decodeDeviceCert(raw);
    if (cert == null) return;
    if (cert.device != _device!.public || cert.userId != _identity!.userId) {
      return;
    }
    if (!cert.verify(suite, _umk!.public)) return;
    _ownCert = cert;
  }

  // ── bootstrap ─────────────────────────────────────────────────────────────

  /// First run of a solo user (07 §3.1, 04 §3.1–§3.4): mints device, user and
  /// tenant ids, generates the device keys and the UMK from the suite's
  /// CSPRNG, self-verifies the device (the first device holds the UMK, 04
  /// §3.4), wraps the UMK to it and stores everything through [keys]. When
  /// [firstBookName] is given and no book exists, the first book (with its
  /// key, v1) is created too. Idempotent: a second call — or a new
  /// [LocalLedger] over the same store — reopens the same identity and posts
  /// with the same device.
  Future<LedgerIdentity> bootstrapSolo({
    String? firstBookName,
    BookType firstBookType = BookType.personal,
    String openingBalanceName = 'Opening Balance',
    LocalDate? startDate,
  }) async {
    if (_identity == null) {
      final stored = await keys.read(LocalLedgerKeys.identity);
      if (stored != null) {
        await _reopen(stored);
      } else {
        await _firstRun();
      }
    }
    if (firstBookName != null && (await mirror.bookIds()).isEmpty) {
      await createBook(
        name: firstBookName,
        type: firstBookType,
        openingBalanceName: openingBalanceName,
        startDate: startDate,
      );
    }
    return _identity!;
  }

  /// The one place a device id is minted (ADR 2026-09-16 §1 🔒): the auth
  /// client registers this id with the server and signs challenges under it;
  /// every envelope and signed record carries it. Nothing else mints one.
  Future<void> _firstRun() async {
    final deviceId = newId();
    final userId = newId();
    final tenantId = newId();

    final edSeed = suite.randomBytes(32);
    final xSeed = suite.randomBytes(32);
    final DeviceKeyPair device;
    try {
      device = _deviceFromSeeds(deviceId, edSeed, xSeed);
      await keys.write(KeyIds.deviceSigningKey, edSeed);
      await keys.write(KeyIds.deviceAgreementKey, xSeed);
    } finally {
      suite.zeroize(edSeed);
      suite.zeroize(xSeed);
    }

    final umk = UmkKeyPair.generate(suite);
    final wrapped = wrapUmkToDevice(suite, umk, _selfVerifyDevice(device));
    await keys.write(KeyIds.wrappedUmk, wrapped.bytes);

    final identity = LedgerIdentity(
      deviceId: deviceId,
      userId: userId,
      tenantId: tenantId,
    );
    await keys.write(
      LocalLedgerKeys.identity,
      identity.encode(suiteVersion: suiteVersion),
    );

    _device = device;
    _umk = umk;
    _umkVerified = _selfVerifyUmk(umk, userId);
    _keySource.store = BookKeyStore(tenantId: tenantId);
    await _openVerifiedMembers(identity);
    _identity = identity;
  }

  Future<void> _reopen(Uint8List identityBytes) async {
    final id = LedgerIdentity.decode(identityBytes);
    if (id == null) {
      throw StateError('identity record unreadable — recovery (03 §5)');
    }
    final edSeed = await keys.read(KeyIds.deviceSigningKey);
    final xSeed = await keys.read(KeyIds.deviceAgreementKey);
    final wrappedUmk = await keys.read(KeyIds.wrappedUmk);
    if (edSeed == null || xSeed == null || wrappedUmk == null) {
      throw StateError('identity present but device keys missing — recovery');
    }
    final DeviceKeyPair device;
    try {
      device = _deviceFromSeeds(id.deviceId, edSeed, xSeed);
    } finally {
      suite.zeroize(edSeed);
      suite.zeroize(xSeed);
    }
    final umk = unwrapUmk(
      suite,
      WrappedUmk(deviceId: id.deviceId, bytes: wrappedUmk),
      device,
    );
    _device = device;
    _umk = umk;
    _umkVerified = _selfVerifyUmk(umk, id.userId);
    _keySource.store = BookKeyStore(tenantId: id.tenantId);
    await _openVerifiedMembers(id);
    _identity = id;
    await _loadOwnCert();

    // Tenants and wrapped book keys back into memory (03 §3.1 key_cache).
    for (final b in await db.select(db.booksP).get()) {
      _keySource.tenants[b.id] = b.tenantId;
    }
    for (final row in await db.select(db.keyCache).get()) {
      _keySource.tenants.putIfAbsent(row.bookId, () => id.tenantId);
      final ref = BookKeyRef(bookId: row.bookId, keyVersion: row.keyVersion);
      _keySource.required.put(
        unwrapBookKey(suite, _decodeWrappedBookKey(ref, row.wrappedBlob), umk),
      );
    }
    await _seedClock();
    for (final bookId in await mirror.bookIds()) {
      await _rebuild(bookId);
    }
  }

  /// Rebuilds a [DeviceKeyPair] from its two 32-byte seeds by replaying them
  /// through `DeviceKeyPair.generate` on a suite whose random source is the
  /// stored seeds — the same determinism path suite B relies on. ⚠️ SPEC: a
  /// `DeviceKeyPair.fromSeeds` factory in core_crypto would make this direct.
  DeviceKeyPair _deviceFromSeeds(String deviceId, Uint8List ed, Uint8List x) {
    final queue = <Uint8List>[Uint8List.fromList(ed), Uint8List.fromList(x)];
    final replay = CryptoSuite(
      suite.sodium,
      random: (int n) {
        if (queue.isEmpty) throw StateError('device seed replay exhausted');
        final next = queue.removeAt(0);
        if (next.length != n) {
          throw StateError('device seed is ${next.length} bytes, need $n');
        }
        return next;
      },
    );
    return DeviceKeyPair.generate(replay, deviceId: deviceId);
  }

  /// The first device verifies its own keys byte-for-byte through the
  /// ceremony module — the only producer of [VerifiedDevicePublic] — so the
  /// UMK is wrapped to a verified device by construction (04 §3.4, §8.2).
  VerifiedDevicePublic _selfVerifyDevice(DeviceKeyPair device) {
    final r = Ceremony.verifyDeviceQr(
      suite,
      scanned: DeviceQrPayload(
        device: device.public,
        nonce: suite.randomBytes(ceremonyNonceBytes),
      ),
      relayed: device.public,
    );
    return switch (r) {
      DeviceVerified(:final verified) => verified,
      DeviceMismatch() => throw StateError('device self-verification failed'),
    };
  }

  /// Same for the user's own UMK: book keys are wrapped only to a
  /// [VerifiedUmkPublic] (04 §8.2), and the owner's own fingerprint is
  /// verified by the same byte-for-byte check.
  VerifiedUmkPublic _selfVerifyUmk(UmkKeyPair umk, String userId) {
    final r = Ceremony.verifyQr(
      suite,
      scanned: QrPayload(
        userId: userId,
        umk: umk.public,
        nonce: suite.randomBytes(ceremonyNonceBytes),
      ),
      relayed: umk.public,
      relayedUserId: userId,
    );
    return switch (r) {
      CeremonyVerified(:final verified) => verified,
      _ => throw StateError('UMK self-verification failed'),
    };
  }

  /// Builds the verification directory over `signed_records_local` and folds
  /// what is already stored (04 §6.4, §8.2 🔒). Called at bootstrap and at
  /// every re-open, before [identity] is set, so no caller can read
  /// [keyMaterial] against a half-built directory.
  Future<void> _openVerifiedMembers(LedgerIdentity id) async {
    final directory = VerifiedMemberDirectory(
      suite: suite,
      records: SignedRecordMirror(db),
      tenantId: id.tenantId,
      selfUserId: id.userId,
      // Borrowed, never held: after [dispose] the callback throws rather than
      // hand out a zeroised key.
      author: () => _device ?? (throw const LedgerNotOpen()),
      tick: _tick,
      newRecordId: newId,
    );
    await directory.load();
    _verifiedMembers = directory;
  }

  Future<void> _seedClock() async {
    final maxHlc = db.envelopesLocal.hlc.max();
    final row = await (db.selectOnly(
      db.envelopesLocal,
    )..addColumns([maxHlc])).getSingle();
    final v = row.read(maxHlc);
    if (v != null && v > _clock.raw) _clock = Hlc(v);
  }

  // ── ids, clock, keys ──────────────────────────────────────────────────────

  /// A fresh canonical uuid (v4 layout) from libsodium's CSPRNG — entry,
  /// account, book and envelope ids (04 §4 requires canonical uuids).
  String newId() {
    final b = suite.randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return Uuid16.fromBytes(b);
  }

  Hlc _tick() => _clock = _clock.tick(physicalMs: now().millisecondsSinceEpoch);

  /// Today per the injected clock, as the ledger's calendar day.
  LocalDate today() {
    final t = now();
    return LocalDate(t.year, t.month, t.day);
  }

  BookKey _currentKey(String bookId) {
    final store = _keySource.required;
    final version = store.highestVersion(bookId);
    final key = version == null
        ? null
        : store.bookKey(BookKeyRef(bookId: bookId, keyVersion: version));
    return key ?? (throw StateError('no key for book $bookId'));
  }

  /// `suite_version(1) ‖ recipient fingerprint(32) ‖ sealed box` — the
  /// `key_cache.wrapped_blob` layout (03 §3.1; BKs rest wrapped to the UMK).
  static Uint8List _encodeWrappedBookKey(WrappedBookKey w) =>
      Bytes.concat([Bytes.u8(w.suiteVersion), w.recipient.bytes, w.blob]);

  /// Persists a book key the sync engine's guard accepted on the meta channel
  /// (05 §5) — the app's half of `sync_engine`'s `AcceptedKeySink`.
  ///
  /// Why it exists: the guard unwraps a `wrapped_keys` row into the in-memory
  /// [BookKeyStore], and the meta cursor then moves past that row for good. A
  /// device that joined somebody else's book would hold the key for one
  /// process and sit in `key_wait` for ever afterwards (05 §4) — a key it was
  /// given and can no longer use. So the blob rests in `key_cache`, which is
  /// what `_reopen` reads at the next launch.
  ///
  /// What is written is the sealed box **exactly as it arrived**: already
  /// wrapped to this user's UMK, so nothing here re-wraps to a fingerprint
  /// nobody verified (04 §8.2 🔒) and no unwrapped key touches the disk
  /// (03 §3.1). The fingerprint check below is belt and braces — the guard
  /// unsealed the blob with this UMK, so a foreign recipient cannot reach
  /// here — but it is the last gate before a row that `_reopen` could only
  /// throw on, and a ledger that will not open is worse than a key refused.
  ///
  /// Idempotent: the same `(book, version)` is the same key, and the copy
  /// already at rest is the one that has been opening envelopes.
  @override
  Future<void> keyAccepted(AcceptedBookKey key) async {
    _requireOpen();
    final mine = Fingerprint.of(suite, _umk!.public);
    if (key.recipient != mine) {
      throw ArgumentError.value(
        key.ref.bookId,
        'key',
        'wrapped to another fingerprint — not this install\'s (04 §8.2)',
      );
    }
    await db
        .into(db.keyCache)
        .insert(
          KeyCacheCompanion.insert(
            bookId: key.ref.bookId,
            keyVersion: key.ref.keyVersion,
            wrappedBlob: _encodeWrappedBookKey(
              WrappedBookKey(
                ref: key.ref,
                sealed: SealedBlob(
                  suiteVersion: key.suiteVersion,
                  recipient: key.recipient,
                  bytes: key.sealed,
                ),
              ),
            ),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    // The book's tenant, for the projector's [KeySource]: a book learned
    // through sync has no `books_p` row until its config envelope opens.
    _keySource.tenants.putIfAbsent(key.ref.bookId, () => _identity!.tenantId);
  }

  static WrappedBookKey _decodeWrappedBookKey(BookKeyRef ref, Uint8List blob) =>
      WrappedBookKey(
        ref: ref,
        sealed: SealedBlob(
          suiteVersion: blob[0],
          recipient: Fingerprint(Uint8List.sublistView(blob, 1, 33)),
          bytes: Uint8List.sublistView(blob, 33),
        ),
      );

  void _requireOpen() {
    if (_identity == null) throw const LedgerNotOpen();
  }

  // ── books and accounts ────────────────────────────────────────────────────

  /// Creates a book (02 §1.1): mints its id and key v1 (wrapped to the
  /// verified UMK into `key_cache`), authors the `book_config` envelope and
  /// the *Opening Balance* system account (02 §4 needs it), rebuilds.
  Future<String> createBook({
    required String name,
    required BookType type,
    int fyStartMonth = 4,
    BookOwnership ownership = BookOwnership.justMe,
    String openingBalanceName = 'Opening Balance',
    String drawingsName = 'Drawings',
    String profitDistributedName = 'Profit Distributed',
    String? cashName,
    String gollakName = 'Gollak Cash',
    List<SeedCategory>? categories,
    List<String> ownerNames = const [],
    List<int> ownerShares = const [],
    List<String> ownerMemberIds = const [],
    OrganizationSubtype? organizationSubtype,
    LocalDate? startDate,
  }) async {
    _requireOpen();
    if (ownerShares.isNotEmpty && ownerShares.length != ownerNames.length) {
      throw ArgumentError.value(
        ownerShares,
        'ownerShares',
        'must be empty or one weight per owner name',
      );
    }
    if (ownerMemberIds.isNotEmpty &&
        ownerMemberIds.length != ownerNames.length) {
      throw ArgumentError.value(
        ownerMemberIds,
        'ownerMemberIds',
        'must be empty or one member id per owner name',
      );
    }
    if (ownerShares.any((w) => w <= 0)) {
      // ADR 2026-09-09 §2: the stepper floors at 1 and an owner cannot hold
      // zero shares. A non-positive weight here is a caller bug, and 02 §7.1
      // would divide by a wrong Σweights rather than fail loudly.
      throw ArgumentError.value(
        ownerShares,
        'ownerShares',
        'share weights are whole and positive',
      );
    }
    final id = _identity!;
    final bookId = newId();
    final bk = BookKey.generate(suite, bookId: bookId, keyVersion: 1);
    final wrapped = wrapBookKey(suite, bk, _umkVerified!);
    await db
        .into(db.keyCache)
        .insert(
          KeyCacheCompanion.insert(
            bookId: bookId,
            keyVersion: 1,
            wrappedBlob: _encodeWrappedBookKey(wrapped),
          ),
        );
    _keySource.required.put(bk);
    _keySource.tenants[bookId] = id.tenantId;

    // The partner accounts' ids are minted here, before the config is
    // authored, because `book_config.partner_shares` keys the weights to the
    // **account id** — the one identity that survives renaming either the
    // owner or the `{Name} — Partner Current A/c` the seed names after them
    // (02 §7.1 🔒, whose remainder rule also keys on the partner account).
    // The accounts themselves are authored below, with these ids.
    final shared =
        type == BookType.business && ownership == BookOwnership.shared;
    final partnerAccountIds = [
      if (shared)
        for (final _ in ownerNames) newId(),
    ];
    final config = BookConfig(
      id: bookId,
      tenantId: id.tenantId,
      type: type,
      name: name,
      fyStartMonth: fyStartMonth,
      ownership: ownership,
      // Recorded only when the caller collected them (S0.6a1, ADR
      // 2026-09-09 §2). Absent means *not recorded* and a reader must say so;
      // it never means equal shares.
      partnerShares: {
        if (ownerShares.isNotEmpty)
          for (final (i, accountId) in partnerAccountIds.indexed)
            accountId: ownerShares[i],
      },
      // 07 §3.1.1 🔒: the trust branch names the trust *and its type*. Null on
      // every other book type, and on a trust whose type was never collected.
      organizationSubtype: type == BookType.organization
          ? organizationSubtype
          : null,
      // ADR 2026-09-09d §4: the books begin on the day the book is made —
      // stamped once, never moved. The UI never offers a picker (owner-ruled:
      // read-only today); the parameter exists for fixtures and imports.
      startDate: startDate ?? today(),
    );
    await _author(
      bookId: bookId,
      objectId: bookId,
      objectType: 'book_config',
      hlc: _tick(),
      object: (_) => config.toJson(),
    );
    // ADR 2026-09-09c §1 — the money the book *certainly* has, and only that
    // (ADR 2026-09-09d §3: seed a floor, never a guess). No bank is seeded in
    // any book type (ADR 2026-09-09d §1); one arrives through *Add an
    // account* and asks for its balance in the same breath (02 §4 🔒).
    await addAccount(
      bookId,
      name: cashName ?? defaultCashName(type),
      accountClass: AccountClass.money,
      subtype: MoneySubtype.cash,
    );
    // 07 §3.1 step 3 🔒 / ADR 2026-09-09d §2: the trust's gollak is a
    // `cash_collection` account and stays a **different account** from the
    // Cash A/c — counted money leaves the box only by deposit (02 §8.2).
    if (type == BookType.organization) {
      await addAccount(
        bookId,
        name: gollakName,
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cashCollection,
      );
    }
    await addAccount(
      bookId,
      name: openingBalanceName,
      accountClass: AccountClass.equitySystem,
      systemRole: SystemRole.openingBalance,
    );
    // ADR 2026-09-09b §2: the Capital/Drawings pair belongs to a *Just me*
    // business. Capital is the Opening Balance account above — both worked
    // examples name it `Opening Balance / Capital A/c`, so it is not a second
    // account. A shared business gets one Partner Current A/c per owner
    // instead, which 02 §7.1 calls the single place that relationship lives.
    if (type == BookType.business && ownership == BookOwnership.justMe) {
      await addAccount(
        bookId,
        name: drawingsName,
        accountClass: AccountClass.equitySystem,
        systemRole: SystemRole.drawings,
      );
    }
    // ADR 2026-09-09c §1: a shared business seeds `Profit Distributed` and
    // **one `{Name} — Partner Current A/c` per owner** — the names come from
    // S0.6a1 ([ownerNames], in the order shown there, the creating user
    // first). 02 §7.1 calls the Partner Current A/c the single place that
    // relationship lives, which is why an owner's opening contribution posts
    // there and never to a Capital account (ADR 2026-09-09c §4).
    //
    // The weights collected on S0.6a1 ride in the `book_config` envelope
    // above, keyed to the ids these accounts are created with, so 02 §7.1's
    // division has a source of truth that outlives the screen. `PartnerShare`
    // (core_ledger) still takes its weight per call at distribution time —
    // the engine is told the ratio, it does not look it up.
    if (shared) {
      await addAccount(
        bookId,
        name: profitDistributedName,
        accountClass: AccountClass.equitySystem,
        systemRole: SystemRole.profitDistributed,
      );
      for (final (i, owner) in ownerNames.indexed) {
        await addAccount(
          bookId,
          id: partnerAccountIds[i],
          name: partnerCurrentAccountName(owner),
          accountClass: AccountClass.partner,
          // The chart's mapping from Partner Current A/c id to the member who
          // signs (02 §7.1 🔒; ADR 2026-09-14b §3 derives the founding owner
          // set from exactly this). Empty until the owners step collects real
          // member ids — an owner set that is *not derivable* is read as such
          // rather than guessed, which is the strict reading.
          memberId: ownerMemberIds.isEmpty ? null : ownerMemberIds[i],
        );
      }
    }
    // ADR 2026-09-09c §1's income/expense column. Category names are *user
    // data* the user may rename, not ARB labels, so they are passed in by the
    // caller localised (docs/reference/seed-category-trees.md, "How these
    // reach the app") — which is also what keeps `core_ledger` free of
    // strings.
    //
    // ⚠️ SPEC: only the **trust** tree has a default here, because 07 §3.1
    // step 3 🔒 names it. The household / shop / farm trees are a DRAFT that
    // 01 §1.8 and 02 put behind the pilot and the native-review gate (ADR
    // 2026-09-09c Open ⚠️), so seeding them from an unratified file would be
    // inventing the user's chart. Until they are ratified the caller supplies
    // them or the book starts with no categories; see the lane report.
    for (final c in categories ?? defaultCategorySeed(type)) {
      await addAccount(bookId, name: c.name, accountClass: c.accountClass);
    }
    return bookId;
  }

  /// The seeded name of the one cash account a [type] of book certainly has
  /// (ADR 2026-09-09c §1). Editable afterwards like any seeded name.
  static String defaultCashName(BookType type) => switch (type) {
    BookType.personal => 'Cash A/c',
    BookType.business => 'Business Cash A/c',
    BookType.family || BookType.joint => 'Joint Cash A/c',
    BookType.organization => 'Cash',
  };

  /// The category accounts seeded when the caller passes none. Empty for
  /// every type but the trust, whose four names 07 §3.1 step 3 🔒 fixes.
  static List<SeedCategory> defaultCategorySeed(BookType type) =>
      type == BookType.organization
      ? const [
          SeedCategory('Donation Income', AccountClass.categoryIncome),
          SeedCategory('Langar Expense', AccountClass.categoryExpense),
          SeedCategory('Building Repair', AccountClass.categoryExpense),
          SeedCategory('Honorarium', AccountClass.categoryExpense),
        ]
      : const [];

  /// `{Name} — Partner Current A/c`, the seeded name of an owner's partner
  /// account (ADR 2026-09-09c §1, 02 §7.1). Editable afterwards like any
  /// seeded name; the engine keys on the account id, never on this string.
  static String partnerCurrentAccountName(String owner) =>
      '$owner — Partner Current A/c';

  /// Books this device holds, as projected.
  Stream<List<BooksPData>> watchBooks() => db.select(db.booksP).watch();

  /// The day [bookId]'s books begin (ADR 2026-09-09d §4), or null for a book
  /// written before the ADR. Read from the projection, so a book that arrived
  /// by sync carries its boundary the moment its config is projected.
  Future<LocalDate?> startDateOf(String bookId) async {
    final row = await (db.select(
      db.booksP,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    final iso = row?.startDate;
    return iso == null ? null : LocalDate.parse(iso);
  }

  /// The month [bookId]'s financial year starts in (02 §1.1, default April).
  /// Read from the projection, so a synced book carries its own calendar.
  Future<int> fyStartMonthOf(String bookId) async {
    final row = await (db.select(
      db.booksP,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    return row?.fyStartMonth ?? 4;
  }

  /// Adds an account (02 §1.2 — created inline, class inferred by the caller
  /// from the picker slot) and rebuilds the book. Returns the engine account.
  ///
  /// [id] is minted when omitted. [createBook] passes one so that the
  /// `book_config` it has already authored can name the Partner Current
  /// accounts it is about to create (02 §7.1's weights key to the account id,
  /// never to the name).
  Future<Account> addAccount(
    String bookId, {
    required String name,
    required AccountClass accountClass,
    String? id,
    MoneySubtype? subtype,
    SystemRole? systemRole,
    String? usualCategoryId,
    String? counterpartBookId,
    String? memberId,
  }) async {
    _requireOpen();
    final countExp = db.envelopesLocal.envelopeId.count();
    final order =
        await (db.selectOnly(db.envelopesLocal)
              ..addColumns([countExp])
              ..where(
                db.envelopesLocal.bookId.equals(bookId) &
                    db.envelopesLocal.objectType.equals('account'),
              ))
            .map((r) => r.read(countExp)!)
            .getSingle();
    final account = Account(
      id: id ?? newId(),
      bookId: bookId,
      name: name,
      accountClass: accountClass,
      subtype: subtype,
      systemRole: systemRole,
      memberId: memberId,
      counterpartBookId: counterpartBookId,
      createdOrder: order,
    );
    await _author(
      bookId: bookId,
      objectId: account.id,
      objectType: 'account',
      hlc: _tick(),
      object: (_) =>
          AccountPayload(account, usualCategoryId: usualCategoryId).toJson(),
    );
    await _rebuild(bookId);
    return account;
  }

  /// The chart as last projected (rebuilding if this process has not yet).
  Future<Chart> chartOf(String bookId) async =>
      (_last[bookId] ?? await _rebuild(bookId)).chart;

  /// The book's `book_config` as last projected (03 §2.3), or null for a book
  /// with no config envelope. The read path for the fields `books_p` does not
  /// project: [BookConfig.ownership], the 02 §7.1 🔒 partner share weights and
  /// the 07 §3.1.1 organization subtype.
  Future<BookConfig?> configOf(String bookId) async =>
      (_last[bookId] ?? await _rebuild(bookId)).config;

  Future<LedgerState> _stateOf(String bookId) async =>
      (_last[bookId] ?? await _rebuild(bookId)).state;

  // ── posting ───────────────────────────────────────────────────────────────

  /// Posts a drafted entry (02 §3: it counts the moment it is saved). The
  /// draft's `hlc`, `createdByDevice` and `authorSeq` are stamped here; its
  /// id is kept when it is a canonical uuid, else minted. Checks 02 §1.4
  /// invariants, the §2 shape, the authoring rules (no future date) and the
  /// period lock (§8) first — a failure throws [PostRejected] and appends
  /// nothing.
  Future<Entry> post(Entry draft) async {
    _requireOpen();
    final entry = _stamp(draft);
    final violations = await _violationsOf(entry);
    if (violations.isNotEmpty) throw PostRejected(entry.id, violations);
    return _append(entry);
  }

  /// The draft with its id and authoring device settled — everything a
  /// validation needs, and nothing that touches the clock.
  ///
  /// The HLC is deliberately *not* stamped here: it is taken at the moment of
  /// append ([_append]), so validating a draft costs no tick and a refused
  /// draft leaves no hole in this device's clock sequence.
  Entry _stamp(Entry draft) => draft.copyWith(
    id: Uuid16.isCanonical(draft.id) ? draft.id : newId(),
    createdByDevice: _identity!.deviceId,
  );

  /// Everything wrong with [entry] against its own book's projected state:
  /// the 02 §1.4 invariants, the §2 shape, the authoring rules (no future
  /// date), the §8 period lock and the ADR 2026-09-09d §4 start-date guard.
  ///
  /// Pure with respect to the ledger — it appends nothing — so a caller with
  /// **two** halves to place can ask about both before placing either.
  Future<List<Violation>> _violationsOf(Entry entry) async {
    final chart = await chartOf(entry.bookId);
    final state = await _stateOf(entry.bookId);
    final violations = <Violation>[
      ...checkUniversalInvariants(entry, chart),
      ...checkAuthoringRules(entry, today: today()),
    ];
    final shape = checkShape(entry, chart);
    if (shape != null) violations.add(shape);
    final period = entry.accountingDate.yearMonth;
    if (state.periods.currentStatus(period) == PeriodStatus.locked) {
      violations.add(
        Violation(ViolationKind.periodLocked, '$period is locked (02 §8)'),
      );
    }
    // ADR 2026-09-09d §4/§4a: nothing is dated before the books begin. An
    // authoring guard only — a reader never rejects, quarantines or hides an
    // earlier-dated entry that arrives by sync (§4b routes it to the Inbox).
    final start = await startDateOf(entry.bookId);
    if (start != null && entry.accountingDate.compareTo(start) < 0) {
      violations.add(
        Violation(
          ViolationKind.beforeBookStart,
          '${entry.accountingDate} is before the books begin ($start); '
          'the opening balance already includes it (ADR 2026-09-09d §4)',
        ),
      );
    }
    return violations;
  }

  /// Appends a validated, stamped entry: takes the HLC, authors the envelope
  /// and rebuilds. Validation has already happened — this never refuses.
  Future<Entry> _append(Entry stamped) async {
    final hlc = _tick();
    var entry = stamped.copyWith(hlc: hlc);
    await _author(
      bookId: entry.bookId,
      objectId: entry.id,
      objectType: 'entry',
      hlc: hlc,
      object: (seq) {
        entry = entry.copyWith(authorSeq: seq);
        return encodeEvent(entry);
      },
    );
    await _rebuild(entry.bookId);
    return entry;
  }

  /// Places the two halves of one inter-book action **atomically** (02 §6 🔒:
  /// one action, two envelopes sharing `refs.transfer_group`).
  ///
  /// Both halves are validated against **both** books' states before either is
  /// appended. The ledger is append-only (CLAUDE.md rule 2), so a half that
  /// has landed can never be taken back: if the receiving book would refuse
  /// its half — a locked period (02 §8), the ADR 2026-09-09d §4 start-date
  /// guard, any shape violation — the paying half must never have been
  /// written. There is no compensating entry here and there must not be one;
  /// a reversal would be a second, visible movement of money that never
  /// happened.
  ///
  /// A refusal throws one [PostRejected] carrying **every** violation of both
  /// halves, so the caller can say what is wrong with the action rather than
  /// with one side of it. The id it names is the refused half's — the paying
  /// half when that is the one at fault, otherwise the receiving half.
  Future<InterBookMovement> _postPair(
    TransferPair pair,
    String transferGroup,
  ) async {
    final from = _stamp(pair.from);
    final to = _stamp(pair.to);
    final fromViolations = await _violationsOf(from);
    final toViolations = await _violationsOf(to);
    if (fromViolations.isNotEmpty || toViolations.isNotEmpty) {
      throw PostRejected(fromViolations.isNotEmpty ? from.id : to.id, [
        ...fromViolations,
        ...toViolations,
      ]);
    }
    return InterBookMovement(
      from: await _append(from),
      to: await _append(to),
      transferGroup: transferGroup,
    );
  }

  /// Posts a draft this facade built, having first **authored its review
  /// flag** (02 §1.3 🔒, 02 §3 🔒, 03 §3.3 rule 5 🔒).
  ///
  /// This, and not [post], is the door every verb goes through: `post` is the
  /// raw primitive — a caller handing it a complete entry (the harness, a
  /// test, a future importer replaying someone else's payload) has already
  /// decided what the payload says, and this client must not overwrite a flag
  /// another author wrote.
  ///
  /// Exactly one policy read per post, so the limit recorded is *the limit in
  /// force at this entry's HLC*. A later change to the grant never re-flags
  /// what is already in the book.
  Future<Entry> _postDrafted(Entry draft) async => post(await _measured(draft));

  /// [draft] with `review_required` and `review_limit_paise` authored from the
  /// limit in force for its author in its book.
  ///
  /// Two entries are never measured:
  ///   * a `pending` one — 02 §1.3 🔒 makes `pending` *only* an advance
  ///     request awaiting approval, §7's deliberate exception where approval
  ///     itself moves the money, so a second flag on it would ask twice;
  ///   * a reversal — `Entry.reversal` (02 §5) fixes `review_required = false`
  ///     in the engine: a mirror restores a figure the book already carries,
  ///     and flagging it would mean a rejected entry's own reversal needs
  ///     reviewing before the month could close.
  Future<Entry> _measured(Entry draft) async {
    if (draft.status != EntryStatus.posted) return draft;
    if (draft.refs.reverses != null) return draft;
    final limit = await reviewPolicy.autoPostLimitPaise(
      bookId: draft.bookId,
      userId: draft.createdByUser,
    );
    if (limit == null) return draft;
    final paise = Paise(limit);
    return draft.copyWith(
      reviewRequired: draft.totalDebits > paise,
      reviewLimitPaise: paise,
    );
  }

  /// The review verdict for one inter-book pair (02 §6 🔒): each half
  /// measured against **its own book's** limit for this author, read once per
  /// book. [override] — the caller's `reviewRequiredIn` — may *add* a flag and
  /// never remove one, so an explicit request to review can only ever ask for
  /// more checking than the limit does.
  ///
  /// Both halves of a pair carry exactly one debit line of [paise]
  /// (`InterBook.transfer` / `InterBook.pocketExpense`), so the amount is the
  /// `totalDebits` every reader will re-check against the recorded limit.
  Future<({({bool from, bool to}) required, ({Paise? from, Paise? to}) limits})>
  _pairReview({
    required String fromBookId,
    required String toBookId,
    required int paise,
    required ({bool from, bool to}) override,
  }) async {
    final user = identity.userId;
    final from = await reviewPolicy.autoPostLimitPaise(
      bookId: fromBookId,
      userId: user,
    );
    final to = await reviewPolicy.autoPostLimitPaise(
      bookId: toBookId,
      userId: user,
    );
    final amount = Paise(paise);
    return (
      required: (
        from: override.from || (from != null && amount > Paise(from)),
        to: override.to || (to != null && amount > Paise(to)),
      ),
      limits: (
        from: from == null ? null : Paise(from),
        to: to == null ? null : Paise(to),
      ),
    );
  }

  Entry _draft({
    required String bookId,
    required EntryKind kind,
    required List<Line> lines,
    required LocalDate date,
    String? note,
    String? channel,
    String? partyId,
    String? advanceId,
    EntryStatus status = EntryStatus.posted,
    String? reviewApprover,
  }) => Entry(
    id: newId(),
    bookId: bookId,
    kind: kind,
    status: status,
    reviewRequired: false,
    accountingDate: date,
    lines: lines,
    note: note,
    partyId: partyId,
    advanceId: advanceId,
    reviewApprover: reviewApprover,
    createdByUser: identity.userId,
    createdByDevice: identity.deviceId,
    hlc: _clock,
    extra: channel == null ? const {} : {'channel': channel},
  );

  String? _partyOf(Account a) =>
      a.accountClass == AccountClass.party ? a.id : null;

  /// Verb 1 — *Money in* (02 §2): Dr [into] (cash/bank) · Cr [from]
  /// (income category or party).
  Future<Entry> moneyIn({
    required String bookId,
    required String into,
    required String from,
    required int paise,
    required LocalDate date,
    String? note,
    String? channel,
  }) async {
    final c = await chartOf(bookId);
    final fromA = c.account(from);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.moneyIn,
        lines: Verbs.moneyIn(
          into: c.account(into),
          from: fromA,
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        channel: channel,
        partyId: _partyOf(fromA),
      ),
    );
  }

  /// Verb 2 — *Money out*: Dr [forWhat] (expense category or party) ·
  /// Cr [from] (cash/bank).
  Future<Entry> moneyOut({
    required String bookId,
    required String from,
    required String forWhat,
    required int paise,
    required LocalDate date,
    String? note,
    String? channel,
  }) async {
    final c = await chartOf(bookId);
    final forA = c.account(forWhat);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.moneyOut,
        lines: Verbs.moneyOut(
          from: c.account(from),
          forWhat: forA,
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        channel: channel,
        partyId: _partyOf(forA),
      ),
    );
  }

  /// Verb 3 — *Gave on credit*: Dr [toWhom] (party) · Cr [gave] (money or
  /// income category).
  Future<Entry> gaveCredit({
    required String bookId,
    required String toWhom,
    required String gave,
    required int paise,
    required LocalDate date,
    String? note,
  }) async {
    final c = await chartOf(bookId);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.gaveCredit,
        lines: Verbs.gaveCredit(
          toWhom: c.account(toWhom),
          gave: c.account(gave),
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        partyId: toWhom,
      ),
    );
  }

  /// Verb 4 — *Took on credit*: Dr [took] (money or expense category) ·
  /// Cr [fromWhom] (party).
  Future<Entry> tookCredit({
    required String bookId,
    required String fromWhom,
    required String took,
    required int paise,
    required LocalDate date,
    String? note,
  }) async {
    final c = await chartOf(bookId);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.tookCredit,
        lines: Verbs.tookCredit(
          fromWhom: c.account(fromWhom),
          took: c.account(took),
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        partyId: fromWhom,
      ),
    );
  }

  /// Verb 5 — *Transfer* within a book: Dr [to] · Cr [from], two money
  /// accounts (or one *Due to/from*, 02 §6).
  Future<Entry> transfer({
    required String bookId,
    required String from,
    required String to,
    required int paise,
    required LocalDate date,
    String? note,
    String? channel,
  }) async {
    final c = await chartOf(bookId);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.transfer,
        lines: Verbs.transfer(
          from: c.account(from),
          to: c.account(to),
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        channel: channel,
      ),
    );
  }

  // ── advances (02 §7 🔒) ────────────────────────────────────────────────────
  // The deliberate exception to §3's post-then-review: here the approval
  // itself moves the money, so the request is authored `pending` and counts
  // nothing until an approver decides. Kinds follow the engine's reading
  // (verbs.dart ⚠️ SPEC): request and spend are `money_out`, a return is
  // `money_in`; balances never depend on kind.

  /// The advance request (02 §7): authored `pending` with the lines it will
  /// post — `Dr Advance – {member} · Cr money` — and **counted by nobody**
  /// until [approveAdvance]. Nothing leaves the drawer here.
  ///
  /// [purpose] is required by 02 §7 and is stored as the entry's note;
  /// [approver] is recorded as `review_approver` — who must act.
  Future<Entry> requestAdvance({
    required String bookId,
    required String advance,
    required String from,
    required int paise,
    required String purpose,
    required LocalDate date,
    String? approver,
  }) async {
    final text = purpose.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'an advance request needs a purpose (02 §7)',
      );
    }
    final c = await chartOf(bookId);
    final adv = c.account(advance);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.moneyOut,
        lines: Verbs.advanceRequest(
          advance: adv,
          from: c.account(from),
          amount: Paise(paise),
        ),
        date: date,
        note: text,
        advanceId: adv.id,
        status: EntryStatus.pending,
        reviewApprover: approver,
      ),
    );
  }

  /// The approval — the one place in this app where approving moves money
  /// (02 §7 🔒). Authors an `approval_decision` the projector folds onto the
  /// pending request, which counts it: cash leaves the drawer now, and
  /// `Advance – {member}` opens.
  ///
  /// Refused, authoring nothing, per [AdvanceRefusal]: an unknown entry, an
  /// entry that is not a pending request, one already decided (the approval
  /// moves the money exactly once), and a self-approval.
  ///
  /// ⚠️ SPEC: there is deliberately **no** auto-approval — not even for a
  /// requester who is the only member of the book. 02 §7 requires approval
  /// "always … regardless of limit", and 02 §7.2 item 1 🔒 (enforced by the
  /// projector, `ViolationKind.selfApproval`) means the requester may not be
  /// the approver, so a single-member book has no way to release its own
  /// request. Refusing is the conservative reading — it never writes an
  /// envelope every reader would quarantine — but it leaves that case without
  /// a path; reported to the owner in the lane report rather than invented
  /// here.
  Future<ApprovalDecision> approveAdvance(String entryId) async {
    _requireOpen();
    final row = await (db.select(
      db.entriesP,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (row == null) {
      throw AdvanceRefused(entryId, AdvanceRefusal.unknownEntry);
    }
    final state = await _stateOf(row.bookId);
    final p = state.entries[entryId];
    if (p == null || p.entry.status != EntryStatus.pending) {
      throw AdvanceRefused(entryId, AdvanceRefusal.notAPendingRequest);
    }
    if (p.status != EffectiveStatus.pending) {
      throw AdvanceRefused(entryId, AdvanceRefusal.alreadyDecided);
    }
    if (p.entry.createdByUser == identity.userId) {
      throw AdvanceRefused(entryId, AdvanceRefusal.selfApproval);
    }
    final decision = await authorApprovalDecision(
      (hlc, id) => ApprovalDecision(
        id: id,
        bookId: row.bookId,
        entryId: entryId,
        decision: Decision.approve,
        byUser: identity.userId,
        hlc: hlc,
      ),
    );
    await _rebuild(row.bookId);
    return decision;
  }

  /// Spending against an open advance (02 §7): `Dr expense-category ·
  /// Cr Advance – {member}`. Ordinary post-then-review — the money already
  /// left when the advance was approved.
  Future<Entry> spendAgainstAdvance({
    required String bookId,
    required String advance,
    required String forWhat,
    required int paise,
    required LocalDate date,
    String? note,
  }) async {
    final c = await chartOf(bookId);
    final adv = c.account(advance);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.moneyOut,
        lines: Verbs.advanceSpend(
          advance: adv,
          forWhat: c.account(forWhat),
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        advanceId: adv.id,
      ),
    );
  }

  /// Returning the remainder (02 §7): `Dr money · Cr Advance – {member}`.
  /// The advance closes when the balance reaches zero — nothing else to do.
  Future<Entry> returnAdvance({
    required String bookId,
    required String advance,
    required String into,
    required int paise,
    required LocalDate date,
    String? note,
  }) async {
    final c = await chartOf(bookId);
    final adv = c.account(advance);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.moneyIn,
        lines: Verbs.advanceReturn(
          advance: adv,
          into: c.account(into),
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        advanceId: adv.id,
      ),
    );
  }

  /// Verb 6, guided — *Opening balances* (02 §4): one `adjustment` per
  /// account against *Opening Balance*. [balances] maps account id → signed
  /// paise as the user answered by class: money = *balance today* (negative
  /// = overdraft); party = + *you will get* / − *you will give*; advance =
  /// held. Zero balances post nothing. The entries need not net to zero —
  /// Opening Balance absorbs the difference.
  ///
  /// [date] defaults to the book's start date (ADR 2026-09-09d §4): an opening
  /// balance describes the position on the day the books began, whenever the
  /// account happens to be added. Pass a later date only when that month is
  /// already locked — the 02 §8.1 pattern, the fix lands in the open period.
  Future<List<Entry>> openingBalances(
    String bookId, {
    required Map<String, int> balances,
    LocalDate? date,
  }) async {
    final when = date ?? await startDateOf(bookId) ?? today();
    final c = await chartOf(bookId);
    final opening = c
        .byClass(AccountClass.equitySystem)
        .firstWhere(
          (a) => a.systemRole == SystemRole.openingBalance,
          orElse: () =>
              throw StateError('book $bookId has no Opening Balance account'),
        );
    final out = <Entry>[];
    for (final MapEntry(key: accountId, value: paise) in balances.entries) {
      if (paise == 0) continue;
      final account = c.account(accountId);
      out.add(
        await _postDrafted(
          _draft(
            bookId: bookId,
            kind: EntryKind.adjustment,
            lines: Verbs.openingBalance(
              account: account,
              balance: Paise(paise),
              openingAccount: opening,
            ),
            date: when,
            partyId: _partyOf(account),
          ),
        ),
      );
    }
    return out;
  }

  // ── the review queue (02 §3 🔒) ────────────────────────────────────────────
  // The opposite of §7's advances: here the money already moved, so approval
  // clears a flag and moves nothing, and rejection posts the §5 mirror with
  // the reason. Both write exactly one `approval_decision` envelope through
  // [authorApprovalDecision] — the same path [approveAdvance] uses, so the
  // codec and the signature live in one place.

  /// Every entry of [bookId] still carrying an **open** review flag — the
  /// Inbox queue's one read (02 §3, 03 §3.3 rule 5 🔒, 07 §9 🔒).
  ///
  /// `review_state` is the projector's, folded from `approval_decision`
  /// envelopes; this reads it and decides nothing. Heads only (an amended-away
  /// entry is not what a reviewer should be deciding on), ordered by
  /// `(accounting_date, hlc, id)`.
  ///
  /// It does **not** filter the reader's own entries: that is 02 §7.2 item 1's
  /// rule and belongs to the queue above it, which is also where a book with
  /// one member raises nothing. [approveEntry] and [rejectEntry] refuse a
  /// self-decision in any case.
  Stream<List<FlaggedEntry>> watchOpenReviews(String bookId) {
    final q = db.customSelect(
      'SELECT e.id, e.kind, e.accounting_date, e.note, e.created_by_user, '
      'e.review_approver, e.hlc, l.account_id, l.amount_paise, l.line_index, '
      'a.name AS account_name '
      'FROM entries_p e '
      'JOIN entry_lines_p l ON l.entry_id = e.id '
      'LEFT JOIN accounts_p a ON a.id = l.account_id '
      "WHERE e.book_id = ? AND e.review_state = 'open' "
      'AND e.superseded_by IS NULL '
      'ORDER BY e.accounting_date, e.hlc, e.id, l.line_index',
      variables: [Variable.withString(bookId)],
      readsFrom: {db.entriesP, db.entryLinesP, db.accountsP},
    );
    return q.watch().map((rows) {
      final lines = <String, List<FlaggedLine>>{};
      final head = <String, QueryRow>{};
      final order = <String>[];
      for (final r in rows) {
        final id = r.read<String>('id');
        if (lines.putIfAbsent(id, () => []).isEmpty) {
          head[id] = r;
          order.add(id);
        }
        lines[id]!.add(
          FlaggedLine(
            accountId: r.read<String>('account_id'),
            accountName:
                r.readNullable<String>('account_name') ??
                r.read<String>('account_id'),
            amount: Paise(r.read<int>('amount_paise')),
          ),
        );
      }
      return [
        for (final id in order)
          () {
            final r = head[id]!;
            return FlaggedEntry(
              entryId: id,
              bookId: bookId,
              kind: EntryKind.parse(r.read<String>('kind')),
              accountingDate: LocalDate.parse(
                r.read<String>('accounting_date'),
              ),
              lines: List.unmodifiable(lines[id]!),
              hlc: r.read<int>('hlc'),
              note: r.readNullable<String>('note'),
              createdByUser: r.readNullable<String>('created_by_user'),
              approver: r.readNullable<String>('review_approver'),
            );
          }(),
      ];
    });
  }

  /// Authors one `approval_decision` envelope (03 §3.3.5) and nothing else.
  ///
  /// [build] is handed this device's next HLC and a fresh id, so the decision
  /// is stamped in the same tick the envelope is sealed in. Authoring applies
  /// nothing: the fold is the projector's, in `(hlc, envelope_id)` order with
  /// the last one winning, so the caller rebuilds and reads the answer back.
  ///
  /// The one write path for every decision this app makes — [approveAdvance]
  /// (02 §7, where the approval moves the money), [approveEntry] and
  /// [rejectEntry] (02 §3, where it never does).
  Future<ApprovalDecision> authorApprovalDecision(
    ApprovalDecision Function(Hlc hlc, String id) build,
  ) async {
    _requireOpen();
    final hlc = _tick();
    final decision = build(hlc, newId());
    await _author(
      bookId: decision.bookId,
      objectId: decision.id,
      objectType: 'approval_decision',
      hlc: hlc,
      object: (_) => encodeEvent(decision),
    );
    return decision;
  }

  /// **Approve** — clears the flag (02 §3 🔒). Moves no money: the entry
  /// posted and counted the moment it was saved, and every balance already
  /// includes it.
  ///
  /// Validate → refuse typed → author exactly one decision → read the head
  /// back out of the rebuilt projection. Refused per [ReviewRefusal],
  /// authoring nothing.
  Future<ReviewDecided> approveEntry(String entryId) async {
    final (row, _) = await _openFlag(entryId);
    final decision = await authorApprovalDecision(
      (hlc, id) => ApprovalDecision(
        id: id,
        bookId: row.bookId,
        entryId: entryId,
        decision: Decision.approve,
        byUser: identity.userId,
        hlc: hlc,
      ),
    );
    await _rebuild(row.bookId);
    return _decidedFrom(entryId, decision);
  }

  /// **Reject** — one signed decision carrying [reason], plus the auto-posted
  /// mirror reversal of 02 §5 (02 §3 🔒). The original and the reversal both
  /// stay in history; the balance returns to where it was before the entry.
  ///
  /// A blank [reason] is a programming error, not a user-facing state: the
  /// rejection envelope carries it and `entries_p.review_reason` requires it
  /// (03 §3.2), so the screens collect it before calling.
  ///
  /// The mirror is validated **before** anything is authored. The ledger is
  /// append-only (CLAUDE.md rule 2): a decision authored beside a reversal
  /// that then refused would leave a flag cleared over money that never came
  /// back, and no envelope can be taken back. Nothing between the two writes
  /// can invalidate the mirror either — a decision changes a flag, never a
  /// balance, a period or a head.
  Future<ReviewDecided> rejectEntry(
    String entryId, {
    required String reason,
  }) async {
    final text = reason.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'a rejection records why (02 §3)',
      );
    }
    final (row, projected) = await _openFlag(entryId);
    if (projected.reversedBy != null) {
      throw ReviewRefused(entryId, ReviewRefusal.alreadyReversed);
    }
    final mirror = _stamp(
      projected.entry.reversal(
        newId: newId(),
        hlc: _clock,
        accountingDate: today(),
        createdByUser: identity.userId,
        createdByDevice: identity.deviceId,
        note: text,
      ),
    );
    final violations = await _violationsOf(mirror);
    if (violations.isNotEmpty) {
      throw ReviewRefused(entryId, ReviewRefusal.reversalRefused, violations);
    }
    final decision = await authorApprovalDecision(
      (hlc, id) => ApprovalDecision(
        id: id,
        bookId: row.bookId,
        entryId: entryId,
        decision: Decision.reject,
        byUser: identity.userId,
        hlc: hlc,
        reason: text,
      ),
    );
    // Appends and rebuilds — the projection the result is read from already
    // holds both envelopes.
    final reversal = await _append(mirror);
    return _decidedFrom(entryId, decision, reversal: reversal);
  }

  /// The entry behind an **open** flag, or a typed refusal that authors
  /// nothing. The order of the checks is the order the refusals should be
  /// read in: an advance request is never this queue's business, and a
  /// self-decision is refused before anything else is judged about the flag.
  Future<(EntriesPData, ProjectedEntry)> _openFlag(String entryId) async {
    _requireOpen();
    final row = await (db.select(
      db.entriesP,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (row == null) throw ReviewRefused(entryId, ReviewRefusal.unknownEntry);
    final state = await _stateOf(row.bookId);
    final projected = state.entries[entryId];
    if (projected == null) {
      throw ReviewRefused(entryId, ReviewRefusal.unknownEntry);
    }
    if (projected.entry.status == EntryStatus.pending) {
      // 02 §7's queue, where approving *moves* the money — [approveAdvance]'s
      // path and never this one (02 §1.3 🔒: `pending` is only an advance).
      throw ReviewRefused(entryId, ReviewRefusal.pendingAdvance);
    }
    if (projected.entry.createdByUser == identity.userId) {
      throw ReviewRefused(entryId, ReviewRefusal.selfApproval);
    }
    switch (projected.reviewState) {
      case ReviewState.none:
        throw ReviewRefused(entryId, ReviewRefusal.notFlagged);
      case ReviewState.approved:
      case ReviewState.rejected:
        throw ReviewRefused(entryId, ReviewRefusal.alreadyDecided);
      case ReviewState.open:
        break;
    }
    if (projected.supersededBy != null || state.headOf(entryId) != entryId) {
      throw ReviewRefused(entryId, ReviewRefusal.notHead);
    }
    return (row, projected);
  }

  /// The head as the **rebuilt** projection now reads it (03 §3.2
  /// `review_state` / `review_decided_hlc` / `review_reason`) — never what
  /// this device assumed it wrote. A decision from another device with a
  /// later `(hlc, id)` wins the fold, and this is where that shows.
  Future<ReviewDecided> _decidedFrom(
    String entryId,
    ApprovalDecision decision, {
    Entry? reversal,
  }) async {
    final row = await (db.select(
      db.entriesP,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    return ReviewDecided(
      decision: decision,
      reviewState: row?.reviewState ?? 'none',
      decidedHlc: row?.reviewDecidedHlc,
      reason: row?.reviewReason,
      reversal: reversal,
    );
  }

  // ── corrections (02 §5) ───────────────────────────────────────────────────

  /// Amends the head of an open-period entry: a new envelope, kind unchanged,
  /// `refs.amends = original`, complete replacement payload; fields not
  /// passed — including ones this client does not understand — are copied
  /// (03 §3.3.4). Rejects a non-head target (`amendNotHead`) or a locked
  /// period (`amendInLockedPeriod` → offer *Fix an old entry* = [reverse]).
  Future<Entry> amend(
    String entryId, {
    List<Line>? lines,
    LocalDate? accountingDate,
    String? note,
    String? partyId,
  }) async {
    _requireOpen();
    final (original, state) = await _projected(entryId);
    final violations = <Violation>[];
    if (original.supersededBy != null || state.headOf(entryId) != entryId) {
      violations.add(
        Violation(ViolationKind.amendNotHead, '$entryId is not the head'),
      );
    }
    final period = original.entry.accountingDate.yearMonth;
    if (state.periods.currentStatus(period) == PeriodStatus.locked &&
        !await _isTrayRedate(
          entryId,
          state,
          accountingDate: accountingDate,
          lines: lines,
          from: original.entry.accountingDate,
        )) {
      violations.add(
        Violation(
          ViolationKind.amendInLockedPeriod,
          '$period is locked — reverse instead (02 §5)',
        ),
      );
    }
    if (violations.isNotEmpty) throw PostRejected(entryId, violations);
    // Re-measured against the limit in force at the amendment's own HLC, not
    // the flag the original carried (02 §1.3 🔒, 03 §3.3 rule 5 🔒). An
    // amendment is a complete replacement payload, so copying the old boolean
    // would let a small approved entry be raised over the limit by amending
    // it — the one way the flag could be skipped while the money still moved.
    return _postDrafted(
      original.entry.amendWith(
        newId: newId(),
        hlc: _clock,
        lines: lines,
        accountingDate: accountingDate,
        note: note,
        partyId: partyId,
        createdByUser: identity.userId,
        createdByDevice: identity.deviceId,
      ),
    );
  }

  /// The **one** amendment 02 §5 allows against a locked period: the closer
  /// re-dating a late arrival into the open period (02 §8 🔒, *default, one
  /// tap*). Everything else in a locked month is still `amendInLockedPeriod`
  /// and must go through [reverse].
  ///
  /// The four conditions are the projector's own, restated here so the facade
  /// never authors an amendment `core_ledger` would then quarantine (see
  /// `_isRedate` in `core_ledger/lib/src/projection.dart`):
  ///
  ///  1. the head's projected status is `in_tray` — the closer's tray, the
  ///     state ADR 2026-09-05e §10 named. This is the half the projector
  ///     cannot see (arrival order is client-local), and the half that keeps
  ///     the carve-out from becoming a hole in the lock;
  ///  2. the date actually moves;
  ///  3. it moves into a period that is **open**;
  ///  4. the lines are untouched — a re-date changes when, never what. An
  ///     amendment that also edits the amount is a rewrite of a certified
  ///     month and stays refused.
  Future<bool> _isTrayRedate(
    String entryId,
    LedgerState state, {
    required LocalDate? accountingDate,
    required List<Line>? lines,
    required LocalDate from,
  }) async {
    if (accountingDate == null || accountingDate == from) return false;
    if (lines != null) return false;
    if (state.periods.currentStatus(accountingDate.yearMonth) ==
        PeriodStatus.locked) {
      return false;
    }
    return _isInTray(entryId);
  }

  /// Reverses an entry (02 §5): the auto-built mirror — every line negated —
  /// dated [date] in the open period, `refs.reverses = original`, posted,
  /// never flagged. Both stay in history; the original shows as `void`.
  Future<Entry> reverse(
    String entryId, {
    required LocalDate date,
    String? note,
  }) async {
    _requireOpen();
    final (original, state) = await _projected(entryId);
    if (original.reversedBy != null) {
      throw PostRejected(entryId, [
        Violation(
          ViolationKind.alreadyReversed,
          '$entryId is already reversed by ${original.reversedBy}',
        ),
      ]);
    }
    if (state.headOf(entryId) != entryId) {
      throw PostRejected(entryId, [
        Violation(
          ViolationKind.amendNotHead,
          '$entryId was amended — reverse the head ${state.headOf(entryId)}',
        ),
      ]);
    }
    return post(
      original.entry.reversal(
        newId: newId(),
        hlc: _clock,
        accountingDate: date,
        createdByUser: identity.userId,
        createdByDevice: identity.deviceId,
        note: note,
      ),
    );
  }

  Future<(ProjectedEntry, LedgerState)> _projected(String entryId) async {
    final row = await (db.select(
      db.entriesP,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (row == null) throw ArgumentError.value(entryId, 'entryId', 'unknown');
    final state = await _stateOf(row.bookId);
    final p = state.entries[entryId];
    if (p == null) throw ArgumentError.value(entryId, 'entryId', 'unknown');
    return (p, state);
  }

  // ── partner settlement (02 §7.1 🔒) ───────────────────────────────────────

  /// Settlement route 1 (02 §7.1 🔒): the business pays a partner out —
  /// `Dr Partner Current · Cr {money account}`.
  ///
  /// The same posting as an owner's takeout (`Verbs.partnerDrawing`), because
  /// it *is* the same movement: the business owes them less and holds less
  /// money. What differs is the reason, which the screen says and the ledger
  /// does not bend to (02 §10).
  Future<Entry> partnerPayOut({
    required String bookId,
    required String partnerAccountId,
    required String fromAccountId,
    required int paise,
    LocalDate? date,
  }) async {
    _requireOpen();
    final chart = await chartOf(bookId);
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.moneyOut,
        lines: Verbs.partnerDrawing(
          partner: chart.account(partnerAccountId),
          from: chart.account(fromAccountId),
          amount: Paise(paise),
        ),
        date: date ?? today(),
      ),
    );
  }

  /// Settlement route 2 (02 §7.1 🔒): partner-to-partner, settled outside the
  /// business — `Dr {over-funded partner} · Cr {under-funded partner}`. The
  /// under-funded partner pays cash outside the books and buys part of the
  /// other's claim; no money account of the business moves.
  ///
  /// ⚠️ SPEC (🔒, for the owner): the engine has **no verb and no admitting
  /// kind** for this posting. `Verbs` builds the other two partner events and
  /// not this one, and `checkShape` (02 §1.4 rule 7, ADR 2026-09-05e §6)
  /// admits `Dr partner · Cr partner` under no `EntryKind`: `money_out` wants
  /// money on the credit side, `gave_credit` wants money or income there, and
  /// `adjustment` wants exactly one `equity_system` account, of which this has
  /// none. So this posts the 🔒 lines 02 §7.1 names, as `adjustment` — the
  /// kind its sibling, profit distribution, already uses — and today `post`
  /// refuses it with a `shapeViolation` **before authoring anything**. The
  /// caller sees the engine's own typed refusal rather than a sentence this
  /// layer invented. Fixing it is an engine ruling (a `Verbs.partnerSettlement`
  /// builder plus a shape rule, or 02 naming the kind), not a change this lane
  /// may make; reported in the lane report.
  Future<Entry> settleBetweenPartners({
    required String bookId,
    required String fromPartnerAccountId,
    required String toPartnerAccountId,
    required int paise,
    LocalDate? date,
  }) async {
    _requireOpen();
    if (paise <= 0) {
      throw ArgumentError.value(paise, 'paise', 'must be positive');
    }
    if (fromPartnerAccountId == toPartnerAccountId) {
      throw ArgumentError.value(
        toPartnerAccountId,
        'toPartnerAccountId',
        'a settlement needs two different partners',
      );
    }
    final chart = await chartOf(bookId);
    final from = chart.account(fromPartnerAccountId);
    final to = chart.account(toPartnerAccountId);
    for (final a in [from, to]) {
      if (a.accountClass != AccountClass.partner) {
        throw ArgumentError.value(
          a.id,
          'partnerAccountId',
          'not a Partner Current A/c of $bookId',
        );
      }
    }
    return _postDrafted(
      _draft(
        bookId: bookId,
        kind: EntryKind.adjustment,
        lines: [
          Line(accountId: from.id, amount: Paise(paise)),
          Line(accountId: to.id, amount: Paise(-paise)),
        ],
        date: date ?? today(),
      ),
    );
  }

  // ── profit distribution (02 §7.1 🔒, 13 §3.2 row S14.1) ───────────────────

  /// The book's structural terms read end to end (ADR 2026-09-14b §2, §5):
  /// the deed, the owner-set versions, the authorised `business_setting`
  /// records, and the settings **in force**.
  ///
  /// This is the only path a distributing caller may read a ratio through —
  /// `BookConfig.partnerShares` is the *deed's* value and is wrong the moment
  /// a ratio change has quorum (ADR 2026-09-14b §2, §6). Recompute does not
  /// hand these envelopes out (`business_setting` and `structural_approval`
  /// are not projector events, ADR 2026-09-14b §5), so they are opened here
  /// from the mirror, in `(hlc, envelope_id)` order, and handed to
  /// `readStructuralState` unjudged: quarantined, unverified and corrupt rows
  /// are skipped exactly as Recompute skips them, and every policy question is
  /// the reader's.
  Future<StructuralReading> structuralStateOf(String bookId) async {
    _requireOpen();
    final rows =
        await (db.select(db.envelopesLocal)
              ..where(
                (t) =>
                    t.bookId.equals(bookId) &
                    t.objectType.isIn(const [
                      'book_config',
                      'structural_approval',
                      'business_setting',
                    ]),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.hlc),
                (t) => OrderingTerm.asc(t.envelopeId),
              ]))
            .get();
    final configVersions = <BookConfigVersion>[];
    final events = <StructuralEvent>[];
    final settings = <BusinessSetting>[];
    for (final r in rows) {
      if (r.quarantined == 1 || r.verified != 1) continue;
      final read = mirror.readBlobOfRow(r);
      if (read is! BlobOk) continue;
      final Map<String, Object?> json;
      try {
        json = recompute.opener.open(
          read.bytes,
          BlobHeader(
            envelopeId: r.envelopeId,
            bookId: r.bookId,
            objectId: r.objectId,
            objectType: r.objectType,
            keyVersion: r.keyVersion,
            authorDevice: r.authorDevice,
            hlc: r.hlc,
          ),
        );
      } on Object {
        // Recompute quarantines a payload it cannot open; this read never
        // writes, so it leaves that to the rebuild and simply cannot see it.
        continue;
      }
      try {
        switch (r.objectType) {
          case 'book_config':
            configVersions.add(
              BookConfigVersion(
                envelopeId: r.envelopeId,
                hlc: Hlc(r.hlc),
                config: BookConfig.fromJson(json),
              ),
            );
          case 'business_setting':
            settings.add(BusinessSetting.fromJson(json));
          case 'structural_approval':
            final ev = decodeStructuralEvent(
              json,
              authorDevice: r.authorDevice,
              authorSeq: r.authorSeq,
            );
            if (ev != null) events.add(ev);
        }
      } on FormatException {
        continue;
      }
    }
    return readStructuralState(
      bookId: bookId,
      configVersions: configVersions,
      accounts: (await chartOf(bookId)).accounts,
      structuralEvents: events,
      businessSettings: settings,
      asOfMs: now().millisecondsSinceEpoch,
    );
  }

  /// Authors one `structural_approval` envelope — the initiation, approval,
  /// veto or lapse of 02 §7.2.1 🔒 (ADR 2026-09-05e §11: one object type, a
  /// `phase` field).
  ///
  /// [build] is handed this device's next HLC and a fresh id so the event is
  /// stamped once, in the same tick the envelope is sealed in. Authoring an
  /// envelope **applies nothing**: quorum is counted by `evaluateStructural`
  /// over the records, every time, and never cached (02 §7.2.1 🔒 *Nothing is
  /// applied early*).
  ///
  /// This is the authoring primitive only. Deciding *when* an approval may be
  /// signed, and writing the `business_setting` record that a reached quorum
  /// authorises, is the Inbox side's — see [authorBusinessSetting].
  Future<T> authorStructural<T extends StructuralEvent>(
    T Function(Hlc hlc, String id) build,
  ) async {
    _requireOpen();
    final hlc = _tick();
    final event = build(hlc, newId());
    await _author(
      bookId: event.bookId,
      objectId: event.id,
      objectType: 'structural_approval',
      hlc: hlc,
      object: (_) => encodeStructuralEvent(event),
    );
    return event;
  }

  /// Authors the dated `business_setting` record of **one applied structural
  /// change** (ADR 2026-09-14b §2, §5) — a new object per change, never
  /// amended, naming the `structural_approval` request whose quorum
  /// authorised it.
  ///
  /// It does not judge the quorum: `verifyBusinessSettings` re-checks on every
  /// read that [requestId] names an approved request whose payload equals
  /// [settings], and quarantines the record when it does not (ADR
  /// 2026-09-14b §5). Callers that reach a quorum write the record; readers
  /// decide whether it counts.
  Future<BusinessSetting> authorBusinessSetting({
    required String bookId,
    required String requestId,
    required Map<String, Object?> settings,
  }) async {
    _requireOpen();
    final hlc = _tick();
    final record = BusinessSetting(
      id: newId(),
      bookId: bookId,
      hlc: hlc,
      byUser: identity.userId,
      requestId: requestId,
      settings: Map<String, Object?>.unmodifiable(settings),
    );
    await _author(
      bookId: bookId,
      objectId: record.id,
      objectType: 'business_setting',
      hlc: hlc,
      object: (_) => record.toJson(),
    );
    return record;
  }

  /// Everything S14.1 shows before anything is posted (02 §7.1 🔒, 13 §3.2
  /// row S14.1).
  ///
  /// [from] / [to] bound the **interest** period — the 122-day season of
  /// 02 §7.1's worked illustration — and default to the open FY's first day
  /// and today. Net profit is **not** period-scoped: ADR 2026-09-05e §8 makes
  /// it the open FY's income − expense − distributions already posted in that
  /// FY, whatever window the interest covers, and `netProfit` computes it.
  ///
  /// This method divides nothing. The ratio is the one in force at this order
  /// point (ADR 2026-09-14b §6), interest is `interestOnCapital`'s, and each
  /// owner's share is read back off the lines `Verbs.profitDistribution`
  /// built — so the 02 §7.1 🔒 rounding rule and its remainder stay the
  /// engine's, on every device.
  Future<DistributionPreview> distributionPreview(
    String bookId, {
    LocalDate? from,
    LocalDate? to,
  }) async {
    _requireOpen();
    final report = _last[bookId] ?? await _rebuild(bookId);
    final chart = report.chart;
    final state = report.state;
    final config = report.config;
    final end = to ?? today();
    final fy = FinancialYear.of(end, startMonth: config?.fyStartMonth ?? 4);
    final start = from ?? fy.firstDay;
    if (end.isBefore(start)) {
      throw ArgumentError.value(to, 'to', 'the period ends before it begins');
    }
    if (!fy.contains(start) || !fy.contains(end)) {
      throw ArgumentError.value(
        from,
        'from',
        'the period must lie inside the financial year it distributes',
      );
    }

    final reading = await structuralStateOf(bookId);
    final inForce = reading.inForce;
    final ratio = reading.partnerShares;
    final interestTerms = interestOnCapitalInForce(inForce);
    final ownerSetVersion = reading.owners.inForce?.version ?? 1;
    final partnerAccounts = chart.byClass(AccountClass.partner)
      ..sort((a, b) => a.createdOrder.compareTo(b.createdOrder));
    // 02 §7.2.1 🔒: a book whose owner set cannot be derived is read at the
    // strictest quorum there is — every owner signs. A quorum of one is
    // claimed only when the book positively has one owner.
    final approvalsRequired =
        reading.owners.inForce?.required ??
        (partnerAccounts.isEmpty ? 1 : partnerAccounts.length);

    DistributionPreview refuse(DistributionRefusal refusal) =>
        DistributionPreview(
          bookId: bookId,
          financialYear: fy,
          from: start,
          to: end,
          netProfit: netProfit(state, chart, fy),
          shares: const [],
          interest: const {},
          lines: const [],
          headroom: distributionHeadroom(
            state,
            chart,
            fy: fy,
            proposed: Paise.zero,
          ).headroom,
          excess: Paise.zero,
          interestEnabled: interestTerms.enabled,
          rateBasisPoints: interestTerms.rateBasisPoints,
          ownerSetVersion: ownerSetVersion,
          approvalsRequired: approvalsRequired,
          refusal: refusal,
        );

    if (config?.ownership != BookOwnership.shared) {
      return refuse(DistributionRefusal.notShared);
    }
    if (reading.quarantined.isNotEmpty) {
      return refuse(DistributionRefusal.termsUnverified);
    }
    if (partnerAccounts.isEmpty) {
      return refuse(DistributionRefusal.noPartnerAccounts);
    }
    if (ratio.isEmpty) return refuse(DistributionRefusal.ratioNotRecorded);
    // Every owner is in the ratio and the ratio names nobody else: 02 §7.1 🔒
    // divides among *the* owners, and quietly dropping one would be a split
    // nobody agreed to.
    final named = partnerAccounts.map((a) => a.id).toSet();
    if (named.length != ratio.length || !named.containsAll(ratio.keys)) {
      return refuse(DistributionRefusal.ratioIncomplete);
    }
    final profitDistributed = _systemAccount(
      chart,
      SystemRole.profitDistributed,
    );
    if (profitDistributed == null) {
      return refuse(DistributionRefusal.noProfitDistributedAccount);
    }

    final partners = [
      for (final a in partnerAccounts)
        PartnerShare(account: a, ratio: ratio[a.id]!),
    ];
    final interest = interestTerms.enabled
        ? interestOnCapital(
            state,
            chart,
            partners: partners,
            from: start,
            to: end,
            rateBasisPoints: interestTerms.rateBasisPoints,
          )
        : const <String, Paise>{};
    final net = netProfit(state, chart, fy);
    // ⚠️ SPEC (02 §7.1, for the 02 owner): `Verbs.profitDistribution` refuses a
    // zero [netProfit] outright, so a year that broke exactly even cannot be
    // distributed even when interest on capital is owed on it — the interest
    // would have to post as a pure loss share. 02 §7.1 covers *interest above
    // profit* but not *profit exactly zero*, so the conservative reading is
    // taken: refuse, and say there is nothing to distribute. Lane report.
    if (net.isZero) return refuse(DistributionRefusal.nothingToDistribute);

    final lines = Verbs.profitDistribution(
      profitDistributed: profitDistributed,
      partners: partners,
      netProfit: net,
      interest: interest,
    );
    // Read back, never recomputed: whatever the engine put on the line is what
    // the owner sees and what will post (02 §7.1 🔒 rounding rule).
    Paise tagged(String accountId, String tag) {
      for (final l in lines) {
        if (l.accountId == accountId && l.tag == tag) return -l.amount;
      }
      return Paise.zero;
    }

    final ceiling = distributionHeadroom(state, chart, fy: fy, proposed: net);
    return DistributionPreview(
      bookId: bookId,
      financialYear: fy,
      from: start,
      to: end,
      netProfit: net,
      shares: [
        for (final a in partnerAccounts)
          DistributionShare(
            accountId: a.id,
            name: a.name,
            ratioWeight: ratio[a.id]!,
            interest: tagged(a.id, 'interest'),
            share: tagged(a.id, 'share'),
          ),
      ],
      interest: interest,
      lines: lines,
      headroom: ceiling.headroom,
      excess: ceiling.excess,
      interestEnabled: interestTerms.enabled,
      rateBasisPoints: interestTerms.rateBasisPoints,
      ownerSetVersion: ownerSetVersion,
      approvalsRequired: approvalsRequired,
      refusal: ceiling.excess.isZero ? null : DistributionRefusal.ceiling,
    );
  }

  /// Distributes, or proposes to (02 §7.1 🔒, §7.2.1 🔒).
  ///
  /// **Quorum of one** — a single-owner book, where 02 §7.2.1 says the concept
  /// is invisible — posts the one multi-line entry now. **Anything else**
  /// authors one signed `structural_request` envelope for
  /// [StructuralAction.profitDistribution] carrying the lines, and applies
  /// **nothing**: 02 §7.2.1 🔒 *Nothing is applied early*, and counting the
  /// signed approvals is the Inbox side's job, not this facade's.
  ///
  /// A refusal throws [DistributionRefused] with nothing authored — including
  /// the ceiling of ADR 2026-09-05e §8, which carries how far over it is.
  Future<DistributionOutcome> proposeDistribution(
    String bookId, {
    LocalDate? from,
    LocalDate? to,
    LocalDate? date,
  }) async {
    final preview = await distributionPreview(bookId, from: from, to: to);
    final refusal = preview.refusal;
    if (refusal != null) {
      throw DistributionRefused(bookId, refusal, excess: preview.excess);
    }
    final when = date ?? preview.to;
    if (preview.quorumOfOne) {
      return DistributionPosted(
        await _postDrafted(
          _draft(
            bookId: bookId,
            // 02 §2 verb 6: an appropriation is a guided adjustment — exactly
            // one `equity_system` account, which is Profit Distributed.
            kind: EntryKind.adjustment,
            lines: preview.lines,
            date: when,
          ),
        ),
      );
    }
    // Checked before a single byte is authored (02 §7.2.1 🔒): the engine
    // rules on the request, this facade only carries the verdict.
    final closedYears = (_last[bookId] ?? await _rebuild(bookId))
        .state
        .years
        .keys
        .toList();
    final engineRefusal = checkStructuralRequest(
      StructuralRequest(
        id: '',
        bookId: bookId,
        hlc: const Hlc(0),
        action: StructuralAction.profitDistribution,
        byUser: identity.userId,
        ownerSetVersion: preview.ownerSetVersion,
      ),
      closedYears: closedYears,
    );
    if (engineRefusal != null) {
      throw DistributionRefused(
        bookId,
        DistributionRefusal.structural,
        structural: engineRefusal,
      );
    }
    // Authored, not applied — 02 §7.2.1 🔒. A `structural_approval` is not a
    // projector event (ADR 2026-09-14b §5), so no projected row changes and
    // the golden content hash is untouched by construction.
    return DistributionProposed(
      await authorStructural(
        (hlc, id) => StructuralRequest(
          id: id,
          bookId: bookId,
          hlc: hlc,
          action: StructuralAction.profitDistribution,
          byUser: identity.userId,
          ownerSetVersion: preview.ownerSetVersion,
          payload: distributionPayload(preview, accountingDate: when),
        ),
      ),
    );
  }

  /// The payload a [StructuralAction.profitDistribution] request carries: the
  /// period, the FY, the figure and **the lines themselves**, so every owner's
  /// device can re-derive the same entry from its own copy of the ledger and
  /// compare it to what they are being asked to approve, rather than trusting
  /// the initiator's arithmetic (02 §7.2.1 🔒 *a distinct card stating exactly
  /// what will change*).
  static Map<String, Object?> distributionPayload(
    DistributionPreview preview, {
    required LocalDate accountingDate,
  }) => {
    'from': preview.from.toIso(),
    'to': preview.to.toIso(),
    'accounting_date': accountingDate.toIso(),
    'fy_start_year': preview.financialYear.startYear,
    'fy_start_month': preview.financialYear.startMonth,
    'net_profit_paise': preview.netProfit.raw,
    if (preview.interest.isNotEmpty)
      'interest_paise': {
        for (final e in preview.interest.entries) e.key: e.value.raw,
      },
    'lines': [for (final l in preview.lines) l.toJson()],
  };

  // ── cash counts (02 §8.2) ─────────────────────────────────────────────────

  /// Everything the S5.5 sheet and the S4 statement header draw about one
  /// countable account (02 §8.2 🔒). One read, one object: the figures on
  /// screen cannot drift apart while the user is counting.
  Future<CashCountReading> cashCountReading(String accountId) async {
    _requireOpen();
    final bookId = await _bookOfAccount(accountId);
    final chart = await chartOf(bookId);
    final account = chart.account(accountId);
    if (!account.isMoney ||
        (account.subtype != MoneySubtype.cash &&
            account.subtype != MoneySubtype.cashCollection)) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'only cash and collection accounts are counted (02 §8.2)',
      );
    }
    final state = await _stateOf(bookId);
    return CashCountReading(
      bookId: bookId,
      bookType: await _bookType(bookId),
      account: account,
      bookBalance: state.balances[accountId],
      lastCount: state.lastCount[accountId],
      incomeAccounts: chart.byClass(AccountClass.categoryIncome),
    );
  }

  /// The latest count of [accountId] — the *Last counted 27 Aug · 20×500 …*
  /// line of the A/C statement header (02 §8.2), or null when it has never
  /// been counted.
  Future<CashCount?> lastCashCount(String accountId) async {
    _requireOpen();
    final bookId = await _bookOfAccount(accountId);
    return (await _stateOf(bookId)).lastCount[accountId];
  }

  /// Records one cash count and posts **exactly** what the engine says it
  /// means (02 §8.2 🔒).
  ///
  /// The count is its own `cash_count` envelope — a memo that never moves
  /// money. What it *leads to* is [resolveCount]'s decision, carried back
  /// unchanged: nothing at all (`cash`, counted equals the book: the account
  /// is *verified on {date}*), one guided adjustment (`Dr/Cr Cash · Cr/Dr
  /// Adjustments`, the count attached as evidence), or one recognition of
  /// income (`cash_collection`: `Dr {collection a/c} · Cr {chosen income
  /// a/c}` for the full counted amount). Counted collection cash **stays on
  /// the collection account** — depositing it later is an ordinary Transfer,
  /// and a collection account is never a spending source (02 §8.2 🔒).
  ///
  /// [validateCount] runs first: a refusal throws [CountRejected] and appends
  /// nothing. The entry is posted before the count is authored, so a posting
  /// the ledger refuses ([PostRejected] — a locked month, §8) leaves **no**
  /// count either: a recorded count whose adjustment never landed would be a
  /// balance silently changed without an entry, which 02 §8.2 🔒 forbids.
  ///
  /// The book's `Adjustments A/c` is created on first use, like the §6 Due
  /// to/from pair; [adjustmentsName] names it then and is ignored afterwards.
  Future<RecordedCashCount> recordCashCount({
    required String accountId,
    required Paise counted,
    required LocalDate date,
    DenominationSheet? sheet,
    String? countedBy,
    String? witness,
    String? incomeAccountId,
    String adjustmentsName = 'Adjustments',
  }) async {
    _requireOpen();
    final bookId = await _bookOfAccount(accountId);
    final chart = await chartOf(bookId);
    final account = chart.account(accountId);
    final draft = CashCount(
      id: newId(),
      bookId: bookId,
      accountId: accountId,
      date: date,
      counted: counted,
      // Stamped when the envelope is authored, below; the outcome does not
      // depend on it, so validating and resolving may use the draft.
      hlc: const Hlc(0),
      sheet: sheet,
      countedBy: (countedBy ?? '').isEmpty ? null : countedBy,
      witness: (witness ?? '').isEmpty ? null : witness,
    );
    final violations = validateCount(
      draft,
      bookType: await _bookType(bookId),
      account: account,
    );
    if (violations.isNotEmpty) throw CountRejected(accountId, violations);

    final state = await _stateOf(bookId);
    final income = incomeAccountId == null
        ? null
        : chart.account(incomeAccountId);
    var adjustments = _systemAccount(chart, SystemRole.adjustments);
    final needsAdjustmentsAccount =
        adjustments == null && !account.isCollection;
    if (needsAdjustmentsAccount) {
      // Minted, not yet authored: `resolveCount`'s lines must already name the
      // account, but a count that *agrees* with the books posts nothing and
      // must not leave a new account behind either. The envelope is authored
      // below, only when the engine actually returns an adjustment — which
      // keeps the decision the engine's and this method's hands clean of it.
      adjustments = Account(
        id: newId(),
        bookId: bookId,
        name: adjustmentsName,
        accountClass: AccountClass.equitySystem,
        systemRole: SystemRole.adjustments,
        createdOrder: chart.accounts.length,
      );
    }
    final outcome = resolveCount(
      draft,
      account: account,
      bookBalance: state.balances[accountId],
      // In collect mode the engine posts `Dr collection · Cr income` and never
      // reads this slot — the Adjustments A/c is created on the first
      // *verification* count, so there is nothing truthful to put here. The
      // account being counted stands in it: unreachable, and a reachable use
      // would be refused loudly by `Verbs.cashCountDifference`, which insists
      // on the adjustments role, rather than posting to the wrong account.
      adjustmentsAccount: adjustments ?? account,
      incomeAccount: income,
    );

    Entry? entry;
    if (outcome.lines.isNotEmpty) {
      if (needsAdjustmentsAccount && outcome is CountAdjustment) {
        await addAccount(
          bookId,
          id: adjustments!.id,
          name: adjustmentsName,
          accountClass: AccountClass.equitySystem,
          systemRole: SystemRole.adjustments,
        );
      }
      entry = await _postDrafted(
        _draft(
          bookId: bookId,
          // A difference is a guided adjustment (02 §2 verb 6); a recognition
          // is an ordinary Money in whose counterpart is the chosen income
          // category (02 §8.2 🔒).
          kind: outcome is CountRecognition
              ? EntryKind.moneyIn
              : EntryKind.adjustment,
          lines: outcome.lines,
          date: date,
        ).copyWith(refs: EntryRefs(extra: {'cash_count': draft.id})),
      );
    }

    final hlc = _tick();
    final count = CashCount(
      id: draft.id,
      bookId: bookId,
      accountId: accountId,
      date: date,
      counted: counted,
      hlc: hlc,
      sheet: draft.sheet,
      countedBy: draft.countedBy,
      witness: draft.witness,
    );
    await _author(
      bookId: bookId,
      objectId: count.id,
      objectType: 'cash_count',
      hlc: hlc,
      // `posted_entry_id` is the link Recompute projects into `cash_counts_p`;
      // the payload codec does not read it back into [CashCount], so it rides
      // as an unknown field and round-trips (03 §3.3.4 🔒).
      object: (_) => {
        ...encodeEvent(count),
        if (entry != null) 'posted_entry_id': entry.id,
      },
    );
    await _rebuild(bookId);
    return RecordedCashCount(count: count, outcome: outcome, entry: entry);
  }

  /// The `equity_system` account of [role], or null when the book has none.
  static Account? _systemAccount(Chart chart, SystemRole role) {
    for (final a in chart.byClass(AccountClass.equitySystem)) {
      if (a.systemRole == role) return a;
    }
    return null;
  }

  /// The book an account belongs to, from the projected chart rows.
  Future<String> _bookOfAccount(String accountId) async {
    final row = await (db.select(
      db.accountsP,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(accountId, 'accountId', 'unknown account');
    }
    return row.bookId;
  }

  /// A book's type — from its `book_config` (the read path for the fields
  /// `books_p` does not project), falling back to the projected row for a
  /// book whose config envelope has not arrived yet.
  Future<BookType> _bookType(String bookId) async {
    final config = await configOf(bookId);
    if (config != null) return config.type;
    final row = await (db.select(
      db.booksP,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(bookId, 'bookId', 'unknown book');
    }
    return BookType.values.firstWhere((t) => t.name == row.type);
  }

  // ── the write path proper ─────────────────────────────────────────────────

  /// Seals [object] (built once the `author_seq` is known) under the book's
  /// current key, appends the envelope and queues it for push. One
  /// transaction: seq allocation, mirror row and outbox row land together.
  Future<EnvelopeRecord> _author({
    required String bookId,
    required String objectId,
    required String objectType,
    required Hlc hlc,
    required Map<String, Object?> Function(int authorSeq) object,
  }) {
    final id = _identity!;
    final device = _device!;
    final key = _currentKey(bookId);
    return db.transaction(() async {
      final seq = await mirror.nextAuthorSeq(bookId, id.deviceId);
      final envelopeId = newId();
      final env = EnvelopeBuilder.seal(
        suite,
        tenantId: id.tenantId,
        bookId: bookId,
        objectId: objectId,
        objectType: objectType,
        envelopeId: envelopeId,
        hlc: hlc.raw,
        authorSeq: seq,
        object: object(seq),
        bookKey: key,
        author: device,
      );
      final blob = env.blob;
      final rec = EnvelopeRecord(
        envelopeId: envelopeId,
        bookId: bookId,
        objectId: objectId,
        objectType: objectType,
        keyVersion: key.ref.keyVersion,
        hlc: hlc.raw,
        authorDevice: id.deviceId,
        authorSeq: seq,
        blob: blob,
        blobHash: env.blobHash(suite),
        // Our own signature over our own device: trusted by construction; the
        // sync engine sets the flag for others' envelopes after ChainVerifier.
        verified: true,
      );
      await mirror.append(rec);
      await mirror.enqueue(
        envelopeId: envelopeId,
        bookId: bookId,
        blob: blob,
        createdAt: now().millisecondsSinceEpoch,
      );
      return rec;
    });
  }

  Future<BookRecompute> _rebuild(String bookId) async {
    final report = (await recompute.run(bookId: bookId)).single;
    _last[bookId] = report;
    return report;
  }

  /// Full rebuild of one book (settings → *Recompute*; 02 §9).
  Future<BookRecompute> rebuild(String bookId) => _rebuild(bookId);

  // ── the month lock (02 §8 🔒) ─────────────────────────────────────────────

  /// Everything standing between [bookId] and a lock of [period] — the
  /// engine's own verdict, in the engine's own terms (02 §8 step 3 🔒, ADR
  /// 2026-09-05b §3–4, ADR 2026-09-05e §4; A-02-48…52).
  ///
  /// This facade decides **nothing**. It calls `monthLockPreconditions` over
  /// the book's projected state and hands back what it says. What it adds is
  /// only what the projector cannot see from one book's envelope stream: the
  /// mirror-level facts — an open author-sequence hole or a `held` envelope
  /// recorded against this install ([watchHealth], [heldFor]) — that a stale
  /// projection would miss. Those are **unioned in**, never substituted, and
  /// deduplicated by (kind, ref), so a blocker can be added here but never
  /// dropped.
  ///
  /// An empty list is the only condition under which [lockMonth] proceeds.
  Future<List<CloseBlockerItem>> monthClosePreconditions(
    String bookId,
    YearMonth period,
  ) async {
    _requireOpen();
    final state = await _stateOf(bookId);
    final out = <CloseBlockerItem>[...monthLockPreconditions(state, period)];
    final seen = {for (final b in out) '${b.kind.name}/${b.ref}'};

    void add(CloseBlocker kind, String ref) {
      if (seen.add('${kind.name}/$ref')) out.add(CloseBlockerItem(kind, ref));
    }

    // The mirror's own view. `author_gaps` and `envelopes_local.held` are what
    // sync writes; the projection is rebuilt from them, so in a healthy
    // install the two agree and this adds nothing. When they disagree the
    // safe direction is the one that refuses the lock: nobody certifies a
    // balance with entries known to be missing (ADR 2026-09-05b §3).
    for (final g in await (db.select(
      db.authorGaps,
    )..where((t) => t.bookId.equals(bookId))).get()) {
      add(CloseBlocker.authorGapOpen, g.authorDevice);
    }
    for (final h in await (db.select(
      db.envelopesLocal,
    )..where((t) => t.bookId.equals(bookId) & t.held.equals(1))).get()) {
      add(CloseBlocker.heldEnvelope, h.objectId);
    }
    return out;
  }

  /// Locks [period] of [bookId] (02 §8 step 4 🔒).
  ///
  /// Refuses with [MonthLockRefused] carrying the engine's own blockers when
  /// [monthClosePreconditions] is not empty — a refusal is an exception, never
  /// a silent no-op, and it appends nothing.
  ///
  /// Otherwise it authors **one signed `period_lock` envelope** recording
  ///
  ///   * [declaredBalances] — what the closer confirmed at steps 1–2, integer
  ///     paise (CLAUDE.md rule 1);
  ///   * `vector_canonical` — the balance vector **the projector computed**,
  ///     taken as `state.balances.canonical()`. This facade never recomputes
  ///     a hash of its own: the whole point of 02 §8 step 4 is that every
  ///     other member's device replays the same pure projector and must get
  ///     the same bytes, so the figure certified has to be the projector's
  ///     (03 §3.3 rule 2);
  ///   * `projector_version` — `core_ledger`'s own [projectorVersion], so a
  ///     reader on an older projector shows *update to verify* rather than a
  ///     false mismatch (ADR 2026-09-05c §3).
  ///
  /// The returned [LockedMonth] carries this device's own verification of the
  /// vector it just published, read back out of the rebuilt projection — so
  /// the caller shows a state the projector agrees with rather than assuming
  /// success.
  Future<LockedMonth> lockMonth(
    String bookId,
    YearMonth period, {
    required Map<String, Paise> declaredBalances,
  }) async {
    _requireOpen();
    final blockers = await monthClosePreconditions(bookId, period);
    if (blockers.isNotEmpty) throw MonthLockRefused(bookId, period, blockers);

    final state = await _stateOf(bookId);
    final hlc = _tick();
    final lock = PeriodLock(
      id: newId(),
      bookId: bookId,
      period: period,
      byUser: identity.userId,
      hlc: hlc,
      declaredBalances: Map.unmodifiable(declaredBalances),
      vectorCanonical: state.balances.canonical(),
      projectorVersion: projectorVersion,
    );
    await _author(
      bookId: bookId,
      objectId: lock.id,
      objectType: 'period_lock',
      hlc: hlc,
      object: (_) => encodeEvent(lock),
    );
    final report = await _rebuild(bookId);
    return LockedMonth(
      lock: lock,
      verification: report.state.lockVerification[lock.id],
    );
  }

  /// Where the closer had got to in [bookId]'s close of [period], or null when
  /// this phone has no saved progress (07 §13 *Resumable* 🔒).
  Future<SavedCloseProgress?> closeProgress(
    String bookId,
    YearMonth period,
  ) async {
    final row =
        await (db.select(db.closeProgressLocal)..where(
              (t) =>
                  t.bookId.equals(bookId) &
                  t.year.equals(period.year) &
                  t.month.equals(period.month),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return SavedCloseProgress(
      step: row.step,
      confirmedAccountIds: {
        for (final id in jsonDecode(row.confirmedBanksJson) as List)
          id as String,
      },
    );
  }

  /// Records [progress] for [bookId]'s close of [period] (07 §13 🔒).
  ///
  /// Device-local: no envelope, no signature, nothing pushed. A close
  /// half-done on one phone is that phone's business, and writing it into the
  /// ledger would make an abandoned wizard part of the family's history.
  Future<void> saveCloseProgress(
    String bookId,
    YearMonth period,
    SavedCloseProgress progress,
  ) async {
    await db
        .into(db.closeProgressLocal)
        .insertOnConflictUpdate(
          CloseProgressLocalCompanion.insert(
            bookId: bookId,
            year: period.year,
            month: period.month,
            step: progress.step,
            confirmedBanksJson: Value(
              jsonEncode(progress.confirmedAccountIds.toList()..sort()),
            ),
          ),
        );
  }

  /// Forgets the saved progress for [bookId]'s close of [period] — called once
  /// the month is locked, so returning to a closed month does not resume a
  /// wizard that has nothing left to do.
  Future<void> clearCloseProgress(String bookId, YearMonth period) =>
      (db.delete(db.closeProgressLocal)..where(
            (t) =>
                t.bookId.equals(bookId) &
                t.year.equals(period.year) &
                t.month.equals(period.month),
          ))
          .go();

  // ── late arrivals (02 §8 🔒) ──────────────────────────────────────────────

  /// The **Late Arrivals tray** of [bookId] (02 §8 🔒, ADR 2026-09-05e §3,
  /// §10): every head whose projected status is `in_tray`, oldest date first,
  /// each carrying *why it is here* — the locked month it is dated into and
  /// the HLC of the lock that was already in force when it landed.
  ///
  /// The tray is a **closer's decision queue, not a hold**: every item here
  /// already counts in the live balances (02 §3 🔒). Only the *certified*
  /// month figures leave it out. Nothing in this stream may be drawn as money
  /// that has not moved.
  ///
  /// The status is the projector's (`entries_p.status`, written by Recompute
  /// from `EffectiveStatus.inTray`) — this facade classifies nothing. Rows
  /// superseded by a later amendment are excluded: the head is the only thing
  /// a closer can act on (02 §5).
  Stream<List<LateArrival>> watchLateArrivals(String bookId) {
    final q = db.customSelect(
      'SELECT e.id, e.kind, e.accounting_date, e.note, e.created_by_user, '
      'e.hlc, l.account_id, l.amount_paise, l.line_index, '
      'a.name AS account_name, p.lock_hlc '
      'FROM entries_p e '
      'JOIN entry_lines_p l ON l.entry_id = e.id '
      'LEFT JOIN accounts_p a ON a.id = l.account_id '
      'LEFT JOIN periods_p p ON p.book_id = e.book_id '
      "  AND p.year = CAST(substr(e.accounting_date, 1, 4) AS INTEGER) "
      "  AND p.month = CAST(substr(e.accounting_date, 6, 2) AS INTEGER) "
      "WHERE e.book_id = ? AND e.status = 'in_tray' "
      'AND e.superseded_by IS NULL '
      'ORDER BY e.accounting_date, e.hlc, e.id, l.line_index',
      variables: [Variable.withString(bookId)],
      readsFrom: {db.entriesP, db.entryLinesP, db.accountsP, db.periodsP},
    );
    return q.watch().map((rows) {
      final lines = <String, List<LateArrivalLine>>{};
      final head = <String, QueryRow>{};
      final order = <String>[];
      for (final r in rows) {
        final id = r.read<String>('id');
        if (lines.putIfAbsent(id, () => []).isEmpty) {
          head[id] = r;
          order.add(id);
        }
        lines[id]!.add(
          LateArrivalLine(
            accountId: r.read<String>('account_id'),
            accountName:
                r.readNullable<String>('account_name') ??
                r.read<String>('account_id'),
            amount: Paise(r.read<int>('amount_paise')),
          ),
        );
      }
      return [
        for (final id in order)
          () {
            final r = head[id]!;
            final date = LocalDate.parse(r.read<String>('accounting_date'));
            return LateArrival(
              entryId: id,
              bookId: bookId,
              kind: EntryKind.parse(r.read<String>('kind')),
              accountingDate: date,
              lockedPeriod: date.yearMonth,
              lockedAtHlc: r.readNullable<int>('lock_hlc'),
              lines: List.unmodifiable(lines[id]!),
              note: r.readNullable<String>('note'),
              createdByUser: r.readNullable<String>('created_by_user'),
              hlc: r.read<int>('hlc'),
            );
          }(),
      ];
    });
  }

  /// *Re-date to today* — the closer's one-tap default on a late arrival
  /// (02 §8 🔒, 07 §13 🔒).
  ///
  /// An **amend**, never a reversal: 02 §8 moves the entry into the open
  /// period, it does not undo and re-post it. The lines are untouched, so the
  /// projector reads it as the one amendment 02 §5 allows against a locked
  /// period (`_isRedate` in `core_ledger/lib/src/projection.dart`: identical
  /// lines, only the date moves, into a period open at the amendment's HLC).
  /// Passing [to] re-dates into a chosen open day instead of today.
  ///
  /// Refuses exactly as [amend] does when the entry is **not** in the tray —
  /// an ordinary posted entry in a locked month is still `amendInLockedPeriod`
  /// and must be corrected by reversal (02 §5).
  Future<Entry> redateLateArrival(String entryId, {LocalDate? to}) =>
      amend(entryId, accountingDate: to ?? today());

  /// *Re-open {month}* — the admin's second choice on a late arrival (02 §8 🔒,
  /// 07 §13 🔒: scary-styled, logged).
  ///
  /// Authors **one** signed `period_unlock` envelope and nothing else: the
  /// envelope *is* the log (02 §7.2 item 3), and re-closing the month is a
  /// separate, deliberate act (02 §8 step 4). Locking and unlocking a month of
  /// an **open** year is routine admin (02 §7.2.1 🔒) — there is no quorum
  /// here and no book-role read on this facade to invent one from.
  ///
  /// Refuses with [MonthUnlockRefused], **authoring nothing**, when the month
  /// is not locked, or when it lies inside a closed financial year: that
  /// re-open voids the certificate and every later one (02 §8.1 🔒) and is the
  /// structural `year_reopen` of 02 §7.2.1 🔒, which this method is not.
  ///
  /// ⚠️ SPEC: 02 §8.1 names a **closed** year. A year already made
  /// `uncertified` by an earlier re-open has no certificate left to void, so
  /// it is not refused here; only `YearStatus.closed` is. If the owner means
  /// *any year that has ever been closed*, that is a one-line widening.
  ///
  /// A blank [reason] is a programming error, never a user state — the sheet
  /// above this call requires one before it can be tapped.
  Future<PeriodUnlock> unlockMonth(
    String bookId,
    YearMonth period, {
    required String reason,
  }) async {
    _requireOpen();
    final why = reason.trim();
    if (why.isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'a re-open records why (02 §7.2 item 3 🔒)',
      );
    }
    final state = await _stateOf(bookId);
    if (state.periods.currentStatus(period) != PeriodStatus.locked) {
      throw MonthUnlockRefused(bookId, period, MonthUnlockRefusal.notLocked);
    }
    final fyStart = await fyStartMonthOf(bookId);
    final fy = FinancialYear.of(period.firstDay, startMonth: fyStart);
    if (await _touchesClosedYear(bookId, state, fy)) {
      throw MonthUnlockRefused(bookId, period, MonthUnlockRefusal.closedYear);
    }

    final hlc = _tick();
    final unlock = PeriodUnlock(
      id: newId(),
      bookId: bookId,
      period: period,
      byUser: identity.userId,
      reason: why,
      hlc: hlc,
    );
    await _author(
      bookId: bookId,
      objectId: unlock.id,
      objectType: 'period_unlock',
      hlc: hlc,
      object: (_) => encodeEvent(unlock),
    );
    await _rebuild(bookId);
    return unlock;
  }

  /// True when re-opening a month of [fy] would void a certificate: [fy]
  /// itself, or any **later** financial year, is closed (02 §8.1 🔒 — a
  /// re-open voids "that year's certificate *and every later year's*").
  ///
  /// The live projection and the projected `year_close_p` row are **unioned**,
  /// never substituted — the same direction [monthClosePreconditions] takes:
  /// a closed year seen by either source is enough to refuse, so a stale read
  /// can add a refusal but can never drop one.
  Future<bool> _touchesClosedYear(
    String bookId,
    LedgerState state,
    FinancialYear fy,
  ) async {
    for (final e in state.years.entries) {
      if (e.value.status == YearStatus.closed &&
          !e.key.lastDay.isBefore(fy.firstDay)) {
        return true;
      }
    }
    final rows = await (db.select(
      db.yearCloseP,
    )..where((t) => t.bookId.equals(bookId) & t.state.equals('closed'))).get();
    for (final r in rows) {
      final closed = _fyOfLabel(r.fyLabel, startMonth: fy.startMonth);
      if (closed != null && !closed.lastDay.isBefore(fy.firstDay)) return true;
    }
    return false;
  }

  /// `2026-27` / `2026` → the FY it labels (the inverse of
  /// `FinancialYear.label`), or null when the row carries something this
  /// build does not understand — unreadable is never silently "open", so the
  /// caller treats null as "not this year" and the projection's own answer
  /// still stands.
  static FinancialYear? _fyOfLabel(String label, {required int startMonth}) {
    final head = label.split('-').first;
    final year = int.tryParse(head);
    return year == null ? null : FinancialYear(year, startMonth: startMonth);
  }

  /// True when [entryId]'s projected status is `in_tray` — the one carve-out
  /// [amend] makes against a locked period (02 §8 🔒). Read from the
  /// projector's own row, so this facade never decides what a tray item is.
  Future<bool> _isInTray(String entryId) async {
    final row = await (db.select(
      db.entriesP,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    return row?.status == 'in_tray';
  }

  // ── the Year Close ceremony (02 §8.1 🔒) ──────────────────────────────────

  /// Everything standing between [bookId] and a certified close of [fy] — the
  /// engine's own verdict, in the engine's own terms (02 §8.1 🔒, ADR
  /// 2026-09-05e §4).
  ///
  /// Exactly the arrangement [monthClosePreconditions] takes, and deliberately
  /// so. This facade decides **nothing**: it calls the engine's own
  /// `yearClosePreconditions` over the book's projected state and hands back
  /// what it says — every month locked, Suspense zero, no open review flag, no
  /// pending advance request, no author gap, no held envelope. What it adds is
  /// only what the projector cannot see from one book's envelope stream: the
  /// mirror-level facts — an open author-sequence hole or a `held` envelope
  /// recorded against this install — that a stale projection would miss. Those
  /// are **unioned in**, never substituted, and deduplicated by (kind, ref), so
  /// a blocker can be added here but never dropped.
  ///
  /// An empty list is the only condition under which [closeYear] proceeds.
  Future<List<CloseBlockerItem>> yearClosePreconditions(
    String bookId,
    FinancialYear fy,
  ) async {
    _requireOpen();
    final chart = await chartOf(bookId);
    final state = await _stateOf(bookId);
    final out = <CloseBlockerItem>[
      ...engine.yearClosePreconditions(state, chart, fy),
    ];
    final seen = {for (final b in out) '${b.kind.name}/${b.ref}'};

    void add(CloseBlocker kind, String ref) {
      if (seen.add('${kind.name}/$ref')) out.add(CloseBlockerItem(kind, ref));
    }

    // The mirror's own view — the same two tables, read the same way, as the
    // month lock. When mirror and projection disagree the safe direction is
    // the one that refuses: nobody certifies a year with entries known to be
    // missing (ADR 2026-09-05b §3).
    for (final g in await (db.select(
      db.authorGaps,
    )..where((t) => t.bookId.equals(bookId))).get()) {
      add(CloseBlocker.authorGapOpen, g.authorDevice);
    }
    for (final h in await (db.select(
      db.envelopesLocal,
    )..where((t) => t.bookId.equals(bookId) & t.held.equals(1))).get()) {
      add(CloseBlocker.heldEnvelope, h.objectId);
    }
    return out;
  }

  /// The closing balance vector of [fy] — **the projector's**, shown before
  /// anything is published (02 §8.1 🔒, ADR 2026-09-05e §2).
  ///
  /// It is `closingVector(state, chart, fy)` and nothing else. What belongs in
  /// the vector — money, party, advance, partner and equity_system accounts as
  /// of the FY's last day, categories not carried, the year's net result as
  /// one `netResultKey` line — is the engine's rule, and re-stating it here
  /// would be a second projector in the app layer (03 §3.3 rule 2: two pure
  /// functions are two answers).
  Future<BalanceVector> yearClosingVector(
    String bookId,
    FinancialYear fy,
  ) async {
    _requireOpen();
    final chart = await chartOf(bookId);
    final state = await _stateOf(bookId);
    return closingVector(state, chart, fy);
  }

  /// Runs the Year Close ceremony for [bookId]'s [fy] (02 §8.1 🔒).
  ///
  /// Refuses with [YearCertifyRefused] carrying the engine's own blockers when
  /// [yearClosePreconditions] is not empty, and with [YearAlreadyClosed] when
  /// the year is already sealed — a refusal is an exception, never a silent
  /// no-op, and it appends nothing.
  ///
  /// Otherwise it authors **one signed `year_close` envelope** recording
  ///
  ///   * `vector` — the vector **the projector computed**, taken straight from
  ///     [yearClosingVector]. This facade never derives a closing balance of
  ///     its own: every other member's device replays the same pure projector
  ///     and must reach the same bytes, so the figure certified has to be the
  ///     projector's (03 §3.3 rule 2);
  ///   * `projector_version` — `core_ledger`'s own [projectorVersion], so a
  ///     reader on an older projector shows *update to verify this close*
  ///     rather than a false mismatch (ADR 2026-09-05c §3 🔒).
  ///
  /// The returned [ClosedYearResult] carries this device's own verification of
  /// the vector it just published, **read back out of the rebuilt projection**
  /// — so the caller shows a state the projector agrees with rather than
  /// assuming success.
  Future<ClosedYearResult> closeYear(String bookId, FinancialYear fy) async {
    _requireOpen();
    final blockers = await yearClosePreconditions(bookId, fy);
    if (blockers.isNotEmpty) throw YearCertifyRefused(bookId, fy, blockers);

    final chart = await chartOf(bookId);
    final state = await _stateOf(bookId);
    final already = state.years[fy];
    if (already != null && already.status != YearStatus.open) {
      throw YearAlreadyClosed(bookId, fy, already.status);
    }

    final hlc = _tick();
    final close = YearClose(
      id: newId(),
      bookId: bookId,
      financialYear: fy,
      vector: closingVector(state, chart, fy),
      byUser: identity.userId,
      hlc: hlc,
      projectorVersion: projectorVersion,
    );
    await _author(
      bookId: bookId,
      objectId: close.id,
      objectType: 'year_close',
      hlc: hlc,
      object: (_) => encodeEvent(close),
    );
    final report = await _rebuild(bookId);
    return ClosedYearResult(
      close: close,
      verification: report.state.years[fy]?.verification,
    );
  }

  /// Every financial year [bookId] has closed, **oldest first** (ADR
  /// 2026-09-09 §4 🔒).
  ///
  /// Empty until the first close — which is what makes *no FY switcher at all
  /// until the first year close* true by construction rather than by a flag a
  /// screen has to remember.
  ///
  /// The live projection and the projected `year_close_p` rows are **unioned**,
  /// never substituted — the same direction [monthClosePreconditions] and
  /// [_touchesClosedYear] take. The projection wins where both speak, because
  /// it is the one that has just replayed the envelopes; a `year_close_p` row
  /// the live state has not got still counts, because a year that has closed
  /// cannot be made to disappear by a stale read.
  Future<List<CertifiedYearRow>> certifiedYears(String bookId) async {
    _requireOpen();
    final startMonth = await fyStartMonthOf(bookId);
    final state = await _stateOf(bookId);
    final rows = <FinancialYear, CertifiedYearRow>{};

    for (final r in await (db.select(
      db.yearCloseP,
    )..where((t) => t.bookId.equals(bookId))).get()) {
      final fy = _fyOfLabel(r.fyLabel, startMonth: startMonth);
      final status = _yearStatusOf(r.state);
      if (fy == null || status == null || status == YearStatus.open) continue;
      rows[fy] = CertifiedYearRow(
        year: fy,
        status: status,
        vector: _vectorOfJson(r.vector),
        verification: _verificationOfWire(r.verification),
      );
    }
    for (final e in state.years.entries) {
      if (e.value.status == YearStatus.open) continue;
      rows[e.key] = CertifiedYearRow(
        year: e.key,
        status: e.value.status,
        vector: e.value.certifiedVector,
        verification: e.value.verification,
      );
    }

    final out = rows.values.toList()
      ..sort((a, b) => a.year.firstDay.compareTo(b.year.firstDay));
    return List.unmodifiable(out);
  }

  /// `{account_id: paise}` → the vector it encodes, or null when the column is
  /// null or carries something this build cannot read. Unreadable is never
  /// silently *zero*: a null vector says *this device has no figures for that
  /// year*, which is a different claim from *the year carried nothing*.
  static BalanceVector? _vectorOfJson(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return BalanceVector({
        for (final e in map.entries) e.key: Paise(e.value as int),
      });
    } on Object {
      return null;
    }
  }

  /// The `year_close_p.state` column's word, or null when this build does not
  /// know it.
  static YearStatus? _yearStatusOf(String raw) {
    for (final s in YearStatus.values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  /// The `verification` column's wire form (`reader_outdated`, …), or null.
  /// The inverse of `packages/data`'s own writer (recompute.dart).
  static CloseVerification? _verificationOfWire(String? raw) => switch (raw) {
    'verified' => CloseVerification.verified,
    'mismatch' => CloseVerification.mismatch,
    'reader_outdated' => CloseVerification.readerOutdated,
    'certifier_outdated' => CloseVerification.certifierOutdated,
    _ => null,
  };

  // ── read side (03 §3.2 streams) ───────────────────────────────────────────

  /// Every account of [bookId] with its live balance, A–Z by name (07 §6).
  Stream<List<AccountBalance>> watchAccounts(String bookId) =>
      _watchAccountRows(bookId).map((rows) {
        final out = rows.toList()
          ..sort(
            (a, b) => a.account.name.toLowerCase().compareTo(
              b.account.name.toLowerCase(),
            ),
          );
        return out;
      });

  Stream<List<AccountBalance>> _watchAccountRows(String bookId) {
    final q = db.select(db.accountsP).join([
      leftOuterJoin(
        db.balances,
        db.balances.accountId.equalsExp(db.accountsP.id),
      ),
    ])..where(db.accountsP.bookId.equals(bookId));
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          AccountBalance(
            account: _accountOf(r.readTable(db.accountsP)),
            balancePaise: r.readTableOrNull(db.balances)?.balancePaise ?? 0,
            archived: r.readTable(db.accountsP).archived == 1,
            usualCategoryId: r.readTable(db.accountsP).usualCategoryId,
          ),
      ],
    );
  }

  static Account _accountOf(AccountsPData a) => AccountPayload.fromJson({
    'id': a.id,
    'book_id': a.bookId,
    'name': a.name,
    'class': a.accountClass,
    if (a.moneySubtype != null) 'money_subtype': a.moneySubtype,
    if (a.systemRole != null) 'system_role': a.systemRole,
    if (a.memberId != null) 'member_id': a.memberId,
    if (a.counterpartBookId != null) 'counterpart_book_id': a.counterpartBookId,
    'created_order': a.createdOrder,
  }).account;

  /// The Home position card (07 §4; 02 §9), live.
  Stream<Position> watchPosition(String bookId) =>
      _watchAccountRows(bookId).map((rows) {
        var total = 0, cash = 0, get = 0, give = 0, advances = 0, transit = 0;
        final banks = <AccountBalance>[];
        final ordered = rows.toList()
          ..sort(
            (a, b) => a.account.createdOrder.compareTo(b.account.createdOrder),
          );
        for (final r in ordered) {
          final a = r.account;
          final b = r.balancePaise;
          switch (a.accountClass) {
            case AccountClass.money:
              total += b;
              if (a.subtype == MoneySubtype.cash) {
                cash += b;
              } else if (a.subtype != MoneySubtype.cashCollection) {
                banks.add(r);
              }
            case AccountClass.party:
              if (b > 0) get += b;
              if (b < 0) give -= b;
            case AccountClass.advance:
              advances += b;
            case AccountClass.equitySystem:
              if (a.systemRole == SystemRole.dueToFrom) transit += b;
            case AccountClass.partner:
            case AccountClass.categoryIncome:
            case AccountClass.categoryExpense:
              break;
          }
        }
        return Position(
          bookId: bookId,
          totalMoneyPaise: total,
          cashPaise: cash,
          banks: banks,
          youWillGetPaise: get,
          youWillGivePaise: give,
          advancesOutPaise: advances,
          inTransitPaise: transit,
        );
      });

  /// Every **open** advance in [bookId] as of [asOf] (default today), oldest
  /// unsettled first — the *Given out* list of 07 §8, aged per 02 §7.
  ///
  /// The balance and the ageing come straight from the engine's own
  /// derivation (`openAdvances`, A-02-72…77); this adds only what the card
  /// draws — the spent/returned split and the purpose — and reads it from the
  /// same counted entries. No parallel state (02 §7 🔒).
  Future<List<AdvanceView>> openAdvances(
    String bookId, {
    LocalDate? asOf,
  }) async {
    final chart = await chartOf(bookId);
    final state = await _stateOf(bookId);
    return _advanceViews(bookId, chart, state, asOf ?? today());
  }

  /// [openAdvances], live.
  Stream<List<AdvanceView>> watchOpenAdvances(
    String bookId, {
    LocalDate? asOf,
  }) =>
      _watchAccountRows(bookId)
          .asyncMap((_) => openAdvances(bookId, asOf: asOf));

  /// *Money you are holding* (02 §7, 07 §8 **My advances**): every open
  /// advance across this device's books whose account names **this** user as
  /// the holder.
  Future<List<AdvanceView>> myAdvances({LocalDate? asOf}) async {
    _requireOpen();
    final me = identity.userId;
    final out = <AdvanceView>[];
    for (final bookId in await mirror.bookIds()) {
      out.addAll(
        (await openAdvances(bookId, asOf: asOf)).where((a) => a.memberId == me),
      );
    }
    out.sort((a, b) => b.ageDays.compareTo(a.ageDays));
    return out;
  }

  /// [myAdvances], live.
  Stream<List<AdvanceView>> watchMyAdvances({LocalDate? asOf}) =>
      db.select(db.balances).watch().asyncMap((_) => myAdvances(asOf: asOf));

  List<AdvanceView> _advanceViews(
    String bookId,
    Chart chart,
    LedgerState state,
    LocalDate asOf,
  ) {
    final views = <AdvanceView>[];
    for (final open in engine.openAdvances(state, chart, asOf: asOf)) {
      final account = chart.account(open.accountId);
      var given = 0, spent = 0, returned = 0;
      String? purpose;
      // `state.counted` is the locked statement order (02 §9), so the first
      // debit on or after the oldest unsettled date is the request still open
      // — its note is the purpose the card shows.
      for (final p in state.counted) {
        for (final line in p.entry.lines) {
          if (line.accountId != open.accountId) continue;
          if (line.amount.isDebit) {
            given += line.amount.raw;
            if (purpose == null &&
                p.entry.accountingDate.compareTo(open.oldestUnsettled) >= 0) {
              purpose = p.entry.note;
            }
          } else if (_creditWentToMoney(p.entry, open.accountId, chart)) {
            returned += -line.amount.raw;
          } else {
            spent += -line.amount.raw;
          }
        }
      }
      views.add(
        AdvanceView(
          bookId: bookId,
          accountId: open.accountId,
          accountName: account.name,
          memberId: open.memberId,
          givenPaise: given,
          spentPaise: spent,
          returnedPaise: returned,
          remainingPaise: open.balance.raw,
          takenDate: open.oldestUnsettled,
          ageDays: open.ageDays,
          purpose: purpose,
        ),
      );
    }
    views.sort((a, b) => b.ageDays.compareTo(a.ageDays));
    return views;
  }

  /// True when the debit side of an entry that credits [advanceId] is money —
  /// a *return* (`Dr money · Cr Advance`) rather than a *spend*
  /// (`Dr expense · Cr Advance`).
  static bool _creditWentToMoney(Entry entry, String advanceId, Chart chart) {
    final debits = entry.lines
        .where((l) => l.amount.isDebit && l.accountId != advanceId)
        .toList();
    return debits.isNotEmpty &&
        debits.every((l) => chart.maybeAccount(l.accountId)?.isMoney ?? false);
  }

  /// The A/C statement of [accountId] (07 §6; design-system §5): heads of
  /// accepted amend chains only, advance requests still pending excluded,
  /// reversed entries and their mirrors both present (02 §9), ordered by
  /// `(accounting_date, hlc, entry_id)` with the running balance.
  ///
  /// [from] and [to] bound the period, both inclusive (ADR 2026-09-09 §4 — the
  /// FY switcher). Rows dated before [from] are not listed but are still
  /// summed into [Statement.openingPaise], the **b/f**: the ledger is
  /// continuous, so a period opens on what the periods before it left behind.
  /// With no bounds the statement is the whole history and the b/f is zero.
  Stream<Statement> watchStatement(
    String accountId, {
    LocalDate? from,
    LocalDate? to,
  }) {
    final l = db.entryLinesP;
    final e = db.entriesP;
    final q = db.customSelect(
      'SELECT l.entry_id, l.account_id, l.amount_paise, l.line_index, '
      'e.accounting_date, e.kind, e.status, e.review_state, e.note, '
      'e.channel, e.hlc '
      'FROM entry_lines_p l JOIN entries_p e ON e.id = l.entry_id '
      'WHERE l.entry_id IN '
      '(SELECT entry_id FROM entry_lines_p WHERE account_id = ?) '
      "AND e.superseded_by IS NULL AND e.status NOT IN ('pending','rejected') "
      '${to == null ? '' : 'AND e.accounting_date <= ? '}'
      'ORDER BY e.accounting_date, e.hlc, e.id, l.line_index',
      variables: [
        Variable.withString(accountId),
        if (to != null) Variable.withString(to.toIso()),
      ],
      readsFrom: {l, e},
    );
    return q.watch().map((rows) {
      final out = <StatementRow>[];
      final others = <String, List<String>>{};
      final own = <String, QueryRow>{};
      final order = <String>[];
      for (final r in rows) {
        final entryId = r.read<String>('entry_id');
        if (!others.containsKey(entryId)) {
          others[entryId] = [];
          order.add(entryId);
        }
        if (r.read<String>('account_id') == accountId) {
          own[entryId] = r;
        } else {
          others[entryId]!.add(r.read<String>('account_id'));
        }
      }
      var running = 0;
      var opening = 0;
      for (final entryId in order) {
        final r = own[entryId];
        if (r == null) continue;
        final amount = r.read<int>('amount_paise');
        running += amount;
        final date = LocalDate.parse(r.read<String>('accounting_date'));
        // Before the period: it is not a row, it is part of the b/f.
        if (from != null && date.isBefore(from)) {
          opening = running;
          continue;
        }
        out.add(
          StatementRow(
            entryId: entryId,
            accountId: accountId,
            date: date,
            kind: EntryKind.parse(r.read<String>('kind')),
            status: r.read<String>('status'),
            reviewState: r.read<String>('review_state'),
            amountPaise: amount,
            runningBalancePaise: running,
            counterAccountIds: List.unmodifiable(others[entryId]!),
            hlc: r.read<int>('hlc'),
            note: r.readNullable<String>('note'),
            channel: r.readNullable<String>('channel'),
          ),
        );
      }
      return Statement(
        accountId: accountId,
        rows: out,
        openingPaise: opening,
        from: from,
        to: to,
      );
    });
  }

  /// The held envelope carrying [objectId], or null when nothing on this
  /// phone holds it (ADR 2026-09-05b §4). *Held* means verified, in the
  /// mirror, not projected and not counted — S4.1 draws it as waiting, never
  /// as an error. The earliest hold wins when a book somehow holds two.
  Future<HeldObject?> heldFor(String objectId) async {
    final row =
        await (db.select(db.envelopesLocal)
              ..where((t) => t.objectId.equals(objectId) & t.held.equals(1))
              ..orderBy([(t) => OrderingTerm.asc(t.hlc)])
              ..limit(1))
            .getSingleOrNull();
    return row == null
        ? null
        : HeldObject(objectId: objectId, waitingForId: row.heldFor);
  }

  /// The id of the entry that reverses [entryId], or null when none does.
  /// One reversal per entry (02 §5, `alreadyReversed`), so at most one row.
  Future<String?> reversalOf(String entryId) async {
    final row =
        await (db.select(db.entriesP)
              ..where((t) => t.reverses.equals(entryId))
              ..limit(1))
            .getSingleOrNull();
    return row?.id;
  }

  /// One entry with its lines, or null.
  Future<EntryView?> entry(String id) async {
    final row = await (db.select(
      db.entriesP,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final lines =
        await (db.select(db.entryLinesP)
              ..where((t) => t.entryId.equals(id))
              ..orderBy([(t) => OrderingTerm.asc(t.lineIndex)]))
            .get();
    return EntryView(
      id: row.id,
      bookId: row.bookId,
      kind: EntryKind.parse(row.kind),
      status: row.status,
      date: LocalDate.parse(row.accountingDate),
      lines: [
        for (final l in lines)
          Line(accountId: l.accountId, amount: Paise(l.amountPaise)),
      ],
      reviewState: row.reviewState,
      createdByUser: row.createdByUser,
      hlc: row.hlc,
      note: row.note,
      channel: row.channel,
      partyId: row.partyId,
      amends: row.amends,
      reverses: row.reverses,
      supersededBy: row.supersededBy,
    );
  }

  /// Live health of [bookId]'s projection for S1.4 and the status chip.
  /// Emits nothing until the book is projected.
  Stream<BookHealth> watchHealth(String bookId) {
    final q = db.customSelect(
      'SELECT b.integrity_ok, b.needs_rebootstrap, '
      '(SELECT COUNT(*) FROM envelopes_local '
      ' WHERE book_id = ?1 AND held = 1) AS held, '
      '(SELECT COUNT(*) FROM author_gaps WHERE book_id = ?1) AS gaps, '
      '(SELECT COUNT(*) FROM envelopes_local '
      ' WHERE book_id = ?1 AND quarantined = 1) AS quarantined '
      'FROM books_p b WHERE b.id = ?1',
      variables: [Variable.withString(bookId)],
      readsFrom: {db.booksP, db.envelopesLocal, db.authorGaps},
    );
    return q
        .watchSingleOrNull()
        .where((r) => r != null)
        .map(
          (r) => BookHealth(
            bookId: bookId,
            integrityOk: r!.read<int>('integrity_ok') == 1,
            needsRebootstrap: r.read<int>('needs_rebootstrap') == 1,
            heldCount: r.read<int>('held'),
            authorGapCount: r.read<int>('gaps'),
            quarantinedCount: r.read<int>('quarantined'),
          ),
        );
  }

  /// Outbox rows still to push — the `Saved on phone · will sync (N)` count
  /// (07 §1 rule 7).
  Stream<int> watchPendingPushes() {
    final c = db.outbox.envelopeId.count();
    return (db.selectOnly(db.outbox)
          ..addColumns([c])
          ..where(db.outbox.pushState.isNotValue(PushState.observed.name)))
        .map((r) => r.read(c) ?? 0)
        .watchSingle();
  }

  // ── inter-book movement (02 §6 🔒) ───────────────────────────────────────
  // Books connect only through paired `Due to/from` system accounts, and one
  // user action appends **two** envelopes sharing `refs.transfer_group`, one
  // per book. Every posting below is the engine's (`InterBook.transfer`,
  // `InterBook.pocketExpense`; A-02-78…82, A-ref-6) — this facade finds or
  // creates the pair of accounts, mints the group, and posts each half through
  // the ordinary [post] path so the 02 §1.4 invariants, the §2 shape and the
  // §8 period lock all still apply to both.

  /// The seeded name of a `Due to/from {other book}` account. Account names
  /// are **user data**, not ARB labels (the [SeedCategory] rule), so a screen
  /// passes the localised spelling in and this English default exists for
  /// fixtures and for a caller that has none — exactly like [createBook]'s
  /// `openingBalanceName`.
  static String defaultDueToFromName(String otherBookName) =>
      'Due to/from $otherBookName';

  /// The `Due to/from [counterpartBookId]` account of [bookId], created on
  /// **first use** (02 §6). [name] is used only when it is created.
  Future<Account> dueToFromAccount(
    String bookId, {
    required String counterpartBookId,
    String? name,
  }) async {
    _requireOpen();
    final existing = _dueFacing(await chartOf(bookId), counterpartBookId);
    if (existing != null) return existing;
    final otherName = await _bookName(counterpartBookId);
    return addAccount(
      bookId,
      name: name ?? defaultDueToFromName(otherName ?? counterpartBookId),
      accountClass: AccountClass.equitySystem,
      systemRole: SystemRole.dueToFrom,
      counterpartBookId: counterpartBookId,
    );
  }

  /// "Move ₹X from {book A} to {book B}" (02 §6 🔒) — one user action, two
  /// envelopes sharing `refs.transfer_group`:
  /// `A: Dr Due to/from B · Cr money` and `B: Dr money · Cr Due to/from A`.
  /// The paired accounts are auto-created on first use. Both halves post
  /// immediately — the money moved — so reconciliation nets to zero from the
  /// moment of entry.
  ///
  /// Each half is measured against **its own book's** auto-post limit for
  /// this author ([reviewPolicy], 02 §3 🔒) — two reads, one per book, each
  /// written into that half's payload with the limit it was measured against.
  /// One movement can therefore be flagged in the book it left and unflagged
  /// in the book it reached, which is what 02 §6 describes.
  ///
  /// ⚠️ SPEC: 02 §6 says the half where *the actor lacks posting rights*
  /// carries the review flag for that book's approver. Rights are still not
  /// evaluated here: the seam answers *the limit*, and a member with **no
  /// grant at all** in the receiving book is indistinguishable from a member
  /// whose grant simply carries no limit, and from metadata this offline-first
  /// device has not pulled yet. Flagging on that absence would raise a flag
  /// nobody can clear (02 §7.2 item 1 🔒) and block that book's month close
  /// (02 §8 step 3 🔒), so the conservative reading stands: flag what the
  /// limit demands, invent nothing from missing metadata. [reviewRequiredIn]
  /// remains as an explicit override a caller may **add** to the computed
  /// flag, never subtract from it. 07 §10's *In transit* is still only what
  /// the engine's [InterBook.isInTransit] reports over the projected halves,
  /// never a state this facade keeps.
  Future<InterBookMovement> transferBetweenBooks({
    required String fromBookId,
    required String fromAccountId,
    required String toBookId,
    required String toAccountId,
    required int paise,
    required LocalDate date,
    ({String from, String to})? dueNames,
    ({bool from, bool to}) reviewRequiredIn = (from: false, to: false),
    String? note,
  }) async {
    _requireOpen();
    await _checkMovement(fromBookId, toBookId, paise);
    final fromMoney = _money(await chartOf(fromBookId), fromAccountId);
    final toMoney = _money(await chartOf(toBookId), toAccountId);
    final fromDue = await dueToFromAccount(
      fromBookId,
      counterpartBookId: toBookId,
      name: dueNames?.from,
    );
    final toDue = await dueToFromAccount(
      toBookId,
      counterpartBookId: fromBookId,
      name: dueNames?.to,
    );
    final group = newId();
    final review = await _pairReview(
      fromBookId: fromBookId,
      toBookId: toBookId,
      paise: paise,
      override: reviewRequiredIn,
    );
    final pair = InterBook.transfer(
      amount: Paise(paise),
      accountingDate: date,
      from: (money: fromMoney, dueToFrom: fromDue),
      to: (money: toMoney, dueToFrom: toDue),
      transferGroup: group,
      ids: (from: newId(), to: newId()),
      hlcs: (from: _clock, to: _clock),
      createdByUser: identity.userId,
      createdByDevice: identity.deviceId,
      reviewRequiredIn: review.required,
      reviewLimitPaise: review.limits,
      note: note,
    );
    return _postPair(pair, group);
  }

  /// The one-sided everyday case (02 §6 🔒): a member pays another book's
  /// expense out of his own pocket. Payer's book `Dr Due to/from {payee} · Cr
  /// Cash` — money owed to him, never an expense of his; payee's book
  /// `Dr Expense · Cr Due to/from {payer}`. Nothing is ever lost in someone's
  /// pocket.
  ///
  /// Same mechanism, same `refs.transfer_group`, same ⚠️ SPEC note on rights
  /// as [transferBetweenBooks].
  Future<InterBookMovement> pocketExpense({
    required String payerBookId,
    required String payerMoneyId,
    required String payeeBookId,
    required String payeeExpenseId,
    required int paise,
    required LocalDate date,
    ({String from, String to})? dueNames,
    ({bool from, bool to}) reviewRequiredIn = (from: false, to: false),
    String? note,
  }) async {
    _requireOpen();
    await _checkMovement(payerBookId, payeeBookId, paise);
    final money = _money(await chartOf(payerBookId), payerMoneyId);
    final expense = _expense(await chartOf(payeeBookId), payeeExpenseId);
    final payerDue = await dueToFromAccount(
      payerBookId,
      counterpartBookId: payeeBookId,
      name: dueNames?.from,
    );
    final payeeDue = await dueToFromAccount(
      payeeBookId,
      counterpartBookId: payerBookId,
      name: dueNames?.to,
    );
    final group = newId();
    final review = await _pairReview(
      fromBookId: payerBookId,
      toBookId: payeeBookId,
      paise: paise,
      override: reviewRequiredIn,
    );
    final pair = InterBook.pocketExpense(
      amount: Paise(paise),
      accountingDate: date,
      payer: (money: money, dueToFrom: payerDue),
      payee: (expense: expense, dueToFrom: payeeDue),
      transferGroup: group,
      ids: (from: newId(), to: newId()),
      hlcs: (from: _clock, to: _clock),
      createdByUser: identity.userId,
      createdByDevice: identity.deviceId,
      reviewRequiredIn: review.required,
      reviewLimitPaise: review.limits,
      note: note,
    );
    return _postPair(pair, group);
  }

  /// The **Family Reconciliation** report (S8.3; 02 §6 🔒): every pair of
  /// `Due to/from` accounts this reader can see, once each, with the engine's
  /// verdict on it and the entries composing both sides.
  ///
  /// The verdict is [InterBook.reconcile]'s, not this method's — balanced,
  /// non-zero, or **one-sided · unconfirmed** when the other side sits in a
  /// book whose key this device does not hold (04 §5.2, ADR 2026-09-05e §7
  /// 🔒). A sealed side is never reported as a mismatch.
  ///
  /// ⚠️ SPEC: a counterpart book this reader *does* hold, but which carries no
  /// matching `Due to/from` account yet — the other half has not arrived — is
  /// therefore reported as a non-zero pair *with its composing entries*, not
  /// as *unconfirmed*: ADR 2026-09-05e §7 reserves *unconfirmed* for a side
  /// the reader cannot open, and 02 §6 says every non-zero pair is listed.
  /// That is the conservative reading; 07 §10's *In transit* label is carried
  /// separately, by [ReconciliationPair.inTransit], and only from the engine.
  Future<List<ReconciliationPair>> reconciliation() async {
    _requireOpen();
    final bookIds = await mirror.bookIds();
    final held = bookIds.toSet();
    final names = {
      for (final b in await db.select(db.booksP).get()) b.id: b.name,
    };
    final charts = <String, Chart>{};
    final states = <String, LedgerState>{};
    for (final id in bookIds) {
      charts[id] = await chartOf(id);
      states[id] = await _stateOf(id);
    }

    final seen = <String>{};
    final out = <ReconciliationPair>[];
    for (final bookId in bookIds) {
      for (final due
          in charts[bookId]!
              .byClass(AccountClass.equitySystem)
              .where((a) => a.systemRole == SystemRole.dueToFrom)) {
        final other = due.counterpartBookId;
        // A `Due to/from` naming no counterpart names no pair: there is
        // nothing to reconcile it against, and that is not a mismatch either.
        if (other == null) continue;
        // One row per pair, whichever side it was met from.
        if (!seen.add(([bookId, other]..sort()).join('/'))) continue;
        final otherHeld = held.contains(other);
        final otherDue = otherHeld ? _dueFacing(charts[other]!, bookId) : null;
        final r = InterBook.reconcile([
          InterBookPair(
            a: states[bookId],
            accountA: due.id,
            b: otherHeld ? states[other] : null,
            accountB: otherDue?.id ?? '',
          ),
        ]).single;
        final entries = [
          ..._composing(states[bookId]!, names, bookId, r.entryIdsA, due.id),
          if (otherHeld && otherDue != null)
            ..._composing(
              states[other]!,
              names,
              other,
              r.entryIdsB,
              otherDue.id,
            ),
        ]..sort((x, y) => x.date.compareTo(y.date));
        out.add(
          ReconciliationPair(
            bookId: bookId,
            bookName: names[bookId] ?? '',
            accountId: due.id,
            counterpartBookId: other,
            counterpartBookName: otherHeld ? names[other] : null,
            counterpartAccountId: otherDue?.id,
            status: r.status,
            netPaise: r.net.raw,
            sidePaise: states[bookId]!.balances[due.id].raw,
            inTransit: entries.any((e) => e.inTransit),
            entries: entries,
          ),
        );
      }
    }
    return out;
  }

  /// [reconciliation], live — the stream S8.3 renders and S1 reads its
  /// *In transit* line from.
  Stream<List<ReconciliationPair>> watchReconciliation() =>
      db.select(db.balances).watch().asyncMap((_) => reconciliation());

  /// The entries of [state] composing one side of a pair, oldest first.
  ///
  /// The ids are the engine's ([PairReconciliation.entryIdsA] / `B`); this
  /// only dresses them with what a reader needs on screen. *In transit* is the
  /// engine's own predicate, given the half it has: [InterBook.isInTransit] is
  /// "either of these halves still carries an open review flag", so asking it
  /// about one half asks exactly whether *that* half is still awaiting its
  /// approver. A pair is in transit when any of its halves is.
  List<ReconciliationEntry> _composing(
    LedgerState state,
    Map<String, String> names,
    String bookId,
    List<String> ids,
    String accountId,
  ) {
    final wanted = ids.toSet();
    return [
      for (final p in state.counted)
        if (wanted.contains(p.entry.id))
          ReconciliationEntry(
            entryId: p.entry.id,
            bookId: bookId,
            bookName: names[bookId] ?? '',
            date: p.entry.accountingDate,
            amountPaise: p.entry.lines
                .where((l) => l.accountId == accountId)
                .fold(0, (sum, l) => sum + l.amount.raw),
            inTransit: InterBook.isInTransit(p, p),
            note: p.entry.note,
          ),
    ];
  }

  Account? _dueFacing(Chart chart, String counterpartBookId) {
    for (final a in chart.byClass(AccountClass.equitySystem)) {
      if (a.systemRole == SystemRole.dueToFrom &&
          a.counterpartBookId == counterpartBookId) {
        return a;
      }
    }
    return null;
  }

  Future<String?> _bookName(String bookId) async => (await (db.select(
    db.booksP,
  )..where((b) => b.id.equals(bookId))).getSingleOrNull())?.name;

  Future<void> _checkMovement(String a, String b, int paise) async {
    if (paise <= 0) {
      throw const InterBookRefused(
        InterBookRefusal.amountNotPositive,
        'an inter-book movement moves a positive number of paise',
      );
    }
    if (a == b) {
      throw const InterBookRefused(
        InterBookRefusal.sameBook,
        'inter-book movement needs two different books (02 §6)',
      );
    }
    final held = (await mirror.bookIds()).toSet();
    for (final id in [a, b]) {
      if (!held.contains(id)) {
        throw InterBookRefused(
          InterBookRefusal.bookNotHeld,
          'this device holds no key for book $id (04 §5.2)',
        );
      }
    }
  }

  Account _money(Chart chart, String accountId) {
    final a = chart.maybeAccount(accountId);
    if (a == null || !a.isMoney) {
      throw InterBookRefused(
        InterBookRefusal.notAMoneyAccount,
        '$accountId is not a money account of ${chart.bookId}',
      );
    }
    return a;
  }

  Account _expense(Chart chart, String accountId) {
    final a = chart.maybeAccount(accountId);
    if (a == null || a.accountClass != AccountClass.categoryExpense) {
      throw InterBookRefused(
        InterBookRefusal.notAnExpenseCategory,
        '$accountId is not an expense category of ${chart.bookId}',
      );
    }
    return a;
  }

  /// Zeroises in-memory key material. The database is the caller's to close.
  void dispose() {
    // The store is shared with the sync engine's guard (see
    // [LedgerKeyMaterial]): clearing it here zeroises those keys for the guard
    // too, which is the point — one device, one set of keys, one wipe.
    _keySource.store?.clear();
    _keySource.store = null;
    _keySource.tenants.clear();
    _umk?.dispose();
    _device?.dispose();
    _umk = null;
    _device = null;
    _umkVerified = null;
    _verifiedMembers = null;
    _ownCert = null;
    _identity = null;
  }
}
