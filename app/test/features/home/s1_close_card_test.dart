// F1-07-140…142: the Home **Close card** 🔒 (07 §13 bullet 1, 07 §4 card
// placement, 13 §3.2 rows S10 and S10.2).
//
// 07 §13 🔒: *"Close card appears on Home from the 1st for each book the user
// closes: `Close August ▸ 4 steps`."* The three states of that card, and the
// fourth that rides on top of them, are a small state machine, so they are
// asserted the way a state machine has to be: the **path** the card links, not
// a callback; the **words** in all three languages; and the fact that a device
// id never reaches the screen.
//
// The seam is the feature-local [CloseSource], exactly as S10 uses it, so Home
// never learns what a close is — it reads a status and draws a card.
//
// Every amount is synthetic (CLAUDE.md rule 4); the clock is the test clock,
// 7 Sep 2026, so the month the card offers is **August 2026** (07 §13: from
// the 1st, the month that has just ended).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/close/close_routes.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_close_card.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/format/date_format.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

final august = YearMonth(2026, 8);

/// A [CloseSource] answering with [statuses] and nothing else — Home needs
/// only `closeStatuses`, and a fake that answered more would let a test pass
/// on a read the screen must not make.
FakeCloseSource closeSource(List<BookCloseStatus> statuses, String bookId) =>
    FakeCloseSource(
      view: CloseView(
        bookId: bookId,
        bookName: 'Kirana',
        period: august,
        cashAccounts: const [],
        bankAccounts: const [],
        tray: const CloseTray(),
      ),
    )..statuses = statuses;

BookCloseStatus status(
  String bookId, {
  BookCloseState state = BookCloseState.notStarted,
  CloseStep? step,
  String? waitingOn,
  YearMonth? period,
  String name = 'Kirana',
}) => BookCloseStatus(
  bookId: bookId,
  bookName: name,
  period: period ?? august,
  state: state,
  step: step,
  waitingOn: waitingOn,
);

/// Distinguishes one pump from the next, so re-pumping builds a **new**
/// [State] rather than updating the one already mounted — which is what
/// *coming back to Home* means, and the only way one test can walk the card
/// through its three states.
int _pumpSeq = 0;

/// Home with a close seam, pumped fresh.
Future<void> pumpHome(
  WidgetTester tester,
  LocalLedger ledger, {
  required FakeCloseSource source,
  required List<String> opened,
}) => pumpRk(
  tester,
  HomeScreen(
    key: ValueKey('home-close-${_pumpSeq++}'),
    closeSource: source,
    onOpenClose: (path) async => opened.add(path),
  ),
  ledger: ledger,
  viewport: rkTallViewport,
);

AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(HomeScreen)));

