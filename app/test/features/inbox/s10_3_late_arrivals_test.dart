// F1-07-180 … F1-07-189 — S10.3 Late Arrivals tray and its S6 section
// (13 §3.2 row S10.3, parent S6; 07 §13 🔒; 02 §8 🔒; ADR 2026-09-05e §3, §10).
//
// What these tests hold in place:
//  · **nothing here is pending** (02 §3 🔒, 02 §8 🔒) — the card says in words
//    that the money is already counted, and no state on this surface draws it
//    as held, waiting or not yet in the book;
//  · consumer vocabulary — *Money in / Money out*, never Dr/Cr (02 §10 🔒);
//  · *Re-date to today* is the one-tap default and *Re-open {month}* the
//    scary-styled second action behind a confirm sheet that will not submit
//    without a reason (07 §13 🔒, 02 §7.2 item 3 🔒);
//  · a month inside a **closed** financial year is never offered a re-open —
//    the card states why and points at the year-close ceremony instead of a
//    tap that can only be refused (02 §8.1 🔒, 02 §7.2.1 🔒, 07 §1 rule 6);
//  · every 13 §4.3 state: loading skeleton, populated, empty (with the viewer
//    variant of 13 §2.3.1), error-with-retry, non-blocking offline chip, and
//    per-card busy / failed / refused;
//  · EN/PA/HI at 1.3 and 2.0 on both F1 phones without a cut word.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart' show LocalDate, YearMonth;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/late_arrivals.dart';
import 'package:rukka_folio/features/inbox/review_queue.dart';
import 'package:rukka_folio/features/inbox/screens/s10_3_late_arrivals_screen.dart';
import 'package:rukka_folio/features/inbox/screens/s6_inbox_screen.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

/// Synthetic figures only (CLAUDE.md rule 4).
LateArrivalItem _item({
  String entryId = 'e1',
  int paise = 2_340_00,
  String? closedYear,
  LocalDate? lockedOn,
  String? note = 'Saturday takings',
}) => LateArrivalItem(
  entryId: entryId,
  bookId: 'b1',
  bookName: 'Kirana Store',
  lockedPeriod: YearMonth(2026, 8),
  date: LocalDate(2026, 8, 29),
  paise: paise,
  fromLabel: 'Shop sales',
  toLabel: 'Cash in hand',
  note: note,
  lockedOn: lockedOn ?? LocalDate(2026, 9, 2),
  closedYear: closedYear,
);

/// Every string actually painted, however it was built.
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

bool _says(WidgetTester tester, String needle) =>
    _painted(tester).any((s) => s.contains(needle));

/// A tray whose re-date hangs until the test releases it, so the per-card
/// busy state (13 §4.3) can be observed at all — [FakeLateArrivals] completes
/// in a microtask, which no pump can catch.
class _SlowLateArrivals extends FakeLateArrivals {
  _SlowLateArrivals({super.initial});

  final release = Completer<void>();

  @override
  Future<void> redateToToday(String entryId) async {
    await release.future;
    return super.redateToToday(entryId);
  }
}

Widget _screen(FakeLateArrivals tray, {VoidCallback? onDone}) =>
    LateArrivalsScope(
      tray: tray,
      child: LateArrivalsScreen(onDone: onDone ?? () {}),
    );

