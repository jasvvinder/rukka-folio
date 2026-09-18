// F1-02-80…91: the app's **review queue** surface on `LocalLedger` — 02 §3 🔒
// post-then-review, 03 §3.3 rule 5 🔒, 03 §3.2.
//
// The money is already in the book. Approving clears a flag and moves nothing;
// rejecting authors the decision **and** the auto-reversal of 02 §5, so the
// balance returns to where it was and both entries stay in history. Nothing
// here writes `review_state`: it folds from `approval_decision` envelopes in
// `(hlc, envelope_id)` order, last one winning, and every assertion below
// reads it back out of the rebuilt projection rather than reasoning about it.
//
// The flagged entries are authored by a *different* member throughout: this
// install has one user and 02 §7.2 item 1 🔒 means nobody decides on their own
// entry — the same reason `local_ledger_advances_test.dart` posts its requests
// by hand.
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

/// A posted, **flagged** entry authored by [user] — `Dr Diesel · Cr Cash`,
/// `review_required = true` (02 §1.3 🔒: the authoring client writes the
/// boolean; the projector never reads `book_roles`).
Future<Entry> postFlaggedBy(
  SeededLedger s, {
  required String user,
  int paise = 750_000,
  LocalDate? date,
  String? note,
  bool flagged = true,
}) async {
  final chart = await s.ledger.chartOf(s.bookId);
  return s.ledger.post(
    Entry(
      id: '',
      bookId: s.bookId,
      kind: EntryKind.moneyOut,
      status: EntryStatus.posted,
      reviewRequired: flagged,
      accountingDate: date ?? s.ledger.today(),
      lines: Verbs.moneyOut(
        from: chart.account(s.cashId),
        forWhat: chart.account(s.fuelId),
        amount: Paise(paise),
      ),
      note: note,
      reviewApprover: s.ledger.identity.userId,
      createdByUser: user,
      createdByDevice: 'device-of-$user',
      hlc: const Hlc(0),
    ),
  );
}

/// The pending **advance request** of 02 §7 — a different queue entirely.
Future<Entry> postAdvanceRequestBy(
  SeededLedger s, {
  required String user,
  required String advanceId,
}) async {
  final chart = await s.ledger.chartOf(s.bookId);
  return s.ledger.post(
    Entry(
      id: '',
      bookId: s.bookId,
      kind: EntryKind.moneyOut,
      status: EntryStatus.pending,
      reviewRequired: false,
      accountingDate: s.ledger.today(),
      lines: Verbs.advanceRequest(
        advance: chart.account(advanceId),
        from: chart.account(s.cashId),
        amount: Paise(500_000),
      ),
      note: 'Mandi trip',
      advanceId: advanceId,
      reviewApprover: s.ledger.identity.userId,
      createdByUser: user,
      createdByDevice: 'device-of-$user',
      hlc: const Hlc(0),
    ),
  );
}

