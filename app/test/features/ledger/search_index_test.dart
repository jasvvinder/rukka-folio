// F1-07-35 (index side): S21's notes index comes from the book-wide
// `LocalLedger.watchEntries` read (desk 80), over the real in-memory ledger —
// an entries read that returned nothing would leave every note unfound here.
// Synthetic amounts only (CLAUDE.md rule 4).
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/search_index.dart';

import '../../shared/test_app.dart';

void main() {
  group('S21 search index (07 §25)', () {
    test('F1-07-35 every noted entry once, from every account, newest first, '
        'each with all its lines', () async {
      final s = await seedSoloLedger();
      final index = await watchSearchIndex(s.ledger, s.bookId).first;
      expect(index.notes.map((n) => n.note), [
        'part repayment', // cash ← Ramesh, day −1
        'Diesel A/C', // cash → Diesel, day −3
        'Saturday sales', // bank ← sales, day −5
      ]);
      expect(
        index.notes.map((n) => n.entryId).toSet(),
        hasLength(index.notes.length),
      );
      for (final n in index.notes) {
        final posted = s.entries.firstWhere((e) => e.id == n.entryId);
        expect(n.lines, [
          for (final l in posted.lines)
            (accountId: l.accountId, amountPaise: l.amount.raw),
        ], reason: n.note);
      }
      expect(
        searchLedger(index, 'sales').notes.single.entryId,
        s.entries.firstWhere((e) => e.note == 'Saturday sales').id,
      );
      expect(index.accounts.map((a) => a.account.id), contains(s.partyId));
    });

    test(
      'F1-07-35 the index is live: a new note arrives without reopening',
      () async {
        final s = await seedSoloLedger();
        final seen = <LedgerSearchIndex>[];
        final sub = watchSearchIndex(s.ledger, s.bookId).listen(seen.add);
        await pumpEventQueue();
        expect(seen, isNotEmpty);
        await s.ledger.moneyOut(
          bookId: s.bookId,
          from: s.cashId,
          forWhat: s.fuelId,
          paise: 12_300,
          date: s.ledger.today(),
          note: 'tyre puncture',
        );
        await pumpEventQueue();
        await sub.cancel();
        expect(searchLedger(seen.last, 'tyre').notes, hasLength(1));
      },
    );
  });
}
