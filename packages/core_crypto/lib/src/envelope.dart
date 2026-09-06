import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium.dart';

import 'bytes.dart';
import 'keys.dart';
import 'padding.dart';
import 'suite.dart';

// The class field `suiteVersion` shadows the library constant inside class
// bodies; this alias resolves at file scope.
const int _currentSuite = suiteVersion;

/// The encryption envelope (04 §4 🔒) — how every synced object travels and
/// rests: plaintext routing header, XChaCha20-Poly1305 ciphertext bound to
/// that header through the AAD, and the author device's Ed25519 signature.
///
/// Inside the ciphertext (ADR 2026-09-05b §3) sits the UTF-8 JSON object
/// `{"author_seq": <int ≥ 1>, "object": {...}}`, padded per ADR 05b §8 before
/// encryption. Unknown top-level payload fields round-trip (CLAUDE.md rule 6);
/// `object` is opaque to this package.

/// Current `payload_schema` (03 §2.3 column; plaintext).
///
/// ⚠️ SPEC: 04 §4 does not list `payload_schema` in the AAD, so it is *not*
/// authenticated by the AEAD — the server checks it against its registry
/// (`rejected:version`, 05 §3) and readers treat it as routing metadata.
const int payloadSchemaCurrent = 1;

/// XChaCha20-Poly1305 nonce length (04 §2 — 24 random bytes).
const int envelopeNonceBytes = 24;

/// Ed25519 detached signature length.
const int envelopeSigBytes = 64;

/// Poly1305 tag length — the shortest possible ciphertext.
const int envelopeTagBytes = 16;

/// Builds the AAD of 04 §4 in its 🔒 order:
/// `uuid16(tenant) ‖ uuid16(book) ‖ uuid16(object) ‖ lenPrefixedUtf8(type)
/// ‖ u32be(key_version) ‖ u8(suite_version)`.
///
/// `object_type` is a registry string (03 §2.3) that this package treats as
/// opaque; it is length-prefixed so it cannot slide into `key_version`.
Uint8List envelopeAad({
  required String tenantId,
  required String bookId,
  required String objectId,
  required String objectType,
  required int keyVersion,
  required int suiteVersion,
}) => Bytes.concat([
  Uuid16.toBytes(tenantId),
  Uuid16.toBytes(bookId),
  Uuid16.toBytes(objectId),
  Bytes.lengthPrefixedUtf8(objectType),
  Bytes.u32be(keyVersion),
  Bytes.u8(suiteVersion),
]);

/// Why [Envelope.open] refused.
enum EnvelopeOpenReason {
  /// The supplied [BookKey] is for another book or another `key_version`.
  keyMismatch,

  /// Poly1305 failed: wrong key, altered ciphertext, or a header that no
  /// longer matches the AAD the author sealed under (04 §10 — moved between
  /// books/objects).
  aeadFailed,

  /// Decryption succeeded but the padding marker is malformed.
  paddingInvalid,

  /// Decryption succeeded but the payload is not
  /// `{"author_seq": int ≥ 1, "object": {...}}`.
  payloadMalformed,
}

/// Typed failure of [Envelope.open]. Carries no payload bytes (rule 4).
final class EnvelopeOpenFailed implements Exception {
  /// Creates the failure.
  const EnvelopeOpenFailed(this.reason, [this.detail]);

  /// What failed.
  final EnvelopeOpenReason reason;

  /// Optional human detail (never plaintext content).
  final String? detail;

  @override
  String toString() =>
      'EnvelopeOpenFailed(${reason.name}${detail == null ? '' : ': $detail'})';
}

/// The decrypted payload of an envelope.
@immutable
final class OpenedPayload {
  /// Creates the view.
  const OpenedPayload({
    required this.authorSeq,
    required this.object,
    required this.raw,
  });

  /// Per-author monotone sequence, from 1 (ADR 2026-09-05b §3).
  final int authorSeq;

  /// The domain object (opaque here; `core_ledger` interprets it).
  final Map<String, Object?> object;

