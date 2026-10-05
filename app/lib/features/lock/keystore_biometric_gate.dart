// The production [BiometricGate] (ADR 2026-10-05b), read by the in-app S15
// that RukkaFolioApp mounts for the background / idle lock and for a cold
// start that needed no biometric.
//
// What it answers:
//   • the phone is PIN-only (the device keys sit in the PIN-only class) →
//     [BiometricOutcome.pinOnly], nothing prompted: S15 shows the PIN boxes and
//     no biometric button (ruling 1);
//   • the person was proved at the cold-start gate moments ago (the device-key
//     read *was* the biometric prompt, cold_start_gate.dart) → one
//     [BiometricOutcome.success], spent on the first ask, so the app does not
//     ask twice for the same launch;
//   • otherwise the platform's own prompt ([KeystorePlatform.authenticate]) —
//     07 §5.6 🔒 "after the background timeout … biometric prompting
//     automatically", 13 §3.2 S15 "background 2 min / idle 5 min | biometric
//     auto-prompt". Once the device keys are open, flutter_secure_storage keeps
//     their cipher in memory and a keystore read prompts nothing, so the relock
//     prompt is the app's own, bound to the current biometric set exactly as
//     the device keys are (keystore_platform.dart). Before KEY145B this branch
//     answered *unavailable* on every relock of a biometric phone, which drew
//     "Face ID isn't available" beside a Face ID button that did nothing
//     (review finding 3).
//
// The relock gate is armed ([armAfterProof]) only where the current biometric
// set is already proven to be the device keys' own: after a successful MPIN,
// and after the cold start opened the biometric-bound keys (bootstrap.dart).
import '../devices/keychain_key_store.dart';
import '../devices/keystore_platform.dart';
import 'biometric_gate.dart';

/// [BiometricGate] over the device-key custody.
final class KeystoreBiometricGate implements BiometricGate {
  KeystoreBiometricGate({required this.keys, required this.platform});

  /// Where the binding record and the ARB prompt copy live.
  final KeychainKeyStore keys;

  /// The enrolment question and the prompt itself.
  final KeystorePlatform platform;

  bool _admitted = false;

  /// The cold-start gate opened the device keys with the person's biometric:
  /// the next [authenticate] answers success once, without asking again.
  void admitOnce() => _admitted = true;

  /// Binds the relock prompt to the biometric set enrolled now. Only after a
  /// proof that this set is the device keys' own (file comment); a PIN-only
  /// phone has nothing to arm.
  Future<void> armAfterProof() async {
    if (await keys.binding() == DeviceKeyBinding.pinOnly) return;
    await platform.armBiometricGate();
  }

  @override
  Future<BiometricOutcome> authenticate({required String reason}) async {
    // No record ⇒ an install from before ADR 2026-10-05b, biometric-bound.
    if (await keys.binding() == DeviceKeyBinding.pinOnly) {
      _admitted = false;
      return BiometricOutcome.pinOnly;
    }
    if (_admitted) {
      _admitted = false;
      return BiometricOutcome.success;
    }
    final copy = keys.promptCopy;
    // Bootstrap sets the ARB copy before the app exists; without it the
    // platform would have to show words that are not in ARB (01 §1.8).
    if (copy == null) return BiometricOutcome.unavailable;
    final answer = await platform.authenticate(
      title: reason,
      subtitle: copy.subtitle,
      cancel: copy.cancel,
    );
    return switch (answer) {
      PlatformBiometricAnswer.success => BiometricOutcome.success,
      PlatformBiometricAnswer.failed => BiometricOutcome.failed,
      PlatformBiometricAnswer.cancelled => BiometricOutcome.cancelled,
      PlatformBiometricAnswer.reenrolled => BiometricOutcome.reenrolled,
      // ⚠️ SPEC: never armed (arming failed on this install) — the PIN carries
      // the unlock and arms the gate for the next relock. No copy names this
      // state; *unavailable* is the nearest true line.
      PlatformBiometricAnswer.unarmed ||
      PlatformBiometricAnswer.unavailable => BiometricOutcome.unavailable,
    };
  }

  @override
  Future<bool> qualifyingBiometricEnrolled() =>
      platform.qualifyingBiometricEnrolled();
}
