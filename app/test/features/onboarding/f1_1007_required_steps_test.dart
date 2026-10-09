// ADR 2026-10-07 — which setup steps are required, and how a skipped one
// comes back (PLAN desk 174, slice SETUP174).
//
// F1-1007-1  ruling 1: naming the branch (S0.6a/d/g) and its opening balances
//            (S0.6b/f/i) draw no *Skip for now*; ₹0 everywhere then Save is a
//            valid answer with no extra confirm, and it ticks the S0.7
//            *Opening balances* row over that book.
// F1-1007-2  ruling 1: S0.6 draws no *Skip for now*; ₹0 + Finish hands over
//            to Home with the row ticked. Reopened from the row on an
//            onboarded install, Back returns Home and Finish returns ticked
//            (the halves of superseded F1-1006c-4 that still hold).
// F1-1007-3  ruling 2: the welcome slides and the invite steps (S0.6e /
//            S0.6h) stay skippable; a skipped invite step is recorded on the
//            device as open, an answered one leaves nothing open.
// F1-1007-6  ruling 3 (the resume half): the *Finish <book>* row resumes the
//            skipped invite step with what was saved kept, Continue ticks the
//            row, and the purpose kept on the device restores a branch a cold
//            start lost.
// F1-1007-7  ruling 2 🔒 with 07 §3.1.1 *never duplicated*: a cold start
//            after the branch's book was made resumes at the first step not
//            yet done over **that** book — never the naming step again, never
//            a second book, never a second set of opening balances.
//
// The S0.7 rows themselves (F1-1007-4/5/6) are in
// test/features/home/s0_7_setup_rows_test.dart.
@Tags(['F1'])
library;

import 'dart:convert';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/home/home_routes.dart' show homeRoot;
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_05_welcome_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart'
    show purposeCardKey;
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';
import 'onboarding_router_harness.dart' show resetOnboardingFlow, tapContinue;

const _name = 'Amrit Kaur';
const _skip = 'Skip for now';

