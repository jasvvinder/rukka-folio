@Tags(['C'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

/// Records the platform options every call carries, so the test can assert
/// what the Keychain / Keystore would be told.
final class RecordingPlatform extends FlutterSecureStoragePlatform {
  final data = <String, String>{};
  final calls = <(String op, String key, Map<String, String> options)>[];
  PlatformException? throwOnRead;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    calls.add(('contains', key, options));
    return data.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    calls.add(('delete', key, options));
    data.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    calls.add(('read', key, options));
    final t = throwOnRead;
    // The binding record (ADR 2026-10-05b) is promptless; the failure under
    // test is the device-key item's.
    if (t != null && !key.endsWith(KeychainKeyStore.bindingItemId)) throw t;
    return data[key];
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => data;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    calls.add(('write', key, options));
    data[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingPlatform platform;
  late KeychainKeyStore store;

  setUp(() {
    platform = RecordingPlatform();
    FlutterSecureStoragePlatform.instance = platform;
    store = KeychainKeyStore(storage: const FlutterSecureStorage());
  });

  group('KeychainKeyStore (04 §3.3, ADR 2026-09-05d §4)', () {
    test('C-06-2 bytes round-trip through the platform as base64 under a namespaced key; read returns a fresh copy; delete and contains agree', () async {
      final secret = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      expect(await store.contains(KeyIds.databaseKey), isFalse);
      expect(await store.read(KeyIds.databaseKey), isNull);

      await store.write(KeyIds.databaseKey, secret);
      expect(platform.data.keys, ['rukka.rk.db.key']);
      expect(platform.data.values.single, base64Encode(secret));

      final back = (await store.read(KeyIds.databaseKey))!;
      expect(back, secret);
      back[0] = 0;
      expect((await store.read(KeyIds.databaseKey))![0], 255);
      expect(await store.contains(KeyIds.databaseKey), isTrue);

      await store.delete(KeyIds.databaseKey);
      expect(await store.contains(KeyIds.databaseKey), isFalse);
      expect(platform.data, isEmpty);
    });

    test('C-06-3 every item is this-device-only, after-first-unlock, never iCloud-synced, never wiped on error; only the device keys are bound to the current biometric set', () async {
      final all = [
        KeyIds.databaseKey,
        KeyIds.wrappedUmk,
        KeyIds.deviceSigningKey,
        KeyIds.deviceAgreementKey,
      ];
      for (final id in all) {
        await store.write(id, Uint8List(4));
      }
      // The options map the plugin sends is per-platform; the test runs on
      // the host, so inspect the static option sets the store hands over.
      for (final apple in [
        KeychainKeyStore.appleBase,
        KeychainKeyStore.appleBiometric,
      ]) {
        final m = apple.toMap();
        expect(m['accessibility'], 'first_unlock_this_device');
        expect(m['synchronizable'], 'false');
        expect(m['useSecureEnclave'], 'false');
      }
      expect(
        KeychainKeyStore.appleBase.toMap().containsKey('accessControlFlags'),
        isFalse,
      );
      expect(
        KeychainKeyStore.appleBiometric.toMap()['accessControlFlags'],
        '[biometryCurrentSet]',
      );
      // Android: what crosses the channel per item class is asserted by
      // F1-05d-1…3 below (desk 145); here only the shared invariants.
      for (final android in [
        KeychainKeyStore.androidBase,
        KeychainKeyStore.androidBiometric,
      ]) {
        final m = android.toMap();
        expect(m['resetOnError'], 'false');
        expect(m['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
      }
      expect(
        KeychainKeyStore.androidBase.toMap()['enforceBiometrics'],
        'false',
      );
      final ab = KeychainKeyStore.androidBiometric.toMap();
      expect(ab['enforceBiometrics'], 'true');
      expect(ab['biometricType'], 'strongBiometricOnly');

      expect(isBiometricBound(KeyIds.deviceSigningKey), isTrue);
      expect(isBiometricBound(KeyIds.deviceAgreementKey), isTrue);
      expect(isBiometricBound(KeyIds.databaseKey), isFalse);
      expect(isBiometricBound(KeyIds.wrappedUmk), isFalse);
      expect(isBiometricBound('rk.pin.vault'), isFalse);

      // Whatever the host, the plugin received *some* option set for each
      // call — never the plugin defaults (which sync to iCloud).
      // (ADR 2026-10-05b adds the promptless binding record's own calls.)
      expect(platform.calls.length, greaterThanOrEqualTo(all.length));
      for (final (_, _, o) in platform.calls) {
        expect(o, isNotEmpty);
      }
    });

    test('C-06-4 a biometric-enrolment invalidation (Android KeyPermanentlyInvalidated) surfaces as KeyStoreInvalidated (the MPIN fallback); iOS errSecInteractionNotAllowed / errSecAuthFailed and other platform errors rethrow; absence is null', () async {
      platform.throwOnRead = PlatformException(
        code: 'Exception encountered',
        message: 'android.security.keystore.KeyPermanentlyInvalidatedException: Key permanently invalidated',
      );
      await expectLater(
        store.read(KeyIds.deviceSigningKey),
        throwsA(
          isA<KeyStoreInvalidated>().having(
            (e) => e.id,
            'id',
            KeyIds.deviceSigningKey,
          ),
        ),
      );
      // KEY145B review finding 1: neither iOS code means an enrolment change
      // (SecBase.h:271 errSecAuthFailed = a failed Face ID, :286
      // errSecInteractionNotAllowed = not now). Ruling 3 deletes what is
      // classified as invalidated, so these must stay plain platform errors.
      for (final code in const ['-25308', '-25293']) {
        platform.throwOnRead = PlatformException(
          code: 'Unexpected security result code',
          message: 'Code: $code',
        );
        await expectLater(
          store.read(KeyIds.deviceAgreementKey),
          throwsA(
            isA<PlatformException>().having(
              (e) => e,
              'not an invalidation',
              isNot(isA<KeyStoreInvalidated>()),
            ),
          ),
        );
      }
      platform.throwOnRead = PlatformException(code: 'Some other failure');
      await expectLater(
        store.read(KeyIds.deviceAgreementKey),
        throwsA(isA<PlatformException>()),
      );
      platform.throwOnRead = null;
      expect(await store.read(KeyIds.deviceAgreementKey), isNull);
    });
  });

  // Desk 145 (5 Oct 2026): the app died at startup on Android inside the
  // plugin's initialise step. These drive the *real* method-channel platform
  // (not a fake platform class) so they assert exactly what reaches the
  // Android side, per item class.
  group('Android Keystore option sets on the wire (desk 145, ADR 2026-09-05d §4)', () {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    late List<MethodCall> wire;
    late Map<String, String> stored;
    late List<PlatformException> failNext;
    String? failOnlyKey;
    late KeychainKeyStore android;

    Map<String, String> optionsOf(MethodCall c) =>
        ((c.arguments as Map)['options'] as Map).cast<String, String>();
    String keyOf(MethodCall c) => (c.arguments as Map)['key'] as String;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterSecureStoragePlatform.instance =
          MethodChannelFlutterSecureStorage();
      wire = [];
      stored = {};
      failNext = [];
      failOnlyKey = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            wire.add(call);
            final args = call.arguments as Map;
            if (failNext.isNotEmpty &&
                (failOnlyKey == null || args['key'] == failOnlyKey)) {
              throw failNext.removeAt(0);
            }
            final ns = optionsOf(call)['storageNamespace']!;
            final k = '$ns/${args['key']}';
            switch (call.method) {
              case 'write':
                stored[k] = args['value'] as String;
                return null;
              case 'read':
                return stored[k];
              case 'containsKey':
                return stored.containsKey(k);
              case 'delete':
                stored.remove(k);
                return null;
            }
            return null;
          });
      android = KeychainKeyStore(storage: const FlutterSecureStorage());
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    final promptless = [
      KeyIds.databaseKey,
      KeyIds.wrappedUmk,
      KeyIds.recoveryCandidate,
      PinVault.itemId,
    ];
    const deviceKeys = [KeyIds.deviceSigningKey, KeyIds.deviceAgreementKey];

    Future<void> touch(String id) async {
      await android.write(id, Uint8List.fromList([1, 2, 3]));
      await android.read(id);
      await android.contains(id);
      await android.delete(id);
    }

    test('F1-05d-1 the database key, the PIN vault and every other non-device item reach Android on the RSA-wrapped, no-user-auth option set — never the biometric key cipher, which would demand a prompt before the DB opens', () async {
      for (final id in promptless) {
        await touch(id);
      }
      expect(wire, hasLength(promptless.length * 4));
      expect(wire.map((c) => c.method).toSet(), {
        'write',
        'read',
        'containsKey',
        'delete',
      });
      for (final c in wire) {
        final o = optionsOf(c);
        expect(o['storageNamespace'], 'rukka_folio', reason: keyOf(c));
        // The plugin's AES_GCM key cipher creates its Keystore key with
        // setUserAuthenticationRequired(true) whenever the phone has a
        // screen lock, whatever enforceBiometrics says — so the promptless
        // class must be on the RSA key cipher.
        expect(
          o['keyCipherAlgorithm'],
          'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
          reason: keyOf(c),
        );
        expect(o['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
        expect(o['enforceBiometrics'], 'false');
        expect(o['requireBiometricsPerOperation'], 'false');
        expect(o['resetOnError'], 'false');
        expect(o['migrateOnAlgorithmChange'], 'false');
      }
    });

    test('F1-05d-2 once the phone is biometric-bound (ADR 2026-10-05b §2), the device keys reach Android strong-biometric bound, in their own namespace, never wiped and never migrated', () async {
      stored['rukka_folio/rukka.${KeychainKeyStore.bindingItemId}'] =
          base64Encode(utf8.encode('biometric'));
      for (final id in deviceKeys) {
        await touch(id);
      }
      final deviceWire = [
        for (final c in wire)
          if (keyOf(c) != 'rukka.${KeychainKeyStore.bindingItemId}') c,
      ];
      expect(deviceWire, hasLength(deviceKeys.length * 4));
      for (final c in deviceWire) {
        final o = optionsOf(c);
        expect(o['storageNamespace'], 'rukka_folio_device', reason: keyOf(c));
        expect(o['keyCipherAlgorithm'], 'AES_GCM_NoPadding');
        expect(o['enforceBiometrics'], 'true');
        expect(o['biometricType'], 'strongBiometricOnly');
        expect(o['resetOnError'], 'false');
        expect(o['migrateOnAlgorithmChange'], 'false');
      }
    });

    test('F1-05d-3 the item classes never share a storage namespace — the plugin keys one storage instance, its config, its algorithm markers and its Keystore alias by namespace, so a shared one lets whichever class initialises first decide for all (ADR 2026-10-05b adds the PIN-only class as a third)', () async {
      final bindingKey = 'rukka_folio/rukka.${KeychainKeyStore.bindingItemId}';
      String nsOfClass(DeviceKeyBinding b) {
        stored[bindingKey] = base64Encode(
          utf8.encode(b == DeviceKeyBinding.pinOnly ? 'pin-only' : 'biometric'),
        );
        return b.name;
      }

      final byClass = <String, Set<String>>{};
      for (final b in DeviceKeyBinding.values) {
        final name = nsOfClass(b);
        wire.clear();
        for (final id in deviceKeys) {
          await touch(id);
        }
        for (final c in wire) {
          if (keyOf(c) == 'rukka.${KeychainKeyStore.bindingItemId}') continue;
          (byClass[name] ??= {}).add(optionsOf(c)['storageNamespace']!);
        }
      }
      wire.clear();
      for (final id in promptless) {
        await touch(id);
      }
      byClass['promptless'] = {
        for (final c in wire) optionsOf(c)['storageNamespace']!,
      };
      expect(byClass.values.every((v) => v.length == 1), isTrue);
      expect(byClass.values.map((v) => v.single).toSet(), hasLength(3));
      // And the stored values landed apart.
      stored.clear();
      await android.write(KeyIds.databaseKey, Uint8List.fromList([9]));
      await android.write(KeyIds.deviceSigningKey, Uint8List.fromList([8]));
      expect(stored.keys, {
        'rukka_folio/rukka.${KeyIds.databaseKey}',
        bindingKey,
        'rukka_folio_device_pin/rukka.${KeyIds.deviceSigningKey}',
      });
    });

    PlatformException freshInstallMismatch() => PlatformException(
      code: 'Exception encountered',
      message:
          'Key mismatch after algorithm change (Algorithm changed detected). '
          'Enable migrateOnAlgorithmChange=true to preserve data, or '
          'resetOnError=true to delete.',
    );

    test('F1-05d-4 a first-ever open of a namespace that reports "Algorithm changed detected" (the plugin reads absent markers as RSA) is retried exactly once; a second mismatch surfaces — no loop, no wipe', () async {
      stored['rukka_folio_device/rukka.${KeyIds.deviceSigningKey}'] = base64
          .encode([7, 7]);
      // The mismatch lands on the device-key read itself, not on the
      // promptless binding record read before it (ADR 2026-10-05b).
      failOnlyKey = 'rukka.${KeyIds.deviceSigningKey}';
      failNext.add(freshInstallMismatch());
      expect(await android.read(KeyIds.deviceSigningKey), [7, 7]);
      expect(
        wire
            .where((c) => keyOf(c) == 'rukka.${KeyIds.deviceSigningKey}')
            .map((c) => c.method),
        ['read', 'read'],
      );

      wire.clear();
      failOnlyKey = null;
      failNext.addAll([freshInstallMismatch(), freshInstallMismatch()]);
      await expectLater(
        android.write(KeyIds.databaseKey, Uint8List(1)),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.message,
            'message',
            contains('Algorithm changed detected'),
          ),
        ),
      );
      expect(wire.map((c) => c.method), ['write', 'write']);
      expect(wire.any((c) => c.method == 'deleteAll'), isFalse);
    });

    test('F1-05d-5 an enrolment change as the plugin really reports it (key mismatch message, KeyPermanentlyInvalidatedException in the cause chain) is KeyStoreInvalidated — the MPIN fallback — and is not retried', () async {
      failNext.add(
        PlatformException(
          code: 'Exception encountered',
          message:
              'Key mismatch after algorithm change (Invalid key, key type '
              'incompatible with cipher). Enable migrateOnAlgorithmChange=true '
              'to preserve data, or resetOnError=true to delete.',
          details:
              'java.lang.Exception: Key mismatch after algorithm change\n'
              'Caused by: android.security.keystore.'
              'KeyPermanentlyInvalidatedException: Key permanently invalidated',
        ),
      );
      await expectLater(
        android.read(KeyIds.deviceAgreementKey),
        throwsA(isA<KeyStoreInvalidated>()),
      );
      expect(wire, hasLength(1));
    });

    test('F1-05d-6 the Android app declares USE_BIOMETRIC (the framework BiometricPrompt the plugin calls is refused without it) and holds the Android 9 / API 28 floor the biometric option set needs (13 §10 decision 9)', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.USE_BIOMETRIC"',
        ),
      );
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, matches(RegExp(r'^\s*minSdk = 28\b', multiLine: true)));
    });

    test('F1-05d-7 the Android app is out of platform backup and device-to-device transfer (03 §6, ADR 2026-09-05c §8): allowBackup=false, and the extraction rules exclude every domain from both cloud-backup and device-transfer, so a restore never brings back the secure-storage preferences without their Keystore keys', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final app = RegExp(
        r'<application\b[^>]*>',
        multiLine: true,
      ).firstMatch(manifest)!.group(0)!;
      expect(app, contains('android:allowBackup="false"'));
      expect(app, contains('android:fullBackupContent="false"'));
      expect(
        app,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );

      final rules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      expect(rules, isNot(contains('<include')));
      const domains = [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
        'device_root',
        'device_file',
        'device_database',
        'device_sharedpref',
      ];
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp(
          '<$section>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(rules)?.group(1);
        expect(body, isNotNull, reason: '$section section missing');
        for (final d in domains) {
          expect(
            body,
            contains('<exclude domain="$d" path="."/>'),
            reason: '$section must exclude $d',
          );
        }
      }
    });
  });
}
