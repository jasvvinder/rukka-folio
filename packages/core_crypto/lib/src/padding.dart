import 'dart:typed_data';

import 'suite.dart';

/// Plaintext padding before encryption (ADR 2026-09-05b §8): libsodium
/// `sodium_pad` to 1 KiB buckets up to 16 KiB, then 4 KiB steps, so a
/// ciphertext's length stops leaking note length or attachment presence.
///
/// `sodium_pad` (ISO/IEC 7816-4) always appends at least one byte, so a
/// plaintext that already fills a bucket moves up one: 1,024 bytes pad to
/// 2,048 and 16,384 bytes pad to 20,480.

/// Bucket size for small plaintexts (bytes).
const int paddingSmallBlock = 1024;

/// Step size for large plaintexts (bytes).
const int paddingLargeBlock = 4096;

/// Largest padded length still produced with [paddingSmallBlock].
///
/// ⚠️ SPEC: ADR 05b §8 says "1 KiB buckets up to 16 KiB, then 4 KiB steps"
/// without fixing the boundary. Interpretation: while the *padded* result
/// would be ≤ 16,384 bytes — i.e. the unpadded length is < 16,384 — the block
/// is 1,024; from 16,384 unpadded bytes upward the block is 4,096.
const int paddingSmallLimit = 16384;

/// Chooses the block size for an unpadded plaintext of [unpaddedLength].
int paddingBlockFor(int unpaddedLength) =>
    unpaddedLength < paddingSmallLimit ? paddingSmallBlock : paddingLargeBlock;

/// Pads [plaintext] per ADR 2026-09-05b §8. Returns a new buffer; the caller
/// still owns (and zeroises) [plaintext].
Uint8List padPlaintext(CryptoSuite suite, Uint8List plaintext) =>
    suite.sodium.pad(plaintext, paddingBlockFor(plaintext.length));

/// Removes the padding [padPlaintext] added. Returns a new buffer.
///
/// The block size is derived from the padded length alone, which is
/// unambiguous: a 1,024-block result is always ≤ 16,384 bytes (the largest
/// input using that block is 16,383 → 16,384), and a 4,096-block result is
/// always ≥ 20,480 (the smallest input using that block is 16,384, which
/// gains ≥ 1 byte and rounds up to 20,480). No padded length lies in both
/// ranges, so "≤ 16,384 → 1,024, else 4,096" inverts [paddingBlockFor].
///
/// Throws [PaddingException] when [padded] is not a whole number of blocks
/// or its final block carries no valid `sodium_pad` marker.
Uint8List unpadPlaintext(CryptoSuite suite, Uint8List padded) {
  final block = padded.length <= paddingSmallLimit
      ? paddingSmallBlock
      : paddingLargeBlock;
  if (padded.isEmpty || padded.length % block != 0) {
    throw PaddingException(
      'padded length ${padded.length} is not a multiple of $block',
    );
  }
  try {
    return suite.sodium.unpad(padded, block);
  } on Exception catch (e) {
    throw PaddingException('invalid padding marker: $e');
  }
}

/// A padded buffer whose length or trailing marker is malformed.
final class PaddingException implements Exception {
  /// Creates the exception.
  const PaddingException(this.message);

  /// Why unpadding failed (never carries payload bytes).
  final String message;

  @override
  String toString() => 'PaddingException: $message';
}
