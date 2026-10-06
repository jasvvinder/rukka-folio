// The production [KeyStore] (04 §3.3, 06 §3) over the platform keystore, as
// ADR 2026-10-06 🔒 lays it out: **the fingerprint guards a gate key, never the
// device keys.** Read before changing an option.
//
// ── Item classes ────────────────────────────────────────────────────────────
//   • **promptless** — the database key, the PIN vault, the identity, the
//     settings, the class record, the gate record: everything that must open
//     before any UI (the DB opens before S15 can draw) and needs no person.
//     iOS: Keychain service `rukka_folio`, `first_unlock_this_device`, never
//     iCloud. Android: flutter_secure_storage namespace `rukka_folio`, AES-GCM
//     data under an app key wrapped by an RSA-OAEP Keystore key (TEE), created
//     without user authentication.
//   • **device keys** (ADR 2026-10-06 §1 🔒) — [deviceItems]: the device
//     signing seed (Ed25519), the device agreement seed (X25519) and the
//     locally wrapped UMK. Hardware-backed, **no user-authentication binding,
//     no enrolment invalidation**, this device only, minted straight into this
//     class and never moved:
//       Android: the app's own helper (`RukkaKeystoreChannel.kt`
//         `deviceItem*`): AES-256-GCM under a Keystore key that is
//         StrongBox-backed when the phone has StrongBox
//         (`FEATURE_STRONGBOX_KEYSTORE`, `setIsStrongBoxBacked(true)`), TEE
//         otherwise, with no `setUserAuthenticationRequired` and no
//         `setInvalidatedByBiometricEnrollment`. Not through the plugin: in
//         flutter_secure_storage 11.2.0 the only AES key cipher sets
//         `setUserAuthenticationRequired(true)` whenever the phone has a
//         screen lock (KeyCipherImplementationAES23.java:166-186), and the
//         RSA-OAEP key cipher never asks for StrongBox
//         (KeyCipherImplementationRSAOAEP.java:145-155) — so neither meets
//         04 §3.3's "StrongBox when available" without a person bound to it.
//       iOS: Keychain service `rukka_folio_device_keys` through the plugin,
//         `first_unlock_this_device`, `synchronizable: false`, **no access
//         control**. The Secure Enclave holds P-256 keys, not our Ed25519 /
//         X25519 seeds; the Keychain's hardware-backed class key protects the
//         item. ⚠️ Not run on an iOS device (ADR 2026-10-06 *Open*).
//   • **the gate** (ADR 2026-10-06 §2 🔒) — native only ([KeystorePlatform]
//     `armBiometricGate` / `authenticate` / `resetGate`): a random secret in
//     its own item, bound to the current biometric set (Android
//     BIOMETRIC_STRONG per use + invalidated by enrolment; iOS
//     `biometryCurrentSet`). Reading it with the biometric *is* the unlock; it
//     opens no data. [gateItemId] (promptless) records that one was minted,
//     so a gate the platform has since dropped reads as *invalidated*, never
//     as *never had one*.
//
// ── Ruling 3: sealed until the gate or the MPIN ─────────────────────────────
// A store starts **sealed**: every read, write, delete or contains of a
// [deviceItems] id throws [DeviceKeysSealed] until one of
//   • [openWithGate] read the gate with the person's biometric;
//   • [unsealAfterPin] — the PIN vault's `onPinProven`, run only on a
//     verified MPIN (or a PIN set at O4b);
//   • [unsealIfNoPin] — no MPIN exists yet (first run, onboarding before O4b):
//     there is nothing to verify and no lock exists (07 §5.6), so a sealed
//     store would be a dead end (07 §1 rule 6). ⚠️ SPEC: ADR 2026-10-06 §3
//     names only the gate and the MPIN; this third door is the conservative
//     reading for the state in which neither can exist.
// A sealed read **throws** rather than answering null: a null device key means
// "mint new ones" to the auth client (http_auth_client.dart `_deviceKeys`),
// which would replace this phone's identity.
//
// ── Ruling 4: an enrolment change costs only the gate ───────────────────────
// [afterPinProven] (after every verified MPIN) mints a new gate for the set
// enrolled now, or removes it when no qualifying biometric is left (PIN-only,
// ADR 2026-10-05b §3). Nothing here ever deletes a device-key item on an
// error path, and nothing native resets the device-key class.
//
// ── Ruling 5: the legacy classes move once, behind an unlock ────────────────
// Installs from before this ADR hold the device seeds in one of two plugin
// namespaces — `rukka_folio_device` (biometric-bound, ADR 2026-09-05d §4 as
// built) or `rukka_folio_device_pin` (PIN-only, ADR 2026-10-05b §1) — and the
// wrapped UMK in the promptless namespace. [migrateAfterUnlock] reads them,
// writes them to the ruling-1 class, reads back and compares, flips
// [classItemId], mints the gate, and only then deletes the old items. Any
// failure before the flip leaves the old items and the old record as they
// were, so some copy always opens.
//
// ── Plugin facts kept from desk 145 (flutter_secure_storage 11.2.0) ─────────
//   • One storage per namespace (the first option set to touch a namespace
//     decides it for the process): every class has its own namespace.
//   • `resetOnError: false` everywhere: the plugin's default wipes every item
//     on a decryption error; key material is never destroyed on an error path
//     (ADR 2026-09-05b §2).
//   • `migrateOnAlgorithmChange: false`: the plugin's migration deletes the old
//     Keystore key before the prompt that re-encrypts.
//   • Fresh-install quirk: the first open of a namespace may report "Algorithm
//     changed detected"; [_onAndroidFirstOpen] retries exactly once.
//   • A reinstall on the same Android is a new device (04 §3.3): the manifest
//     keeps the app out of Auto Backup and device transfer (F1-05d-7).
//
// Values cross the plugin boundary base64-encoded because its API is
// string-typed; the app's own channel carries bytes. Reads return a fresh
// buffer the caller zeroises. Nothing here logs (CLAUDE.md rule 4).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/seams/key_store.dart';
import 'keystore_platform.dart';
import 'pin_vault.dart' show PinVault;

