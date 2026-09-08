// The production [KeyStore] (04 §3.3, 06 §3, ADR 2026-09-05d §4) over the
// platform keystore through `flutter_secure_storage`.
//
// What each platform can do — read before changing an option:
//
// iOS / macOS (Keychain)
//   • `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
//     (`KeychainAccessibility.first_unlock_this_device`): readable once the
//     phone has been unlocked since boot — the sync engine and the SQLCipher
//     open must work in the background — and **never migrated** to another
//     device: not in an encrypted iTunes/Finder backup restored elsewhere, not
//     via device-to-device transfer. `synchronizable: false` keeps every item
//     out of iCloud Keychain. (Platform key sync of the UMK — 04 §7.0 — is a
//     *separate*, deliberately synchronizable item owned by the recovery lane,
//     never this store.)
//   • Items survive uninstall → reinstall on the same phone, which is 04 §3.3's
//     "Keychain remnant" rung 0 and why the PinVault's counter survives a
//     reinstall on iOS (ADR 05d §5).
//   • **Biometric-set binding:** `AccessControlFlag.biometryCurrentSet` on the
//     device-key items makes them unreadable after any Face ID / Touch ID
//     enrolment change — the platform then reports `errSecItemNotFound` /
//     an interaction-not-allowed error, surfaced here as [KeyStoreInvalidated]
//     so the app falls back to the MPIN and re-creates the item (06 §4.4 🔒).
//     Applied to [KeyIds.deviceSigningKey] and [KeyIds.deviceAgreementKey]
//     only — the database key and the PIN vault must be readable without a
//     biometric prompt (the app opens the DB before any UI, and the PIN *is*
//     the fallback when biometrics are gone).
//   • Secure Enclave: the Enclave holds P-256 keys, not our Ed25519 seed, so
//     `useSecureEnclave` is off; the Keychain's own hardware-backed class key
//     protects the item at rest. Generating Ed25519 *inside* the Enclave is
//     not possible on iOS today — 04 §3.3's "⚠️ verify at build time" resolves
//     to: seed in Keychain, biometric-bound, this-device-only.
//
// Android (Keystore, API 28+)
//   • `AndroidOptions.biometric(...)`: the wrapping AES key lives in the
//     Android Keystore and is **StrongBox-backed where the device has one**
//     (the plugin requests StrongBox and falls back to the TEE). Data is
//     AES-GCM under that key; nothing is a plain SharedPreferences string.
//   • **Biometric-set binding:** `enforceBiometrics: true` +
//     `AndroidBiometricType.strongBiometricOnly` for the device-key items:
//     the Keystore key is created with `setUserAuthenticationRequired(true)`
//     and `setInvalidatedByBiometricEnrollment(true)`, so a new fingerprint or
//     face permanently invalidates it → `KeyPermanentlyInvalidatedException`
//     → [KeyStoreInvalidated] here → MPIN fallback and re-create.
//   • Keystore entries die with uninstall: a reinstall on the same Android is
//     a **new device** (04 §3.3) and the PIN vault starts over — ADR 05d §5's
//     "cannot be reset by clearing app data" holds on Android for *Clear data*
//     (the Keystore alias survives) but not for uninstall, which is the
//     platform's limit, stated here rather than hidden.
//   • `resetOnError: false`: the plugin's default silently wipes every item on
//     a decryption error; we never destroy key material on an error path
//     (ADR 2026-09-05b §2) — the failure surfaces and the recovery ladder
//     decides.
//
// Values cross the plugin boundary base64-encoded because the platform API is
// string-typed; the *Dart* API stays bytes (B-04-8 forbids `String` keys in
// the type system, and the encoding lives in exactly one place). Reads return
// a fresh buffer the caller zeroises; `delete` lets the platform overwrite.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/seams/key_store.dart';

/// The item exists but the platform refuses to open it because the biometric
/// set changed since it was written (ADR 2026-09-05d §4). Callers fall back to
/// the MPIN, then re-create the item.
final class KeyStoreInvalidated implements Exception {
  const KeyStoreInvalidated(this.id, this.cause);

  final String id;
  final Object cause;

  @override
  String toString() => 'KeyStoreInvalidated($id)';
}

/// Which items are bound to the current biometric set (the device keys), and
/// which must stay readable without a prompt.
bool isBiometricBound(String id) =>
    id == KeyIds.deviceSigningKey || id == KeyIds.deviceAgreementKey;

/// Keychain / Keystore-backed secrets. See the file comment for the platform
/// matrix.
final class KeychainKeyStore implements KeyStore {
  KeychainKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Key prefix so our items never collide with another plugin user's.
  static const _prefix = 'rukka.';

  /// iOS/macOS: after first unlock, this device only, never iCloud.
  static const appleBase = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    accountName: 'rukka_folio',
  );

  /// iOS/macOS device-key items: additionally bound to the current biometric
  /// set (ADR 2026-09-05d §4).
  static const appleBiometric = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    accountName: 'rukka_folio',
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  );

  /// Android: hardware-backed AES-GCM (StrongBox where available), no silent
  /// wipe on error.
  static const androidBase = AndroidOptions.biometric(
    resetOnError: false,
    storageNamespace: 'rukka_folio',
  );

  /// Android device-key items: strong biometrics required, invalidated by any
  /// enrolment change (ADR 2026-09-05d §4).
  static const androidBiometric = AndroidOptions.biometric(
    resetOnError: false,
    storageNamespace: 'rukka_folio',
    enforceBiometrics: true,
    biometricType: AndroidBiometricType.strongBiometricOnly,
  );

  static IOSOptions _apple(String id) =>
      isBiometricBound(id) ? appleBiometric : appleBase;
  static AndroidOptions _android(String id) =>
      isBiometricBound(id) ? androidBiometric : androidBase;

  @override
  Future<Uint8List?> read(String id) async {
    final String? v;
    try {
      v = await _storage.read(
        key: _prefix + id,
        iOptions: _apple(id),
        mOptions: _apple(id),
        aOptions: _android(id),
      );
    } on PlatformException catch (e) {
      if (_looksInvalidated(e)) throw KeyStoreInvalidated(id, e);
      rethrow;
    }
    if (v == null) return null;
    return base64Decode(v);
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    // base64Encode copies; the String cannot be zeroised — accepted as the
    // plugin boundary's cost (documented above), kept as short-lived as Dart
    // allows.
    await _storage.write(
      key: _prefix + id,
      value: base64Encode(bytes),
      iOptions: _apple(id),
      mOptions: _apple(id),
      aOptions: _android(id),
    );
  }

  @override
  Future<void> delete(String id) => _storage.delete(
    key: _prefix + id,
    iOptions: _apple(id),
    mOptions: _apple(id),
    aOptions: _android(id),
  );

  @override
  Future<bool> contains(String id) => _storage.containsKey(
    key: _prefix + id,
    iOptions: _apple(id),
    mOptions: _apple(id),
    aOptions: _android(id),
  );

  /// Platform error codes that mean "the biometric set changed" rather than
  /// "absent" or "broken": Android's `KeyPermanentlyInvalidatedException`
  /// and iOS `errSecInteractionNotAllowed` / `errSecAuthFailed` on a
  /// `biometryCurrentSet` item.
  static bool _looksInvalidated(PlatformException e) {
    final text = '${e.code} ${e.message ?? ''} ${e.details ?? ''}';
    return text.contains('KeyPermanentlyInvalidated') ||
        text.contains('-25308') || // errSecInteractionNotAllowed
        text.contains('-25293'); // errSecAuthFailed
  }
}
