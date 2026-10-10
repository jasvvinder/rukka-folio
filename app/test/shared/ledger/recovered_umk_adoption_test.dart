// C-1006d-1 — rung 3's two ledger doors (ADR 2026-10-06d §2 🔒; 04 §7.4,
// §7.3 step 4; ADR 2026-10-06 §1):
//
//   * `LocalLedger.makeRecoverySheet()` — RK + the sealed blob bytes that
//     `RecoveryApi.publishSheet` stores (`SealedRecoveryBlob.encode`).
//   * `LocalLedger.adoptRecoveredUmk(...)` — frame, open under the scanned
//     or typed RK, compare against the account's **published** `UmkPublic`
//     (the one the server relays; rung 3's authenticator is the AEAD under
//     the paper RK — ADR 2026-09-13c §1), and only then re-wrap to this
//     device's key and replace the install's UMK. The outcome is typed, split
//     as the S11.3 seam contract splits it: a verdict on the code
//     (`didNotOpen`, `mismatch` → R2.4), this install's state (`notThisUser`,
//     `keyInUse`), and a blob this build cannot frame, which is a throw.
//
// "Nothing stored" is asserted over the whole key store — every id the
// ledger owns, read before and after — on a phone that already holds a
// certificate and an accepted-pubs record, so a refusal that *deleted*
// something would be seen (FakeKeyStore.writes records writes only).
//
// The restoring phone is modelled as a fresh install whose identity record
// already names the account's user id — what ADR 2026-10-04b §3 (C-04b-4)
// does after `/otp/verify` answers an existing account. The record is written
// into the key store directly here because that adoption is another slice's.
//
// Synthetic ids and amounts only (CLAUDE.md rule 4).
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart' show BookType;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../test_app.dart';
import 'tenant_of.dart';

/// The account owner: a bootstrapped ledger with one book and a sheet.
/// [published] is the UMK public as the server would relay it to a wiped
/// phone — a plain `UmkPublic`, not a ceremony product.
Future<
  ({
    LocalLedger ledger,
    LedgerIdentity id,
    RecoverySheetMaterial sheet,
    UmkPublic published,
  })
>
account() async {
  final a = await openTestLedger();
  final id = await a.bootstrapSolo(firstBookName: 'Me');
  final sheet = a.makeRecoverySheet();
  addTearDown(sheet.dispose);
  return (ledger: a, id: id, sheet: sheet, published: a.keyMaterial.umk.public);
}

/// A fresh phone whose identity already carries [userId] (ADR 2026-10-04b
/// §3), with its own device keys and a provisional UMK of its own. With
/// [certified], it also holds a certificate and an accepted-pubs record under
/// that provisional UMK — what S0.2 may have filed before the restore.
Future<({LocalLedger ledger, FakeKeyStore keys, String ownUserId})> freshPhone(
  String userId, {
  bool certified = false,
}) async {
  final keys = FakeKeyStore();
  final db = await openTestDb();
  final first = await openTestLedger(keys: keys, db: db);
  final minted = await first.bootstrapSolo();
  first.dispose();
  await keys.write(
    LocalLedgerKeys.identity,
    LedgerIdentity(
      deviceId: minted.deviceId,
      userId: userId,
      tenantId: minted.tenantId,
    ).encode(suiteVersion: suiteVersion),
  );
  final b = await openTestLedger(keys: keys, db: db);
  final id = await b.bootstrapSolo();
  expect(id.userId, userId);
  expect(id.deviceId, minted.deviceId);
  if (certified) {
    final offer = b.issueOwnCert();
    await b.installOwnCert(offer.cert);
    await b.recordUmkPubsAccepted(offer);
    expect(b.ownDeviceCert, isNotNull);
    expect(await keys.contains(LocalLedgerKeys.deviceCert), isTrue);
    expect(await keys.contains(LocalLedgerKeys.umkPubsAccepted), isTrue);
  }
  return (ledger: b, keys: keys, ownUserId: minted.userId);
}

