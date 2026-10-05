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
//     enrolment change. The plugin answers an unreadable item's
//     `errSecItemNotFound` as `null` (flutter_secure_storage_darwin 0.4.0
//     FlutterSecureStorage.swift:466-467), which the ledger reports as
//     `DeviceKeysMissing`. iOS has no error code that *means* an enrolment
//     change: `errSecAuthFailed` (-25293) is a failed Face ID and
//     `errSecInteractionNotAllowed` (-25308) is "not now" (SecBase.h:271,
//     :286), so both rethrow as the plugin's PlatformException — a failed or
//     refused prompt, never [KeyStoreInvalidated] (KEY145B review finding 1:
//     treating them as an invalidation let a failed face at cold start end,
//     after the PIN, in the deletion of still-valid device keys). ⚠️ Not
//     verified on an iOS device: which answer an invalidated
//     `biometryCurrentSet` item gives is unchecked.
//     06 §4.4 🔒 then wants "fall back to the MPIN and re-create the item":
//     [dropInvalidatedAfterPin], with the material caveat under *Still open*.
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
// Android (Keystore, API 28+ — minSdk 28, 13 §10 decision 9)
//   Read flutter_secure_storage 11.2.0's Android source before touching these
//   two option sets; desk 145 (5 Oct 2026) is what guessing cost — the app
//   died at startup on its first Android run. Facts, with the source line:
//   • **One storage per namespace.** FlutterSecureStoragePlugin
//     .getOrCreateStorage keys a single FlutterSecureStorage instance by
//     `storageNamespace|keyPrefix`, and FlutterSecureStorage.initialize returns
//     early once initialised — so the *first* option set to touch a namespace
//     decides the config for the whole process, and the namespace also names
//     the algorithm markers (NamespacedConfigSource) and the Keystore alias
//     (FlutterSecureStorageConfig.getKeyAliasSuffix). The two item classes
//     therefore live in **two namespaces**: `rukka_folio` (promptless) and
//     `rukka_folio_device` (biometric-bound). A shared namespace silently
//     dropped the biometric binding (or imposed it on the DB key).
//   • **Promptless items** (database key, PIN vault, wrapped UMK, identity,
//     everything not a device key) use the default `AndroidOptions(...)`
//     constructor: AES-GCM data under an app key wrapped by an RSA-OAEP key in
//     the Android Keystore (TEE-backed; the plugin does not request StrongBox
//     for RSA), created *without* user authentication. They cannot use
//     `AndroidOptions.biometric(...)`: its Keystore AES key is generated with
//     `setUserAuthenticationRequired(true)` whenever the phone has a screen
//     lock, regardless of `enforceBiometrics`
//     (KeyCipherImplementationAES23.generateSymmetricKey), and
//     initializeStorageCipher then raises a BiometricPrompt — the DB could not
//     open before the UI and the PIN could not be the fallback.
//   • **Device-key items:** `AndroidOptions.biometric(enforceBiometrics: true,
//     biometricType: strongBiometricOnly)`: the Keystore AES key (StrongBox
//     where available, TEE otherwise) is created with
//     `setUserAuthenticationRequired(true)`,
//     `setUserAuthenticationParameters(0, BIOMETRIC_STRONG)` and
//     `setInvalidatedByBiometricEnrollment(true)`, so a new fingerprint or
//     face permanently invalidates it → `KeyPermanentlyInvalidatedException`
//     (an InvalidKeyException the plugin reports as a key mismatch with the
//     exception in the cause chain) → [KeyStoreInvalidated] here →
//     [dropInvalidatedAfterPin] after the MPIN (see *Still open*). The prompt is the
//     framework
//     `android.hardware.biometrics.BiometricPrompt` built from the application
//     context, which needs `USE_BIOMETRIC` in the manifest (refused at
//     AuthService.checkPermission otherwise) and no FlutterFragmentActivity.
//   • `migrateOnAlgorithmChange: false` on both: there is nothing to migrate
//     (no Android install existed before 5 Oct 2026), and the plugin's
//     migration path deletes the old Keystore key and rewrites the markers
//     *before* the BiometricPrompt that re-encrypts, so a cancelled prompt
//     destroys the items — key material destroyed on an error path, which
//     ADR 2026-09-05b §2 forbids. A real algorithm change must surface.
//   • **Fresh-install quirk:** StorageCipherFactory reads absent algorithm
//     markers as the RSA default, so the first-ever open of the biometric
//     namespace reports "Algorithm changed detected" — while the same
//     constructor writes the current markers. With migration off and no reset,
//     that first call fails touching nothing, and one retry opens cleanly;
//     [_onAndroidFirstOpen] retries exactly once. A mismatch that survives the
//     retry is real and is rethrown.
//   • Keystore entries die with uninstall: a reinstall on the same Android is
//     a **new device** (04 §3.3) and the PIN vault starts over. This holds only
//     because the manifest keeps the app out of Auto Backup *and* Android 12+
//     device-to-device transfer (`allowBackup="false"` plus
//     res/xml/data_extraction_rules.xml, 03 §6 🔒, ADR 2026-09-05c §8): a
//     restored copy of the plugin's SharedPreferences, without the Keystore
//     keys that wrapped them, fails at open (the plugin's README, "Failed to
//     unwrap key") — F1-05d-7 guards it. ADR 05d §5's
//     "cannot be reset by clearing app data" holds on Android for *Clear data*
//     (the Keystore alias survives) but not for uninstall, which is the
//     platform's limit, stated here rather than hidden.
//   • `resetOnError: false`: the plugin's default silently wipes every item on
//     a decryption error; we never destroy key material on an error path
//     (ADR 2026-09-05b §2) — the failure surfaces and the recovery ladder
//     decides.
//
// Three item classes, one binding record (ADR 2026-10-05b, 5 Oct 2026):
//   • **promptless** — `rukka_folio` / `appleBase`: the database key, the PIN
//     vault, the wrapped UMK, the identity, the binding record itself.
//   • **PIN-only device keys** — `rukka_folio_device_pin` / `applePinOnly`
//     (its own Keychain service): the device keys of a phone with no
//     qualifying biometric enrolled, or of any phone before its PIN exists
//     (ruling 4). Hardware-backed (Android: RSA-OAEP Keystore key, TEE),
//     this-device-only, **no user-authentication binding** — and never the
//     device credential (07 §5.6). The MPIN gates the app, not the item: it
//     is still never a key (06 §4.4 🔒).
//   • **biometric device keys** — `rukka_folio_device` / `appleBiometric`:
//     ADR 2026-09-05d §4 in full, once [upgradeAfterPin] has moved them.
//   [bindingItemId] (promptless) records which device-key class this phone is
//   in, so the lock screen knows (S15 PIN-only variant) and every device-key
//   read goes to the one class that holds the keys. Absent ⇒ an install from
//   before this ADR, whose keys can only be in the biometric class.
//
// Rulings 2 and 3 live here as [upgradeAfterPin] and
// [dropInvalidatedAfterPin]; both are called only after a *successful MPIN*
// (PinVault's `afterPinProven`), never on a biometric success alone.
//
// Still open (owner, not guessed — lane report M13-KEY145B):
//   ⚠️ SPEC: **ruling 3 cannot bring the key material back.** A biometric-bound
//     item the platform invalidated is unreadable for good (Android
//     KeyPermanentlyInvalidatedException; iOS biometryCurrentSet), and since
//     ruling 2 deletes the PIN-only copy there is no other copy. So "re-create
//     the item" re-creates the *class* (binding chosen by what is enrolled
//     now) but the device keys inside it must be minted again, which is a new
//     device for 04 §3.4 / 06 §5 (UMK re-wrap, re-certification): the recovery
//     ladder's job. Worse than the device keys alone: the local UMK copy is
//     wrapped *to* the lost X25519 key (local_ledger.dart `_firstRun`,
//     `wrapUmkToDevice` → [KeyIds.wrappedUmk]), so it cannot be opened
//     either, and no other copy exists on the phone — every item here is
//     `synchronizable: false`, and 04 §7.0's synchronizable UMK item is not
//     built. Only rungs 1–3 (own device, guardians, sheet) bring the books
//     back. KEY145's option (i) — a separate biometric *gate* item over
//     promptless device keys, the literal reading of ADR 05d §4's "the
//     keystore item guarding the device key" — would avoid the loss.
//   ⚠️ SPEC: **the MPIN cannot open a biometric-bound item** (auth per use;
//     06 §4.4 🔒 MPIN never a key). On a biometric phone *Use PIN instead*
//     admits the person but the device keys still need the biometric, so the
//     cold-start gate asks for it again after the PIN (features/lock
//     cold_start_gate.dart).

