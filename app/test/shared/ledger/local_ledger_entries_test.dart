// F1-07-35 (data side): `LocalLedger.watchEntries` — the book-wide entries
// read S21 Search builds its notes index from (07 §25 🔒 "search across
// accounts, parties and notes in scope"; desk 80).
//
// The read must list exactly the entries the statements list (07 §6, 02 §9):
// heads of amend chains only, pending/rejected advance requests excluded,
// reversed entries and their mirrors both present — so these tests pin it
// against the union of every account's `watchStatement`, over the real
// in-memory ledger. Synthetic amounts only (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

/// Every entry id the book's statements show, in no particular order.
Future<Set<String>> statementUnion(SeededLedger s) async {
  final ids = <String>{};
  for (final a in await s.ledger.watchAccounts(s.bookId).first) {
    for (final r in await s.ledger.watchStatement(a.account.id).first) {
      ids.add(r.entryId);
    }
  }
  return ids;
}

int sum(Iterable<Line> lines) =>
    lines.fold(0, (acc, line) => acc + line.amount.raw);

void main() {
  group('LocalLedger.watchEntries (07 §25 S21 notes, desk 80)', () {
    late SeededLedger s;
    setUp(() async => s = await seedSoloLedger());

    test('F1-07-35 every entry of the book once, across accounts, with its '
        'note and every line', () async {
      final entries = await s.ledger.watchEntries(s.bookId).first;
      // Two opening adjustments + five verbs.
      expect(entries, hasLength(s.entries.length));
      expect(entries, isNotEmpty);
      expect(
        entries.map((e) => e.id).toSet(),
        s.entries.map((e) => e.id).toSet(),
      );
      expect(
        entries.map((e) => e.id).toSet(),
        hasLength(entries.length),
        reason: 'one view per entry, not one per line',
      );
      final byId = {for (final e in entries) e.id: e};
      for (final posted in s.entries) {
        final v = byId[posted.id]!;
        expect(v.bookId, s.bookId);
        expect(v.note, posted.note, reason: posted.id);
        expect(v.kind, posted.kind);
        expect(v.date, posted.accountingDate);
        expect(v.isHead, isTrue);
        expect(
          v.lines.map((l) => (l.accountId, l.amount.raw)),
          posted.lines.map((l) => (l.accountId, l.amount.raw)),
          reason: 'lines in order, integer paise',
        );
        expect(sum(v.lines), 0, reason: 'balanced');
      }
      // The notes live on entries that touch different accounts — a read of
      // one statement would miss some of them.
      expect(
        [
          for (final e in entries)
            if (e.note != null) e.note,
        ]..sort(),
        ['Diesel A/C', 'Saturday sales', 'part repayment'],
      );
      // Statement order (02 §9): accounting date, then hlc, then id.
      for (var i = 1; i < entries.length; i++) {
        final a = entries[i - 1], b = entries[i];
        final byDate = a.date.compareTo(b.date);
        expect(
          byDate < 0 || (byDate == 0 && a.hlc <= b.hlc),
          isTrue,
          reason: 'ordered at $i',
        );
      }
    });

    test('F1-07-35 parity with the statements: amended heads only, reversal '
        'and mirror both, pending advance request left out', () async {
      final diesel = s.entries.firstWhere((e) => e.note == 'Diesel A/C');
      final amended = await s.ledger.amend(diesel.id, note: 'Diesel, Sunday');
      final repayment = s.entries.firstWhere((e) => e.note == 'part repayment');
      final mirror = await s.ledger.reverse(
        repayment.id,
        date: s.ledger.today(),
      );
      final advance = await s.ledger.addAccount(
        s.bookId,
        name: 'Advance – Ramesh',
        accountClass: AccountClass.advance,
        memberId: 'user-ramesh',
      );
      final request = await s.ledger.requestAdvance(
        bookId: s.bookId,
        advance: advance.id,
        from: s.cashId,
        paise: 500_000,
        purpose: 'Mandi trip',
        date: s.ledger.today(),
        approver: s.ledger.identity.userId,
      );

      final ids = (await s.ledger.watchEntries(s.bookId).first)
          .map((e) => e.id)
          .toList();
      expect(ids.toSet(), await statementUnion(s));
      expect(ids, hasLength(ids.toSet().length));
      expect(ids, isNot(contains(diesel.id)), reason: 'superseded');
      expect(ids, contains(amended.id));
      expect(ids, containsAll([repayment.id, mirror.id]));
      expect(ids, isNot(contains(request.id)), reason: 'pending request');
      final notes = {
        for (final e in await s.ledger.watchEntries(s.bookId).first)
          e.id: e.note,
      };
      expect(notes[amended.id], 'Diesel, Sunday');
    });

    test('F1-07-35 scoped to the book: another book\'s entries are not '
        'listed', () async {
      final other = await s.ledger.createBook(
        name: 'Shop',
        type: BookType.business,
      );
      final cash = await s.ledger.addAccount(
        other,
        name: 'Galla',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cash,
      );
      final sales = await s.ledger.addAccount(
        other,
        name: 'Counter sales',
        accountClass: AccountClass.categoryIncome,
      );
      final elsewhere = await s.ledger.moneyIn(
        bookId: other,
        into: cash.id,
        from: sales.id,
        paise: 70_000,
        date: s.ledger.today(),
        note: 'Saturday sales',
      );
      final mine = await s.ledger.watchEntries(s.bookId).first;
      expect(mine.map((e) => e.id), isNot(contains(elsewhere.id)));
      expect(mine.every((e) => e.bookId == s.bookId), isTrue);
      final theirs = await s.ledger.watchEntries(other).first;
      expect(theirs.map((e) => e.id), contains(elsewhere.id));
      expect(theirs.every((e) => e.bookId == other), isTrue);
    });

    test('F1-07-35 live: a new note re-emits while watched', () async {
      final seen = <List<EntryView>>[];
      final sub = s.ledger.watchEntries(s.bookId).listen(seen.add);
      await pumpEventQueue();
      expect(seen, isNotEmpty);
      final posted = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 12_300,
        date: s.ledger.today(),
        note: 'tyre puncture',
      );
      await pumpEventQueue();
      await sub.cancel();
      expect(
        seen.last.firstWhere((e) => e.id == posted.id).note,
        'tyre puncture',
      );
      expect(seen.last, hasLength(s.entries.length + 1));
    });
  });
}
