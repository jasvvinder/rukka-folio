// ADR 2026-10-07b — an account created inside an entry asks for its opening
// balance afterwards. The data half: which accounts are still unanswered
// (`LocalLedger.watchOpeningUnanswered`), derived only from data that syncs,
// so a second device that has applied the same envelopes asks the same
// question or none. Synthetic names and sums only (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../test_app.dart';

/// Device B: a second ledger over a fresh database with A's keys — the book
/// key arrives the way key sync leaves it (`key_cache`, 05) — holding exactly
/// the envelopes A's mirror holds, rebuilt from them. No projection row and no
/// setting of A's crosses over.
Future<LocalLedger> _secondDevice(SeededLedger a) async {
  final b = await openTestLedger(keys: a.ledger.keys as FakeKeyStore);
  for (final k in await a.ledger.db.select(a.ledger.db.keyCache).get()) {
    await b.db.into(b.db.keyCache).insert(k.toCompanion(false));
  }
  await b.openIdentity();
  await _deliver(a.ledger, b, a.bookId);
  return b;
}

/// Hands [to] every envelope of [from] it does not hold yet, then rebuilds —
/// what a sync pull leaves behind (03 §3.1, §3.3).
Future<void> _deliver(LocalLedger from, LocalLedger to, String bookId) async {
  final held = {
    for (final r in await to.db.select(to.db.envelopesLocal).get())
      r.envelopeId,
  };
  for (final r in await from.db.select(from.db.envelopesLocal).get()) {
    if (held.contains(r.envelopeId)) continue;
    await to.db.into(to.db.envelopesLocal).insert(r.toCompanion(false));
  }
  await to.rebuild(bookId);
}

void main() {
  test('F1-1007b-1 a person created the way the entry picker creates one '
      '(addAccount, no opening) is unanswered; expense, income, money and '
      'system accounts never are', () async {
    final s = await seedSoloLedger();
    final l = s.ledger;
    final person = await l.addAccount(
      s.bookId,
      name: 'Gurdeep',
      accountClass: AccountClass.party,
    );
    final expense = await l.addAccount(
      s.bookId,
      name: 'Tea Expense',
      accountClass: AccountClass.categoryExpense,
    );
    final income = await l.addAccount(
      s.bookId,
      name: 'Tuition Income',
      accountClass: AccountClass.categoryIncome,
    );
    final pending = await l.watchOpeningUnanswered(s.bookId).first;
    expect(pending, contains(person.id));
    // The seed's *Ramesh* was created the same way and never answered.
    expect(pending, contains(s.partyId));
    for (final id in [expense.id, income.id, s.salesId, s.fuelId]) {
      expect(pending, isNot(contains(id)), reason: 'categories never ask');
    }
    // Cash and the bank are answered by the seed's openings, and a money
    // account is never read as unanswered in any case (see the ⚠️ SPEC on
    // watchOpeningUnanswered).
    expect(pending, isNot(contains(s.cashId)));
    expect(pending, isNot(contains(s.bankId)));
    final chart = await l.chartOf(s.bookId);
    for (final a in chart.byClass(AccountClass.equitySystem)) {
      expect(pending, isNot(contains(a.id)));
    }
    expect(pending, hasLength(2));
  });

  test('F1-1007b-2 one opening adjustment answers it — and it stays answered '
      'when that entry is later reversed (either answer is final)', () async {
    final s = await seedSoloLedger();
    final l = s.ledger;
    final person = await l.addAccount(
      s.bookId,
      name: 'Gurdeep',
      accountClass: AccountClass.party,
    );
    expect(await l.watchOpeningUnanswered(s.bookId).first, contains(person.id));
    final posted = await l.openingBalances(
      s.bookId,
      balances: {person.id: 2_000_00},
    );
    expect(
      await l.watchOpeningUnanswered(s.bookId).first,
      isNot(contains(person.id)),
    );
    // A later correction does not bring the question back.
    await l.reverse(posted.single.id, date: l.today());
    expect(
      await l.watchOpeningUnanswered(s.bookId).first,
      isNot(contains(person.id)),
    );
    // Ramesh, untouched, still waits.
    expect(await l.watchOpeningUnanswered(s.bookId).first, {s.partyId});
  });

  test('F1-1007b-2 an ordinary entry with the person does not answer the '
      'question — only an adjustment against Opening Balance does', () async {
    final s = await seedSoloLedger();
    final l = s.ledger;
    final person = await l.addAccount(
      s.bookId,
      name: 'Gurdeep',
      accountClass: AccountClass.party,
    );
    await l.gaveCredit(
      bookId: s.bookId,
      toWhom: person.id,
      gave: s.cashId,
      paise: 500_00,
      date: l.today(),
    );
    expect(await l.watchOpeningUnanswered(s.bookId).first, contains(person.id));
  });

  test(
    'F1-1007b-2 the answer survives sync: device B, holding the same '
    'envelopes, asks for exactly the accounts device A still asks for',
    () async {
      final a = await seedSoloLedger();
      final answered = await a.ledger.addAccount(
        a.bookId,
        name: 'Gurdeep',
        accountClass: AccountClass.party,
      );
      final waiting = await a.ledger.addAccount(
        a.bookId,
        name: 'Harpreet',
        accountClass: AccountClass.party,
      );
      await a.ledger.openingBalances(
        a.bookId,
        balances: {answered.id: -1_250_00},
      );
      final onA = await a.ledger.watchOpeningUnanswered(a.bookId).first;
      expect(onA, {waiting.id, a.partyId});

      final b = await _secondDevice(a);
      expect(await b.watchOpeningUnanswered(a.bookId).first, onA);
      // A answers Harpreet later; the one new envelope reaches B the way a
      // pull leaves it, and B stops asking too. (B only reads here: it shares
      // A's device identity in this rig, so it must not author.)
      await a.ledger.openingBalances(a.bookId, balances: {waiting.id: 300_00});
      await _deliver(a.ledger, b, a.bookId);
      expect(await b.watchOpeningUnanswered(a.bookId).first, {a.partyId});
    },
  );

  test('F1-1007b-2 a person carried in a certified year-close vector is '
      'answered — its b/f is the certified figure, and a device whose '
      'archived years hold the adjustment only inside that vector does not '
      'ask again', () async {
    final s = await seedSoloLedger();
    final l = s.ledger;
    // The row Recompute writes for a certified close (03 §3.2 year_close_p):
    // the vector is a JSON object of account id → integer paise.
    await l.db.customStatement(
      'INSERT INTO year_close_p (book_id, fy_label, state, vector) '
      "VALUES (?, '2025-26', 'closed', ?)",
      [s.bookId, '{"${s.partyId}": 500000}'],
    );
    expect(await l.watchOpeningUnanswered(s.bookId).first, isEmpty);
  });
}
