// F1 widget tests for S15 App lock and S15.3 MPIN cooldown / disabled
// (13 §3.2 rows S15 / S15.3, 07 §5.6 🔒, 06 §4.4 🔒, ADR 2026-09-05d §5).
//
// The ladder itself is [PinVault]'s (a core behaviour with its own tests);
// what is asserted here is that the screen shows the right state at each rung,
// never offers the device passcode, and always leaves a door open.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/screens/s15_lock_screen.dart';
import 'package:rukka_folio/features/lock/widgets/pin_pad.dart';

import '../../shared/test_app.dart';
import 'lock_harness.dart';

/// Misses the PIN [times] over, walking the cooldown ladder by advancing the
/// clock past each wait (ADR 2026-09-05d §5).
Future<void> missPin(PinVault vault, TestClock clock, int times) async {
  for (var i = 0; i < times; i++) {
    await vault.verify('000000');
    final wait = PinVault.cooldownAfter(i + 1);
    if (wait != null) clock.advance(wait + const Duration(seconds: 1));
  }
}

void main() {
  group('F1-07-19 S15 App lock (07 §5.6)', () {
    testWidgets(
      'F1-07-63 biometric prompts automatically without a tap, and success '
      'opens the books',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        final gate = FakeBiometricGate();
        var unlocked = 0;
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () => unlocked++, onForgotPin: () {}),
          vault: vault,
          biometrics: gate,
          clock: clock,
        );

        expect(find.text('Unlock to open your books'), findsOneWidget);
        // No tap happened between pumping and here.
        expect(gate.prompts, ['Unlock your books']);
        expect(unlocked, 1);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-63 a failed sensor falls back to the 6-digit MPIN — never the '
      "phone's passcode (06 §4.4 🔒)",
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        var unlocked = 0;
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () => unlocked++, onForgotPin: () {}),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.failed]),
          clock: clock,
        );

        expect(find.byType(PinKeypad), findsOneWidget);
        expect(
          find.text("Face ID didn't work — type your PIN"),
          findsOneWidget,
        );
        expect(find.textContaining('passcode'), findsNothing);

        await typePin(tester, '135790');
        expect(unlocked, 1);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-63 a wrong PIN says so and clears the boxes; the right one opens',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        var unlocked = 0;
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () => unlocked++, onForgotPin: () {}),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.unavailable]),
          clock: clock,
        );

        expect(
          find.text(
            "Face ID isn't available on this phone right now — type your PIN",
          ),
          findsOneWidget,
        );
        await typePin(tester, '111111');
        expect(find.text('That PIN is not right'), findsOneWidget);
        expect(unlocked, 0);
        // Error is never colour alone (07 §1 rule 3): a word and an icon.
        expect(find.byIcon(Icons.error_outline), findsOneWidget);

        await typePin(tester, '135790');
        expect(unlocked, 1);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-63 the tries-left warning only appears once the 5 free attempts '
      'are spent (ADR 2026-09-05d §5)',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        await missPin(vault, clock, 4);
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.cancelled]),
          clock: clock,
        );

        // Four misses: still inside the free band, so no threat on screen.
        expect(find.byType(PinKeypad), findsOneWidget);
        expect(find.textContaining('tries left'), findsNothing);
        expect(find.textContaining('One try left'), findsNothing);
        await unmount(tester);
      },
    );
  });

  group('F1-07-19 S15.3 MPIN cooldown / disabled (ADR 2026-09-05d §5)', () {
    testWidgets(
      'F1-07-63 the 5th miss opens a 30-second cooldown with a countdown row '
      'and no usable pad — a code, not a lockout',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.failed]),
          clock: clock,
        );

        for (var i = 0; i < 5; i++) {
          await typePin(tester, '111111');
        }

        expect(find.text('Take a short break'), findsOneWidget);
        expect(
          find.textContaining("It's a code, not a lockout"),
          findsOneWidget,
        );
        expect(find.text('Try again in 0:30'), findsOneWidget);
        expect(find.byType(PinKeypad), findsNothing);

        // The countdown is live and reads the injected clock.
        clock.advance(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Try again in 0:20'), findsOneWidget);

        // When the wait is over the pad comes back on its own.
        clock.advance(const Duration(seconds: 21));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.byType(PinKeypad), findsOneWidget);
        expect(find.textContaining('tries left'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-63 the ladder is 30 s · 1 min · 5 min · 15 min · 1 h, rendered '
      'from the vault so it cannot drift',
      (tester) async {
        sizeView(tester);
        const expected = ['0:30', '1:00', '5:00', '15:00', '1:00:00'];
        for (var rung = 0; rung < expected.length; rung++) {
          final clock = TestClock();
          final vault = await makeVault(clock);
          await vault.setPin('135790');
          await missPin(vault, clock, 5 + rung - 1);
          // The rung's own wait is still ahead: miss once more without
          // advancing the clock.
          await vault.verify('000000');
          await pumpLock(
            tester,
            LockScreen(onUnlocked: () {}, onForgotPin: () {}),
            vault: vault,
            biometrics: FakeBiometricGate([BiometricOutcome.cancelled]),
            clock: clock,
          );
          expect(
            find.text('Try again in ${expected[rung]}'),
            findsOneWidget,
            reason: 'rung $rung of the cooldown ladder',
          );
          await unmount(tester);
        }
      },
    );

    testWidgets(
      'F1-07-63 after 10 misses the PIN is switched off and the only door is '
      'OTP + biometric — never data loss (06 §4.4)',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        await missPin(vault, clock, 10);
        var forgot = 0;
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () => forgot++),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.cancelled]),
          clock: clock,
        );

        expect(await vault.status(), isA<PinDisabled>());
        expect(find.text('The PIN is switched off'), findsOneWidget);
        expect(
          find.textContaining('Your books are safe and nothing is lost'),
          findsOneWidget,
        );
        expect(find.byType(PinKeypad), findsNothing);

        // The door is live, not decorative (07 §1 rule 6).
        await tester.tap(find.text('Send me a code'));
        await tester.pumpAndSettle();
        expect(find.text('Set a new PIN'), findsOneWidget);
        await tester.tap(find.text('Send me a code'));
        await tester.pumpAndSettle();
        expect(forgot, 1);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-63 biometric re-enrolment asks for the PIN once, in its own words '
      '(ADR 2026-09-05d §4)',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        final gate = FakeBiometricGate();
        await pumpLock(
          tester,
          LockScreen(
            onUnlocked: () {},
            onForgotPin: () {},
            reason: LockReason.biometricReenrolled,
          ),
          vault: vault,
          biometrics: gate,
          clock: clock,
        );

        expect(
          find.text(
            'A new face or fingerprint was added to this phone — enter your PIN once',
          ),
          findsOneWidget,
        );
        // The sensor cannot open the invalidated item, so it is not asked.
        expect(gate.prompts, isEmpty);
        expect(find.byType(PinKeypad), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-63 the forgot-PIN door is reachable from the ordinary pad too, '
      'and explains that nothing is re-encrypted',
      (tester) async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.failed]),
          clock: clock,
        );

        await tester.tap(find.text('Forgot your PIN?'));
        await tester.pumpAndSettle();
        expect(find.textContaining('your books are untouched'), findsOneWidget);
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(PinKeypad), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-63 strings resolve in EN/PA/HI and hold at 200% on a 360x800 phone',
      (tester) async {
        sizeView(tester, width: 360, height: 800);
        for (final locale in lockLocales) {
          final clock = TestClock();
          final vault = await makeVault(clock);
          await vault.setPin('135790');
          await missPin(vault, clock, 5);
          await pumpLock(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: LockScreen(onUnlocked: () {}, onForgotPin: () {}),
            ),
            vault: vault,
            biometrics: FakeBiometricGate([BiometricOutcome.cancelled]),
            clock: clock,
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(PinKeypad), findsOneWidget);
          await typePin(tester, '111111');
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      },
    );
  });
}
