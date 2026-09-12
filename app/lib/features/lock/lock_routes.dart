// Lock feature routes (features/README, router.dart contract). Mounted on the
// root navigator: the lock covers the whole app, shell included.
//
// The screens read the [PinVault] and [BiometricGate] from a [LockScope] that
// main.dart mounts above the router — `shared/app_scope.dart` carries neither
// the libsodium suite nor a biometric seam today, and this lane does not own
// that file.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'lock_paths.dart';
import 'screens/s15_lock_screen.dart';

export 'biometric_gate.dart';
export 'lock_paths.dart';
export 'lock_scope.dart';
export 'screens/s15_lock_screen.dart' show LockReason, LockScreen;
export 'widgets/pin_pad.dart' show PinBoxes, PinKeypad, pinLength;
export 'widgets/privacy_cover.dart'
    show PrivacyCover, PrivacyCoverSheet, PrivacyCoverState;

/// S15 at [LockPaths.lock]. [onUnlocked] is what the host does once the person
/// is through — pop the lock and return the app exactly where it was, draft
/// and focus included (ADR 2026-09-05 §7: the lock never discards work).
/// [onForgotPin] opens the reset path (OTP + biometric → S0.8).
List<RouteBase> lockRoutes({
  required VoidCallback onUnlocked,
  required VoidCallback onForgotPin,
}) => [
  GoRoute(
    path: LockPaths.lock,
    builder: (context, state) => LockScreen(
      onUnlocked: onUnlocked,
      onForgotPin: onForgotPin,
      // The host passes `?reason=biometric-reenrolled` when the keystore item
      // was invalidated by an enrolment change (ADR 2026-09-05d §4).
      reason: state.uri.queryParameters['reason'] == 'biometric-reenrolled'
          ? LockReason.biometricReenrolled
          : LockReason.routine,
    ),
  ),
];
