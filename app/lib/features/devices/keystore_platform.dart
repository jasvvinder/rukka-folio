// The app's own keystore helper channel (ADR 2026-10-05b), for the things
// flutter_secure_storage 11.2.0 cannot do. The native halves:
//   Android  app/android/app/src/main/kotlin/com/rukkafolio/rukka_folio/RukkaKeystoreChannel.kt
//   iOS      app/ios/Runner/AppDelegate.swift (RukkaKeystoreChannel)
//
//  • [qualifyingBiometricEnrolled] — ruling 1: is a biometric that can guard a
//    hardware key enrolled now? iOS: Face ID or Touch ID. Android: any Class 3
//    (strong) biometric, answered by creating the very key the plugin would
//    create for the device-key items and deleting it. A Class 2 (weak) face
//    unlock answers false (desk 149, conservative reading (a)). The device
//    passcode never counts (07 §5.6).
//  • [resetBiometricDeviceItems] — ruling 3: Android removes the invalidated
//    Keystore alias and the prefs of the `rukka_folio_device` namespace only;
//    the plugin cannot (every call initialises first, which fails on the
//    invalidated key). iOS answers without doing anything — the plugin's own
//    delete works there.
//  • [excludeFromBackup] — desk 150 / ADR 2026-09-05c §8: iOS sets
//    NSURLIsExcludedFromBackupKey; Android is a no-op (the manifest does it).
//  • [authenticate] / [armBiometricGate] — the in-app S15's biometric prompt
//    for the background / idle relock (07 §5.6 🔒 "after the background
//    timeout … biometric prompting automatically"; 13 §3.2 S15). Once the
//    device keys are open, flutter_secure_storage holds their cipher in memory
//    and a keystore read prompts nothing, so the relock needs a prompt of its
//    own. It is bound to the *current* biometric set, exactly like the device
//    keys (ADR 2026-09-05d §4), so a face added while the app was in the
//    background is caught here too:
//      Android — BiometricPrompt (BIOMETRIC_STRONG, never the device
//        credential) over a CryptoObject on a dedicated AES gate key created
//        with setUserAuthenticationRequired + setInvalidatedByBiometricEnrollment;
//        an invalidated gate key answers *reenrolled* and is removed.
//      iOS — LAContext `.deviceOwnerAuthenticationWithBiometrics` (never the
//        passcode; the fallback button is hidden) and the
//        `evaluatedPolicyDomainState` recorded when the gate was armed; a
//        different state answers *reenrolled*.
//    The gate is (re-)armed only where the current biometric set is already
//    proven to be the device keys' own: after a successful MPIN, and after the
//    cold start opened the biometric-bound device keys (bootstrap.dart).
//    ⚠️ Not verified on a device in this lane (iOS not at all); the Dart side
//    is covered over the channel by the emulator in the F1 tests.
import 'package:flutter/services.dart';

/// What the platform's own biometric prompt answered ([KeystorePlatform.authenticate]).
enum PlatformBiometricAnswer {
  /// The current biometric set proved the person.
  success,

  /// The sensor said no and the prompt ended (too many tries).
  failed,

  /// The person dismissed the prompt or chose *Use PIN instead*.
  cancelled,

  /// No usable biometric right now (none enrolled, locked out, no hardware).
  unavailable,

  /// The enrolled set changed since the gate was armed — the PIN, once.
  reenrolled,

  /// The gate was never armed on this install (or arming failed): nothing to
  /// prompt against until the next PIN arms it.
  unarmed,
}

/// The platform half of the device-key custody (ADR 2026-10-05b).
abstract interface class KeystorePlatform {
  /// Whether a biometric that can guard a hardware key is enrolled now.
  /// Never throws: anything the platform cannot answer is `false`, which puts
  /// the phone on the PIN-only path — the safe side (ruling 1).
  Future<bool> qualifyingBiometricEnrolled();

  /// Removes the biometric-bound device-key items whose key the platform has
  /// invalidated (Android). A no-op on iOS.
  Future<void> resetBiometricDeviceItems();

  /// Keeps each existing file in [paths] out of the platform backup (iOS).
  Future<void> excludeFromBackup(List<String> paths);

  /// Raises the platform's biometric prompt with the ARB copy given — never
  /// the device credential (07 §5.6). Never throws: a channel failure is
  /// [PlatformBiometricAnswer.unavailable], which leaves the PIN.
  Future<PlatformBiometricAnswer> authenticate({
    required String title,
    required String subtitle,
    required String cancel,
  });

  /// Binds the relock gate to the biometric set enrolled now. Called only
  /// where that set is already proven (file comment). Never throws; `false`
  /// when the platform could not arm it.
  Future<bool> armBiometricGate();
}

/// The production [KeystorePlatform] over `rukka_folio/keystore`.
final class MethodChannelKeystorePlatform implements KeystorePlatform {
  const MethodChannelKeystorePlatform();

  /// The channel name both native halves register.
  static const channel = MethodChannel('rukka_folio/keystore');

  @override
  Future<bool> qualifyingBiometricEnrolled() async {
    try {
      return await channel.invokeMethod<bool>('qualifyingBiometricEnrolled') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> resetBiometricDeviceItems() =>
      channel.invokeMethod<Object?>('resetBiometricDeviceItems');

  @override
  Future<void> excludeFromBackup(List<String> paths) =>
      channel.invokeMethod<Object?>('excludeFromBackup', {'paths': paths});

  @override
  Future<PlatformBiometricAnswer> authenticate({
    required String title,
    required String subtitle,
    required String cancel,
  }) async {
    try {
      final answer = await channel.invokeMethod<String>('authenticate', {
        'title': title,
        'subtitle': subtitle,
        'cancel': cancel,
      });
      return PlatformBiometricAnswer.values.firstWhere(
        (a) => a.name == answer,
        orElse: () => PlatformBiometricAnswer.unavailable,
      );
    } on PlatformException {
      return PlatformBiometricAnswer.unavailable;
    } on MissingPluginException {
      return PlatformBiometricAnswer.unavailable;
    }
  }

  @override
  Future<bool> armBiometricGate() async {
    try {
      return await channel.invokeMethod<bool>('armBiometricGate') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
