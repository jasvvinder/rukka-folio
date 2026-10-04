// ADR 2026-10-04b §2 🔒 — the first-run identity is provisional until signup
// answers with it. `_firstRun` mints device, user and tenant ids, the device
// keys and a UMK before the network is reached; until `/otp/verify` has echoed
// that same `user_id`, the install authors nothing under them. The guard is
// switched on by the composition root (`requireConfirmedIdentity`, pinned in
// `test/shared/sync/bootstrap_wiring_test.dart`); every other suite keeps
// constructing ledgers without it.
//
// §2 last bullet: on `409 user_id_taken` the install discards the provisional
// identity and mints a fresh one — only while provisional and only while
// nothing has been authored (C-04b-3).
//
// In-memory SQLite, FakeKeyStore, injected clock, libsodium. Synthetic ids.
@Tags(['C'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart' show BookType;
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../test_app.dart';

const String _member = '55555555-5555-4555-8555-555555555551';

/// A ledger built the way the composition root builds it: the guard on.
Future<LocalLedger> _guarded(FakeKeyStore keys, {LedgerDatabase? db}) async {
  final l = LocalLedger(
    db: db ?? await openTestDb(),
    keys: keys,
    suite: await testSuite(),
    now: testNow,
    requireConfirmedIdentity: true,
  );
  addTearDown(l.dispose);
  return l;
}

/// What a provisional install must not hold: no book key, no envelope, no
/// outbox row, no signed record.
Future<void> _expectNothingAuthored(LocalLedger l) async {
  expect(await l.db.select(l.db.keyCache).get(), isEmpty, reason: 'key');
  expect(await l.mirror.bookIds(), isEmpty, reason: 'envelope');
  expect(await l.db.select(l.db.outbox).get(), isEmpty, reason: 'outbox');
  expect(
    await l.db.select(l.db.signedRecordsLocal).get(),
    isEmpty,
    reason: 'signed record',
  );
}

VerifiedUmkPublic _verifiedStranger(CryptoSuite suite) {
  final umk = UmkKeyPair.generate(suite);
  return (Ceremony.verifyQr(
    suite,
    scanned: QrPayload(
      userId: _member,
      umk: umk.public,
      nonce: suite.randomBytes(ceremonyNonceBytes),
    ),
    relayed: umk.public,
    relayedUserId: _member,
  ) as CeremonyVerified).verified;
}

void main() {
  late FakeKeyStore keys;

  setUp(() => keys = FakeKeyStore());

  group('C-04b-2 the first-run identity is provisional (ADR 2026-10-04b §2)', () {
    test('C-04b-2 a first run is provisional: identityConfirmed is false and, '
        'with the guard on, createBook refuses IdentityNotConfirmed before a '
        'book key, an envelope or an outbox row exists', () async {
      final l = await _guarded(keys);
      await l.bootstrapSolo();
      expect(l.identityConfirmed, isFalse);
      expect(l, isA<SignupIdentity>());

      await expectLater(
        l.createBook(name: 'Me', type: BookType.personal),
        throwsA(isA<IdentityNotConfirmed>()),
      );
      await _expectNothingAuthored(l);
    });

    test('C-04b-2 while provisional every other authoring door refuses too: '
        'bootstrapSolo(firstBookName:), the device certificate (issue, file, '
        'UMK pubs accepted), an accepted book key and a verification record; '
        'the launch re-offer offers nothing', () async {
      final l = await _guarded(keys);
      await expectLater(
        l.bootstrapSolo(firstBookName: 'Me'),
        throwsA(isA<IdentityNotConfirmed>()),
      );
      expect(l.isOpen, isTrue, reason: 'the identity itself still opens');

      expect(() => l.issueOwnCert(), throwsA(isA<IdentityNotConfirmed>()));
      expect(l.reofferOwnCert(), isNull);

      // A certificate this device could have issued, had it been allowed.
      final cert = DeviceCert.issue(
        l.suite,
        issuer: l.keyMaterial.umk,
        userId: l.identity.userId,
        device: l.keyMaterial.device.public,
        issuedAtMs: testNow().millisecondsSinceEpoch,
      );
      await expectLater(
        l.installOwnCert(cert),
        throwsA(isA<IdentityNotConfirmed>()),
      );
      expect(l.ownDeviceCert, isNull);
      await expectLater(
        l.recordUmkPubsAccepted(
          DeviceCertOffer(
            cert: cert,
            umkPubEd: l.keyMaterial.umk.public.ed25519,
            umkPubX: l.keyMaterial.umk.public.x25519,
          ),
        ),
        throwsA(isA<IdentityNotConfirmed>()),
      );
      expect(await keys.contains(LocalLedgerKeys.umkPubsAccepted), isFalse);
      expect(await keys.contains(LocalLedgerKeys.deviceCert), isFalse);

      final bk = BookKey.generate(l.suite, bookId: l.newId(), keyVersion: 1);
      final wrapped = wrapBookKey(
        l.suite,
        bk,
        l.keyMaterial.verifiedUmkOf(l.identity.userId)!,
      );
      await expectLater(
        l.keyAccepted(
          eng.AcceptedBookKey(
            ref: bk.ref,
            suiteVersion: wrapped.suiteVersion,
            recipient: wrapped.recipient,
            sealed: wrapped.sealed.bytes,
          ),
        ),
        throwsA(isA<IdentityNotConfirmed>()),
      );

      await expectLater(
        l.verifiedMembers.storeVerified(
          userId: _member,
          verified: _verifiedStranger(l.suite),
          method: VerificationMethod.codeRemote,
        ),
        throwsA(isA<IdentityNotConfirmed>()),
      );
      await _expectNothingAuthored(l);
    });

    test(
      'C-04b-2 confirmIdentity with the install\'s own user id is persisted: '
      'the ledger authors, and a new ledger over the same store reopens '
      'confirmed; another id is refused and changes nothing',
      () async {
        final db = await openTestDb();
        final l = await _guarded(keys, db: db);
        final id = await l.bootstrapSolo();

        await expectLater(
          l.confirmIdentity('7d2f9c1a-4b6e-4c8d-9e0f-1a2b3c4d5e6f'),
          throwsA(isA<ArgumentError>()),
        );
        expect(l.identityConfirmed, isFalse);

        await l.confirmIdentity(id.userId);
        expect(l.identityConfirmed, isTrue);
        await l.confirmIdentity(id.userId); // idempotent
        final bookId = await l.createBook(name: 'Me', type: BookType.personal);
        expect(await l.mirror.bookIds(), [bookId]);

        final again = await _guarded(keys, db: db);
        await again.bootstrapSolo();
        expect(again.identity.userId, id.userId);
        expect(again.identityConfirmed, isTrue);
      },
    );

    test(
      'C-04b-2 a provisional identity stays provisional across a relaunch',
      () async {
        final db = await openTestDb();
        await (await _guarded(keys, db: db)).bootstrapSolo();
        final again = await _guarded(keys, db: db);
        await again.bootstrapSolo();
        expect(again.identityConfirmed, isFalse);
        await expectLater(
          again.createBook(name: 'Me', type: BookType.personal),
          throwsA(isA<IdentityNotConfirmed>()),
        );
      },
    );

    test('C-04b-2 legacy installs are never locked out: an identity stored '
        'before the guard (no identity-state record) reopens confirmed — with '
        'books or without — and authors', () async {
      // With books: the shape of every install that already has a ledger.
      final db = await openTestDb();
      final before = await openTestLedger(keys: keys, db: db);
      await before.bootstrapSolo(firstBookName: 'Me');
      await keys.delete(LocalLedgerKeys.identityState);

      final l = await _guarded(keys, db: db);
      await l.bootstrapSolo();
      expect(l.identityConfirmed, isTrue);
      await l.createBook(name: 'Shop', type: BookType.business);
      expect(await l.mirror.bookIds(), hasLength(2));

      // Without books.
      final bare = FakeKeyStore();
      await (await openTestLedger(keys: bare)).bootstrapSolo();
      await bare.delete(LocalLedgerKeys.identityState);
      final m = await _guarded(bare);
      await m.bootstrapSolo();
      expect(m.identityConfirmed, isTrue);
      await m.createBook(name: 'Me', type: BookType.personal);
    });

    test('C-04b-2 the guard is the composition root\'s switch: a ledger built '
        'without it authors while provisional (every other suite), and still '
        'reports the identity provisional', () async {
      final l = await openTestLedger(keys: keys);
      await l.bootstrapSolo(firstBookName: 'Me');
      expect(l.identityConfirmed, isFalse);
      expect(await l.mirror.bookIds(), hasLength(1));
    });
  });

  group('C-04b-3 a taken user id is re-minted once (ADR 2026-10-04b §2)', () {
    test('C-04b-3 remintProvisionalIdentity mints a fresh user id, tenant id '
        'and UMK, keeps the device id and device keys (ADR 2026-09-16 §1), '
        'rewrites the stored identity and stays provisional', () async {
      final db = await openTestDb();
      final l = await _guarded(keys, db: db);
      final old = await l.bootstrapSolo();
      final oldUmk = Uint8List.fromList(l.keyMaterial.umk.public.ed25519);
      final edSeed = await keys.read(KeyIds.deviceSigningKey);
      final xSeed = await keys.read(KeyIds.deviceAgreementKey);

      final fresh = await l.remintProvisionalIdentity();

      expect(Uuid16.isCanonical(fresh), isTrue);
      expect(fresh, isNot(old.userId));
      expect(l.identity.userId, fresh);
      expect(l.identity.tenantId, isNot(old.tenantId));
      expect(Uuid16.isCanonical(l.identity.tenantId), isTrue);
      expect(l.identity.deviceId, old.deviceId);
      expect(l.keyMaterial.device.deviceId, old.deviceId);
      expect(await keys.read(KeyIds.deviceSigningKey), edSeed);
      expect(await keys.read(KeyIds.deviceAgreementKey), xSeed);
      expect(l.keyMaterial.umk.public.ed25519, isNot(oldUmk));
      expect(l.keyMaterial.verifiedUmkOf(fresh), isNotNull);
      expect(l.identityConfirmed, isFalse);

      final stored = await readStoredIdentity(keys);
      expect(stored!.userId, fresh);
      expect(stored.tenantId, l.identity.tenantId);
      expect(stored.deviceId, old.deviceId);

      // The re-minted identity is what a relaunch opens, still provisional,
      // and it confirms under the new id only.
      final again = await _guarded(keys, db: db);
      await again.bootstrapSolo();
      expect(again.identity.userId, fresh);
      expect(again.identityConfirmed, isFalse);
      await expectLater(
        again.confirmIdentity(old.userId),
        throwsA(isA<ArgumentError>()),
      );
      await again.confirmIdentity(fresh);
      expect(again.identityConfirmed, isTrue);
    });

    test('C-04b-3 a re-mint never zeroises key material a holder borrowed '
        'before it (the sync guard): the old UMK is retired, the root is '
        'told once through onIdentityReminted, and dispose() zeroises the '
        'retired UMK with the live one (review finding ID107C-3)', () async {
      final l = await _guarded(keys);
      await l.bootstrapSolo();
      final borrowed = l.keyMaterial;
      var told = 0;
      l.onIdentityReminted = () => told++;

      await l.remintProvisionalIdentity();

      expect(told, 1);
      expect(borrowed.umk.isDisposed, isFalse);
      expect(() => borrowed.umk.x25519Secret, returnsNormally);
      final live = l.keyMaterial.umk;
      expect(identical(live, borrowed.umk), isFalse);

      l.dispose();
      expect(borrowed.umk.isDisposed, isTrue);
      expect(live.isDisposed, isTrue);
      expect(() => borrowed.umk.x25519Secret, throwsStateError);
    });

    test('C-04b-3 a refused re-mint tells nobody', () async {
      final l = await _guarded(keys);
      final id = await l.bootstrapSolo();
      await l.confirmIdentity(id.userId);
      var told = 0;
      l.onIdentityReminted = () => told++;
      await expectLater(
        l.remintProvisionalIdentity(),
        throwsA(isA<IdentityNotProvisional>()),
      );
      expect(told, 0);
    });

    test('C-04b-3 a re-mint is refused once the identity is confirmed, and '
        'once anything was authored under it — nothing is rewritten', () async {
      final l = await _guarded(keys);
      final id = await l.bootstrapSolo();
      await l.confirmIdentity(id.userId);
      await expectLater(
        l.remintProvisionalIdentity(),
        throwsA(isA<IdentityNotProvisional>()),
      );
      expect(l.identity.userId, id.userId);

      // Authored while provisional: only an unguarded ledger can get here,
      // and a re-mint must still refuse — the book is sealed under the id.
      final bare = FakeKeyStore();
      final u = await openTestLedger(keys: bare);
      final uid = await u.bootstrapSolo(firstBookName: 'Me');
      await expectLater(
        u.remintProvisionalIdentity(),
        throwsA(isA<IdentityNotProvisional>()),
      );
      expect(u.identity.userId, uid.userId);
      expect((await readStoredIdentity(bare))!.userId, uid.userId);
    });

    test('C-04b-3 a legacy identity is never re-minted', () async {
      await (await openTestLedger(keys: keys)).bootstrapSolo();
      await keys.delete(LocalLedgerKeys.identityState);
      final l = await _guarded(keys);
      final id = await l.bootstrapSolo();
      await expectLater(
        l.remintProvisionalIdentity(),
        throwsA(isA<IdentityNotProvisional>()),
      );
      expect(l.identity.userId, id.userId);
    });
  });
}
