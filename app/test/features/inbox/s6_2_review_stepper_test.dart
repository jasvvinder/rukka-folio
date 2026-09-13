// F1-07-23 — S6.2, the one-by-one review stepper (07 §9 🔒, 02 §3 🔒, §5).
//
// What these tests hold in place:
//  · progress in counts, advancing on every decision ("1 of 3" → "2 of 3");
//  · Approve writes a decision and moves on; nothing is approved unseen;
//  · Reject demands a reason and carries it to the engine seam (auto-reversal);
//  · Skip writes NOTHING — the flag stays exactly where it was;
//  · the entry is described as already in the book, never as pending (02 §3);
//  · consumer vocabulary (02 §10 🔒) and a way out of every end state.
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/review_queue.dart';
import 'package:rukka_folio/features/inbox/screens/s6_2_review_stepper_screen.dart';

import '../../shared/test_app.dart';

ReviewGroup _group({int entries = 3}) => ReviewGroup(
  id: 'g1',
  authorName: 'Ramesh Kumar',
  bookName: 'Kirana Store',
  day: LocalDate(2026, 9, 4),
  entries: [
    for (var i = 0; i < entries; i++)
      ReviewEntry(
        id: 'g1-e$i',
        paise: i.isEven ? 2_340_000 : -1_250_00,
        fromLabel: i.isEven ? 'Shop sales' : 'Cash in hand',
        toLabel: i.isEven ? 'Cash in hand' : 'Diesel',
        date: LocalDate(2026, 9, 4),
        postedAt: DateTime(2026, 9, 4, 18, 42),
        note: i == 0 ? 'Saturday takings' : null,
        hasPhoto: i == 0,
      ),
  ],
);

List<String> _painted(WidgetTester tester) {
  final out = <String>[];
  void visit(RenderObject o) {
    if (o is RenderParagraph) out.add(o.text.toPlainText());
    o.visitChildren(visit);
  }

  final root = tester.binding.rootElement?.renderObject;
  if (root != null) visit(root);
  return out;
}

Widget _screen(FakeReviewQueue queue, {String groupId = 'g1'}) =>
    ReviewQueueScope(
      queue: queue,
      child: ReviewStepperScreen(groupId: groupId, onDone: () {}),
    );