  /// The whole top-level payload map, unknown fields included (rule 6).
  final Map<String, Object?> raw;
}

/// One synced object as stored (04 §4; columns per 03 §2.3 / §3.1).
///
/// The wire/storage form is the header columns plus one [blob]:
/// `nonce(24) ‖ author_sig(64) ‖ ciphertext`.
///
/// ⚠️ SPEC: 03 §2.3 has no `nonce` or `author_sig` column, so both ride
/// inside `blob` in that fixed order; `blob_hash`/`size` therefore cover them
/// (ADR 2026-09-05c §2).
///
/// ⚠️ SPEC: per 04 §4 `author_sig` covers `BLAKE2b(ciphertext ‖ aad)` only.
/// `hlc`, `envelope_id` and `payload_schema` are plaintext columns outside
/// both the AAD and the signature — the server can alter them without any
/// reader noticing cryptographically. Implemented as written; flagged for the
/// owner.
@immutable
final class Envelope {
  /// Assembles an envelope from its parts (validates shapes, not the crypto).
  Envelope({
    required this.suiteVersion,
    required this.tenantId,
    required this.bookId,
    required this.objectId,
    required this.objectType,
    required this.keyVersion,
    required this.payloadSchema,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required this.authorDeviceId,
    required Uint8List authorSig,
    required this.hlc,
    required this.envelopeId,
  }) : nonce = Uint8List.fromList(nonce),
       ciphertext = Uint8List.fromList(ciphertext),
       authorSig = Uint8List.fromList(authorSig) {
    for (final id in [tenantId, bookId, objectId, authorDeviceId, envelopeId]) {
      if (!Uuid16.isCanonical(id)) {
        throw FormatException('envelope ids must be canonical uuids', id);
      }
    }
    if (nonce.length != envelopeNonceBytes) {
      throw ArgumentError.value(nonce.length, 'nonce', 'must be 24 bytes');
    }
    if (authorSig.length != envelopeSigBytes) {
      throw ArgumentError.value(authorSig.length, 'authorSig', '64 bytes');
    }
    if (ciphertext.length < envelopeTagBytes) {
      throw ArgumentError.value(
        ciphertext.length,
        'ciphertext',
        'shorter than the Poly1305 tag',
      );
    }
    if (keyVersion < 1) {
      throw ArgumentError.value(keyVersion, 'keyVersion', 'starts at 1');
    }
    if (objectType.isEmpty) {
      throw ArgumentError.value(objectType, 'objectType', 'empty');
    }
  }

  /// Splits a stored `blob` (`nonce ‖ author_sig ‖ ciphertext`) back into an
  /// envelope. Refuses blobs shorter than `24 + 64 + 16` bytes.
  factory Envelope.fromParts({
    required int suiteVersion,
    required String tenantId,
    required String bookId,
    required String objectId,
    required String objectType,
    required int keyVersion,
    required int payloadSchema,
    required String authorDeviceId,
    required int hlc,
    required String envelopeId,
    required Uint8List blob,
  }) {
    const minLen = envelopeNonceBytes + envelopeSigBytes + envelopeTagBytes;
    if (blob.length < minLen) {
      throw FormatException(
        'envelope blob is ${blob.length} bytes; minimum is $minLen',
      );
    }
    const sigEnd = envelopeNonceBytes + envelopeSigBytes;
    return Envelope(
      suiteVersion: suiteVersion,
      tenantId: tenantId,
      bookId: bookId,
      objectId: objectId,
      objectType: objectType,
      keyVersion: keyVersion,
      payloadSchema: payloadSchema,
      nonce: Uint8List.sublistView(blob, 0, envelopeNonceBytes),
      authorSig: Uint8List.sublistView(blob, envelopeNonceBytes, sigEnd),
      ciphertext: Uint8List.sublistView(blob, sigEnd),
      authorDeviceId: authorDeviceId,
      hlc: hlc,
      envelopeId: envelopeId,
    );
  }

  /// `suite_version` (04 §2).
  final int suiteVersion;

  /// Tenant (plaintext — routing & RLS).
  final String tenantId;

