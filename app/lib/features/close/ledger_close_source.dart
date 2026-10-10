// [CloseSource] over the real ledger — S10's source of truth (02 §8 🔒).
//
// It is a **composer**, not a decider. Every judgement on this screen belongs
// somewhere else and is carried here unchanged:
//
//   * what blocks — `LocalLedger.monthClosePreconditions`, which is the
//     engine's `monthLockPreconditions` over the projected state unioned with
//     the mirror's own gaps and `held` rows (02 §8 step 3 🔒, ADR
//     2026-09-05b §3–4, ADR 2026-09-05e §4);
//   * what the lock records — `LocalLedger.lockMonth`, which publishes the
//     projector's own canonical vector and `core_ledger.projectorVersion`
//     (02 §8 step 4 🔒, ADR 2026-09-05c §3). No hash is computed in this
//     file, and none may be;
//   * the figures — the live `balances` row and `lastCashCount`, the same
//     reads S1, S4 and S5.5 draw from, so steps 1–2 cannot disagree with the
//     screens the closer just came from (02 §9: balances are derived, never
//     stored twice). Step 4 declares the same row less what is dated after
//     the month ([_figures]), shown under a dated heading — the one figure
//     that is the month's rather than today's (02 §8 step 4 🔒).
//
// What it adds is only shape: the engine's blockers become [CloseBlockingItem]
// with a human label, the warn-only facts become [CloseWarningItem], and the
// two stay different types all the way to the widget (07 §13 🔒).
//
// Money is [Paise] end to end (CLAUDE.md rule 1).
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BooksPData;
import 'package:drift/drift.dart' show Variable;

import '../../shared/ledger/local_ledger.dart';
import 'close_source.dart';

/// The ageing window after which an open advance warns on the close tray.
///
/// ⚠️ SPEC: 02 §7 makes this configurable per book, default 15 days to the
/// holder then 30 to the approver, but `book_config` carries no such field
/// yet and the projector may not read settings (03 §3.3 rule 2). The
/// conservative reading is the **later** of the two published defaults: a
/// warning that appears a fortnight late is a smaller wrong than one that
/// nags every closer about a ten-day advance. Replace this with the book's
/// own window when `book_config` grows one.
const int defaultAdvanceAgeingDays = 30;

/// [CloseSource] backed by [LocalLedger].
final class LedgerCloseSource implements CloseSource {
  /// Creates the source over [ledger].
  const LedgerCloseSource(this.ledger);

  /// The ledger facade. One instance per app, installed by the shell.
  final LocalLedger ledger;

  @override
  Future<CloseView> loadClose(String bookId, YearMonth period) async {
    final chart = await ledger.chartOf(bookId);
    final accounts = await ledger.watchAccounts(bookId).first;
    final bookName = await _bookName(bookId);

    final figures = await _figures(bookId, period.lastDay);

    final cash = <CloseCashAccount>[];
    final banks = <CloseBankAccount>[];
    final unverified = <CloseWarningItem>[];

    for (final row in accounts) {
      final a = row.account;
      if (!a.isMoney || row.archived) continue;
      // Both figures from the one statement: today's, which steps 1–2 check
      // against the cash box and the bank, and the month-end one the lock
      // declares (02 §8 step 4 🔒) — see [_figures]. An A/C the statement
      // did not see (added between the two reads) has nothing dated at all.
      final f = figures[a.id] ?? (row.balancePaise, row.balancePaise);
      final live = Paise(f.$1);
      final monthEnd = Paise(f.$2);
      if (a.subtype == MoneySubtype.cash ||
          a.subtype == MoneySubtype.cashCollection) {
        // The row is a door to S5.5, which owns counting (02 §8.2 🔒); this
        // only needs to know whether a count landed inside the month.
        final last = await ledger.lastCashCount(a.id);
        final counted = last != null && period.contains(last.date);
        cash.add(
          CloseCashAccount(
            accountId: a.id,
            name: a.name,
            bookBalance: live,
            monthEndBalance: monthEnd,
            lastCountDate: last?.date,
            countedInPeriod: counted,
          ),
        );
        if (!counted) {
          unverified.add(
            CloseWarningItem(
              kind: CloseWarning.unverifiedCount,
              ref: a.id,
              label: a.name,
            ),
          );
        }
      } else {
        banks.add(
          CloseBankAccount(
            accountId: a.id,
            name: a.name,
            bookBalance: live,
            monthEndBalance: monthEnd,
          ),
        );
      }
    }

    final blocks = await _blocks(bookId, period, chart);
    final warns = <CloseWarningItem>[
      ...await _agedAdvances(bookId),
      ...unverified,
    ];

    final saved = await ledger.closeProgress(bookId, period);
    return CloseView(
      bookId: bookId,
      bookName: bookName,
      period: period,
      cashAccounts: cash,
      bankAccounts: banks,
      tray: CloseTray(blocks: blocks, warns: warns),
      progress: _progressOf(saved),
      // ⚠️ SPEC: 13 §2.3.1's read-only member is a *role*, and this app has no
      // book-role source yet (the same gap `LocalLedger.transferBetweenBooks`
      // names). Reporting every reader as a closer would be the dangerous
      // wrong; reporting every reader as read-only would make the wizard
      // unreachable. The conservative reading that keeps 07 §1 rule 6 (no
      // dead ends) is to leave the gate to the ledger: the wizard opens, and
      // `lockMonth` is the thing that can refuse.
      readOnly: false,
    );
  }

