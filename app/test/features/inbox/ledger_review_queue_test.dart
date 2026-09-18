// F1-07-230…239: `LedgerReviewQueue` over the **real** ledger — the approvals
// S6, S6.1 and S6.2 have been drawn against `FakeReviewQueue` all phase
// (02 §3 🔒 post-then-review, 03 §3.3 rule 5 🔒, 07 §9 🔒, 13 §3.2 S6/S6.1/S6.2).
//
// The book question, settled the way `LedgerLateArrivals` settled it: **the
// Inbox is one surface** (07 §9 🔒), so the queue watches every book this
// device holds and merges the cards, each carrying its own book's name.
//
// Everything else is the ledger's: what is flagged is the projector's
// `entries_p.review_state`, approve is one signed decision that moves nothing,
// and reject is the decision plus 02 §5's auto-reversal. Two rules the seam
// states and the screens cannot check are pinned here: the entries are already
// in the book, and **nobody clears their own flag** (02 §7.2 item 1 🔒).
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/ledger_review_queue.dart';
import 'package:rukka_folio/features/inbox/review_queue.dart';
import 'package:rukka_folio/features/inbox/screens/s6_inbox_screen.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

const ramesh = 'user-ramesh';
const sunita = 'user-sunita';

/// A posted, **flagged** entry authored by [user] — `Dr {category} · Cr
/// {money}`, `review_required = true` (02 §1.3 🔒: the authoring client writes
/// the boolean, never the projector).
Future<Entry> postFlaggedBy(
  LocalLedger ledger, {
  required String bookId,
  required String user,
  required String moneyId,
  required String categoryId,
  int paise = 750_000,
  LocalDate? date,
  String? note,
  EntryStatus status = EntryStatus.posted,
  String? advanceId,
  List<Line>? lines,
}) async {
  final chart = await ledger.chartOf(bookId);
  return ledger.post(
    Entry(
      id: '',
      bookId: bookId,
      kind: EntryKind.moneyOut,
      status: status,
      reviewRequired: true,
      accountingDate: date ?? ledger.today(),
      lines:
          lines ??
          Verbs.moneyOut(
            from: chart.account(moneyId),
            forWhat: chart.account(categoryId),
            amount: Paise(paise),
          ),
      note: note,
      advanceId: advanceId,
      reviewApprover: ledger.identity.userId,
      createdByUser: user,
      createdByDevice: 'device-of-$user',
      hlc: const Hlc(0),
    ),
  );
}