  /// Book (plaintext — routing & RLS).
  final String bookId;

  /// Object identity (plaintext — sync identity).
  final String objectId;

  /// Registry string, e.g. `entry` (03 §2.3).
  final String objectType;

  /// The book-key version the ciphertext is sealed under (04 §3.2).
  final int keyVersion;

  /// Plaintext payload schema (03 §2.3).
  final int payloadSchema;

  /// 24-byte nonce.
  final Uint8List nonce;

  /// XChaCha20-Poly1305 combined-mode ciphertext (tag included).
  final Uint8List ciphertext;

  /// Authoring device (plaintext).
  final String authorDeviceId;

  /// `Ed25519(BLAKE2b-256(ciphertext ‖ aad))` under the author device key.
  final Uint8List authorSig;

  /// Hybrid logical clock (05 §2; `bigint` in 03).
  final int hlc;

  /// Client-minted idempotency key (03 §2.3).
  final String envelopeId;

  /// The AAD rebuilt from this header (04 §4).
  Uint8List get aad => envelopeAad(
    tenantId: tenantId,
    bookId: bookId,
    objectId: objectId,
    objectType: objectType,
    keyVersion: keyVersion,
    suiteVersion: suiteVersion,
  );

  /// `nonce ‖ author_sig ‖ ciphertext` — the stored `blob`.
  Uint8List get blob => Bytes.concat([nonce, authorSig, ciphertext]);

  /// `size` column: length of [blob].
  int get size => envelopeNonceBytes + envelopeSigBytes + ciphertext.length;

  /// `blob_hash = BLAKE2b-256(blob)` (ADR 2026-09-05c §2).
  Uint8List blobHash(CryptoSuite suite) => suite.blake2b256(blob);

  /// The bytes the author signed: `BLAKE2b-256(ciphertext ‖ aad)` (04 §4).
  Uint8List signedDigest(CryptoSuite suite) =>
      suite.blake2b256(Bytes.concat([ciphertext, aad]));

  /// Checks [authorSig] under [author]'s Ed25519 key. Does **not** walk the
  /// certificate chain — use `ChainVerifier` for that (04 §3.4).
  bool verifyAuthorSig(CryptoSuite suite, DevicePublic author) {
    if (author.deviceId != authorDeviceId) return false;
    return suite.sodium.crypto.sign.verifyDetached(
      message: signedDigest(suite),
      signature: authorSig,
      publicKey: author.ed25519,
    );
  }

  /// Decrypts and returns the **padded** plaintext bytes — what re-seal
  /// (05 §3) re-encrypts unchanged. The caller owns and zeroises the buffer.
  ///
  /// Throws [EnvelopeOpenFailed] with [EnvelopeOpenReason.keyMismatch] when
  /// [key] is not `(book_id, key_version)` of this envelope, or
  /// [EnvelopeOpenReason.aeadFailed] when Poly1305 rejects — a wrong key
  /// (removed member, 04 §10), a flipped ciphertext bit, or a header that was
  /// changed after sealing (re-upload under another `book_id`, 04 §10).
  Uint8List decryptPadded(CryptoSuite suite, BookKey key) {
    if (key.ref.bookId != bookId || key.ref.keyVersion != keyVersion) {
      throw EnvelopeOpenFailed(
        EnvelopeOpenReason.keyMismatch,
        'envelope is under $bookId v$keyVersion, key is ${key.ref}',
      );
    }
    try {
      return suite.sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: ciphertext,
        nonce: nonce,
        key: key.key,
        additionalData: aad,
      );
    } on SodiumException {
      throw const EnvelopeOpenFailed(EnvelopeOpenReason.aeadFailed);
    }
  }

  /// Decrypts, unpads and parses the payload.
  ///
  /// Opening checks the AEAD only. It does **not** verify [authorSig] or the
  /// certificate chain: callers must run `ChainVerifier.verifyEnvelope` first
  /// and never show unverified content as trusted (04 §8.3).
  OpenedPayload open(CryptoSuite suite, BookKey key) {
    final padded = decryptPadded(suite, key);
    Uint8List? plain;
    try {
      try {
        plain = unpadPlaintext(suite, padded);
      } on PaddingException catch (e) {
        throw EnvelopeOpenFailed(EnvelopeOpenReason.paddingInvalid, e.message);
      }
      return _parsePayload(plain);
    } finally {
      suite.zeroize(padded);
      if (plain != null) suite.zeroize(plain);
    }
  }

  static OpenedPayload _parsePayload(Uint8List plain) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plain));
    } on FormatException {
      throw const EnvelopeOpenFailed(
        EnvelopeOpenReason.payloadMalformed,
        'not UTF-8 JSON',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const EnvelopeOpenFailed(
        EnvelopeOpenReason.payloadMalformed,
        'payload is not a JSON object',
      );
    }
    final raw = Map<String, Object?>.from(decoded);
    final seq = raw[EnvelopeBuilder.authorSeqField];
    if (seq is! int || seq < 1) {
      throw const EnvelopeOpenFailed(
        EnvelopeOpenReason.payloadMalformed,
        'author_seq missing or not an int ≥ 1',
      );
    }
    final object = raw[EnvelopeBuilder.objectField];
    if (object is! Map<String, Object?>) {
      throw const EnvelopeOpenFailed(
        EnvelopeOpenReason.payloadMalformed,
        'object missing or not a JSON object',
      );
    }
    return OpenedPayload(
      authorSeq: seq,
      object: Map<String, Object?>.from(object),
      raw: raw,
    );
  }
}

