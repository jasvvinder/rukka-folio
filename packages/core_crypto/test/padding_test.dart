@Tags(['B'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _objectId = '55555555-5555-4555-8555-555555555551';
const String _envId1 = '66666666-6666-4666-8666-666666666661';
const String _envId2 = '66666666-6666-4666-8666-666666666662';

void main() {
  test('B-05b-8 plaintext padding: 3-char and 900-char notes → identical ciphertext length; 1,025 bytes → next bucket', () async {
    // ADR 2026-09-05b §8: "Plaintext is padded (libsodium sodium_pad) to
    // 1 KiB buckets up to 16 KiB, then 4 KiB steps, before encryption;
    // sizes stop leaking note length or attachment presence."
    final suite = await testSuite(seed: 11);
    final key = BookKey.generate(suite, bookId: bookA, keyVersion: 1);
    final author = DeviceKeyPair.generate(suite, deviceId: deviceA);
    addTearDown(key.dispose);
    addTearDown(author.dispose);

    Envelope sealNote(String envId, String note) => EnvelopeBuilder.seal(
      suite,
      tenantId: tenantA,
      bookId: bookA,
      objectId: _objectId,
      objectType: 'entry',
      envelopeId: envId,
      hlc: 1,
      authorSeq: 1,
      object: {'amount_paise': 12500, 'note': note},
      bookKey: key,
      author: author,
    );
    final short = sealNote(_envId1, 'tea');
    final long = sealNote(_envId2, 'x' * 900);
    expect(short.ciphertext.length, long.ciphertext.length);
    expect(short.size, long.size);
    // 1 KiB buckets: 1,000 and 1,023 bytes → 1,024; 1,025 → 2,048.
    expect(padPlaintext(suite, Uint8List(1000)).length, 1024);
    expect(padPlaintext(suite, Uint8List(1023)).length, 1024);
    expect(padPlaintext(suite, Uint8List(1025)).length, 2048);
    // sodium_pad always adds ≥ 1 byte, so a full bucket moves up one.
    expect(padPlaintext(suite, Uint8List(1024)).length, 2048);
    // Boundary: 16,383 stays in the small regime; 16,384 unpadded switches
    // to 4 KiB steps → 20,480 (⚠️ SPEC interpretation in padding.dart).
    expect(padPlaintext(suite, Uint8List(16383)).length, 16384);
    expect(padPlaintext(suite, Uint8List(16384)).length, 20480);
    expect(padPlaintext(suite, Uint8List(40000)).length, 40960);
  });

  test('B-04-20 unpad restores the exact bytes for lengths 0, 1, 1023, 1024, 16383, 16384, 40000', () async {
    // ADR 2026-09-05b §8 (padding is reversible — the payload must reach
    // the reader byte-for-byte) and padding.dart's unambiguity argument:
    // ≤ 16,384 padded → 1,024 block, else 4,096.
    final suite = await testSuite(seed: 12);
    for (final n in [0, 1, 1023, 1024, 16383, 16384, 40000]) {
      final plain = Uint8List.fromList(
        List<int>.generate(n, (i) => (i * 31 + 7) & 0xff),
      );
      final padded = padPlaintext(suite, plain);
      expect(padded.length % paddingBlockFor(n), 0, reason: 'n=$n');
      expect(padded.length, greaterThan(n), reason: 'n=$n');
      final back = unpadPlaintext(suite, padded);
      expect(back, plain, reason: 'n=$n');
    }
    // Real JSON as the envelope carries it.
    final json = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'author_seq': 1,
          'object': {'a': 1},
        }),
      ),
    );
    expect(unpadPlaintext(suite, padPlaintext(suite, json)), json);
  });

  test(
    'B-04-21 unpad refuses a buffer that is not whole blocks or has no marker',
    () async {
      // A malformed padded buffer is a typed failure, never silently
      // truncated content (04 §8.3 — never display unverified content).
      final suite = await testSuite(seed: 13);
      expect(
        () => unpadPlaintext(suite, Uint8List(1000)),
        throwsA(isA<PaddingException>()),
      );
      expect(
        () => unpadPlaintext(suite, Uint8List(0)),
        throwsA(isA<PaddingException>()),
      );
      // All-zero block: no 0x80 marker anywhere → sodium_unpad fails.
      expect(
        () => unpadPlaintext(suite, Uint8List(1024)),
        throwsA(isA<PaddingException>()),
      );
      // 20,480 is a valid 4 KiB length but 17,408 (17 × 1,024) is neither a
      // 1 KiB result (> 16,384) nor a 4 KiB multiple.
      expect(
        () => unpadPlaintext(suite, Uint8List(17408)),
        throwsA(isA<PaddingException>()),
      );
    },
  );
}
