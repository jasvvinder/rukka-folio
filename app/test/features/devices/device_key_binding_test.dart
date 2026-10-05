// ADR 2026-10-05b rulings 1–3 against the real method channels (the
// emulation in keystore_emulator.dart sits under them, F1-05d style).
@Tags(['C'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/keystore_biometric_gate.dart';
import 'package:rukka_folio/features/devices/keystore_platform.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../../shared/test_app.dart';
import 'keystore_emulator.dart';

const _ids = [KeyIds.deviceSigningKey, KeyIds.deviceAgreementKey];
final _sign = Uint8List.fromList(List.generate(32, (i) => i + 1));
final _agree = Uint8List.fromList(List.generate(32, (i) => 200 - i));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AndroidKeystoreEmulator android;
  late KeychainKeyStore keys;

  setUp(() {
    android = AndroidKeystoreEmulator();
    android.install();
    keys = KeychainKeyStore();
  });

  Future<void> mintDeviceKeys() async {
    await keys.write(KeyIds.deviceSigningKey, _sign);
    await keys.write(KeyIds.deviceAgreementKey, _agree);
  }

  String stored(String ns, String id) => android.stored['$ns/rukka.$id']!;
  bool has(String ns, String id) => android.stored.containsKey('$ns/rukka.$id');

  group('ruling 1 — no qualifying biometric → PIN-only, never a dead end', () {
    test('C-1005b-1 with no strong biometric enrolled the device keys are created in the PIN-only class (promptless Keystore, own namespace, no user auth), the binding is recorded first, nothing touches the biometric class — and the next PIN leaves them there', () async {
      android.enrolled = false;
      await mintDeviceKeys();

      // The binding record went first, promptless, then both keys — PIN-only.
      final writes = [
        for (final c in android.wire)
          if (c.method == 'write')
            '${AndroidKeystoreEmulator.nsOf(c)}:'
                '${AndroidKeystoreEmulator.keyOf(c)}',
      ];
      expect(writes, [
        '$promptlessNs:rukka.${KeychainKeyStore.bindingItemId}',
        '$pinOnlyNs:rukka.${KeyIds.deviceSigningKey}',
        '$pinOnlyNs:rukka.${KeyIds.deviceAgreementKey}',
      ]);
      for (final c in android.callsTo(pinOnlyNs)) {
        final o = AndroidKeystoreEmulator.optionsOf(c);
        expect(o['enforceBiometrics'], 'false');
        expect(
          o['keyCipherAlgorithm'],
          'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
        );
        expect(o['resetOnError'], 'false');
        expect(o['migrateOnAlgorithmChange'], 'false');
      }
      expect(android.callsTo(biometricNs), isEmpty);
      expect(await keys.binding(), DeviceKeyBinding.pinOnly);
      expect(await keys.read(KeyIds.deviceSigningKey), _sign);

      // A successful PIN on a phone that still has no biometric: the
      // capability is asked of the platform and the keys stay put. Were the
      // check skipped, the emulated Keystore would refuse the biometric write
      // and this would read failedKeptPinOnly with biometric-class traffic.
      expect(await keys.upgradeAfterPin(), DeviceKeyUpgrade.stayedPinOnly);
      expect(
        android.native.map((c) => c.method),
        contains('qualifyingBiometricEnrolled'),
      );
      expect(android.callsTo(biometricNs), isEmpty);
      expect(await keys.binding(), DeviceKeyBinding.pinOnly);
      expect(await keys.read(KeyIds.deviceAgreementKey), _agree);

      // The S15 gate reads the same record: PIN-only, nothing prompted.
      final gate = KeystoreBiometricGate(
        keys: keys,
        platform: const MethodChannelKeystorePlatform(),
      );
      expect(await gate.authenticate(reason: 'x'), BiometricOutcome.pinOnly);
      expect(await gate.qualifyingBiometricEnrolled(), isFalse);

      // iOS: the PIN-only class is this-device-only, never iCloud, no access
      // control, and its own Keychain service (so both copies can coexist
      // during an upgrade).
      final apple = KeychainKeyStore.applePinOnly.toMap();
      expect(apple['accessibility'], 'first_unlock_this_device');
      expect(apple['synchronizable'], 'false');
      expect(apple.containsKey('accessControlFlags'), isFalse);
      expect(apple['accountName'], 'rukka_folio_device_pin');
      expect(
        KeychainKeyStore.appleBiometric.toMap()['accountName'],
        isNot(apple['accountName']),
      );
    });
  });

  group('ruling 2 — the upgrade happens only behind the PIN', () {
    test('C-1005b-2 after a biometric is enrolled, only a successful MPIN upgrades: the keys are re-created biometric-bound and read back before the PIN-only items are deleted; a cancelled prompt or a bad read-back keeps the PIN-only items; a wrong PIN or a biometric success alone changes nothing', () async {
      android.enrolled = false;
      await mintDeviceKeys();
      final vault = PinVault(
        keys: keys,
        suite: await testSuite(),
        now: () => DateTime.utc(2026, 10, 5),
        afterPinProven: () async {
          await keys.upgradeAfterPin();
        },
      );
      await vault.setPin('135790');
      await vault.pendingAfterPin; // O4b on a PIN-only phone
      expect(await keys.binding(), DeviceKeyBinding.pinOnly);

      // A fingerprint is enrolled in Settings.
      android.enrolled = true;

      // A biometric success alone (the cold-start admission) never upgrades.
      final gate = KeystoreBiometricGate(
        keys: keys,
        platform: const MethodChannelKeystorePlatform(),
      )..admitOnce();
      await gate.authenticate(reason: 'x');
      expect(await keys.binding(), DeviceKeyBinding.pinOnly);
      expect(android.callsTo(biometricNs), isEmpty);

      // A wrong PIN changes nothing.
      expect(await vault.verify('000000'), isA<PinRejected>());
      expect(android.callsTo(biometricNs), isEmpty);
      expect(await keys.binding(), DeviceKeyBinding.pinOnly);

      // The prompt is cancelled part-way: PIN-only stays, and still opens.
      android.cancelBiometric = 1;
      expect(await vault.verify('135790'), isA<PinAccepted>());
      await vault.pendingAfterPin;
      expect(await keys.binding(), DeviceKeyBinding.pinOnly);
      expect(has(pinOnlyNs, KeyIds.deviceSigningKey), isTrue);
      expect(await keys.read(KeyIds.deviceSigningKey), _sign);

      // A read-back that differs: PIN-only stays.
      android.corruptBiometricReads = true;
      expect(await keys.upgradeAfterPin(), DeviceKeyUpgrade.failedKeptPinOnly);
      expect(await keys.binding(), DeviceKeyBinding.pinOnly);
      expect(await keys.read(KeyIds.deviceAgreementKey), _agree);
      android.corruptBiometricReads = false;
      // That attempt opened the biometric namespace in this process, so a
      // retry here would not reset it under the plugin's cached cipher; the
      // next launch is a new process.
      expect(keys.biometricNamespaceOpened, isTrue);
      keys = KeychainKeyStore();

      // The next successful PIN upgrades — in order.
      android.wire.clear();
      android.native.clear();
      expect(await vault.verify('135790'), isA<PinAccepted>());
      await vault.pendingAfterPin;
      expect(await keys.binding(), DeviceKeyBinding.biometric);
      final steps = [
        for (final c in android.wire)
          '${c.method}:${AndroidKeystoreEmulator.nsOf(c)}:'
              '${AndroidKeystoreEmulator.keyOf(c).replaceFirst('rukka.', '')}',
      ];
      int at(String step) => steps.indexOf(step);
      final readBack = [for (final id in _ids) at('read:$biometricNs:$id')];
      final deletes = [for (final id in _ids) at('delete:$pinOnlyNs:$id')];
      final flip = steps.lastIndexOf(
        'write:$promptlessNs:${KeychainKeyStore.bindingItemId}',
      );
      for (final id in _ids) {
        expect(at('write:$biometricNs:$id'), greaterThanOrEqualTo(0));
      }
      expect(readBack.every((i) => i >= 0), isTrue, reason: '$steps');
      expect(deletes.every((i) => i >= 0), isTrue, reason: '$steps');
      expect(flip, greaterThan(readBack.reduce((a, b) => a > b ? a : b)));
      expect(deletes.reduce((a, b) => a < b ? a : b), greaterThan(flip));
      // The biometric class went on the strong-biometric option set, with
      // the stale namespace reset through the app's channel first.
      expect(android.native.map((c) => c.method), [
        'qualifyingBiometricEnrolled',
        'resetBiometricDeviceItems',
      ]);
      for (final c in android.callsTo(biometricNs)) {
        expect(
          AndroidKeystoreEmulator.optionsOf(c)['enforceBiometrics'],
          'true',
        );
        expect(
          AndroidKeystoreEmulator.optionsOf(c)['biometricType'],
          'strongBiometricOnly',
        );
      }
      expect(has(pinOnlyNs, KeyIds.deviceSigningKey), isFalse);
      expect(has(pinOnlyNs, KeyIds.deviceAgreementKey), isFalse);
      expect(stored(biometricNs, KeyIds.deviceSigningKey), base64Encode(_sign));
      expect(await keys.read(KeyIds.deviceSigningKey), _sign);
      expect(await keys.read(KeyIds.deviceAgreementKey), _agree);

      // And from now on a PIN finds nothing to do.
      expect(await keys.upgradeAfterPin(), DeviceKeyUpgrade.notNeeded);
    });
  });

  group('ruling 3 — losing the biometric drops back, through the PIN', () {
    Future<void> biometricPhone() async {
      android.enrolled = true;
      await mintDeviceKeys();
      expect(await keys.upgradeAfterPin(), DeviceKeyUpgrade.upgraded);
      // A new process: the plugin's cached cipher is gone.
      keys = KeychainKeyStore();
    }

    test('C-1005b-3 an invalidated biometric item reads as KeyStoreInvalidated, the plugin cannot even delete it, nothing is removed before the PIN, and after it the app\'s own reset clears it and the next device keys land in the class the phone qualifies for now — biometric if one is enrolled, PIN-only if none is', () async {
      for (final stillEnrolled in [true, false]) {
        android = AndroidKeystoreEmulator()..install();
        keys = KeychainKeyStore();
        await biometricPhone();

        // An enrolment change (or every biometric removed).
        android.invalidated = true;
        android.enrolled = stillEnrolled;
        android.native.clear();
        await expectLater(
          keys.read(KeyIds.deviceSigningKey),
          throwsA(isA<KeyStoreInvalidated>()),
        );
        // The plugin's own delete runs initialise first and fails too —
        // why the app has its own reset (RukkaKeystoreChannel.kt).
        await expectLater(
          keys.delete(KeyIds.deviceSigningKey),
          throwsA(isA<Object>()),
        );
        expect(
          android.native.map((c) => c.method),
          isNot(contains('resetBiometricDeviceItems')),
          reason: 'nothing is removed before the PIN',
        );

        // The PIN was accepted (the cold-start gate's job): drop and re-pick.
        final next = await keys.dropInvalidatedAfterPin();
        expect(android.native.map((c) => c.method), [
          'resetBiometricDeviceItems',
          'qualifyingBiometricEnrolled',
        ]);
        expect(
          android.stored.keys.where((k) => k.startsWith('$biometricNs/')),
          isEmpty,
        );
        expect(
          next,
          stillEnrolled ? DeviceKeyBinding.biometric : DeviceKeyBinding.pinOnly,
        );
        expect(await keys.binding(), next);

        // Re-created in that class (the material is the recovery ladder's to
        // mint — ⚠️ SPEC in keychain_key_store.dart; any bytes stand in here).
        android.wire.clear();
        await keys.write(KeyIds.deviceSigningKey, _agree);
        final ns = stillEnrolled ? biometricNs : pinOnlyNs;
        expect(
          android.wire
              .where((c) => c.method == 'write')
              .map(AndroidKeystoreEmulator.nsOf)
              .toSet(),
          {ns},
          reason: 'still enrolled: $stillEnrolled',
        );
        expect(await keys.read(KeyIds.deviceSigningKey), _agree);
      }
      expect(defaultTargetPlatform, TargetPlatform.android);
    });
  });
}