/// Seals plaintext objects into [Envelope]s (04 §4) and re-seals queued ones
/// across a key rotation (05 §3).
final class EnvelopeBuilder {
  EnvelopeBuilder._();

  /// Payload key carrying the per-author sequence (ADR 2026-09-05b §3).
  static const String authorSeqField = 'author_seq';

  /// Payload key carrying the domain object (ADR 2026-09-05b §3).
  static const String objectField = 'object';

  /// Encodes, pads, encrypts and signs [object] as a new envelope.
  ///
  /// [envelopeId] is the client-minted idempotency uuid; [hlc] the caller's
  /// hybrid logical clock (never read here — rule 3); [authorSeq] the
  /// device's monotone per-book sequence (≥ 1). [extraPayloadFields] are
  /// carried at the top level of the payload beside `author_seq`/`object`
  /// (they may not shadow either) — the hook for forward-compatible fields.
  static Envelope seal(
    CryptoSuite suite, {
    required String tenantId,
    required String bookId,
    required String objectId,
    required String objectType,
    required String envelopeId,
    required int hlc,
    required int authorSeq,
    required Map<String, Object?> object,
    required BookKey bookKey,
    required DeviceKeyPair author,
    Map<String, Object?>? extraPayloadFields,
    int payloadSchema = payloadSchemaCurrent,
  }) {
    if (authorSeq < 1) {
      throw ArgumentError.value(authorSeq, 'authorSeq', 'starts at 1');
    }
    if (bookKey.ref.bookId != bookId) {
      throw ArgumentError.value(
        bookKey.ref,
        'bookKey',
        'is not a key of book $bookId',
      );
    }
    if (extraPayloadFields != null &&
        (extraPayloadFields.containsKey(authorSeqField) ||
            extraPayloadFields.containsKey(objectField))) {
      throw ArgumentError.value(
        extraPayloadFields.keys,
        'extraPayloadFields',
        'may not shadow $authorSeqField or $objectField',
      );
    }
    final payload = <String, Object?>{
      authorSeqField: authorSeq,
      objectField: object,
      ...?extraPayloadFields,
    };
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    Uint8List? padded;
    try {
      padded = padPlaintext(suite, plain);
      return _encryptAndSign(
        suite,
        padded: padded,
        tenantId: tenantId,
        bookId: bookId,
        objectId: objectId,
        objectType: objectType,
        envelopeId: envelopeId,
        hlc: hlc,
        payloadSchema: payloadSchema,
        bookKey: bookKey,
        author: author,
      );
    } finally {
      suite.zeroize(plain);
      if (padded != null) suite.zeroize(padded);
    }
  }

