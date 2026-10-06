// An emulation of what reaches Android, for ADR 2026-10-05b's and ADR
// 2026-10-06's tests. It sits on the two *real* method channels —
// flutter_secure_storage's (`plugins.it_nomads.com/flutter_secure_storage`,
// driven through `MethodChannelFlutterSecureStorage`, as F1-05d does) and the
// app's own `rukka_folio/keystore` (driven through
// `MethodChannelKeystorePlatform`) — so every assertion is about what crosses
// the boundary, not about a fake class.
//
// Of flutter_secure_storage 11.2.0 on Android, per namespace:
//   • `rukka_folio_device` (the legacy biometric class): every call
//     initialises the namespace first (FlutterSecureStoragePlugin.java:176-178),
//     and that fails when no strong biometric is enrolled
//     (KeyCipherImplementationAES23.java:169-181), when the key was
//     invalidated (KeyPermanentlyInvalidatedException → key mismatch,
//     FlutterSecureStorage.java:425-426 → :1016), or when the person cancels
//     the BiometricPrompt ("Biometric authentication error [10]", :1305-1308).
//   • every other namespace opens without a person.
// Of the app's native helper (RukkaKeystoreChannel.kt):
//   • the device-key class (`deviceItem*`, ADR 2026-10-06 §1): [hw], with no
//     person bound and nothing an enrolment change touches;
//   • the gate (`armBiometricGate` / `authenticate` / `resetGate`, ruling 2):
//     minted only with a qualifying biometric, invalidated by
//     [changeEnrolment], answering `reenrolled` (and removing itself) when
//     read after one;
//   • `qualifyingBiometricEnrolled` answers [enrolled].
// A method the native half does not have throws [MissingPluginException], so a
// call to a removed one (KEY145B's `resetBiometricDeviceItems`) fails loudly.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keystore_platform.dart';

const pluginChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The legacy biometric namespace (ADR 2026-09-05d §4 as built).
const biometricNs = 'rukka_folio_device';

/// The legacy PIN-only namespace (ADR 2026-10-05b §1).
const pinOnlyNs = 'rukka_folio_device_pin';

/// The promptless namespace (DB key, vault, records).
const promptlessNs = 'rukka_folio';

final class AndroidKeystoreEmulator {
  AndroidKeystoreEmulator({this.enrolled = false});

  /// A Class 3 biometric is enrolled (and a screen lock set).
  bool enrolled;

  // ── the legacy biometric plugin namespace ──────────────────────────────

  /// The legacy biometric namespace's Keystore key was invalidated.
  bool invalidated = false;

  /// The next n legacy-biometric calls end in a cancelled prompt.
  int cancelBiometric = 0;

  /// The next n legacy-biometric calls never answer (the plugin's negative
  /// button, FlutterSecureStorage.java:1281-1282).
  int hangBiometric = 0;

  /// Legacy-biometric reads return different bytes.
  bool corruptBiometricReads = false;

  /// The next n legacy-biometric calls fail as iOS reports a face that was
  /// not recognised (errSecAuthFailed -25293) — NOT an invalidation.
  int failFaceBiometric = 0;

  /// The next plugin write to a key ending with this fails.
  String? failPluginWriteKey;

  /// Plugin deletes of keys ending with any of these fail.
  final failPluginDeleteKeys = <String>{};

  // ── the device-key class (ADR 2026-10-06 §1) ───────────────────────────

  /// id → stored bytes.
  final hw = <String, Uint8List>{};

  /// The next n device-item writes fail.
  int failHwWrites = 0;

  /// The next n device-item reads fail.
  int failHwReads = 0;

  /// Device-item reads return different bytes.
  bool corruptHwReads = false;

  // ── the gate (ADR 2026-10-06 §2) ───────────────────────────────────────

  /// A gate item exists.
  bool gateMinted = false;

  /// The gate's biometric set has changed since it was minted.
  bool gateInvalid = false;

  /// Answers the gate read gives, in order, for a valid gate; when empty a
  /// valid gate answers `success`.
  final gateAnswers = <String>[];

  /// A finger or face added or removed in Settings: the gate (and a legacy
  /// biometric class) is invalidated; the device-key class is not.
  void changeEnrolment({bool stillEnrolled = true}) {
    enrolled = stillEnrolled;
    if (gateMinted) gateInvalid = true;
    if (stored.keys.any((k) => k.startsWith('$biometricNs/'))) {
      invalidated = true;
    }
  }

  // ── records ────────────────────────────────────────────────────────────

  /// Every plugin call, in order.
  final wire = <MethodCall>[];

  /// Every call on the app's own channel, in order.
  final native = <MethodCall>[];

  /// `namespace/key` → stored value (plugin).
  final stored = <String, String>{};