/// A legacy biometric-bound device-key item (ADR 2026-09-05d §4 as built
/// before ADR 2026-10-06) that the platform refuses because the biometric set
/// changed. The key material is gone; nothing is deleted (ruling 4), and the
/// books need the recovery ladder.
final class KeyStoreInvalidated implements Exception {
  const KeyStoreInvalidated(this.id, this.cause);

  final String id;
  final Object cause;

  @override
  String toString() => 'KeyStoreInvalidated($id)';
}

/// ADR 2026-10-06 §3 🔒: a device-key item was asked for before the gate or
/// the MPIN opened the store. Carries the id only — never material.
final class DeviceKeysSealed implements Exception {
  const DeviceKeysSealed(this.id);

  final String id;

  @override
  String toString() => 'DeviceKeysSealed($id)';
}

/// The three ids of the device-key class (ADR 2026-10-06 §1).
bool isDeviceKeyItem(String id) =>
    id == KeyIds.deviceSigningKey ||
    id == KeyIds.deviceAgreementKey ||
    id == KeyIds.wrappedUmk;

/// The two ids a legacy class held in its own namespace (the wrapped UMK sat
/// in the promptless one).
bool _legacySeed(String id) =>
    id == KeyIds.deviceSigningKey || id == KeyIds.deviceAgreementKey;

/// Where this phone's device keys are ([KeychainKeyStore.classItemId]).
enum DeviceKeyClass {
  /// ADR 2026-10-06 §1: hardware-backed, no user-authentication binding.
  hardware,

  /// ADR 2026-10-05b §1's PIN-only plugin class — migrated at the next
  /// unlock (ruling 5).
  legacyPinOnly,

  /// ADR 2026-09-05d §4's biometric-bound plugin class, as built before ADR
  /// 2026-10-06 — migrated at the next unlock while it still opens (ruling 5).
  legacyBiometric;

  static DeviceKeyClass? _decode(Uint8List? raw) =>
      switch (raw == null ? null : utf8.decode(raw, allowMalformed: true)) {
        'hardware' => hardware,
        'pin-only' => legacyPinOnly,
        'biometric' => legacyBiometric,
        _ => null,
      };

  Uint8List _encode() => Uint8List.fromList(
    utf8.encode(switch (this) {
      hardware => 'hardware',
      legacyPinOnly => 'pin-only',
      legacyBiometric => 'biometric',
    }),
  );
}

/// What [KeychainKeyStore.migrateAfterUnlock] did (ADR 2026-10-06 §5).
enum DeviceKeyMigration {
  /// Already in the ruling-1 class.
  notNeeded,

  /// Moved, read back equal, record flipped, old items removed.
  migrated,

