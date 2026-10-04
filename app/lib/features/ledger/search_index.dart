// S21 Search — what it searches and how (07 §25 🔒 ⟦tests: F1-07-35⟧:
// "search across accounts, parties and notes in scope; results are P1 rows").
//
// Read side only, and only through the read APIs this feature already
// consumes: [LocalLedger.watchAccounts] for accounts and parties (a party *is*
// an account of class `party`, 02 §1.2) and [LocalLedger.watchEntries] — one
// book-wide query — for the notes. That read lists exactly the entries the
// statements list (heads of amend chains; pending/rejected advance requests
// excluded — the same set S4 lists). No query is written here and
// `packages/data` is not touched.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart' hide StatementRow;

import '../../shared/ledger/local_ledger.dart';

/// One posting line of a note hit: the account and its signed paise
/// (+ = Dr, the engine's sign).
typedef SearchLine = ({String accountId, int amountPaise});

/// An entry carrying a note (the user's own words, 13 §4.1 P1 second line).
final class NoteHit {
  /// Creates the hit.
  const NoteHit({
    required this.entryId,
    required this.date,
    required this.hlc,
    required this.kind,
    required this.note,
    required this.reviewState,
    required this.lines,
  });

  /// Entry.
  final String entryId;

  /// `accounting_date`.
  final LocalDate date;

  /// HLC — the tie-break that makes "newest first" deterministic.
  final int hlc;

  /// Verb.
  final EntryKind kind;

  /// The note, as typed.
  final String note;

  /// `none | open | approved | rejected` (03 §3.3.5).
  final String reviewState;

  /// Every posting line of the entry.
  final List<SearchLine> lines;

  /// True while the review flag is open — the entry counts either way (02 §3).
  bool get underReview => reviewState == 'open';
}

/// Everything S21 searches over, for one book.
final class LedgerSearchIndex {
  /// Creates the index.
  LedgerSearchIndex({required this.accounts, required this.notes})
    : chart = {for (final a in accounts) a.account.id: a.account};

  /// Every account of the book with its live balance (archived included —
  /// the chart labels need them; [searchLedger] leaves them out of results).
  final List<AccountBalance> accounts;

  /// Every head entry that carries a non-blank note, newest first.
  final List<NoteHit> notes;

  /// Account lookup for row labels.
  final Map<String, Account> chart;
}

/// What one query found, grouped by type (DESIGN-PACK S21: "results grouped
/// by type"; names first, because a name is usually what is being looked
/// for).
final class LedgerSearchResults {
  /// Creates the results.
  const LedgerSearchResults({
    required this.parties,
    required this.accounts,
    required this.notes,
  });

  /// No results.
  static const none = LedgerSearchResults(parties: [], accounts: [], notes: []);

  /// Party accounts whose name matches, A–Z.
  final List<AccountBalance> parties;

  /// Every other account whose name matches, A–Z.
  final List<AccountBalance> accounts;

  /// Entries whose note matches, newest first.
  final List<NoteHit> notes;

  /// True when nothing matched.
  bool get isEmpty => parties.isEmpty && accounts.isEmpty && notes.isEmpty;
}

/// The query as matched: trimmed, case-folded. Gurmukhi and Devanagari have
/// no case, so folding leaves them as typed.
String normaliseQuery(String query) => query.trim().toLowerCase();

/// Runs [query] over [index]. A blank query matches nothing — S21 shows its
/// empty-query state instead of every account in the book.
///
/// Archived accounts are left out, exactly as S3 leaves them out of the index
/// (07 §6) — search is the fast path to the same khatas, not a second list.
LedgerSearchResults searchLedger(LedgerSearchIndex index, String query) {
  final q = normaliseQuery(query);
  if (q.isEmpty) return LedgerSearchResults.none;
  int byName(AccountBalance a, AccountBalance b) =>
      a.account.name.toLowerCase().compareTo(b.account.name.toLowerCase());
  final named = [
    for (final a in index.accounts)
      if (!a.archived && a.account.name.toLowerCase().contains(q)) a,
  ]..sort(byName);
  return LedgerSearchResults(
    parties: [
      for (final a in named)
        if (a.account.accountClass == AccountClass.party) a,
    ],
    accounts: [
      for (final a in named)
        if (a.account.accountClass != AccountClass.party) a,
    ],
    notes: [
      for (final n in index.notes)
        if (n.note.toLowerCase().contains(q)) n,
    ],
  );
}

