// What S10.4 needs from the ledger, and nothing more — the CL1 arrangement of
// `close_source.dart`, applied to the **Year Close ceremony** (02 §8.1 🔒).
//
// `app/lib/shared/ledger/` is another lane's folder this round and carries no
// year-close surface at all: there is no `closeYear`, no year-precondition
// read and no certified-years read on `LocalLedger` today. So the screen talks
// to this **feature-local interface**, the next lane implements it over the
// facade, and nothing in this folder imports `LocalLedger`.
//
// There is deliberately **no `LedgerYearCloseSource` in this slice.** A year
// close needs `yearClosePreconditions(state, chart, fy)` and
// `closingVector(state, chart, fy)`, both of which take the projector's
// `LedgerState`. That state is not reachable from the facade's public reads,
// and re-deriving it here would mean a second projector in the UI layer —
// forbidden (03 §3.3: the projector is *the* pure function, and two of them
// are two answers). The exact `LocalLedger` signatures the next lane must add
// are in this lane's report.
//
// What a year close *means* stays the engine's to say:
//
//   * **what blocks** is `core_ledger`'s own [CloseBlockerItem], returned by
//     `yearClosePreconditions` — every month locked, Suspense zero, no open
//     review flag, no pending advance request, no author-sequence gap, no held
//     envelope (02 §8.1 🔒, ADR 2026-09-05e §4). [YearCloseBlocker] *holds*
//     that item rather than restating it, so the screen cannot invent a
//     blocker and an implementation cannot quietly demote one to a warning.
//   * **what warns** is [CloseWarning.agedAdvance] — the one thing 02 §8.1 🔒
//     names as warn-only at the year boundary — carried as the same
//     [CloseWarningItem] the month close uses. A different type from a
//     blocker, so the two can never arrive as one undifferentiated list
//     (07 §13 🔒).
//   * **what a close is** is [YearClose]: the signed envelope carrying the
//     closing balance vector and the `projectorVersion` that computed it
//     (02 §8.1 🔒, ADR 2026-09-05c §3). This seam carries the engine's event
//     back unchanged.
//   * **what the vector holds** is ADR 2026-09-05e §2's rule and not this
//     file's: money, party, advance, partner and equity_system accounts as of
//     the FY's last day, category accounts **not** carried, the year's net
//     result as one [netResultKey] line. [YearCloseVector] only *names* those
//     keys for display.
//
// Money is [Paise] end to end — integer paise, never a double (CLAUDE.md
// rule 1).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/widgets.dart';

import 'close_period.dart';
import 'close_source.dart' show CloseWarning, CloseWarningItem;

/// One precondition standing between the closer and the certificate.
///
/// It **holds** the engine's [CloseBlockerItem] rather than copying its
/// fields, so `kind` and `ref` are the engine's own words. The two extra
/// fields are presentation only: a name for the thing [CloseBlockerItem.ref]
/// points at, and — for the two sync blockers — the name of the phone whose
/// entries have not arrived, because a device id is never printed at a
/// shopkeeper (07 §28 🔒).
final class YearCloseBlocker {
  /// Creates the blocker.
  const YearCloseBlocker({required this.item, this.label, this.deviceName});

  /// Convenience for the common case: an engine kind and the ref it points at.
  YearCloseBlocker.of(
    CloseBlocker kind,
    String ref, {
    String? label,
    String? deviceName,
  }) : this(
         item: CloseBlockerItem(kind, ref),
         label: label,
         deviceName: deviceName,
       );

  /// The engine's own item, as `yearClosePreconditions` returned it.
  final CloseBlockerItem item;

  /// A human label for [ref] — an A/C name, a party, a narration. Null is
  /// fine: the screen then states the kind alone rather than an id.
  final String? label;

  /// The **name of the phone** whose entries have not arrived, for
  /// [CloseBlocker.authorGapOpen] and [CloseBlocker.heldEnvelope].
  final String? deviceName;

  /// The engine's reason.
  CloseBlocker get kind => item.kind;

  /// The month, account, entry, envelope or device id concerned.
  String get ref => item.ref;