/// Tears the tree down **inside** the test: cancelling drift's query stream
/// schedules a zero-duration timer, and only a pump inside the test fires it
/// before the binding's pending-timer invariant runs (the same helper the
/// other S1 test files carry).
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('S1 Home close card (07 §13 🔒 bullet 1)', () {
    // ── F1-07-140 · the three states, and the path each one links ────────────

    testWidgets(
      'F1-07-140 the card offers the month that ended, resumes where the '
      'closer stopped, and gives way to the S10.2 door once the month closed',
      (tester) async {
        final seed = await seedSoloLedger();
        final book = seed.bookId;

        // — not started: `Close Aug 2026`, the size of the job, into S10.
        var opened = <String>[];
        await pumpHome(
          tester,
          seed.ledger,
          source: closeSource([status(book)], book),
          opened: opened,
        );
        final l = stringsOf(tester);
        final month = '${monthName(l, 8)} 2026';
        expect(find.byKey(HomeCloseKeys.card(book)), findsOneWidget);
        expect(find.text(l.homeCloseTitle(month)), findsWidgets);
        expect(find.text(l.homeCloseSteps(4)), findsOneWidget);
        await tester.tap(find.byKey(HomeCloseKeys.action(book)));
        await tester.pumpAndSettle();
        // The path is `YearMonth.toString()`'s own `YYYY-MM`, so the card and
        // the route agree by construction (close_paths.dart).
        expect(opened, [ClosePaths.forBook(book, '2026-08')]);

        // — in progress: it *resumes* (07 §13 *Resumable* 🔒).
        opened = <String>[];
        await pumpHome(
          tester,
          seed.ledger,
          source: closeSource([
            status(
              book,
              state: BookCloseState.inProgress,
              step: CloseStep.clearTray,
            ),
          ], book),
          opened: opened,
        );
        expect(find.text(l.homeCloseResume(3, 4)), findsOneWidget);
        expect(find.text(l.homeCloseSteps(4)), findsNothing);
        await tester.tap(find.byKey(HomeCloseKeys.action(book)));
        await tester.pumpAndSettle();
        expect(opened, [ClosePaths.forBook(book, '2026-08')]);

        // — closed ✓: the card gives way to the S10.2 door for that month.
        opened = <String>[];
        await pumpHome(
          tester,
          seed.ledger,
          source: closeSource([
            status(book, state: BookCloseState.closed),
          ], book),
          opened: opened,
        );
        expect(find.text(l.homeCloseDoneTitle(month)), findsOneWidget);
        expect(find.text(l.homeCloseTitle(month)), findsNothing);
        expect(find.text(l.homeCloseDoneAction), findsOneWidget);
        await tester.tap(find.byKey(HomeCloseKeys.action(book)));
        await tester.pumpAndSettle();
        expect(opened, [ClosePaths.summaryFor(book, '2026-08')]);
        await unmount(tester);
      },
    );

    // ── F1-07-141 · waiting on a phone, and never a device id ────────────────

    testWidgets(
      'F1-07-141 a book waiting on a phone says so on the card, never prints '
      'a device id, and still opens the wizard',
      (tester) async {
        final seed = await seedSoloLedger();
        final book = seed.bookId;
        final opened = <String>[];
        await pumpHome(
          tester,
          seed.ledger,
          source: closeSource([
            status(book, state: BookCloseState.waiting),
          ], book),
          opened: opened,
        );
        final l = stringsOf(tester);
        // No name yet (`author_gaps.author_device` is an id — see
        // `ledger_close_source.dart`), so the card says *another phone*.
        expect(
          find.text(l.homeCloseWaiting(l.closeBlockedUnknownDevice)),
          findsOneWidget,
        );
        // 07 §1 rule 6: the door still opens — the first three steps are
        // useful work, and S10.5 is what explains the lock.
        expect(
          tester
              .widget<ButtonStyleButton>(find.byKey(HomeCloseKeys.action(book)))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(HomeCloseKeys.action(book)));
        await tester.pumpAndSettle();
        expect(opened, [ClosePaths.forBook(book, '2026-08')]);

        // A named phone is named.
        await pumpHome(
          tester,
          seed.ledger,
          source: closeSource([
            status(
              book,
              state: BookCloseState.waiting,
              waitingOn: 'Pankaj’s phone',
            ),
          ], book),
          opened: opened,
        );
        expect(find.text(l.homeCloseWaiting('Pankaj’s phone')), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-141 with no close seam Home draws no card and is otherwise whole',
      (tester) async {
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          const HomeScreen(),
          ledger: seed.ledger,
          viewport: rkTallViewport,
        );
        expect(find.byType(HomeCloseCards), findsOneWidget);
        expect(find.byKey(HomeCloseKeys.card(seed.bookId)), findsNothing);
        // The surface Home exists for is untouched.
        expect(find.text('Total money you have'), findsOneWidget);
        await unmount(tester);
      },
    );

    // ── F1-07-142 · every language, both phones, both scales ─────────────────
    //
    // The card is pumped **on its own** here, not inside Home's lazy list: the
    // question is whether this card's own words fit a 360 px phone at 200 %,
    // and a sliver that was never built has no width to measure. Home's list
    // layout is F1-07-49/50's to prove.

    for (final locale in rkLocales) {
      for (final scale in rkTextScales) {
        for (final phone in rkPhones) {
          testWidgets(
            'F1-07-142 the close card holds at ${(scale * 100).round()} % in '
            '${locale.languageCode} on ${phone.width.toInt()}×'
            '${phone.height.toInt()}',
            (tester) async {
              await pumpRk(
                tester,
                Scaffold(
                  body: ListView(
                    children: [
                      HomeCloseCards(
                        showBookName: true,
                        statuses: [
                          // The longest line the card can draw: a Gurmukhi
                          // book name, the resume line and the waiting line.
                          status(
                            'b1',
                            state: BookCloseState.waiting,
                            step: CloseStep.confirmBanks,
                            name: 'ਸਾਂਝਾ ਜੁਆਇੰਟ ਪੂਲ',
                          ),
                          status(
                            'b2',
                            state: BookCloseState.inProgress,
                            step: CloseStep.clearTray,
                            name: 'ਖੇਤੀਬਾੜੀ',
                          ),
                          status(
                            'b3',
                            state: BookCloseState.closed,
                            name: 'ਕਰਿਆਨਾ',
                          ),
                          status('b4', name: 'Kirana'),
                        ],
                        onOpenClose: (_) {},
                        onOpenSummary: (_) {},
                      ),
                    ],
                  ),
                ),
                locale: locale,
                textScale: scale,
                viewport: phone,
              );
              expect(tester.takeException(), isNull);
              expectTextFits(
                tester,
                reason:
                    'Home close card, ${locale.languageCode} at $scale on '
                    '${phone.width}×${phone.height}',
              );
              // Scroll the rest of the section through the same viewport: the
              // closed card's own words have to fit too.
              await tester.drag(find.byType(ListView), const Offset(0, -600));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expectTextFits(
                tester,
                reason:
                    'Home close card (scrolled), ${locale.languageCode} at '
                    '$scale on ${phone.width}×${phone.height}',
              );
            },
          );
        }
      }
    }
  });
}