  @override
  Future<void> saveProgress(
    String bookId,
    YearMonth period,
    CloseProgress progress,
  ) => ledger.saveCloseProgress(
    bookId,
    period,
    SavedCloseProgress(
      step: progress.step.name,
      confirmedAccountIds: progress.confirmedBankIds,
    ),
  );

  @override
  Future<CloseLockResult> lock({
    required String bookId,
    required YearMonth period,
    required Map<String, Paise> declaredBalances,
  }) async {
    final LockedMonth locked;
    try {
      locked = await ledger.lockMonth(
        bookId,
        period,
        declaredBalances: declaredBalances,
      );
    } on MonthLockRefused catch (e) {
      // The engine's own items, not a message this file invented.
      throw CloseRefused(e.blockers);
    }
    // The wizard is over: a closed month must not resume one.
    await ledger.clearCloseProgress(bookId, period);
    return CloseLockResult(
      lock: locked.lock,
      verification: locked.verification,
    );
  }

  // ── the tray ──────────────────────────────────────────────────────────────

  Future<List<CloseBlockingItem>> _blocks(
    String bookId,
    YearMonth period,
    Chart chart,
  ) async {
    final out = <CloseBlockingItem>[];
    for (final b in await ledger.monthClosePreconditions(bookId, period)) {
      out.add(
        CloseBlockingItem(
          kind: b.kind,
          ref: b.ref,
          label: await _labelFor(b, chart),
          // ⚠️ SPEC: 07 §13 🔒 and 07 §28 want S10.5 to **name the phone**
          // whose entries have not arrived. `author_gaps.author_device` is a
          // device id and no table in `packages/data` carries a device label
          // — `DeviceCert` has none either (04 §3.4). Printing a uuid at a
          // shopkeeper is worse than saying *another phone*, so this stays
          // null until a device-name source exists.
          deviceName: null,
        ),
      );
    }
    return out;
  }

  /// A human label for what a blocker points at, or null — in which case the
  /// screen states the kind alone rather than an id.
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

  Future<List<CloseWarningItem>> _agedAdvances(String bookId) async => [
    for (final a in await ledger.openAdvances(bookId))
      if (a.ageDays >= defaultAdvanceAgeingDays)
        CloseWarningItem(
          kind: CloseWarning.agedAdvance,
          ref: a.accountId,
          label: a.accountName,
        ),
  ];

  /// The saved step, resolved back to a [CloseStep].
  ///
  /// An unknown name — progress written by a build that named its steps
  /// differently — restarts the wizard rather than crashing it: the figures
  /// are all re-read anyway, so the cost is a few taps (07 §1 rule 6).
  static CloseProgress _progressOf(SavedCloseProgress? saved) {
    if (saved == null) return const CloseProgress();
    for (final step in CloseStep.values) {
      if (step.name == saved.step) {
        return CloseProgress(
          step: step,
          confirmedBankIds: saved.confirmedAccountIds,
        );
      }
    }
    return CloseProgress(confirmedBankIds: saved.confirmedAccountIds);
  }

