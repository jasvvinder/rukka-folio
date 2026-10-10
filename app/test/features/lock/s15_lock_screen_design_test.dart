// Design captures for S15 / S15.3 (ADR 2026-10-05 §2), including the PIN-only
// variant of ADR 2026-10-05b §1. Each state is captured for iPhone (390×844)
// and Android (360×800): the iPhone capture pairs with the c3 S15 / c1 S15.3
// *· iPhone* frames, the `__android360` capture with their *· Android* twins
// (ADR 2026-10-08 §3; RESKIN1 audit, design/match/S15.json, S15.3.json). The
// remaining lock states (S15.1) are in reskin1_lock_test.dart. Pair with
// `python3 scripts/design_match.py pair S15` / `pair S15.3`.
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/biometric_kind.dart';
import 'package:rukka_folio/features/lock/lock_scope.dart';
import 'package:rukka_folio/features/lock/screens/s15_lock_screen.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';
import 'lock_harness.dart';

/// A sheet that is still up: the attempt never answers.
final class _Waiting implements BiometricGate, BiometricModalitySource {
  _Waiting(this.modality);

  final BiometricModality modality;

  @override
  Future<BiometricModality?> enrolledModality() async => modality;

  @override
  Future<BiometricOutcome> authenticate({required String reason}) =>
      Completer<BiometricOutcome>().future;

  @override
  Future<bool> qualifyingBiometricEnrolled() async => true;
}

void main() {
  Future<void> capture(
    WidgetTester tester, {
    required String sid,
    required String state,
    required BiometricGate Function(BiometricModality modality) gate,
    int misses = 0,
    String typed = '',
    bool wrong = false,
    bool forgot = false,
    bool ladder = false,
  }) async {
    for (final target in RkDesignTarget.values) {
      // ADR 2026-10-08 §3: each frame pair names the phone's own method — the
      // iPhone frames Face ID, the Android twins the fingerprint.
      final modality = target == RkDesignTarget.ios
          ? BiometricModality.face
          : BiometricModality.fingerprint;
      final clock = TestClock();
      final vault = await makeVault(clock);
      await vault.setPin('135790');
      for (var i = 0; i < misses; i++) {
        await vault.verify('000000');
        final wait = PinVault.cooldownAfter(i + 1);
        if (wait != null) clock.advance(wait + const Duration(seconds: 1));
      }
      await rkDesignCapture(
        tester,
        sid: sid,
        state: state,
        target: target,
        child: LockScope(
          vault: vault,
          biometrics: gate(modality),
          child: LockScreen(
            onUnlocked: () {},
            onForgotPin: () {},
            onForgotPinPinOnly: ladder ? () {} : null,
            debugTyped: typed,
            debugWrong: wrong,
            debugForgotDoor: forgot,
          ),
        ),
      );
      await unmount(tester);
    }
  }

  testWidgets('F1-1005b-1 design capture S15 (waiting · face not recognised · '
      'PIN instead · PIN-only)', (tester) async {
    await capture(tester, sid: 'S15', state: 'default', gate: _Waiting.new);
    await capture(
      tester,
      sid: 'S15',
      state: 'face-not-recognised',
      gate: (m) => FakeBiometricGate([BiometricOutcome.failed], true, m),
    );
    await capture(
      tester,
      sid: 'S15',
      state: 'pin-instead',
      gate: (m) => FakeBiometricGate([BiometricOutcome.cancelled], true, m),
      typed: '13',
    );
    await capture(
      tester,
      sid: 'S15',
      state: 'pin-only',
      gate: (m) => FakeBiometricGate([BiometricOutcome.pinOnly], false, m),
      typed: '13',
    );
  });

  // ADR 2026-10-06 §4 (GATE1 review findings 2, 3): the gate was invalidated
  // — no frame draws it; nearest c3/S15 *PIN instead · six digits* and
  // c1/S15.3 *Forgot PIN* (design/match/S15.json, S15.3.json).
  testWidgets('C-1006-4 design capture S15 re-enrolled · S15.3 forgot door '
      're-enrolled (in the app, and before it is open)', (tester) async {
    await capture(
      tester,
      sid: 'S15',
      state: 'reenrolled',
      gate: (m) => FakeBiometricGate([BiometricOutcome.reenrolled], true, m),
      typed: '13',
    );
    await capture(
      tester,
      sid: 'S15.3',
      state: 'forgot-reenrolled',
      gate: (m) => FakeBiometricGate([BiometricOutcome.reenrolled], true, m),
      forgot: true,
      ladder: true,
    );
    await capture(
      tester,
      sid: 'S15.3',
      state: 'forgot-reenrolled-before-open',
      gate: (m) => FakeBiometricGate([BiometricOutcome.reenrolled], true, m),
      forgot: true,
    );
  });

  testWidgets('F1-1005b-1 design capture S15.3 (enter PIN · wrong PIN · '
      'forgot PIN)', (tester) async {
    await capture(
      tester,
      sid: 'S15.3',
      state: 'default',
      gate: (m) => FakeBiometricGate([BiometricOutcome.cancelled], true, m),
      typed: '13',
    );
    await capture(
      tester,
      sid: 'S15.3',
      state: 'wrong-pin',
      gate: (m) => FakeBiometricGate([BiometricOutcome.cancelled], true, m),
      // c1 S15.3 *Wrong PIN* says "2 tries left": eight misses spent.
      misses: 8,
      wrong: true,
    );
    await capture(
      tester,
      sid: 'S15.3',
      state: 'forgot-pin',
      gate: (m) => FakeBiometricGate([BiometricOutcome.cancelled], true, m),
      forgot: true,
    );
  });
}
