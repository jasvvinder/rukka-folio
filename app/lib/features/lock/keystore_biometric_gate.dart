// The production [BiometricGate] (ADR 2026-10-06 🔒), read by S15 — the
// cold-start one (cold_start_gate.dart, through [openAtColdStart]) and the
// in-app one RukkaFolioApp mounts for the background / idle relock.
//
// What it answers:
//   • the person was let through by the cold-start S15 moments ago (the gate
//     or the MPIN) → one [BiometricOutcome.success], spent on the first ask,
//     so the app does not ask twice for the same launch ([admitOnce]);
//   • no gate on this install (a PIN-only phone, ADR 2026-10-05b §1 — or one
//     whose device keys still sit in a legacy class) → [BiometricOutcome
//     .pinOnly], nothing prompted: S15 shows the PIN boxes and no biometric
//     button;
//   • otherwise the gate read ([KeychainKeyStore.openWithGate]) — the
//     platform's own prompt over the gate item, bound to the current
//     biometric set (ruling 2). Its success opens the device keys (ruling 3);
//     an invalidated gate answers [BiometricOutcome.reenrolled] and S15 asks
//     for the MPIN once, after which a new gate is minted (ruling 4,
//     [KeychainKeyStore.afterPinProven]). A cancelled or failed read leaves
//     *Use PIN instead* — never a blocked screen.
import '../devices/keychain_key_store.dart';
import '../devices/keystore_platform.dart';
import 'biometric_gate.dart';
import 'biometric_kind.dart';

/// [BiometricGate] over the gate key.
final class KeystoreBiometricGate
    implements SealingBiometricGate, BiometricModalitySource {
  KeystoreBiometricGate({
    required this.keys,
    required this.platform,
    this.modality,
  });

  /// Which biometric is enrolled (ADR 2026-10-08 §3: the screens name the
  /// method the phone uses). ⚠️ SPEC: the keystore channel has no such query
  /// yet (features/devices + the native halves), so the host passes none and
  /// the method is named neutrally — never guessed (WORDS179 open item).
  final Future<BiometricModality?> Function()? modality;

  @override
  Future<BiometricModality?> enrolledModality() async => await modality?.call();

  /// The device-key custody: the gate record, the gate read, the ARB copy.
  final KeychainKeyStore keys;

  /// The enrolment question.
  final KeystorePlatform platform;

  bool _admitted = false;

  /// The cold-start S15 let the person through (gate or MPIN): the next
  /// [authenticate] answers success once, without asking again.
  void admitOnce() => _admitted = true;

  /// The cold start's biometric attempt: the gate read — or `null` on an
  /// install whose device keys still sit in the legacy biometric-bound class,
  /// where the device-key read itself raises the platform prompt (ruling 5:
  /// it opens once more that way, and is migrated right after).
  Future<BiometricOutcome?> openAtColdStart({required String reason}) async {
    if (await keys.deviceKeyClass() == DeviceKeyClass.legacyBiometric &&
        !await keys.gateArmed()) {
      return null;
    }
    return _readGate(reason);
  }

  /// Ruling 3 at the relock (07 §5.6 background timeout, and the idle lock):
  /// the in-app S15 seals the device keys as it covers the app; the gate read
  /// or the MPIN opens them again. Not the S15 that follows a cold start the
  /// person has just passed ([admitOnce]) — that one opens without asking.
  ///
  /// ⚠️ SPEC: ADR 2026-10-06 §3 names the cold start and the background
  /// timeout; the 5-minute idle lock (ADR 2026-09-05 §7) puts up the same S15
  /// and is sealed too — the stricter reading, with the same two doors out.
  @override
  void sealBehindLock() {
    if (_admitted) return;
    keys.seal();
  }

  @override
  Future<BiometricOutcome> authenticate({required String reason}) async {
    if (_admitted) {
      _admitted = false;
      return BiometricOutcome.success;
    }
    return _readGate(reason);
  }

  Future<BiometricOutcome> _readGate(String reason) async {
    final answer = await keys.openWithGate(title: reason);
    return switch (answer) {
      PlatformBiometricAnswer.success => BiometricOutcome.success,
      PlatformBiometricAnswer.failed => BiometricOutcome.failed,
      PlatformBiometricAnswer.cancelled => BiometricOutcome.cancelled,
      PlatformBiometricAnswer.reenrolled => BiometricOutcome.reenrolled,
      PlatformBiometricAnswer.unarmed => BiometricOutcome.pinOnly,
      PlatformBiometricAnswer.unavailable => BiometricOutcome.unavailable,
    };
  }

  @override
  Future<bool> qualifyingBiometricEnrolled() =>
      platform.qualifyingBiometricEnrolled();
}
