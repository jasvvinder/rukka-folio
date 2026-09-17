// F1-05: the one seam this install's key material leaves the ledger through
// (`LocalLedger.keyMaterial`), and the property that makes it correct — the
// book-key store the sync engine's guard reads is the *same* store the
// projector opens envelopes with (05 §4 `key_wait` drains once, 05 §5 key
// rotation and own-device wipe reach both halves at once).
//
// What is deliberately NOT here: a second key-unwrap path. Nothing in this
// file (or in bootstrap) unwraps a UMK or a book key — that stays inside
// `LocalLedger`, and the material is a borrowed view of what it already holds.
import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../test_app.dart';

void main() {
  group('LedgerKeyMaterial (04 §3.4, §8.2 · 05 §1, §5)', () {
    test(
      'F1-05-43 keyMaterial is LedgerNotOpen before bootstrapSolo and again '
      'after dispose — and a reference kept across dispose holds no key',
      () async {
        final l = await openTestLedger();
        expect(() => l.keyMaterial, throwsA(isA<LedgerNotOpen>()));

        final id = await l.bootstrapSolo(firstBookName: 'Me');
        final bookId = (await l.mirror.bookIds()).single;
        final material = l.keyMaterial;
        expect(material.bookKeys.has(bookId, 1), isTrue);

        l.dispose();
        expect(() => l.keyMaterial, throwsA(isA<LedgerNotOpen>()));
        // The holder kept the value object; the keys inside it are gone.
        expect(material.bookKeys.has(bookId, 1), isFalse);
        expect(material.bookKeys.books, isEmpty);
        expect(material.userId, id.userId);
      },
    );

    test(
      'F1-05-44 the material is this install and only this install: its own '
      'device and UMK, and a verified UMK for its own user alone (04 §8.2)',
      () async {
        final l = await openTestLedger();
        final id = await l.bootstrapSolo(firstBookName: 'Me');
        final m = l.keyMaterial;

        expect(m.userId, id.userId);
        expect(m.device.public.deviceId, id.deviceId);
        expect(m.bookKeys.tenantId, id.tenantId);
        // Believed: this user, whose fingerprint the ledger checked
        // byte-for-byte at bootstrap.
        expect(m.verifiedUmkOf(id.userId), isNotNull);
        // Believed by nobody else: another member is trusted only after a
        // ceremony, never because this device knows their id.
        expect(m.verifiedUmkOf(id.deviceId), isNull);
        expect(m.verifiedUmkOf(l.newId()), isNull);
        // The same live objects on every read — no copy of any secret byte.
        expect(identical(l.keyMaterial.bookKeys, m.bookKeys), isTrue);
        expect(identical(l.keyMaterial.device, m.device), isTrue);
        expect(identical(l.keyMaterial.umk, m.umk), isTrue);
      },
    );

    test('F1-05-45 a real CryptoGuard built from the material shares the '
        "ledger's keys: the guard's own-revocation wipe (05 §5) leaves the "
        'ledger unable to seal, one device one wipe', () async {
      final seed = await seedSoloLedger();
      final l = seed.ledger;
      final m = l.keyMaterial;

      // Exactly the bootstrap construction (bootstrap.dart).
      final trust = eng.RecordTrustStore(umks: m);
      final guard = eng.CryptoGuard(
        suite: l.suite,
        keys: m.bookKeys,
        trust: trust,
        me: m.device,
        umk: m.umk,
      );
      expect(trust.verifiedUmkOf(l.identity.userId), isNotNull);
      expect(guard.keys.has(seed.bookId, 1), isTrue);

      // A verified own-device revocation drops every book key (05 §5).
      guard.dropAllKeys();
      await expectLater(
        l.moneyIn(
          bookId: seed.bookId,
          into: seed.cashId,
          from: seed.salesId,
          paise: 1000,
          date: l.today(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('F1-05-46 a key that arrives on the guard side is the key the ledger '
        'seals under and opens with — same process, no second store (05 §5 '
        'rotation: new envelopes use the highest version)', () async {
      final seed = await seedSoloLedger();
      final l = seed.ledger;
      final m = l.keyMaterial;
      final before = (await l.db.select(l.db.envelopesLocal).get()).length;

      // What `CryptoGuard.acceptWrappedKey` does on a meta pull, without
      // inventing a second unwrap path: a new version lands in the store.
      m.bookKeys.put(
        BookKey.generate(l.suite, bookId: seed.bookId, keyVersion: 2),
      );

      final entry = await l.moneyIn(
        bookId: seed.bookId,
        into: seed.cashId,
        from: seed.salesId,
        paise: 2500,
        date: l.today(),
      );

      final rows = await l.db.select(l.db.envelopesLocal).get();
      expect(rows, hasLength(before + 1));
      expect(rows.last.keyVersion, 2, reason: 'sealed under the highest');

      // And the projector opens both versions from the same store.
      await l.rebuild(seed.bookId);
      final ids = (await l.db.select(l.db.entriesP).get())
          .map((e) => e.id)
          .toSet();
      expect(ids, contains(entry.id));
      expect(ids.length, greaterThan(1), reason: 'v1 history still opens');
    });
  });
}
