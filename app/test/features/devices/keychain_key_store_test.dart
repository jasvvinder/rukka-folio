@Tags(['C'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
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
    if (t != null) throw t;
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
      for (final android in [
        KeychainKeyStore.androidBase,
        KeychainKeyStore.androidBiometric,
      ]) {
        final m = android.toMap();
        expect(m['resetOnError'], 'false');
        expect(m['keyCipherAlgorithm'], 'AES_GCM_NoPadding');
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
      expect(platform.calls, hasLength(all.length));
      for (final (_, _, o) in platform.calls) {
        expect(o, isNotEmpty);
      }
    });

    test('C-06-4 a biometric-enrolment invalidation surfaces as KeyStoreInvalidated (the MPIN fallback), other platform errors rethrow, absence is null', () async {
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
      platform.throwOnRead = PlatformException(
        code: 'Unexpected security result code',
        message: 'Code: -25308',
      );
      await expectLater(
        store.read(KeyIds.deviceAgreementKey),
        throwsA(isA<KeyStoreInvalidated>()),
      );
      platform.throwOnRead = PlatformException(code: 'Some other failure');
      await expectLater(
        store.read(KeyIds.deviceAgreementKey),
        throwsA(isA<PlatformException>()),
      );
      platform.throwOnRead = null;
      expect(await store.read(KeyIds.deviceAgreementKey), isNull);
    });
  });
}
