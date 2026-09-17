// F1-02-13…17: the app's advance (ਐਡਵਾਂਸ) surface on `LocalLedger` — 02 §7 🔒.
// The engine already owns the postings (`Verbs.advanceRequest/Spend/Return`,
// `openAdvances`, A-02-72…77); these tests pin the *app* facade over them:
// a request that moves nothing, an approval that does, spend and return
// against the advance account, and reads that derive purely from `advance`
// balances — no parallel state (02 §7 last bullet 🔒).
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

/// The pending advance request a *different* member authored, posted through
/// the public write path. It cannot come from `requestAdvance` here: this
/// install has one user, and 02 §7.2 item 1 (enforced by the projector) means
/// nobody decides on their own entry — so an approval that actually moves
/// money needs a requester who is not the approver.
Future<Entry> postRequestBy(
  SeededLedger s, {
  required String user,
  required String advanceId,
  required int paise,
  required LocalDate date,
  required String purpose,
}) async {
  final chart = await s.ledger.chartOf(s.bookId);
  return s.ledger.post(
    Entry(
      id: '',
      bookId: s.bookId,
      kind: EntryKind.moneyOut,
      status: EntryStatus.pending,
      reviewRequired: false,
      accountingDate: date,
      lines: Verbs.advanceRequest(
        advance: chart.account(advanceId),
        from: chart.account(s.cashId),
        amount: Paise(paise),
      ),
      note: purpose,
      advanceId: advanceId,
      reviewApprover: s.ledger.identity.userId,
      createdByUser: user,
      createdByDevice: 'device-of-$user',
      hlc: const Hlc(0),
    ),
  );
}

Future<String> addAdvanceAccount(
  SeededLedger s, {
  required String name,
  required String memberId,
}) async => (await s.ledger.addAccount(
  s.bookId,
  name: name,
  accountClass: AccountClass.advance,
  memberId: memberId,
)).id;

