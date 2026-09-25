@Tags(['F1'])
library;

// ADR 2026-09-24b §2 over the REAL ledger — the half of F1-24b-2 that the
// auth client's `FakeCertifier` cannot vouch for: that `LocalLedger` puts the
// UMK's own X25519 half on the offer, and that the launch-time re-offer hands
// back the certificate already on file rather than signing a new one.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show UmkKeyPair;
import 'package:data/data.dart' show LedgerDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/device_certification.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../../shared/test_app.dart';

void main() {
  group('ADR 2026-09-24b §2 — the ledger offers both UMK halves', () {
    test('F1-24b-2 issueOwnCert carries the UMK\'s own x half beside its ed '
        'half, and the certificate verifies under the pair it names', () async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      final umk = ledger.keyMaterial.umk.public;

      final offer = ledger.issueOwnCert();
      expect(offer.umkPubEd, umk.ed25519);
      expect(offer.umkPubX, umk.x25519);
      expect(offer.umkPubX, hasLength(32));
      expect(offer.umkPubX, isNot(offer.umkPubEd));
      expect(offer.cert.verify(ledger.suite, umk), isTrue);
    });

    test('F1-24b-2 reofferOwnCert is null while uncertified, then returns the '
        'FILED certificate byte for byte with both halves — it signs nothing '
        'new', () async {
      var clock = testNow();
      final ledger = await openTestLedger(now: () => clock);
      await ledger.bootstrapSolo();
      expect(ledger.reofferOwnCert(), isNull, reason: 'nothing on file yet');

      final issued = ledger.issueOwnCert().cert;
      await ledger.installOwnCert(issued);

      // A later clock: a fresh issue would carry a different issue time and
      // therefore a different signature. The re-offer must not.
      clock = clock.add(const Duration(days: 3));
      final again = ledger.reofferOwnCert()!;
      expect(again.cert.signature, issued.signature);
      expect(again.cert.issuedAtMs, issued.issuedAtMs);
      expect(again.cert.deviceId, issued.deviceId);
      final umk = ledger.keyMaterial.umk.public;
      expect(again.umkPubEd, umk.ed25519);
      expect(again.umkPubX, umk.x25519);
    });
  });

  // Owner ruling 25 Sep (PLAN desk 33): the re-offer stops once the server
  // has accepted this UMK's x half. The marker is the ledger's, in the key
  // store beside the certificate, so it survives a restart — the property a
  // per-process flag cannot give.
  group(
    'ADR 2026-09-24b §2 — the re-offer stops after the server accepted',
    () {
      Future<(LocalLedger, FakeKeyStore, LedgerDatabase)> certified() async {
        final keys = FakeKeyStore();
        final db = await openTestDb();
        final ledger = await openTestLedger(keys: keys, db: db);
        await ledger.bootstrapSolo();
        await ledger.installOwnCert(ledger.issueOwnCert().cert);
        return (ledger, keys, db);
      }

      Future<LocalLedger> relaunch(FakeKeyStore keys, LedgerDatabase db) async {
        final again = await openTestLedger(keys: keys, db: db);
        await again.bootstrapSolo();
        return again;
      }

      test(
        'F1-24b-2 once the server accepted both halves, the next launch has '
        'nothing to re-offer — the marker is persisted, not per-process',
        () async {
          final (ledger, keys, db) = await certified();
          final offer = ledger.reofferOwnCert()!;
          await ledger.recordUmkPubsAccepted(offer);
          expect(ledger.reofferOwnCert(), isNull, reason: 'this launch');

          final later = await relaunch(keys, db);
          expect(later.ownDeviceCert, isNotNull, reason: 'still certified');
          expect(later.reofferOwnCert(), isNull, reason: 'a later launch');
        },
      );

      test(
        'F1-24b-2 without an acceptance on file, every launch still re-offers '
        '(a refused or unheard re-offer records nothing)',
        () async {
          final (ledger, keys, db) = await certified();
          expect(ledger.reofferOwnCert(), isNotNull);
          final later = await relaunch(keys, db);
          expect(later.reofferOwnCert(), isNotNull);
        },
      );

      test(
        'F1-24b-2 an acceptance of a DIFFERENT x half is not this one: it is '
        'not recorded, and the re-offer continues',
        () async {
          final (ledger, keys, db) = await certified();
          final mine = ledger.reofferOwnCert()!;
          final other = UmkKeyPair.generate(ledger.suite);
          addTearDown(other.dispose);
          await ledger.recordUmkPubsAccepted(
            DeviceCertOffer(
              cert: mine.cert,
              umkPubEd: mine.umkPubEd,
              umkPubX: other.public.x25519,
            ),
          );
          expect(ledger.reofferOwnCert(), isNotNull);
          expect(await keys.read(LocalLedgerKeys.umkPubsAccepted), isNull);
          final later = await relaunch(keys, db);
          expect(later.reofferOwnCert(), isNotNull);
        },
      );

      test('F1-24b-2 a marker that will not parse, or names another x half, '
          'suppresses nothing', () async {
        final (_, keys, db) = await certified();
        await keys.write(
          LocalLedgerKeys.umkPubsAccepted,
          Uint8List.fromList(utf8.encode('not json')),
        );
        expect((await relaunch(keys, db)).reofferOwnCert(), isNotNull);

        final other = UmkKeyPair.generate(await testSuite());
        addTearDown(other.dispose);
        final ledger = await relaunch(keys, db);
        await keys.write(
          LocalLedgerKeys.umkPubsAccepted,
          encodeUmkPubsAccepted(
            deviceId: ledger.identity.deviceId,
            umkKeyVersion: umkKeyVersionFirst,
            umkPubX: other.public.x25519,
          ),
        );
        expect((await relaunch(keys, db)).reofferOwnCert(), isNotNull);
      });
    },
  );
}
