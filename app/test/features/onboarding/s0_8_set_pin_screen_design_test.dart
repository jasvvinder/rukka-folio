// Design captures for S0.8 Set your PIN (ADR 2026-10-05 §2), including the
// PIN-only form of the app-lock line (ADR 2026-10-05b §1). Pair with
// `python3 scripts/design_match.py pair S0.8`.
@Tags(['F1'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/biometric_kind.dart';
import 'package:rukka_folio/features/lock/lock_scope.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_8_set_pin_screen.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';
import '../lock/lock_harness.dart';

void main() {
  testWidgets('F1-1005b-1 design capture S0.8 (six digits · mismatch · '
      'PIN-only line)', (tester) async {
    Future<void> capture(
      String state, {
      bool enrolled = true,
      String typed = '',
      bool mismatch = false,
    }) async {
      for (final target in RkDesignTarget.values) {
        final clock = TestClock();
        await rkDesignCapture(
          tester,
          sid: 'S0.8',
          state: state,
          target: target,
          child: LockScope(
            vault: await makeVault(clock),
            // ADR 2026-10-08 §3: the c1/c11 O4b pair names each phone's
            // own method — Face ID on the iPhone, the fingerprint on Android.
            biometrics: FakeBiometricGate(
              const [BiometricOutcome.unavailable],
              enrolled,
              target == RkDesignTarget.ios
                  ? BiometricModality.face
                  : BiometricModality.fingerprint,
            ),
            child: SetPinScreen(
              onBack: () {},
              debugTyped: typed,
              debugMismatch: mismatch,
            ),
          ),
        );
        await unmount(tester);
      }
    }

    await capture('default', typed: '135');
    await capture('mismatch', mismatch: true);
    await capture('pin-only', enrolled: false, typed: '135');
  });
}