  /// Per account of [bookId]: `(live, monthEnd)` signed paise — the live
  /// `balances` figure, and that figure less what the **counted** entries
  /// dated after [lastDay] moved.
  ///
  /// Why the declared figure is as of the period's last day: 02 §8 🔒 has a
  /// late arrival count in every live balance "but leave the certified month
  /// untouched", and the year close the month closes feed (02 §8.1 🔒) is
  /// restricted to `accounting_date` ≤ the last day regardless of HLC.
  /// Closing August on 3 Sep with the live balance would certify September's
  /// money as August's (PLAN desk 200 (e)).
  ///
  /// Why steps 1–2 still show the live figure: step 1 counts the cash that is
  /// in the box *today* and S5.5 posts its adjustment from the live balance,
  /// and step 2 checks against "the bank's app/statement" (02 §8 step 2 🔒),
  /// which show today's balance. Live and month-end differ only by entries
  /// that are in the book, so confirming the one confirms the other; the
  /// screen shows the month-end figure beside the live one whenever they
  /// differ, and step 4's heading is dated.
  ///
  /// ⚠️ SPEC: 02 §8 step 4 says "the declared balances" without spelling out
  /// *as of when*; this is the reading the two 🔒 lines above force, and the
  /// conservative one — owner to confirm.
  ///
  /// Why it subtracts rather than sums: `balances` is the projector's live
  /// figure, which already includes a certified seed vector when the book was
  /// rebuilt from one (03 §3.3 rule 3) — a sum over `entry_lines_p` alone
  /// would lose that seed. The data layer's own invariant is
  /// `balances = seed + Σ entry_lines_p of entries in ('posted','void')`
  /// (`Recompute.verifyBalances`, ADR 05c §6), so taking the post-period part
  /// of that same sum back off is exact and derives no balance of its own
  /// (02 §9). No `packages/data` or `core_ledger` read answers *balance of a
  /// money A/C at date D* for a month (`closingVector` is per FY), which is
  /// why this one query lives here.
  ///
  /// Why **one statement**: Recompute rewrites `balances` and `entry_lines_p`
  /// together in its own transaction (recompute.dart). Two separate reads
  /// could straddle a rebuild — a sync pull landing while S10 loads — and
  /// subtract a post-rebuild sum from a pre-rebuild balance, a figure that is
  /// neither live nor as-of and would then be signed. A single SQLite
  /// statement reads one snapshot, so the pair is always consistent.
  Future<Map<String, (int, int)>> _figures(
    String bookId,
    LocalDate lastDay,
  ) async {
    final rows = await ledger.db
        .customSelect(
          'SELECT a.id AS a, COALESCE(b.balance_paise, 0) AS live, '
          'COALESCE((SELECT SUM(l.amount_paise) FROM entry_lines_p l '
          'JOIN entries_p e ON e.id = l.entry_id '
          'WHERE l.book_id = a.book_id AND l.account_id = a.id '
          'AND e.accounting_date > ?2 '
          "AND e.status IN ('posted','void')), 0) AS after "
          'FROM accounts_p a LEFT JOIN balances b ON b.account_id = a.id '
          'WHERE a.book_id = ?1',
          variables: [
            Variable.withString(bookId),
            Variable.withString(lastDay.toIso()),
          ],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('a'): (
          r.read<int>('live'),
          r.read<int>('live') - r.read<int>('after'),
        ),
    };
  }

  Future<String> _bookName(String bookId) async {
    for (final b in await ledger.watchBooks().first) {
      if (b.id == bookId) return b.name;
    }
    // The wizard still opens and still says which month: a missing name is
    // not a dead end (07 §1 rule 6).
    return '';
  }

  // ── S10.1 · every book's state (07 §13 🔒) ────────────────────────────────