// Values cross the plugin boundary base64-encoded because the platform API is
// string-typed; the *Dart* API stays bytes (B-04-8 forbids `String` keys in
// the type system, and the encoding lives in exactly one place). Reads return
// a fresh buffer the caller zeroises; `delete` lets the platform overwrite.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/seams/key_store.dart';
import 'keystore_platform.dart';

/// The item exists but the platform refuses to open it because the biometric
/// set changed since it was written (ADR 2026-09-05d §4). The response is the
/// MPIN, then [KeychainKeyStore.dropInvalidatedAfterPin] (ADR 2026-10-05b §3).
final class KeyStoreInvalidated implements Exception {
  const KeyStoreInvalidated(this.id, this.cause);

  final String id;
  final Object cause;

  @override
  String toString() => 'KeyStoreInvalidated($id)';
}

/// The two device-key ids — the only items that may be biometric-bound.
/// (Name kept from desk 145: it answers "may this id be bound", not "is it
/// bound now" — that is [KeychainKeyStore.binding].)
bool isBiometricBound(String id) =>
    id == KeyIds.deviceSigningKey || id == KeyIds.deviceAgreementKey;

/// Which class holds this phone's device keys (ADR 2026-10-05b §1).
enum DeviceKeyBinding {
  /// Hardware keystore without a user-authentication binding; the app is
  /// gated by the MPIN alone and S15 shows no biometric button.
  pinOnly,

