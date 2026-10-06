// The app's own keystore helper channel (ADR 2026-10-05b, ADR 2026-10-06), for
// the things flutter_secure_storage 11.2.0 cannot do. The native halves:
//   Android  app/android/app/src/main/kotlin/com/rukkafolio/rukka_folio/RukkaKeystoreChannel.kt
//   iOS      app/ios/Runner/AppDelegate.swift (RukkaKeystoreChannel)
//
//  • [qualifyingBiometricEnrolled] — ADR 2026-10-05b §1: is a biometric that
//    can guard a hardware key enrolled now? iOS: Face ID or Touch ID. Android:
//    any Class 3 (strong) biometric, answered by creating a key that needs one
//    and deleting it. A Class 2 (weak) face unlock answers false (desk 149,
//    conservative reading (a)). The device passcode never counts (07 §5.6).
//  • The **device-key class** (ADR 2026-10-06 §1 🔒) on Android —
//    [deviceItemRead] / [deviceItemWrite] / [deviceItemDelete] /
//    [deviceItemContains]: the device signing seed, the device agreement seed
//    and the locally wrapped UMK, sealed by an AES-256-GCM Keystore key that is
//    StrongBox-backed where the phone has StrongBox, TEE otherwise, with **no
//    user-authentication binding and no enrolment invalidation**. The plugin
//    cannot make that key: its AES key cipher sets
//    `setUserAuthenticationRequired(true)` whenever the phone has a screen lock
//    (flutter_secure_storage 11.2.0 KeyCipherImplementationAES23.java:166-186;
//    `false` only on a phone with no screen lock, :182-185), and its RSA-OAEP
//    key cipher never asks for StrongBox (KeyCipherImplementationRSAOAEP.java
//    :145-155 builds its spec without setIsStrongBoxBacked). iOS keeps
//    these items in the Keychain through the plugin (this-device-only, no
//    access control), so these four methods are Android's alone.
//    [deviceKeyStorage] reports which hardware holds that key (no secret).
//  • The **gate** (ADR 2026-10-06 §2 🔒) — [armBiometricGate] mints it,
//    [authenticate] reads it with the person's biometric (that read *is* the
//    unlock), [resetGate] removes it. A random secret in its own item, bound to
//    the current biometric set: Android an AES-256-GCM Keystore key that needs
//    BIOMETRIC_STRONG on every use and is invalidated by any enrolment change
//    (the key itself is the secret; a read is an authenticated cipher
//    operation over a CryptoObject); iOS a Keychain item holding 32 random
//    bytes under `biometryCurrentSet`. The gate opens no data and is never a
//    key to data. [resetGate] touches the gate and nothing else — never a
//    device-key item (ruling 4).
//  • [excludeFromBackup] — desk 150 / ADR 2026-09-05c §8: iOS sets
//    NSURLIsExcludedFromBackupKey; Android is a no-op (the manifest does it).
//
// Nothing that crosses this channel is logged by either half (CLAUDE.md
// rule 4).
import 'package:flutter/services.dart';

/// What the gate read answered ([KeystorePlatform.authenticate]).
enum PlatformBiometricAnswer {
  /// The current biometric set proved the person: the gate item was read.
  success,

  /// The sensor said no and the prompt ended (too many tries).
  failed,

  /// The person dismissed the prompt or chose *Use PIN instead*.
  cancelled,

  /// No usable biometric right now (none enrolled, locked out, no hardware).
  unavailable,

  /// The gate was invalidated by an enrolment change since it was minted —
  /// the MPIN, once, then a new gate (ADR 2026-10-06 §4).
  reenrolled,

  /// No gate item exists on this install (never minted, or removed).
  unarmed,
}

/// Which hardware holds the device-key class's wrapping key (Android).
enum DeviceKeyHardware {
  /// StrongBox (a separate secure element) — 04 §3.3 "when available".
  strongBox,

  /// The TEE (the phone has no StrongBox, or it refused the key).
  tee,

  /// Not known (no key yet, or the platform would not say).
  unknown,
}

/// The platform half of the device-key custody.
abstract interface class KeystorePlatform {
  /// Whether a biometric that can guard a hardware key is enrolled now.
  /// Never throws: anything the platform cannot answer is `false`, which puts
  /// the phone on the PIN-only path — the safe side.
  Future<bool> qualifyingBiometricEnrolled();

  /// Android device-key class: the bytes stored under [id], or null.
  /// Throws a [PlatformException] when the item exists but cannot be opened
  /// (never answered as absent: an absent device key means *recovery*).
  Future<Uint8List?> deviceItemRead(String id);

  /// Android device-key class: stores [bytes] under [id], durably, before
  /// answering.
  Future<void> deviceItemWrite(String id, Uint8List bytes);

  /// Android device-key class: removes [id] (the wrapping key stays).
  Future<void> deviceItemDelete(String id);

  /// Android device-key class: whether [id] is stored.
  Future<bool> deviceItemContains(String id);

  /// Android: which hardware holds the device-key class's wrapping key.
  /// Never throws.
  Future<DeviceKeyHardware> deviceKeyStorage();

  /// Keeps each existing file in [paths] out of the platform backup (iOS).
  Future<void> excludeFromBackup(List<String> paths);

  /// Reads the gate with the person's biometric — the platform's own prompt
  /// with the ARB copy given, never the device credential (07 §5.6). Never
  /// throws: a channel failure is [PlatformBiometricAnswer.unavailable],
  /// which leaves the PIN.
  Future<PlatformBiometricAnswer> authenticate({
    required String title,
    required String subtitle,
    required String cancel,
  });

  /// Mints a new gate bound to the biometric set enrolled now, replacing any
  /// old one. Prompts nothing. Never throws; `false` when the platform could
  /// not mint it (no qualifying biometric).
  Future<bool> armBiometricGate();

  /// Removes the gate — and only the gate. Never throws.
  Future<void> resetGate();
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
  Future<Uint8List?> deviceItemRead(String id) async {
    final v = await channel.invokeMethod<Uint8List>('deviceItemRead', {
      'id': id,
    });
    // The engine's codec answers an unmodifiable view, which the caller could
    // not zeroise (found on rf_min: the ledger's reopen threw UnsupportedError
    // in `zeroize`). A fresh copy goes up; the view is the boundary's cost, as
    // the plugin's base64 String is.
    return v == null ? null : Uint8List.fromList(v);
  }

  @override
  Future<void> deviceItemWrite(String id, Uint8List bytes) => channel
      .invokeMethod<Object?>('deviceItemWrite', {'id': id, 'bytes': bytes});

  @override
  Future<void> deviceItemDelete(String id) =>
      channel.invokeMethod<Object?>('deviceItemDelete', {'id': id});

  @override
  Future<bool> deviceItemContains(String id) async =>
      await channel.invokeMethod<bool>('deviceItemContains', {'id': id}) ??
      false;

  @override
  Future<DeviceKeyHardware> deviceKeyStorage() async {
    try {
      final a = await channel.invokeMethod<String>('deviceKeyStorage');
      return DeviceKeyHardware.values.firstWhere(
        (h) => h.name == a,
        orElse: () => DeviceKeyHardware.unknown,
      );
    } on PlatformException {
      return DeviceKeyHardware.unknown;
    } on MissingPluginException {
      return DeviceKeyHardware.unknown;
    }
  }

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

  @override
  Future<void> resetGate() async {
    try {
      await channel.invokeMethod<Object?>('resetGate');
    } on PlatformException {
      // Left for the next mint, which replaces it.
    } on MissingPluginException {
      // No native half (a host without the app's channel).
    }
  }
}
