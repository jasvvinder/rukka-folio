// F1-05: a book key that arrives on the meta channel has to be on disk before
// the process ends. The guard unwraps it into the in-memory `BookKeyStore`
// (05 §5); `key_cache` is what `LocalLedger` reads back at open (03 §3.1), and
// the meta cursor passes a `wrapped_keys` row exactly once — so a key that
// only ever reached memory leaves the device in permanent `key_wait` (05 §4)
// for a book it joined and can never open again.
//
// The seam under test is `LocalLedger.keyAccepted`, the app's implementation
// of `sync_engine`'s `AcceptedKeySink`: the engine hands over the sealed blob
// as it came off the wire, the ledger owns the at-rest layout and the write.
// Nothing here unwraps a second time, and nothing re-wraps (04 §8.2 🔒).
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../test_app.dart';

/// The `wrapped_keys` row a member's device would pull for [bk]: sealed to
/// [l]'s own ceremony-verified UMK, which is the only fingerprint this
/// install will ever hold a key under (04 §8.2 🔒).
eng.WireWrappedKey wireKeyFor(LocalLedger l, BookKey bk) {
  final material = l.keyMaterial;
  final verified = material.verifiedUmkOf(l.identity.userId)!;
  final wrapped = wrapBookKey(l.suite, bk, verified);
  return eng.WireWrappedKey(
    id: l.newId(),
    kind: eng.WireWrappedKey.kindBkForUser,
    userId: l.identity.userId,
    bookId: bk.ref.bookId,
    keyVersion: bk.ref.keyVersion,
    blob: wrapped.blob,
    recipientFingerprint: wrapped.recipient.bytes,
  );
}

/// The guard the composition root builds (`bootstrap.dart`), over this
/// install's own material.
eng.CryptoGuard guardOver(LocalLedger l) {
  final m = l.keyMaterial;
  return eng.CryptoGuard(
    suite: l.suite,
    keys: m.bookKeys,
    trust: eng.RecordTrustStore(umks: m),
    me: m.device,
    umk: m.umk,
  );
}

void main() {
  group('accepted book keys reach key_cache (03 §3.1 · 05 §4, §5)', () {
    test(
      'F1-05-57 a key accepted through the guard is still held after the '
      'ledger is closed and reopened, and that book\'s envelopes open — '
      'the second launch of a device that joined somebody else\'s book',
      () async {
        final keys = FakeKeyStore();
        final db = await openTestDb();
        final a = await openTestLedger(keys: keys, db: db);
        final id = await a.bootstrapSolo(firstBookName: 'Me');

        // A book this device did not create: no key for it until one arrives
        // wrapped to this user's UMK on the meta channel.
        final joined = a.newId();
        final bk = BookKey.generate(a.suite, bookId: joined, keyVersion: 1);
        final ref = BookKeyRef(bookId: joined, keyVersion: 1);
        expect(a.keyMaterial.bookKeys.has(joined, 1), isFalse);

        final acceptance = guardOver(a).acceptWrappedKey(wireKeyFor(a, bk));
        expect(acceptance, isA<eng.KeyAccepted>());
        await a.keyAccepted((acceptance as eng.KeyAccepted).key);
        expect(a.keyMaterial.bookKeys.has(joined, 1), isTrue);

        // One envelope of that book, authored by its owner under that key. It
        // is opened below by the *reopened* ledger's copy of the key.
        final sealed = EnvelopeBuilder.seal(
          a.suite,
          tenantId: id.tenantId,
          bookId: joined,
          objectId: a.newId(),
          objectType: 'entry',
          envelopeId: a.newId(),
          hlc: 1 << 16,
          authorSeq: 1,
          object: const {'kind': 'money_out', 'n': 7},
          bookKey: bk,
          author: a.keyMaterial.device,
        );
        a.dispose();

        // Second launch: same store, same database, a new process's objects.
        final b = await openTestLedger(keys: keys, db: db);
        await b.bootstrapSolo();
        final held = b.keyMaterial.bookKeys;
        expect(
          held.has(joined, 1),
          isTrue,
          reason: 'the key came back from key_cache, not from a second pull',
        );
        final opened = sealed.open(b.suite, held.bookKey(ref)!);
        expect(opened.object['n'], 7);
        expect(opened.authorSeq, 1);
      },
    );

    test('F1-05-58 what rests is the wire blob wrapped to this user, never an '
        'unwrapped key (03 §3.1) — and a blob addressed to anybody else is '
        'refused rather than written (04 §8.2 🔒)', () async {
      final l = await openTestLedger();
      await l.bootstrapSolo(firstBookName: 'Me');
      final joined = l.newId();
      final bk = BookKey.generate(l.suite, bookId: joined, keyVersion: 1);
      final wire = wireKeyFor(l, bk);

      final accepted = guardOver(l).acceptWrappedKey(wire) as eng.KeyAccepted;
      await l.keyAccepted(accepted.key);

      final row = (await (l.db.select(
        l.db.keyCache,
      )..where((t) => t.bookId.equals(joined))).get()).single;
      expect(row.keyVersion, 1);
      // `suite_version(1) ‖ recipient fingerprint(32) ‖ sealed box`.
      expect(row.wrappedBlob[0], suiteVersion);
      expect(row.wrappedBlob.sublist(1, 33), wire.recipientFingerprint);
      expect(row.wrappedBlob.sublist(33), wire.blob);
      // A sealed box is longer than the key it hides; the key's own bytes
      // appear nowhere in the row.
      final plain = bk.key.runUnlockedSync(List<int>.from);
      expect(row.wrappedBlob.length, greaterThan(plain.length));
      expect(
        String.fromCharCodes(row.wrappedBlob)
            .contains(String.fromCharCodes(plain)),
        isFalse,
      );

      // The same blob, labelled with a fingerprint that is not this user's:
      // the ledger writes nothing rather than cache a key it could not open
      // at the next launch.
      final stranger = UmkKeyPair.generate(l.suite);
      final foreign = eng.AcceptedBookKey(
        ref: BookKeyRef(bookId: l.newId(), keyVersion: 1),
        suiteVersion: accepted.key.suiteVersion,
        recipient: Fingerprint.of(l.suite, stranger.public),
        sealed: accepted.key.sealed,
      );
      await expectLater(l.keyAccepted(foreign), throwsA(isA<ArgumentError>()));
      expect(
        await l.db.select(l.db.keyCache).get(),
        hasLength(2),
        reason: 'the first book and the joined one — nothing else',
      );
    });
  });
}
