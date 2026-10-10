// ADR 2026-10-06 🔒 — the fingerprint guards a gate key, never the device keys.
// Rulings 1–5 against the real method channels: flutter_secure_storage's and
// the app's own `rukka_folio/keystore`, with the Android emulation of
// keystore_emulator.dart under them (F1-05d style), a real [LocalLedger]
// minting and reopening the device keys, and a real [PinVault] behind the PIN.
// The native halves (RukkaKeystoreChannel.kt, AppDelegate.swift) are pinned by
// their source, as F1-05d-6/7 pin the manifest.
@Tags(['C'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
import 'package:rukka_folio/features/devices/keystore_platform.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/keystore_biometric_gate.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../../shared/test_app.dart';
import 'keystore_emulator.dart';

const _pin = '135790';
const _items = [
  KeyIds.deviceSigningKey,
  KeyIds.deviceAgreementKey,
  KeyIds.wrappedUmk,
];
final _sign = Uint8List.fromList(List.generate(32, (i) => i + 1));
final _agree = Uint8List.fromList(List.generate(32, (i) => 200 - i));
final _umk = Uint8List.fromList(List.generate(80, (i) => (i * 7) & 0xff));

String _kt() => File(
  'android/app/src/main/kotlin/com/rukkafolio/rukka_folio/RukkaKeystoreChannel.kt',
).readAsStringSync();

String _swift() => File('ios/Runner/AppDelegate.swift').readAsStringSync();

/// The text of the Kotlin function [name], up to the next `private fun`.
String _ktFun(String name) {
  final kt = _kt();
  final at = kt.indexOf('private fun $name(');
  expect(at, greaterThan(0), reason: name);
  final next = kt.indexOf('private fun ', at + 1);
  return kt.substring(at, next < 0 ? kt.length : next);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AndroidKeystoreEmulator android;

  setUp(() {
    android = AndroidKeystoreEmulator()..install();
  });

  /// A new process over the same platform state: nothing cached, sealed.
  KeychainKeyStore process() {
    final keys = KeychainKeyStore();
    keys.setPromptCopy(title: 'Unlock', subtitle: 'Touch', cancel: 'Use PIN');
    return keys;
  }

  Future<PinVault> vaultOver(KeychainKeyStore keys) async => PinVault(
    keys: keys,
    suite: await testSuite(),
    now: testNow,
    onPinProven: keys.unsealAfterPin,
    afterPinProven: () async {
      await keys.afterPinProven();
    },
  );

  /// First run (no PIN yet → open), as bootstrap does it.
  /// A first launch — ids only (ADR 2026-10-09 §2 🔒) — and then S0.2's key
  /// step, `mintForRegistration`, which is where the device keys and a new
  /// account's UMK are minted (desk 184 (c)); nothing key-shaped reaches the
  /// device-key class before it.
  Future<LocalLedger> firstRun(KeychainKeyStore keys) async {
    expect(await keys.unsealIfNoPin(), isTrue);
    final ledger = LocalLedger(
      db: await openTestDb(),
      keys: keys,
      suite: await testSuite(),
      now: testNow,
    );
    addTearDown(ledger.dispose);
    final writesBefore = android.native
        .where((c) => c.method == 'deviceItemWrite')
        .length;
    await ledger.openIdentity();
    expect(
      android.native.where((c) => c.method == 'deviceItemWrite').length,
      writesBefore,
      reason: 'the first run mints ids only — no device key, no UMK',
    );
    expect(ledger.keysRegistered, isFalse);
    await ledger.mintForRegistration();
    expect(ledger.keysRegistered, isTrue);
    return ledger;
  }

  Map<String, List<int>> hwSnapshot() => {
    for (final e in android.hw.entries) e.key: List.of(e.value),
  };

  String? promptless(String id) {
    final v = android.stored['$promptlessNs/rukka.$id'];
    return v == null ? null : utf8.decode(base64Decode(v));
  }

  int count(String method) =>
      android.native.where((c) => c.method == method).length;

  group('ruling 1 — the device keys are never biometric-bound', () {
    test('C-1006-1 the device keys and the wrapped UMK are minted by S0.2\'s '
        'key step (mintForRegistration, ADR 2026-10-09 §2 — never at the first '
        'run, which mints ids only) straight into the hardware-backed class '
        '(the app channel — no '
        'plugin namespace, no biometric option) and are never written again '
        'by an unlock, a gate, an enrolment change or a PIN; the native key '
        'is StrongBox where available with no user-auth binding and no '
        'enrolment invalidation; iOS keeps them this-device-only with no '
        'access control', () async {
      android.enrolled = true;
      final keys = process();
      final ledger = await firstRun(keys);

      // Minted: the class record (promptless) first, then all three items on
      // the app's own channel.
      expect(promptless(KeychainKeyStore.classItemId), 'hardware');
      expect(android.hw.keys.toSet(), _items.toSet());
      expect(count('deviceItemWrite'), 3);
      final recordWrite = android.wire.indexWhere(
        (c) =>
            c.method == 'write' &&
            AndroidKeystoreEmulator.keyOf(c) ==
                'rukka.${KeychainKeyStore.classItemId}',
      );
      expect(recordWrite, greaterThanOrEqualTo(0));
      // Nothing of the device keys on the plugin: no legacy namespace, no
      // biometric option set, no UMK copy in the promptless class.
      expect(android.callsTo(biometricNs), isEmpty);
      expect(android.callsTo(pinOnlyNs), isEmpty);
      expect(
        android.wire.where(
          (c) =>
              AndroidKeystoreEmulator.optionsOf(c)['enforceBiometrics'] ==
              'true',
        ),
        isEmpty,
      );
      for (final id in _items) {
        expect(
          android.stored.keys.where((k) => k.endsWith('rukka.$id')),
          isEmpty,
          reason: id,
        );
      }
      expect(await keys.deviceKeyHardware(), DeviceKeyHardware.strongBox);
      final minted = hwSnapshot();

      // O4b with a fingerprint: a gate, no key write.
      final vault = await vaultOver(keys);
      await vault.setPin(_pin);
      await vault.pendingAfterPin;
      expect(android.gateMinted, isTrue);

      // Cold starts: by the gate; then after a second fingerprint by the PIN
      // (a new gate); then with every biometric removed by the PIN (no gate);
      // and the one-time migration finds nothing to move.
      var k = process();
      expect(await k.openWithGate(), PlatformBiometricAnswer.success);
      await k.read(KeyIds.deviceSigningKey);
      android.changeEnrolment();
      k = process();
      expect(await k.openWithGate(), PlatformBiometricAnswer.reenrolled);
      var v = await vaultOver(k);
      expect(await v.verify(_pin), isA<PinAccepted>());
      await v.pendingAfterPin;
      expect(android.gateMinted, isTrue);
      android.changeEnrolment(stillEnrolled: false);
      k = process();
      v = await vaultOver(k);
      expect(await v.verify(_pin), isA<PinAccepted>());
      await v.pendingAfterPin;
      expect(await k.migrateAfterUnlock(), DeviceKeyMigration.notNeeded);

      expect(count('deviceItemWrite'), 3, reason: 'never written again');
      expect(count('deviceItemDelete'), 0);
      expect(hwSnapshot(), minted);
      // …and the same identity reopens through them.
      final again = LocalLedger(
        db: ledger.db,
        keys: k,
        suite: await testSuite(),
        now: testNow,
      );
      expect((await again.bootstrapSolo()).deviceId, ledger.identity.deviceId);

      // Android, the native key (RukkaKeystoreChannel.kt).
      final spec = _ktFun('deviceKeySpec');
      expect(spec, contains('.setUserAuthenticationRequired(false)'));
      expect(spec, contains('.setInvalidatedByBiometricEnrollment(false)'));
      expect(spec, contains('setIsStrongBoxBacked(true)'));
      expect(spec, isNot(contains('AUTH_BIOMETRIC')));
      expect(spec, isNot(contains('setUserAuthenticationParameters')));
      final make = _ktFun('deviceKey');
      expect(make, contains('FEATURE_STRONGBOX_KEYSTORE'));
      expect(make, contains('deviceKeySpec(alias, true)'));
      // The read never mints a key: a sealed item whose key is gone fails.
      expect(_ktFun('deviceItemRead'), contains('create = false'));
      expect(_ktFun('deviceItemRead'), contains('throw IllegalStateException'));

      // iOS: the plugin's Keychain, its own service, no access control.
      final apple = KeychainKeyStore.appleDeviceKeys.toMap();
      expect(apple['accessibility'], 'first_unlock_this_device');
      expect(apple['synchronizable'], 'false');
      expect(apple.containsKey('accessControlFlags'), isFalse);
      expect(apple['accountName'], 'rukka_folio_device_keys');
      expect(
        KeychainKeyStore.appleBase.toMap()['accountName'],
        isNot(apple['accountName']),
      );
    });

    test(
      'C-1006-1 on iOS the device-key items go to the Keychain service of '
      'their own with no access-control flags, never to the app channel',
      () async {
        final calls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final data = <String, String>{};
        messenger.setMockMethodCallHandler(pluginChannel, (call) async {
          calls.add(call);
          final a = call.arguments as Map;
          final o = (a['options'] as Map).cast<String, String>();
          final k = '${o['accountName']}/${a['key']}';
          switch (call.method) {
            case 'write':
              data[k] = a['value'] as String;
            case 'read':
              return data[k];
            case 'containsKey':
              return data.containsKey(k);
          }
          return null;
        });
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        FlutterSecureStoragePlatform.instance =
            MethodChannelFlutterSecureStorage();
        final keys = KeychainKeyStore(storage: const FlutterSecureStorage());
        expect(await keys.unsealIfNoPin(), isTrue);
        for (final id in _items) {
          await keys.write(id, _sign);
          expect(await keys.read(id), _sign);
        }
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final device = [
          for (final c in calls)
            if (_items.any(((c.arguments as Map)['key'] as String).endsWith)) c,
        ];
        expect(device, isNotEmpty);
        for (final c in device) {
          final o = ((c.arguments as Map)['options'] as Map)
              .cast<String, String>();
          expect(o['accountName'], 'rukka_folio_device_keys');
          expect(o['accessibility'], 'first_unlock_this_device');
          expect(o['synchronizable'], 'false');
          expect(o.containsKey('accessControlFlags'), isFalse);
        }
        expect(
          android.native.where((c) => c.method.startsWith('deviceItem')),
          isEmpty,
        );
      },
    );
  });

  group('ruling 2 — the gate', () {
    test('C-1006-2 the gate is minted only behind the PIN set at O4b and only '
        'with a qualifying biometric — a PIN-only phone has none (S15 asks for '
        'the PIN without prompting); its native item needs BIOMETRIC_STRONG on '
        'every use and dies with any enrolment change (iOS biometryCurrentSet, '
        'no passcode); reading it reads no device-key item; and a phone that '
        'enrols a finger later gets its gate at the next PIN with no key '
        'moved', () async {
      for (final enrolled in [true, false]) {
        android = AndroidKeystoreEmulator(enrolled: enrolled)..install();
        final keys = process();
        await firstRun(keys);
        expect(
          android.nativeMethods,
          isNot(contains('armBiometricGate')),
          reason: 'no gate before the PIN exists',
        );
        expect(await keys.gateArmed(), isFalse);

        final vault = await vaultOver(keys);
        // A wrong PIN mints nothing — there is no PIN yet to be wrong about,
        // so set it, then try a wrong one on a new process.
        await vault.setPin(_pin);
        await vault.pendingAfterPin;
        expect(android.gateMinted, enrolled, reason: 'enrolled: $enrolled');
        expect(await keys.gateArmed(), enrolled);
        expect(
          promptless(KeychainKeyStore.gateItemId),
          enrolled ? 'armed' : isNull,
        );
        final gate = KeystoreBiometricGate(
          keys: keys,
          platform: const MethodChannelKeystorePlatform(),
        );
        android.native.clear();
        if (enrolled) {
          expect(
            await gate.authenticate(reason: 'Unlock Rukka Folio'),
            BiometricOutcome.success,
          );
          final read = android.native.singleWhere(
            (c) => c.method == 'authenticate',
          );
          expect(read.arguments, {
            'title': 'Unlock Rukka Folio',
            'subtitle': 'Touch',
            'cancel': 'Use PIN',
          });
          // The gate read opens no data: no device-key item crossed.
          expect(android.nativeMethods, ['authenticate']);
        } else {
          expect(
            await gate.authenticate(reason: 'x'),
            BiometricOutcome.pinOnly,
          );
          expect(android.nativeMethods, isEmpty, reason: 'nothing prompted');

          // A finger enrolled later: the next verified PIN mints the gate,
          // and no device-key item is written, read or moved by it.
          android.enrolled = true;
          final k = process();
          final v = await vaultOver(k);
          expect(await v.verify('000000'), isA<PinRejected>());
          await v.pendingAfterPin;
          expect(android.gateMinted, isFalse, reason: 'a wrong PIN mints none');
          android.native.clear();
          expect(await v.verify(_pin), isA<PinAccepted>());
          await v.pendingAfterPin;
          expect(android.gateMinted, isTrue);
          expect(
            android.nativeMethods.where((m) => m.startsWith('deviceItem')),
            isEmpty,
          );
        }
      }

      // The native gate (RukkaKeystoreChannel.kt): the same spec as the
      // enrolment probe — strong biometric on every use, invalidated by
      // enrolment — and a read answers success only after the authenticated
      // cipher ran.
      final spec = _ktFun('biometricSpec');
      expect(spec, contains('.setUserAuthenticationRequired(true)'));
      expect(spec, contains('AUTH_BIOMETRIC_STRONG'));
      expect(spec, contains('setInvalidatedByBiometricEnrollment(true)'));
      expect(spec, isNot(contains('DEVICE_CREDENTIAL')));
      expect(_ktFun('armBiometricGate'), contains('biometricSpec(alias)'));
      final auth = _ktFun('authenticate');
      expect(auth, contains('BIOMETRIC_STRONG'));
      expect(auth, contains('doFinal'));
      expect(auth, isNot(contains('DEVICE_CREDENTIAL')));
      // iOS: a biometryCurrentSet item of 32 random bytes, passcode never
      // offered.
      final swift = _swift();
      expect(swift, contains('.biometryCurrentSet'));
      expect(
        swift,
        contains('kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly'),
      );
      expect(swift, contains('SecRandomCopyBytes(kSecRandomDefault, 32'));
      expect(swift, contains('context.localizedFallbackTitle = ""'));
      expect(swift, isNot(contains('.deviceOwnerAuthentication,')));
      expect(swift, isNot(contains('.devicePasscode')));
    });
  });

  group('ruling 3 — sealed until the gate or the MPIN', () {
    test('C-1006-3 a new process holds the device keys sealed: every read, '
        'write, delete and contains throws DeviceKeysSealed and reaches no '
        'channel, the ledger cannot reopen (no unwrap), a cancelled or failed '
        'gate read and a wrong PIN leave it sealed, and only the gate read '
        'with the biometric or a verified MPIN opens it', () async {
      android.enrolled = true;
      final first = process();
      final ledger = await firstRun(first);
      await (await vaultOver(first)).setPin(_pin);

      var keys = process();
      expect(keys.sealed, isTrue);
      expect(await keys.unsealIfNoPin(), isFalse, reason: 'a PIN exists');
      android
        ..wire.clear()
        ..native.clear();
      for (final id in _items) {
        await expectLater(keys.read(id), throwsA(isA<DeviceKeysSealed>()));
        await expectLater(
          keys.write(id, _sign),
          throwsA(isA<DeviceKeysSealed>()),
        );
        await expectLater(keys.delete(id), throwsA(isA<DeviceKeysSealed>()));
        await expectLater(keys.contains(id), throwsA(isA<DeviceKeysSealed>()));
      }
      expect(
        android.nativeMethods.where((m) => m.startsWith('deviceItem')),
        isEmpty,
      );
      final reopen = LocalLedger(
        db: ledger.db,
        keys: keys,
        suite: await testSuite(),
        now: testNow,
      );
      await expectLater(
        reopen.bootstrapSolo(),
        throwsA(isA<DeviceKeysSealed>()),
      );
      expect(
        DeviceKeysSealed(KeyIds.deviceSigningKey).toString(),
        'DeviceKeysSealed(${KeyIds.deviceSigningKey})',
      );

      // Cancelled, failed, unavailable gate reads: still sealed.
      android.gateAnswers.addAll(['cancelled', 'failed', 'unavailable']);
      for (final a in [
        PlatformBiometricAnswer.cancelled,
        PlatformBiometricAnswer.failed,
        PlatformBiometricAnswer.unavailable,
      ]) {
        expect(await keys.openWithGate(), a);
        expect(keys.sealed, isTrue);
        await expectLater(
          keys.read(KeyIds.deviceSigningKey),
          throwsA(isA<DeviceKeysSealed>()),
        );
      }
      // A wrong PIN: still sealed. The right one: open, synchronously with
      // the PIN's answer.
      final vault = await vaultOver(keys);
      expect(await vault.verify('000000'), isA<PinRejected>());
      expect(keys.sealed, isTrue);
      expect(await vault.verify(_pin), isA<PinAccepted>());
      expect(keys.sealed, isFalse);
      expect((await reopen.bootstrapSolo()).deviceId, ledger.identity.deviceId);

      // A new process, opened by the gate read alone.
      keys = process();
      expect(await keys.openWithGate(), PlatformBiometricAnswer.success);
      expect(keys.sealed, isFalse);
      expect(await keys.read(KeyIds.deviceAgreementKey), isNotNull);
    });
  });

  group('ruling 4 — an enrolment change costs only the gate', () {
    test('C-1006-4 a second fingerprint invalidates the gate only: the gate '
        'read answers re-enrolled, the MPIN opens and mints a new gate for the '
        'set enrolled now (none once every biometric is removed), the device '
        'keys and UMK copy are byte-identical before and after, and the native '
        'reset touches the gate and nothing else', () async {
      android.enrolled = true;
      final first = process();
      final ledger = await firstRun(first);
      final vault0 = await vaultOver(first);
      await vault0.setPin(_pin);
      await vault0.pendingAfterPin;
      final before = hwSnapshot();
      final legacyBefore = Map.of(android.stored);

      // A second fingerprint (adb emu finger touch 2 enrolled in Settings).
      android.changeEnrolment();
      var keys = process();
      final gate = KeystoreBiometricGate(
        keys: keys,
        platform: const MethodChannelKeystorePlatform(),
      );
      expect(await gate.authenticate(reason: 'x'), BiometricOutcome.reenrolled);
      expect(keys.sealed, isTrue);
      expect(
        android.gateMinted,
        isFalse,
        reason: 'the native gate removed itself',
      );
      expect(
        await keys.gateArmed(),
        isTrue,
        reason: 'the record still says so',
      );
      // Asking again before the PIN still answers re-enrolled (never PIN-only,
      // never success).
      expect(await gate.authenticate(reason: 'x'), BiometricOutcome.reenrolled);

      var vault = await vaultOver(keys);
      expect(await vault.verify(_pin), isA<PinAccepted>());
      await vault.pendingAfterPin;
      expect(android.gateMinted, isTrue, reason: 'a new gate, current set');
      expect(android.gateInvalid, isFalse);
      expect(hwSnapshot(), before, reason: 'device keys and UMK untouched');
      final reopened = LocalLedger(
        db: ledger.db,
        keys: keys,
        suite: await testSuite(),
        now: testNow,
      );
      expect(
        (await reopened.bootstrapSolo()).deviceId,
        ledger.identity.deviceId,
      );
      // The next cold start opens with the new finger.
      keys = process();
      expect(await keys.openWithGate(), PlatformBiometricAnswer.success);

      // Every biometric removed: the PIN, then no gate — PIN-only.
      android.changeEnrolment(stillEnrolled: false);
      keys = process();
      vault = await vaultOver(keys);
      android.native.clear();
      expect(await vault.verify(_pin), isA<PinAccepted>());
      await vault.pendingAfterPin;
      expect(android.nativeMethods, contains('resetGate'));
      expect(await keys.gateArmed(), isFalse);
      expect(
        await KeystoreBiometricGate(
          keys: keys,
          platform: const MethodChannelKeystorePlatform(),
        ).authenticate(reason: 'x'),
        BiometricOutcome.pinOnly,
      );
      expect(hwSnapshot(), before);
      // The plugin's namespaces are untouched by any of it (the class and gate
      // records aside).
      final pluginNow = Map.of(android.stored)
        ..removeWhere(
          (k, _) => k.contains('rk.device.') || k.contains('rk.pin'),
        );
      final pluginBefore = legacyBefore
        ..removeWhere(
          (k, _) => k.contains('rk.device.') || k.contains('rk.pin'),
        );
      expect(pluginNow, pluginBefore);

      // The native reset (RukkaKeystoreChannel.kt): the gate alias only. The
      // KEY145B namespace reset is gone, and no path deletes the device-key
      // class's key or clears its prefs.
      final kt = _kt();
      final reset = _ktFun('resetGate');
      expect(reset, contains('GATE_ALIAS_SUFFIX'));
      expect(reset, isNot(contains('DEVICE')));
      expect(reset, isNot(contains('getSharedPreferences')));
      expect(kt, isNot(contains('"resetBiometricDeviceItems"')));
      expect(kt, isNot(contains('fun resetBiometricDeviceItems')));
      expect(kt, isNot(contains('.clear()')));
      expect(
        RegExp(r'DEVICE_KEY_ALIAS_SUFFIX[\s\S]{0,200}deleteEntry')
            .allMatches(kt)
            .length,
        lessThanOrEqualTo(1),
        reason: 'only the StrongBox-refused retry removes a half-made key',
      );
      // And the Dart side has no way to ask for it.
      await expectLater(
        const MethodChannel('rukka_folio/keystore')
            .invokeMethod<Object?>('resetBiometricDeviceItems'),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });

  group('ruling 5 — legacy installs move once, behind an unlock', () {
    void legacy(DeviceKeyClass cls) {
      final ns = cls == DeviceKeyClass.legacyBiometric
          ? biometricNs
          : pinOnlyNs;
      android.stored['$promptlessNs/rukka.${KeychainKeyStore.classItemId}'] =
          base64Encode(
            utf8.encode(
              cls == DeviceKeyClass.legacyBiometric ? 'biometric' : 'pin-only',
            ),
          );
      android.stored['$ns/rukka.${KeyIds.deviceSigningKey}'] = base64Encode(
        _sign,
      );
      android.stored['$ns/rukka.${KeyIds.deviceAgreementKey}'] = base64Encode(
        _agree,
      );
      android.stored['$promptlessNs/rukka.${KeyIds.wrappedUmk}'] = base64Encode(
        _umk,
      );
    }

    Future<void> setPinBefore() async {
      final k = KeychainKeyStore(sealed: false);
      await (await vaultOver(k)).setPin(_pin);
    }

    Future<KeychainKeyStore> unlockedLegacy(DeviceKeyClass cls) async {
      final keys = process();
      if (cls == DeviceKeyClass.legacyBiometric) {
        // The cold start opens it the old way: the read prompts.
        expect(await keys.read(KeyIds.deviceSigningKey), _sign);
      } else {
        final v = await vaultOver(keys);
        expect(await v.verify(_pin), isA<PinAccepted>());
        await v.pendingAfterPin;
      }
      expect(keys.sealed, isFalse);
      return keys;
    }

    Future<void> expectOldOpens(DeviceKeyClass cls) async {
      final keys = await unlockedLegacy(cls);
      expect(await keys.recordedClass(), cls);
      expect(await keys.read(KeyIds.deviceSigningKey), _sign);
      expect(await keys.read(KeyIds.deviceAgreementKey), _agree);
      expect(await keys.read(KeyIds.wrappedUmk), _umk);
    }

    test('C-1006-5 a legacy install (biometric-bound, and ADR 2026-10-05b '
        'PIN-only) moves on its next unlock: read, write to the ruling-1 '
        'class, read back and compare, flip the record, mint the gate, and '
        'only then delete the old items — and not before an unlock, nor by '
        'raising a prompt of its own', () async {
      for (final cls in [
        DeviceKeyClass.legacyBiometric,
        DeviceKeyClass.legacyPinOnly,
      ]) {
        android = AndroidKeystoreEmulator(enrolled: true)..install();
        legacy(cls);
        await setPinBefore();

        // Sealed, or a biometric class this process has not opened: deferred,
        // nothing touched, no prompt.
        var keys = process();
        expect(await keys.migrateAfterUnlock(), DeviceKeyMigration.deferred);
        if (cls == DeviceKeyClass.legacyBiometric) {
          keys.unsealAfterPin(); // the PIN alone does not open that class
          expect(await keys.migrateAfterUnlock(), DeviceKeyMigration.deferred);
          expect(android.callsTo(biometricNs), isEmpty);
        }
        expect(android.hw, isEmpty);

        keys = await unlockedLegacy(cls);
        android
          ..wire.clear()
          ..native.clear();
        expect(
          await keys.migrateAfterUnlock(),
          DeviceKeyMigration.migrated,
          reason: '$cls',
        );

        // The order, across both channels.
        final steps = <String>[];
        var w = 0, n = 0;
        // Interleave by replaying the two logs in call order is not possible
        // across channels, so assert each log's own order and the cross-log
        // facts that matter: every hw write and read-back happened before any
        // plugin write of the record, and the deletes after it.
        for (final c in android.native) {
          steps.add(
            '${c.method}:${(c.arguments is Map ? (c.arguments as Map)['id'] : '') ?? ''}',
          );
          n++;
        }
        expect(n, greaterThan(0));
        expect(steps.sublist(0, 6), [
          for (final id in _items) 'deviceItemWrite:$id',
          for (final id in _items) 'deviceItemRead:$id',
        ]);
        expect(
          steps.sublist(6),
          containsAllInOrder([
            'qualifyingBiometricEnrolled:',
            'armBiometricGate:',
          ]),
        );
        final plugin = [
          for (final c in android.wire)
            '${c.method}:${AndroidKeystoreEmulator.nsOf(c)}:'
                '${AndroidKeystoreEmulator.keyOf(c).replaceFirst('rukka.', '')}',
        ];
        w = plugin.indexOf(
          'write:$promptlessNs:${KeychainKeyStore.classItemId}',
        );
        expect(w, greaterThanOrEqualTo(0), reason: '$plugin');
        final ns = cls == DeviceKeyClass.legacyBiometric
            ? biometricNs
            : pinOnlyNs;
        for (final id in [KeyIds.deviceSigningKey, KeyIds.deviceAgreementKey]) {
          expect(plugin.indexOf('delete:$ns:$id'), greaterThan(w), reason: id);
        }
        expect(
          plugin.indexOf('delete:$promptlessNs:${KeyIds.wrappedUmk}'),
          greaterThan(w),
        );
        expect(
          plugin.indexOf('write:$promptlessNs:${KeychainKeyStore.gateItemId}'),
          greaterThan(w),
          reason: 'the gate after the flip',
        );

        // Where everything is now.
        expect(await keys.recordedClass(), DeviceKeyClass.hardware);
        expect(android.hw[KeyIds.deviceSigningKey], _sign);
        expect(android.hw[KeyIds.deviceAgreementKey], _agree);
        expect(android.hw[KeyIds.wrappedUmk], _umk);
        expect(android.stored.keys.where((k) => k.startsWith('$ns/')), isEmpty);
        expect(promptless(KeyIds.wrappedUmk), isNull);
        expect(promptless(KeychainKeyStore.sweepItemId), isNull);
        expect(android.gateMinted, isTrue);

        // The next cold start: the gate, then the same bytes.
        final next = process();
        expect(await next.openWithGate(), PlatformBiometricAnswer.success);
        expect(await next.read(KeyIds.deviceSigningKey), _sign);
        expect(await next.migrateAfterUnlock(), DeviceKeyMigration.notNeeded);
      }
    });

    test('C-1006-5 every failure point before the flip leaves the old items '
        'and record as they were, still opening, and the next unlock moves '
        'them; a delete that fails after the flip is swept at the next unlock '
        '— never a state in which neither copy opens', () async {
      final failures = <String, void Function()>{
        'old read cancelled': () => android.cancelBiometric = 1,
        'hw write fails': () => android.failHwWrites = 1,
        'read-back differs': () => android.corruptHwReads = true,
        'read-back fails': () => android.failHwReads = 1,
        'record flip fails': () =>
            android.failPluginWriteKey = KeychainKeyStore.classItemId,
      };
      for (final cls in [
        DeviceKeyClass.legacyBiometric,
        DeviceKeyClass.legacyPinOnly,
      ]) {
        for (final MapEntry(key: what, value: arm) in failures.entries) {
          if (what == 'old read cancelled' &&
              cls != DeviceKeyClass.legacyBiometric) {
            continue;
          }
          android = AndroidKeystoreEmulator(enrolled: true)..install();
          legacy(cls);
          await setPinBefore();
          final keys = await unlockedLegacy(cls);
          arm();
          final why = '$cls / $what';
          expect(
            await keys.migrateAfterUnlock(),
            DeviceKeyMigration.failedKeptOld,
            reason: why,
          );
          android
            ..corruptHwReads = false
            ..cancelBiometric = 0;
          expect(await keys.recordedClass(), cls, reason: why);
          expect(android.hw, isEmpty, reason: '$why: no half copy left');
          expect(android.gateMinted, isFalse, reason: why);
          await expectOldOpens(cls);

          // The next unlock moves them.
          final again = await unlockedLegacy(cls);
          expect(
            await again.migrateAfterUnlock(),
            DeviceKeyMigration.migrated,
            reason: why,
          );
          expect(
            await process().openWithGate(),
            PlatformBiometricAnswer.success,
          );
        }
      }

      // After the flip: a delete fails → the new copy opens, and the next
      // unlock sweeps the old one.
      android = AndroidKeystoreEmulator(enrolled: true)..install();
      legacy(DeviceKeyClass.legacyPinOnly);
      await setPinBefore();
      android.failPluginDeleteKeys.add(KeyIds.deviceSigningKey);
      final keys = await unlockedLegacy(DeviceKeyClass.legacyPinOnly);
      expect(await keys.migrateAfterUnlock(), DeviceKeyMigration.migrated);
      expect(await keys.read(KeyIds.deviceSigningKey), _sign);
      expect(promptless(KeychainKeyStore.sweepItemId), 'pin-only');
      expect(
        android.stored,
        contains('$pinOnlyNs/rukka.${KeyIds.deviceSigningKey}'),
      );
      android.failPluginDeleteKeys.clear();
      final next = process();
      expect(await next.openWithGate(), PlatformBiometricAnswer.success);
      expect(await next.migrateAfterUnlock(), DeviceKeyMigration.notNeeded);
      expect(
        android.stored.keys.where((k) => k.startsWith('$pinOnlyNs/')),
        isEmpty,
      );
      expect(promptless(KeychainKeyStore.sweepItemId), isNull);
      expect(await next.read(KeyIds.deviceSigningKey), _sign);
    });
  });

  // GATE1 review finding 4: on a phone the engine hands the channel's answer
  // back as an *unmodifiable* view (rf_min: LocalLedger._reopen's zeroize
  // threw UnsupportedError and the second launch went to RukkaFolioBlocked).
  // The emulator above answers through a writable buffer, so this drives the
  // boundary with a reply buffer the way the engine delivers it.
  group('C-1006-1 the device-key read at the channel boundary', () {
    test('C-1006-1 a device-key read whose engine reply is an unmodifiable '
        'view hands back a copy the caller can zeroize (rf_min second-launch '
        'RukkaFolioBlocked)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannelKeystorePlatform.channel;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final seed = Uint8List.fromList(List.generate(32, (i) => i + 9));
      messenger.setMockMessageHandler(channel.name, (message) async {
        final call = channel.codec.decodeMethodCall(message);
        expect(call.method, 'deviceItemRead');
        return channel.codec.encodeSuccessEnvelope(seed).asUnmodifiableView();
      });
      addTearDown(() => messenger.setMockMessageHandler(channel.name, null));

      // The precondition the device showed: the raw answer cannot be wiped.
      final raw = await channel.invokeMethod<Uint8List>('deviceItemRead', {
        'id': KeyIds.deviceSigningKey,
      });
      expect(raw, seed);
      expect(() => raw!.fillRange(0, raw.length, 0), throwsUnsupportedError);

      // What the store hands the ledger: the same bytes, and wipeable.
      final v = await const MethodChannelKeystorePlatform().deviceItemRead(
        KeyIds.deviceSigningKey,
      );
      expect(v, seed);
      v!.fillRange(0, v.length, 0);
      expect(v.every((b) => b == 0), isTrue);
      expect(seed.first, 9, reason: 'the zeroize touched the copy only');
    });
  });
}