  /// Bound to the current biometric set (ADR 2026-09-05d §4).
  biometric;

  static DeviceKeyBinding? _decode(Uint8List? raw) =>
      switch (raw == null ? null : utf8.decode(raw, allowMalformed: true)) {
        'pin-only' => pinOnly,
        'biometric' => biometric,
        _ => null,
      };

  Uint8List _encode() => Uint8List.fromList(
    utf8.encode(this == pinOnly ? 'pin-only' : 'biometric'),
  );
}

/// What [KeychainKeyStore.upgradeAfterPin] did (ADR 2026-10-05b §2).
enum DeviceKeyUpgrade {
  /// Already biometric-bound (or nothing to decide yet).
  notNeeded,

  /// No qualifying biometric enrolled, or no device keys to move: still
  /// PIN-only.
  stayedPinOnly,

  /// Re-created under the biometric binding, read back equal, PIN-only items
  /// deleted.
  upgraded,

  /// Something failed part-way (a cancelled prompt, a write or read-back that
  /// failed or differed): the PIN-only items are untouched and still open.
  failedKeptPinOnly,
}

/// Keychain / Keystore-backed secrets. See the file comment for the platform
/// matrix and the three item classes.
final class KeychainKeyStore implements KeyStore {
  KeychainKeyStore({FlutterSecureStorage? storage, KeystorePlatform? platform})
    : _storage = storage ?? const FlutterSecureStorage(),
      _platform = platform ?? const MethodChannelKeystorePlatform();

  final FlutterSecureStorage _storage;
  final KeystorePlatform _platform;

  /// Key prefix so our items never collide with another plugin user's.
  static const _prefix = 'rukka.';

  /// The promptless record of [DeviceKeyBinding] (ADR 2026-10-05b §1).
  static const bindingItemId = 'rk.device.binding';

  static const _deviceIds = [
    KeyIds.deviceSigningKey,
    KeyIds.deviceAgreementKey,
  ];

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