  /// Not attempted now (the store is sealed, or the legacy biometric class
  /// has not been opened in this process and reading it would prompt).
  deferred,

  /// Something failed before the record flipped: the old items and record are
  /// exactly as they were, and still open.
  failedKeptOld,
}

/// What [KeychainKeyStore.afterPinProven] left behind (ADR 2026-10-06 §2, §4).
enum GateMint {
  /// A new gate bound to the biometric set enrolled now.
  minted,

  /// No qualifying biometric: no gate — PIN-only (ADR 2026-10-05b §3).
  none,

  /// The device keys are still in a legacy class; the migration mints it.
  awaitingMigration,
}

/// Keychain / Keystore-backed secrets. See the file comment.
final class KeychainKeyStore implements KeyStore {
  KeychainKeyStore({
    FlutterSecureStorage? storage,
    KeystorePlatform? platform,
    bool sealed = true,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _platform = platform ?? const MethodChannelKeystorePlatform(),
       // ignore: prefer_initializing_formals — a named parameter cannot be private
       _sealed = sealed;

  final FlutterSecureStorage _storage;
  final KeystorePlatform _platform;

  /// Key prefix so our items never collide with another plugin user's.
  static const _prefix = 'rukka.';

  /// The promptless record of [DeviceKeyClass].
  static const classItemId = 'rk.device.binding';

  /// The promptless record that a gate was minted (value `armed`).
  static const gateItemId = 'rk.device.gate';

  /// The promptless marker of a legacy class whose copies a finished
  /// migration has still to delete (ruling 5).
  static const sweepItemId = 'rk.device.sweep';

  /// The device-key class's ids (ADR 2026-10-06 §1).
  static const deviceItems = [
    KeyIds.deviceSigningKey,
    KeyIds.deviceAgreementKey,
    KeyIds.wrappedUmk,
  ];

  static const _seedIds = [KeyIds.deviceSigningKey, KeyIds.deviceAgreementKey];

  // ── option sets ───────────────────────────────────────────────────────────

  /// iOS/macOS promptless: after first unlock, this device only, never iCloud.
  static const appleBase = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    accountName: 'rukka_folio',
  );

  /// iOS/macOS device-key class (ADR 2026-10-06 §1): this device only, never
  /// iCloud, **no access control**, a Keychain service of its own.
  static const appleDeviceKeys = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    accountName: 'rukka_folio_device_keys',
  );

