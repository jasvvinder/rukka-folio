// F1 widget test for S1 Home / Position (07 §4 🔒, 07 §1, 02 §9, 13 §3.2 row
// S1, 13 §4.3 states).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
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

/// A viewport tall enough that every card of the Home list is laid out — a
/// sliver below the fold has no element, so `find` would not see it.
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

/// A bootstrapped book with a chart but no entries at all — the 07 §4 "new
/// user" the position card collapses to the setup checklist for.
Future<LocalLedger> emptyBook() async {
  final ledger = await openTestLedger();
  await ledger.bootstrapSolo(
    firstBookName: 'Me',
    startDate: ledger.today().addDays(-7),
  );
  return ledger;
}

void main() {
  group('S1 Home / Position (07 §4, 13 §3.2 row S1)', () {
    testWidgets(
      'F1-07-49 loaded: hero, verification card, position, month, verbs, today',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);

        // Hero: Σ money accounts = cash 21,600 + bank 1,14,600.
        expect(find.text('Total money you have'), findsOneWidget);
        expect(find.text('₹1,36,200'), findsOneWidget);

        // Verification card: the books balance, said in plain words.
        expect(find.byType(HomeVerificationCard), findsOneWidget);
        expect(find.text('Books balanced · difference nil'), findsOneWidget);

        // Position card = 02 §9 exactly.
        expect(find.byType(HomePositionCard), findsOneWidget);
        expect(find.text('Cash in hand'), findsOneWidget);
        expect(find.text('You will get'), findsOneWidget);
        expect(find.text('You will give'), findsOneWidget);
        expect(find.text('Advances out'), findsOneWidget);
        expect(find.text('In transit'), findsOneWidget);
        // The bank's own row; the same name is also today's transfer
        // counter-account, so this is scoped to the card.
        expect(
          find.descendant(
            of: find.byType(HomePositionCard),
            matching: find.text('SBI Saving'),
          ),
          findsOneWidget,
        );

        // This month In/Out, and the four verb buttons.
        expect(find.text('This month'), findsOneWidget);
        expect(find.byType(HomeVerbButtons), findsOneWidget);
        for (final label in const [
          'Money in',
          'Money out',
          'Gave on credit',
          'Took on credit',
        ]) {
          expect(find.text(label), findsOneWidget);
        }

        // Today: the seed's last entry is a transfer posted today.
        expect(find.text('Today'), findsOneWidget);
        expect(find.byType(HomeTodayRow), findsOneWidget);
        expect(find.text('Nothing recorded today yet'), findsNothing);

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
      },
    );

    testWidgets('F1-07-49 every position line drills into its list (S1.1)', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      final drilled = <PositionLine>[];
      final accounts = <String>[];
      await pumpRk(
        tester,
        HomeScreen(onOpenPosition: drilled.add, onOpenAccount: accounts.add),
        ledger: seed.ledger,
      );

      Future<void> tapRow(String label) async {
        await tester.tap(
          find
              .ancestor(
                of: find.descendant(
                  of: find.byType(HomePositionCard),
                  matching: find.text(label),
                ),
                matching: find.byType(InkWell),
              )
              .first,
          warnIfMissed: false,
        );
        await tester.pump();
      }

      await tapRow('Cash in hand');
      await tapRow('You will get');
      await tapRow('You will give');
      await tapRow('Advances out');
      await tapRow('In transit');
      expect(drilled, const [
        PositionLine.cash,
        PositionLine.youWillGet,
        PositionLine.youWillGive,
        PositionLine.advancesOut,
        PositionLine.inTransit,
      ]);

      // A bank row names its own account, so it goes straight to S4.
      await tapRow('SBI Saving');
      expect(accounts, [seed.bankId]);
      await unmount(tester);
    });

    testWidgets('F1-07-49 a verb button opens the entry flow with the verb', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      final verbs = <EntryKind>[];
      await pumpRk(tester, HomeScreen(onVerb: verbs.add), ledger: seed.ledger);
      await tester.tap(find.text('Money in'));
      await tester.pump();
      await tester.tap(find.text('Gave on credit'));
      await tester.pump();
      expect(verbs, const [EntryKind.moneyIn, EntryKind.gaveCredit]);
      await unmount(tester);
    });

    testWidgets(
      'F1-07-49 empty (new user): the position card is the setup checklist',
      (tester) async {
        tallViewport(tester);
        final ledger = await emptyBook();
        final steps = <int>[];
        await pumpRk(
          tester,
          HomeScreen(onSetupStep: steps.add),
          ledger: ledger,
        );

        expect(find.byType(HomeSetupChecklist), findsOneWidget);
        expect(find.byType(HomePositionCard), findsNothing);
        expect(find.text('Get your book going'), findsOneWidget);
        expect(find.text('Add your opening balances'), findsOneWidget);
        expect(find.text('Record your first entry'), findsOneWidget);
        // Never a blank, and never a dead end (13 §8, 07 §1 rule 12).
        expect(find.text('Nothing recorded today yet'), findsOneWidget);
        expect(find.byType(HomeVerbButtons), findsOneWidget);

        await tester.tap(find.text('Add your opening balances'));
        await tester.pump();
        expect(steps, const [0]);
        await unmount(tester);
      },
    );

    testWidgets('F1-07-49 error-with-retry when the book cannot be resolved', (
      tester,
    ) async {
      tallViewport(tester);
      // Never bootstrapped: soloBookId() throws, which is the error state.
      final ledger = await openTestLedger();
      await pumpRk(tester, const HomeScreen(), ledger: ledger);

      expect(find.byType(HomeErrorState), findsOneWidget);
      expect(find.text("Couldn't load your position"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      // Still broken, so the state holds — and it is still not a dead end.
      expect(find.byType(HomeErrorState), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('F1-07-49 loading draws the ruled skeleton, never a spinner', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      await pumpFirstFrame(tester, const HomeScreen(), ledger: seed.ledger);

      expect(find.byType(HomeSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(HomeSkeleton), findsNothing);
      await unmount(tester);
    });

    testWidgets('F1-07-49 strings resolve in EN, PA and HI', (tester) async {
      tallViewport(tester);
      for (final (locale, title, today) in const [
        (Locale('en'), 'Home', 'Today'),
        (Locale('pa'), 'ਘਰ', 'ਅੱਜ'),
        (Locale('hi'), 'होम', 'आज'),
      ]) {
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          const HomeScreen(),
          ledger: seed.ledger,
          locale: locale,
        );
        expect(find.text(title), findsOneWidget, reason: '$locale');
        expect(find.text(today), findsOneWidget, reason: '$locale');
        await unmount(tester);
      }
    });

    testWidgets('F1-07-49 holds at 200% text scale on a 360x800 phone', (
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
          child: HomeScreen(),
        ),
        ledger: seed.ledger,
      );
      expect(tester.takeException(), isNull);

      // And every card is still reachable: the list scrolls, it does not clip.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}
