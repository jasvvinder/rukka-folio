// C-04b-2 at route level (review finding ID107C-1): ADR 2026-10-04b §3's
// *already signed up* state offers the 06 §5 / 13 §5 F11 fork on **every**
// route that mounts S0.2 — the F1 signup chain (`/onboarding/sign-in`,
// 13 §5 F1) as well as auth's own door. These mount the real route lists
// under the real `RukkaFolioApp`, so a route that drops the fork fails here
// rather than in a screen test that passes the callback by hand.
//
// Numbers: the reserved test block `+91 99999 xxxxx` (ADR 2026-09-05i §7).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/auth/auth_routes.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

const _forkMarker = 'S11.6 fork (stub)';

/// [routes] under the real app, starting on [start], with a stub at
/// [RkPaths.recoveryFork] so the test reads where *Get my books back* went
/// without depending on the recovery feature's scopes.
Future<GoRouter> _pump(
  WidgetTester tester, {
  required List<RouteBase> routes,
  required String start,
  required LocalLedger ledger,
  required FakeAuthClient auth,
}) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = buildRouter(
    featureRoutes: [
      ...routes,
      GoRoute(
        path: RkPaths.recoveryFork,
        builder: (context, state) => const Scaffold(body: Text(_forkMarker)),
      ),
    ],
    initialLocation: start,
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

/// Number → code, with the verify answering another account's id.
Future<void> _reachExisting(WidgetTester tester, FakeAuthClient auth) async {
  await tester.enterText(find.byType(TextField), '9999912345');
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
  auth.failNext = const AuthFailure(AuthFailureKind.existingAccount);
  await tester.enterText(find.byType(TextField), '482913');
  await tester.tap(find.text('Verify'));
  await tester.pumpAndSettle();
  expect(find.text('This number is already signed up'), findsOneWidget);
}

void main() {
  final cases = <String, (List<RouteBase>, String)>{
    'the F1 signup route (${OnboardingPaths.signIn})': (
      onboardingRoutes,
      OnboardingPaths.signIn,
    ),
    "auth's own door (${AuthPaths.phoneOtp})": (authRoutes, AuthPaths.phoneOtp),
  };

  for (final MapEntry(key: name, value: (routes, start)) in cases.entries) {
    testWidgets(
      'C-04b-2 on $name a number that already has an account offers Get my books back, which opens S11.6 (13 §5 F11), and Use a different number, which goes back to the phone step — never activating this phone',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = FakeAuthClient();
        final router = await _pump(
          tester,
          routes: routes,
          start: start,
          ledger: ledger,
          auth: auth,
        );
        await _reachExisting(tester, auth);
        expect(auth.current, isNot(isA<Active>()));

        await tester.tap(find.text('Use a different number'));
        await tester.pumpAndSettle();
        expect(find.text('Your phone number'), findsOneWidget);
        expect(router.state.uri.path, start);

        await _reachExisting(tester, auth);
        await tester.tap(find.text('Get my books back'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, RkPaths.recoveryFork);
        expect(find.text(_forkMarker), findsOneWidget);
        expect(auth.current, isNot(isA<Active>()));
      },
    );
  }
}
