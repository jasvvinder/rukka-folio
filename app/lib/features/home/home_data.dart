// What S1 Home needs from the local projection, in one live snapshot.
//
// The Home surface is 02 §9 rendered whole: money accounts with signed
// balances, You-will-get / You-will-give, open advances, in-transit, and
// this month's income against expense — "one screen, all live-computed,
// correct offline". [LocalLedger.watchPosition] (02 §9, F1-02-8) already owns
// the position card itself; the three figures Home adds around it — the
// trial-balance difference behind the verification card, today's day book,
// and the this-month In/Out line — have no stream on the facade, so they are
// read here from the same projection tables the facade reads (`entries_p`,
// `entry_lines_p`, 03 §3.2). This is read-side rendering only: no posting
// rule is re-implemented, and every figure stays integer paise.
//
// The row filter is the projection's own (02 §9): heads of accepted amend
// chains (`superseded_by IS NULL`), advance requests still `pending`
// excluded, `rejected` excluded — a reversed entry and its reversal both
// count, and `review_state` never changes a balance (02 §3).
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show QueryRow, Variable;

import '../../shared/ledger/local_ledger.dart';

/// One line of an entry as Home reads it — account plus signed paise.
final class HomeLine {
  /// Creates the line.
  const HomeLine({required this.accountId, required this.amountPaise});

  /// Account.
  final String accountId;

  /// Signed integer paise (+ = Dr).
  final int amountPaise;
}

/// One row of the Today list (13 §4.1 pattern P1).
final class HomeEntryRow {
  /// Creates the row.
  const HomeEntryRow({
    required this.entryId,
    required this.kind,
    required this.reviewState,
    required this.hlc,
    required this.lines,
    this.note,
  });

  /// Entry.
  final String entryId;

  /// Verb (02 §2).
  final EntryKind kind;

  /// `none | open | approved | rejected` (03 §3.3.5). Only `open` draws the
  /// amber clock (02 §3) — the entry counts in every balance regardless.
  final String reviewState;

  /// Entry HLC — the tie-break that makes "newest first" deterministic.
  final int hlc;

  /// The entry's posting lines, in line order.
  final List<HomeLine> lines;

  /// The user's own words.
  final String? note;

  /// True while the entry carries an open review flag (07 §4 amber clock).
  bool get underReview => reviewState == 'open';
}

/// Everything S1 renders, recomputed on every projection change.
final class HomeSnapshot {
  /// Creates the snapshot.
  const HomeSnapshot({
    required this.position,
    required this.accounts,
    required this.today,
    required this.monthInPaise,
    required this.monthOutPaise,
    required this.entryCount,
    required this.differencePaise,
    required this.health,
  });

  /// The position card (02 §9), straight from the facade.
  final Position position;

  /// Every account of the book with its live balance.
  final List<AccountBalance> accounts;

  /// Today's entries, newest first (07 §4).
  final List<HomeEntryRow> today;

  /// This month's income, as a positive figure (02 §9).
  final int monthInPaise;

  /// This month's expense, as a positive figure (02 §9).
  final int monthOutPaise;

  /// Entries in the book at all — zero is the new-user empty state (07 §4).
  final int entryCount;

  /// Σ every account balance. Double entry makes this nil; anything else is
  /// what the verification card reports **in plain words** (07 §4 🔒, 02 §8).
  final int differencePaise;

  /// Projection health, or null before the book has been projected.
  final BookHealth? health;

  /// The verification card's own state (07 §4 🔒).
  bool get booksBalanced =>
      differencePaise == 0 && (health?.integrityOk ?? true);

  /// The position card carries a *provisional* badge while an author gap is
  /// open (13 §4.1 P2, 07 §1 rule 7).
  bool get provisional => health?.isProvisional ?? false;

  /// Accounts by id — the label source for every row Home draws.
  Map<String, Account> get accountsById => {
    for (final a in accounts) a.account.id: a.account,
  };
}

/// The live Home snapshot for [bookId].
///
/// [today] and [month] are passed in rather than read from a clock here, so a
/// caller (and a test) decides what "today" means; the ledger's own injected
/// clock is the app's source for both (CLAUDE.md rule 3).
Stream<HomeSnapshot> watchHome(
  LocalLedger ledger,
  String bookId, {
  required LocalDate today,
  required YearMonth month,
}) =>
    _combine([
      ledger.watchPosition(bookId),
      ledger.watchAccounts(bookId),
      _watchDay(ledger, bookId, today),
      _watchMonth(ledger, bookId, month),
      _watchEntryCount(ledger, bookId),
      _nullFirst(ledger.watchHealth(bookId)),
    ]).map((v) {
      final accounts = v[1]! as List<AccountBalance>;
      final totals = v[3]! as _MonthTotals;
      return HomeSnapshot(
        position: v[0]! as Position,
        accounts: accounts,
        today: v[2]! as List<HomeEntryRow>,
        monthInPaise: totals.inPaise,
        monthOutPaise: totals.outPaise,
        entryCount: v[4]! as int,
        differencePaise: accounts.fold(0, (s, a) => s + a.balancePaise),
        health: v[5] as BookHealth?,
      );
    });