  @override
  Future<List<BookCloseStatus>> closeStatuses(YearMonth upTo) async {
    final db = ledger.db;
    final books = await ledger.watchBooks().first;

    // Three cheap projection reads, once each, rather than one per book: this
    // runs behind the Home card on every build, and `monthClosePreconditions`
    // replays a book's envelopes. The two facts that decide *waiting* —
    // `author_gaps` and a `held` envelope — are exactly what the mirror
    // records, and they are what S10.5 is raised on (ADR 2026-09-05b §3–4,
    // ADR 2026-09-05e §4). The wizard still asks the engine before the lock;
    // this only decides a status line.
    final locked = <String, Set<int>>{};
    for (final p in await (db.select(
      db.periodsP,
    )..where((t) => t.state.equals('locked'))).get()) {
      (locked[p.bookId] ??= <int>{}).add(p.year * 12 + p.month);
    }
    final waiting = <String>{};
    for (final g in await db.select(db.authorGaps).get()) {
      waiting.add(g.bookId);
    }
    for (final h in await (db.select(
      db.envelopesLocal,
    )..where((t) => t.held.equals(1))).get()) {
      waiting.add(h.bookId);
    }

    final out = <BookCloseStatus>[];
    for (final b in books) {
      final start = await _firstMonth(b.id, b.startDate);
      // A book that began after the month asked for has nothing to close, so
      // it carries no card and no S10.1 line — rather than a line offering a
      // month that predates the book (ADR 2026-09-09d §4).
      if (start == null || start.compareTo(upTo) > 0) continue;
      final mine = locked[b.id] ?? const <int>{};
      final period = _firstOpenMonth(start, upTo, mine);
      if (period == null) {
        out.add(
          BookCloseStatus(
            bookId: b.id,
            bookName: b.name,
            period: upTo,
            state: BookCloseState.closed,
          ),
        );
        continue;
      }
      final saved = await ledger.closeProgress(b.id, period);
      final step = saved == null ? null : _progressOf(saved).step;
      out.add(
        BookCloseStatus(
          bookId: b.id,
          bookName: b.name,
          period: period,
          // *Waiting* is the headline over *in progress*: the karta needs to
          // know who he is waiting for (07 §13 🔒). The saved step rides
          // along in [step], so the card still says *resumes*.
          state: waiting.contains(b.id)
              ? BookCloseState.waiting
              : step == null
              ? BookCloseState.notStarted
              : BookCloseState.inProgress,
          // ⚠️ SPEC: the same gap as `_blocks` — `author_gaps.author_device`
          // is an id and nothing carries a device label (04 §3.4), so the
          // screen says *another phone* rather than printing a uuid.
          step: step,
        ),
      );
    }
    return out;
  }

  /// The first month this book could ever close: the day the books begin
  /// (ADR 2026-09-09d §4), or the earliest entry when the book predates that
  /// column. Null when the book holds nothing at all.
  Future<YearMonth?> _firstMonth(String bookId, String? startDate) async {
    if (startDate != null) {
      final d = LocalDate.parse(startDate);
      return YearMonth(d.year, d.month);
    }
    final db = ledger.db;
    final rows = await db
        .customSelect(
          'SELECT MIN(accounting_date) AS first FROM entries_p '
          'WHERE book_id = ?1 AND superseded_by IS NULL '
          "AND status NOT IN ('pending','rejected')",
          variables: [Variable.withString(bookId)],
          readsFrom: {db.entriesP},
        )
        .get();
    final first = rows.isEmpty ? null : rows.first.read<String?>('first');
    if (first == null) return null;
    final d = LocalDate.parse(first);
    return YearMonth(d.year, d.month);
  }

  /// The earliest month from [start] through [upTo] that is not locked, or
  /// null when every one of them is. Months lock in order (02 §8.1 🔒), so
  /// this — not [upTo] — is the month the card offers.
  static YearMonth? _firstOpenMonth(
    YearMonth start,
    YearMonth upTo,
    Set<int> locked,
  ) {
    var m = start;
    while (m.compareTo(upTo) <= 0) {
      if (!locked.contains(m.year * 12 + m.month)) return m;
      m = m.next;
    }
    return null;
  }

  // ── S10.2 · the month summary (07 §13 🔒) ─────────────────────────────────

  @override
  Future<MonthSummary> monthSummary(String bookId, YearMonth period) async {
    final books = await ledger.watchBooks().first;
    String name = '';
    String? tenantId;
    for (final b in books) {
      if (b.id == bookId) {
        name = b.name;
        tenantId = b.tenantId;
      }
    }
    final totals = await _inOut(bookId, period);
    return MonthSummary(
      bookId: bookId,
      bookName: name,
      period: period,
      moneyIn: totals.$1,
      moneyOut: totals.$2,
      topExpenses: await _topExpenses(bookId, period),
      subFamilies: tenantId == null
          ? const []
          : await _subFamilies(tenantId, period, books),
    );
  }

