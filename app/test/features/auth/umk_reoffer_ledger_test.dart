@Tags(['F1'])
library;

// ADR 2026-09-24b §2 over the REAL ledger — the half of F1-24b-2 that the
// auth client's `FakeCertifier` cannot vouch for: that `LocalLedger` puts the
// UMK's own X25519 half on the offer, and that the launch-time re-offer hands
// back the certificate already on file rather than signing a new one.
import 'package:flutter_test/flutter_test.dart';

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
}
