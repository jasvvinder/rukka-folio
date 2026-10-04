// F1-DEMO-17, F1-DEMO-18: the production wiring that makes the debug-only
// demo card reachable (review finding DEMO1-2). F1-DEMO-9/13/14 build the
// card themselves; these go through the real `onboardingRoutes` under the
// real `RukkaFolioApp`, and pin that the composition root starts the
// sign-in watcher — so stubbing any one link fails a test here.
//
// Numbers: the fictional roster's (+91 5000 08x xxx, the dev-only demo range)
// and the reserved test block `+91 99999 xxxxx` (ADR 2026-09-05i §7).
@Tags(['F1'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/phone_shape.dart';
import 'package:rukka_folio/features/demo/demo_gate.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

/// The real app over [ledger], with only the onboarding routes, starting on
/// S0.05 welcome — the hop the signup chain takes after the language step.
Future<GoRouter> _pumpSignup(
  WidgetTester tester, {
  required LocalLedger ledger,
  required FakeAuthClient auth,
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = buildRouter(
    featureRoutes: onboardingRoutes,
    initialLocation: OnboardingPaths.welcome,
  );
  await tester.pumpWidget(
    RukkaFolioApp(
      db: ledger.db,
      sync: FakeSyncClient(),
      auth: auth,
      keys: ledger.keys as FakeKeyStore,
      now: testNow,
      locale: const Locale('en'),
      router: router,
      ledger: ledger,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Welcome → Skip → S0.2 at the onboarding sign-in path → [tenDigits] →
/// code → *This phone is ready* → Continue.
Future<void> _signIn(
  WidgetTester tester,
  GoRouter router,
  String tenDigits,
) async {
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
  expect(router.state.uri.path, OnboardingPaths.signIn);
  await tester.enterText(find.byType(TextField), tenDigits);
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '123456');
  await tester.tap(find.text('Verify'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Future<List<String>> _bookNames(WidgetTester tester, LocalLedger ledger) async {
  final rows = await tester.runAsync(
    () => ledger.db.select(ledger.db.booksP).get(),
  );
  return [for (final r in rows!) r.name];
}

/// `lib/bootstrap.dart` with `//` comments stripped, so the pin cannot pass
/// on prose that merely names the call (the bootstrap_wiring_test reader).
String _bootstrapCode() {
  for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    expect(text, isNotEmpty, reason: 'the root was really read');
    return [
      for (final line in text.split('\n'))
        line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
    ].join('\n');
  }
  fail('lib/bootstrap.dart not found from ${Directory.current.path}');
}

void main() {
  tearDown(() {
    debugDemoBuilderOverride = null;
    debugDemoPhonesOverride = null;
    demoSignedInPhone.value = null;
  });

  group('F1-DEMO-17 the signup chain through the real onboarding routes', () {
    testWidgets('F1-DEMO-17 welcome → S0.2 → S0.3 with the demo on: the '
        "roster head's card is on the purpose route, building makes his books "
        'on the device, Continue goes to S0.4 with his roster name, no '
        'purpose is recorded so the step after the PIN is Home — no second '
        'book', (tester) async {
      debugDemoBuilderOverride = true;
      debugDemoPhonesOverride = true;
      final ledger = (await tester.runAsync(() async {
        final l = await openTestLedger();
        await l.bootstrapSolo();
        return l;
      }))!;
      final auth = FakeAuthClient();
      // What bootstrap.dart starts after `auth.restore()` (F1-DEMO-18).
      final sub = watchDemoSignIn(auth);
      expect(sub, isNotNull, reason: 'the gate is open in this test');
      // Not awaited: the fake's `state` is an `async*` generator, whose
      // cancel completes only once real async work runs — never inside the
      // widget test's fake zone. The production root never cancels it.
      addTearDown(() => unawaited(sub!.cancel()));
      onboardingFlow.purpose = null;

      final router = await _pumpSignup(tester, ledger: ledger, auth: auth);
      await _signIn(tester, router, '5000081001');
      expect(router.state.uri.path, OnboardingPaths.purpose);
      expect(demoSignedInPhone.value, '+915000081001');

      final card = find.text("Demo: build Rakesh Sharma's books");
      expect(card, findsOneWidget, reason: 'the route passes the card');
      expect(find.text('Our trust'), findsOneWidget, reason: 'the five stay');
      final before = await _bookNames(tester, ledger);

      await tester.tap(card);
      for (var i = 0; i < 400; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.text('Made on this phone').evaluate().isNotEmpty) break;
      }
      expect(find.text('Made on this phone'), findsOneWidget);
      final after = await _bookNames(tester, ledger);
      expect(
        after.toSet().difference(before.toSet()),
        containsAll(['Sharma Joint Family', 'Sharma Dairy', 'Sharma Farm']),
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.namePhoto);
      expect(
        find.widgetWithText(TextField, 'Rakesh Sharma'),
        findsOneWidget,
        reason: 'S0.4 is prefilled with the roster name',
      );
      expect(onboardingFlow.yourName, 'Rakesh Sharma');
      expect(onboardingFlow.purpose, isNull);
      expect(afterSetPin(onboardingFlow), HomePaths.home);
      expect(
        await _bookNames(tester, ledger),
        after,
        reason: 'Continue made no book of its own',
      );

      // S0.4's Continue carries on to the PIN as a purpose choice would.
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.setPin);
    });

    testWidgets('F1-DEMO-17 the same chain with the demo off (a real signup): '
        'welcome → S0.2 → S0.3 lands on the five purpose cards with no demo '
        'card, and a purpose choice goes on to S0.4 as before', (tester) async {
      final ledger = (await tester.runAsync(() async {
        final l = await openTestLedger();
        await l.bootstrapSolo();
        return l;
      }))!;
      final auth = FakeAuthClient();
      expect(watchDemoSignIn(auth), isNull, reason: 'no define, no seam');
      onboardingFlow.purpose = null;

      final router = await _pumpSignup(tester, ledger: ledger, auth: auth);
      await _signIn(tester, router, '9999900001');
      expect(auth.requestedPhones, ['+919999900001']);
      expect(router.state.uri.path, OnboardingPaths.purpose);
      expect(find.textContaining('Demo:'), findsNothing);
      expect(demoSignedInPhone.value, isNull, reason: 'no number is held');

      await tester.tap(find.text('Our trust'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.namePhoto);
      expect(onboardingFlow.purpose, OnboardingPurpose.trust);
    });
  });

  test('F1-DEMO-18 the composition root starts the demo sign-in watcher on '
      'the live auth client, after the session is restored', () {
    final code = _bootstrapCode();
    expect(
      code,
      contains("import 'features/demo/demo_gate.dart' show watchDemoSignIn;"),
    );
    final restore = code.indexOf('await auth.restore();');
    final watch = code.indexOf('watchDemoSignIn(auth);');
    expect(restore, greaterThan(-1));
    expect(watch, greaterThan(restore), reason: 'watcher follows restore');
    // Only once — a second watcher would race the first.
    expect('watchDemoSignIn('.allMatches(code), hasLength(1));
  });
}
