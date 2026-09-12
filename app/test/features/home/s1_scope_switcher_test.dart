// F1 widget tests for the Home scope switcher (S1.2 / S1.3) and the S1.4
// rebuilding state: 07 §5.7 🔒 (two forms, decided by a count), 13 §2.2 🔒
// (Me | one Book | Everything; the chip only above one book; switching never
// loses the screen), 07 §28 🔒 + 11 §4.5 🔒 (determinate loader with a count,
// never a spinner), ADR 2026-09-05c §3/§6 (integrity_ok gates the return).
@Tags(['F1'])
library;

import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_rebuild.dart';
import 'package:rukka_folio/features/home/home_routes.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/features/home/widgets/home_everything.dart';
import 'package:rukka_folio/features/home/widgets/home_scope_switcher.dart';
import 'package:rukka_folio/features/home/widgets/home_states.dart';
import 'package:rukka_folio/shared/tokens.dart';

import '../../shared/test_app.dart';

/// A viewport tall enough that every card is laid out (a sliver below the
/// fold has no element, so `find` would not see it).
void tallViewport(
  WidgetTester tester, {
  double width = 400,
  double height = 3000,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Tears the tree down *inside* the test: cancelling drift's query stream
/// schedules a zero-duration timer, and only a pump inside the test fires it
/// before the binding's pending-timer invariant runs.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Pumps past `loader-appear-delay` (11 §4.5 🔒) and settles. S1.4 only
/// replaces the Home card once a rebuild has run longer than the delay.
Future<void> settleAfterAppearDelay(WidgetTester tester) async {
  await tester.pump(
    RkMotion.loaderAppearDelay + const Duration(milliseconds: 1),
  );
  await tester.pumpAndSettle();
}

/// The seeded solo book plus [extra] further books, so the switcher has a
/// real book list to group. Returns the seeded handle.
Future<SeededLedger> withBooks(
  List<(String, BookType)> extra, {
  bool seeded = true,
}) async {
  final seed = await seedSoloLedger();
  for (final (name, type) in extra) {
    await seed.ledger.createBook(
      name: name,
      type: type,
      startDate: seed.ledger.today().addDays(-7),
    );
  }
  return seed;
}

void main() {
  group('S1.2 scope switcher — two books (07 §5.7 🔒)', () {
    testWidgets(
      'F1-07-52 one book: no scope control renders at all (13 §2.2)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);

        expect(find.byType(HomeScopeControl), findsNothing);
        expect(find.byType(HomeScopeToggle), findsNothing);
        expect(find.byType(HomeScopeSheetButton), findsNothing);
        // And Home itself is unchanged.
        expect(find.byType(HomePositionCard), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-52 two books: the top bar shows the two-chip inline toggle',
      (tester) async {
        tallViewport(tester);
        final seed = await withBooks([('Shop', BookType.business)]);
        await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);

        expect(find.byType(HomeScopeToggle), findsOneWidget);
        // 🔒 07 §5.7: never the grouped sheet for exactly two books.
        expect(find.byType(HomeScopeSheetButton), findsNothing);
        expect(find.byType(HomeScopeSheet), findsNothing);
        expect(
          find.descendant(
            of: find.byType(HomeScopeToggle),
            matching: find.text('Me'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(HomeScopeToggle),
            matching: find.text('Shop'),
          ),
          findsOneWidget,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-52 tapping the other chip switches the body, not the screen',
      (tester) async {
        tallViewport(tester);
        final seed = await withBooks([('Shop', BookType.business)]);
        await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);

        // Me is seeded, so it has a position card and a real hero figure.
        expect(find.byType(HomePositionCard), findsOneWidget);
        expect(find.text('₹1,36,200'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(HomeScopeToggle),
            matching: find.text('Shop'),
          ),
        );
        await tester.pumpAndSettle();

        // Still S1 — nothing was pushed, the same screen re-rendered.
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text('Home'), findsOneWidget);
        expect(find.byType(HomeScopeToggle), findsOneWidget);
        // …in the other book, which has no entries at all.
        expect(find.byType(HomePositionCard), findsNothing);
        expect(find.byType(HomeSetupChecklist), findsOneWidget);
        expect(find.text('₹1,36,200'), findsNothing);

        // And back again, without leaving the screen.
        await tester.tap(
          find.descendant(
            of: find.byType(HomeScopeToggle),
            matching: find.text('Me'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HomePositionCard), findsOneWidget);
        await unmount(tester);
      },
    );

    // Layout sweep (09 suite F, ADR 2026-09-05f §H): both phone viewports,
    // 1.3 as well as 200 %, all three languages. The two-book toggle is the
    // widest thing on Home at 1.3× — both book names are still words there.
    for (final locale in rkLocales) {
      for (final size in rkPhones) {
        for (final scale in rkTextScales) {
          testWidgets('F1-07-52 the toggle holds in ${locale.languageCode} at '
              '${(scale * 100).round()}% on ${size.width.toInt()}x'
              '${size.height.toInt()}', (tester) async {
            final seed = await withBooks([('Shop', BookType.business)]);
            await pumpRk(
              tester,
              const HomeScreen(),
              ledger: seed.ledger,
              locale: locale,
              textScale: scale,
              viewport: size,
            );
            expect(tester.takeException(), isNull, reason: '$locale');
            expect(
              find.byType(HomeScopeToggle),
              findsOneWidget,
              reason: '$locale',
            );
            // The toggle still reaches both books: the chip row scrolls.
            expect(
              find.descendant(
                of: find.byType(HomeScopeToggle),
                matching: find.text('Shop'),
              ),
              findsOneWidget,
              reason: '$locale',
            );
            expectTextFits(tester, reason: '$locale');
            await unmount(tester);
          });
        }
      }
    }
  });

  group('S1.3 scope switcher — three or more books (07 §5.7 🔒)', () {
    testWidgets('F1-07-53 the control opens the grouped sheet, empty groups '
        'omitted', (tester) async {
      tallViewport(tester);
      final seed = await withBooks([
        ('Shop', BookType.business),
        ('Ghar', BookType.family),
      ]);
      await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);

      expect(find.byType(HomeScopeSheetButton), findsOneWidget);
      expect(find.byType(HomeScopeToggle), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(HomeScopeSheetButton),
          matching: find.byType(ActionChip),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScopeSheet), findsOneWidget);
      expect(find.text('Me'), findsWidgets);
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Businesses'), findsOneWidget);
      expect(find.text('Everything'), findsOneWidget);
      // No organization book exists, so that group is not drawn.
      expect(find.text('Organizations'), findsNothing);
      await unmount(tester);
    });

    testWidgets('F1-07-53 choosing a book re-renders Home in that scope', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await withBooks([
        ('Shop', BookType.business),
        ('Ghar', BookType.family),
      ]);
      await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);
      expect(find.byType(HomePositionCard), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(HomeScopeSheetButton),
          matching: find.byType(ActionChip),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HomeScopeSheet),
          matching: find.text('Shop'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScopeSheet), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(HomeSetupChecklist), findsOneWidget);
      expect(find.byType(HomePositionCard), findsNothing);
      await unmount(tester);
    });

    testWidgets('F1-07-53 Everything: one read-only card per book, no '
        'provisional badge without the flag', (tester) async {
      tallViewport(tester);
      final seed = await withBooks([
        ('Shop', BookType.business),
        ('Ghar', BookType.family),
      ]);
      await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);

      await tester.tap(
        find.descendant(
          of: find.byType(HomeScopeSheetButton),
          matching: find.byType(ActionChip),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HomeScopeSheet),
          matching: find.text('Everything'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeEverythingList), findsOneWidget);
      expect(find.byType(HomeBookCard), findsNWidgets(3));
      expect(find.text('Every book together — view only'), findsOneWidget);
      // Read-only: none of the posting affordances are on this surface.
      expect(find.byType(HomeVerbButtons), findsNothing);
      expect(find.byType(HomePositionCard), findsNothing);
      // No book has an author gap or a held envelope, so no badge — the UI
      // never infers one (13 §2.2, ADR 2026-09-05f §B).
      expect(find.text('Waiting for entries from another phone'), findsNothing);
      // Each book still names itself and its total.
      expect(find.text('Me'), findsWidgets);
      expect(find.text('Shop'), findsWidgets);
      expect(find.text('Ghar'), findsWidgets);
      await unmount(tester);
    });

    testWidgets(
      'F1-07-53 🔒 the grouped sheet is never shown for exactly two books',
      (tester) async {
        tallViewport(tester);
        final seed = await withBooks([('Shop', BookType.business)]);
        await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);

        expect(find.byType(HomeScopeSheetButton), findsNothing);
        await tester.tap(
          find.descendant(
            of: find.byType(HomeScopeToggle),
            matching: find.text('Shop'),
          ),
        );
        await tester.pumpAndSettle();
        // A chip switches; it never opens a sheet (07 §5.7 🔒).
        expect(find.byType(HomeScopeSheet), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        await unmount(tester);
      },
    );
  });

  group('S1.4 rebuilding (07 §28 🔒, 11 §4.5 🔒)', () {
    testWidgets('F1-07-38 the loader with a count replaces the Home card, '
        'then integrity_ok brings it back', (tester) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      final progress = StreamController<RebuildProgress?>();
      addTearDown(progress.close);
      await pumpRk(
        tester,
        HomeScreen(rebuildProgress: (_) => progress.stream),
        ledger: seed.ledger,
      );

      // Nothing rebuilding: the normal book shows.
      expect(find.byType(HomeRebuildingCard), findsNothing);
      expect(find.byType(HomePositionCard), findsOneWidget);

      progress.add(const RebuildProgress(done: 3, total: 10));
      await tester.pumpAndSettle();

      // `pumpAndSettle` has already run past `loader-appear-delay` here; the
      // delay itself is asserted by the short-rebuild test below.
      await settleAfterAppearDelay(tester);

      expect(find.byType(HomeRebuildingCard), findsOneWidget);
      expect(find.text('3 of 10 entries restored'), findsOneWidget);
      // The book is not shown as whole meanwhile (13 §3.2 row S1.4).
      expect(find.byType(HomePositionCard), findsNothing);
      expect(find.byType(HomeHero), findsNothing);
      expect(find.byType(HomeVerificationCard), findsNothing);
      // The loader is a determinate 2px rule — never a spinner, anywhere.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.3, 0.0001));

      // Progress moves; still a count, never a percentage.
      progress.add(const RebuildProgress(done: 10, total: 10));
      await tester.pumpAndSettle();
      expect(find.text('10 of 10 entries restored'), findsOneWidget);

      // Done, and the seeded book's integrity_ok is true: the card returns.
      progress.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(HomeRebuildingCard), findsNothing);
      expect(find.byType(HomePositionCard), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await unmount(tester);
    });

    // The rebuild line is one long sentence with two numbers in it, so it is
    // the narrowest fit on Home: swept over both viewports and both scales in
    // all three languages (09 suite F, ADR 2026-09-05f §H).
    for (final (locale, text) in const [
      (Locale('en'), '3 of 10 entries restored'),
      (Locale('pa'), '10 ਵਿੱਚੋਂ 3 ਇੰਦਰਾਜ ਵਾਪਸ ਆਏ'),
      (Locale('hi'), '10 में से 3 प्रविष्टियाँ वापस आईं'),
    ]) {
      for (final size in rkPhones) {
        for (final scale in rkTextScales) {
          testWidgets(
            'F1-07-38 the rebuild line resolves in ${locale.languageCode} at '
            '${(scale * 100).round()}% on ${size.width.toInt()}x'
            '${size.height.toInt()}',
            (tester) async {
              final seed = await seedSoloLedger();
              final progress = StreamController<RebuildProgress?>();
              addTearDown(progress.close);
              await pumpRk(
                tester,
                HomeScreen(rebuildProgress: (_) => progress.stream),
                ledger: seed.ledger,
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              progress.add(const RebuildProgress(done: 3, total: 10));
              await settleAfterAppearDelay(tester);

              expect(find.text(text), findsOneWidget, reason: '$locale');
              expect(tester.takeException(), isNull, reason: '$locale');
              expect(find.byType(CircularProgressIndicator), findsNothing);
              expectTextFits(tester, reason: '$locale');
              await unmount(tester);
            },
          );
        }
      }
    }

    testWidgets(
      'F1-07-38 a rebuild shorter than loader-appear-delay never swaps the '
      'card (11 §4.5 🔒) — the facade re-projects the book after every post',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final progress = StreamController<RebuildProgress?>();
        addTearDown(progress.close);
        await pumpRk(
          tester,
          HomeScreen(rebuildProgress: (_) => progress.stream),
          ledger: seed.ledger,
        );

        progress.add(const RebuildProgress(done: 1, total: 40));
        await tester.pump(const Duration(milliseconds: 50));
        progress.add(const RebuildProgress(done: 40, total: 40));
        await tester.pump(const Duration(milliseconds: 50));
        progress.add(null);
        await tester.pumpAndSettle();

        // Nothing was ever shown, and nothing is pending afterwards.
        expect(find.byType(HomeRebuildingCard), findsNothing);
        expect(find.byType(HomePositionCard), findsOneWidget);
        await settleAfterAppearDelay(tester);
        expect(find.byType(HomeRebuildingCard), findsNothing);
        expect(find.byType(HomePositionCard), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets('F1-07-38 homeRoot passes the real producer, and a screen '
        'pumped without a ledger has none', (tester) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        Builder(builder: homeRoot.builder),
        ledger: seed.ledger,
      );
      final wired = tester.widget<HomeScreen>(find.byType(HomeScreen));
      expect(
        wired.rebuildProgress,
        isNotNull,
        reason: 'S1.4 has a real source (Recompute.watchProgress, E-03-29)',
      );
      // It is the live seam, not a fake: it answers for the seeded book and
      // says "not rebuilding" rather than never emitting.
      await expectLater(
        wired.rebuildProgress!(seed.bookId).first,
        completion(isNull),
      );
      await unmount(tester);

      RebuildProgressSource? loose;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            loose = rebuildProgressOf(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(loose, isNull);
    });

    test('F1-07-38 the real Recompute feeds the seam: a rebuild of the seeded '
        'book arrives as counted readings and ends', () async {
      final seed = await seedSoloLedger();
      final source = recomputeRebuildProgress(seed.ledger.recompute);
      final readings = <RebuildProgress?>[];
      final sub = source(seed.bookId).listen(readings.add);

      await seed.ledger.rebuild(seed.bookId);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(readings.first, isNull, reason: 'not rebuilding when we listened');
      expect(readings.last, isNull, reason: 'and not rebuilding at the end');
      final ticks = readings
          .sublist(1, readings.length - 1)
          .cast<RebuildProgress>();
      expect(ticks, isNotEmpty);
      expect(ticks.last.done, ticks.last.total);
      expect(ticks.last.total, seed.entries.length);
      expect(ticks.last.fraction, 1.0);
    });
  });
}
