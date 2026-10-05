// ADR 2026-10-05b on screen: the S15 PIN-only variant (ruling 1), and the
// cold start that never ends at a blocked screen (ruling 4). Driven over the
// real method channels through the emulation in
// test/features/devices/keystore_emulator.dart.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
import 'package:rukka_folio/features/devices/keystore_platform.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/cold_start_gate.dart';
import 'package:rukka_folio/features/lock/keystore_biometric_gate.dart';
import 'package:rukka_folio/features/lock/screens/s15_lock_screen.dart';
import 'package:rukka_folio/features/lock/widgets/pin_pad.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_8_set_pin_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/widgets/blocked_screen.dart';

import '../../shared/test_app.dart';
import '../devices/keystore_emulator.dart';
import 'lock_harness.dart';

const _small = Size(360, 800);

void main() {
  group('F1-1005b-1 S15 PIN-only variant (ADR 2026-10-05b §1)', () {
    testWidgets('F1-1005b-1 a PIN-only phone gets the PIN boxes and keypad from the '
        'first answer, no biometric button or line (also in cooldown), a line '
        'saying why, and S0.8 states the PIN-only form — EN/PA/HI at 200% on '
        '360x800', (tester) async {
      final android = AndroidKeystoreEmulator(enrolled: false)..install();
      final keys = KeychainKeyStore();
      await tester.runAsync(
        () => keys.write(KeyIds.deviceSigningKey, Uint8List.fromList([1])),
      );
      expect(await tester.runAsync(keys.binding), DeviceKeyBinding.pinOnly);
      final gate = KeystoreBiometricGate(
        keys: keys,
        platform: const MethodChannelKeystorePlatform(),
      );

      for (final locale in lockLocales) {
        final l10n = lookupAppLocalizations(locale);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        await vault.pendingAfterPin;
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: gate,
          clock: clock,
          locale: locale,
          textScale: 2,
          viewport: _small,
        );
        final why = '${locale.languageCode} @ 200% on 360x800';
        expect(tester.takeException(), isNull, reason: why);
        expect(find.byType(PinBoxes), findsOneWidget, reason: why);
        expect(find.byType(PinKeypad), findsOneWidget, reason: why);
        expect(find.text(l10n.lockBiometricButton), findsNothing, reason: why);
        expect(find.text(l10n.lockBiometricUnavailable), findsNothing);
        expect(find.text(l10n.lockPinOnlyNote), findsOneWidget, reason: why);
        expectTextFits(tester, reason: why);
        // The forgot door on a PIN-only phone says the recovery-ladder
        // reading (desk 147), not "a code and Face ID".
        await tester.ensureVisible(find.text(l10n.lockForgotAction));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.lockForgotAction));
        await tester.pumpAndSettle();
        expect(find.text(l10n.lockForgotBodyPinOnly), findsOneWidget);
        expect(find.text(l10n.lockForgotBody), findsNothing);
        expectTextFits(tester, reason: '$why forgot');
        await unmount(tester);

        // Cooldown: the wait is the only way forward — no face offered.
        for (var i = 0; i < 5; i++) {
          await vault.verify('000000');
        }
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: gate,
          clock: clock,
          locale: locale,
          textScale: 2,
          viewport: _small,
        );
        expect(find.text(l10n.lockCooldownTitle), findsOneWidget);
        expect(find.text(l10n.lockBiometricButton), findsNothing, reason: why);
        expectTextFits(tester, reason: '$why cooldown');
        await unmount(tester);

        // S0.8 states the PIN-only form of the app-lock line.
        await pumpLock(
          tester,
          const SetPinScreen(),
          vault: await makeVault(clock),
          biometrics: gate,
          clock: clock,
          locale: locale,
          textScale: 2,
          viewport: _small,
        );
        expect(
          find.text(l10n.onboardingSetPinBiometricNotePinOnly),
          findsOneWidget,
          reason: why,
        );
        expect(find.text(l10n.onboardingSetPinBiometricNote), findsNothing);
        expectTextFits(tester, reason: '$why S0.8');
        await unmount(tester);
      }

      // The same screen on a biometric-bound phone keeps its biometric
      // button — the variant is the binding's, not the screen's default — and
      // the button is live: it raises the platform prompt (KEY145B finding 3).
      await tester.runAsync(() async {
        android.stored['$promptlessNs/rukka.${KeychainKeyStore.bindingItemId}'] =
            base64Encode(utf8.encode('biometric'));
      });
      final en = lookupAppLocalizations(const Locale('en'));
      keys.setPromptCopy(
        title: en.lockBiometricPrompt,
        subtitle: en.lockBiometricSheetSubtitle,
        cancel: en.lockPinUseInstead,
      );
      android
        ..gateArmed = true
        ..gateAnswers.add('cancelled');
      final clock = TestClock();
      final vault = await makeVault(clock);
      await vault.setPin('135790');
      await vault.pendingAfterPin;
      var unlocked = 0;
      await pumpLock(
        tester,
        LockScreen(onUnlocked: () => unlocked++, onForgotPin: () {}),
        vault: vault,
        biometrics: gate,
        clock: clock,
        viewport: _small,
      );
      expect(find.text('Face ID'), findsOneWidget);
      expect(find.text(en.lockPinOnlyNote), findsNothing);
      expect(find.text(en.lockBiometricUnavailable), findsNothing);
      expect(unlocked, 0, reason: 'the auto-prompt was cancelled');
      await tester.tap(find.text('Face ID'));
      await tester.pumpAndSettle();
      expect(unlocked, 1, reason: 'the Face ID button prompts and unlocks');
      expect(android.native.where((c) => c.method == 'authenticate').length, 2);
      await unmount(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('F1-1005b-2 no person-bound item before O4b; a cancelled prompt '
      'reaches Use PIN instead (ADR 2026-10-05b §4)', () {
    // ⚠️ SPEC (KEY145B review finding 2; owner): ruling 4 and 07 §5.6 🔒 also
    // say the device keys are minted *after O4b*, never at bootstrap. They are
    // not: S0.2's device registration (ADR 2026-09-16 §2, 06 §3) needs them
    // first (bootstrap.dart). This test pins only ruling 4's heading — no
    // keystore item that needs the person before the PIN — and says so; the
    // literal line is the skipped test below, not a green one.
    test('F1-1005b-2 (ruling 4 heading only) first run on a phone WITH a '
        'fingerprint: bootstrapSolo mints the device keys at bootstrap, into '
        'the promptless PIN-only class — nothing reaches the biometric class '
        'and no prompt can rise — and only the PIN set at O4b binds them to '
        'the biometric', () async {
      final android = AndroidKeystoreEmulator(enrolled: true)..install();
      final keys = KeychainKeyStore();
      final ledger = LocalLedger(
        db: await openTestDb(),
        keys: keys,
        suite: await testSuite(),
        now: testNow,
      );
      addTearDown(ledger.dispose);
      await ledger.bootstrapSolo();

      expect(android.callsTo(biometricNs), isEmpty);
      expect(
        android.wire.where(
          (c) =>
              AndroidKeystoreEmulator.optionsOf(c)['enforceBiometrics'] ==
              'true',
        ),
        isEmpty,
      );
      expect(
        android.stored.keys,
        containsAll([
          '$pinOnlyNs/rukka.${KeyIds.deviceSigningKey}',
          '$pinOnlyNs/rukka.${KeyIds.deviceAgreementKey}',
        ]),
      );
      expect(await keys.binding(), DeviceKeyBinding.pinOnly);

      // O4b: the PIN is set → the keys move behind the biometric.
      final vault = PinVault(
        keys: keys,
        suite: await testSuite(),
        now: testNow,
        afterPinProven: () async {
          await keys.upgradeAfterPin();
        },
      );
      await vault.setPin('135790');
      await vault.pendingAfterPin;
      expect(await keys.binding(), DeviceKeyBinding.biometric);
      expect(
        android.stored.keys.where((k) => k.startsWith('$pinOnlyNs/')),
        isEmpty,
      );
      expect(
        android.stored.keys,
        contains('$biometricNs/rukka.${KeyIds.deviceSigningKey}'),
      );

      // And the next launch reopens the same identity through them.
      final again = LocalLedger(
        db: ledger.db,
        keys: KeychainKeyStore(),
        suite: await testSuite(),
        now: testNow,
      );
      expect((await again.bootstrapSolo()).deviceId, ledger.identity.deviceId);
    });

    test(
      'F1-1005b-2 device keys are minted after O4b, never at bootstrap',
      () {},
      skip:
          '⚠️ SPEC (KEY145B review finding 2): not delivered — S0.2 registers '
          "the ledger's device keys with the server before O4b (ADR 2026-09-16 "
          '§2, 06 §3, 13 §5 F1); minting after O4b needs an auth / onboarding '
          'order ruling by the owner. bootstrap.dart carries the marker.',
    );

    test('F1-1005b-2 the composition root opens a biometric-bound ledger only '
        'behind the cold-start S15, hands every successful PIN to the upgrade, '
        'and gives the in-app S15 the custody gate (root pin)', () {
      final root = File('lib/bootstrap.dart').readAsStringSync();
      final gate = root.indexOf('ColdStartGate(');
      final open = root.indexOf('identity = await ledger.bootstrapSolo()');
      expect(gate, greaterThan(0));
      expect(open, greaterThan(gate), reason: 'S15 before the device-key read');
      expect(root, contains('open: () => ledger.bootstrapSolo()'));
      expect(
        RegExp(r'afterPinProven:[^;]*keys\.upgradeAfterPin\(\)').hasMatch(root),
        isTrue,
      );
      expect(root, contains('biometrics: biometricGate'));
      expect(root, contains('biometricGate.admitOnce()'));
      // The relock prompt is armed only behind a proof (KEY145B finding 3):
      // in afterPinProven, and after the cold-start read.
      expect(
        RegExp(
          r'afterPinProven:[^;]*keys\.upgradeAfterPin\(\);\s*await biometricGate\.armAfterProof\(\)',
        ).hasMatch(root),
        isTrue,
      );
      expect(
        RegExp(
          r'biometricGate\.admitOnce\(\);\s*await biometricGate\.armAfterProof\(\)',
        ).hasMatch(root),
        isTrue,
      );
      expect(root, contains('!= ColdStartResult.opened'));
    });

    testWidgets(
      'F1-1005b-2 cold start on a biometric-bound phone: S15 is up before the '
      'device keys are read, a cancelled prompt leaves Use PIN instead (never '
      'RukkaFolioBlocked), and after the PIN the biometric opens the books',
      (tester) async {
        final android = AndroidKeystoreEmulator(enrolled: true)..install();
        android.stored['$promptlessNs/rukka.${KeychainKeyStore.bindingItemId}'] =
            base64Encode(utf8.encode('biometric'));
        android.stored['$biometricNs/rukka.${KeyIds.deviceSigningKey}'] =
            base64Encode([1, 2, 3]);
        final keys = KeychainKeyStore();
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        await vault.pendingAfterPin;
        final l10n = lookupAppLocalizations(const Locale('en'));

        var opens = 0;
        ColdStartResult? result;
        android.cancelBiometric = 1;
        await tester.pumpWidget(
          ColdStartApp(
            locale: const Locale('en'),
            child: ColdStartGate(
              vault: vault,
              // The read the ledger's reopen does first — the prompt.
              open: () async {
                opens++;
                final k = await keys.read(KeyIds.deviceSigningKey);
                if (k == null) throw DeviceKeysMissing();
              },
              dropInvalidated: keys.dropInvalidatedAfterPin,
              onDone: (r) => result = r,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(opens, 1, reason: 'S15 raised the prompt itself');
        expect(find.byType(LockScreen), findsOneWidget);
        expect(find.byType(RukkaFolioBlocked), findsNothing);
        expect(find.byType(PinKeypad), findsOneWidget);
        expect(result, isNull);

        // Use PIN instead → the PIN → the keys still want the biometric,
        // which this time succeeds.
        await typePin(tester, '135790');
        await tester.pumpAndSettle();
        expect(result, ColdStartResult.opened);
        expect(opens, 2);
        expect(find.byType(RukkaFolioBlocked), findsNothing);

        // Cancelled again after the PIN: the screen says why and offers the
        // biometric again — still no dead end.
        result = null;
        opens = 0;
        android.cancelBiometric = 2;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ColdStartApp(
            locale: const Locale('en'),
            child: ColdStartGate(
              vault: vault,
              open: () async {
                opens++;
                await keys.read(KeyIds.deviceSigningKey);
              },
              dropInvalidated: keys.dropInvalidatedAfterPin,
              onDone: (r) => result = r,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await typePin(tester, '135790');
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.text(l10n.lockKeysNeedBiometric), findsOneWidget);
        await tester.tap(find.text(l10n.lockBiometricRetry));
        await tester.pumpAndSettle();
        expect(result, ColdStartResult.opened);

        // The prompt's own "Use PIN instead" (its negative button) never
        // answers on 11.2.0: S15's *Use PIN instead* and the pad still work,
        // and after the PIN a fresh prompt opens the books.
        result = null;
        opens = 0;
        android.hangBiometric = 1;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ColdStartApp(
            locale: const Locale('en'),
            child: ColdStartGate(
              vault: vault,
              open: () async {
                opens++;
                await keys.read(KeyIds.deviceSigningKey);
              },
              dropInvalidated: keys.dropInvalidatedAfterPin,
              onDone: (r) => result = r,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(opens, 1);
        await tester.tap(find.text(l10n.lockPinUseInstead));
        await tester.pump();
        await typePin(tester, '135790');
        await tester.pump();
        expect(result, ColdStartResult.opened);
        expect(opens, 2);

        // Invalidated: S15 goes to the PIN with the re-enrolment line, and only
        // after the PIN are the items removed (ruling 3).
        result = null;
        android.invalidated = true;
        android.native.clear();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ColdStartApp(
            locale: const Locale('en'),
            child: ColdStartGate(
              vault: vault,
              open: () async {
                await keys.read(KeyIds.deviceSigningKey);
              },
              dropInvalidated: () async {
                await keys.dropInvalidatedAfterPin();
              },
              onDone: (r) => result = r,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.lockBiometricReenrolled), findsOneWidget);
        expect(
          android.native.map((c) => c.method),
          isNot(contains('resetBiometricDeviceItems')),
        );
        await typePin(tester, '135790');
        await tester.pumpAndSettle();
        expect(result, ColdStartResult.keysLost);
        expect(
          android.native.map((c) => c.method),
          contains('resetBiometricDeviceItems'),
        );
        expect(find.byType(RukkaFolioBlocked), findsNothing);
        await unmount(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });

  group('KEY145B review repairs over the platform channels', () {
    // A biometric-bound phone as the cold-start gate finds it.
    AndroidKeystoreEmulator boundPhone() {
      final android = AndroidKeystoreEmulator(enrolled: true)..install();
      android.stored['$promptlessNs/rukka.${KeychainKeyStore.bindingItemId}'] =
          base64Encode(utf8.encode('biometric'));
      android.stored['$biometricNs/rukka.${KeyIds.deviceSigningKey}'] =
          base64Encode([1, 2, 3]);
      android.stored['$biometricNs/rukka.${KeyIds.deviceAgreementKey}'] =
          base64Encode([4, 5, 6]);
      return android;
    }

    testWidgets('C-1005b-3 a face that was not recognised at cold start (iOS '
        'errSecAuthFailed -25293) is not an invalidation: S15 says so, the PIN '
        'removes nothing, and the biometric then opens the books', (
      tester,
    ) async {
      final android = boundPhone()..failFaceBiometric = 1;
      final keys = KeychainKeyStore();
      final clock = TestClock();
      final vault = await makeVault(clock);
      await vault.setPin('135790');
      await vault.pendingAfterPin;
      final l10n = lookupAppLocalizations(const Locale('en'));
      ColdStartResult? result;
      var dropped = 0;
      await tester.pumpWidget(
        ColdStartApp(
          locale: const Locale('en'),
          child: ColdStartGate(
            vault: vault,
            open: () async {
              final k = await keys.read(KeyIds.deviceSigningKey);
              if (k == null) throw DeviceKeysMissing();
            },
            dropInvalidated: () async {
              dropped++;
              await keys.dropInvalidatedAfterPin();
            },
            onDone: (r) => result = r,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockBiometricFailed), findsOneWidget);
      expect(find.text(l10n.lockBiometricReenrolled), findsNothing);

      await tester.tap(find.text(l10n.lockPinUseInstead));
      await tester.pumpAndSettle();
      await typePin(tester, '135790');
      await tester.pumpAndSettle();
      expect(result, ColdStartResult.opened);
      expect(dropped, 0);
      expect(
        android.native.map((c) => c.method),
        isNot(contains('resetBiometricDeviceItems')),
      );
      expect(
        android.stored.keys,
        containsAll([
          '$biometricNs/rukka.${KeyIds.deviceSigningKey}',
          '$biometricNs/rukka.${KeyIds.deviceAgreementKey}',
        ]),
      );
      await unmount(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'C-1005b-3 the keystore classifies only Android\'s '
      'KeyPermanentlyInvalidated as an invalidation — iOS errSecAuthFailed '
      'and errSecInteractionNotAllowed rethrow as the platform error',
      () async {
        final android = boundPhone()..failFaceBiometric = 1;
        final keys = KeychainKeyStore();
        await expectLater(
          keys.read(KeyIds.deviceSigningKey),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.message,
              'message',
              contains('-25293'),
            ),
          ),
        );
        expect(
          android.stored,
          contains('$biometricNs/rukka.${KeyIds.deviceSigningKey}'),
        );
        android.invalidated = true;
        await expectLater(
          KeychainKeyStore().read(KeyIds.deviceSigningKey),
          throwsA(isA<KeyStoreInvalidated>()),
        );
      },
    );

    testWidgets(
      'C-1005b-3 only the wrapped UMK missing (the device keys read back) '
      'removes nothing: the gate ends at umkMissing without a PIN and the '
      'device keys stay',
      (tester) async {
        final android = boundPhone();
        final keys = KeychainKeyStore();
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        await vault.pendingAfterPin;
        ColdStartResult? result;
        var dropped = 0;
        await tester.pumpWidget(
          ColdStartApp(
            locale: const Locale('en'),
            child: ColdStartGate(
              vault: vault,
              open: () async {
                final k = await keys.read(KeyIds.deviceSigningKey);
                if (k == null) throw DeviceKeysMissing();
                throw DeviceKeysMissing(deviceKeys: false);
              },
              dropInvalidated: () async => dropped++,
              onDone: (r) => result = r,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(result, ColdStartResult.umkMissing);
        expect(dropped, 0);
        expect(
          android.native.map((c) => c.method),
          isNot(contains('resetBiometricDeviceItems')),
        );
        expect(
          android.stored.keys,
          contains('$biometricNs/rukka.${KeyIds.deviceSigningKey}'),
        );
        await unmount(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'F1-07-19 the cold-start forgot door on a biometric phone promises no '
      'code: it says the code comes from inside the app, its action opens the '
      'books with the biometric — EN/PA/HI at 200% on 360x800',
      (tester) async {
        for (final locale in lockLocales) {
          final android = boundPhone()..cancelBiometric = 1;
          final keys = KeychainKeyStore();
          final clock = TestClock();
          final vault = await makeVault(clock);
          await vault.setPin('135790');
          await vault.pendingAfterPin;
          final l10n = lookupAppLocalizations(locale);
          final why = '${locale.languageCode} @ 200% on 360x800';
          ColdStartResult? result;
          tester.view
            ..physicalSize = _small
            ..devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          await tester.pumpWidget(
            ColdStartApp(
              locale: locale,
              child: ColdStartGate(
                vault: vault,
                open: () async {
                  final k = await keys.read(KeyIds.deviceSigningKey);
                  if (k == null) throw DeviceKeysMissing();
                },
                dropInvalidated: keys.dropInvalidatedAfterPin,
                onDone: (r) => result = r,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text(l10n.lockForgotAction));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.lockForgotAction));
          await tester.pumpAndSettle();
          expect(
            find.text(l10n.lockForgotBodyBeforeOpen),
            findsOneWidget,
            reason: why,
          );
          expect(find.text(l10n.lockForgotBody), findsNothing, reason: why);
          expect(find.text(l10n.lockForgotStart), findsNothing, reason: why);
          expect(tester.takeException(), isNull, reason: why);
          expectTextFits(tester, reason: why);
          await tester.tap(find.text(l10n.lockForgotStartBeforeOpen));
          await tester.pumpAndSettle();
          expect(result, ColdStartResult.opened, reason: why);
          expect(
            android.native.map((c) => c.method),
            isNot(contains('resetBiometricDeviceItems')),
          );
          await unmount(tester);
        }
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'F1-07-63 the production gate prompts by itself on the background / '
      'idle relock of a biometric-bound phone — through the app\'s own channel '
      'with the ARB copy, never answering "unavailable" for an enrolled face — '
      'and a changed set needs the PIN once, which re-arms it',
      (tester) async {
        final android = boundPhone();
        final keys = KeychainKeyStore();
        final en = lookupAppLocalizations(const Locale('en'));
        keys.setPromptCopy(
          title: en.lockBiometricPrompt,
          subtitle: en.lockBiometricSheetSubtitle,
          cancel: en.lockPinUseInstead,
        );
        final gate = KeystoreBiometricGate(
          keys: keys,
          platform: const MethodChannelKeystorePlatform(),
        );
        // Bootstrap arms the gate after the cold start proved the set.
        await gate.armAfterProof();
        expect(android.gateArmed, isTrue);

        final clock = TestClock();
        final vault = PinVault(
          keys: FakeKeyStore(),
          suite: await testSuite(),
          now: clock.call,
          afterPinProven: gate.armAfterProof,
        );
        await vault.setPin('135790');
        await vault.pendingAfterPin;
        android.native.clear();

        var unlocked = 0;
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () => unlocked++, onForgotPin: () {}),
          vault: vault,
          biometrics: gate,
          clock: clock,
          viewport: _small,
        );
        expect(unlocked, 1, reason: 'no tap: the relock prompted by itself');
        final call = android.native.singleWhere(
          (c) => c.method == 'authenticate',
        );
        expect(call.arguments, {
          'title': en.lockBiometricPrompt,
          'subtitle': en.lockBiometricSheetSubtitle,
          'cancel': en.lockPinUseInstead,
        });
        expect(find.text(en.lockBiometricUnavailable), findsNothing);
        await unmount(tester);

        // A face added while the app was in the background: the PIN, once.
        android
          ..gateAnswers.add('reenrolled')
          ..native.clear();
        unlocked = 0;
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () => unlocked++, onForgotPin: () {}),
          vault: vault,
          biometrics: gate,
          clock: clock,
          viewport: _small,
        );
        expect(unlocked, 0);
        expect(find.text(en.lockBiometricReenrolled), findsOneWidget);
        expect(
          android.native.map((c) => c.method),
          isNot(contains('armBiometricGate')),
          reason: 'never re-armed on the biometric alone',
        );
        await typePin(tester, '135790');
        await tester.pumpAndSettle();
        await vault.pendingAfterPin;
        expect(unlocked, 1);
        expect(
          android.native.map((c) => c.method),
          contains('armBiometricGate'),
        );
        await unmount(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });
}
