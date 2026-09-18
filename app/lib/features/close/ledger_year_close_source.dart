// [YearCloseSource] over the real ledger — S10.4's source of truth (02 §8.1 🔒).
//
// The twin of `ledger_close_source.dart`, and a **composer** in the same way:
// every judgement on this screen belongs somewhere else and is carried here
// unchanged.
//
//   * what blocks — `LocalLedger.yearClosePreconditions`, which is the
//     engine's own `yearClosePreconditions` over the projected state unioned
//     with the mirror's gaps and `held` rows (02 §8.1 🔒, ADR 2026-09-05e §4);
//   * what the certificate carries — `LocalLedger.yearClosingVector`, which is
//     `closingVector` and nothing else (ADR 2026-09-05e §2 🔒). No closing
//     balance is derived in this file, and none may be: a second sum in the UI
//     layer is a second projector (03 §3.3 rule 2);
//   * what a close records — `LocalLedger.closeYear`, which publishes the
//     signed `year_close` envelope with `core_ledger.projectorVersion` and
//     reads this device's own [CloseVerification] back out of the rebuilt
//     projection (ADR 2026-09-05c §3 🔒);
//   * the years already certified — `LocalLedger.certifiedYears`, which is
//     empty until the first close and is therefore what makes ADR 2026-09-09
//     §4 🔒's *no FY switcher at all* true by construction.
//
// What it adds is only shape: the engine's blockers become [YearCloseBlocker]
// with a human label, the aged advances become [CloseWarningItem], and the two
// stay different types all the way to the widget (07 §13 🔒).
//
// Money is [Paise] end to end (CLAUDE.md rule 1).
import 'package:core_ledger/core_ledger.dart';

import '../../shared/ledger/local_ledger.dart';
import '../../shared/seams/closed_years.dart';
import 'close_source.dart' show CloseWarning, CloseWarningItem;
import 'ledger_close_source.dart' show defaultAdvanceAgeingDays;
import 'year_close_source.dart';

/// [YearCloseSource] backed by [LocalLedger].
final class LedgerYearCloseSource implements YearCloseSource {
  /// Creates the source over [ledger].
  const LedgerYearCloseSource(this.ledger);

  /// The ledger facade. One instance per app, installed by the shell.
  final LocalLedger ledger;

  @override
  Future<YearCloseView> loadYearClose(String bookId, FinancialYear fy) async {
    final chart = await ledger.chartOf(bookId);
    final book = await _book(bookId);
    final isBusiness = book?.type == BookType.business.name;

    final blockers = <YearCloseBlocker>[
      for (final b in await ledger.yearClosePreconditions(bookId, fy))
        YearCloseBlocker(
          item: b,
          label: await _labelFor(b, chart),
          // ⚠️ SPEC: the same gap `LedgerCloseSource` records — 07 §13 🔒 and
          // 07 §28 want the *phone's name*, and `author_gaps.author_device`
          // is a device id with no label anywhere in `packages/data`
          // (`DeviceCert` carries none either, 04 §3.4). Printing a uuid at a
          // shopkeeper is worse than saying *another phone*, so this stays
          // null until a device-name source exists.
          deviceName: null,
        ),
    ];

    final names = {for (final a in chart.accounts) a.id: a.name};
    final years = await ledger.certifiedYears(bookId);
    CertifiedYearRow? thisYear;
    for (final y in years) {
      if (y.year == fy) thisYear = y;
    }
    final status = thisYear?.status ?? YearStatus.open;

    // The vector is shown **before** the action (02 §8.1 🔒) — but only where
    // there are figures to show. A year still blocked on a missing phone has
    // no certifiable total, and an empty table would read as *nothing to carry
    // forward*, which is a different claim (07 §1 rule 12).
    YearCloseVector? preview;
    if (status == YearStatus.open) {
      final v = await ledger.yearClosingVector(bookId, fy);
      preview = YearCloseVector(vector: v, names: names);
    }
    final certified = thisYear?.vector;

    return YearCloseView(
      bookId: bookId,
      bookName: book?.name ?? '',
      financialYear: fy,
      status: status,
      blockers: blockers,
      warnings: await _agedAdvances(bookId),
      vector: preview,
      isBusiness: isBusiness,
      distributionPending: isBusiness && await _distributionPending(bookId, fy),
      certifiedVector: certified == null
          ? null
          : YearCloseVector(vector: certified, names: names),
      verification: thisYear?.verification,
      // ⚠️ SPEC: 02 §8.1 🔒 says a re-open voids the certificate, and 07 §13 🔒
      // wants the banner to name the month where it can — but nothing on the
      // facade reads back *which* `period_unlock` did the voiding (the
      // projection records the resulting `uncertified` status, not its cause).
      // Naming the wrong month would be worse than naming none, so this stays
      // null and the banner falls back to its month-less sentence. Recorded in
      // this lane's report.
      voidedBy: null,
      // ⚠️ SPEC: the same gap `LedgerCloseSource.loadClose` records — 13 §2.3.1's
      // read-only member is a *role*, and this app has no book-role source
      // yet. Reporting every reader as a closer would be the dangerous wrong;
      // reporting every reader as read-only would make the ceremony
      // unreachable. The conservative reading that keeps 07 §1 rule 6 is to
      // leave the gate to the ledger: the screen opens, and `closeYear` is the
      // thing that can refuse.
      readOnly: false,
    );
  }

