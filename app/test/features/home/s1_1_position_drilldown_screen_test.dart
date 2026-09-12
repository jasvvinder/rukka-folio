// F1 widget test for S1.1 Position line drill-down (07 §4 🔒 "every line
// drills into its list", 07 §1, 02 §9 position semantics, 13 §3.2 row S1.1,
// 13 §4.1 P1 rows, 13 §4.3 states).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/home/screens/s1_1_position_drilldown_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_states.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

/// A viewport tall enough that every row of the list is laid out.
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
/// before the binding's pending-timer invariant runs. Never `await` a stream
/// cancellation on the disposal path — that deadlocks the whole file.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Like `pumpRk`, but stops at the *first* frame — the only way to see the
/// loading state, which `pumpAndSettle` has already passed.
Future<void> pumpFirstFrame(
  WidgetTester tester,
  Widget child, {
  required LocalLedger ledger,
}) async {
  await tester.pumpWidget(
    RkScope(
      db: ledger.db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: ledger.keys,
      now: ledger.now,
      child: LedgerScope(
        ledger: ledger,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: rkLocalizationsDelegates,
          theme: rkTheme(Brightness.light),
          home: child,
        ),
      ),
    ),
  );
}

/// A [MoneyText] figure: rendered as `Text.rich`, so rich-text matching, and
/// consumer surfaces sign a positive amount (07 §1 rule 3).
Finder money(String s) => find.text(s, findRichText: true);

/// The app-bar title, scoped so a title that repeats as a row label (the cash
/// line does) is still asserted exactly once.
Finder titleText(String s) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(s));