  /// iOS/macOS PIN-only device-key items (ADR 2026-10-05b §1): this device
  /// only, no access control — and a Keychain service of their own, so an
  /// upgrade can hold both copies until the new one has read back.
  static const applePinOnly = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    accountName: 'rukka_folio_device_pin',
  );

  /// Android promptless items (DB key, PIN vault, …): AES-GCM under an
  /// RSA-OAEP Keystore key created without user authentication, no migration,
  /// no silent wipe. Its own namespace — see the file comment.
  static const androidBase = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    storageNamespace: 'rukka_folio',
  );

  /// Android device-key items: strong biometrics required, invalidated by any
  /// enrolment change (ADR 2026-09-05d §4), in a namespace of their own. The
  /// prompt copy is laid over it from ARB at call time ([setPromptCopy]).
  static const androidBiometric = AndroidOptions.biometric(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    storageNamespace: 'rukka_folio_device',
    enforceBiometrics: true,
    biometricType: AndroidBiometricType.strongBiometricOnly,
  );

  /// Android PIN-only device-key items (ADR 2026-10-05b §1): the promptless
  /// option set (RSA-OAEP-wrapped, Keystore/TEE, no user authentication) in a
  /// third namespace, so it never shares a plugin instance, config or alias
  /// with either other class (F1-05d-3).
  static const androidPinOnly = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    storageNamespace: 'rukka_folio_device_pin',
  );

  ({String title, String subtitle, String cancel})? _promptCopy;

  /// The ARB prompt copy set by [setPromptCopy], for the relock's own prompt
  /// (`KeystoreBiometricGate`); null until bootstrap sets it.
  ({String title, String subtitle, String cancel})? get promptCopy =>
      _promptCopy;

  /// The Android BiometricPrompt's title, subtitle and negative button, from
  /// ARB (01 §1.8). Without it the plugin shows its English defaults, whose
  /// subtitle offers "device credentials" (07 §5.6 forbids). The negative
  /// button is the way to the PIN.
  void setPromptCopy({
    required String title,
    required String subtitle,
    required String cancel,
  }) => _promptCopy = (title: title, subtitle: subtitle, cancel: cancel);

  /// Whether this process has opened the biometric namespace: once it has,
  /// the plugin holds that namespace's cipher in memory, and resetting the
  /// items under it would leave a copy only this process can read.
  bool _biometricTouched = false;

  AndroidOptions _androidBiometric() {
    final copy = _promptCopy;
    if (copy == null) return androidBiometric;
    return androidBiometric.copyWith(
      biometricPromptTitle: copy.title,
      biometricPromptSubtitle: copy.subtitle,
      biometricPromptNegativeButton: copy.cancel,
    );
  }

  (IOSOptions, AndroidOptions) _class(String id, DeviceKeyBinding? device) {
    if (!isBiometricBound(id)) return (appleBase, androidBase);
    return switch (device) {
      DeviceKeyBinding.pinOnly => (applePinOnly, androidPinOnly),
      _ => (appleBiometric, _androidBiometric()),
    };
  }

  // ── the binding record ────────────────────────────────────────────────────

  /// Which class holds the device keys; null before any were written.
  Future<DeviceKeyBinding?> binding() async =>
      DeviceKeyBinding._decode(await _rawRead(bindingItemId, null));

  Future<void> _setBinding(DeviceKeyBinding b) =>
      _rawWrite(bindingItemId, b._encode(), null);

  /// The class a device-key *read* goes to: the recorded one, or — with no
  /// record — the biometric class, the only one an install from before ADR
  /// 2026-10-05b can have written.
  Future<DeviceKeyBinding> _readBinding() async =>
      await binding() ?? DeviceKeyBinding.biometric;

  // ── KeyStore ──────────────────────────────────────────────────────────────

  @override
  Future<Uint8List?> read(String id) async {
    if (!isBiometricBound(id)) return _rawRead(id, null);
    return _rawRead(id, await _readBinding());
  }

  /// A device-key write with no binding recorded starts the phone **PIN-only**
  /// (ADR 2026-10-05b §4): before the MPIN exists no item that needs the
  /// person may exist, and [upgradeAfterPin] moves the keys once the PIN is
  /// set. The record is written first, so a write that dies half-way is never
  /// looked for in the wrong class.
  @override
  Future<void> write(String id, Uint8List bytes) async {
    if (!isBiometricBound(id)) return _rawWrite(id, bytes, null);
    var b = await binding();
    if (b == null) {
      b = DeviceKeyBinding.pinOnly;
      await _setBinding(b);
    }
    await _rawWrite(id, bytes, b);
  }

  @override
  Future<void> delete(String id) async {
    if (!isBiometricBound(id)) return _rawDelete(id, null);
    await _rawDelete(id, await _readBinding());
  }

  @override
  Future<bool> contains(String id) async {
    if (!isBiometricBound(id)) return _rawContains(id, null);
    return _rawContains(id, await _readBinding());
  }

  // ── ruling 2: the upgrade, behind the PIN ────────────────────────────────

  /// ADR 2026-10-05b §2 🔒 — called after a **successful MPIN** (set at O4b,
  /// or accepted at S15) and never after a biometric success alone. On a
  /// PIN-only phone that now has a qualifying biometric: re-creates both
  /// device-key items under the biometric binding, reads each back and
  /// compares, and only then records the new binding and deletes the PIN-only
  /// items. Anything that fails before the record flips leaves the PIN-only
  /// items exactly as they were ([DeviceKeyUpgrade.failedKeptPinOnly]); a
  /// delete that fails after it is swept the next time.
  Future<DeviceKeyUpgrade> upgradeAfterPin() =>
      _upgrading ??= _upgrade().whenComplete(() => _upgrading = null);

  /// One upgrade at a time: a second PIN while a sheet is still up (or never
  /// answered — see PinVault) does not raise a second one.
  Future<DeviceKeyUpgrade>? _upgrading;

  Future<DeviceKeyUpgrade> _upgrade() async {
    final b = await binding();
    if (b == DeviceKeyBinding.biometric) {
      await _sweepPinOnly();
      return DeviceKeyUpgrade.notNeeded;
    }
    if (b == null) return DeviceKeyUpgrade.notNeeded;
    if (!await _platform.qualifyingBiometricEnrolled()) {
      return DeviceKeyUpgrade.stayedPinOnly;
    }
    final held = <String, Uint8List>{};
    try {
      for (final id in _deviceIds) {
        final v = await _rawRead(id, DeviceKeyBinding.pinOnly);
        if (v == null) return DeviceKeyUpgrade.stayedPinOnly;
        held[id] = v;
      }
      try {
        await _clearBiometricClass();
        for (final id in _deviceIds) {
          await _rawWrite(id, held[id]!, DeviceKeyBinding.biometric);
        }
        for (final id in _deviceIds) {
          final back = await _rawRead(id, DeviceKeyBinding.biometric);
          final same = back != null && _equal(back, held[id]!);
          if (back != null) zeroise(back);
          if (!same) return DeviceKeyUpgrade.failedKeptPinOnly;
        }
      } on Object {
        return DeviceKeyUpgrade.failedKeptPinOnly;
      }
    } finally {
      for (final v in held.values) {
        zeroise(v);
      }
    }
    await _setBinding(DeviceKeyBinding.biometric);
    await _sweepPinOnly();
    return DeviceKeyUpgrade.upgraded;
  }

  // ── ruling 3: invalidated, behind the PIN ────────────────────────────────

  /// ADR 2026-10-05b §3 🔒 — called after a **successful MPIN** when the
  /// biometric-bound items were found unreadable ([KeyStoreInvalidated]).
  /// Removes them (Android through the app's own channel, which the plugin
  /// cannot do with `resetOnError: false`; iOS through the plugin's delete)
  /// and records the class the next device keys go into: biometric if a
  /// qualifying biometric is enrolled now, PIN-only if none is.
  ///
  /// ⚠️ SPEC: the key material itself is gone (file comment, *Still open*);
  /// the next device keys are minted by the recovery ladder, not here.
  Future<DeviceKeyBinding> dropInvalidatedAfterPin() async {
    await _clearBiometricClass(force: true);
    final next = await _platform.qualifyingBiometricEnrolled()
        ? DeviceKeyBinding.biometric
        : DeviceKeyBinding.pinOnly;
    await _setBinding(next);
    return next;
  }

  Future<void> _clearBiometricClass({bool force = false}) async {
    if (_biometricTouched && !force) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _platform.resetBiometricDeviceItems();
    } else {
      for (final id in _deviceIds) {
        await _rawDelete(id, DeviceKeyBinding.biometric);
      }
    }
  }

  Future<void> _sweepPinOnly() async {
    try {
      for (final id in _deviceIds) {
        if (await _rawContains(id, DeviceKeyBinding.pinOnly)) {
          await _rawDelete(id, DeviceKeyBinding.pinOnly);
        }
      }
    } on Object {
      // Left for the next sweep; the binding already points at the
      // biometric copy, which read back.
    }
  }

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  // ── the plugin boundary ───────────────────────────────────────────────────

  /// [device] picks the class for a device-key id; ignored for the rest.
  Future<Uint8List?> _rawRead(String id, DeviceKeyBinding? device) async {
    final (apple, android) = _class(id, device);
    final String? v;
    try {
      v = await _onAndroidFirstOpen(
        () => _storage.read(
          key: _prefix + id,
          iOptions: apple,
          mOptions: apple,
          aOptions: android,
        ),
      );
    } on PlatformException catch (e) {
      if (_looksInvalidated(e)) throw KeyStoreInvalidated(id, e);
      rethrow;
    }
    _touched(id, device);
    if (v == null) return null;
    return base64Decode(v);
  }

  Future<void> _rawWrite(
    String id,
    Uint8List bytes,
    DeviceKeyBinding? device,
  ) async {
    final (apple, android) = _class(id, device);
    // base64Encode copies; the String cannot be zeroised — accepted as the
    // plugin boundary's cost (documented above), kept as short-lived as Dart
    // allows.
    await _onAndroidFirstOpen(
      () => _storage.write(
        key: _prefix + id,
        value: base64Encode(bytes),
        iOptions: apple,
        mOptions: apple,
        aOptions: android,
      ),
    );
    _touched(id, device);
  }

  Future<void> _rawDelete(String id, DeviceKeyBinding? device) {
    final (apple, android) = _class(id, device);
    return _onAndroidFirstOpen(
      () => _storage.delete(
        key: _prefix + id,
        iOptions: apple,
        mOptions: apple,
        aOptions: android,
      ),
    );
  }

  Future<bool> _rawContains(String id, DeviceKeyBinding? device) {
    final (apple, android) = _class(id, device);
    return _onAndroidFirstOpen(
      () => _storage.containsKey(
        key: _prefix + id,
        iOptions: apple,
        mOptions: apple,
        aOptions: android,
      ),
    );
  }

  void _touched(String id, DeviceKeyBinding? device) {
    if (isBiometricBound(id) && device == DeviceKeyBinding.biometric) {
      _biometricTouched = true;
    }
  }

  /// Test seam: whether this process has opened the biometric namespace.
  @visibleForTesting
  bool get biometricNamespaceOpened => _biometricTouched;

  /// Runs [op], retrying it exactly once when the plugin reports its
  /// fresh-install "Algorithm changed detected" mismatch (file comment,
  /// *Fresh-install quirk*). The failed first call touched nothing (no
  /// migration, no reset) and left the current markers written, so the retry
  /// opens the namespace normally; a second mismatch is real and rethrown.
  /// Only that message is retried — an invalidation or any other error is
  /// never repeated. The message is Android's alone, so iOS never retries.
  static Future<T> _onAndroidFirstOpen<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PlatformException catch (e) {
      if (!(e.message ?? '').contains(_freshMarkerMismatch) ||
          _looksInvalidated(e)) {
        rethrow;
      }
      return op();
    }
  }

  /// FlutterSecureStorage.initializeStorageCipher's log/error text for a
  /// saved-vs-current algorithm marker mismatch (11.2.0).
  static const _freshMarkerMismatch = 'Algorithm changed detected';

  /// The one platform error that *means* "the biometric set changed":
  /// Android's `KeyPermanentlyInvalidatedException`. Nothing on iOS does —
  /// `errSecAuthFailed` (-25293) is a failed Face ID and
  /// `errSecInteractionNotAllowed` (-25308) a prompt not allowed right now
  /// (SecBase.h:271, :286); both rethrow as they came, because ruling 3
  /// deletes what this classifies, and a failed face must never cost the
  /// device keys (file comment, *Biometric-set binding*).
  static bool _looksInvalidated(PlatformException e) {
    final text = '${e.code} ${e.message ?? ''} ${e.details ?? ''}';
    return text.contains('KeyPermanentlyInvalidated');
  }
}
