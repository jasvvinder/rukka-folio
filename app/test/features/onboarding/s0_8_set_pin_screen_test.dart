// F1 widget tests for S0.8 Set your PIN (13 §3.2 row S0.8, 13 §5 flow F1,
// 06 §4.4 🔒 six digits, one PIN). The PIN lands in the one [PinVault] —
// asserted by verifying it back through the same vault, so a screen that
// invented a second store would fail here.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/widgets/pin_pad.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_8_set_pin_screen.dart';

import '../../shared/test_app.dart';
import '../lock/lock_harness.dart';

void main() {
  group('S0.8 Set your PIN (07 §3.1, 06 §4.4)', () {
    testWidgets('F1-07-62 Continue is disabled with a reason until all 6 digits are typed '
        '(13 §4.3 disabled-with-reason)', (tester) async {
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

      expect(find.text('Type all 6 digits to continue'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await typePin(tester, '12345');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'five digits is not a 6-digit MPIN (06 §4.4 🔒)',
      );

      await typePin(tester, '6');
      expect(find.text('Type all 6 digits to continue'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await unmount(tester);
    });

    testWidgets('F1-07-62 the PIN is confirmed before it is saved; a mismatch starts over '
        'and saves nothing', (tester) async {
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
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text('Type it once more'), findsOneWidget);

      await typePin(tester, '246814');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text("Those two didn't match — start again"), findsOneWidget);
      expect(find.text('Set your PIN'), findsOneWidget);
      expect(done, 0);
      expect(await vault.status(), isA<PinNotSet>());
      await unmount(tester);
    });

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
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await typePin(tester, '246813');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

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
      'F1-07-62 strings resolve in EN/PA/HI and hold at 200% on a 360x800 phone',
      (tester) async {
        sizeView(tester, width: 360, height: 800);
        for (final locale in lockLocales) {
          final clock = TestClock();
          final vault = await makeVault(clock);
          await pumpLock(
            tester,
            const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SetPinScreen(),
            ),
            vault: vault,
            biometrics: FakeBiometricGate(),
            clock: clock,
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(PinKeypad), findsOneWidget);
          await typePin(tester, '123456');
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      },
    );
  });
}