  /// iOS/macOS legacy biometric-bound seeds (read and removed by the
  /// migration only).
  static const appleLegacyBiometric = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    accountName: 'rukka_folio',
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  );

  /// iOS/macOS legacy PIN-only seeds (read and removed by the migration only).
  static const appleLegacyPinOnly = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    accountName: 'rukka_folio_device_pin',
  );

  /// Android promptless items: RSA-OAEP-wrapped Keystore key, no user
  /// authentication, no migration, no silent wipe.
  static const androidBase = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    storageNamespace: 'rukka_folio',
  );

  /// Android legacy biometric-bound seeds (read and removed by the migration
  /// only). The prompt copy is laid over it from ARB ([setPromptCopy]).
  static const androidLegacyBiometric = AndroidOptions.biometric(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    storageNamespace: 'rukka_folio_device',
    enforceBiometrics: true,
    biometricType: AndroidBiometricType.strongBiometricOnly,
  );

  /// Android legacy PIN-only seeds (read and removed by the migration only).
  static const androidLegacyPinOnly = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    storageNamespace: 'rukka_folio_device_pin',
  );

  // ── prompt copy ───────────────────────────────────────────────────────────

  ({String title, String subtitle, String cancel})? _promptCopy;

  /// The ARB prompt copy set by [setPromptCopy]; null until bootstrap sets it.
  ({String title, String subtitle, String cancel})? get promptCopy =>
      _promptCopy;

  /// The biometric prompt's title, subtitle and negative button, from ARB
  /// (01 §1.8). The negative button is the way to the PIN; the device
  /// credential is never offered (07 §5.6).
  void setPromptCopy({
    required String title,
    required String subtitle,
    required String cancel,
  }) => _promptCopy = (title: title, subtitle: subtitle, cancel: cancel);

  AndroidOptions _androidLegacyBiometric() {
    final copy = _promptCopy;
    if (copy == null) return androidLegacyBiometric;
    return androidLegacyBiometric.copyWith(
      biometricPromptTitle: copy.title,
      biometricPromptSubtitle: copy.subtitle,
      biometricPromptNegativeButton: copy.cancel,
    );
  }

  // ── ruling 3: the seal ────────────────────────────────────────────────────

  bool _sealed;

  /// Whether device-key items are still closed (ruling 3).
  bool get sealed => _sealed;

  /// Closes the device-key items again — ruling 3's relock: S15 calls it
  /// (through [KeystoreBiometricGate.sealBehindLock]) the moment it covers the
  /// app after the background timeout, so nothing reads the device keys —
  /// the auth client's token refresh, a record signature — until the gate or
  /// the MPIN opens them again.
  void seal() => _sealed = true;

  /// Called each time the store goes from sealed to open (the gate, the MPIN,
  /// a legacy class's own prompt). Bootstrap hangs the sync nudge here: a
  /// resume behind S15 does not sync (ruling 3), so the unlock is the
  /// foreground return 05 §7 pulls on.
  void Function()? onReopened;

  void _open() {
    final was = _sealed;
    _sealed = false;
    if (was) onReopened?.call();
  }

  /// Ruling 3: the MPIN was verified (or set at O4b). Wired only to
  /// [PinVault.onPinProven], which runs on nothing else.
  void unsealAfterPin() => _open();

  /// Opens the store when **no MPIN exists** (first run, onboarding before
  /// O4b) — nothing to verify, no lock yet (file comment, ⚠️ SPEC). Answers
  /// whether it opened; with a PIN set it stays sealed.
  Future<bool> unsealIfNoPin() async {
    if (await _rawContains(PinVault.itemId)) return false;
    _open();
    return true;
  }

  void _guard(String id, DeviceKeyClass cls) {
    if (!_sealed) return;
    // A legacy biometric-bound seed is opened by the platform's own per-use
    // biometric: the read *is* the proof (and on success unseals). Every
    // other device-key item waits.
    if (cls == DeviceKeyClass.legacyBiometric && _legacySeed(id)) return;
    throw DeviceKeysSealed(id);
  }

  // ── the records ───────────────────────────────────────────────────────────

  /// The recorded class; null before any device key was written.
  Future<DeviceKeyClass?> recordedClass() async =>
      DeviceKeyClass._decode(await _rawRead(classItemId));

  /// The class a device-key operation goes to: the recorded one, or — with no
  /// record — the biometric class, the only one an install from before ADR
  /// 2026-10-05b can have written.
  Future<DeviceKeyClass> deviceKeyClass() async =>
      await recordedClass() ?? DeviceKeyClass.legacyBiometric;

  Future<void> _setClass(DeviceKeyClass c) =>
      _rawWrite(classItemId, c._encode());

  /// Whether a gate was minted (and not removed) on this install.
  Future<bool> gateArmed() async {
    final raw = await _rawRead(gateItemId);
    return raw != null && utf8.decode(raw, allowMalformed: true) == 'armed';
  }

  /// Android: which hardware holds the device-key class's key.
  Future<DeviceKeyHardware> deviceKeyHardware() =>
      defaultTargetPlatform == TargetPlatform.android
      ? _platform.deviceKeyStorage()
      : Future.value(DeviceKeyHardware.unknown);

  // ── KeyStore ──────────────────────────────────────────────────────────────

  @override
  Future<Uint8List?> read(String id) async {
    if (!isDeviceKeyItem(id)) return _rawRead(id);
    final cls = await deviceKeyClass();
    _guard(id, cls);
    final v = await _classRead(id, cls);
    if (v != null && cls == DeviceKeyClass.legacyBiometric && _legacySeed(id)) {
      // The platform demanded the person's biometric for this read.
      _legacyOpened = true;
      _open();
    }
    return v;
  }

  /// A device-key write with no class recorded starts the phone in the
  /// ruling-1 class: the record first, so a write that dies half-way is never
  /// looked for in the wrong class.
  @override
  Future<void> write(String id, Uint8List bytes) async {
    if (!isDeviceKeyItem(id)) return _rawWrite(id, bytes);
    // Strict: no write while sealed, whatever the class.
    if (_sealed) throw DeviceKeysSealed(id);
    var cls = await recordedClass();
    if (cls == null) {
      cls = DeviceKeyClass.hardware;
      await _setClass(cls);
    }
    await _classWrite(id, bytes, cls);
  }

  @override
  Future<void> delete(String id) async {
    if (!isDeviceKeyItem(id)) return _rawDelete(id);
    final cls = await deviceKeyClass();
    if (_sealed) throw DeviceKeysSealed(id);
    await _classDelete(id, cls);
  }

  @override
  Future<bool> contains(String id) async {
    if (!isDeviceKeyItem(id)) return _rawContains(id);
    final cls = await deviceKeyClass();
    if (_sealed) throw DeviceKeysSealed(id);
    return _classContains(id, cls);
  }

  // ── ruling 2: the gate ────────────────────────────────────────────────────

  /// Reads the gate with the person's biometric (ruling 2) — the cold-start
  /// and relock unlock. On success the store opens (ruling 3). A gate the
  /// record says was minted but the platform no longer has answers
  /// [PlatformBiometricAnswer.reenrolled]; no record answers
  /// [PlatformBiometricAnswer.unarmed] without prompting.
  Future<PlatformBiometricAnswer> openWithGate({String? title}) async {
    if (!await gateArmed()) return PlatformBiometricAnswer.unarmed;
    final copy = _promptCopy;
    // Bootstrap sets the ARB copy before any S15 exists; without it the
    // platform would show words that are not in ARB (01 §1.8).
    if (copy == null) return PlatformBiometricAnswer.unavailable;
    final answer = await _platform.authenticate(
      title: title ?? copy.title,
      subtitle: copy.subtitle,
      cancel: copy.cancel,
    );
    switch (answer) {
      case PlatformBiometricAnswer.success:
        _open();
        return answer;
      case PlatformBiometricAnswer.unarmed:
        // The record says minted; the platform dropped it (some Androids
        // delete an invalidated key, iOS answers an invalidated item as
        // absent). The MPIN, once, then a new gate (ruling 4).
        return PlatformBiometricAnswer.reenrolled;
      default:
        return answer;
    }
  }

  /// Ruling 2 / 4 🔒 — after every **verified MPIN** (PinVault
  /// `afterPinProven`: a PIN set at O4b, or accepted at S15), never on a
  /// biometric alone: mints a new gate bound to the biometric set enrolled
  /// now, or removes the gate when no qualifying biometric is left. On an
  /// install still in a legacy class the migration mints it instead (ruling 5
  /// order: copy, compare, then the gate). Device keys are never touched.
  Future<GateMint> afterPinProven() => _exclusive(() async {
    if (await recordedClass() != DeviceKeyClass.hardware) {
      return GateMint.awaitingMigration;
    }
    return _mintGate();
  });

  Future<GateMint> _mintGate() async {
    if (await _platform.qualifyingBiometricEnrolled() &&
        await _platform.armBiometricGate()) {
      await _rawWrite(gateItemId, Uint8List.fromList(utf8.encode('armed')));
      return GateMint.minted;
    }
    // PIN-only now: the record goes first, so a half-done removal reads as
    // "no gate" (S15 PIN-only variant), never as a gate to prompt for.
    await _rawDelete(gateItemId);
    await _platform.resetGate();
    return GateMint.none;
  }

  // ── ruling 5: the one-time move ───────────────────────────────────────────

  /// ADR 2026-10-06 §5 🔒 — after a successful unlock: moves an install whose
  /// device keys sit in a legacy class into the ruling-1 class. Read → write →
  /// read back and compare → flip the record → mint the gate (only once an
  /// MPIN exists — ruling 2: after O4b) → delete the old items. Anything that
  /// fails before the flip leaves the old items and record untouched
  /// ([DeviceKeyMigration.failedKeptOld]); a delete that fails after it is
  /// swept at the next unlock.
  Future<DeviceKeyMigration> migrateAfterUnlock() => _exclusive(_migrate);

  /// Whether this process has read the legacy biometric namespace (its cipher
  /// is then cached and a second read prompts nothing on Android).
  bool _legacyOpened = false;

  Future<DeviceKeyMigration> _migrate() async {
    if (_sealed) return DeviceKeyMigration.deferred;
    final from = await deviceKeyClass();
    if (from == DeviceKeyClass.hardware) {
      // A sweep a previous launch could not finish (and only then: the
      // legacy namespaces are not opened on an install that never had them).
      final pending = DeviceKeyClass._decode(await _rawRead(sweepItemId));
      if (pending != null) await _sweep(pending);
      return DeviceKeyMigration.notNeeded;
    }
    if (from == DeviceKeyClass.legacyBiometric && !_legacyOpened) {
      return DeviceKeyMigration.deferred;
    }
    final held = <String, Uint8List>{};
    try {
      try {
        for (final id in deviceItems) {
          final v = await _classRead(id, from);
          if (v == null) return DeviceKeyMigration.failedKeptOld;
          held[id] = v;
        }
        for (final id in deviceItems) {
          await _classWrite(id, held[id]!, DeviceKeyClass.hardware);
        }
        for (final id in deviceItems) {
          final back = await _classRead(id, DeviceKeyClass.hardware);
          final same = back != null && _equal(back, held[id]!);
          if (back != null) zeroise(back);
          if (!same) {
            await _dropPartialCopy();
            return DeviceKeyMigration.failedKeptOld;
          }
        }
        // Marked before the flip, so old copies left by a death between the
        // flip and the deletes are swept at the next unlock.
        await _rawWrite(sweepItemId, from._encode());
        await _setClass(DeviceKeyClass.hardware);
      } on Object {
        await _dropPartialCopy();
        return DeviceKeyMigration.failedKeptOld;
      }
    } finally {
      for (final v in held.values) {
        zeroise(v);
      }
    }
    // The record now points at the copy that read back equal.
    try {
      if (await _rawContains(PinVault.itemId)) await _mintGate();
    } on Object {
      // No gate yet: S15 shows the PIN, and the next PIN mints it.
    }
    await _sweep(from);
    return DeviceKeyMigration.migrated;
  }

  /// A copy that did not read back equal is removed from the ruling-1 class
  /// (the record still points at the legacy one, so nothing reads it).
  Future<void> _dropPartialCopy() async {
    for (final id in deviceItems) {
      try {
        await _classDelete(id, DeviceKeyClass.hardware);
      } on Object {
        // Overwritten by the next attempt.
      }
    }
  }

  /// Removes the legacy copies once the record points at the ruling-1 class,
  /// then the [sweepItemId] marker if nothing was left. The biometric
  /// namespace is touched only when this process opened it — any other call
  /// raises a prompt; seeds left there open only with the biometric and die
  /// with the next enrolment change, so they do not hold the marker.
  Future<void> _sweep(DeviceKeyClass from) async {
    var done = true;
    final seeds =
        from == DeviceKeyClass.legacyPinOnly ||
        (from == DeviceKeyClass.legacyBiometric && _legacyOpened);
    for (final id in seeds ? _seedIds : const <String>[]) {
      try {
        if (from == DeviceKeyClass.legacyBiometric ||
            await _pluginContains(id, from)) {
          await _pluginDelete(id, from);
        }
      } on Object {
        done = false; // the record already points at the copy that read back
      }
    }
    try {
      if (await _rawContains(KeyIds.wrappedUmk)) {
        await _rawDelete(KeyIds.wrappedUmk);
      }
      if (done) await _rawDelete(sweepItemId);
    } on Object {
      // Left for the next unlock.
    }
  }

  Future<Object?>? _running;

  /// One gate / migration step at a time (a PIN while the migration runs
  /// waits for it).
  Future<T> _exclusive<T>(Future<T> Function() op) {
    final before = _running;
    final next = () async {
      if (before != null) {
        try {
          await before;
        } on Object {
          // Its own caller saw it.
        }
      }
      return op();
    }();
    _running = next;
    return next;
  }

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  // ── per-class routing ─────────────────────────────────────────────────────

  bool get _androidNative => defaultTargetPlatform == TargetPlatform.android;

  Future<Uint8List?> _classRead(String id, DeviceKeyClass cls) {
    if (cls == DeviceKeyClass.hardware) {
      return _androidNative
          ? _platform.deviceItemRead(id)
          : _read(id, appleDeviceKeys, androidBase);
    }
    if (!_legacySeed(id)) return _rawRead(id); // legacy UMK: promptless
    return _pluginRead(id, cls);
  }

  Future<void> _classWrite(String id, Uint8List bytes, DeviceKeyClass cls) {
    if (cls == DeviceKeyClass.hardware) {
      return _androidNative
          ? _platform.deviceItemWrite(id, bytes)
          : _write(id, bytes, appleDeviceKeys, androidBase);
    }
    if (!_legacySeed(id)) return _rawWrite(id, bytes);
    return _pluginWrite(id, bytes, cls);
  }

  Future<void> _classDelete(String id, DeviceKeyClass cls) {
    if (cls == DeviceKeyClass.hardware) {
      return _androidNative
          ? _platform.deviceItemDelete(id)
          : _delete(id, appleDeviceKeys, androidBase);
    }
    if (!_legacySeed(id)) return _rawDelete(id);
    return _pluginDelete(id, cls);
  }

  Future<bool> _classContains(String id, DeviceKeyClass cls) async {
    if (cls == DeviceKeyClass.hardware) {
      return _androidNative
          ? _platform.deviceItemContains(id)
          : _contains(id, appleDeviceKeys, androidBase);
    }
    if (!_legacySeed(id)) return _rawContains(id);
    return _pluginContains(id, cls);
  }

  (IOSOptions, AndroidOptions) _legacyOptions(DeviceKeyClass cls) =>
      cls == DeviceKeyClass.legacyPinOnly
      ? (appleLegacyPinOnly, androidLegacyPinOnly)
      : (appleLegacyBiometric, _androidLegacyBiometric());

  Future<Uint8List?> _pluginRead(String id, DeviceKeyClass cls) {
    final (apple, android) = _legacyOptions(cls);
    return _read(id, apple, android);
  }

  Future<void> _pluginWrite(String id, Uint8List b, DeviceKeyClass cls) {
    final (apple, android) = _legacyOptions(cls);
    return _write(id, b, apple, android);
  }

  Future<void> _pluginDelete(String id, DeviceKeyClass cls) {
    final (apple, android) = _legacyOptions(cls);
    return _delete(id, apple, android);
  }

  Future<bool> _pluginContains(String id, DeviceKeyClass cls) {
    final (apple, android) = _legacyOptions(cls);
    return _contains(id, apple, android);
  }

  // ── the plugin boundary ───────────────────────────────────────────────────

  Future<Uint8List?> _rawRead(String id) => _read(id, appleBase, androidBase);

  Future<void> _rawWrite(String id, Uint8List bytes) =>
      _write(id, bytes, appleBase, androidBase);

  Future<void> _rawDelete(String id) => _delete(id, appleBase, androidBase);

  Future<bool> _rawContains(String id) => _contains(id, appleBase, androidBase);

  Future<Uint8List?> _read(
    String id,
    IOSOptions apple,
    AndroidOptions android,
  ) async {
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
    if (v == null) return null;
    return base64Decode(v);
  }

  Future<void> _write(
    String id,
    Uint8List bytes,
    IOSOptions apple,
    AndroidOptions android,
  ) =>
      // base64Encode copies; the String cannot be zeroised — the plugin
      // boundary's cost, kept as short-lived as Dart allows.
      _onAndroidFirstOpen(
        () => _storage.write(
          key: _prefix + id,
          value: base64Encode(bytes),
          iOptions: apple,
          mOptions: apple,
          aOptions: android,
        ),
      );

  Future<void> _delete(String id, IOSOptions apple, AndroidOptions android) =>
      _onAndroidFirstOpen(
        () => _storage.delete(
          key: _prefix + id,
          iOptions: apple,
          mOptions: apple,
          aOptions: android,
        ),
      );

  Future<bool> _contains(String id, IOSOptions apple, AndroidOptions android) =>
      _onAndroidFirstOpen(
        () => _storage.containsKey(
          key: _prefix + id,
          iOptions: apple,
          mOptions: apple,
          aOptions: android,
        ),
      );

  /// Test seam: whether this process has opened the legacy biometric class.
  @visibleForTesting
  bool get legacyBiometricOpened => _legacyOpened;

  /// Runs [op], retrying it exactly once when the plugin reports its
  /// fresh-install "Algorithm changed detected" mismatch (file comment). A
  /// second mismatch is real and rethrown; an invalidation is never retried.
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

  /// FlutterSecureStorage.initializeStorageCipher's text for a saved-vs-
  /// current algorithm marker mismatch (11.2.0).
  static const _freshMarkerMismatch = 'Algorithm changed detected';

  /// The one platform error that *means* "the biometric set changed" for a
  /// legacy biometric-bound item: Android's `KeyPermanentlyInvalidated`.
  /// iOS `errSecAuthFailed` (-25293) is a failed Face ID and
  /// `errSecInteractionNotAllowed` (-25308) "not now" (SecBase.h:271, :286);
  /// both rethrow as they came.
  static bool _looksInvalidated(PlatformException e) {
    final text = '${e.code} ${e.message ?? ''} ${e.details ?? ''}';
    return text.contains('KeyPermanentlyInvalidated');
  }
}
