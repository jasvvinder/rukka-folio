// Shared harness for the lock family's F1 tests: a real [PinVault] over a
// [FakeKeyStore] and libsodium (the same vault the app uses — never a second
// store), a scripted [BiometricGate], and a settable clock so the cooldown
// ladder can be driven without waiting an hour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/lock_scope.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../../shared/test_app.dart';

/// The three shipped locales.
const lockLocales = [Locale('en'), Locale('pa'), Locale('hi')];

/// Sizes the surface; 360x800 is the small phone 07 §1 rule 9 must survive.
void sizeView(WidgetTester tester, {double width = 400, double height = 900}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A real vault over an in-memory keychain and [clock].
Future<PinVault> makeVault(TestClock clock, [FakeKeyStore? keys]) async =>
    PinVault(
      keys: keys ?? FakeKeyStore(),
      suite: await testSuite(),
      now: clock.call,
    );

/// Pumps [child] under the app theme, l10n and a [LockScope].
Future<void> pumpLock(
  WidgetTester tester,
  Widget child, {
  required PinVault vault,
  required BiometricGate biometrics,
  required TestClock clock,
  Locale? locale,
}) => pumpRk(
  tester,
  LockScope(vault: vault, biometrics: biometrics, child: child),
  locale: locale,
  now: clock.call,
);

/// Types [pin] on the pad, scrolling each key into view first when the pad
/// sits inside a scroll view (which it does at 200% on a small phone).
Future<void> typePin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    final key = find.widgetWithText(TextButton, d);
    final scrollable = find.ancestor(
      of: key,
      matching: find.byType(Scrollable),
    );
    if (scrollable.evaluate().isNotEmpty) await tester.ensureVisible(key);
    await tester.pumpAndSettle();
    await tester.tap(key);
    await tester.pumpAndSettle();
  }
}

/// Tears the tree down inside the test so pending timers fire.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
