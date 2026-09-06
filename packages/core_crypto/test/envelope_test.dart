@Tags(['B'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:sodium/sodium.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String objectX = '55555555-5555-4555-8555-555555555551';
const String objectY = '55555555-5555-4555-8555-555555555552';
const String bookB = '22222222-2222-4222-8222-222222222223';
const String envId = '66666666-6666-4666-8666-666666666661';

/// One sealed envelope with everything needed to open, tamper and re-seal it.
final class Fx {
  Fx(this.suite, this.key, this.author, this.envelope);

  final CryptoSuite suite;
  final BookKey key;
  final DeviceKeyPair author;
  final Envelope envelope;
}

const Map<String, Object?> sampleObject = {
  'amount_paise': 125000,
  'lines': [
    {'account': 'cash', 'dr': 125000},
    {'account': 'sales', 'cr': 125000},
  ],
  'note': 'chai and samosa',
};

Future<Fx> fx({
  int seed = 21,
  int authorSeq = 7,
  Map<String, Object?>? extra,
  int keyVersion = 1,
}) async {
  final suite = await testSuite(seed: seed);
  final key = BookKey.generate(suite, bookId: bookA, keyVersion: keyVersion);
  final author = DeviceKeyPair.generate(suite, deviceId: deviceA);
  addTearDown(key.dispose);
  addTearDown(author.dispose);
  final env = EnvelopeBuilder.seal(
    suite,
    tenantId: tenantA,
    bookId: bookA,
    objectId: objectX,
    objectType: 'entry',
    envelopeId: envId,
    hlc: 1725500000000 << 16,
    authorSeq: authorSeq,
    object: sampleObject,
    extraPayloadFields: extra,
    bookKey: key,
    author: author,
  );
  return Fx(suite, key, author, env);
}

/// The same envelope with one header field changed and the blob untouched —
/// what a hostile server can do (04 §10).
Envelope withHeader(
  Envelope e, {
  String? bookId,
  String? objectId,
  String? objectType,
  int? keyVersion,
  String? tenantId,
  Uint8List? blob,
}) => Envelope.fromParts(
  suiteVersion: e.suiteVersion,
  tenantId: tenantId ?? e.tenantId,
  bookId: bookId ?? e.bookId,
  objectId: objectId ?? e.objectId,
  objectType: objectType ?? e.objectType,
  keyVersion: keyVersion ?? e.keyVersion,
  payloadSchema: e.payloadSchema,
  authorDeviceId: e.authorDeviceId,
  hlc: e.hlc,
  envelopeId: e.envelopeId,
  blob: blob ?? e.blob,
);

Matcher openFails(EnvelopeOpenReason reason) => throwsA(
  isA<EnvelopeOpenFailed>().having((e) => e.reason, 'reason', reason),
);

void main() {
  test('B-04-22 AAD bytes follow the 🔒 order of 04 §4', () async {
    // 04 §4: aad = tenant_id ‖ book_id ‖ object_id ‖ object_type ‖
    // key_version ‖ suite_version.
    final f = await fx();
    final expected = Bytes.concat([
      Uuid16.toBytes(tenantA),
      Uuid16.toBytes(bookA),
      Uuid16.toBytes(objectX),
      Bytes.u32be(5),
      Uint8List.fromList(utf8.encode('entry')),
      Bytes.u32be(1),
      Bytes.u8(0x01),
    ]);
    expect(f.envelope.aad, expected);
    expect(f.envelope.aad.length, 16 * 3 + 4 + 5 + 4 + 1);
    expect(f.envelope.suiteVersion, suiteVersion);
    expect(f.envelope.payloadSchema, payloadSchemaCurrent);
  });

  test('B-04-23 seal → open round-trips author_seq and the object', () async {
    // ADR 2026-09-05b §3: `{author_seq, object}` inside the encrypted
    // payload; 04 §4: XChaCha20-Poly1305 over the (padded) plaintext JSON.
    final f = await fx(authorSeq: 7);
    final opened = f.envelope.open(f.suite, f.key);
    expect(opened.authorSeq, 7);
    expect(opened.object, sampleObject);
    expect(opened.raw.keys, containsAll(['author_seq', 'object']));
    expect(f.envelope.nonce.length, 24);
    expect(f.envelope.authorSig.length, 64);
    expect(f.envelope.keyVersion, 1);
    expect(f.envelope.authorDeviceId, deviceA);
    expect(f.envelope.envelopeId, envId);
    // author_seq < 1 is refused at seal (05b §3: "starting at 1").
    expect(
      () => EnvelopeBuilder.seal(
        f.suite,
        tenantId: tenantA,
        bookId: bookA,
        objectId: objectX,
        objectType: 'entry',
        envelopeId: envId,
        hlc: 1,
        authorSeq: 0,
        object: const {},
        bookKey: f.key,
        author: f.author,
      ),
      throwsArgumentError,
    );
  });

  test('B-04-24 AAD binding: a header changed by the server (book_id, object_id, object_type, key_version, tenant_id) fails to open', () async {
    // 04 §4: "the server cannot move an envelope between books or objects
    // without Poly1305 failing"; 04 §10: "re-uploaded under a different
    // book_id → AEAD verification fails".
    final f = await fx();
    final s = f.suite;
    final keyForBookB = BookKey(
      BookKeyRef(bookId: bookB, keyVersion: 1),
      s.sodium.secureCopy(f.key.key.extractBytes()),
    );
    addTearDown(keyForBookB.dispose);
    expect(
      () => withHeader(f.envelope, bookId: bookB).open(s, keyForBookB),
      openFails(EnvelopeOpenReason.aeadFailed),
    );
    expect(
      () => withHeader(f.envelope, objectId: objectY).open(s, f.key),
      openFails(EnvelopeOpenReason.aeadFailed),
    );
    expect(
      () => withHeader(f.envelope, objectType: 'account').open(s, f.key),
      openFails(EnvelopeOpenReason.aeadFailed),
    );
    expect(
      () => withHeader(f.envelope, tenantId: userB).open(s, f.key),
      openFails(EnvelopeOpenReason.aeadFailed),
    );
    // key_version: same key bytes relabelled v2 so only the AAD differs.
    final sameBytesV2 = BookKey(
      BookKeyRef(bookId: bookA, keyVersion: 2),
      s.sodium.secureCopy(f.key.key.extractBytes()),
    );
    addTearDown(sameBytesV2.dispose);
    expect(
      () => withHeader(f.envelope, keyVersion: 2).open(s, sameBytesV2),
      openFails(EnvelopeOpenReason.aeadFailed),
    );
    // The untouched envelope still opens.
    expect(f.envelope.open(s, f.key).authorSeq, 7);
  });

  test('B-04-25 a flipped ciphertext bit fails to open', () async {
    // 04 §4 AEAD integrity; 04 §8.3 — never display unverified content.
    final f = await fx();
    final blob = f.envelope.blob;
    blob[24 + 64 + 3] ^= 0x01; // inside the ciphertext
    expect(
      () => withHeader(f.envelope, blob: blob).open(f.suite, f.key),
      openFails(EnvelopeOpenReason.aeadFailed),
    );
    // Flipping a nonce byte fails the same way.
    final blob2 = f.envelope.blob;
    blob2[0] ^= 0x80;
    expect(
      () => withHeader(f.envelope, blob: blob2).open(f.suite, f.key),
      openFails(EnvelopeOpenReason.aeadFailed),
    );
  });

  test('B-04-26 wrong book key fails: a removed member\'s old version is refused typed, a foreign key fails the AEAD', () async {
    // 04 §10: "Given a removed member's device, when it pulls
    // post-rotation envelopes, then decryption fails for all of them."
    final f = await fx(keyVersion: 2);
    final oldVersion = BookKey.generate(f.suite, bookId: bookA, keyVersion: 1);
    addTearDown(oldVersion.dispose);
    expect(
      () => f.envelope.open(f.suite, oldVersion),
      openFails(EnvelopeOpenReason.keyMismatch),
    );
    // Same (book, version) label but different key bytes.
    final impostor = BookKey.generate(f.suite, bookId: bookA, keyVersion: 2);
    addTearDown(impostor.dispose);
    expect(
      () => f.envelope.open(f.suite, impostor),
      openFails(EnvelopeOpenReason.aeadFailed),
    );
    // A key for another book is refused before any decryption.
    final otherBook = BookKey.generate(f.suite, bookId: bookB, keyVersion: 2);
    addTearDown(otherBook.dispose);
    expect(
      () => f.envelope.open(f.suite, otherBook),
      openFails(EnvelopeOpenReason.keyMismatch),
    );
  });

  test('B-04-27 author_sig = Ed25519(BLAKE2b-256(ciphertext ‖ aad)) under the device key', () async {
    // 04 §4: author_sig : Ed25519( BLAKE2b(ciphertext ‖ aad) ).
    final f = await fx();
    final s = f.suite;
    final digest = s.blake2b256(
      Bytes.concat([f.envelope.ciphertext, f.envelope.aad]),
    );
    expect(f.envelope.signedDigest(s), digest);
    expect(
      s.sodium.crypto.sign.verifyDetached(
        message: digest,
        signature: f.envelope.authorSig,
        publicKey: f.author.public.ed25519,
      ),
      isTrue,
    );
    expect(f.envelope.verifyAuthorSig(s, f.author.public), isTrue);
    // A header change alters the AAD, so the same sig no longer verifies.
    expect(
      withHeader(f.envelope, bookId: bookB).verifyAuthorSig(s, f.author.public),
      isFalse,
    );
    // Another device's key does not verify it.
    final other = DeviceKeyPair.generate(s, deviceId: deviceB);
    addTearDown(other.dispose);
    expect(f.envelope.verifyAuthorSig(s, other.public), isFalse);
  });

  test('B-04-28 blob = nonce ‖ author_sig ‖ ciphertext; fromParts round-trips; blob_hash and size match', () async {
    // 03 §2.3: blob / blob_hash / size columns; ADR 2026-09-05c §2:
    // blob_hash = BLAKE2b-256(blob). ⚠️ SPEC layout chosen in envelope.dart.
    final f = await fx();
    final e = f.envelope;
    final blob = e.blob;
    expect(blob.sublist(0, 24), e.nonce);
    expect(blob.sublist(24, 88), e.authorSig);
    expect(blob.sublist(88), e.ciphertext);
    expect(e.size, blob.length);
    expect(e.blobHash(f.suite), f.suite.blake2b256(blob));
    final again = withHeader(e);
    expect(again.blob, blob);
    expect(again.nonce, e.nonce);
    expect(again.authorSig, e.authorSig);
    expect(again.ciphertext, e.ciphertext);
    expect(again.blobHash(f.suite), e.blobHash(f.suite));
    expect(again.open(f.suite, f.key).object, sampleObject);
    // Too-short blobs are refused (24 + 64 + 16 = 104 bytes minimum).
    expect(() => withHeader(e, blob: Uint8List(103)), throwsFormatException);
    expect(() => withHeader(e, blob: Uint8List(104)), returnsNormally);
  });

  test(
    'B-04-29 a seeded suite yields byte-identical envelopes run after run',
    () async {
      // 09 §1: injected RNG everywhere — deterministic crypto tests.
      final a = await fx(seed: 99);
      final b = await fx(seed: 99);
      expect(b.envelope.blob, a.envelope.blob);
      expect(b.envelope.nonce, a.envelope.nonce);
      expect(b.envelope.authorSig, a.envelope.authorSig);
      final c = await fx(seed: 100);
      expect(c.envelope.blob, isNot(a.envelope.blob));
      // Live CSPRNG: two seals of the same object never share a nonce.
      final live = await liveSuite();
      final key = BookKey.generate(live, bookId: bookA, keyVersion: 1);
      final dev = DeviceKeyPair.generate(live, deviceId: deviceA);
      addTearDown(key.dispose);
      addTearDown(dev.dispose);
      Envelope seal() => EnvelopeBuilder.seal(
        live,
        tenantId: tenantA,
        bookId: bookA,
        objectId: objectX,
        objectType: 'entry',
        envelopeId: envId,
        hlc: 1,
        authorSeq: 1,
        object: sampleObject,
        bookKey: key,
        author: dev,
      );
      expect(seal().nonce, isNot(seal().nonce));
    },
  );

  test('B-04-30 an unknown top-level payload field round-trips through seal/open and re-seal', () async {
    // CLAUDE.md rule 6 / 03 §3.3.4: preserve JSON fields you don't
    // understand.
    final f = await fx(
      extra: {
        'future_field': {
          'x': [1, 2, 3],
        },
        'v': 9,
      },
    );
    final opened = f.envelope.open(f.suite, f.key);
    expect(opened.raw['future_field'], {
      'x': [1, 2, 3],
    });
    expect(opened.raw['v'], 9);
    expect(opened.object, sampleObject);
    final v2 = BookKey.generate(f.suite, bookId: bookA, keyVersion: 2);
    addTearDown(v2.dispose);
    final resealed = EnvelopeBuilder.reseal(
      f.suite,
      f.envelope,
      oldKey: f.key,
      newKey: v2,
      author: f.author,
    );
    expect(resealed.open(f.suite, v2).raw['future_field'], {
      'x': [1, 2, 3],
    });
    // Shadowing author_seq / object through the extras is refused.
    expect(
      () => EnvelopeBuilder.seal(
        f.suite,
        tenantId: tenantA,
        bookId: bookA,
        objectId: objectX,
        objectType: 'entry',
        envelopeId: envId,
        hlc: 1,
        authorSeq: 1,
        object: const {},
        extraPayloadFields: const {'author_seq': 99},
        bookKey: f.key,
        author: f.author,
      ),
      throwsArgumentError,
    );
  });

  test('B-04-31 re-seal preserves envelope_id, object_id, hlc, header and the padded plaintext byte-for-byte; only key_version, nonce, ciphertext and author_sig change', () async {
    // 05 §3 "Re-seal before push": "Preserve envelope_id, object_id, hlc
    // and payload byte-for-byte — only key_version, nonce, ciphertext and
    // author_sig change." ADR 2026-09-05b §3: "Re-seal preserves the
    // payload byte-for-byte, so author_seq survives rotation."
    final f = await fx(authorSeq: 42, extra: {'keep_me': true});
    final s = f.suite;
    final v3 = BookKey.generate(s, bookId: bookA, keyVersion: 3);
    addTearDown(v3.dispose);
    final r = EnvelopeBuilder.reseal(
      s,
      f.envelope,
      oldKey: f.key,
      newKey: v3,
      author: f.author,
    );
    final e = f.envelope;
    // Preserved.
    expect(r.envelopeId, e.envelopeId);
    expect(r.objectId, e.objectId);
    expect(r.hlc, e.hlc);
    expect(r.tenantId, e.tenantId);
    expect(r.bookId, e.bookId);
    expect(r.objectType, e.objectType);
    expect(r.payloadSchema, e.payloadSchema);
    expect(r.authorDeviceId, e.authorDeviceId);
    expect(r.suiteVersion, e.suiteVersion);
    // Padded plaintext identical (no unpad/re-pad in between).
    final before = e.decryptPadded(s, f.key);
    final after = r.decryptPadded(s, v3);
    expect(after, before);
    expect(after.length % 1024, 0);
    // Changed.
    expect(r.keyVersion, 3);
    expect(r.nonce, isNot(e.nonce));
    expect(r.ciphertext, isNot(e.ciphertext));
    expect(r.ciphertext.length, e.ciphertext.length);
    expect(r.authorSig, isNot(e.authorSig));
    expect(r.verifyAuthorSig(s, f.author.public), isTrue);
    // author_seq and unknown fields survive.
    final opened = r.open(s, v3);
    expect(opened.authorSeq, 42);
    expect(opened.raw['keep_me'], isTrue);
    expect(opened.object, sampleObject);
    // The old copy no longer opens under the new key, and vice versa.
    expect(() => e.open(s, v3), openFails(EnvelopeOpenReason.keyMismatch));
  });

  test('B-04-32 re-seal refuses a non-increasing key_version, another book\'s key, the wrong old version, or another author', () async {
    // 04 §3.2 "new entries always use the highest version"; 05 §3 re-seal
    // is "under the highest BK"; re-sealing is a re-wrapping by the author.
    final f = await fx(keyVersion: 2);
    final s = f.suite;
    final v2 = BookKey.generate(s, bookId: bookA, keyVersion: 2);
    final v1 = BookKey.generate(s, bookId: bookA, keyVersion: 1);
    final v3b = BookKey.generate(s, bookId: bookB, keyVersion: 3);
    final v3 = BookKey.generate(s, bookId: bookA, keyVersion: 3);
    final other = DeviceKeyPair.generate(s, deviceId: deviceB);
    for (final k in [v2, v1, v3b, v3]) {
      addTearDown(k.dispose);
    }
    addTearDown(other.dispose);
    Envelope go({BookKey? oldKey, BookKey? newKey, DeviceKeyPair? author}) =>
        EnvelopeBuilder.reseal(
          s,
          f.envelope,
          oldKey: oldKey ?? f.key,
          newKey: newKey ?? v3,
          author: author ?? f.author,
        );
    expect(() => go(newKey: v2), throwsArgumentError); // equal version
    expect(() => go(newKey: v1), throwsArgumentError); // lower version
    expect(() => go(newKey: v3b), throwsArgumentError); // other book
    expect(() => go(oldKey: v1), throwsArgumentError); // not the sealed v
    expect(() => go(author: other), throwsArgumentError); // not the author
    expect(go().keyVersion, 3);
  });

  test('B-04-33 open reports a malformed payload as a typed failure', () async {
    // ADR 2026-09-05b §3 — the payload shape is `{author_seq, object}`;
    // 04 §8.3 — failures are typed, never partially trusted content.
    final f = await fx();
    final s = f.suite;
    Envelope sealRaw(Uint8List plain) {
      final padded = padPlaintext(s, plain);
      final aead = s.sodium.crypto.aeadXChaCha20Poly1305IETF;
      final nonce = s.randomBytes(24);
      final ct = aead.encrypt(
        message: padded,
        nonce: nonce,
        key: f.key.key,
        additionalData: f.envelope.aad,
      );
      return withHeader(
        f.envelope,
        blob: Bytes.concat([nonce, f.envelope.authorSig, ct]),
      );
    }

    expect(
      () => sealRaw(Uint8List.fromList(utf8.encode('[1,2]'))).open(s, f.key),
      openFails(EnvelopeOpenReason.payloadMalformed),
    );
    expect(
      () =>
          sealRaw(Uint8List.fromList(utf8.encode('{"object":{}}')))
              .open(s, f.key),
      openFails(EnvelopeOpenReason.payloadMalformed),
    );
    expect(
      () => sealRaw(
        Uint8List.fromList(utf8.encode('{"author_seq":0,"object":{}}')),
      ).open(s, f.key),
      openFails(EnvelopeOpenReason.payloadMalformed),
    );
    expect(
      () => sealRaw(
        Uint8List.fromList(utf8.encode('{"author_seq":1,"object":[]}')),
      ).open(s, f.key),
      openFails(EnvelopeOpenReason.payloadMalformed),
    );
    expect(
      () => sealRaw(Uint8List.fromList([0xff, 0xfe])).open(s, f.key),
      openFails(EnvelopeOpenReason.payloadMalformed),
    );
    // Valid minimal payload still opens.
    expect(
      sealRaw(Uint8List.fromList(utf8.encode('{"author_seq":1,"object":{}}')))
          .open(s, f.key)
          .authorSeq,
      1,
    );
    // The SodiumException from a bad AEAD never leaks past the typed error.
    expect(
      () => withHeader(f.envelope, objectId: objectY).open(s, f.key),
      isNot(throwsA(isA<SodiumException>())),
    );
  });
}
