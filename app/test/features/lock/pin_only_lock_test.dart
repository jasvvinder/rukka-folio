// ADR 2026-10-05b on screen: the S15 PIN-only variant (ruling 1), and the
// cold start that never ends at a blocked screen (ruling 4). Driven over the
// real method channels through the emulation in
// test/features/devices/keystore_emulator.dart.
@Tags(['F1'])
library;

import 'dart:convert';
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

/// The production cold-start attempt over [keys] (ADR 2026-10-06): the gate
/// read, or — on a legacy biometric-bound install — null, so the device-key
/// read itself prompts.
Future<BiometricOutcome?> Function(String) attemptOf(KeychainKeyStore keys) {
  final gate = KeystoreBiometricGate(
    keys: keys,
    platform: const MethodChannelKeystorePlatform(),
  );
  return (reason) => gate.openAtColdStart(reason: reason);
}

void main() {
  group('F1-1005b-1 S15 PIN-only variant (ADR 2026-10-05b §1)', () {
    testWidgets(
      'F1-1005b-1 a PIN-only phone gets the PIN boxes and keypad from the '
      'first answer, no biometric button or line (also in cooldown), a line '
      'saying why, and S0.8 states the PIN-only form — EN/PA/HI at 200% on '
      '360x800',
      (tester) async {
        final android = AndroidKeystoreEmulator(enrolled: false)..install();
        // Adapted for ADR 2026-10-06: a PIN-only phone is one with no gate.
        final keys = KeychainKeyStore(sealed: false);
        await tester.runAsync(
          () => keys.write(KeyIds.deviceSigningKey, Uint8List.fromList([1])),
        );
        expect(await tester.runAsync(keys.gateArmed), isFalse);
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
          expect(
            find.text(l10n.lockBiometricButton),
            findsNothing,
            reason: why,
          );
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
          expect(
            find.text(l10n.lockBiometricButton),
            findsNothing,
            reason: why,
          );
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

        // The same screen on a phone with a gate keeps its biometric button —
        // the variant is the gate's, not the screen's default — and the button
        // is live: it reads the gate (KEY145B finding 3; ADR 2026-10-06 §2).
        await tester.runAsync(() async {
          android.stored['$promptlessNs/rukka.${KeychainKeyStore.gateItemId}'] =
              base64Encode(utf8.encode('armed'));
        });
        final en = lookupAppLocalizations(const Locale('en'));
        keys.setPromptCopy(
          title: en.lockBiometricPrompt,
          subtitle: en.lockBiometricSheetSubtitle,
          cancel: en.lockPinUseInstead,
        );
        android
          ..enrolled = true
          ..gateMinted = true
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
        expect(
          android.native.where((c) => c.method == 'authenticate').length,
          2,
        );
        await unmount(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });

  group('F1-1005b-2 no person-bound item before O4b; a cancelled prompt '
      'reaches Use PIN instead (ADR 2026-10-05b §4)', () {
    // ADR 2026-10-06 §1 settles desk 153: the device keys are minted into the
    // hardware-backed class with no biometric binding and never move, so the
    // KEY145B tests of the PIN-only → biometric move and of the old root
    // wiring are superseded (bodies in git history), re-landing in
    // test/features/devices/gate_key_test.dart and gate_unlock_test.dart.
    test(
      'F1-1005b-2 (ruling 4 heading only) first run on a phone WITH a '
      'fingerprint: bootstrapSolo mints the device keys at bootstrap, into the '
      'promptless PIN-only class — nothing reaches the biometric class and no '
      'prompt can rise — and only the PIN set at O4b binds them to the biometric',
      () {},
      skip:
          'superseded by ADR 2026-10-06 §1; re-lands as C-1006-1 '
          '(gate_key_test.dart)',
    );

    test(
      'F1-1005b-2 device keys are minted after O4b, never at bootstrap',
      () {},
      skip:
          'superseded by ADR 2026-10-06 §1 (desk 153 settled: minted at the '
          'first run that S0.2 registers, straight into the ruling-1 class, '
          'never moved); re-lands as C-1006-1 (gate_key_test.dart)',
    );

    test(
      'F1-1005b-2 the composition root opens a biometric-bound ledger only '
      'behind the cold-start S15, hands every successful PIN to the upgrade, '
      'and gives the in-app S15 the custody gate (root pin)',
      () {},
      skip:
          'superseded by ADR 2026-10-06 §3 (every install with a PIN opens '
          'behind S15; the PIN opens the store and mints the gate); re-lands as '
          'C-1006-3 root pin (gate_unlock_test.dart)',
    );

    testWidgets(
      'F1-1005b-2 cold start on a biometric-bound phone: S15 is up before the '
      'device keys are read, a cancelled prompt leaves Use PIN instead (never '
      'RukkaFolioBlocked), and after the PIN the biometric opens the books '
      '(adapted, ADR 2026-10-06 §4/§5: a legacy biometric-bound install, and an '
      'invalidated one removes nothing)',
      (tester) async {
        final android = AndroidKeystoreEmulator(enrolled: true)..install();
        android.stored['$promptlessNs/rukka.${KeychainKeyStore.classItemId}'] =
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
              attempt: attemptOf(keys),
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
              attempt: attemptOf(keys),
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
              attempt: attemptOf(keys),
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

        // Invalidated: S15 goes to the PIN with the re-enrolment line, and after
        // the PIN the books need recovery — but nothing is removed, ever
        // (ADR 2026-10-06 §4 supersedes ADR 2026-10-05b §3's removal).
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
              attempt: attemptOf(keys),
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
          isNot(contains('resetBiometricDeviceItems')),
        );
        expect(
          android.stored,
          contains('$biometricNs/rukka.${KeyIds.deviceSigningKey}'),
          reason: 'no error path deletes a device-key item',
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
      android.stored['$promptlessNs/rukka.${KeychainKeyStore.classItemId}'] =
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
      await tester.pumpWidget(
        ColdStartApp(
          locale: const Locale('en'),
          child: ColdStartGate(
            vault: vault,
            open: () async {
              final k = await keys.read(KeyIds.deviceSigningKey);
              if (k == null) throw DeviceKeysMissing();
            },
            attempt: attemptOf(keys),
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
              attempt: attemptOf(keys),
              onDone: (r) => result = r,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(result, ColdStartResult.umkMissing);
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
                attempt: attemptOf(keys),
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
      'and a changed set needs the PIN once, which re-arms it (adapted, ADR '
      '2026-10-06 §2/§4: the prompt is the gate read, and the PIN mints a new '
      'gate)',
      (tester) async {
        // A phone in the ruling-1 class with a gate minted at O4b.
        final android = AndroidKeystoreEmulator(enrolled: true)..install();
        android
          ..stored['$promptlessNs/rukka.${KeychainKeyStore.classItemId}'] =
              base64Encode(utf8.encode('hardware'))
          ..stored['$promptlessNs/rukka.${KeychainKeyStore.gateItemId}'] =
              base64Encode(utf8.encode('armed'))
          ..gateMinted = true;
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
        final clock = TestClock();
        final vault = PinVault(
          keys: FakeKeyStore(),
          suite: await testSuite(),
          now: clock.call,
          onPinProven: keys.unsealAfterPin,
          afterPinProven: () async {
            await keys.afterPinProven();
          },
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
          ..changeEnrolment()
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
