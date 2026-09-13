// F1-07-23 — S6 Inbox and the S6.1 grouped review card (07 §9 🔒, 02 §3 🔒).
//
// What these tests hold in place:
//  · one card per author + book + day, with count and total (07 §9, 13 §4.1);
//  · post-then-review: the card says the entries are already in the book, and
//    never draws the money as pending (02 §3 🔒);
//  · consumer vocabulary — *Money in / Money out*, never Dr/Cr (02 §10 🔒);
//  · every 13 §4.3 list state, including the viewer variant of 13 §2.3.1;
//  · no dead ends (07 §1 rule 6): the empty state carries its one next action;
//  · EN/PA/HI at 1.3 and 2.0 on 360×800 without a cut word.
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/inbox_routes.dart';
import 'package:rukka_folio/features/inbox/review_queue.dart';
import 'package:rukka_folio/features/inbox/screens/s6_inbox_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/main.dart' show rkLocalizationsDelegates;
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

ReviewGroup _group({int entries = 3, String id = 'g1'}) => ReviewGroup(
  id: id,
  authorName: 'Ramesh Kumar',
  bookName: 'Kirana Store',
  day: LocalDate(2026, 9, 4),
  entries: [
    for (var i = 0; i < entries; i++)
      ReviewEntry(
        id: '$id-e$i',
        // Alternating direction: a card mixes money in and money out.
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

/// Every string actually painted, however it was built (Text or Text.rich).
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

Widget _screen(FakeReviewQueue queue, {VoidCallback? onOpenLedger}) =>
    ReviewQueueScope(
      queue: queue,
      child: InboxScreen(
        onOpenLedger: onOpenLedger ?? () {},
        onReviewGroup: (_) {},
      ),
    );

void main() {
  testWidgets(
    'F1-07-23 S6 groups flags into one card per author, book and day',
    (tester) async {
      final queue = FakeReviewQueue(
        initial: InboxSnapshot(reviews: [_group()]),
      );
      addTearDown(queue.dispose);
      await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

      expect(find.text('Ramesh Kumar'), findsOneWidget);
      expect(find.text('Kirana Store · 04 Sep 2026'), findsOneWidget);
      expect(find.text('3 entries'), findsOneWidget);
      // 23,400 + 1,250 + 23,400 = 48,050 — magnitudes, no sign, no colour.
      expect(find.text('₹48,050 in all'), findsOneWidget);
    },
  );

  testWidgets(
    'F1-07-23 S6.1 says the entries are already in the book (02 §3)',
    (tester) async {
      final queue = FakeReviewQueue(
        initial: InboxSnapshot(reviews: [_group()]),
      );
      addTearDown(queue.dispose);
      await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

      expect(
        find.textContaining('Already in the book'),
        findsOneWidget,
        reason:
            'post-then-review: the entry posted and counted on save (02 §3)',
      );
      final painted = _painted(tester).join(' | ').toLowerCase();
      for (final forbidden in ['pending', 'awaiting approval', 'on hold']) {
        expect(
          painted.contains(forbidden),
          isFalse,
          reason: '02 §3 defines no state in which posted money waits',
        );
      }
    },
  );

  testWidgets(
    'F1-07-23 S6.1 speaks Money in / Money out, never Dr/Cr (02 §10)',
    (tester) async {
      final queue = FakeReviewQueue(
        initial: InboxSnapshot(reviews: [_group()]),
      );
      addTearDown(queue.dispose);
      await pumpRk(tester, _screen(queue), viewport: rkTallViewport);
      await tester.tap(find.text('Show the entries'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Money in', findRichText: true), findsWidgets);
      expect(
        find.textContaining('Money out', findRichText: true),
        findsWidgets,
      );
      final painted = _painted(tester);
      for (final line in painted) {
        expect(
          RegExp(r'\b(Dr|Cr)\b').hasMatch(line),
          isFalse,
          reason: 'the Inbox is a consumer surface (02 §10 🔒): "$line"',
        );
      }
    },
  );

  testWidgets(
    'F1-07-23 S6.1 Approve all clears every flag in one tap (07 §9)',
    (tester) async {
      final queue = FakeReviewQueue(
        initial: InboxSnapshot(reviews: [_group()]),
      );
      addTearDown(queue.dispose);
      await pumpRk(tester, _screen(queue), viewport: rkTallViewport);

      await tester.tap(find.text('Approve all'));
      await tester.pumpAndSettle();

      expect(queue.approvedGroups, ['g1']);
      expect(queue.current!.reviews, isEmpty);
      expect(
        find.textContaining('Nothing needs you right now'),
        findsOneWidget,
      );
    },
  );

  testWidgets('F1-07-23 S6.1 quick reject cannot be sent without a reason', (
    tester,
  ) async {
    final queue = FakeReviewQueue(initial: InboxSnapshot(reviews: [_group()]));
    addTearDown(queue.dispose);
    await pumpRk(tester, _screen(queue), viewport: rkTallViewport);
    await tester.tap(find.text('Show the entries'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject and reverse'));
    await tester.pumpAndSettle();

    expect(queue.decisions, isEmpty, reason: 'a reason is required (07 §9)');
    expect(find.textContaining('Write a reason first'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'This bill is not ours');
    await tester.tap(find.text('Reject and reverse'));
    await tester.pumpAndSettle();

    expect(queue.decisions.single.decision, ReviewDecision.reject);
    expect(queue.decisions.single.reason, 'This bill is not ours');
    expect(queue.decisions.single.entryId, 'g1-e0');
  });

  testWidgets('F1-07-23 S6 empty state offers its one next action (07 §1.6)', (
    tester,
  ) async {
    final queue = FakeReviewQueue(initial: const InboxSnapshot());
    addTearDown(queue.dispose);
    var opened = 0;
    await pumpRk(
      tester,
      _screen(queue, onOpenLedger: () => opened++),
      viewport: rkPhone360,
    );

    expect(find.text('Nothing needs you right now.'), findsOneWidget);
    await tester.tap(find.text('Open your books'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('F1-07-23 S6 viewer is told why the tray is empty (13 §2.3.1)', (
    tester,
  ) async {
    final queue = FakeReviewQueue(initial: const InboxSnapshot(readOnly: true));
    addTearDown(queue.dispose);
    await pumpRk(tester, _screen(queue), viewport: rkPhone360);

    expect(find.text('You can view this book.'), findsOneWidget);
    expect(
      find.textContaining('not part of your access'),
      findsOneWidget,
      reason: 'never hide a capability silently (13 §2.3 🔒)',
    );
    expect(find.text('Open your books'), findsOneWidget);
  });

  testWidgets('F1-07-23 S6 shows the skeleton, then the error with a retry', (
    tester,
  ) async {
    final queue = FakeReviewQueue()..failNext = const ReviewQueueFailure();
    addTearDown(queue.dispose);
    await pumpRk(tester, _screen(queue), viewport: rkPhone360);

    expect(find.textContaining('Couldn’t load your inbox'), findsOneWidget);

    queue.onRefresh = InboxSnapshot(reviews: [_group(entries: 1)]);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('1 entry'), findsOneWidget);
  });

  testWidgets(
    'F1-07-23 S6 offline is a quiet chip, never a blocker (07 §1.7)',
    (tester) async {
      final queue = FakeReviewQueue(
        initial: InboxSnapshot(reviews: [_group(entries: 1)]),
      );
      addTearDown(queue.dispose);
      final sync = FakeSyncClient(initial: const Offline());
      await pumpRk(
        tester,
        _screen(queue),
        sync: sync,
        viewport: rkTallViewport,
      );

      expect(find.textContaining('Offline'), findsOneWidget);
      expect(find.text('Approve all'), findsOneWidget);
    },
  );

  for (final locale in rkLocales) {
    for (final scale in rkTextScales) {
      testWidgets(
        'F1-07-23 S6 fits 360×800 at ${scale}x in ${locale.languageCode}',
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

          // Again with the card open: the rows carry the amount, its
          // direction word and the quick reject on one 360 px line.
          await tester.tap(find.byType(InkWell).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason: 'expanded, ${locale.languageCode} @ $scale',
          );
        },
      );
    }
  }

  testWidgets('F1-07-23 S6.2 mounts at /inbox/review/<group> (13 §3.1 depth)', (
    tester,
  ) async {
    final queue = FakeReviewQueue(
      initial: InboxSnapshot(reviews: [_group(entries: 2)]),
    );
    addTearDown(queue.dispose);
    rkViewport(tester, rkTallViewport);

    expect(InboxPaths.stepperFor('g1'), '/inbox/review/g1');
    // The feature's own routes, on a bare router: this is the wiring this
    // lane owns. Composing them into the shell is `main.dart`'s (see the
    // lane report's open item about tab-root height inside RkShell).
    final router = GoRouter(
      routes: inboxRoutes,
      initialLocation: InboxPaths.stepperFor('g1'),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RkScope(
        db: await openTestDb(),
        sync: FakeSyncClient(),
        auth: FakeAuthClient(),
        keys: FakeKeyStore(),
        now: testNow,
        child: ReviewQueueScope(
          queue: queue,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: rkLocalizationsDelegates,
            theme: rkTheme(Brightness.light),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Entered by Ramesh Kumar'), findsOneWidget);
  });
}