void main() {
  group('S1.1 position drill-down (07 §4, 13 §3.2 row S1.1)', () {
    testWidgets('F1-07-50 cash: its own title, its accounts, and the total', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const PositionDrilldownScreen(line: PositionLine.cash),
        ledger: seed.ledger,
      );

      expect(titleText('Cash in hand'), findsOneWidget);
      // Two rows — the seed's own cash account and the `Cash A/c` every book
      // is seeded with (ADR 2026-09-09c §1) — plus the line total. The total
      // and the funded account both read ₹21,600, and integer paise never
      // became a float on the way.
      expect(find.byType(RkLabelAmountRow), findsNWidgets(3));
      expect(find.text('Cash A/c'), findsOneWidget);
      expect(money('+₹21,600'), findsNWidgets(2));
      expect(find.text('Total'), findsOneWidget);
      // Not the other lines' accounts.
      expect(find.text('SBI Saving'), findsNothing);
      expect(find.text('Ramesh'), findsNothing);

      // Consumer vocabulary only (02 §10 🔒, CLAUDE.md rule 9).
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        final s = w.data ?? '';
        expect(
          s.contains('Dr'),
          isFalse,
          reason: 'Dr/Cr on a consumer surface: $s',
        );
        expect(
          s.contains('Cr'),
          isFalse,
          reason: 'Dr/Cr on a consumer surface: $s',
        );
      }
      await unmount(tester);
    });

    testWidgets('F1-07-50 bank lists the money accounts that are not cash', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const PositionDrilldownScreen(line: PositionLine.bank),
        ledger: seed.ledger,
      );

      expect(find.text('SBI Saving'), findsOneWidget);
      expect(money('+₹1,14,600'), findsNWidgets(2));
      expect(find.text('Cash in hand'), findsNothing);
      await unmount(tester);
    });

    testWidgets('F1-07-50 a Home bank row narrows the list to its account', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        PositionDrilldownScreen(
          line: PositionLine.bank,
          accountId: seed.bankId,
        ),
        ledger: seed.ledger,
      );

      expect(find.text('SBI Saving'), findsOneWidget);
      expect(find.byType(RkLabelAmountRow), findsNWidgets(2)); // row + total
      await unmount(tester);
    });

    testWidgets('F1-07-50 you-will-get lists the party who owes (02 §9)', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const PositionDrilldownScreen(line: PositionLine.youWillGet),
        ledger: seed.ledger,
      );

      expect(titleText('You will get'), findsOneWidget);
      expect(find.text('Ramesh'), findsOneWidget);
      expect(money('+₹5,000'), findsNWidgets(2));
      await unmount(tester);
    });

    testWidgets(
      'F1-07-50 you-will-give, advances out and in transit each render '
      'their own titled empty list',
      (tester) async {
        tallViewport(tester);
        for (final (line, title) in const [
          (PositionLine.youWillGive, 'You will give'),
          (PositionLine.advancesOut, 'Advances out'),
          (PositionLine.inTransit, 'In transit'),
        ]) {
          final seed = await seedSoloLedger();
          await pumpRk(
            tester,
            PositionDrilldownScreen(line: line),
            ledger: seed.ledger,
          );
          expect(titleText(title), findsOneWidget, reason: '$line');
          expect(
            find.text('Nothing behind this line yet'),
            findsOneWidget,
            reason: '$line',
          );
          expect(find.byType(RkLabelAmountRow), findsNothing, reason: '$line');
          await unmount(tester);
        }
      },
    );

    testWidgets('F1-07-50 empty is never a dead end: it offers an entry', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      var recorded = 0;
      await pumpRk(
        tester,
        PositionDrilldownScreen(
          line: PositionLine.advancesOut,
          onRecordEntry: () => recorded++,
        ),
        ledger: seed.ledger,
      );

      expect(find.text('Nothing behind this line yet'), findsOneWidget);
      await tester.tap(find.text('Record an entry'));
      await tester.pump();
      expect(recorded, 1);
      await unmount(tester);
    });

    testWidgets('F1-07-50 a row taps through to its A/C statement (S4)', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      final opened = <String>[];
      await pumpRk(
        tester,
        PositionDrilldownScreen(
          line: PositionLine.cash,
          onOpenAccount: opened.add,
        ),
        ledger: seed.ledger,
      );

      // The total row carries no drill-down; only the account rows do — the
      // funded one and the seeded `Cash A/c` (ADR 2026-09-09c §1).
      expect(find.byType(InkWell), findsNWidgets(2));
      await tester.tap(
        find.ancestor(
          of: find.text('Cash in hand'),
          matching: find.byType(InkWell),
        ),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(opened, [seed.cashId]);
      await unmount(tester);
    });

    testWidgets('F1-07-50 error-with-retry when the book cannot be resolved', (
      tester,
    ) async {
      tallViewport(tester);
      // Never bootstrapped: soloBookId() throws, which is the error state.
      final ledger = await openTestLedger();
      await pumpRk(
        tester,
        const PositionDrilldownScreen(line: PositionLine.cash),
        ledger: ledger,
      );

      expect(find.byType(HomeErrorState), findsOneWidget);
      expect(find.text("Couldn't load this list"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      // Still broken, so the state holds — and it is still not a dead end.
      expect(find.byType(HomeErrorState), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('F1-07-50 loading draws the ruled skeleton, never a spinner', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      await pumpFirstFrame(
        tester,
        const PositionDrilldownScreen(line: PositionLine.cash),
        ledger: seed.ledger,
      );

      expect(find.byType(HomeSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(HomeSkeleton), findsNothing);
      await unmount(tester);
    });

    testWidgets('F1-07-50 strings resolve in EN, PA and HI', (tester) async {
      tallViewport(tester);
      for (final (locale, title, total) in const [
        (Locale('en'), 'You will get', 'Total'),
        (Locale('pa'), 'ਤੁਸੀਂ ਲੈਣੇ ਹਨ', 'ਕੁੱਲ'),
        (Locale('hi'), 'आपको मिलने हैं', 'कुल'),
      ]) {
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          const PositionDrilldownScreen(line: PositionLine.youWillGet),
          ledger: seed.ledger,
          locale: locale,
        );
        expect(titleText(title), findsOneWidget, reason: '$locale');
        expect(find.text(total), findsOneWidget, reason: '$locale');
        // Latin digits in every locale (11 §4.4).
        expect(money('+₹5,000'), findsNWidgets(2), reason: '$locale');
        await unmount(tester);
      }
    });

    testWidgets('F1-07-50 empty state resolves in PA and HI too', (
      tester,
    ) async {
      tallViewport(tester);
      for (final (locale, empty, action) in const [
        (Locale('pa'), 'ਇਸ ਲਾਈਨ ਪਿੱਛੇ ਹਾਲੇ ਕੁਝ ਨਹੀਂ', 'ਇੰਦਰਾਜ ਦਰਜ ਕਰੋ'),
        (Locale('hi'), 'इस पंक्ति के पीछे अभी कुछ नहीं', 'प्रविष्टि दर्ज करें'),
      ]) {
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          PositionDrilldownScreen(
            line: PositionLine.inTransit,
            onRecordEntry: () {},
          ),
          ledger: seed.ledger,
          locale: locale,
        );
        expect(find.text(empty), findsOneWidget, reason: '$locale');
        expect(find.text(action), findsOneWidget, reason: '$locale');
        await unmount(tester);
      }
    });

    testWidgets('F1-07-50 holds at 200% text scale on a 360x800 phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: PositionDrilldownScreen(line: PositionLine.cash),
        ),
        ledger: seed.ledger,
      );
      expect(tester.takeException(), isNull);
      expect(money('+₹21,600'), findsNWidgets(2));

      // Still reachable: the list scrolls, it does not clip.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}