void main() {
  testWidgets('F1-07-180 S10.3 shows the entry, why it is here, and that it '
      'already counts', (tester) async {
    final tray = FakeLateArrivals(initial: LateArrivalsTray(items: [_item()]));
    addTearDown(tray.dispose);
    await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

    // The entry itself, in consumer words (02 §10 🔒).
    expect(_says(tester, 'Money in'), isTrue);
    expect(_says(tester, '2,340'), isTrue);
    expect(_says(tester, 'Shop sales'), isTrue);
    expect(_says(tester, 'Cash in hand'), isTrue);
    expect(_says(tester, 'Saturday takings'), isTrue);

    // Why it is here (07 §13 🔒): the date it carries, the book, the month
    // that had already closed, and when it closed.
    expect(_says(tester, 'Aug 2026'), isTrue);
    expect(_says(tester, 'Kirana Store'), isTrue);
    expect(_says(tester, 'already been closed'), isTrue);

    // 02 §3 🔒 / 02 §8 🔒 — already counted, said outright.
    expect(_says(tester, 'already counted in your balances'), isTrue);

    // Both actions, the default first (07 §13 🔒).
    expect(find.text('Re-date to today'), findsOneWidget);
    expect(find.text('Re-open Aug 2026'), findsOneWidget);

    // Nothing on this surface may read as a hold (02 §3 🔒).
    for (final line in _painted(tester)) {
      expect(line.toLowerCase(), isNot(contains('pending')));
      expect(line.toLowerCase(), isNot(contains('not yet')));
      // Consumer surface: never Dr/Cr (02 §10 🔒).
      expect(line, isNot(contains('Debit')));
      expect(line, isNot(contains('Credit')));
    }
  });

  testWidgets(
    'F1-07-180 S10.3 says Money out for an entry that took money out',
    (tester) async {
      final tray = FakeLateArrivals(
        initial: LateArrivalsTray(items: [_item(paise: -1_250_00)]),
      );
      addTearDown(tray.dispose);
      await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

      expect(_says(tester, 'Money out'), isTrue);
      expect(_says(tester, 'Money in'), isFalse);
      // The magnitude is drawn, never a minus sign standing in for the word.
      expect(_says(tester, '1,250'), isTrue);
    },
  );

  testWidgets(
    'F1-07-181 S10.3 draws the ruled skeleton until the first tray arrives',
    (tester) async {
      final tray = FakeLateArrivals()
        ..onRefresh = LateArrivalsTray(items: [_item()]);
      addTearDown(tray.dispose);

      await tester.pumpWidget(const SizedBox());
      await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

      // The post-frame refresh has run by now and replaced the skeleton.
      expect(find.byType(LateArrivalsSkeleton), findsNothing);
      expect(find.text('Re-date to today'), findsOneWidget);
    },
  );

  testWidgets(
    'F1-07-181 S10.3 announces the skeleton while nothing is loaded',
    (tester) async {
      // A tray that never resolves: `refresh` leaves `current` null.
      final tray = FakeLateArrivals();
      addTearDown(tray.dispose);
      await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

      expect(find.byType(LateArrivalsSkeleton), findsOneWidget);
      expect(find.bySemanticsLabel('Loading late arrivals'), findsOneWidget);
    },
  );

  testWidgets(
    'F1-07-182 S10.3 empty is a friendly line plus its one next action',
    (tester) async {
      final tray = FakeLateArrivals(initial: const LateArrivalsTray());
      addTearDown(tray.dispose);
      var done = 0;
      await pumpRk(
        tester,
        _screen(tray, onDone: () => done++),
        viewport: rkTallViewport,
      );

      expect(_says(tester, 'Nothing arrived late.'), isTrue);
      // No dead end (07 §1 rule 6).
      await tester.tap(find.text('Back to your inbox'));
      await tester.pumpAndSettle();
      expect(done, 1);
    },
  );

  testWidgets(
    'F1-07-182 S10.3 states the capability for a viewer (13 §2.3 🔒)',
    (tester) async {
      final tray = FakeLateArrivals(
        initial: const LateArrivalsTray(readOnly: true),
      );
      addTearDown(tray.dispose);
      await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

      expect(_says(tester, 'You can view this book.'), isTrue);
      expect(_says(tester, 'not part of your access'), isTrue);
      // Never a bare tray: the reason is on the screen, not implied.
      expect(_says(tester, 'Nothing arrived late.'), isFalse);
    },
  );

  testWidgets('F1-07-183 S10.3 error names the cause and retries', (
    tester,
  ) async {
    final tray = FakeLateArrivals()
      ..failNext = const LateArrivalsFailure('no db');
    addTearDown(tray.dispose);
    await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

    expect(_says(tester, 'Couldn’t load late arrivals.'), isTrue);
    expect(find.text('Try again'), findsOneWidget);

    tray.onRefresh = LateArrivalsTray(items: [_item()]);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Re-date to today'), findsOneWidget);
    expect(_says(tester, 'Couldn’t load late arrivals.'), isFalse);
  });

  testWidgets(
    'F1-07-184 S10.3 offline is a chip beside the tray, never a block',
    (tester) async {
      final tray = FakeLateArrivals(
        initial: LateArrivalsTray(items: [_item()]),
      );
      addTearDown(tray.dispose);
      final sync = FakeSyncClient(initial: const Offline());
      addTearDown(sync.dispose);
      await pumpRk(tester, _screen(tray), sync: sync, viewport: rkTallViewport);

      expect(_says(tester, 'Offline'), isTrue);
      // The work is still reachable (07 §1 rule 7).
      expect(find.text('Re-date to today'), findsOneWidget);
      await tester.tap(find.text('Re-date to today'));
      await tester.pumpAndSettle();
      expect(tray.redated, ['e1']);
    },
  );

  testWidgets(
    'F1-07-185 re-date to today is one tap and keeps the entry in the book',
    (tester) async {
      final tray = FakeLateArrivals(
        initial: LateArrivalsTray(items: [_item()]),
      );
      addTearDown(tray.dispose);
      await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

      await tester.tap(find.text('Re-date to today'));
      await tester.pumpAndSettle();

      // One tap, no confirm sheet in the way (02 §8 🔒 "default, one tap").
      expect(tray.redated, ['e1']);
      // An amend, not a reversal: the confirmation says so.
      expect(_says(tester, 'It stays in the book either way'), isTrue);
    },
  );

  testWidgets('F1-07-185 a card in flight says so and cannot be tapped twice', (
    tester,
  ) async {
    final tray = _SlowLateArrivals(initial: LateArrivalsTray(items: [_item()]));
    addTearDown(tray.dispose);
    await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

    await tester.tap(find.text('Re-date to today'));
    await tester.pump();

    // Busy is per card, and it replaces the actions rather than leaving a
    // second tap reachable (07 §1 rule 6).
    expect(_says(tester, 'Sending…'), isTrue);
    expect(find.text('Re-date to today'), findsNothing);
    expect(find.text('Re-open Aug 2026'), findsNothing);

    tray.release.complete();
    await tester.pumpAndSettle();
    expect(tray.redated, ['e1']);
  });

  testWidgets(
    'F1-07-186 re-open will not submit without a reason, then reaches the '
    'seam with it',
    (tester) async {
      final tray = FakeLateArrivals(
        initial: LateArrivalsTray(items: [_item()]),
      );
      addTearDown(tray.dispose);
      await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

      await tester.tap(find.text('Re-open Aug 2026'));
      await tester.pumpAndSettle();

      // The consequence is stated before the confirm (07 §1 rule 6, 13 §8).
      expect(_says(tester, 'will need closing again'), isTrue);
      expect(_says(tester, 'Your name and reason are recorded'), isTrue);

      // Blank reason: refused by the sheet, nothing authored.
      await tester.tap(find.widgetWithText(FilledButton, 'Re-open Aug 2026'));
      await tester.pumpAndSettle();
      expect(tray.reopened, isEmpty);
      expect(_says(tester, 'Write a reason first'), isTrue);

      await tester.enterText(find.byType(TextField), '  Missed the cut-off  ');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Re-open Aug 2026'));
      await tester.pumpAndSettle();

      expect(tray.reopened, hasLength(1));
      expect(tray.reopened.single.bookId, 'b1');
      expect(tray.reopened.single.period, YearMonth(2026, 8));
      expect(tray.reopened.single.reason, 'Missed the cut-off');
    },
  );

  testWidgets('F1-07-187 a closed financial year is never offered a re-open', (
    tester,
  ) async {
    final tray = FakeLateArrivals(
      initial: LateArrivalsTray(items: [_item(closedYear: 'FY 2025–26')]),
    );
    addTearDown(tray.dispose);
    await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

    // No tap that can only be refused (07 §1 rule 6).
    expect(find.text('Re-open Aug 2026'), findsNothing);
    // The reason is a plain sentence pointing at the year-close ceremony.
    expect(_says(tester, 'FY 2025–26'), isTrue);
    expect(_says(tester, 'year-close ceremony'), isTrue);
    // The one-tap default survives.
    expect(find.text('Re-date to today'), findsOneWidget);
  });

  testWidgets(
    'F1-07-187 a re-open the book refuses is one sentence, not an error',
    (tester) async {
      final tray = FakeLateArrivals(initial: LateArrivalsTray(items: [_item()]))
        ..refuseNextReopen = const ReopenRefused(ReopenRefusal.notLocked);
      addTearDown(tray.dispose);
      await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

      await tester.tap(find.text('Re-open Aug 2026'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Missed the cut-off');
      await tester.tap(find.widgetWithText(FilledButton, 'Re-open Aug 2026'));
      await tester.pumpAndSettle();

      expect(_says(tester, 'is open again — somebody re-opened it'), isTrue);
      expect(_says(tester, 'Nothing was changed.'), isTrue);
      // The card is still there, still actionable.
      expect(find.text('Re-date to today'), findsOneWidget);
    },
  );

  testWidgets(
    'F1-07-188 a failed write is held on its own card and changed nothing',
    (tester) async {
      final tray = FakeLateArrivals(
        initial: LateArrivalsTray(
          items: [
            _item(),
            _item(entryId: 'e2', paise: -99_900),
          ],
        ),
      )..failNext = const LateArrivalsFailure('offline write');
      addTearDown(tray.dispose);
      await pumpRk(tester, _screen(tray), viewport: rkTallViewport);

      await tester.tap(find.text('Re-date to today').first);
      await tester.pumpAndSettle();

      // Append-only: a failure changed nothing (02 rule 2).
      expect(tray.redated, isEmpty);
      expect(_says(tester, 'Nothing has changed.'), isTrue);
      // Per card: the other card is untouched and still offers both actions.
      expect(find.text('Re-date to today'), findsNWidgets(2));
      expect(find.text('Re-open Aug 2026'), findsNWidgets(2));
    },
  );

  testWidgets('F1-07-189 S6 counts what arrived late and opens S10.3', (
    tester,
  ) async {
    final tray = FakeLateArrivals(
      initial: LateArrivalsTray(
        items: [
          _item(),
          _item(entryId: 'e2', paise: -99_900),
        ],
      ),
    );
    addTearDown(tray.dispose);
    final queue = FakeReviewQueue(initial: const InboxSnapshot());
    addTearDown(queue.dispose);
    var opened = 0;
    await pumpRk(
      tester,
      LateArrivalsScope(
        tray: tray,
        child: ReviewQueueScope(
          queue: queue,
          child: InboxScreen(
            onOpenLedger: () {},
            onOpenLateArrivals: () => opened++,
          ),
        ),
      ),
      viewport: rkTallViewport,
    );

    expect(
      _says(tester, '2 entries arrived after their month had closed'),
      isTrue,
    );
    // Post-then-review on S6 too (02 §3 🔒).
    expect(_says(tester, 'already counted in your balances'), isTrue);
    // An inbox holding only late arrivals is not an empty inbox.
    expect(_says(tester, 'Nothing needs you'), isFalse);

    await tester.tap(find.text('Open late arrivals'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets(
    'F1-07-189 S6 draws no late-arrivals section when the tray is empty',
    (tester) async {
      final tray = FakeLateArrivals(initial: const LateArrivalsTray());
      addTearDown(tray.dispose);
      final queue = FakeReviewQueue(initial: const InboxSnapshot());
      addTearDown(queue.dispose);
      await pumpRk(
        tester,
        LateArrivalsScope(
          tray: tray,
          child: ReviewQueueScope(
            queue: queue,
            child: InboxScreen(onOpenLedger: () {}, onOpenLateArrivals: () {}),
          ),
        ),
        viewport: rkTallViewport,
      );

      expect(find.text('Open late arrivals'), findsNothing);
      // S6's own empty state still states what this reader may do here.
      expect(_says(tester, 'Arrived after the month closed'), isFalse);
    },
  );

  // ── layout sweep ────────────────────────────────────────────────────────
  for (final locale in rkLocales) {
    for (final scale in rkTextScales) {
      for (final phone in rkPhones) {
        testWidgets('F1-07-180 S10.3 fits ${locale.languageCode} at $scale on '
            '${phone.width.toInt()}×${phone.height.toInt()}', (tester) async {
          final tray = FakeLateArrivals(
            initial: LateArrivalsTray(
              items: [
                _item(),
                _item(entryId: 'e2', closedYear: 'FY 2025–26'),
              ],
            ),
          );
          addTearDown(tray.dispose);
          await pumpRk(
            tester,
            _screen(tray),
            locale: locale,
            textScale: scale,
            viewport: phone,
          );
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason: 'S10.3 ${locale.languageCode} @$scale ${phone.width}',
          );
        });

        testWidgets(
          'F1-07-189 S6 late section fits ${locale.languageCode} at $scale on '
          '${phone.width.toInt()}×${phone.height.toInt()}',
          (tester) async {
            final tray = FakeLateArrivals(
              initial: LateArrivalsTray(items: [_item()]),
            );
            addTearDown(tray.dispose);
            final queue = FakeReviewQueue(initial: const InboxSnapshot());
            addTearDown(queue.dispose);
            await pumpRk(
              tester,
              LateArrivalsScope(
                tray: tray,
                child: ReviewQueueScope(
                  queue: queue,
                  child: InboxScreen(
                    onOpenLedger: () {},
                    onOpenLateArrivals: () {},
                  ),
                ),
              ),
              locale: locale,
              textScale: scale,
              viewport: phone,
            );
            expect(tester.takeException(), isNull);
            expectTextFits(
              tester,
              reason: 'S6 late ${locale.languageCode} @$scale',
            );
          },
        );
      }
    }
  }

  testWidgets(
    'F1-07-186 the re-open sheet fits pa at 2.0 on the narrow phone',
    (tester) async {
      final tray = FakeLateArrivals(
        initial: LateArrivalsTray(items: [_item()]),
      );
      addTearDown(tray.dispose);
      await pumpRk(
        tester,
        _screen(tray),
        locale: const Locale('pa'),
        textScale: 2,
        viewport: rkPhone360,
      );
      // At 200 % the card is taller than the phone, so the scary-styled
      // second action sits below the fold — scroll to it, or the tap silently
      // misses and the sweep measures a screen with no sheet on it.
      await tester.ensureVisible(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectTextFits(tester, reason: 'S10.3 re-open sheet pa @2.0');
    },
  );
}