Future<int> envelopes(SeededLedger s) async =>
    (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length;

Future<int> cash(SeededLedger s) async =>
    (await s.ledger.watchPosition(s.bookId).first).cashPaise;

void main() {
  late SeededLedger s;
  const ramesh = 'user-ramesh';

  setUp(() async => s = await seedSoloLedger());

  test('F1-02-80 approve authors exactly ONE approval_decision and the head '
      're-projects `approved` with review_decided_hlc — and no money moves, '
      'because it already did (02 §3 🔒)', () async {
    final flagged = await postFlaggedBy(s, user: ramesh);
    expect((await s.ledger.entry(flagged.id))!.reviewState, 'open');
    final cashAfterPost = await cash(s);
    final before = await envelopes(s);

    final decided = await s.ledger.approveEntry(flagged.id);

    expect(await envelopes(s), before + 1, reason: 'one decision, no more');
    expect(decided.decision.decision, Decision.approve);
    expect(decided.decision.byUser, s.ledger.identity.userId);
    expect(decided.reviewState, 'approved');
    expect(decided.decidedHlc, decided.decision.hlc.raw);
    expect(decided.reason, isNull);
    expect(decided.reversal, isNull);
    // Read back from the projection, not from the return value alone.
    expect((await s.ledger.entry(flagged.id))!.reviewState, 'approved');
    expect((await s.ledger.entry(flagged.id))!.status, 'posted');
    expect(await cash(s), cashAfterPost, reason: 'a flag is not a gate');
  });

  test('F1-02-81 reject authors the decision AND the 02 §5 mirror reversal '
      'with the reason; the head reads `rejected` and the balance returns to '
      'where it was before the entry', () async {
    final cashBefore = await cash(s);
    final flagged = await postFlaggedBy(s, user: ramesh, paise: 750_000);
    expect(await cash(s), cashBefore - 750_000);
    final before = await envelopes(s);

    final decided = await s.ledger.rejectEntry(
      flagged.id,
      reason: 'No bill, and the drum was not delivered',
    );

    expect(await envelopes(s), before + 2, reason: 'decision + reversal');
    expect(decided.decision.decision, Decision.reject);
    expect(decided.decision.reason, 'No bill, and the drum was not delivered');
    expect(decided.reviewState, 'rejected');
    expect(decided.reason, 'No bill, and the drum was not delivered');

    // The mirror: every line negated, `refs.reverses = original`, dated in the
    // open period, never itself flagged (02 §5).
    final mirror = decided.reversal!;
    expect(mirror.refs.reverses, flagged.id);
    expect(mirror.kind, flagged.kind);
    expect(mirror.reviewRequired, isFalse);
    expect(mirror.accountingDate, s.ledger.today());
    expect(mirror.note, 'No bill, and the drum was not delivered');
    expect(
      mirror.lines.map((l) => l.amount.raw),
      flagged.lines.map((l) => -l.amount.raw),
    );

    // Both stay in history; the original is void and carries the reason.
    final head = (await s.ledger.entry(flagged.id))!;
    expect(head.reviewState, 'rejected');
    expect(head.status, 'void');
    expect(await s.ledger.reversalOf(flagged.id), mirror.id);
    expect(await cash(s), cashBefore);
  });

  test('F1-02-82 a rejection with a blank reason is a programming error — it '
      'authors nothing (02 §3: the reason is required)', () async {
    final flagged = await postFlaggedBy(s, user: ramesh);
    final before = await envelopes(s);

    await expectLater(
      s.ledger.rejectEntry(flagged.id, reason: '   '),
      throwsArgumentError,
    );

    expect(await envelopes(s), before);
    expect((await s.ledger.entry(flagged.id))!.reviewState, 'open');
  });

  test('F1-02-83 an entry that never carried a flag refuses `notFlagged` and '
      'authors nothing — nothing below the limit is a reviewer\'s business '
      '(02 §3: the flag is a threshold)', () async {
    final unflagged = await postFlaggedBy(s, user: ramesh, flagged: false);
    final before = await envelopes(s);
    expect((await s.ledger.entry(unflagged.id))!.reviewState, 'none');

    await expectLater(
      s.ledger.approveEntry(unflagged.id),
      throwsA(
        isA<ReviewRefused>().having(
          (e) => e.refusal,
          'refusal',
          ReviewRefusal.notFlagged,
        ),
      ),
    );

    expect(await envelopes(s), before);
  });

  test('F1-02-84 a second decision on an already-decided entry refuses '
      '`alreadyDecided` and authors nothing', () async {
    final flagged = await postFlaggedBy(s, user: ramesh);
    await s.ledger.approveEntry(flagged.id);
    final before = await envelopes(s);

    await expectLater(
      s.ledger.approveEntry(flagged.id),
      throwsA(
        isA<ReviewRefused>().having(
          (e) => e.refusal,
          'refusal',
          ReviewRefusal.alreadyDecided,
        ),
      ),
    );
    await expectLater(
      s.ledger.rejectEntry(flagged.id, reason: 'changed my mind'),
      throwsA(
        isA<ReviewRefused>().having(
          (e) => e.refusal,
          'refusal',
          ReviewRefusal.alreadyDecided,
        ),
      ),
    );

    expect(await envelopes(s), before);
    expect((await s.ledger.entry(flagged.id))!.reviewState, 'approved');
  });

  test('F1-02-85 a pending advance request is refused `pendingAdvance` — that '
      'is 02 §7\'s queue, where approval MOVES the money, and it belongs to '
      'approveAdvance and never to this path', () async {
    final advanceId = (await s.ledger.addAccount(
      s.bookId,
      name: 'Advance – Ramesh',
      accountClass: AccountClass.advance,
      memberId: ramesh,
    )).id;
    final request = await postAdvanceRequestBy(
      s,
      user: ramesh,
      advanceId: advanceId,
    );
    final before = await envelopes(s);

    await expectLater(
      s.ledger.approveEntry(request.id),
      throwsA(
        isA<ReviewRefused>().having(
          (e) => e.refusal,
          'refusal',
          ReviewRefusal.pendingAdvance,
        ),
      ),
    );

    expect(await envelopes(s), before);
    expect((await s.ledger.entry(request.id))!.status, 'pending');
    // The right path still works, and it is the one that moves the money.
    await s.ledger.approveAdvance(request.id);
    expect((await s.ledger.entry(request.id))!.status, 'posted');
  });

  test('F1-02-86 nobody clears their own flag: a decision on an entry this '
      'user authored refuses `selfApproval` and authors nothing '
      '(02 §7.2 item 1 🔒)', () async {
    final mine = await postFlaggedBy(s, user: s.ledger.identity.userId);
    final before = await envelopes(s);

    await expectLater(
      s.ledger.approveEntry(mine.id),
      throwsA(
        isA<ReviewRefused>().having(
          (e) => e.refusal,
          'refusal',
          ReviewRefusal.selfApproval,
        ),
      ),
    );

    expect(await envelopes(s), before);
    expect((await s.ledger.entry(mine.id))!.reviewState, 'open');
  });

  test('F1-02-87 two decisions on one entry fold last-wins by (hlc, '
      'envelope_id) — asserted by reading the projection, never by assuming '
      'the last write won (03 §3.3 rule 5 🔒)', () async {
    final flagged = await postFlaggedBy(s, user: ramesh);
    final first = await s.ledger.approveEntry(flagged.id);
    expect((await s.ledger.entry(flagged.id))!.reviewState, 'approved');

    // A second approver's decision, as it arrives from another device: the
    // facade refuses a second local decision (F1-02-84), so this goes in
    // through the one authoring primitive both paths share.
    final second = await s.ledger.authorApprovalDecision(
      (hlc, id) => ApprovalDecision(
        id: id,
        bookId: s.bookId,
        entryId: flagged.id,
        decision: Decision.reject,
        byUser: 'user-sunita',
        hlc: hlc,
        reason: 'Sunita says no',
      ),
    );
    await s.ledger.rebuild(s.bookId);

    expect(second.hlc.raw, greaterThan(first.decision.hlc.raw));
    final afterSecond = (await s.ledger.entry(flagged.id))!;
    expect(afterSecond.reviewState, 'rejected');

    // And a third, later still, flips it back — the fold is over the whole
    // set every time, not a latch.
    final third = await s.ledger.authorApprovalDecision(
      (hlc, id) => ApprovalDecision(
        id: id,
        bookId: s.bookId,
        entryId: flagged.id,
        decision: Decision.approve,
        byUser: 'user-sunita',
        hlc: hlc,
      ),
    );
    await s.ledger.rebuild(s.bookId);

    expect(third.hlc.raw, greaterThan(second.hlc.raw));
    expect((await s.ledger.entry(flagged.id))!.reviewState, 'approved');
  });

  test(
    'F1-02-88 an entry this device does not hold refuses `unknownEntry`',
    () async {
      final before = await envelopes(s);
      await expectLater(
        s.ledger.approveEntry('00000000-0000-4000-8000-000000000000'),
        throwsA(
          isA<ReviewRefused>().having(
            (e) => e.refusal,
            'refusal',
            ReviewRefusal.unknownEntry,
          ),
        ),
      );
      expect(await envelopes(s), before);
    },
  );

  test('F1-02-89 an amended-away flag refuses `notHead` — the decision belongs '
      'on the head of the chain (02 §5)', () async {
    final flagged = await postFlaggedBy(s, user: ramesh);
    await s.ledger.amend(flagged.id, note: 'diesel for the tractor');
    final before = await envelopes(s);

    await expectLater(
      s.ledger.approveEntry(flagged.id),
      throwsA(
        isA<ReviewRefused>().having(
          (e) => e.refusal,
          'refusal',
          ReviewRefusal.notHead,
        ),
      ),
    );

    expect(await envelopes(s), before);
    // And the superseded row is not offered to a reviewer either.
    final open = await s.ledger.watchOpenReviews(s.bookId).first;
    expect(open.map((f) => f.entryId), isNot(contains(flagged.id)));
  });

  test('F1-02-90 an entry already reversed refuses `alreadyReversed` and '
      'authors nothing — a second mirror would take the money out twice '
      '(02 §5)', () async {
    final cashBefore = await cash(s);
    final flagged = await postFlaggedBy(s, user: ramesh);
    await s.ledger.reverse(flagged.id, date: s.ledger.today());
    expect(await cash(s), cashBefore);
    final before = await envelopes(s);

    await expectLater(
      s.ledger.rejectEntry(flagged.id, reason: 'no bill'),
      throwsA(
        isA<ReviewRefused>().having(
          (e) => e.refusal,
          'refusal',
          ReviewRefusal.alreadyReversed,
        ),
      ),
    );

    expect(await envelopes(s), before);
    expect(await cash(s), cashBefore, reason: 'reversed once, not twice');
    // The flag is still the reviewer's to clear — a correction is not a
    // decision (02 §3).
    expect((await s.ledger.entry(flagged.id))!.reviewState, 'open');
    await s.ledger.approveEntry(flagged.id);
    expect((await s.ledger.entry(flagged.id))!.reviewState, 'approved');
  });

  test('F1-02-91 watchOpenReviews lists open flags only — heads, with their '
      'lines, account names and the approver the author wrote — and drops a '
      'row the moment it is decided (03 §3.3 rule 5 🔒)', () async {
    final older = await postFlaggedBy(
      s,
      user: ramesh,
      paise: 120_000,
      date: s.ledger.today().addDays(-2),
      note: 'diesel, Tuesday',
    );
    final newer = await postFlaggedBy(s, user: ramesh, paise: 340_000);

    var open = await s.ledger.watchOpenReviews(s.bookId).first;
    expect(open.map((f) => f.entryId), [older.id, newer.id]);

    final f = open.first;
    expect(f.bookId, s.bookId);
    expect(f.kind, EntryKind.moneyOut);
    expect(f.createdByUser, ramesh);
    expect(f.approver, s.ledger.identity.userId);
    expect(f.note, 'diesel, Tuesday');
    expect(f.amountPaise, 120_000);
    expect(f.to.map((l) => l.accountName), ['Diesel']);
    expect(f.from.map((l) => l.accountName), ['Cash in hand']);
    expect(f.from.single.amount.raw, -120_000);

    await s.ledger.approveEntry(older.id);
    open = await s.ledger.watchOpenReviews(s.bookId).first;
    expect(open.map((f) => f.entryId), [newer.id]);

    await s.ledger.rejectEntry(newer.id, reason: 'no bill');
    open = await s.ledger.watchOpenReviews(s.bookId).first;
    expect(open, isEmpty);
  });
}
