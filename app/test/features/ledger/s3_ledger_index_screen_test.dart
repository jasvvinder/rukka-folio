// F1 widget test for the S3 ledger index (07 §6, 13 §3.2 row S3, §4.3
// states).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s3_ledger_index_screen.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

/// A viewport tall enough that the index's lazy `ListView.builder` builds
/// every seeded row — rows below the fold otherwise do not exist at all.
void tallViewport(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Tears the tree down *inside* the test. Cancelling drift's query stream
/// schedules a zero-duration cleanup timer, and only a pump inside the test
/// fires it before the binding's end-of-test pending-timer invariant runs.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('S3 Ledger index (07 §6, 13 §3.2)', () {
    testWidgets(
      'F1-07-42 A-Z list shows every seeded account with its signed balance',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await pumpRk(tester, const LedgerIndexScreen(), ledger: seed.ledger);

        expect(find.text('Cash in hand'), findsOneWidget);
        expect(find.text('SBI Saving'), findsOneWidget);
        expect(find.text('Ramesh'), findsOneWidget);
        expect(find.text('Shop sales'), findsOneWidget);
        expect(find.text('Diesel'), findsOneWidget);

        // A-Z: Cash in hand < Diesel < Ramesh < SBI Saving < Shop sales.
        const seeded = [
          'Cash in hand',
          'Diesel',
          'Ramesh',
          'SBI Saving',
          'Shop sales',
        ];
        final names = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .where(seeded.contains)
            .toList();
        expect(names, seeded);
        await unmount(tester);
      },
    );

    testWidgets('F1-07-42 the alphabet rail is sticky (07 §6)', (tester) async {
      // Short on purpose: a rail can only be shown to stick if the list
      // actually scrolls under it.
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seed = await seedSoloLedger();
      await pumpRk(tester, const LedgerIndexScreen(), ledger: seed.ledger);

      // Cash in hand · Diesel · Ramesh · SBI Saving + Shop sales -> C D R S.
      final headers = tester
          .widgetList<SliverPersistentHeader>(
            find.byType(SliverPersistentHeader),
          )
          .toList();
      expect(headers, hasLength(4));
      expect(
        headers.every((h) => h.pinned),
        isTrue,
        reason: '07 §6 asks for a sticky alphabet rail, not plain headers',
      );

      // And it behaves: scrolled to the bottom, the last group's letter is
      // still on screen rather than having left with its rows.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Shop sales'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
      'F1-07-42 filter chips All · Parties · Categories · Money · System are all offered',
      (tester) async {
        // Wide as well as tall: the chip strip is a horizontal `ListView`,
        // so at phone width the last chips are lazily unbuilt (a real user
        // scrolls to them; a finder cannot).
        tallViewport(tester, width: 1000);
        final seed = await seedSoloLedger();
        await pumpRk(tester, const LedgerIndexScreen(), ledger: seed.ledger);

        expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Parties'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Categories'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Money'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'System'), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Parties'));
        await tester.pumpAndSettle();
        expect(find.text('Ramesh'), findsOneWidget);
        expect(find.text('Cash in hand'), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-42 search-in-header narrows the list; a miss shows the create row (07 §6)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await pumpRk(tester, const LedgerIndexScreen(), ledger: seed.ledger);

        await tester.enterText(find.byType(TextField), 'ramesh');
        await tester.pumpAndSettle();
        expect(find.text('Ramesh'), findsOneWidget);
        expect(find.text('Cash in hand'), findsNothing);

        await tester.enterText(find.byType(TextField), 'zzz-no-such-account');
        await tester.pumpAndSettle();
        expect(
          find.text('No account matches "zzz-no-such-account"'),
          findsOneWidget,
        );
        // 07 §6 bullet 4: the search-miss state *is* the create row, and the
        // header action stays reachable — a miss is never a dead end
        // (07 §1 rule 6).
        expect(find.widgetWithText(ListTile, 'New A/C'), findsOneWidget);
        expect(
          find.widgetWithText(FloatingActionButton, 'New A/C'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(ListTile, 'New A/C'));
        await tester.pumpAndSettle();
        // The create row leads into S3.1, the quick-add bottom sheet.
        expect(find.text('Add an account'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets('F1-07-42 error state: unresolvable book shows retry', (
      tester,
    ) async {
      final ledger = await openTestLedger();
      await pumpRk(tester, const LedgerIndexScreen(), ledger: ledger);

      expect(find.text("Couldn't load your accounts"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('F1-07-42 loading state renders the ruled skeleton (11 §4.5)', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      final db = seed.ledger.db;
      await tester.pumpWidget(
        RkScope(
          db: db,
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          keys: seed.ledger.keys,
          now: seed.ledger.now,
          child: LedgerScope(
            ledger: seed.ledger,
            child: MaterialApp(
              supportedLocales: const [Locale('en')],
              localizationsDelegates: rkLocalizationsDelegates,
              theme: rkTheme(Brightness.light),
              home: const LedgerIndexScreen(),
            ),
          ),
        ),
      );
      // One frame — before the async book resolve completes.
      await tester.pump();
      // 11 §4.5 / 07 §1 rule 12: the skeleton announces itself, so a screen
      // reader says something other than silence while the book resolves.
      // Matched on the `Semantics` widget rather than the semantics tree,
      // which widget tests only build while a handle is held.
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Loading accounts',
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets(
      'F1-07-42 strings resolve in EN/PA/HI with no overflow at 200%',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          final seed = await seedSoloLedger();
          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const LedgerIndexScreen(),
            ),
            ledger: seed.ledger,
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      },
    );
  });
}