/// The app as `bootstrap` composes it for these steps: the onboarding routes,
/// the production Home tab root, and an [AppSettings] over [prefs].
Future<(GoRouter, AppSettings)> _pump(
  WidgetTester tester,
  LocalLedger ledger, {
  required String at,
  required MemoryPrefs prefs,
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = AppSettings(prefs: prefs);
  await settings.load();
  final router = buildRouter(
    featureRoutes: onboardingRoutes,
    home: homeRoot,
    initialLocation: at,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    RukkaFolioApp(
      db: ledger.db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: ledger.keys as FakeKeyStore,
      now: testNow,
      locale: const Locale('en'),
      router: router,
      ledger: ledger,
      settings: settings,
    ),
  );
  await tester.pumpAndSettle();
  return (router, settings);
}

String _where(GoRouter r) => r.state.uri.path;

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<List<(String, String)>> _books(LocalLedger l, BookType type) async => [
  for (final b in await l.db.select(l.db.booksP).get())
    if (b.type == type.name) (b.id, b.name),
];

Map<String, Object?>? _branchOf(MemoryPrefs prefs) {
  final raw = prefs.values[RkPrefKeys.setupBranch];
  return raw == null ? null : jsonDecode(raw) as Map<String, Object?>;
}

/// S0.3 → S0.4 → (PIN is not part of these routes) → S0.5b's skip, which
/// stays until RUNG3B (ADR 2026-10-07 ruling 1) → the branch's first step.
Future<GoRouter> _toBranch(
  WidgetTester tester,
  LocalLedger ledger,
  OnboardingPurpose purpose,
  MemoryPrefs prefs,
) async {
  final (router, _) = await _pump(
    tester,
    ledger,
    at: OnboardingPaths.purpose,
    prefs: prefs,
  );
  await tester.tap(find.byKey(purposeCardKey(purpose)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, _name);
  await tapContinue(tester);
  router.go(OnboardingPaths.recoverySheet);
  await tester.pumpAndSettle();
  await tester.tap(find.text(_skip));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() {
    onboardingFlow.reset();
    resetOnboardingFlow();
  });
  tearDown(onboardingFlow.reset);

  group('F1-1007-1 naming and opening balances are required (ruling 1)', () {
    const cases = {
      OnboardingPurpose.businesses: (
        'Kaur Traders',
        OnboardingPaths.business,
        OnboardingPaths.businessOpening,
        'Save and continue',
        BookType.business,
      ),
      OnboardingPurpose.family: (
        'Kaur Parivar',
        OnboardingPaths.family,
        OnboardingPaths.familyAccounts,
        'Save',
        BookType.family,
      ),
      OnboardingPurpose.trust: (
        'Guru Nanak Sabha',
        OnboardingPaths.trust,
        OnboardingPaths.trustAccounts,
        'Save',
        BookType.organization,
      ),
    };
    for (final MapEntry(key: purpose, value: c) in cases.entries) {
      final (bookName, namePath, openingPath, save, type) = c;
      testWidgets('F1-1007-1 ${purpose.name}: the naming step and the '
          'opening balances draw no Skip; ₹0 + $save goes on with no confirm '
          'and ticks that book\'s row', (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo();
        final prefs = MemoryPrefs();
        final router = await _toBranch(tester, ledger, purpose, prefs);

        expect(_where(router), namePath);
        expect(find.text(_skip), findsNothing, reason: 'naming step');
        await tester.enterText(find.byType(TextField).first, bookName);
        await tapContinue(tester);
        if (purpose != OnboardingPurpose.businesses) {
          // The invite step (ruling 2) — answered here; F1-1007-3 skips it.
          await tapContinue(tester);
        }
        expect(_where(router), openingPath);
        expect(find.text(_skip), findsNothing, reason: 'opening balances');

        await tester.tap(find.text(save));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(_where(router), isNot(openingPath));

        final book = (await _books(ledger, type)).single;
        expect(book.$2, bookName);
        expect(prefs.values[RkPrefKeys.openingBalancesOf(book.$1)], '1');
        // ₹0 everywhere posts nothing (02 §4).
        final accounts = (await tester.runAsync(
          () => ledger.watchAccounts(book.$1).first,
        ))!;
        expect(accounts.every((a) => a.balancePaise == 0), isTrue);
        await _unmount(tester);
      });
    }
  });

  group('F1-1007-2 S0.6 is required (ruling 1)', () {
    testWidgets('F1-1007-2 no Skip; ₹0 + Finish hands over with the row '
        'ticked; reopened from the row, Back returns Home and Finish keeps '
        'it ticked', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      onboardingFlow.setYourName(_name);
      final prefs = MemoryPrefs();
      final (router, settings) = await _pump(
        tester,
        ledger,
        at: OnboardingPaths.openingBalances,
        prefs: prefs,
      );
      final bookId = (await _books(ledger, BookType.personal)).single.$1;
      expect(find.text('What do you have?'), findsOneWidget);
      expect(find.text(_skip), findsNothing);

      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_where(router), HomePaths.home);
      expect(settings.onboarded, isTrue);
      expect(prefs.values[RkPrefKeys.openingBalancesOf(bookId)], '1');
      expect(
        tester.widget<Text>(find.text('Opening balances')).style?.decoration,
        TextDecoration.lineThrough,
      );

      // The production door (home_routes.dart): S0.6 alone.
      await tester.tap(find.text('Opening balances'));
      await tester.pumpAndSettle();
      expect(_where(router), OnboardingPaths.openingBalances);
      expect(find.text(_skip), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_where(router), HomePaths.home);

      await tester.tap(find.text('Opening balances'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(_where(router), HomePaths.home);
      expect(
        tester.widget<Text>(find.text('Opening balances')).style?.decoration,
        TextDecoration.lineThrough,
      );
      expect(await _books(ledger, BookType.personal), hasLength(1));
      await _unmount(tester);
    });
  });

  group('F1-1007-3 the slides and the invites stay skippable (ruling 2)', () {
    testWidgets('F1-1007-3 the welcome slides still offer Skip', (
      tester,
    ) async {
      var done = 0;
      await pumpRk(tester, WelcomeScreen(onDone: () => done++));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(done, 1);
    });

    for (final (purpose, name, members, accounts) in [
      (
        OnboardingPurpose.family,
        'Kaur Parivar',
        OnboardingPaths.familyMembers,
        OnboardingPaths.familyAccounts,
      ),
      (
        OnboardingPurpose.trust,
        'Guru Nanak Sabha',
        OnboardingPaths.trustMembers,
        OnboardingPaths.trustAccounts,
      ),
    ]) {
      testWidgets('F1-1007-3 ${purpose.name}: the invite step shows Skip; '
          'skipping it goes on and records the step open, with the book once '
          'made', (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo();
        final prefs = MemoryPrefs();
        final router = await _toBranch(tester, ledger, purpose, prefs);
        await tester.enterText(find.byType(TextField).first, name);
        await tapContinue(tester);
        expect(_where(router), members);
        expect(find.text(_skip), findsOneWidget);

        await tester.tap(find.text(_skip));
        await tester.pumpAndSettle();
        expect(_where(router), accounts);
        expect(_branchOf(prefs), {'purpose': purpose.name, 'state': 'open'});

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final type = purpose == OnboardingPurpose.family
            ? BookType.family
            : BookType.organization;
        final bookId = (await _books(ledger, type)).single.$1;
        expect(_branchOf(prefs), {
          'purpose': purpose.name,
          'state': 'open',
          'book': bookId,
        });
        await _unmount(tester);
      });
    }

    testWidgets('F1-1007-3 an answered invite step leaves nothing open', (
      tester,
    ) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      final prefs = MemoryPrefs()
        ..values[RkPrefKeys.setupBranch] = jsonEncode({
          'purpose': 'family',
          'state': 'open',
        });
      final router = await _toBranch(
        tester,
        ledger,
        OnboardingPurpose.family,
        prefs,
      );
      await tester.enterText(find.byType(TextField).first, 'Kaur Parivar');
      await tapContinue(tester);
      await tapContinue(tester); // S0.6e answered
      expect(_where(router), OnboardingPaths.familyAccounts);
      expect(prefs.values[RkPrefKeys.setupBranch], isNull);
      await _unmount(tester);
    });
  });

  group('F1-1007-6 the Finish row resumes the skipped step (ruling 3)', () {
    for (final (purpose, name, step, hint) in [
      (
        OnboardingPurpose.family,
        'Kaur Parivar',
        OnboardingPaths.familyMembers,
        'Next: invite the other heads',
      ),
      (
        OnboardingPurpose.trust,
        'Guru Nanak Sabha',
        OnboardingPaths.trustMembers,
        'Next: invite who runs it',
      ),
    ]) {
      testWidgets('F1-1007-6 ${purpose.name} — invites skipped: Home shows '
          '"Finish $name"; tapping it resumes there, Back returns Home, '
          'Continue ticks the row', (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo();
        final prefs = MemoryPrefs();
        final router = await _toBranch(tester, ledger, purpose, prefs);
        await tester.enterText(find.byType(TextField).first, name);
        await tapContinue(tester);
        await tester.tap(find.text(_skip)); // invites skipped
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save')); // the book's openings, ₹0
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finish')); // S0.6, ₹0
        await tester.pumpAndSettle();
        expect(_where(router), HomePaths.home);

        final row = find.text('Finish $name');
        expect(row, findsOneWidget);
        expect(find.text(hint), findsOneWidget);
        expect(find.text('Add your family'), findsNothing);

        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(_where(router), step);
        // Onboarded: Back goes Home, never back into the chain's naming step.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(_where(router), HomePaths.home);
        expect(find.text('Finish $name'), findsOneWidget);

        // Resumed and skipped again: the row stays open.
        await tester.tap(find.text('Finish $name'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_skip));
        await tester.pumpAndSettle();
        expect(_where(router), HomePaths.home);
        expect(_branchOf(prefs)?['state'], 'open');

        await tester.tap(find.text('Finish $name'));
        await tester.pumpAndSettle();
        await tapContinue(tester);
        expect(_where(router), HomePaths.home);
        expect(_branchOf(prefs)?['state'], 'done');
        expect(
          tester.widget<Text>(find.text('Finish $name')).style?.decoration,
          TextDecoration.lineThrough,
        );
        // Still one branch book: resuming made nothing new.
        final type = purpose == OnboardingPurpose.family
            ? BookType.family
            : BookType.organization;
        expect(await _books(ledger, type), hasLength(1));
        await _unmount(tester);
      });
    }

    testWidgets('F1-1007-6 a cold start that lost the purpose still takes '
        'the branch: S0.5b restores it from the device', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      final prefs = MemoryPrefs();
      await _pump(tester, ledger, at: OnboardingPaths.purpose, prefs: prefs);
      await tester.tap(find.byKey(purposeCardKey(OnboardingPurpose.trust)));
      await tester.pumpAndSettle();
      expect(prefs.values[RkPrefKeys.setupPurpose], 'trust');
      await _unmount(tester);

      // The process died: the in-memory answers are gone.
      onboardingFlow.reset();
      final (again, _) = await _pump(
        tester,
        ledger,
        at: OnboardingPaths.recoverySheet,
        prefs: prefs,
      );
      await tester.tap(find.text(_skip));
      await tester.pumpAndSettle();
      expect(_where(again), OnboardingPaths.trust);
      await _unmount(tester);
    });
  });

  group('F1-1007-7 a cold start after the branch book was made never makes '
      'a second one (ruling 2, 07 §3.1.1)', () {
    const cases = {
      OnboardingPurpose.businesses: (
        'Kaur Traders',
        OnboardingPaths.businessOpening,
        'Save and continue',
        OnboardingPaths.businessAnother,
        BookType.business,
      ),
      OnboardingPurpose.family: (
        'Kaur Parivar',
        OnboardingPaths.familyAccounts,
        'Save',
        OnboardingPaths.openingBalances,
        BookType.family,
      ),
      OnboardingPurpose.trust: (
        'Guru Nanak Sabha',
        OnboardingPaths.trustAccounts,
        'Save',
        OnboardingPaths.openingBalances,
        BookType.organization,
      ),
    };
    for (final MapEntry(key: purpose, value: c) in cases.entries) {
      final (bookName, openingPath, save, after, type) = c;
      for (final saved in [false, true]) {
        testWidgets('F1-1007-7 ${purpose.name}, openings '
            '${saved ? 'saved' : 'not saved'}: the resume lands on '
            '${saved ? after : openingPath} over the same book', (
          tester,
        ) async {
          final ledger = await openTestLedger();
          await ledger.bootstrapSolo();
          final prefs = MemoryPrefs();
          final router = await _toBranch(tester, ledger, purpose, prefs);
          await tester.enterText(find.byType(TextField).first, bookName);
          await tapContinue(tester);
          if (purpose != OnboardingPurpose.businesses) {
            await tester.tap(find.text(_skip)); // invites skipped
            await tester.pumpAndSettle();
          }
          expect(_where(router), openingPath);
          final made = (await _books(ledger, type)).single;
          if (saved) {
            await tester.tap(find.text(save));
            await tester.pumpAndSettle();
            expect(_where(router), after);
          }
          await _unmount(tester);

          // The process died: every in-memory answer is gone.
          onboardingFlow.reset();
          final (again, _) = await _pump(
            tester,
            ledger,
            at: OnboardingPaths.recoverySheet,
            prefs: prefs,
          );
          await tester.tap(find.text(_skip));
          await tester.pumpAndSettle();
          expect(_where(again), saved ? after : openingPath);
          expect(await _books(ledger, type), [made]);
          if (purpose == OnboardingPurpose.businesses && saved) {
            // S0.6c's recap still names the business made before the restart.
            expect(find.textContaining(bookName), findsWidgets);
          }
          if (!saved) {
            await tester.tap(find.text(save));
            await tester.pumpAndSettle();
            expect(_where(again), after);
            expect(prefs.values[RkPrefKeys.openingBalancesOf(made.$1)], '1');
          }
          expect(await _books(ledger, type), [made]);
          await _unmount(tester);
        });
      }
    }
  });
}
