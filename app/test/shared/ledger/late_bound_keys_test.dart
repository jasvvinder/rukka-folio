// ADR 2026-10-09 🔒 — the device keys are minted at S0.2 and the composition
// root binds them late.
//
//  * ruling 2 (C-1009-2): a first launch mints ids only; S0.2's one ledger
//    step (`mintForRegistration`) mints the signing + agreement seeds and, for
//    a NEW account only, the UMK and its wrap; a retried POST reuses the
//    seeds; a further device of an existing account gets seeds only (ADR
//    2026-10-04b §3); a re-mint re-mints ids only.
//  * ruling 1 (C-1009-1, ledger half): `LedgerBinding` answers *not
//    registered yet* until the mint and the live ids and keys after it, to a
//    real `SyncEngine.late` / `CryptoGuard.late` built once, before the mint.
//  * Open ⚠️ (the fail-closed rule, conservative reading): an identity with
//    no seeds reopens as *not registered yet* only when nothing is authored,
//    there is no device certificate and no registered device id; anything
//    else stays `DeviceKeysMissing`.
//  * C-04b-4: an existing account's id is adopted before any authoring.
//  * C-1006-1: the mint writes the device keys and the wrapped UMK into the
//    hardware-backed class with no biometric binding — the real
//    `KeychainKeyStore` over the Android emulation.
//
// Real `LocalLedger` over in-memory SQLite and libsodium; synthetic ids.
@Tags(['C'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart' show BookType;
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart'
    show SessionItems;
import 'package:rukka_folio/features/devices/keychain_key_store.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../../features/devices/keystore_emulator.dart';
import '../test_app.dart';
import 'tenant_of.dart';

const _existingUser = '1f2e3d4c-5b6a-4978-8695-a4b3c2d1e0f9';

const _keyItems = [
  KeyIds.deviceSigningKey,
  KeyIds.deviceAgreementKey,
  KeyIds.wrappedUmk,
];

Future<LocalLedger> _ledger(
  KeyStore keys, {
  LedgerDatabase? db,
  bool guarded = true,
}) async {
  final l = LocalLedger(
    db: db ?? await openTestDb(),
    keys: keys,
    suite: await testSuite(),
    now: testNow,
    requireConfirmedIdentity: guarded,
  );
  addTearDown(l.dispose);
  return l;
}

Future<Map<String, Uint8List?>> _snapshot(KeyStore keys) async => {
  for (final id in _keyItems) id: await keys.read(id),
};

/// The engine the composition root builds once, before any key exists.
({eng.SyncEngine engine, eng.FakeTransport transport, eng.CryptoGuard guard})
_engineOver(LocalLedger l) {
  final binding = l.binding;
  final trust = eng.RecordTrustStore(umks: eng.BoundUmkSource(binding));
  final guard = eng.CryptoGuard.late(
    suite: l.suite,
    trust: trust,
    material: binding,
  );
  final server = eng.FakeSyncServer(clock: eng.ManualClock(1));
  final transport = server.transportFor(l.identity.deviceId);
  final engine = eng.SyncEngine.late(
    db: l.db,
    mirror: l.mirror,
    transport: transport,
    clock: eng.ManualClock(1),
    guard: guard,
    trust: trust,
    identity: binding,
    recompute: l.recompute,
    keySink: l,
  );
  return (engine: engine, transport: transport, guard: guard);
}

void main() {
  late FakeKeyStore keys;

  setUp(() => keys = FakeKeyStore());

  group('C-1009-2 the mint happens inside S0.2, through the ledger '
      '(ADR 2026-10-09 §2)', () {
    test('C-1009-2 a first launch mints the device, user and tenant ids and '
        'no key material: no seed, no UMK, no wrap is written, the binding '
        'answers not-registered-yet and every key reader refuses with '
        'LedgerKeysNotRegistered — never a null key', () async {
      final l = await _ledger(keys, guarded: false);
      final id = await l.openIdentity();

      expect(Uuid16.isCanonical(id.deviceId), isTrue);
      expect(Uuid16.isCanonical(id.userId), isTrue);
      expect(Uuid16.isCanonical(id.tenantId), isTrue);
      expect((await readStoredIdentity(keys))!.deviceId, id.deviceId);
      expect(await _snapshot(keys), {for (final k in _keyItems) k: null});
      expect(keys.writes.toSet().intersection(_keyItems.toSet()), isEmpty);

      expect(l.keysRegistered, isFalse);
      expect(l.binding.registered, isFalse);
      expect(l.binding.currentIdentity(), const eng.NotRegisteredYet());
      expect(l.binding.currentKeys(), const eng.KeysNotRegisteredYet());
      expect(() => l.keyMaterial, throwsA(isA<LedgerKeysNotRegistered>()));
      // Even an unguarded ledger authors nothing without keys.
      await expectLater(
        l.createBook(name: 'Me', type: BookType.personal),
        throwsA(isA<LedgerKeysNotRegistered>()),
      );
      expect(await l.mirror.bookIds(), isEmpty);
      expect(await l.db.select(l.db.outbox).get(), isEmpty);

      // A relaunch before S0.2 opens the same ids, still keyless.
      final again = await _ledger(keys, db: l.db);
      expect(await again.openIdentity(), isA<LedgerIdentity>());
      expect(again.identity.deviceId, id.deviceId);
      expect(again.keysRegistered, isFalse);
    });

    test('C-1009-2 S0.2\'s step mints both seeds and, for a new account, the '
        'UMK and its wrap — seeds first — self-verified for this user and '
        'wrapped to this device; it is idempotent, so a retried POST '
        'registers the same public keys, and a reopen holds them', () async {
      final db = await openTestDb();
      final l = await _ledger(keys, db: db);
      final id = await l.openIdentity();
      await l.confirmIdentity(id.userId);
      keys.writes.clear();

      await l.mintForRegistration();

      final order = keys.writes.where(_keyItems.contains).toList();
      expect(order, _keyItems, reason: 'seeds, then the wrapped UMK');
      final first = await _snapshot(keys);
      expect(first.values.every((v) => v != null), isTrue);
      expect(l.keysRegistered, isTrue);
      final m = l.keyMaterial;
      expect(m.device.deviceId, id.deviceId);
      expect(m.verifiedUmkOf(id.userId), isNotNull);
      final pubEd = Uint8List.fromList(m.device.public.ed25519);
      final umkEd = Uint8List.fromList(m.umk.public.ed25519);

      // A retried POST: nothing is minted again, nothing rewritten.
      keys.writes.clear();
      await l.mintForRegistration();
      expect(keys.writes, isEmpty);
      expect(l.keyMaterial.device.public.ed25519, pubEd);

      // A kill after the step, before the POST answered: the next launch
      // reuses what is held.
      final again = await _ledger(keys, db: db);
      await again.openIdentity();
      expect(again.keysRegistered, isTrue);
      keys.writes.clear();
      await again.mintForRegistration();
      expect(keys.writes, isEmpty);
      expect(again.keyMaterial.device.public.ed25519, pubEd);
      expect(again.keyMaterial.umk.public.ed25519, umkEd);
      expect(await _snapshot(keys), first);

      // And the new account authors.
      await again.createBook(name: 'Me', type: BookType.personal);
      expect(await again.mirror.bookIds(), hasLength(1));
    });

    test('C-1009-2 a step cut short reopens as not registered yet and the '
        'next step finishes it: complete seeds are reused and only the UMK '
        'is added; half a pair is replaced whole', () async {
      final db = await openTestDb();
      final l = await _ledger(keys, db: db);
      await l.openIdentity();
      await l.mintForRegistration();
      final ed = await keys.read(KeyIds.deviceSigningKey);
      final x = await keys.read(KeyIds.deviceAgreementKey);
      // Died after the seeds, before the wrap.
      await keys.delete(KeyIds.wrappedUmk);

      final b = await _ledger(keys, db: db);
      await b.openIdentity();
      expect(b.keysRegistered, isFalse);
      await b.mintForRegistration();
      expect(await keys.read(KeyIds.deviceSigningKey), ed);
      expect(await keys.read(KeyIds.deviceAgreementKey), x);
      expect(await keys.contains(KeyIds.wrappedUmk), isTrue);
      expect(b.keyMaterial.umk, isNotNull);

      // Died between the two seeds.
      await keys.delete(KeyIds.deviceAgreementKey);
      await keys.delete(KeyIds.wrappedUmk);
      final c = await _ledger(keys, db: db);
      await c.openIdentity();
      expect(c.keysRegistered, isFalse);
      await c.mintForRegistration();
      expect(await keys.read(KeyIds.deviceSigningKey), isNot(ed));
      expect(await keys.contains(KeyIds.deviceAgreementKey), isTrue);
      expect(c.keyMaterial.umk, isNotNull);
    });

    test('C-1009-2 a device signing in to an existing account mints its '
        'device seeds only — never a UMK (ADR 2026-10-04b §3) — reopens '
        'with them and no UMK, and still authors nothing', () async {
      final db = await openTestDb();
      final l = await _ledger(keys, db: db);
      await l.openIdentity();
      await l.adoptExistingAccount(_existingUser);

      await l.mintForRegistration();

      expect(await keys.contains(KeyIds.deviceSigningKey), isTrue);
      expect(await keys.contains(KeyIds.deviceAgreementKey), isTrue);
      expect(await keys.contains(KeyIds.wrappedUmk), isFalse);
      expect(l.keysRegistered, isTrue);
      final material = l.binding.currentKeys();
      expect(material, isA<eng.DeviceKeyMaterial>());
      expect((material as eng.DeviceKeyMaterial).umk, isNull);
      // ADR 2026-10-10 §1 🔒 (C-1010-1): registered under the account's user,
      // with no tenant until it is learned — never a RegisteredIdentity
      // carrying a placeholder id.
      expect(
        l.binding.currentIdentity(),
        isA<eng.RegisteredAwaitingTenant>().having(
          (r) => r.userId,
          'userId',
          _existingUser,
        ),
      );

      // Registered (SessionItems.deviceId stored), then a relaunch: the
      // seeds-without-UMK state is this device's, not keys lost.
      await keys.write(LocalLedgerKeys.sessionDeviceId, Uint8List(1));
      final again = await _ledger(keys, db: db);
      await again.openIdentity();
      expect(again.keysRegistered, isTrue);
      expect(again.identity.userId, _existingUser);
      expect(() => again.keyMaterial, throwsA(isA<LedgerKeysNotRegistered>()));
      await again.confirmIdentity(_existingUser);
      await expectLater(
        again.createBook(name: 'Me', type: BookType.personal),
        throwsA(isA<LedgerKeysNotRegistered>()),
      );
    });

    test('C-1009-2 a re-mint (C-04b-3) re-mints ids only: the device id and '
        'any seeds stay, no UMK is minted, a held UMK is dropped with its '
        'wrap and retired (never zeroised under a borrower), and the next '
        'S0.2 step mints the account\'s UMK over the same seeds', () async {
      // The production path: nothing to re-wrap.
      final l = await _ledger(keys);
      final old = await l.openIdentity();
      keys.writes.clear();
      await l.remintProvisionalIdentity();
      expect(l.identity.deviceId, old.deviceId);
      expect(l.identity.userId, isNot(old.userId));
      expect(keys.writes.toSet().intersection(_keyItems.toSet()), isEmpty);
      expect(l.keysRegistered, isFalse);

      // A ledger whose keys were minted before signup answered.
      final k2 = FakeKeyStore();
      final m = await _ledger(k2);
      await m.bootstrapSolo();
      final borrowed = m.keyMaterial;
      final ed = await k2.read(KeyIds.deviceSigningKey);
      await m.remintProvisionalIdentity();
      expect(await k2.contains(KeyIds.wrappedUmk), isFalse);
      expect(await k2.read(KeyIds.deviceSigningKey), ed);
      expect(() => m.keyMaterial, throwsA(isA<LedgerKeysNotRegistered>()));
      expect(borrowed.umk.isDisposed, isFalse);
      await m.mintForRegistration();
      expect(m.keyMaterial.device.public, borrowed.device.public);
      expect(m.keyMaterial.umk.public, isNot(borrowed.umk.public));
      expect(m.keyMaterial.verifiedUmkOf(m.identity.userId), isNotNull);
      m.dispose();
      expect(borrowed.umk.isDisposed, isTrue);
    });

    test('C-1009-2 the ledger reads the auth client\'s registered device id '
        'under the auth client\'s own key', () {
      expect(LocalLedgerKeys.sessionDeviceId, SessionItems.deviceId);
    });
  });

  group('ADR 2026-10-09 Open — not registered yet vs keys lost (fail '
      'closed)', () {
    Future<LedgerDatabase> registeredThenWiped({
      required Future<void> Function(LocalLedger l) leave,
    }) async {
      final db = await openTestDb();
      final l = await _ledger(keys, db: db, guarded: false);
      await l.openIdentity();
      await l.mintForRegistration();
      await leave(l);
      l.dispose();
      for (final k in _keyItems) {
        await keys.delete(k);
      }
      return db;
    }

    test('C-1009-2 with nothing authored, no certificate and no registered '
        'device id, a keyless identity opens as not registered yet and S0.2 '
        'may mint', () async {
      final db = await registeredThenWiped(leave: (_) async {});
      final l = await _ledger(keys, db: db);
      await l.openIdentity();
      expect(l.keysRegistered, isFalse);
      await l.mintForRegistration();
      expect(l.keysRegistered, isTrue);
    });

    test('C-1009-2 an authored book, a filed certificate or a registered '
        'device id each keeps a keyless identity blocked: DeviceKeysMissing, '
        'nothing minted', () async {
      final cases = <String, Future<void> Function(LocalLedger)>{
        'authored': (l) async {
          await l.createBook(name: 'Me', type: BookType.personal);
        },
        'certificate': (l) async {
          await keys.write(LocalLedgerKeys.deviceCert, Uint8List(4));
        },
        'registered': (l) async {
          await keys.write(LocalLedgerKeys.sessionDeviceId, Uint8List(4));
        },
      };
      for (final MapEntry(key: name, value: leave) in cases.entries) {
        keys = FakeKeyStore();
        final db = await registeredThenWiped(leave: leave);
        final l = await _ledger(keys, db: db);
        keys.writes.clear();
        await expectLater(
          l.openIdentity(),
          throwsA(
            isA<DeviceKeysMissing>().having(
              (e) => e.deviceKeys,
              'deviceKeys',
              isTrue,
            ),
          ),
          reason: name,
        );
        expect(l.isOpen, isFalse, reason: name);
        expect(keys.writes, isEmpty, reason: '$name: nothing minted');
      }
    });

    test('C-1009-2 seeds held but the wrapped UMK gone on a registered new '
        'account stays the umkMissing case, as before', () async {
      final db = await openTestDb();
      final l = await _ledger(keys, db: db);
      await l.openIdentity();
      await l.mintForRegistration();
      await keys.write(LocalLedgerKeys.sessionDeviceId, Uint8List(4));
      await keys.delete(KeyIds.wrappedUmk);
      final again = await _ledger(keys, db: db);
      await expectLater(
        again.openIdentity(),
        throwsA(
          isA<DeviceKeysMissing>().having(
            (e) => e.deviceKeys,
            'deviceKeys',
            isFalse,
          ),
        ),
      );
    });
  });

  group('C-04b-4 a phone that already has an account takes that account\'s '
      'id (ADR 2026-10-04b §3)', () {
    test('C-04b-4 adoptExistingAccount adopts the account\'s user id before '
        'anything is authored: the device id stays, the tenant id is not the '
        'provisional one, the identity stays provisional, it survives a '
        'relaunch, and the binding announces it', () async {
      final db = await openTestDb();
      final l = await _ledger(keys, db: db);
      final old = await l.openIdentity();
      var told = 0;
      l.binding.userId.addListener(() => told++);

      await l.adoptExistingAccount(_existingUser);

      expect(told, 1);
      expect(l.identity.userId, _existingUser);
      expect(l.binding.userId.value, _existingUser);
      expect(l.identity.deviceId, old.deviceId);
      // ADR 2026-10-10 §1 🔒: the provisional tenant is discarded and none
      // replaces it — not a placeholder, not a mint (C-1010-1).
      expect(l.identity.tenant, const TenantNotKnownYet());
      expect(old.tenant, isA<KnownTenant>());
      expect(l.identityConfirmed, isFalse);
      await expectLater(
        l.createBook(name: 'Me', type: BookType.personal),
        throwsA(isA<IdentityNotConfirmed>()),
      );
      final stored = await readStoredIdentity(keys);
      expect(stored!.userId, _existingUser);
      expect(stored.deviceId, old.deviceId);

      final again = await _ledger(keys, db: db);
      await again.openIdentity();
      expect(again.identity.userId, _existingUser);
      expect(again.identityConfirmed, isFalse);
      await again.confirmIdentity(_existingUser);
      expect(again.identityConfirmed, isTrue);
      // Confirming keeps it a further device: the mint makes no UMK.
      final third = await _ledger(keys, db: db);
      await third.openIdentity();
      await third.mintForRegistration();
      expect(await keys.contains(KeyIds.wrappedUmk), isFalse);
    });

    test('C-04b-4 adoption is refused once the identity is confirmed or '
        'anything was authored under it; nothing is rewritten', () async {
      final l = await _ledger(keys);
      final id = await l.bootstrapSolo();
      await l.confirmIdentity(id.userId);
      await expectLater(
        l.adoptExistingAccount(_existingUser),
        throwsA(isA<IdentityNotProvisional>()),
      );
      expect(l.identity.userId, id.userId);

      final bare = FakeKeyStore();
      final u = await _ledger(bare, guarded: false);
      final uid = await u.bootstrapSolo(firstBookName: 'Me');
      await expectLater(
        u.adoptExistingAccount(_existingUser),
        throwsA(isA<IdentityNotProvisional>()),
      );
      expect((await readStoredIdentity(bare))!.userId, uid.userId);
    });

    test('C-04b-4 a further device keeps reopening as existing-account-no-UMK '
        'only while that is true: once rung 3 has adopted the account\'s UMK '
        'a lost wrapped UMK (or seed) is keys lost, and a filed certificate '
        'with no UMK is keys lost too — never not-registered-yet, and never a '
        'second UMK minted (review finding KEY168B-3)', () async {
      // The account, on its first phone, with its paper sheet.
      final owner = await _ledger(FakeKeyStore(), guarded: false);
      await owner.bootstrapSolo();
      final sheet = owner.makeRecoverySheet();
      addTearDown(sheet.dispose);
      final published = owner.keyMaterial.umk.public;

      // The further device: adopted, seeds only, then the sheet scanned.
      final db = await openTestDb();
      final l = await _ledger(keys, db: db);
      await l.openIdentity();
      await l.adoptExistingAccount(owner.identity.userId);
      expect(l.awaitingAccountUmk, isTrue);
      await l.mintForRegistration();
      expect(await keys.contains(KeyIds.wrappedUmk), isFalse);
      expect(
        await l.adoptRecoveredUmk(
          sealedBlob: sheet.sealedBlob,
          rk: sheet.rk,
          sheetUserId: sheet.userId,
          expected: published,
        ),
        isA<RecoveredUmkAdopted>(),
      );
      expect(l.awaitingAccountUmk, isFalse);
      await l.confirmIdentity(owner.identity.userId);

      // Whole: reopens with the account's UMK; the mint makes no second one.
      final whole = await _ledger(keys, db: db);
      await whole.openIdentity();
      expect(whole.keyMaterial.umk.public, published);
      final wrapped = await keys.read(KeyIds.wrappedUmk);
      await whole.mintForRegistration();
      expect(await keys.read(KeyIds.wrappedUmk), wrapped);

      // The wrapped UMK lost: keys lost, not an existing account awaiting it.
      await keys.delete(KeyIds.wrappedUmk);
      final lost = await _ledger(keys, db: db);
      await expectLater(
        lost.openIdentity(),
        throwsA(
          isA<DeviceKeysMissing>().having(
            (e) => e.deviceKeys,
            'deviceKeys',
            isFalse,
          ),
        ),
      );
      expect(lost.isOpen, isFalse);

      // A seed lost instead: keys lost too, nothing minted over it.
      await keys.write(KeyIds.wrappedUmk, wrapped!);
      await keys.delete(KeyIds.deviceSigningKey);
      final seedless = await _ledger(keys, db: db);
      await expectLater(
        seedless.openIdentity(),
        throwsA(
          isA<DeviceKeysMissing>().having(
            (e) => e.deviceKeys,
            'deviceKeys',
            isTrue,
          ),
        ),
      );
      expect(await keys.contains(KeyIds.deviceSigningKey), isFalse);

      // Never adopted, but a certificate filed: that needed a UMK, so it is
      // keys lost as well.
      final other = FakeKeyStore();
      final odb = await openTestDb();
      final f = await _ledger(other, db: odb);
      await f.openIdentity();
      await f.adoptExistingAccount(_existingUser);
      await f.mintForRegistration();
      final healthy = await _ledger(other, db: odb);
      await healthy.openIdentity();
      expect(healthy.awaitingAccountUmk, isTrue, reason: 'case 2 still opens');
      await other.write(LocalLedgerKeys.deviceCert, Uint8List(4));
      final certified = await _ledger(other, db: odb);
      await expectLater(
        certified.openIdentity(),
        throwsA(
          isA<DeviceKeysMissing>().having(
            (e) => e.deviceKeys,
            'deviceKeys',
            isFalse,
          ),
        ),
      );
    });
  });

  group('C-1009-1 the ledger binding is read late (ADR 2026-10-09 §1)', () {
    test('C-1009-1 an engine, guard and trust store built once over the '
        'binding before S0.2 hold notRegistered and send nothing; the S0.2 '
        'mint takes effect at the next round with no rebuild, and a re-mint '
        'is answered under the new ids', () async {
      final l = await _ledger(keys, guarded: false);
      final id = await l.openIdentity();
      final rig = _engineOver(l);

      expect(rig.engine.hold, eng.SyncHold.notRegistered);
      expect((await rig.engine.sync()).held, eng.SyncHold.notRegistered);
      expect(rig.transport.calls, isEmpty);
      expect(rig.guard.boundTo(id.deviceId), isFalse);
      expect(rig.engine.trust.umks.verifiedUmkOf(id.userId), isNull);

      // Re-minted before S0.2: the binding names the new user at once.
      final fresh = await l.remintProvisionalIdentity();
      expect(rig.engine.hold, eng.SyncHold.notRegistered);

      await l.mintForRegistration();

      expect(rig.engine.hold, isNull);
      expect(rig.guard.boundTo(id.deviceId), isTrue);
      expect(
        rig.engine.identity.currentIdentity(),
        eng.RegisteredIdentity(
          deviceId: id.deviceId,
          userId: fresh,
          tenantId: l.identity.tenantId,
        ),
      );
      expect(rig.engine.trust.umks.verifiedUmkOf(fresh), isNotNull);
      expect(rig.engine.trust.umks.verifiedUmkOf(id.userId), isNull);
      final report = await rig.engine.sync();
      expect(report.held, isNull);
      expect(rig.transport.calls, isNotEmpty);
    });

    test('C-1009-1 the binding is borrowed: after dispose the guard refuses '
        'the zeroised pair rather than using it', () async {
      final l = await _ledger(keys, guarded: false);
      final id = await l.bootstrapSolo();
      final rig = _engineOver(l);
      expect(rig.guard.boundTo(id.deviceId), isTrue);
      l.dispose();
      expect(rig.guard.boundTo(id.deviceId), isFalse);
      expect(l.binding.currentKeys(), const eng.KeysNotRegisteredYet());
    });
  });

  group('C-1006-1 S0.2\'s mint lands in the non-biometric device-key class '
      '(ADR 2026-10-06 §1)', () {
    late AndroidKeystoreEmulator android;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      android = AndroidKeystoreEmulator()..install();
      // A phone with a biometric enrolled: the case where a biometric-bound
      // class would have been chosen before ADR 2026-10-06.
      android.enrolled = true;
    });

    test(
      'C-1006-1 the first launch writes no device-key item; the S0.2 step '
      'writes the two seeds and the wrapped UMK straight into the '
      'hardware-backed class on the app channel — no biometric or PIN-only '
      'namespace, no enforceBiometrics option — and they reopen there',
      () async {
        final store = KeychainKeyStore()
          ..setPromptCopy(
            title: 'Unlock',
            subtitle: 'Touch',
            cancel: 'Use PIN',
          );
        expect(await store.unsealIfNoPin(), isTrue);
        final db = await openTestDb();
        final l = await _ledger(store, db: db);
        await l.openIdentity();
        expect(android.hw, isEmpty, reason: 'ids only at first launch');
        // A relaunch and a re-mint before S0.2 never look for a device key:
        // with no class recorded such a read would go to the legacy
        // biometric class and ask the person for a biometric.
        final relaunched = await _ledger(store, db: db);
        await relaunched.openIdentity();
        await relaunched.remintProvisionalIdentity();
        expect(android.callsTo(biometricNs), isEmpty);
        expect(android.hw, isEmpty);

        await relaunched.mintForRegistration();
        await l.mintForRegistration(); // the same store: reuses, mints nothing

        expect(android.hw.keys.toSet(), _keyItems.toSet());
        expect(
          l.keyMaterial.device.public,
          relaunched.keyMaterial.device.public,
        );
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

        final again = await _ledger(store, db: db);
        await again.openIdentity();
        expect(again.keyMaterial.device.public, l.keyMaterial.device.public);
      },
    );
  });
}
