// [LateArrivals] over the real ledger — what S6's late-arrivals section and
// S10.3 read and write through in the shipped app (02 §8 🔒, 07 §9, 07 §13 🔒,
// ADR 2026-09-05e §3 and §10).
//
// **The Inbox is one surface, so this tray is device-wide.** 07 §9 🔒 makes the
// Inbox the single place everything waiting for a person lands; a karta closing
// three books does not want three trays and the seam is deliberately book-less.
// So this adapter watches **every book this device holds**
// (`LocalLedger.watchBooks`), merges their trays into one list and gives each
// item its own `bookName` from that same read — no coupling to Home's
// `HomeScopeController`, whose selected book is a different question.
//
// It is a **composer**, not a decider. Every judgement is the ledger's:
//
//   * what is in the tray — `watchLateArrivals`, which reads the projector's
//     own `entries_p.status = 'in_tray'`. This file classifies nothing, and
//     nothing here may be drawn as money that has not moved: a late arrival
//     already counts in every live balance (02 §3 🔒);
//   * *Re-date to today* — `redateLateArrival`, an **amend** (02 §5, 02 §8):
//     identical lines, only the date moves;
//   * *Re-open {month}* — `unlockMonth`, one signed `period_unlock` envelope
//     carrying the reason, refused outright inside a closed FY because that
//     re-open is the structural act of 02 §7.2.1 🔒.
//
// Money is signed integer paise (CLAUDE.md rule 1).
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BooksPData;

import '../../shared/ledger/local_ledger.dart';
import 'late_arrivals.dart';

/// [LateArrivals] backed by [LocalLedger], across every book on this device.
final class LedgerLateArrivals implements LateArrivals {
  /// Creates the tray over [ledger] and starts watching.
  LedgerLateArrivals(this.ledger) {
    _books = ledger.watchBooks().listen(_onBooks, onError: _onError);
  }

  /// The ledger facade. One instance per app, installed by the shell.
  final LocalLedger ledger;

  final _controller = StreamController<LateArrivalsTray>.broadcast();
  final _trays = <String, List<LateArrivalItem>>{};
  final _subs = <String, StreamSubscription<List<LateArrival>>>{};
  final _names = <String, String>{};
  final _traySeq = <String, int>{};

  StreamSubscription<List<BooksPData>>? _books;
  LateArrivalsTray? _current;
  Object? _lastError;

  @override
  LateArrivalsTray? get current => _current;

  /// The tray as it changes, starting with the one standing now.
  ///
  /// It subscribes to the broadcast stream **before** replaying [current]: the
  /// obvious `async*` shape (`yield current; yield* stream`) drops any tray
  /// produced between the two, which would leave S6/S10.3 showing a card the
  /// ledger has already cleared — a tap that can now only be refused (07 §1
  /// rule 6).
  @override
  Stream<LateArrivalsTray> watch() {
    late final StreamController<LateArrivalsTray> out;
    StreamSubscription<LateArrivalsTray>? sub;
    out = StreamController<LateArrivalsTray>(
      onListen: () {
        final standing = _current;
        sub = _controller.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        if (standing != null) out.add(standing);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// A fresh read of every book's tray.
  ///
  /// The streams are live, so this is a re-read rather than the only load —
  /// what the error state's *Try again* needs (13 §4.3). It rethrows as
  /// [LateArrivalsFailure] so nothing below the seam ever carries plaintext
  /// financial data into an error (CLAUDE.md rule 4).
  @override
  Future<void> refresh() async {
    try {
      final books = await ledger.watchBooks().first;
      _names
        ..clear()
        ..addEntries([for (final b in books) MapEntry(b.id, b.name)]);
      _trays.removeWhere((id, _) => !_names.containsKey(id));
      for (final b in books) {
        _trays[b.id] = await _itemsOf(
          b.id,
          await ledger.watchLateArrivals(b.id).first,
        );
      }
      _lastError = null;
      _emit();
    } on Object catch (e) {
      throw LateArrivalsFailure('late arrivals unavailable: ${e.runtimeType}');
    }
  }

  @override
  Future<void> redateToToday(String entryId) async {
    try {
      await ledger.redateLateArrival(entryId);
    } on Object catch (e) {
      throw LateArrivalsFailure('re-date refused: ${e.runtimeType}');
    }
  }

  @override
  Future<void> reopenMonth({
    required String bookId,
    required YearMonth period,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'a re-open records why');
    }
    try {
      await ledger.unlockMonth(bookId, period, reason: reason);
    } on MonthUnlockRefused catch (e) {
      // A **state of the book**, not a failure — carried across as the seam's
      // own typed refusal so the screen says one plain sentence (07 §1 rule 6).
      throw ReopenRefused(
        switch (e.reason) {
          MonthUnlockRefusal.notLocked => ReopenRefusal.notLocked,
          MonthUnlockRefusal.closedYear => ReopenRefusal.closedYear,
        },
        closedYearLabel: e.reason == MonthUnlockRefusal.closedYear
            ? await _closedYearLabel(bookId, period)
            : null,
      );
    } on Object catch (e) {
      throw LateArrivalsFailure('re-open failed: ${e.runtimeType}');
    }
  }

  /// Stops watching every book.
  Future<void> dispose() async {
    await _books?.cancel();
    for (final s in _subs.values) {
      await s.cancel();
    }
    _subs.clear();
    await _controller.close();
  }

  // ── the merge ─────────────────────────────────────────────────────────────

  void _onBooks(List<BooksPData> rows) {
    final books = {for (final b in rows) b.id: b.name};
    _names
      ..clear()
      ..addAll(books);
    for (final id in _subs.keys.toList()) {
      if (books.containsKey(id)) continue;
      _subs.remove(id)?.cancel();
      _trays.remove(id);
    }
    for (final id in books.keys) {
      if (_subs.containsKey(id)) continue;
      _subs[id] = ledger
          .watchLateArrivals(id)
          .listen(
            (arrivals) => unawaited(_onTray(id, arrivals)),
            onError: _onError,
          );
    }
    _emit();
  }

  /// Rebuilds one book's cards.
  ///
  /// Building them is asynchronous (it reads the chart and the certified
  /// years), so two projections of the same book landing close together can
  /// build concurrently and finish out of order. The write is therefore
  /// token-guarded: a build the next one overtook is dropped rather than
  /// written over the newer answer, because an older tray standing would keep
  /// a card the ledger has already cleared — a tap that can now only be
  /// refused (07 §1 rule 6).
  Future<void> _onTray(String bookId, List<LateArrival> arrivals) async {
    if (!_names.containsKey(bookId)) return;
    final token = (_traySeq[bookId] ?? 0) + 1;
    _traySeq[bookId] = token;
    final items = await _itemsOf(bookId, arrivals);
    if (_traySeq[bookId] != token || !_names.containsKey(bookId)) return;
    _trays[bookId] = items;
    _lastError = null;
    _emit();
  }

  void _onError(Object error) {
    _lastError = error;
    // An error is never a silently empty tray: the last good snapshot stands
    // and `refresh()` is what the screen's *Try again* calls.
  }

  void _emit() {
    if (_controller.isClosed) return;
    final items = <LateArrivalItem>[for (final list in _trays.values) ...list]
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.entryId.compareTo(b.entryId);
      });
    // ⚠️ SPEC: 13 §2.3.1's read-only member is a *role* and this app has no
    // book-role source yet — the same gap `LedgerCloseSource` records. The
    // conservative reading that keeps 07 §1 rule 6 is to leave the gate to the
    // ledger: the screen opens, and `unlockMonth` is the thing that refuses.
    _current = LateArrivalsTray(items: List.unmodifiable(items));
    _controller.add(_current!);
  }

