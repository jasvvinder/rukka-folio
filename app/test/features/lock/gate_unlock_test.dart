// ADR 2026-10-06 on screen: the cold-start S15 is the only door to the device
// keys (ruling 3) and an enrolment change costs only the gate (ruling 4).
// Driven over the real method channels through the Android emulation in
// test/features/devices/keystore_emulator.dart, with the device keys minted by
// a real LocalLedger and the PIN checked by a real PinVault.
@Tags(['F1'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
import 'package:rukka_folio/features/devices/keystore_platform.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/cold_start_gate.dart';
import 'package:rukka_folio/features/lock/keystore_biometric_gate.dart';
import 'package:rukka_folio/features/lock/relock_sync_nudge.dart';
import 'package:rukka_folio/features/lock/screens/s15_lock_screen.dart';
import 'package:rukka_folio/features/lock/widgets/pin_pad.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/blocked_screen.dart';

import '../../shared/test_app.dart';
import '../devices/keystore_emulator.dart';
import 'lock_harness.dart';

const _pin = '135790';
const _items = [
  KeyIds.deviceSigningKey,
  KeyIds.deviceAgreementKey,
  KeyIds.wrappedUmk,
];

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  KeychainKeyStore process() => KeychainKeyStore()
    ..setPromptCopy(
      title: en.lockBiometricPrompt,
      subtitle: en.lockBiometricSheetSubtitle,
      cancel: en.lockPinUseInstead,
    );

  Future<PinVault> vaultOver(KeychainKeyStore keys) async => PinVault(
    keys: keys,
    suite: await testSuite(),
    now: testNow,
    onPinProven: keys.unsealAfterPin,
    afterPinProven: () async {
      await keys.afterPinProven();
    },
  );

  /// A phone that has onboarded: first run, O4b.
  Future<void> onboarded(WidgetTester tester) async {
    await tester.runAsync(() async {
      final keys = process();
      expect(await keys.unsealIfNoPin(), isTrue);
      final ledger = LocalLedger(
        db: await openTestDb(),
        keys: keys,
        suite: await testSuite(),
        now: testNow,
      );
      await ledger.bootstrapSolo();
      final vault = await vaultOver(keys);
      await vault.setPin(_pin);
      await vault.pendingAfterPin;
      ledger.dispose();
      await ledger.db.close();
    });
  }

  /// What the ledger's reopen reads, in its order.
  Future<void> readDeviceKeys(KeychainKeyStore keys) async {
    for (final id in _items) {
      final v = await keys.read(id);
      if (v == null) {
        throw DeviceKeysMissing(deviceKeys: id != KeyIds.wrappedUmk);
      }
    }
  }

  Future<Future<ColdStartResult?> Function()> coldStart(
    WidgetTester tester,
    KeychainKeyStore keys,
    PinVault vault, {
    void Function()? onOpen,
  }) async {
    ColdStartResult? result;
    final gate = KeystoreBiometricGate(
      keys: keys,
      platform: const MethodChannelKeystorePlatform(),
    );
    await tester.pumpWidget(
      ColdStartApp(
        locale: const Locale('en'),
        child: ColdStartGate(
          vault: vault,
          attempt: (reason) => gate.openAtColdStart(reason: reason),
          open: () async {
            onOpen?.call();
            await readDeviceKeys(keys);
          },
          onDone: (r) => result = r,
        ),
      ),
    );
    return () async => result;
  }

  int firstIndex(AndroidKeystoreEmulator a, String method) =>
      a.nativeMethods.indexOf(method);

  group('C-1006-3 S15 is the only door to the device keys', () {
    testWidgets('C-1006-3 a cancelled biometric at cold start reaches Use PIN '
        'instead with no device key read and no blocked screen; a wrong PIN '
        'reads nothing; the right PIN opens the books', (tester) async {
      final android = AndroidKeystoreEmulator(enrolled: true)..install();
      await onboarded(tester);
      final keys = process();
      final vault = await vaultOver(keys);
      android
        ..gateAnswers.add('cancelled')
        ..native.clear();
      var opens = 0;
      final result = await coldStart(
        tester,
        keys,
        vault,
        onOpen: () => opens++,
      );
      await tester.pumpAndSettle();

      expect(android.nativeMethods, contains('authenticate'));
      expect(firstIndex(android, 'deviceItemRead'), -1);
      expect(opens, 0, reason: 'nothing that needs the keys ran');
      expect(keys.sealed, isTrue);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(PinKeypad), findsOneWidget);
      expect(find.byType(RukkaFolioBlocked), findsNothing);
      expect(await result(), isNull);

      await typePin(tester, '000000');
      await tester.pumpAndSettle();
      expect(firstIndex(android, 'deviceItemRead'), -1);
      expect(keys.sealed, isTrue);
      expect(await result(), isNull);

      await typePin(tester, _pin);
      await tester.pumpAndSettle();
      expect(await result(), ColdStartResult.opened);
      expect(opens, 1);
      expect(
        android.nativeMethods.where((m) => m == 'deviceItemRead').length,
        3,
      );
      expect(find.byType(RukkaFolioBlocked), findsNothing);
      await unmount(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('C-1006-3 the gate read with the biometric opens the books by '
        'itself, the device keys read only after it answered; a failed face '
        'stays on S15 with Use PIN instead; a PIN-only phone is asked for the '
        'PIN with no prompt at all', (tester) async {
      var android = AndroidKeystoreEmulator(enrolled: true)..install();
      await onboarded(tester);
      android.native.clear();
      var keys = process();
      var result = await coldStart(tester, keys, await vaultOver(keys));
      await tester.pumpAndSettle();
      expect(await result(), ColdStartResult.opened);
      final gateAt = firstIndex(android, 'authenticate');
      final readAt = firstIndex(android, 'deviceItemRead');
      expect(gateAt, greaterThanOrEqualTo(0));
      expect(readAt, greaterThan(gateAt));
      await unmount(tester);

      // A face not recognised: the face page with Use PIN instead beneath.
      android
        ..gateAnswers.add('failed')
        ..native.clear();
      keys = process();
      result = await coldStart(tester, keys, await vaultOver(keys));
      await tester.pumpAndSettle();
      expect(find.text(en.lockBiometricFailedAny), findsOneWidget);
      expect(find.text(en.lockPinUseInstead), findsOneWidget);
      expect(firstIndex(android, 'deviceItemRead'), -1);
      await tester.tap(find.text(en.lockPinUseInstead));
      await tester.pumpAndSettle();
      await typePin(tester, _pin);
      await tester.pumpAndSettle();
      expect(await result(), ColdStartResult.opened);
      await unmount(tester);

      // PIN-only phone: no gate, nothing prompted, the PIN opens.
      android = AndroidKeystoreEmulator(enrolled: false)..install();
      await onboarded(tester);
      android.native.clear();
      keys = process();
      result = await coldStart(tester, keys, await vaultOver(keys));
      await tester.pumpAndSettle();
      expect(android.nativeMethods, isNot(contains('authenticate')));
      expect(find.text(en.lockPinOnlyNote), findsOneWidget);
      expect(find.byType(PinKeypad), findsOneWidget);
      await typePin(tester, _pin);
      await tester.pumpAndSettle();
      expect(await result(), ColdStartResult.opened);
      await unmount(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    test('C-1006-3 the composition root seals the device keys behind the '
        'cold-start S15 on any install with a PIN, wires the PIN to open them '
        'and to mint the gate, and migrates only after the books opened '
        '(root pin)', () {
      final root = File('lib/bootstrap.dart').readAsStringSync();
      final seal = root.indexOf('if (!await keys.unsealIfNoPin())');
      final gate = root.indexOf('ColdStartGate(');
      final open = root.indexOf('await ledger.openIdentity()');
      final migrate = root.indexOf('await keys.migrateAfterUnlock()');
      expect(seal, greaterThan(0));
      expect(gate, greaterThan(seal));
      expect(open, greaterThan(gate), reason: 'S15 before the device-key read');
      expect(migrate, greaterThan(open));
      expect(root, contains('onPinProven: keys.unsealAfterPin'));
      expect(
        RegExp(
          r'afterPinProven: \(\) async \{\s*await keys\.afterPinProven\(\);',
        ).hasMatch(root),
        isTrue,
      );
      expect(
        root,
        contains(
          'attempt: (reason) =>\n                  biometricGate.openAtColdStart(reason: reason)',
        ),
      );
      expect(root, contains('open: () => ledger.openIdentity()'));
      expect(root, contains('biometricGate.admitOnce()'));
      expect(root, contains('biometrics: biometricGate'));
      // Nothing before the gate reads a device key: the only device-key
      // readers in the root come after it.
      final before = root.substring(0, gate);
      for (final id in [
        'deviceSigningKey',
        'deviceAgreementKey',
        'wrappedUmk',
      ]) {
        expect(before, isNot(contains('KeyIds.$id')), reason: id);
      }
      expect(root, isNot(contains('upgradeAfterPin')));
      expect(root, isNot(contains('dropInvalidatedAfterPin')));
      // The relock half (GATE1 review finding 1): the resume pull waits on the
      // seal, and the unlock that reopens the store is the pull.
      expect(root, contains('RelockAwareSyncNudge('));
      expect(root, contains('sealed: () => keys.sealed'));
      expect(root, contains('keys.onReopened = sync.onAppForeground'));
      expect(root, isNot(contains('SyncLifecycleObserver(sync)')));
    });

    testWidgets('C-1006-3 after the background timeout the in-app S15 seals '
        'the device keys as it covers the app: the resume pull does not run '
        'and no device key can be read until the MPIN or the gate; each '
        'unlock reopens them and is the pull; a short trip out seals nothing', (
      tester,
    ) async {
      final android = AndroidKeystoreEmulator(enrolled: true)..install();
      await onboarded(tester);
      final keys = process();
      final vault = await vaultOver(keys);
      final gate = KeystoreBiometricGate(
        keys: keys,
        platform: const MethodChannelKeystorePlatform(),
      );
      // The cold start the person passed (bootstrap): the gate opened the
      // store, and the in-app S15 that follows must not ask again.
      expect(await keys.openWithGate(), PlatformBiometricAnswer.success);
      gate.admitOnce();
      var pulls = 0;
      keys.onReopened = () => pulls++;
      final nudge = RelockAwareSyncNudge(
        sealed: () => keys.sealed,
        nudge: () => pulls++,
      );
      WidgetsBinding.instance.addObserver(nudge);
      addTearDown(() => WidgetsBinding.instance.removeObserver(nudge));
      final db = await openTestDb();
      await tester.pumpWidget(
        RukkaFolioApp(
          db: db,
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          keys: keys,
          now: testNow,
          locale: const Locale('en'),
          pinVault: vault,
          biometrics: gate,
          settings: AppSettings(prefs: MemoryPrefs()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
      expect(keys.sealed, isFalse, reason: 'the admitted S15 seals nothing');

      Future<void> away(Duration d) async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(d);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      }

      // Past the timeout; the face is dismissed, so the PIN pad comes up.
      android
        ..gateAnswers.add('cancelled')
        ..native.clear();
      await away(AppSettings.defaultAutoLockBackground);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(keys.sealed, isTrue);
      expect(pulls, 0, reason: 'no pull behind S15');
      expect(android.nativeMethods, isNot(contains('deviceItemRead')));
      for (final id in _items) {
        await expectLater(keys.read(id), throwsA(isA<DeviceKeysSealed>()));
      }
      await typePin(tester, _pin);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
      expect(keys.sealed, isFalse);
      expect(pulls, 1, reason: 'the MPIN reopened the store: one pull');
      expect(await keys.read(KeyIds.deviceSigningKey), isNotNull);

      // A short trip out: nothing locks, nothing seals, the resume pulls.
      await away(const Duration(seconds: 10));
      expect(find.byType(LockScreen), findsNothing);
      expect(keys.sealed, isFalse);
      expect(pulls, 2);

      // Past the timeout again; this time the gate read opens.
      android.native.clear();
      await away(AppSettings.defaultAutoLockBackground);
      expect(android.nativeMethods, contains('authenticate'));
      expect(find.byType(LockScreen), findsNothing);
      expect(keys.sealed, isFalse);
      expect(pulls, 3, reason: 'the gate reopened the store: one pull');
      await unmount(tester);
      await db.close();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('C-1006-4 an enrolment change costs only the gate', () {
    testWidgets('C-1006-4 the re-enrolled S15 inside the app: the line says '
        'the set changed (added or removed), no Face ID button on the pad or '
        'in the cooldown, and Forgot PIN goes to the recovery ladder, never '
        'the code-plus-face reset; EN/PA/HI at 200% on 360x800', (
      tester,
    ) async {
      // GATE1 review finding 6: the same state follows a removal.
      expect(en.lockBiometricReenrolled, isNot(contains('added')));
      for (final locale in lockLocales) {
        final l10n = lookupAppLocalizations(locale);
        final why = '${locale.languageCode} 200%';
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin(_pin);
        var ladder = 0;
        var code = 0;
        await pumpLock(
          tester,
          LockScreen(
            onUnlocked: () {},
            onForgotPin: () => code++,
            onForgotPinPinOnly: () => ladder++,
          ),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.reenrolled]),
          clock: clock,
          locale: locale,
          textScale: 2,
          viewport: const Size(360, 800),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.lockBiometricReenrolled), findsOneWidget);
        expect(find.byType(PinKeypad), findsOneWidget, reason: why);
        expect(find.text(l10n.lockMethodAny), findsNothing, reason: why);
        expectTextFits(tester, reason: '$why pad');

        await tester.ensureVisible(find.text(l10n.lockForgotAction));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.lockForgotAction));
        await tester.pumpAndSettle();
        expect(find.text(l10n.lockForgotBodyReenrolled), findsOneWidget);
        expect(find.text(l10n.lockForgotBody), findsNothing, reason: why);
        expect(find.text(l10n.lockForgotStart), findsNothing, reason: why);
        expectTextFits(tester, reason: '$why forgot');
        await tester.ensureVisible(find.text(l10n.lockForgotStartLadder));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.lockForgotStartLadder));
        await tester.pumpAndSettle();
        expect((ladder, code), (1, 0), reason: why);
        await unmount(tester);

        // Five misses: the cooldown offers no face either.
        for (var i = 0; i < 5; i++) {
          await vault.verify('000000');
        }
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.reenrolled]),
          clock: clock,
          locale: locale,
          textScale: 2,
          viewport: const Size(360, 800),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.lockCooldownTitle), findsOneWidget, reason: why);
        expect(find.text(l10n.lockMethodAny), findsNothing, reason: why);
        await unmount(tester);
      }
    });

    testWidgets('C-1006-4 after a second fingerprint the cold start says the '
        'set changed and asks for the PIN, the PIN opens the same books, a new '
        'gate is minted for the new set, the device keys are byte-identical, '
        'and the next cold start opens with the finger again', (tester) async {
      final android = AndroidKeystoreEmulator(enrolled: true)..install();
      await onboarded(tester);
      final before = {
        for (final e in android.hw.entries) e.key: List.of(e.value),
      };
      android
        ..changeEnrolment()
        ..native.clear();

      var keys = process();
      var vault = await vaultOver(keys);
      var result = await coldStart(tester, keys, vault);
      await tester.pumpAndSettle();
      expect(find.text(en.lockBiometricReenrolled), findsOneWidget);
      expect(find.byType(PinKeypad), findsOneWidget);
      expect(find.byType(RukkaFolioBlocked), findsNothing);
      expect(keys.sealed, isTrue);
      // GATE1 review finding 3: no Face ID button — a tap could only answer
      // re-enrolled again, with no prompt.
      expect(find.text(en.lockMethodAny), findsNothing);
      // GATE1 review finding 2: the forgot door neither promises the face
      // nor offers a button that does nothing; Back returns to the PIN.
      final asked = android.nativeMethods
          .where((m) => m == 'authenticate')
          .length;
      await tester.ensureVisible(find.text(en.lockForgotAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.lockForgotAction));
      await tester.pumpAndSettle();
      expect(find.text(en.lockForgotBodyReenrolledBeforeOpen), findsOneWidget);
      expect(find.text(en.lockForgotBodyBeforeOpen), findsNothing);
      expect(find.text(en.lockForgotStartBeforeOpen), findsNothing);
      expect(find.text(en.lockForgotStart), findsNothing);
      expect(find.text(en.lockForgotStartLadder), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(find.byTooltip(en.lockForgotCancel));
      await tester.pumpAndSettle();
      expect(find.byType(PinKeypad), findsOneWidget);
      expect(
        android.nativeMethods.where((m) => m == 'authenticate').length,
        asked,
        reason: 'nothing on the forgot door asked the platform again',
      );
      await typePin(tester, _pin);
      await tester.pumpAndSettle();
      await tester.runAsync(() async => vault.pendingAfterPin);
      expect(await result(), ColdStartResult.opened);
      expect(android.gateMinted, isTrue);
      expect(android.gateInvalid, isFalse);
      expect({
        for (final e in android.hw.entries) e.key: List.of(e.value),
      }, before);
      expect(
        android.nativeMethods.where(
          (m) => m == 'deviceItemWrite' || m == 'deviceItemDelete',
        ),
        isEmpty,
      );
      await unmount(tester);

      android.native.clear();
      keys = process();
      vault = await vaultOver(keys);
      result = await coldStart(tester, keys, vault);
      await tester.pumpAndSettle();
      expect(await result(), ColdStartResult.opened);
      expect(find.byType(PinKeypad), findsNothing);
      await unmount(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