void main() {
  testWidgets('F1-07-23 S6.2 shows the entry as posted, in consumer words', (
    tester,
  ) async {
    final queue = FakeReviewQueue(initial: InboxSnapshot(reviews: [_group()]));
    addTearDown(queue.dispose);
    await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Entered by Ramesh Kumar'), findsOneWidget);
    expect(find.text('In Kirana Store'), findsOneWidget);
    expect(find.textContaining('Already in the book'), findsOneWidget);
    expect(find.textContaining('Money in', findRichText: true), findsOneWidget);
    expect(find.text('Saturday takings'), findsOneWidget);
    expect(find.text('04 Sep 2026, 18:42'), findsOneWidget);

    for (final line in _painted(tester)) {
      expect(
        RegExp(r'\b(Dr|Cr)\b').hasMatch(line),
        isFalse,
        reason: 'S6.2 is a consumer surface (02 §10 🔒): "$line"',
      );
      expect(
        line.toLowerCase().contains('pending'),
        isFalse,
        reason: '02 §3 defines no pending state for posted money',
      );
    }
  });

  testWidgets('F1-07-23 S6.2 Approve advances and reaches the end (07 §9)', (
    tester,
  ) async {
    final queue = FakeReviewQueue(
      initial: InboxSnapshot(reviews: [_group(entries: 2)]),
    );
    addTearDown(queue.dispose);
    await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(queue.decisions.map((d) => d.entryId), ['g1-e0', 'g1-e1']);
    expect(
      queue.decisions.every((d) => d.decision == ReviewDecision.approve),
      isTrue,
    );
    expect(find.textContaining('You have looked at all 2'), findsOneWidget);
    expect(
      find.text('Nothing from this card is left for you.'),
      findsOneWidget,
    );
    expect(find.text('Back to Inbox'), findsOneWidget);
  });

  testWidgets('F1-07-23 S6.2 Reject needs a reason and posts it (02 §3, §5)', (
    tester,
  ) async {
    final queue = FakeReviewQueue(
      initial: InboxSnapshot(reviews: [_group(entries: 1)]),
    );
    addTearDown(queue.dispose);
    await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('A reversal for the same amount'),
      findsOneWidget,
    );

    await tester.tap(find.text('Reject and reverse'));
    await tester.pumpAndSettle();
    expect(queue.decisions, isEmpty);
    expect(find.textContaining('Write a reason first'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Wrong shop');
    await tester.tap(find.text('Reject and reverse'));
    await tester.pumpAndSettle();

    expect(queue.decisions.single.decision, ReviewDecision.reject);
    expect(queue.decisions.single.reason, 'Wrong shop');
  });

  testWidgets(
    'F1-07-23 S6.2 Skip decides nothing and leaves the flag (07 §9)',
    (tester) async {
      final queue = FakeReviewQueue(
        initial: InboxSnapshot(reviews: [_group(entries: 2)]),
      );
      addTearDown(queue.dispose);
      await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

      expect(find.text('Stays in your inbox.'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(queue.decisions, isEmpty, reason: 'skip writes no envelope');
      expect(queue.current!.reviews.single.count, 2);
      expect(
        find.textContaining('2 entries you skipped are still in your inbox'),
        findsOneWidget,
      );
    },
  );

  testWidgets('F1-07-23 S6.2 rejecting one never blocks the rest (07 §9)', (
    tester,
  ) async {
    final queue = FakeReviewQueue(
      initial: InboxSnapshot(reviews: [_group(entries: 3)]),
    );
    addTearDown(queue.dispose);
    await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Not ours');
    await tester.tap(find.text('Reject and reverse'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 3'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(queue.decisions.length, 2);
  });

  testWidgets(
    'F1-07-23 S6.2 asks for a better photo without deciding (07 §9)',
    (tester) async {
      final queue = FakeReviewQueue(
        initial: InboxSnapshot(reviews: [_group(entries: 1)]),
      );
      addTearDown(queue.dispose);
      await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

      await tester.tap(find.text('Ask for a better photo'));
      await tester.pumpAndSettle();

      expect(queue.photoAsks, ['g1-e0']);
      expect(queue.decisions, isEmpty);
      expect(find.textContaining('Asked Ramesh Kumar'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
    },
  );

  testWidgets('F1-07-23 S6.2 a failed write says the flag is unchanged', (
    tester,
  ) async {
    final queue = FakeReviewQueue(
      initial: InboxSnapshot(reviews: [_group(entries: 1)]),
    );
    addTearDown(queue.dispose);
    await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

    queue.failNext = const ReviewQueueFailure();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('still waiting for you'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget, reason: 'no silent advance');
  });

  testWidgets('F1-07-23 S6.2 a card that has gone still offers the way back', (
    tester,
  ) async {
    final queue = FakeReviewQueue(initial: const InboxSnapshot());
    addTearDown(queue.dispose);
    await pumpRk(
      tester,
      _screen(queue, groupId: 'missing'),
      viewport: rkPhone360,
    );

    expect(find.text('That card is not here any more.'), findsOneWidget);
    expect(
      find.text('Back to Inbox'),
      findsOneWidget,
      reason: 'no dead ends (07 §1 rule 6)',
    );
  });

  for (final locale in rkLocales) {
    for (final scale in rkTextScales) {
      testWidgets(
        'F1-07-23 S6.2 fits 360×800 at ${scale}x in ${locale.languageCode}',
        (tester) async {
          final queue = FakeReviewQueue(
            initial: InboxSnapshot(reviews: [_group(entries: 2)]),
          );
          addTearDown(queue.dispose);
          await pumpRk(
            tester,
            _screen(queue),
            locale: locale,
            textScale: scale,
            viewport: rkPhone360,
          );

          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: '${locale.languageCode} @ $scale');
        },
      );
    }
  }
}