  /// The month's income against its expense, both as **positive** paise.
  ///
  /// Income accounts carry credit balances and expense accounts debit ones,
  /// so the sign is flipped for income and kept for expense — the engine's
  /// convention is read, never bent (02 §10 🔒). The row filter is the
  /// projection's own (02 §9), the same one Home reads.
  Future<(Paise, Paise)> _inOut(String bookId, YearMonth period) async {
    final db = ledger.db;
    final rows = await db
        .customSelect(
          'SELECT a.class AS klass, SUM(l.amount_paise) AS total '
          'FROM entry_lines_p l '
          'JOIN entries_p e ON e.id = l.entry_id '
          'JOIN accounts_p a ON a.id = l.account_id '
          'WHERE l.book_id = ?1 AND l.accounting_date >= ?2 '
          'AND l.accounting_date <= ?3 '
          "AND e.superseded_by IS NULL "
          "AND e.status NOT IN ('pending','rejected') "
          "AND a.class IN ('category_income','category_expense') "
          'GROUP BY a.class',
          variables: [
            Variable.withString(bookId),
            Variable.withString(period.firstDay.toIso()),
            Variable.withString(period.lastDay.toIso()),
          ],
          readsFrom: {db.entriesP, db.entryLinesP, db.accountsP},
        )
        .get();
    var income = 0, expense = 0;
    for (final r in rows) {
      final total = r.read<int?>('total') ?? 0;
      if (r.read<String>('klass') == 'category_income') {
        income += -total;
      } else {
        expense += total;
      }
    }
    return (Paise(income), Paise(expense));
  }

  /// The three largest expenses of the month, largest first (07 §13 🔒).
  Future<List<MonthSummaryExpense>> _topExpenses(
    String bookId,
    YearMonth period,
  ) async {
    final db = ledger.db;
    final rows = await db
        .customSelect(
          'SELECT a.id AS id, a.name AS name, SUM(l.amount_paise) AS total '
          'FROM entry_lines_p l '
          'JOIN entries_p e ON e.id = l.entry_id '
          'JOIN accounts_p a ON a.id = l.account_id '
          'WHERE l.book_id = ?1 AND l.accounting_date >= ?2 '
          'AND l.accounting_date <= ?3 '
          "AND e.superseded_by IS NULL "
          "AND e.status NOT IN ('pending','rejected') "
          "AND a.class = 'category_expense' "
          'GROUP BY a.id, a.name HAVING SUM(l.amount_paise) > 0 '
          'ORDER BY total DESC, a.name LIMIT 3',
          variables: [
            Variable.withString(bookId),
            Variable.withString(period.firstDay.toIso()),
            Variable.withString(period.lastDay.toIso()),
          ],
          readsFrom: {db.entriesP, db.entryLinesP, db.accountsP},
        )
        .get();
    return [
      for (final r in rows)
        MonthSummaryExpense(
          accountId: r.read<String>('id'),
          name: r.read<String>('name'),
          amount: Paise(r.read<int>('total')),
        ),
    ];
  }

  /// Each sub-family's month, in a joint family (07 §13 🔒).
  ///
  /// ⚠️ SPEC: 02 §1.1 🔒 lists the book types as `personal · family · joint ·
  /// business · organization` — there is **no sub-family type**, and books
  /// never nest, so no column says which books are the sub-families of a
  /// joint household. The conservative reading is the one that cannot invent
  /// a hierarchy: the tenant's `family` books *are* the sub-families, and the
  /// section appears only when there is more than one of them (a single
  /// family book is the household itself, not a sub-family of anything).
  /// Recorded as an open item; if the owner wants a real hierarchy it needs a
  /// parent on the book object, which is 02's to say and not this file's.
  Future<List<SubFamilyTotal>> _subFamilies(
    String tenantId,
    YearMonth period,
    List<BooksPData> books,
  ) async {
    final family = [
      for (final b in books)
        if (b.tenantId == tenantId && b.type == 'family') b,
    ];
    if (family.length < 2) return const [];
    final out = <SubFamilyTotal>[];
    for (final b in family) {
      final totals = await _inOut(b.id, period);
      out.add(
        SubFamilyTotal(
          bookId: b.id,
          name: b.name,
          moneyIn: totals.$1,
          moneyOut: totals.$2,
        ),
      );
    }
    return out;
  }
}