  @override
  Future<YearCloseResult> closeYear(String bookId, FinancialYear fy) async {
    final ClosedYearResult closed;
    try {
      closed = await ledger.closeYear(bookId, fy);
    } on YearCertifyRefused catch (e) {
      // The engine's own items, not a message this file invented.
      throw YearCloseRefused(e.blockers);
    } on YearAlreadyClosed {
      // Not an error and not a failure to publish: the certificate is already
      // there. A refusal with nothing to list sends the screen back to a fresh
      // read, which shows it (07 §1 rule 6 — never a dead end).
      throw const YearCloseRefused([]);
    }
    return YearCloseResult(
      close: closed.close,
      verification: closed.verification,
    );
  }

  @override
  Future<List<CertifiedYear>> certifiedYears(String bookId) async => [
    for (final y in await ledger.certifiedYears(bookId))
      CertifiedYear(
        year: y.year,
        status: y.status,
        carriedForward: y.carriedForward,
        verification: y.verification,
      ),
  ];

  // ── labels and warnings ───────────────────────────────────────────────────

  /// A human label for what a blocker points at, or null — in which case the
  /// screen states the kind alone rather than an id. The same resolution
  /// `LedgerCloseSource` makes, kept in step with it deliberately.
  Future<String?> _labelFor(CloseBlockerItem b, Chart chart) async {
    switch (b.kind) {
      case CloseBlocker.reviewFlagOpen:
      case CloseBlocker.advancePending:
      case CloseBlocker.heldEnvelope:
        final entry = await ledger.entry(b.ref);
        return entry?.note;
      case CloseBlocker.suspenseNonZero:
        for (final a in chart.accounts) {
          if (a.id == b.ref) return a.name;
        }
        return null;
      case CloseBlocker.monthOpen:
      case CloseBlocker.authorGapOpen:
        // A month label is the ref itself; a device id has no name to give.
        return null;
    }
  }

  /// Aged advances — the one thing 02 §8.1 🔒 names as warn-only at the year
  /// boundary. The same window the month close uses, for the same reason.
  Future<List<CloseWarningItem>> _agedAdvances(String bookId) async => [
    for (final a in await ledger.openAdvances(bookId))
      if (a.ageDays >= defaultAdvanceAgeingDays)
        CloseWarningItem(
          kind: CloseWarning.agedAdvance,
          ref: a.accountId,
          label: a.accountName,
        ),
  ];

  /// True when this FY has a surplus that has not been distributed — what
  /// makes the **optional** *Distribute profit first* door worth offering
  /// (02 §8.1 🔒). It is a door to S14.1, which owns the wizard; nothing is
  /// divided here.
  ///
  /// The judgement is `distributionPreview`'s, not this file's: a refusal
  /// (not a shared book, no ratio in force, no Partner Current A/cs) means
  /// there is nothing to offer, and the headroom is the engine's own ceiling
  /// (02 §7.1 🔒, ADR 2026-09-05e §8). Anything it throws is read as *no
  /// door*: a missing optional door is never a dead end, and offering one that
  /// cannot be taken would be.
  Future<bool> _distributionPending(String bookId, FinancialYear fy) async {
    try {
      final preview = await ledger.distributionPreview(
        bookId,
        from: fy.firstDay,
        to: fy.lastDay,
      );
      return preview.refusal == null &&
          preview.netProfit.raw > 0 &&
          preview.headroom.raw > 0;
    } on Object {
      return false;
    }
  }

  Future<BooksPRow?> _book(String bookId) async {
    for (final b in await ledger.watchBooks().first) {
      if (b.id == bookId) return (id: b.id, name: b.name, type: b.type);
    }
    // The ceremony still opens and still says which year: a missing name is
    // not a dead end (07 §1 rule 6).
    return null;
  }
}

/// The two columns of `books_p` this file reads, so nothing else in
/// `features/close` has to know the drift row type.
typedef BooksPRow = ({String id, String name, String type});

/// [ClosedYearsSource] over the real ledger — the FY switcher's input on S4 and
/// S8.2 (ADR 2026-09-09 §4 🔒).
///
/// The seam asks for **one A/C's** carried-forward figure, and that is read out
/// of the year's own certified vector rather than recomputed: the b/f a
/// statement shows has to be the figure that was certified, not a sum this
/// screen made later (02 §9 — balances are derived once, 02 §8.1 🔒 — the
/// certified vector *is* the next year's opening).
///
/// An empty `accountId` — how S8.2 calls it, because a report is a whole book —
/// carries the book's balance-sheet total instead.
final class LedgerClosedYearsSource {
  /// Creates the source over [ledger].
  const LedgerClosedYearsSource(this.ledger);

  /// The ledger facade.
  final LocalLedger ledger;

  /// The [ClosedYearsSource] function itself, for the scope.
  Future<List<ClosedYear>> call(String bookId, String accountId) async => [
    for (final y in await ledger.certifiedYears(bookId))
      ClosedYear(
        year: y.year,
        carriedForwardPaise: accountId.isEmpty
            ? y.carriedForward.raw
            : y.carriedForwardFor(accountId).raw,
      ),
  ];
}