/// The first snapshot [holds] accepts — the streams are live and emit once per
/// projection, so every read waits for the shape it is about to assert rather
/// than taking one event and hoping.
Future<InboxSnapshot> snapshotWhere(
  LedgerReviewQueue q,
  bool Function(InboxSnapshot) holds,
) async {
  for (var i = 0; i < 600; i++) {
    final c = q.current;
    if (c != null && holds(c)) return c;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('no snapshot matched: ${q.current?.reviews.length} cards');
}

/// The snapshot holding exactly [cards] cards whose entry counts are [counts].
Future<InboxSnapshot> snapshotOf(
  LedgerReviewQueue q,
  int cards, {
  List<int>? counts,
}) => snapshotWhere(q, (s) {
  if (s.reviews.length != cards) return false;
  if (counts == null) return true;
  final got = s.reviews.map((g) => g.count).toList()..sort();
  return '$got' == '${[...counts]..sort()}';
});

Future<int> envelopes(LocalLedger l) async =>
    (await l.db.select(l.db.envelopesLocal).get()).length;

void main() {
  late SeededLedger s;
  late LedgerReviewQueue queue;

  setUp(() async {
    s = await seedSoloLedger();
    queue = LedgerReviewQueue(
      s.ledger,
      authorNameOf: (id) => switch (id) {
        ramesh => 'Ramesh Kumar',
        sunita => 'Sunita',
        _ => '',
      },
    );
  });

  tearDown(() => queue.dispose());

  Future<Entry> flag({
    String user = ramesh,
    int paise = 750_000,
    String? note,
  }) => postFlaggedBy(
    s.ledger,
    bookId: s.bookId,
    user: user,
    moneyId: s.cashId,
    categoryId: s.fuelId,
    paise: paise,
    note: note,
  );

  test('F1-07-230 one card per author + book + day, and never a card of the '
      'reader\'s own: nobody clears their own flag (02 §7.2 item 1 🔒, '
      '07 §9 🔒)', () async {
    await flag(user: ramesh);
    await flag(user: ramesh, paise: 120_000);
    await flag(user: sunita, paise: 45_000);
    await flag(user: s.ledger.identity.userId, paise: 99_000);

    final snap = await snapshotOf(queue, 2, counts: [2, 1]);

    expect(snap.reviews.map((g) => g.authorName), ['Ramesh Kumar', 'Sunita']);
    expect(snap.reviews.map((g) => g.count), [2, 1]);
    expect(snap.reviews.every((g) => g.bookName == 'Me'), isTrue);
    expect(
      snap.reviews.map((g) => g.id).toSet().length,
      2,
      reason: 'the card id is (book, author, day) and must be stable',
    );
    // Two flags of the reader's own are in the book and counted — they are
    // simply nobody's to decide on here.
    final open = await s.ledger.watchOpenReviews(s.bookId).first;
    expect(open.length, 4);
  });

  test(
    'F1-07-231 the Inbox is ONE surface: the queue merges every book this '
    'device holds, each card carrying its own book\'s name (07 §9 🔒)',
    () async {
      final second = await s.ledger.createBook(
        name: 'Kirana',
        type: BookType.business,
        startDate: s.ledger.today().addDays(-7),
      );
      final cash2 = (await s.ledger.addAccount(
        second,
        name: 'Shop cash',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cash,
      )).id;
      final packing = (await s.ledger.addAccount(
        second,
        name: 'Packing',
        accountClass: AccountClass.categoryExpense,
      )).id;

      await flag(user: ramesh);
      await postFlaggedBy(
        s.ledger,
        bookId: second,
        user: ramesh,
        moneyId: cash2,
        categoryId: packing,
        paise: 60_000,
      );

      final snap = await snapshotOf(queue, 2, counts: [1, 1]);
      expect(snap.reviews.map((g) => g.bookName).toList()..sort(), [
        'Kirana',
        'Me',
      ], reason: 'one author, two books — two cards, not one');
    },
  );

  test('F1-07-232 the card reads from the money A/C\'s own side — + money in, '
      '− money out (02 §10 🔒) — with the chart\'s names, entries oldest '
      'first, and a total that is magnitudes only', () async {
    final first = await flag(paise: 120_000, note: 'diesel, Tuesday');
    final second = await s.ledger.post(
      Entry(
        id: '',
        bookId: s.bookId,
        kind: EntryKind.moneyIn,
        status: EntryStatus.posted,
        reviewRequired: true,
        accountingDate: s.ledger.today(),
        lines: Verbs.moneyIn(
          into: (await s.ledger.chartOf(s.bookId)).account(s.cashId),
          from: (await s.ledger.chartOf(s.bookId)).account(s.salesId),
          amount: const Paise(80_000),
        ),
        reviewApprover: s.ledger.identity.userId,
        createdByUser: ramesh,
        createdByDevice: 'device-of-$ramesh',
        hlc: const Hlc(0),
      ),
    );

    final card = (await snapshotOf(queue, 1, counts: [2])).reviews.single;
    expect(card.entries.map((e) => e.id), [first.id, second.id]);
    expect(card.entries.first.paise, -120_000, reason: 'money out');
    expect(card.entries.last.paise, 80_000, reason: 'money in');
    expect(card.entries.first.fromLabel, 'Cash in hand');
    expect(card.entries.first.toLabel, 'Diesel');
    expect(card.entries.first.note, 'diesel, Tuesday');
    expect(card.entries.first.date, s.ledger.today());
    // A card mixes directions, so its total carries none (07 §1 rule 3).
    expect(card.totalPaise, 200_000);
  });

  test('F1-07-233 Approve all is N signed decisions that clear every flag in '
      'the card in one tap, and move no money (07 §9 🔒, 02 §3 🔒)', () async {
    final a = await flag(paise: 120_000);
    final b = await flag(paise: 340_000);
    final cashAfterPost =
        (await s.ledger.watchPosition(s.bookId).first).cashPaise;
    final card = (await snapshotOf(queue, 1, counts: [2])).reviews.single;
    final before = await envelopes(s.ledger);

    await queue.approveAll(card.id);

    expect(await envelopes(s.ledger), before + 2, reason: 'one per entry');
    expect((await s.ledger.entry(a.id))!.reviewState, 'approved');
    expect((await s.ledger.entry(b.id))!.reviewState, 'approved');
    expect(
      (await s.ledger.watchPosition(s.bookId).first).cashPaise,
      cashAfterPost,
    );
    expect((await snapshotOf(queue, 0)).isEmpty, isTrue);
  });

  test(
    'F1-07-234 Approve all\'s partial-failure rule, stated: a refusal that '
    'means the flag is already gone is skipped, one that means the queue '
    'yielded something it should not have surfaces — after the rest of the '
    'card has been approved (07 §9 🔒: refusing one never blocks the rest)',
    () async {
      // The classification itself, named rather than buried.
      for (final settled in [
        ReviewRefusal.unknownEntry,
        ReviewRefusal.notFlagged,
        ReviewRefusal.alreadyDecided,
        ReviewRefusal.notHead,
      ]) {
        expect(LedgerReviewQueue.settledAlready(settled), isTrue);
      }
      for (final loud in [
        ReviewRefusal.pendingAdvance,
        ReviewRefusal.selfApproval,
        ReviewRefusal.alreadyReversed,
        ReviewRefusal.reversalRefused,
      ]) {
        expect(LedgerReviewQueue.settledAlready(loud), isFalse);
      }

      // A flagged **advance request** — 02 §7's queue, which this path must
      // never decide, and which `approveEntry` refuses `pendingAdvance`.
      final advanceId = (await s.ledger.addAccount(
        s.bookId,
        name: 'Advance – Ramesh',
        accountClass: AccountClass.advance,
        memberId: ramesh,
      )).id;
      final chart = await s.ledger.chartOf(s.bookId);
      final a = await flag(paise: 120_000);
      final stray = await postFlaggedBy(
        s.ledger,
        bookId: s.bookId,
        user: ramesh,
        moneyId: s.cashId,
        categoryId: s.fuelId,
        status: EntryStatus.pending,
        advanceId: advanceId,
        lines: Verbs.advanceRequest(
          advance: chart.account(advanceId),
          from: chart.account(s.cashId),
          amount: const Paise(500_000),
        ),
      );
      final b = await flag(paise: 340_000);
      final card = (await snapshotOf(queue, 1, counts: [3])).reviews.single;
      expect(card.count, 3);

      await expectLater(
        queue.approveAll(card.id),
        throwsA(isA<ReviewQueueFailure>()),
      );

      // The refused member left the others approved — append-only, so a
      // decision already authored can never be taken back.
      expect((await s.ledger.entry(a.id))!.reviewState, 'approved');
      expect((await s.ledger.entry(b.id))!.reviewState, 'approved');
      expect((await s.ledger.entry(stray.id))!.reviewState, 'open');
      expect((await s.ledger.entry(stray.id))!.status, 'pending');
    },
  );

  test(
    'F1-07-235 Reject posts the 02 §5 auto-reversal with the reason; the '
    'balance returns to where it was and the card loses that entry',
    () async {
      final cashBefore =
          (await s.ledger.watchPosition(s.bookId).first).cashPaise;
      final a = await flag(paise: 120_000);
      final b = await flag(paise: 340_000);
      final card = (await snapshotOf(queue, 1, counts: [2])).reviews.single;
      final before = await envelopes(s.ledger);

      await queue.decide(
        groupId: card.id,
        entryId: a.id,
        decision: ReviewDecision.reject,
        reason: 'No bill',
      );

      expect(
        await envelopes(s.ledger),
        before + 2,
        reason: 'decision + mirror',
      );
      final head = (await s.ledger.entry(a.id))!;
      expect(head.reviewState, 'rejected');
      expect(head.status, 'void');
      expect(await s.ledger.reversalOf(a.id), isNotNull);
      expect(
        (await s.ledger.watchPosition(s.bookId).first).cashPaise,
        cashBefore - 340_000,
        reason: 'a\'s 1,200 came back; b is still in the book',
      );

      final after = (await snapshotOf(queue, 1, counts: [1])).reviews.single;
      expect(after.entries.map((e) => e.id), [b.id]);
    },
  );

  test('F1-07-236 a rejection with a blank reason is a programming error — it '
      'authors nothing (07 §9 🔒: the sheet collects it first)', () async {
    final a = await flag();
    final card = (await snapshotOf(queue, 1)).reviews.single;
    final before = await envelopes(s.ledger);

    await expectLater(
      queue.decide(
        groupId: card.id,
        entryId: a.id,
        decision: ReviewDecision.reject,
        reason: '   ',
      ),
      throwsArgumentError,
    );

    expect(await envelopes(s.ledger), before);
    expect((await s.ledger.entry(a.id))!.reviewState, 'open');
  });

  test('F1-07-237 a refusal from the ledger arrives as the seam\'s own '
      'ReviewQueueFailure, carrying no plaintext financial data '
      '(CLAUDE.md rule 4)', () async {
    final a = await flag();
    final card = (await snapshotOf(queue, 1)).reviews.single;
    await queue.decide(
      groupId: card.id,
      entryId: a.id,
      decision: ReviewDecision.approve,
    );

    ReviewQueueFailure? caught;
    try {
      await queue.decide(
        groupId: card.id,
        entryId: a.id,
        decision: ReviewDecision.approve,
      );
    } on ReviewQueueFailure catch (e) {
      caught = e;
    }
    expect(caught, isNotNull);
    expect(caught!.reason, contains(ReviewRefusal.alreadyDecided.name));
    expect(caught.reason, isNot(contains('750')));
    expect(caught.reason, isNot(contains('Diesel')));
  });

  test('F1-07-238 *ask for a better photo* authors NOTHING — ⚠️ SPEC: 07 §9 🔒 '
      'gives it a link, 03 §3 gives it no object type and 07 §17 / 13 §3.4 '
      'give it no notification, so it stays a device-local request rather '
      'than an invented envelope', () async {
    final a = await flag();
    final card = (await snapshotOf(queue, 1)).reviews.single;
    final before = await envelopes(s.ledger);

    await queue.askForPhoto(groupId: card.id, entryId: a.id);

    expect(await envelopes(s.ledger), before);
    expect(queue.askedForPhoto, {a.id});
    // The flag stays exactly as it was (07 §9).
    expect((await s.ledger.entry(a.id))!.reviewState, 'open');
    expect((await snapshotOf(queue, 1)).reviews.single.count, 1);
  });

  testWidgets('F1-07-239 mounted over the real ledger, S6 renders the '
      'ledger-backed cards — the shell\'s ReviewQueueScope, not '
      'FakeReviewQueue', (tester) async {
    late LedgerReviewQueue live;
    await tester.runAsync(() async {
      await postFlaggedBy(
        s.ledger,
        bookId: s.bookId,
        user: ramesh,
        moneyId: s.cashId,
        categoryId: s.fuelId,
        paise: 120_000,
      );
      live = LedgerReviewQueue(s.ledger, authorNameOf: (_) => 'Ramesh Kumar');
      await live.refresh();
    });
    addTearDown(() => tester.runAsync(live.dispose));

    await pumpRk(
      tester,
      ReviewQueueScope(
        queue: live,
        child: InboxScreen(onOpenLedger: () {}, onReviewGroup: (_) {}),
      ),
      viewport: rkTallViewport,
    );

    expect(live.current!.reviews.single.entries.single.paise, -120_000);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('1 entry'), findsOneWidget);
  });
}
