// F1 widget tests for S0.8 Set your PIN (13 §3.2 row S0.8, 13 §5 flow F1,
// 06 §4.4 🔒 six digits, one PIN). The PIN lands in the one [PinVault] —
// asserted by verifying it back through the same vault, so a screen that
// invented a second store would fail here.
@Tags(['F1'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
import 'package:rukka_folio/features/devices/keystore_platform.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/keystore_biometric_gate.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/widgets/pin_pad.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_8_set_pin_screen.dart';

import '../../shared/test_app.dart';
import '../devices/keystore_emulator.dart';
import '../lock/lock_harness.dart';

void main() {
  group('S0.8 Set your PIN (07 §3.1, 06 §4.4)', () {
    testWidgets(
      'F1-07-62 a step advances only at the sixth digit — five is not a '
      'PIN (06 §4.4 🔒; c1 O4b draws no Continue, *Six digits* says why)',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await pumpLock(
          tester,
          const SetPinScreen(),
          vault: vault,
          biometrics: FakeBiometricGate(),
          clock: clock,
        );

        expect(find.text('Six digits'), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);

        await typePin(tester, '12345');
        expect(
          find.text('Set your PIN'),
          findsOneWidget,
          reason: 'five digits is not a 6-digit MPIN (06 §4.4 🔒)',
        );
        expect(find.text('Type it again'), findsNothing);

        await typePin(tester, '6');
        expect(find.text('Type it again'), findsOneWidget);
        expect(await vault.status(), isA<PinNotSet>());
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-62 the PIN is confirmed before it is saved; a mismatch clears '
      'both entries and saves nothing (c1 O4b *Mismatch on confirm*)',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        var done = 0;
        await pumpLock(
          tester,
          SetPinScreen(onDone: () => done++),
          vault: vault,
          biometrics: FakeBiometricGate(),
          clock: clock,
        );

        await typePin(tester, '246813');
        expect(find.text('Type it again'), findsOneWidget);

        await typePin(tester, '246814');
        // Drawn as the confirm step that failed: words, an icon and six
        // debit-edged boxes (07 §1 rule 3).
        expect(
          find.text("Those two didn't match. Start again."),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(tester.widget<PinBoxes>(find.byType(PinBoxes)).error, isTrue);
        expect(done, 0);
        expect(await vault.status(), isA<PinNotSet>());

        // Both entries were cleared: the next digit starts a new first entry.
        await typePin(tester, '1');
        expect(find.text('Set your PIN'), findsOneWidget);
        expect(find.text("Those two didn't match. Start again."), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets('F1-07-62 matching entries write the one vault and the vault accepts that '
        'PIN afterwards', (tester) async {
      sizeView(tester);
      final clock = TestClock();
      final vault = await makeVault(clock);
      var done = 0;
      await pumpLock(
        tester,
        SetPinScreen(onDone: () => done++),
        vault: vault,
        biometrics: FakeBiometricGate(),
        clock: clock,
      );

      await typePin(tester, '246813');
      await typePin(tester, '246813');

      expect(done, 1);
      expect(await vault.status(), isA<PinReady>());
      expect(await vault.verify('246813'), isA<PinAccepted>());
      await unmount(tester);
    });

    testWidgets(
      'F1-07-62 the digits are never rendered — the boxes fill, the number '
      'does not appear',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await pumpLock(
          tester,
          const SetPinScreen(),
          vault: vault,
          biometrics: FakeBiometricGate(),
          clock: clock,
        );

        await typePin(tester, '777777');
        // Six keypad keys carry a '7' glyph, and exactly one of them is the
        // key itself; nothing else on the screen echoes the typed PIN.
        expect(find.text('7'), findsOneWidget);
        expect(find.text('777777'), findsNothing);
        expect(find.byType(PinBoxes), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-62 the app-lock line is stated, not offered as a setting '
      '(07 §5.6, ADR 2026-09-05d §4)',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await pumpLock(
          tester,
          const SetPinScreen(),
          vault: vault,
          biometrics: FakeBiometricGate(),
          clock: clock,
        );

        expect(
          find.textContaining('if a new face is added to this phone'),
          findsOneWidget,
        );
        // Stated: there is nothing to switch off.
        expect(find.byType(Switch), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-62 strings resolve in EN/PA/HI and hold at 1.3x and 200% on '
      'both F1 phones',
      (tester) async {
        for (final locale in lockLocales) {
          for (final vp in rkPhones) {
            for (final scale in rkTextScales) {
              final clock = TestClock();
              final vault = await makeVault(clock);
              await pumpLock(
                tester,
                const SetPinScreen(),
                vault: vault,
                biometrics: FakeBiometricGate(),
                clock: clock,
                locale: locale,
                textScale: scale,
                viewport: vp,
              );
              expect(tester.takeException(), isNull);
              expect(find.byType(PinKeypad), findsOneWidget);
              expectTextFits(
                tester,
                reason: '${locale.languageCode} @ $scale on $vp',
              );
              await typePin(tester, '123456');
              expect(tester.takeException(), isNull);
              await unmount(tester);
            }
          }
        }
      },
    );
  });

  group('C-1006-2 the gate is minted after O4b (ADR 2026-10-06 §2)', () {
    testWidgets('C-1006-2 setting the PIN at S0.8 mints the gate on a phone '
        'with a qualifying biometric and none on a PIN-only phone — never '
        'before the PIN exists, and without writing a device key', (
      tester,
    ) async {
      for (final enrolled in [true, false]) {
        sizeView(tester);
        final android = AndroidKeystoreEmulator(enrolled: enrolled)..install();
        final keys = KeychainKeyStore();
        // First run: no PIN yet, the store opens and the device keys are
        // minted (their class record first) — and no gate exists.
        await tester.runAsync(() async {
          expect(await keys.unsealIfNoPin(), isTrue);
          await keys.write(KeyIds.deviceSigningKey, Uint8List(32));
        });
        expect(android.nativeMethods, isNot(contains('armBiometricGate')));
        android.native.clear();
        final vault = PinVault(
          keys: keys,
          suite: await testSuite(),
          now: testNow,
          onPinProven: keys.unsealAfterPin,
          afterPinProven: () async {
            await keys.afterPinProven();
          },
        );
        final clock = TestClock();
        await pumpLock(
          tester,
          SetPinScreen(onDone: () {}),
          vault: vault,
          biometrics: KeystoreBiometricGate(
            keys: keys,
            platform: const MethodChannelKeystorePlatform(),
          ),
          clock: clock,
        );
        await typePin(tester, '246813');
        expect(android.gateMinted, isFalse, reason: 'not before the confirm');
        await typePin(tester, '246813');
        await tester.runAsync(() async => vault.pendingAfterPin);
        await tester.pumpAndSettle();
        expect(android.gateMinted, enrolled, reason: 'enrolled: $enrolled');
        expect(await tester.runAsync(keys.gateArmed), enrolled);
        expect(
          android.nativeMethods.where((m) => m.startsWith('deviceItem')),
          isEmpty,
          reason: 'the gate moves no device key',
        );
        await unmount(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
