// Test harness: the real onboarding routes, mounted in the real app shell,
// over a fresh test ledger. Shared by the tests that must drive a branch
// through production wiring (onboarding_routes.dart) rather than call a
// routing function by hand — F1-04c-2, F1-04c-3, F1-07-16.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

/// Clears every answer the global [onboardingFlow] carries between tests in
/// one isolate, so a branch host never resumes a book an earlier test made.
/// The business list has no public reset; moving the cursor past a finished
/// business is what S0.6c's *Add another* does, and leaves S0.6a blank.
void resetOnboardingFlow() {
  onboardingFlow
    ..purpose = null
    ..family = null
    ..familyMembers = const []
    ..familyBookId = null
    ..trust = null
    ..trustMembers = const []
    ..trustBookId = null;
  if (onboardingFlow.business != null ||
      onboardingFlow.businessBookId != null) {
    onboardingFlow.addAnotherBusiness();
  }
}

/// Pumps the app at [initialLocation] with only the onboarding routes, over
/// [ledger], on a tall viewport so no step needs scrolling.
Future<GoRouter> pumpOnboardingRouter(
  WidgetTester tester,
  LocalLedger ledger, {
  required String initialLocation,
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(resetOnboardingFlow);
  final router = buildRouter(
    featureRoutes: onboardingRoutes,
    initialLocation: initialLocation,
  );
  // A fresh tree per call: a reused app element would keep the last ledger.
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
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Taps the screen's filled *Continue*. The pump first lets a field typed
/// into just before rebuild the button out of its disabled state.
Future<void> tapContinue(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
}
