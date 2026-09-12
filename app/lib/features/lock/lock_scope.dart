// The lock family's two collaborators, handed down the tree: the MPIN vault
// (features/devices/pin_vault.dart — the one store, never a second one) and
// the biometric seam. Both are injected rather than constructed here, because
// building a [PinVault] needs the libsodium suite and the keychain, and
// `shared/app_scope.dart` (shell-owned) carries neither today.
//
// main.dart mounts one of these above the router; a widget test mounts one
// over a `FakeKeyStore`-backed vault and a `FakeBiometricGate`.
import 'package:flutter/widgets.dart';

import '../devices/pin_vault.dart';
import 'biometric_gate.dart';

/// Carries the [PinVault] and [BiometricGate] to S0.8, S15 and S15.3.
class LockScope extends InheritedWidget {
  /// Wraps [child].
  const LockScope({
    super.key,
    required this.vault,
    required this.biometrics,
    required super.child,
  });

  /// The MPIN gate (06 §4.4, ADR 2026-09-05d §5).
  final PinVault vault;

  /// Face ID / Touch ID (07 §5.6).
  final BiometricGate biometrics;

  /// The nearest scope, or null when none is mounted.
  static LockScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LockScope>();

  /// The nearest scope; throws when the lock family is not mounted.
  static LockScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw FlutterError('No LockScope above this widget (see pumpLock)');
    }
    return scope;
  }

  @override
  bool updateShouldNotify(LockScope old) =>
      vault != old.vault || biometrics != old.biometrics;
}