  /// Re-seals [envelope] under [newKey] (05 §3 "Re-seal before push"):
  /// decrypts with [oldKey], re-encrypts the **identical padded plaintext**
  /// (no unpad/re-pad, so `author_seq` and every byte survive — ADR
  /// 2026-09-05b §3), recomputes the AAD under the new `key_version` and
  /// re-signs. `envelope_id`, `object_id`, `hlc`, `tenant_id`, `book_id`,
  /// `object_type`, `payload_schema` and `author_device_id` are preserved;
  /// only `key_version`, `nonce`, `ciphertext` and `author_sig` change.
  ///
  /// Refuses when the keys are for another book, [oldKey] is not the version
  /// the envelope is sealed under, `newKey.version ≤ oldKey.version`, or
  /// [author] is not the envelope's author device (re-sealing is a
  /// re-wrapping, not a re-authoring — the outbox is the author's own).
  static Envelope reseal(
    CryptoSuite suite,
    Envelope envelope, {
    required BookKey oldKey,
    required BookKey newKey,
    required DeviceKeyPair author,
  }) {
    if (oldKey.ref.bookId != envelope.bookId ||
        newKey.ref.bookId != envelope.bookId) {
      throw ArgumentError('re-seal keys must belong to ${envelope.bookId}');
    }
    if (oldKey.ref.keyVersion != envelope.keyVersion) {
      throw ArgumentError.value(
        oldKey.ref,
        'oldKey',
        'envelope is sealed under v${envelope.keyVersion}',
      );
    }
    if (newKey.ref.keyVersion <= oldKey.ref.keyVersion) {
      throw ArgumentError.value(
        newKey.ref,
        'newKey',
        'must be a higher version than ${oldKey.ref}',
      );
    }
    if (author.deviceId != envelope.authorDeviceId) {
      throw ArgumentError.value(
        author.deviceId,
        'author',
        'envelope was authored by ${envelope.authorDeviceId}',
      );
    }
    final padded = envelope.decryptPadded(suite, oldKey);
    try {
      return _encryptAndSign(
        suite,
        padded: padded,
        tenantId: envelope.tenantId,
        bookId: envelope.bookId,
        objectId: envelope.objectId,
        objectType: envelope.objectType,
        envelopeId: envelope.envelopeId,
        hlc: envelope.hlc,
        payloadSchema: envelope.payloadSchema,
        bookKey: newKey,
        author: author,
      );
    } finally {
      suite.zeroize(padded);
    }
  }

  static Envelope _encryptAndSign(
    CryptoSuite suite, {
    required Uint8List padded,
    required String tenantId,
    required String bookId,
    required String objectId,
    required String objectType,
    required String envelopeId,
    required int hlc,
    required int payloadSchema,
    required BookKey bookKey,
    required DeviceKeyPair author,
  }) {
    final aad = envelopeAad(
      tenantId: tenantId,
      bookId: bookId,
      objectId: objectId,
      objectType: objectType,
      keyVersion: bookKey.ref.keyVersion,
      suiteVersion: suiteVersion,
    );
    final aead = suite.sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = suite.randomBytes(aead.nonceBytes);
    final ciphertext = aead.encrypt(
      message: padded,
      nonce: nonce,
      key: bookKey.key,
      additionalData: aad,
    );
    final sig = suite.sodium.crypto.sign.detached(
      message: suite.blake2b256(Bytes.concat([ciphertext, aad])),
      secretKey: author.ed25519Secret,
    );
    return Envelope(
      suiteVersion: _currentSuite,
      tenantId: tenantId,
      bookId: bookId,
      objectId: objectId,
      objectType: objectType,
      keyVersion: bookKey.ref.keyVersion,
      payloadSchema: payloadSchema,
      nonce: nonce,
      ciphertext: ciphertext,
      authorDeviceId: author.deviceId,
      authorSig: sig,
      hlc: hlc,
      envelopeId: envelopeId,
    );
  }
}
