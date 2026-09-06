// The M3 boundary between the mirror and `core_crypto` (04 §4; ADR 05b §3;
// ADR 05c §2): BLAKE2b for `blob_hash`, and an opener that rebuilds the
// envelope from a mirror row, checks the AAD by decrypting, unpads and hands
// the object JSON to Recompute.
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

import 'payload_codec.dart';

/// `blob_hash = BLAKE2b-256(blob)` (ADR 2026-09-05c §2) — the hasher the
/// mirror verifies with on every read.
BlobHasher blake2bHasher(CryptoSuite suite) => suite.blake2b256;

/// Where unwrapped book keys and the book → tenant mapping come from
/// (`key_cache` and the meta channel, 03 §3.1, 05 §5). Keys are handed out as
/// [BookKey]s that stay owned by the source — the opener never disposes them.
abstract interface class KeySource {
  /// The unwrapped key for [ref], or `null` when it has not arrived
  /// (05 §4 `key_wait`).
  BookKey? bookKey(BookKeyRef ref);

  /// The tenant a book belongs to (part of the AAD, 04 §4), or `null` if unknown.
  String? tenantIdOf(String bookId);
}

/// A [KeySource] over maps — tests, the harness and bootstrapping.
final class InMemoryKeySource implements KeySource {
  /// Creates the source.
  InMemoryKeySource({
    Map<BookKeyRef, BookKey>? keys,
    Map<String, String>? tenants,
  }) : keys = keys ?? {},
       tenants = tenants ?? {};

  /// Keys by `(book, version)`.
  final Map<BookKeyRef, BookKey> keys;

  /// Book → tenant.
  final Map<String, String> tenants;

  @override
  BookKey? bookKey(BookKeyRef ref) => keys[ref];

  @override
  String? tenantIdOf(String bookId) => tenants[bookId];
}

/// The key (or tenant mapping) an envelope needs is not available yet. This is
/// `key_wait` (05 §4), not a quarantine: Recompute must only see rows whose
/// keys are present, which the sync engine guarantees at M4 by marking a row
/// `verified` only after it decrypted once. ⚠️ SPEC: until then a caller that
/// feeds Recompute an un-keyed row will see it quarantined `payload: …`.
final class KeyUnavailable implements Exception {
  /// Creates the failure.
  const KeyUnavailable(this.message);

  /// What is missing.
  final String message;

  @override
  String toString() => 'KeyUnavailable: $message';
}

/// Opens mirror blobs with `core_crypto` (04 §4).
///
/// The mirror stores `nonce ‖ author_sig ‖ ciphertext` as the blob and the
/// routing fields as columns; the opener rebuilds the [Envelope], so a column
/// changed after the fact (another `book_id`, `object_id`, `object_type` or
/// `key_version`) fails the AEAD and the row is quarantined by Recompute.
///
/// ⚠️ SPEC: `envelopes_local` (03 §3.1) carries neither `suite_version` nor
/// `payload_schema`, which the server row has (03 §2.3). Until 03 gains the
/// columns the opener assumes the current suite and [payloadSchema]; an
/// envelope from a future suite would fail to open rather than be misread.
final class CryptoPayloadOpener implements PayloadOpener {
  /// Creates the opener over [suite] and [keys].
  const CryptoPayloadOpener(this.suite, this.keys, {this.payloadSchema = 1});

  /// Crypto suite.
  final CryptoSuite suite;

  /// Keys and tenant mapping.
  final KeySource keys;

  /// `payload_schema` assumed for every local row (see the class note).
  final int payloadSchema;

  @override
  Map<String, Object?> open(Uint8List blob, BlobHeader header) {
    final tenantId = keys.tenantIdOf(header.bookId);
    if (tenantId == null) {
      throw KeyUnavailable('tenant of book ${header.bookId} unknown');
    }
    final ref = BookKeyRef(
      bookId: header.bookId,
      keyVersion: header.keyVersion,
    );
    final key = keys.bookKey(ref);
    if (key == null) throw KeyUnavailable('no book key for $ref');
    final envelope = Envelope.fromParts(
      suiteVersion: suiteVersion,
      tenantId: tenantId,
      bookId: header.bookId,
      objectId: header.objectId,
      objectType: header.objectType,
      keyVersion: header.keyVersion,
      payloadSchema: payloadSchema,
      authorDeviceId: header.authorDevice,
      hlc: header.hlc,
      envelopeId: header.envelopeId,
      blob: blob,
    );
    final opened = envelope.open(suite, key);
    // The wrapper's `author_seq` (ADR 05b §3) is what the mirror row must
    // agree with; it is surfaced at the top level of the object so Recompute
    // checks every object type the same way. ⚠️ SPEC: an `author_seq` field
    // inside the object itself (02 §1.3 gives Entry one) is overridden by the
    // wrapper's — the wrapper is the one the ADR defines.
    return {...opened.object, EnvelopeBuilder.authorSeqField: opened.authorSeq};
  }
}