/// Today's entries with their lines, newest first (07 §4).
Stream<List<HomeEntryRow>> _watchDay(
  LocalLedger ledger,
  String bookId,
  LocalDate date,
) {
  final db = ledger.db;
  final q = db.customSelect(
    'SELECT e.id, e.kind, e.review_state, e.hlc, e.note, '
    'l.account_id, l.amount_paise '
    'FROM entries_p e JOIN entry_lines_p l ON l.entry_id = e.id '
    'WHERE e.book_id = ?1 AND e.accounting_date = ?2 '
    "AND e.superseded_by IS NULL AND e.status NOT IN ('pending','rejected') "
    'ORDER BY e.hlc DESC, e.id DESC, l.line_index',
    variables: [Variable.withString(bookId), Variable.withString(date.toIso())],
    readsFrom: {db.entriesP, db.entryLinesP},
  );
  return q.watch().map((rows) {
    final order = <String>[];
    final heads = <String, QueryRow>{};
    final lines = <String, List<HomeLine>>{};
    for (final r in rows) {
      final id = r.read<String>('id');
      if (!heads.containsKey(id)) {
        heads[id] = r;
        lines[id] = [];
        order.add(id);
      }
      lines[id]!.add(
        HomeLine(
          accountId: r.read<String>('account_id'),
          amountPaise: r.read<int>('amount_paise'),
        ),
      );
    }
    return [
      for (final id in order)
        HomeEntryRow(
          entryId: id,
          kind: EntryKind.parse(heads[id]!.read<String>('kind')),
          reviewState: heads[id]!.read<String>('review_state'),
          hlc: heads[id]!.read<int>('hlc'),
          note: heads[id]!.read<String?>('note'),
          lines: lines[id]!,
        ),
    ];
  });
}

final class _MonthTotals {
  const _MonthTotals(this.inPaise, this.outPaise);

  final int inPaise;
  final int outPaise;
}

/// This month's income against expense (02 §9), both as positive paise.
///
/// Income accounts carry credit balances and expense accounts debit ones, so
/// the sign is flipped for income and kept for expense — the engine's
/// convention is read, never bent (02 §10 🔒).
Stream<_MonthTotals> _watchMonth(
  LocalLedger ledger,
  String bookId,
  YearMonth month,
) {
  final db = ledger.db;
  final q = db.customSelect(
    'SELECT a.class AS klass, SUM(l.amount_paise) AS total '
    'FROM entry_lines_p l '
    'JOIN entries_p e ON e.id = l.entry_id '
    'JOIN accounts_p a ON a.id = l.account_id '
    'WHERE l.book_id = ?1 AND l.accounting_date >= ?2 '
    'AND l.accounting_date <= ?3 '
    "AND e.superseded_by IS NULL AND e.status NOT IN ('pending','rejected') "
    "AND a.class IN ('category_income','category_expense') "
    'GROUP BY a.class',
    variables: [
      Variable.withString(bookId),
      Variable.withString(month.firstDay.toIso()),
      Variable.withString(month.lastDay.toIso()),
    ],
    readsFrom: {db.entriesP, db.entryLinesP, db.accountsP},
  );
  return q.watch().map((rows) {
    var income = 0, expense = 0;
    for (final r in rows) {
      final total = r.read<int?>('total') ?? 0;
      if (r.read<String>('klass') == 'category_income') {
        income += -total;
      } else {
        expense += total;
      }
    }
    return _MonthTotals(income, expense);
  });
}

/// How many entries the book holds at all — zero is the setup checklist.
Stream<int> _watchEntryCount(LocalLedger ledger, String bookId) {
  final db = ledger.db;
  final q = db.customSelect(
    'SELECT COUNT(*) AS n FROM entries_p WHERE book_id = ?1 '
    "AND superseded_by IS NULL AND status NOT IN ('pending','rejected')",
    variables: [Variable.withString(bookId)],
    readsFrom: {db.entriesP},
  );
  return q.watch().map((rows) => rows.isEmpty ? 0 : rows.first.read<int>('n'));
}

/// [s] with a leading `null`, so a stream that emits nothing until the book is
/// projected ([LocalLedger.watchHealth]) never holds the whole snapshot back.
Stream<T?> _nullFirst<T extends Object>(Stream<T> s) async* {
  yield null;
  yield* s;
}

/// Emits once every input has produced a value, then on every later change.
Stream<List<Object?>> _combine(List<Stream<Object?>> sources) {
  final latest = List<Object?>.filled(sources.length, null);
  final seen = List<bool>.filled(sources.length, false);
  late final StreamController<List<Object?>> out;
  final subs = <StreamSubscription<Object?>>[];
  out = StreamController<List<Object?>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        final index = i;
        subs.add(
          sources[i].listen((v) {
            latest[index] = v;
            seen[index] = true;
            if (seen.every((x) => x)) out.add(List<Object?>.of(latest));
          }, onError: out.addError),
        );
      }
    },
    // Deliberately NOT `async`: returning a Future here makes widget disposal
    // await it, and a drift query stream's cancel only completes on a real
    // event-loop turn — which never arrives inside flutter_test's fake-async
    // zone, so the teardown deadlocks (F1-07-49 hung for the full 10-minute
    // test timeout). The subscriptions are still cancelled; nothing needs to
    // observe when that finishes.
    onCancel: () {
      for (final s in subs) {
        unawaited(s.cancel());
      }
      subs.clear();
    },
  );
  return out.stream;
}