  /// For [CloseBlocker.monthOpen], the month itself — `yearClosePreconditions`
  /// writes `YearMonth.toString()` into [ref], so this is a parse of the
  /// engine's own form and never a second calendar. Null for every other kind.
  ///
  /// The checklist states the month by name: *"March 2027 is still open"*
  /// tells the closer where to go, *"a month is open"* does not (07 §1 rule 6).
  YearMonth? get month =>
      kind == CloseBlocker.monthOpen ? parseClosePeriod(ref) : null;

  /// True for the two blockers that mean *entries are known to be missing*
  /// (ADR 2026-09-05b §3–4). Nobody certifies a balance with entries missing,
  /// and the screen says whose phone rather than offering a remedy here.
  bool get isGap =>
      kind == CloseBlocker.authorGapOpen || kind == CloseBlocker.heldEnvelope;

  /// True for the two **queue** blockers — the open review flags and the
  /// pending advance requests, which 02 §8.1 🔒 is explicit are *two distinct
  /// queues, both of which must be empty*. The checklist names the queue.
  bool get isQueue =>
      kind == CloseBlocker.reviewFlagOpen ||
      kind == CloseBlocker.advancePending;
}

/// One line of the closing balance vector, named for display.
final class YearCloseVectorLine {
  /// Creates the line.
  const YearCloseVectorLine({
    required this.key,
    required this.amount,
    this.name,
  });

  /// The account id — or a [netResultKey] for the year's own net result.
  final String key;

  /// Signed engine paise (+ = Dr).
  final Paise amount;

  /// The A/C name as the user wrote it; null for a net-result line and for an
  /// account this reader cannot name.
  final String? name;

  /// True for the **one net surplus/deficit line** ADR 2026-09-05e §2 🔒
  /// requires in place of carried category accounts.
  bool get isNetResult => isNetResultKey(key);
}

/// The closing balance vector as the certify step shows it, before anything
/// is published (02 §8.1 🔒: *the closer's device computes the closing balance
/// vector … and publishes it as a signed year-close envelope*).
///
/// It carries the engine's [BalanceVector] unchanged — the thing that will be
/// hashed and verified — plus the names needed to draw it. Nothing here
/// decides *what* is in the vector; that is `closingVector`, and an
/// implementation calls it rather than re-stating ADR 2026-09-05e §2.
final class YearCloseVector {
  /// Creates the summary.
  const YearCloseVector({required this.vector, this.names = const {}});

  /// The engine's vector.
  final BalanceVector vector;

  /// Account id → name, for the lines this reader can name.
  final Map<String, String> names;

  /// The lines to draw: balance-sheet accounts first in name order, then the
  /// net-result line(s) last, because the net result is the *conclusion* of
  /// the list and reads as one at the bottom.
  List<YearCloseVectorLine> get lines {
    final accounts = <YearCloseVectorLine>[];
    final results = <YearCloseVectorLine>[];
    for (final e in vector.nonZero.entries) {
      final line = YearCloseVectorLine(
        key: e.key,
        amount: e.value,
        name: names[e.key],
      );
      (line.isNetResult ? results : accounts).add(line);
    }
    accounts.sort((a, b) => (a.name ?? a.key).compareTo(b.name ?? b.key));
    results.sort((a, b) => a.key.compareTo(b.key));
    return [...accounts, ...results];
  }

  /// The book's balance-sheet total carried into the next year — debits and
  /// credits are equal in a balanced vector, so one figure states it.
  Paise get carriedForward => vector.totalDebits;

  /// The books-balanced check (02 §8). A vector that does not balance is not
  /// certifiable, and the screen says so rather than offering the action.
  bool get isBalanced => vector.isBalanced;

  /// True when there is nothing to certify — the honest empty state, never a
  /// blank card (07 §1 rule 12).
  bool get isEmpty => vector.nonZero.isEmpty;
}

/// Everything S10.4 draws for one book's financial year, in one load.
///
/// One load, one object — the same reason as [CloseView]: the checklist, the
/// vector and the certify action must not be computed from three different
/// readings of the ledger while the closer is deciding.
final class YearCloseView {
  /// Creates the view.
  const YearCloseView({
    required this.bookId,
    required this.bookName,
    required this.financialYear,
    required this.status,
    this.blockers = const [],
    this.warnings = const [],
    this.vector,
    this.isBusiness = false,
    this.distributionPending = false,
    this.certifiedVector,
    this.verification,
    this.voidedBy,
    this.readOnly = false,
  });