  /// What the last stream event failed with, for a caller that wants to know
  /// whether the standing snapshot is stale. Developer-facing only.
  Object? get lastError => _lastError;

  // ── one arrival → one card ────────────────────────────────────────────────

  Future<List<LateArrivalItem>> _itemsOf(
    String bookId,
    List<LateArrival> arrivals,
  ) async {
    if (arrivals.isEmpty) return const [];
    final name = _names[bookId] ?? '';
    final chart = await ledger.chartOf(bookId);
    final money = {
      for (final a in chart.accounts)
        if (a.isMoney) a.id,
    };
    final closedLabels = <YearMonth, String?>{};
    final out = <LateArrivalItem>[];
    for (final a in arrivals) {
      out.add(
        LateArrivalItem(
          entryId: a.entryId,
          bookId: bookId,
          bookName: name,
          lockedPeriod: a.lockedPeriod,
          date: a.accountingDate,
          paise: _signedPaise(a, money),
          fromLabel: _join(a.from),
          toLabel: _join(a.to),
          note: a.note,
          lockedOn: _dayOfHlc(a.lockedAtHlc),
          closedYear: closedLabels[a.lockedPeriod] ??= await _closedYearLabel(
            bookId,
            a.lockedPeriod,
          ),
        ),
      );
    }
    return out;
  }

  /// The movement **from the money A/C's own side**: + is money in, − is money
  /// out (02 §10 🔒 — the words beside it on S10.3 are *Money in / Money out*,
  /// never Dr/Cr).
  ///
  /// An entry with no money line — a party settled against a category, say —
  /// has no money side to read, so its magnitude is stated without a direction
  /// rather than a direction being invented.
  static int _signedPaise(LateArrival a, Set<String> money) {
    for (final l in a.lines) {
      if (money.contains(l.accountId)) return l.amount.raw;
    }
    return a.amount.raw;
  }

  static String _join(List<LateArrivalLine> lines) =>
      lines.map((l) => l.accountName).join(', ');

  /// The day the month locked, from the HLC the projection recorded against it
  /// (03 §1: 48 bits of physical milliseconds + a 16-bit counter).
  ///
  /// ⚠️ SPEC: the physical half is the **closer's** wall clock, read back here
  /// in this phone's own zone, so it is *the day this device says the lock
  /// landed* rather than a certified date — a lock envelope carries no
  /// accounting date of its own (02 §8 step 4). It is the honest answer to
  /// 07 §13 🔒's *when it locked*, and null (no lock row) still falls back to
  /// the card's date-less sentence.
  static LocalDate? _dayOfHlc(int? raw) {
    if (raw == null) return null;
    final ms = Hlc(raw).physicalMs;
    if (ms <= 0) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    return LocalDate(at.year, at.month, at.day);
  }

  /// The label of the **closed** FY [period] sits inside, or null.
  ///
  /// Pre-empting the refusal is what 07 §1 rule 6 asks for: the card must not
  /// offer a *Re-open* that can only be refused. The rule itself is the
  /// ledger's — a re-open is refused when [period]'s own FY **or any later
  /// one** is closed (02 §8.1 🔒) — and `certifiedYears` is where this device
  /// reads it.
  Future<String?> _closedYearLabel(String bookId, YearMonth period) async {
    try {
      final startMonth = await ledger.fyStartMonthOf(bookId);
      final fy = FinancialYear.of(period.firstDay, startMonth: startMonth);
      for (final y in await ledger.certifiedYears(bookId)) {
        if (y.status == YearStatus.closed &&
            !y.year.lastDay.isBefore(fy.firstDay)) {
          return y.year.label;
        }
      }
    } on Object {
      // Unknown is *not* "open": a null here leaves the tap available and the
      // ledger's own refusal is still the backstop the screen handles.
      return null;
    }
    return null;
  }
}
