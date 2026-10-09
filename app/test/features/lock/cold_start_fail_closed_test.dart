// ADR 2026-10-09 *Open* ⚠️ (conservative reading, owner to confirm) at the
// cold-start S15: the gate's `open` is the real `LocalLedger.openIdentity`,
// over the real method channels and the Android emulation. A phone whose
// identity holds no device keys reaches the books only when it reads as *not
// registered yet* (nothing authored, no certificate, no registered device
// id); a registered phone whose keys are gone stays `keysLost` →
// RukkaFolioBlocked (03 §5), and nothing is minted over it.
@Tags(['F1'])
library;

import 'dart:convert';

import 'package:data/data.dart' show LedgerDatabase;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart'
    show SessionItems;
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
import 'package:rukka_folio/features/devices/keystore_platform.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/lock/cold_start_gate.dart';
import 'package:rukka_folio/features/lock/keystore_biometric_gate.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../../shared/test_app.dart';
import '../devices/keystore_emulator.dart';
import 'lock_harness.dart';

const _pin = '135790';

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

  /// Runs the cold start with the real ledger behind it, PIN-unlocked.
  Future<(ColdStartResult?, LocalLedger)> coldStart(
    WidgetTester tester,
    LedgerDatabaseHandle db,
  ) async {
    final keys = process();
    final vault = await vaultOver(keys);
    final ledger = LocalLedger(
      db: db.db,
      keys: keys,
      suite: await testSuite(),
      now: testNow,
      requireConfirmedIdentity: true,
    );
    ColdStartResult? result;
    await tester.pumpWidget(
      ColdStartApp(
        locale: const Locale('en'),
        child: ColdStartGate(
          vault: vault,
          attempt: (reason) => KeystoreBiometricGate(
            keys: keys,
            platform: const MethodChannelKeystorePlatform(),
          ).openAtColdStart(reason: reason),
          open: () => ledger.openIdentity(),
          onDone: (r) => result = r,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // With no device-key class recorded the gate offers its biometric page
    // first; the PIN is beneath it.
    final usePin = find.text(en.lockPinUseInstead);
    if (usePin.evaluate().isNotEmpty) {
      await tester.tap(usePin);
      await tester.pumpAndSettle();
    }
    await typePin(tester, _pin);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    return (result, ledger);
  }

  testWidgets('C-1009-2 a registered phone whose device keys are gone stays '
      'keysLost (blocked, nothing minted); a phone whose identity was never '
      'registered — nothing authored, no certificate, no registered device '
      'id — opens as not registered yet, without even looking for a key', (
    tester,
  ) async {
    // ── registered, then wiped ─────────────────────────────────────────────
    final android = AndroidKeystoreEmulator()..install();
    final db = LedgerDatabaseHandle();
    await tester.runAsync(() async {
      db.db = await openTestDb();
      final keys = process();
      expect(await keys.unsealIfNoPin(), isTrue);
      final l = LocalLedger(
        db: db.db,
        keys: keys,
        suite: await testSuite(),
        now: testNow,
      );
      final id = await l.openIdentity();
      await l.mintForRegistration();
      // `POST devices` answered: the auth client stored the id.
      await keys.write(
        SessionItems.deviceId,
        Uint8List.fromList(utf8.encode(id.deviceId)),
      );
      final vault = await vaultOver(keys);
      await vault.setPin(_pin);
      await vault.pendingAfterPin;
      l.dispose();
    });
    android.hw
      ..remove(KeyIds.deviceSigningKey)
      ..remove(KeyIds.deviceAgreementKey);
    final hwBefore = Map.of(android.hw);

    var (result, ledger) = await coldStart(tester, db);
    expect(result, ColdStartResult.keysLost);
    expect(ledger.isOpen, isFalse);
    expect(android.hw.keys.toSet(), hwBefore.keys.toSet(), reason: 'no mint');
    await unmount(tester);

    // ── never registered ───────────────────────────────────────────────────
    final fresh = AndroidKeystoreEmulator()..install();
    final db2 = LedgerDatabaseHandle();
    await tester.runAsync(() async {
      db2.db = await openTestDb();
      final keys = process();
      expect(await keys.unsealIfNoPin(), isTrue);
      final l = LocalLedger(
        db: db2.db,
        keys: keys,
        suite: await testSuite(),
        now: testNow,
      );
      await l.openIdentity();
      final vault = await vaultOver(keys);
      await vault.setPin(_pin);
      await vault.pendingAfterPin;
      l.dispose();
    });
    fresh.native.clear();

    (result, ledger) = await coldStart(tester, db2);
    expect(result, ColdStartResult.opened);
    expect(ledger.isOpen, isTrue);
    expect(ledger.keysRegistered, isFalse);
    expect(fresh.nativeMethods, isNot(contains('deviceItemRead')));
    expect(fresh.hw, isEmpty);
    ledger.dispose();
    await unmount(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}

/// The database a test hands between its setup (run for real) and the
/// widget pass.
final class LedgerDatabaseHandle {
  late LedgerDatabase db;
}