  /// The book being closed.
  final String bookId;

  /// Its name, for the title line.
  final String bookName;

  /// The year being closed.
  final FinancialYear financialYear;

  /// `open` → `closed` → `uncertified` (13 §6 🔒: *open → closed/certified →
  /// (voided by re-open, loudly)*; 02 §8.1 says `closed`, 13 said `certified`,
  /// and both name the same state — ADR 2026-09-05e §12).
  final YearStatus status;

  /// Every precondition not yet met, in the engine's terms. Empty is the only
  /// condition under which the certify action is offered (02 §8.1 🔒).
  final List<YearCloseBlocker> blockers;

  /// Aged advances — warn-only at the year boundary (02 §8.1 🔒), stated
  /// plainly *as* warnings and never mixed into [blockers].
  final List<CloseWarningItem> warnings;

  /// What certifying would publish, shown **before** the action (02 §8.1 🔒).
  ///
  /// Null while this reader has no vector to show — a book still blocked on a
  /// missing phone has no certifiable figures, and an empty table would read
  /// as *nothing to carry forward*, which is a different claim.
  final YearCloseVector? vector;

  /// True for a business book — the only kind 02 §8.1 🔒 prompts (optionally)
  /// to distribute profit first. A personal or family book never sees the door
  /// and never hears the word *partner* (02 §7.1 🔒: *Just me* books never
  /// mention partners, ratios or profit distribution anywhere in the app).
  final bool isBusiness;

  /// True when this FY's surplus has not been distributed — what makes the
  /// optional *Distribute profit first* door worth offering. It is a **door to
  /// S14.1**, which already exists at `PartnersPaths.distributeOf`; this
  /// screen never rebuilds the wizard (02 §7.2.1: distribution is structural).
  final bool distributionPending;

  /// For a closed year: the vector actually certified, which is the b/f the
  /// next FY opens on (02 §8.1 🔒). Null while the year is open.
  final YearCloseVector? certifiedVector;

  /// How **this device's** replay relates to the certified vector
  /// (ADR 2026-09-05c §3 🔒). [CloseVerification.readerOutdated] is the
  /// *unverified-by-you* variant — *Update the app to verify this close* —
  /// and is never shown as a mismatch. Null before a close exists.
  final CloseVerification? verification;

  /// For [YearStatus.uncertified]: the month whose re-opening voided the
  /// certificate, when it is known. 02 §8.1 🔒 — *unlocking any month of a
  /// closed year voids that year's certificate and every later year's* — so
  /// the loud banner names the month where it can.
  final YearMonth? voidedBy;

  /// True when this member may read the book but not certify it (13 §2.3.1,
  /// and 02 §7.2.1: re-opening a closed year is a structural act). The screen
  /// stays legible; the action says why it is off.
  final bool readOnly;

  /// True when nothing blocks (02 §8.1 🔒).
  bool get canCertify => blockers.isEmpty;

  /// The blockers that mean entries are missing, which the closer cannot
  /// clear here (ADR 2026-09-05b §3–4).
  List<YearCloseBlocker> get gaps =>
      blockers.where((b) => b.isGap).toList(growable: false);

  /// The months of this FY still open, oldest first — the checklist's first
  /// group, and the one with a place to go (02 §8.1 🔒: every month locked).
  List<YearMonth> get openMonths {
    final out = [for (final b in blockers) ?b.month];
    out.sort();
    return out;
  }
}

/// What certifying the year came to — the engine's own [YearClose], carried
/// back unchanged, with this device's verification of it.
final class YearCloseResult {
  /// Creates the result.
  const YearCloseResult({required this.close, this.verification});

  /// The signed year-close envelope: the closing vector and the
  /// `projectorVersion` that computed it (02 §8.1 🔒, ADR 2026-09-05c §3).
  final YearClose close;

  /// This device's own verification. [CloseVerification.readerOutdated] is a
  /// **state**, not an error (ADR 2026-09-05c §3 🔒).
  final CloseVerification? verification;
}

