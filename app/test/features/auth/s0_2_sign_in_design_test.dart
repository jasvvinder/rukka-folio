// Design captures for the sign-in journey (ADR 2026-10-05 §2; ADR 2026-10-05c,
// canvas 1b): S0.2 on both doors (c1 O2a/O2b, c1b L2/L3/L4), S0.2a (L1),
// S0.2b (L5) and S0.2e (L8). S0.06 (L0) is captured from features/onboarding.
// Pair with `python3 scripts/design_match.py pair S0.2` (and S0.2a, S0.2b,
// S0.2e).
@Tags(['F1'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/screens/s0_2_phone_otp_screen.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';

import '../../shared/design_capture.dart';
import '../lock/lock_harness.dart' show unmount;

/// The canvas's number (c1b): the reserved test block is used everywhere
/// else; the frames draw 98765 43210, so the captures do too.
const _number = '9876543210';

void main() {
  testWidgets('F1-1005c-1 design capture S0.2 · S0.2a · S0.2b · S0.2e '
      '(canvas 1 O2a/O2b, canvas 1b L1–L5, L8)', (tester) async {
    Future<void> capture(String sid, String state, Widget child) async {
      for (final target in RkDesignTarget.values) {
        await rkDesignCapture(
          tester,
          sid: sid,
          state: state,
          target: target,
          child: child,
        );
        await unmount(tester);
      }
    }

    // c1 O2a — I'm new, part-typed, Send waits for ten digits.
    await capture(
      'S0.2',
      'new-number',
      PhoneOtpScreen(
        onboardingStep: true,
        onBack: () {},
        debugPhone: '98765 43'.replaceAll(' ', ''),
      ),
    );
    // c1 O2b / c11 O2b — I'm new, three digits in, the 0:24 wait.
    await capture(
      'S0.2',
      'new-code',
      PhoneOtpScreen(
        onboardingStep: true,
        debugStep: PhoneOtpStep.otp,
        debugPhone: _number,
        debugCode: '491',
        debugResendSeconds: 24,
      ),
    );
    // c1b L2 — sign in, the number typed.
    await capture(
      'S0.2',
      'sign-in-number',
      PhoneOtpScreen(
        door: SignInDoor.signIn,
        onBack: () {},
        debugPhone: _number,
      ),
    );
    // c1b L3 — the code, five in, the wait over.
    await capture(
      'S0.2',
      'sign-in-code',
      const PhoneOtpScreen(
        door: SignInDoor.signIn,
        debugStep: PhoneOtpStep.otp,
        debugPhone: _number,
        debugCode: '49172',
        debugResendSeconds: 0,
      ),
    );
    // c1b L4 — wrong code, two tries left.
    await capture(
      'S0.2',
      'wrong-code',
      const PhoneOtpScreen(
        door: SignInDoor.signIn,
        debugStep: PhoneOtpStep.otp,
        debugPhone: _number,
        debugCode: '491728',
        debugWrongTriesLeft: 2,
        debugResendSeconds: 0,
      ),
    );
    // c1b L1 — S0.2a.
    await capture(
      'S0.2a',
      'default',
      const PhoneOtpScreen(
        debugStep: PhoneOtpStep.hasBooks,
        debugPhone: _number,
      ),
    );
    // c1b L5 — S0.2b, Yes disabled with its reason (PLAN SIGNIN2).
    await capture(
      'S0.2b',
      'default',
      const PhoneOtpScreen(
        door: SignInDoor.signIn,
        debugStep: PhoneOtpStep.foundYou,
        debugPhone: _number,
      ),
    );
    // c1b L8 — S0.2e.
    await capture(
      'S0.2e',
      'default',
      const PhoneOtpScreen(
        door: SignInDoor.signIn,
        debugStep: PhoneOtpStep.noBooks,
        debugPhone: _number,
      ),
    );
  });
}
