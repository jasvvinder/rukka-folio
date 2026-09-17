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
import 'package:core_ledger/core_ledger.dart' as engine show openAdvances;
import 'package:data/data.dart';
import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart'
    show AcceptedBookKey, AcceptedKeySink, BookKeyStore, VerifiedUmkSource;

import '../seams/key_store.dart';
import 'device_certification.dart';
import 'ledger_identity.dart';

export 'device_certification.dart'
    show DeviceCertOffer, DeviceCertifier, umkKeyVersionFirst;
export 'ledger_identity.dart'
    show LedgerIdentity, LocalLedgerKeys, readStoredIdentity;

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
/// What it does not permit: believing anybody else — [verifiedUmkOf] answers
/// only for this install's own user and returns null for every other user id,
/// so no book key can be wrapped to an unverified fingerprint through this
/// seam (04 §8.2 🔒, rule 5). It carries no ledger write path either: posting,
/// book creation and key minting stay behind [LocalLedger]'s own methods.
final class LedgerKeyMaterial implements VerifiedUmkSource {
  const LedgerKeyMaterial._({
    required this.userId,
    required this.device,
    required this.umk,
    required this.bookKeys,
    required VerifiedUmkPublic ownUmk,
  }) : _ownUmk = ownUmk; // ignore: prefer_initializing_formals

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

  /// The ceremony-verified UMK of [userId] — this install's own user, whose
  /// fingerprint it checked byte-for-byte at bootstrap (04 §3.4). Null for
  /// every other user: another member is believed only after a ceremony, never
  /// because this device happens to know their id.
  @override
  VerifiedUmkPublic? verifiedUmkOf(String userId) =>
      userId == this.userId ? _ownUmk : null;
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

/// The local ledger.
final class LocalLedger implements DeviceCertifier, AcceptedKeySink {
  /// Creates the facade. [suite] is the app's libsodium binding wrapped in a
  /// [CryptoSuite]; [now] is the injected wall clock the HLC ticks against.
  LocalLedger({
    required this.db,
    required this.keys,
    required this.suite,
    required this.now,
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
    );
  }

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
    return post(
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
    return post(
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
    return post(
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
    return post(
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
    return post(
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
    return post(
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
    final hlc = _tick();
    final decision = ApprovalDecision(
      id: newId(),
      bookId: row.bookId,
      entryId: entryId,
      decision: Decision.approve,
      byUser: identity.userId,
      hlc: hlc,
    );
    await _author(
      bookId: row.bookId,
      objectId: decision.id,
      objectType: 'approval_decision',
      hlc: hlc,
      object: (_) => encodeEvent(decision),
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
    return post(
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
    return post(
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
        await post(
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
    if (state.periods.currentStatus(period) == PeriodStatus.locked) {
      violations.add(
        Violation(
          ViolationKind.amendInLockedPeriod,
          '$period is locked — reverse instead (02 §5)',
        ),
      );
    }
    if (violations.isNotEmpty) throw PostRejected(entryId, violations);
    return post(
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
    return post(
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
    return post(
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
      entry = await post(
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
  /// ⚠️ SPEC: 02 §6 says the half where *the actor lacks posting rights*
  /// carries the review flag for that book's approver, and 07 §10 labels the
  /// pair *In transit* while it is open. This app has **no book-role source
  /// yet** — 13 §2.3's "who am I, here?" is not wired to a membership record —
  /// so no rights can be evaluated here and both halves post unflagged by
  /// default. [reviewRequiredIn] is the seam the rights lane fills; inventing
  /// a role to decide it would be inventing behaviour. Consequently *in
  /// transit* is only ever what the engine's [InterBook.isInTransit] reports
  /// over the projected halves, never a state this facade keeps.
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
      reviewRequiredIn: reviewRequiredIn,
      reviewLimitPaise: (from: null, to: null),
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
      reviewRequiredIn: reviewRequiredIn,
      reviewLimitPaise: (from: null, to: null),
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
    _ownCert = null;
    _identity = null;
  }
}
