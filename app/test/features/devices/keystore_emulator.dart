// An emulation of what reaches Android, for ADR 2026-10-05b's tests. It sits
// on the two *real* method channels — flutter_secure_storage's
// (`plugins.it_nomads.com/flutter_secure_storage`, driven through
// `MethodChannelFlutterSecureStorage`, as F1-05d does) and the app's own
// `rukka_folio/keystore` (driven through `MethodChannelKeystorePlatform`) — so
// every assertion is about what crosses the boundary, not about a fake class.
//
// What it models of flutter_secure_storage 11.2.0 on Android, per namespace:
//   • `rukka_folio_device` (the biometric class): every call initialises the
//     namespace first (FlutterSecureStoragePlugin.java:176-178), and that
//     fails when no strong biometric is enrolled ("At least one biometric must
//     be enrolled …", KeyCipherImplementationAES23.java:169-181), when the key
//     was invalidated (KeyPermanentlyInvalidatedException → key mismatch,
//     FlutterSecureStorage.java:425-426 → :1016), or when the person cancels
//     the BiometricPrompt ("Biometric authentication error [10]", :1305-1308).
//     So delete fails on an invalidated namespace too — the reason the app has
//     its own reset.
//   • every other namespace opens without a person.
// And of the app's native helper: `qualifyingBiometricEnrolled` answers
// [enrolled]; `resetBiometricDeviceItems` empties the biometric namespace and
// clears the invalidation (RukkaKeystoreChannel.kt).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keystore_platform.dart';

const pluginChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The biometric namespace (ADR 2026-09-05d §4 class).
const biometricNs = 'rukka_folio_device';

/// The PIN-only namespace (ADR 2026-10-05b §1 class).
const pinOnlyNs = 'rukka_folio_device_pin';

/// The promptless namespace (DB key, vault, binding record).
const promptlessNs = 'rukka_folio';

final class AndroidKeystoreEmulator {
  AndroidKeystoreEmulator({this.enrolled = false});

  /// A Class 3 biometric is enrolled (and a screen lock set).
  bool enrolled;

  /// The biometric namespace's Keystore key was invalidated.
  bool invalidated = false;

  /// The next n biometric-namespace calls end in a cancelled prompt.
  int cancelBiometric = 0;

  /// The next n biometric-namespace calls never answer — the plugin's
  /// BiometricPrompt negative button (FlutterSecureStorage.java:1281-1282:
  /// a no-op listener, and the framework then calls no error callback).
  int hangBiometric = 0;

  /// Biometric-namespace reads return different bytes (a corrupt read-back).
  bool corruptBiometricReads = false;

  /// The next n biometric-namespace calls fail the way iOS reports a face that
  /// was not recognised — `errSecAuthFailed` (-25293) through the plugin's
  /// "Unexpected security result code" — which is NOT an invalidation.
  int failFaceBiometric = 0;

  /// The relock gate (`armBiometricGate` / `authenticate` on the app's own
  /// channel): armed against the set enrolled at arming time.
  bool gateArmed = false;

  /// Answers the relock prompt gives, in order; when empty an armed gate
  /// answers `success` and an unarmed one `unarmed`.
  final gateAnswers = <String>[];

  /// Every plugin call, in order.
  final wire = <MethodCall>[];

  /// Every call on the app's own channel, in order.
  final native = <MethodCall>[];

  /// `namespace/key` → stored value.
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
    final k = '$ns/${args['key']}';
    switch (call.method) {
      case 'write':
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
        stored.remove(k);
        return null;
    }
    return null;
  }

  Future<Object?> _native(MethodCall call) async {
    native.add(call);
    switch (call.method) {
      case 'qualifyingBiometricEnrolled':
        return enrolled;
      case 'resetBiometricDeviceItems':
        stored.removeWhere((k, _) => k.startsWith('$biometricNs/'));
        invalidated = false;
        return true;
      case 'excludeFromBackup':
        return true;
      case 'armBiometricGate':
        gateArmed = enrolled;
        return enrolled;
      case 'authenticate':
        if (gateAnswers.isNotEmpty) return gateAnswers.removeAt(0);
        return gateArmed ? 'success' : 'unarmed';
    }
    return null;
  }
}
