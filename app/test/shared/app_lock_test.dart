// F1 — the shell's lock (07 §5.6 🔒, 06 §4.5, ADR 2026-09-05 §7, 13 §3.2 rows
// S15/S15.1). The lock screen, the privacy cover and the two timers all exist;
// these tests are about the shell actually mounting and driving them.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/lock_routes.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/lock/draft_activity.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import 'test_app.dart';

const _pin = '123456';

void main() {
  /// Pumps the whole app with a PIN already set, so the shell's cold-start
  /// gate applies. Biometrics answer [outcomes] (unavailable by default, which
  /// is what puts the MPIN pad on screen without a tap).
  Future<void> pumpLockedApp(
    WidgetTester tester, {
    DraftActivity? draft,
    AppSettings? settings,
    List<BiometricOutcome> outcomes = const [BiometricOutcome.unavailable],
    bool setPin = true,
  }) async {
    final keys = FakeKeyStore();
    final vault = PinVault(keys: keys, suite: await testSuite(), now: testNow);
    if (setPin) await vault.setPin(_pin);
    final db = await openTestDb();
    await tester.pumpWidget(
      RukkaFolioApp(
        db: db,
        sync: FakeSyncClient(),
        auth: FakeAuthClient(),
        keys: keys,
        now: testNow,
        locale: const Locale('en'),
        pinVault: vault,
        biometrics: FakeBiometricGate(outcomes),
        draftActivity: draft,
        settings: settings ?? AppSettings(prefs: MemoryPrefs()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester) async {
    for (final digit in _pin.split('')) {
      await tester.tap(find.widgetWithText(TextButton, digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'F1-07-68 the lock gates the app: cold start lands on S15, unlock returns '
    'to the route that was showing, backgrounding covers the app',
    (tester) async {
      await pumpLockedApp(tester);

      // Cold start with a PIN set (07 §5.6): S15 covers the shell.
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(PinKeypad), findsOneWidget);

      await typePin(tester);
      expect(find.byType(LockScreen), findsNothing);

      // Move to a second tab, then lock again by idling there.
      await tester.tap(find.text('Ledger'));
      await tester.pumpAndSettle();
      expect(
        find.text('Every account, A to Z, will be listed here.'),
        findsOneWidget,
      );

      await tester.pump(AppSettings.defaultAutoLockIdle);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);

      // Unlocking resumes exactly where the app was — the Ledger tab, not
      // Home (ADR 2026-09-05 §7: the lock never discards work).
      await typePin(tester);
      expect(find.byType(LockScreen), findsNothing);
      expect(
        find.text('Every account, A to Z, will be listed here.'),
        findsOneWidget,
      );

      // S15.1: anything that is not `resumed` covers the app, before the
      // system takes its switcher snapshot.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(PrivacyCoverSheet), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyCoverSheet), findsNothing);
    },
  );

  testWidgets(
    'F1-07-69 the timers: 5 min idle and 2 min background both lock; a draft '
    'with digits typed suppresses the idle lock only',
    (tester) async {
      final draft = DraftActivity();
      await pumpLockedApp(tester, draft: draft);
      await typePin(tester);
      expect(find.byType(LockScreen), findsNothing);

      // Idle (ADR 2026-09-05 §7, default 5 min).
      await tester.pump(AppSettings.defaultAutoLockIdle);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      await typePin(tester);

      // 🔒 07 §5.6: never while a draft has digits typed. The clock simply
      // starts again — two full idle periods pass and nothing locks.
      draft.report('entry', hasDigits: true);
      await tester.pump(AppSettings.defaultAutoLockIdle);
      await tester.pump(AppSettings.defaultAutoLockIdle);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);

      // ⚠️ SPEC: the suppression 07 §5.6 states is the *foreground* one. The
      // background timeout (06 §4.5) is read conservatively and still fires
      // with digits waiting — the draft survives the lock either way.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(AppSettings.defaultAutoLockBackground);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      await typePin(tester);

      // And with no draft, the idle lock fires again as normal.
      draft.report('entry', hasDigits: false);
      await tester.pump(AppSettings.defaultAutoLockIdle);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
    },
  );

  testWidgets('F1-07-68 no PIN set: nothing is gated and nothing is locked', (
    tester,
  ) async {
    await pumpLockedApp(tester, setPin: false);
    expect(find.byType(LockScreen), findsNothing);
    await tester.pump(AppSettings.defaultAutoLockIdle);
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);
  });
}