/// Every id the ledger keeps in the store (KeyIds + LocalLedgerKeys), with
/// its bytes or null when absent. Equal before and after ⇔ nothing was
/// written **or deleted**.
const _allKeyIds = [
  KeyIds.databaseKey,
  KeyIds.deviceSigningKey,
  KeyIds.deviceAgreementKey,
  KeyIds.wrappedUmk,
  KeyIds.recoveryCandidate,
  LocalLedgerKeys.identity,
  LocalLedgerKeys.identityState,
  LocalLedgerKeys.deviceCert,
  LocalLedgerKeys.umkPubsAccepted,
];

Future<Map<String, List<int>?>> snapshot(KeyStore keys) async => {
  for (final id in _allKeyIds) id: (await keys.read(id))?.toList(),
};

void main() {
  group('rung 3 adoption (ADR 2026-10-06d §2 · 04 §7.4)', () {
    test('C-1006d-1 makeRecoverySheet seals this install\'s UMK under a fresh '
        'RK as 105 wire bytes that open back to the same UMK; every call '
        'rotates RK (04 §7.4) and the blob never carries the key', () async {
      final a = await account();
      final s = a.ledger.suite;
      expect(a.sheet.userId, a.id.userId);
      expect(a.sheet.sealedBlob.length, sealedRecoveryBlobBytes);
      expect(a.sheet.sealedBlob[0], suiteVersion);

      final opened = openUmkWithRecoveryKey(
        s,
        a.sheet.rk,
        SealedRecoveryBlob.decode(a.sheet.sealedBlob),
      );
      addTearDown(opened.dispose);
      expect(opened.public, a.ledger.keyMaterial.umk.public);

      // Regenerating rotates RK: the earlier sheet no longer opens the
      // new blob, and vice versa.
      final again = a.ledger.makeRecoverySheet();
      addTearDown(again.dispose);
      expect(again.sealedBlob, isNot(a.sheet.sealedBlob));
      expect(
        () => openUmkWithRecoveryKey(
          s,
          a.sheet.rk,
          SealedRecoveryBlob.decode(again.sealedBlob),
        ),
        throwsA(isA<RecoveryUnsealFailed>()),
      );

      // No secret in the blob: neither RK nor a UMK seed appears in it.
      final rkBytes = a.sheet.rk.key.extractBytes();
      final umkBytes = a.ledger.keyMaterial.umk.exportSecretBytes();
      expect(_contains(a.sheet.sealedBlob, rkBytes), isFalse);
      expect(
        _contains(a.sheet.sealedBlob, Uint8List.sublistView(umkBytes, 0, 32)),
        isFalse,
      );
      s.zeroize(rkBytes);
      s.zeroize(umkBytes);
    });

    test('C-1006d-1 a sheet that opens to the account\'s published UMK is '
        'adopted on a wiped phone that holds only the relayed UmkPublic: the '
        'install\'s UMK becomes the account\'s, re-wrapped to this device\'s '
        'unchanged key and persisted (a cold reopen holds it), its own '
        'VerifiedUmkPublic comes from possession, the old UMK is retired not '
        'zeroised while a borrowed material may point at it, and a certificate '
        'filed under the replaced UMK is dropped', () async {
      final a = await account();
      final p = await freshPhone(a.id.userId, certified: true);
      final b = p.ledger;

      final before = b.keyMaterial;
      final wrappedBefore = await p.keys.read(KeyIds.wrappedUmk);
      expect(before.umk.public, isNot(a.published));
      var adopted = 0;
      b.onUmkAdopted = () => adopted++;

      final outcome = await b.adoptRecoveredUmk(
        sealedBlob: a.sheet.sealedBlob,
        rk: a.sheet.rk,
        sheetUserId: a.sheet.userId,
        expected: a.published,
      );
      expect(outcome, isA<RecoveredUmkAdopted>());
      expect(adopted, 1);

      // The material is now the account's key, on the same device; the
      // install's own verified public is the recovered pair's, matching
      // what the owner's own ledger verified for itself.
      final after = b.keyMaterial;
      expect(after.umk.public, a.published);
      expect(
        after.verifiedUmkOf(a.id.userId)!.fingerprint,
        a.ledger.keyMaterial.verifiedUmkOf(a.id.userId)!.fingerprint,
      );
      expect(identical(after.device, before.device), isTrue);
      expect(after.userId, a.id.userId);
      // Retired, not zeroised (a guard built from `before` still holds it).
      expect(before.umk.isDisposed, isFalse);
      expect(identical(after.umk, before.umk), isFalse);
      // The stale certificate and accepted-pubs record are gone.
      expect(b.ownDeviceCert, isNull);
      expect(await p.keys.contains(LocalLedgerKeys.deviceCert), isFalse);
      expect(await p.keys.contains(LocalLedgerKeys.umkPubsAccepted), isFalse);

      // Re-wrapped to this device as at signup (ADR 2026-10-06 §1): the
      // stored wrap changed, and a cold reopen over the same store opens
      // to the adopted key with the same device.
      final wrappedAfter = await p.keys.read(KeyIds.wrappedUmk);
      expect(wrappedAfter, isNot(wrappedBefore));
      final storedId = await p.keys.read(LocalLedgerKeys.identity);
      b.dispose();
      expect(before.umk.isDisposed, isTrue);
      final reopened = await openTestLedger(keys: p.keys, db: b.db);
      final id = await reopened.bootstrapSolo();
      expect(id.userId, a.id.userId);
      expect(reopened.keyMaterial.umk.public, a.published);
      expect(reopened.keyMaterial.device.public, before.device.public);
      expect(await p.keys.read(LocalLedgerKeys.identity), storedId);
    });

    test('C-1006d-1 a blob that opens to a key other than the account\'s '
        'published one is refused as mismatch with nothing stored or deleted '
        '— the UMK, the wrap, the certificate, the accepted-pubs record and '
        'the borrowed material are untouched (04 §7.3 step 4)', () async {
      final a = await account();
      final other = await openTestLedger();
      await other.bootstrapSolo();
      final foreign = other.keyMaterial.umk.public;
      final p = await freshPhone(a.id.userId, certified: true);
      final b = p.ledger;
      final before = b.keyMaterial;
      final cert = b.ownDeviceCert;
      final store = await snapshot(p.keys);
      var adopted = 0;
      b.onUmkAdopted = () => adopted++;

      final outcome = await b.adoptRecoveredUmk(
        sealedBlob: a.sheet.sealedBlob,
        rk: a.sheet.rk,
        sheetUserId: a.sheet.userId,
        expected: foreign,
      );
      expect(
        outcome,
        isA<RecoveredUmkRefused>().having(
          (r) => r.reason,
          'reason',
          RecoveredUmkRefusal.mismatch,
        ),
      );
      expect(adopted, 0);
      expect(identical(b.keyMaterial.umk, before.umk), isTrue);
      expect(identical(b.ownDeviceCert, cert), isTrue);
      expect(await snapshot(p.keys), store);
    });

    test('C-1006d-1 a code that does not open the blob (another sheet\'s RK) '
        'is refused as didNotOpen — R2.4\'s "that code didn\'t work" — while '
        'a blob this build cannot frame (truncated, empty, a future suite '
        'byte) is a RecoveryBlobNotFramed throw that says nothing about the '
        'code; nothing is stored or deleted on either path', () async {
      final a = await account();
      final p = await freshPhone(a.id.userId, certified: true);
      final b = p.ledger;
      final before = b.keyMaterial;
      final cert = b.ownDeviceCert;
      final store = await snapshot(p.keys);
      var adopted = 0;
      b.onUmkAdopted = () => adopted++;
      final wrongRk = RecoveryKey.generate(b.suite);
      addTearDown(wrongRk.dispose);

      Future<RecoveredUmkOutcome> attempt(Uint8List blob, RecoveryKey rk) =>
          b.adoptRecoveredUmk(
            sealedBlob: blob,
            rk: rk,
            sheetUserId: a.sheet.userId,
            expected: a.published,
          );

      // The code's fault: the AEAD refused.
      expect(
        await attempt(a.sheet.sealedBlob, wrongRk),
        isA<RecoveredUmkRefused>().having(
          (r) => r.reason,
          'reason',
          RecoveredUmkRefusal.didNotOpen,
        ),
      );

      // Not the code's fault: this build cannot frame the blob. The right
      // RK is passed each time, so a refusal here would blame a good code.
      Future<void> unframed(Uint8List blob, String reason) async {
        await expectLater(
          attempt(blob, a.sheet.rk),
          throwsA(
            isA<RecoveryBlobNotFramed>().having(
              (e) => e.reason,
              'reason',
              reason,
            ),
          ),
        );
      }

      await unframed(
        Uint8List.sublistView(a.sheet.sealedBlob, 0, 90),
        'length',
      );
      await unframed(Uint8List(0), 'length');
      await unframed(
        Uint8List.fromList(a.sheet.sealedBlob)..[0] = 0x02,
        'suite',
      );

      expect(adopted, 0);
      expect(identical(b.keyMaterial.umk, before.umk), isTrue);
      expect(identical(b.ownDeviceCert, cert), isTrue);
      expect(await snapshot(p.keys), store);

      // The same sheet with the right code still adopts afterwards: a
      // refusal costs nothing but the attempt.
      expect(
        await attempt(a.sheet.sealedBlob, a.sheet.rk),
        isA<RecoveredUmkAdopted>(),
      );
      expect(adopted, 1);
    });

    test('C-1006d-1 a sheet naming another user than this install\'s identity '
        'is refused as notThisUser before the blob is tried, and an install '
        'that has already authored under its current UMK is refused as '
        'keyInUse — nothing stored or deleted either way', () async {
      final a = await account();

      // Still on its own provisional id: the sheet is somebody else's.
      final strangerKeys = FakeKeyStore();
      final stranger = await openTestLedger(keys: strangerKeys);
      await stranger.bootstrapSolo();
      final m0 = stranger.keyMaterial;
      final store0 = await snapshot(strangerKeys);
      final r0 = await stranger.adoptRecoveredUmk(
        sealedBlob: a.sheet.sealedBlob,
        rk: a.sheet.rk,
        sheetUserId: a.sheet.userId,
        expected: a.published,
      );
      expect(
        r0,
        isA<RecoveredUmkRefused>().having(
          (r) => r.reason,
          'reason',
          RecoveredUmkRefusal.notThisUser,
        ),
      );
      expect(identical(stranger.keyMaterial.umk, m0.umk), isTrue);
      expect(await snapshot(strangerKeys), store0);

      // Right user, but a book already exists under the current UMK:
      // adopting another key would strand it (⚠️ SPEC: 06 §5 "every rung
      // fails" leaves which key wins unspecified — fail closed).
      final p = await freshPhone(a.id.userId, certified: true);
      final b = p.ledger;
      await b.createBook(name: 'Shop', type: BookType.business);
      final m1 = b.keyMaterial;
      final cert = b.ownDeviceCert;
      final store1 = await snapshot(p.keys);
      final r1 = await b.adoptRecoveredUmk(
        sealedBlob: a.sheet.sealedBlob,
        rk: a.sheet.rk,
        sheetUserId: a.sheet.userId,
        expected: a.published,
      );
      expect(
        r1,
        isA<RecoveredUmkRefused>().having(
          (r) => r.reason,
          'reason',
          RecoveredUmkRefusal.keyInUse,
        ),
      );
      expect(identical(b.keyMaterial.umk, m1.umk), isTrue);
      expect(identical(b.ownDeviceCert, cert), isTrue);
      expect(await snapshot(p.keys), store1);
    });
  });
}

/// Whether [needle] occurs contiguously in [haystack] (test code only).
bool _contains(Uint8List haystack, Uint8List needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