Future<int> envelopes(SeededLedger s) async =>
    (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length;

void main() {
  late SeededLedger s;
  late String advanceId;

  setUp(() async {
    s = await seedSoloLedger();
    advanceId = await addAdvanceAccount(
      s,
      name: 'Advance – Ramesh',
      memberId: 'user-ramesh',
    );
  });

  test('F1-02-13 requestAdvance posts `pending` with the purpose and moves '
      'no money — the approval does that (02 §7 🔒)', () async {
    final before = await s.ledger.watchPosition(s.bookId).first;
    final e = await s.ledger.requestAdvance(
      bookId: s.bookId,
      advance: advanceId,
      from: s.cashId,
      paise: 500_000,
      purpose: 'Mandi trip',
      date: s.ledger.today(),
      approver: s.ledger.identity.userId,
    );

    expect(e.status, EntryStatus.pending);
    expect(e.note, 'Mandi trip');
    expect(e.advanceId, advanceId);
    expect(e.reviewApprover, s.ledger.identity.userId);
    // `Dr Advance – {member} · Cr money`, authored but not yet counted.
    expect(e.lines.map((l) => l.accountId), [advanceId, s.cashId]);
    expect(e.lines.map((l) => l.amount.raw), [500_000, -500_000]);

    final after = await s.ledger.watchPosition(s.bookId).first;
    expect(after.cashPaise, before.cashPaise);
    expect(after.advancesOutPaise, 0);
    expect(await s.ledger.openAdvances(s.bookId), isEmpty);
  });

  test('F1-02-18 a request without a purpose is refused (02 §7: purpose text '
      'required)', () async {
    await expectLater(
      s.ledger.requestAdvance(
        bookId: s.bookId,
        advance: advanceId,
        from: s.cashId,
        paise: 500_000,
        purpose: '   ',
        date: s.ledger.today(),
      ),
      throwsArgumentError,
    );
    expect(await s.ledger.openAdvances(s.bookId), isEmpty);
  });

  test('F1-02-14 approveAdvance moves the money — `Dr Advance – {member} · '
      'Cr money` — and only once', () async {
    final before = await s.ledger.watchPosition(s.bookId).first;
    final req = await postRequestBy(
      s,
      user: 'user-ramesh',
      advanceId: advanceId,
      paise: 500_000,
      date: s.ledger.today(),
      purpose: 'Mandi trip',
    );
    expect(
      (await s.ledger.watchPosition(s.bookId).first).advancesOutPaise,
      0,
      reason: 'a pending request contributes nothing (02 §9)',
    );

    await s.ledger.approveAdvance(req.id);

    final after = await s.ledger.watchPosition(s.bookId).first;
    expect(after.advancesOutPaise, 500_000);
    expect(after.cashPaise, before.cashPaise - 500_000);

    // A second approval of the same request authors nothing.
    final envelopesBefore = await envelopes(s);
    await expectLater(
      s.ledger.approveAdvance(req.id),
      throwsA(
        isA<AdvanceRefused>().having(
          (e) => e.refusal,
          'refusal',
          AdvanceRefusal.alreadyDecided,
        ),
      ),
    );
    expect(await envelopes(s), envelopesBefore);
    expect(
      (await s.ledger.watchPosition(s.bookId).first).advancesOutPaise,
      500_000,
    );
  });

  test('F1-02-15 spend and return post against the advance account; the '
      'balance and the ageing follow OpenAdvance (02 §7)', () async {
    final taken = s.ledger.today().addDays(-5);
    final req = await postRequestBy(
      s,
      user: 'user-ramesh',
      advanceId: advanceId,
      paise: 500_000,
      date: taken,
      purpose: 'Mandi trip',
    );
    await s.ledger.approveAdvance(req.id);

    final spend = await s.ledger.spendAgainstAdvance(
      bookId: s.bookId,
      advance: advanceId,
      forWhat: s.fuelId,
      paise: 150_000,
      date: s.ledger.today().addDays(-2),
      note: 'Diesel on the way',
    );
    // `Dr expense-category · Cr Advance – {member}`.
    expect(spend.lines.map((l) => l.accountId), [s.fuelId, advanceId]);
    expect(spend.lines.map((l) => l.amount.raw), [150_000, -150_000]);

    final ret = await s.ledger.returnAdvance(
      bookId: s.bookId,
      advance: advanceId,
      into: s.cashId,
      paise: 100_000,
      date: s.ledger.today(),
    );
    // `Dr money · Cr Advance – {member}`.
    expect(ret.lines.map((l) => l.accountId), [s.cashId, advanceId]);
    expect(ret.lines.map((l) => l.amount.raw), [100_000, -100_000]);

    final open = await s.ledger.openAdvances(s.bookId);
    expect(open, hasLength(1));
    final a = open.single;
    expect(a.accountId, advanceId);
    expect(a.memberId, 'user-ramesh');
    expect(a.givenPaise, 500_000);
    expect(a.spentPaise, 150_000);
    expect(a.returnedPaise, 100_000);
    expect(a.remainingPaise, 250_000);
    expect(a.givenPaise, a.spentPaise + a.returnedPaise + a.remainingPaise);
    expect(a.purpose, 'Mandi trip');
    expect(a.takenDate, taken);
    expect(a.ageDays, 5, reason: 'days since the oldest unsettled debit');
  });

  test('F1-02-16 an advance closes at zero and myAdvances shows only what '
      'this user holds — both derive from `advance` balances', () async {
    final mine = await addAdvanceAccount(
      s,
      name: 'Advance – me',
      memberId: s.ledger.identity.userId,
    );
    final theirs = await postRequestBy(
      s,
      user: 'user-ramesh',
      advanceId: advanceId,
      paise: 300_000,
      date: s.ledger.today().addDays(-3),
      purpose: 'Mandi trip',
    );
    await s.ledger.approveAdvance(theirs.id);
    final ours = await postRequestBy(
      s,
      user: 'user-manager',
      advanceId: mine,
      paise: 200_000,
      date: s.ledger.today().addDays(-1),
      purpose: 'Transport',
    );
    await s.ledger.approveAdvance(ours.id);

    // Aged list: oldest unsettled first (07 §8 "Given out", aged).
    var open = await s.ledger.openAdvances(s.bookId);
    expect(open.map((a) => a.accountId), [advanceId, mine]);
    expect(open.map((a) => a.ageDays), [3, 1]);

    final held = await s.ledger.myAdvances();
    expect(held.map((a) => a.accountId), [mine]);
    expect(held.single.remainingPaise, 200_000);

    // Returning every last paisa closes it: balance zero, off both lists.
    await s.ledger.returnAdvance(
      bookId: s.bookId,
      advance: mine,
      into: s.cashId,
      paise: 200_000,
      date: s.ledger.today(),
    );
    open = await s.ledger.openAdvances(s.bookId);
    expect(open.map((a) => a.accountId), [advanceId]);
    expect(await s.ledger.myAdvances(), isEmpty);
  });

  test('F1-02-17 nobody approves their own request — no auto-approval, and '
      'no envelope authored (02 §7.2 item 1 🔒)', () async {
    final e = await s.ledger.requestAdvance(
      bookId: s.bookId,
      advance: advanceId,
      from: s.cashId,
      paise: 500_000,
      purpose: 'Mandi trip',
      date: s.ledger.today(),
    );
    final envelopesBefore = await envelopes(s);
    await expectLater(
      s.ledger.approveAdvance(e.id),
      throwsA(
        isA<AdvanceRefused>().having(
          (x) => x.refusal,
          'refusal',
          AdvanceRefusal.selfApproval,
        ),
      ),
    );
    expect(await envelopes(s), envelopesBefore);
    expect(
      (await s.ledger.watchPosition(s.bookId).first).advancesOutPaise,
      0,
      reason: 'the request is still pending — nothing moved',
    );

    // An entry that is not a pending advance request is refused too.
    await expectLater(
      s.ledger.approveAdvance(s.entries.last.id),
      throwsA(
        isA<AdvanceRefused>().having(
          (x) => x.refusal,
          'refusal',
          AdvanceRefusal.notAPendingRequest,
        ),
      ),
    );
  });
}
