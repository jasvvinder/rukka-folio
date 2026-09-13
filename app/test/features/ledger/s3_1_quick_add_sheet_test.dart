// F1 widget test for the S3.1 quick-add sheet (07 §6 bullet 3, 13 §3.2 row
// S3.1). The sheet presentation of the type picker: the entry flow shows the
// same choice as a full screen (07 §5 step 3) — deliberately two
// presentations of one component, so the test pins the sheet-ness too.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s3_1_quick_add_sheet.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

/// Tears the tree down inside the test so drift's zero-duration stream
/// cleanup timer fires before the binding's pending-timer invariant runs.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Reads the book's accounts from outside the fake-async zone. A drift query
/// stream's first event arrives on a zero-duration timer, and a bare `await`
/// in a widget test never lets the fake clock fire it — the test would hang.
/// `runAsync` is the supported escape hatch.
Future<List<AccountBalance>> accountsOf(
  WidgetTester tester,
  SeededLedger seed,
) async => (await tester.runAsync(
  () => seed.ledger.watchAccounts(seed.bookId).first,
))!;

/// Pumps the sheet the way S3 opens it — through `showModalBottomSheet`, so
/// the test sees the real presentation and not a bare widget.
Future<void> openSheet(
  WidgetTester tester,
  SeededLedger seed, {
  Locale? locale,
}) async {
  await pumpRk(
    tester,
    Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => QuickAddSheet(bookId: seed.bookId),
          ),
          child: const Text('open'),
        ),
      ),
    ),
    ledger: seed.ledger,
    locale: locale,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // Step 2 autofocuses its name field, and a focused `EditableText` blinks
  // its caret on a repeating timer — an animation that never settles, so
  // every `pumpAndSettle` past step 1 would grind out ten simulated minutes
  // of frames before giving up. A deterministic (non-blinking) cursor is the
  // supported way to make the tree quiescent.
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  group('S3.1 Quick add sheet (07 §6)', () {
    testWidgets('F1-07-43 opens as a bottom sheet, not a full screen (07 §6)', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      await openSheet(tester, seed);

      // The sheet presentation: a BottomSheet, and no Scaffold of its own
      // (the entry flow's picker is the full-screen twin).
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
      expect(find.text('Add an account'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('F1-07-43 step 1 is the grid of illustrated type tiles', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seed = await seedSoloLedger();
      await openSheet(tester, seed);

      expect(find.byType(GridView), findsOneWidget);
      // Every tile carries an icon as well as its label — colour and shape
      // are never the only cue (07 §1 rule 3).
      for (final tile in QuickAddTile.values) {
        expect(
          find.descendant(
            of: find.byType(GridView),
            matching: find.byIcon(tile.icon),
          ),
          findsOneWidget,
          reason: 'tile ${tile.name} is missing its icon',
        );
      }
      // ⚠️ SPEC: 07 §6 lists eight tiles; the eighth (Capital) is withheld
      // because 02 §7.1 creates the Capital/Drawings pair structurally at
      // business setup and no `AccountClass` models an ad-hoc one. Logged as
      // an open item in the lane report — the day it lands, this count goes
      // to eight rather than tracking the enum. The *engine* half unblocked on
      // 13 Sep (ADR 2026-09-13 §4 🔒, `A-09b-5`): capital introduced posts as
      // Money in. What this tile does with that is still the open UX ruling.
      expect(QuickAddTile.values.length, 7);
      for (final label in const [
        'Bank',
        'Cash',
        'Credit card',
        "Someone I owe",
        'Someone who owes me',
        'Expense category',
        'Income category',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'tile $label');
      }
      await unmount(tester);
    });

    testWidgets(
      'F1-07-43 step 2 is name + opening balance and refuses an empty name',
      (tester) async {
        final seed = await seedSoloLedger();
        await openSheet(tester, seed);

        await tester.tap(find.text('Bank'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
        expect(
          find.widgetWithText(TextField, 'Opening balance'),
          findsOneWidget,
        );

        // Saving with no name is refused, in words, and nothing is posted —
        // a blocked action always says why (07 §1 rule 6).
        final before = (await accountsOf(tester, seed)).length;
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(find.text('Enter a name'), findsOneWidget);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect((await accountsOf(tester, seed)).length, before);

        // Named, it saves: the sheet closes and the account exists, money
        // class, with its opening balance in integer paise (CLAUDE.md 1).
        await tester.enterText(find.widgetWithText(TextField, 'Name'), 'HDFC');
        await tester.enterText(
          find.widgetWithText(TextField, 'Opening balance'),
          '1500.50',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);

        final rows = await accountsOf(tester, seed);
        final added = rows.singleWhere((a) => a.account.name == 'HDFC');
        expect(added.account.accountClass, AccountClass.money);
        expect(added.balancePaise, 150050);
        await unmount(tester);
      },
    );

    testWidgets('F1-07-43 rupees parse to integer paise, never a double', (
      tester,
    ) async {
      expect(parseRupeesToPaise(''), 0);
      expect(parseRupeesToPaise('1500'), 150000);
      expect(parseRupeesToPaise('1500.5'), 150050);
      expect(parseRupeesToPaise('1500.05'), 150005);
      expect(parseRupeesToPaise('-2000'), -200000);
      expect(parseRupeesToPaise('12.345'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
    });

    testWidgets(
      'F1-07-43 strings resolve in EN/PA/HI with no overflow at 200%',
      (tester) async {
        // A real 360x800 phone, at the 200% scale of 07 §1 rule 9 — the scale
        // has to go through the platform dispatcher, because the sheet lives in
        // the Navigator overlay, above any MediaQuery a test wraps `home` in.
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          final seed = await seedSoloLedger();
          await openSheet(tester, seed, locale: locale);
          // Step 1 renders, scrolls rather than overflows...
          expect(find.byType(GridView), findsOneWidget);
          expect(tester.takeException(), isNull);
          // ...and so does step 2, whose actions are the tall ones.
          final bank = find.byIcon(QuickAddTile.bank.icon);
          await tester.ensureVisible(bank);
          await tester.pumpAndSettle();
          await tester.tap(bank);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      },
    );
  });
}