  static Map<String, String> optionsOf(MethodCall c) =>
      ((c.arguments as Map)['options'] as Map).cast<String, String>();
  static String nsOf(MethodCall c) => optionsOf(c)['storageNamespace']!;
  static String keyOf(MethodCall c) => (c.arguments as Map)['key'] as String;

  /// Plugin calls that reached [ns].
  List<MethodCall> callsTo(String ns) => [
    for (final c in wire)
      if (nsOf(c) == ns) c,
  ];

  /// Native method names, in order.
  List<String> get nativeMethods => [for (final c in native) c.method];

  /// Installs both handlers and the Android target; undone at tear-down.
  void install() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStoragePlatform.instance = MethodChannelFlutterSecureStorage();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pluginChannel, _plugin);
    messenger.setMockMethodCallHandler(
      MethodChannelKeystorePlatform.channel,
      _native,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(pluginChannel, null);
      messenger.setMockMethodCallHandler(
        MethodChannelKeystorePlatform.channel,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }

  Future<Object?> _plugin(MethodCall call) async {
    wire.add(call);
    final args = call.arguments as Map;
    final ns = nsOf(call);
    if (ns == biometricNs) {
      if (invalidated) {
        throw PlatformException(
          code: 'Exception encountered',
          message:
              'Key mismatch after algorithm change (Invalid key, key type '
              'incompatible with cipher). Enable migrateOnAlgorithmChange=true '
              'to preserve data, or resetOnError=true to delete.',
          details:
              'Caused by: android.security.keystore.'
              'KeyPermanentlyInvalidatedException: Key permanently invalidated',
        );
      }
      if (!enrolled) {
        throw PlatformException(
          code: 'Exception encountered',
          message:
              'java.lang.IllegalStateException: At least one biometric must be '
              'enrolled to create keys requiring user authentication for every '
              'use',
        );
      }
      if (hangBiometric > 0) {
        hangBiometric--;
        return Completer<Object?>().future;
      }
      if (failFaceBiometric > 0) {
        failFaceBiometric--;
        throw PlatformException(
          code: 'Unexpected security result code',
          message:
              'Code: -25293, Message: The user name or passphrase you '
              'entered is not correct.',
        );
      }
      if (cancelBiometric > 0) {
        cancelBiometric--;
        throw PlatformException(
          code: 'Exception encountered',
          message: 'Biometric authentication error [10]: Cancelled by user',
        );
      }
    }
    final key = args['key'] as String;
    final k = '$ns/$key';
    switch (call.method) {
      case 'write':
        final f = failPluginWriteKey;
        if (f != null && key.endsWith(f)) {
          failPluginWriteKey = null;
          throw PlatformException(code: 'write failed');
        }
        stored[k] = args['value'] as String;
        return null;
      case 'read':
        final v = stored[k];
        if (v != null && ns == biometricNs && corruptBiometricReads) {
          return 'AAAA';
        }
        return v;
      case 'containsKey':
        return stored.containsKey(k);
      case 'delete':
        if (failPluginDeleteKeys.any(key.endsWith)) {
          throw PlatformException(code: 'delete failed');
        }
        stored.remove(k);
        return null;
    }
    return null;
  }

  Future<Object?> _native(MethodCall call) async {
    native.add(call);
    final args = call.arguments is Map
        ? call.arguments as Map
        : const <Object?, Object?>{};
    switch (call.method) {
      case 'qualifyingBiometricEnrolled':
        return enrolled;
      case 'excludeFromBackup':
        return true;
      case 'deviceItemRead':
        if (failHwReads > 0) {
          failHwReads--;
          throw PlatformException(code: 'device_item_failed');
        }
        final v = hw[args['id']];
        if (v == null) return null;
        if (corruptHwReads) return Uint8List.fromList([0, ...v]);
        return Uint8List.fromList(v);
      case 'deviceItemWrite':
        if (failHwWrites > 0) {
          failHwWrites--;
          throw PlatformException(code: 'device_item_failed');
        }
        hw[args['id'] as String] = Uint8List.fromList(
          args['bytes'] as Uint8List,
        );
        return true;
      case 'deviceItemDelete':
        hw.remove(args['id']);
        return true;
      case 'deviceItemContains':
        return hw.containsKey(args['id']);
      case 'deviceKeyStorage':
        return 'strongBox';
      case 'armBiometricGate':
        if (!enrolled) return false;
        gateMinted = true;
        gateInvalid = false;
        return true;
      case 'resetGate':
        gateMinted = false;
        gateInvalid = false;
        return true;
      case 'authenticate':
        if (!gateMinted) return 'unarmed';
        if (gateInvalid) {
          gateMinted = false;
          gateInvalid = false;
          return 'reenrolled';
        }
        if (gateAnswers.isNotEmpty) return gateAnswers.removeAt(0);
        return enrolled ? 'success' : 'unavailable';
    }
    throw MissingPluginException('no native ${call.method}');
  }
}