/// The line whose signed paise a note hit shows — the money account's own
/// view (+ = money came in), the same rule as the Home Today P1 row
/// (`features/home/widgets/home_cards.dart` `HomeTodayRow.amountLine`): a
/// transfer shows its destination leg; an entry with no money leg falls back
/// to the party line seen from the user's side; failing both, the first line.
SearchLine? amountLineOf(NoteHit hit, Map<String, Account> chart) {
  final money = [
    for (final l in hit.lines)
      if (chart[l.accountId]?.accountClass == AccountClass.money) l,
  ];
  if (money.isNotEmpty) {
    if (hit.kind == EntryKind.transfer) {
      return money.firstWhere(
        (l) => l.amountPaise > 0,
        orElse: () => money.first,
      );
    }
    return money.first;
  }
  for (final l in hit.lines) {
    if (chart[l.accountId]?.accountClass == AccountClass.party) {
      return (accountId: l.accountId, amountPaise: -l.amountPaise);
    }
  }
  return hit.lines.isEmpty ? null : hit.lines.first;
}

/// The index over one book's [accounts] and [entries] — every entry that
/// carries a non-blank note becomes a [NoteHit], newest first.
LedgerSearchIndex buildSearchIndex(
  List<AccountBalance> accounts,
  List<EntryView> entries,
) {
  final notes =
      <NoteHit>[
        for (final e in entries)
          if (e.note != null && e.note!.trim().isNotEmpty)
            NoteHit(
              entryId: e.id,
              date: e.date,
              hlc: e.hlc,
              kind: e.kind,
              note: e.note!,
              reviewState: e.reviewState,
              lines: List.unmodifiable([
                for (final l in e.lines)
                  (accountId: l.accountId, amountPaise: l.amount.raw),
              ]),
            ),
      ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        final byHlc = b.hlc.compareTo(a.hlc);
        return byHlc != 0 ? byHlc : b.entryId.compareTo(a.entryId);
      });
  return LedgerSearchIndex(accounts: accounts, notes: notes);
}

/// The live index for [bookId]: rebuilt whenever either the book's accounts
/// ([LocalLedger.watchAccounts]) or its entries ([LocalLedger.watchEntries])
/// re-emit, once both have emitted. Errors from either read reach the
/// listener (S21's error state).
Stream<LedgerSearchIndex> watchSearchIndex(LocalLedger ledger, String bookId) {
  StreamSubscription<List<AccountBalance>>? accountsSub;
  StreamSubscription<List<EntryView>>? entriesSub;
  List<AccountBalance>? accounts;
  List<EntryView>? entries;
  late final StreamController<LedgerSearchIndex> out;
  void emit() {
    final a = accounts, e = entries;
    if (a != null && e != null) out.add(buildSearchIndex(a, e));
  }

  out = StreamController<LedgerSearchIndex>(
    onListen: () {
      accountsSub = ledger.watchAccounts(bookId).listen((v) {
        accounts = v;
        emit();
      }, onError: out.addError);
      entriesSub = ledger.watchEntries(bookId).listen((v) {
        entries = v;
        emit();
      }, onError: out.addError);
    },
    onPause: () {
      accountsSub?.pause();
      entriesSub?.pause();
    },
    onResume: () {
      accountsSub?.resume();
      entriesSub?.resume();
    },
    onCancel: () async {
      await Future.wait([
        if (accountsSub != null) accountsSub!.cancel(),
        if (entriesSub != null) entriesSub!.cancel(),
      ]);
    },
  );
  return out.stream;
}