/// A close the engine refused: `yearClosePreconditions` was not empty.
///
/// The screen keeps the action disabled for every blocker it can see, so this
/// is the backstop — and it carries the engine's own [CloseBlockerItem]s
/// rather than a message the widget invented.
final class YearCloseRefused implements Exception {
  /// Creates the refusal.
  const YearCloseRefused(this.blockers);

  /// What the engine objected to (02 §8.1 🔒).
  final List<CloseBlockerItem> blockers;

  @override
  String toString() => 'YearCloseRefused($blockers)';
}

/// One year this book has closed — the FY switcher's input (ADR 2026-09-09
/// §4 🔒: the switcher is one control on S4 · S8.2 · S10.4, and there is **no
/// switcher at all until the first year close**).
final class CertifiedYear {
  /// Creates the record.
  const CertifiedYear({
    required this.year,
    required this.status,
    this.carriedForward = Paise.zero,
    this.verification,
  });

  /// The year.
  final FinancialYear year;

  /// [YearStatus.closed], or [YearStatus.uncertified] once a month inside it
  /// (or an earlier year) was re-opened (02 §8.1 🔒).
  final YearStatus status;

  /// The balance-sheet total this year hands to the next — the b/f of ADR
  /// 2026-09-09 §4 🔒, book-scoped here because S10.4 shows a whole book and
  /// not one A/C.
  final Paise carriedForward;

  /// This device's verification of that year's vector (ADR 2026-09-05c §3).
  final CloseVerification? verification;

  /// True when the badge reads *Certified* — copy, not a state (13 §6 🔒).
  bool get isCertified => status == YearStatus.closed;
}

/// The ledger, as S10.4 needs it.
///
/// Two reads and one write. Nothing here decides *whether* a year may close —
/// that is `yearClosePreconditions`, and an implementation calls it rather
/// than re-stating it.
abstract interface class YearCloseSource {
  /// Everything S10.4 draws for [bookId]'s [fy].
  ///
  /// Throws when the book or year is unknown — the screen shows its error
  /// state with a retry (13 §4.3), never a red screen.
  Future<YearCloseView> loadYearClose(String bookId, FinancialYear fy);

  /// Runs the ceremony for [bookId]'s [fy] (02 §8.1 🔒).
  ///
  /// Implementations call `yearClosePreconditions` first and throw
  /// [YearCloseRefused] when it is not empty — a refusal is an exception, not
  /// a silent no-op — then compute `closingVector` and publish the signed
  /// [YearClose] carrying it and the `projectorVersion`. Every other member's
  /// device recomputes and verifies it; this device's own reading comes back
  /// as [YearCloseResult.verification].
  Future<YearCloseResult> closeYear(String bookId, FinancialYear fy);

  /// Every year [bookId] has closed, **oldest first**.
  ///
  /// Empty until the first close, which is what makes ADR 2026-09-09 §4 🔒's
  /// *no switcher until the first year close* true by construction rather than
  /// by a flag the screen has to remember.
  Future<List<CertifiedYear>> certifiedYears(String bookId);
}

/// The [YearCloseSource] for the tree below — installed by the shell above the
/// router, so `closeRoutes` can build S10.4 from a path alone.
class YearCloseScope extends InheritedWidget {
  /// Creates the scope.
  const YearCloseScope({super.key, required this.source, required super.child});

  /// The implementation in force.
  final YearCloseSource source;

  /// The nearest scope, or null when the shell has not installed one yet —
  /// the screen then shows its error state rather than throwing (07 §1 rule
  /// 6: no dead ends, and no red screen either).
  static YearCloseSource? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<YearCloseScope>()?.source;

  @override
  bool updateShouldNotify(YearCloseScope old) => source != old.source;
}

/// The aged-advance warning, for callers building a [YearCloseView].
///
/// Re-exported so nothing in this feature has to reach for the month close's
/// file to name the one warning 02 §8.1 🔒 allows at the year boundary.
typedef YearCloseWarning = CloseWarningItem;

/// The warn-only kinds, as the month close already names them.
typedef YearCloseWarningKind = CloseWarning;
