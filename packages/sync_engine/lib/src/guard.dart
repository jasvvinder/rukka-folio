// The engine's verification seam (04 §8.3; ADR 2026-09-05b §1, §2; 05 §3
// re-seal; 05 §4 key_wait). Everything the server says is a claim until the
// guard says otherwise: an envelope is `verified` only when the chain passes
// AND the blob decrypts once (M3 changelog Open); a record is applied only when
// its chain passes. [CryptoGuard] is the real one over `core_crypto`;
// `testing.dart`'s `PlainGuard` serves the two-client harness, whose devices
// author plaintext JSON blobs.
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:meta/meta.dart';

import 'key_store.dart';
import 'trust.dart';
import 'wire.dart';

/// What the guard decided about a pulled envelope.
@immutable
sealed class EnvelopeVerdict {
  const EnvelopeVerdict();
}

/// Chain intact and the blob decrypted once — mark the row `verified`.
final class EnvelopeVerified extends EnvelopeVerdict {
  /// Creates the verdict.
  const EnvelopeVerified(this.authorSeq);

  /// The per-author sequence read from inside the ciphertext (ADR 05b §3) —
  /// what the mirror row's `author_seq` column is filled from.
  final int authorSeq;
}

/// `blob_hash` ≠ hash(blob): corruption, never tampering (ADR 05c §2) —
/// not stored, re-fetched; no security event.
final class EnvelopeCorrupt extends EnvelopeVerdict {
  /// Creates the verdict.
  const EnvelopeCorrupt();
}

/// The book key for this `key_version` has not arrived (05 §4 `key_wait`).
final class EnvelopeKeyWait extends EnvelopeVerdict {
  /// Creates the verdict.
  const EnvelopeKeyWait(this.keyVersion);

  /// The missing version.
  final int keyVersion;
}

/// Quarantine with the reason written to `quarantine_reason` (security event).
final class EnvelopeQuarantine extends EnvelopeVerdict {
  /// Creates the verdict.
  const EnvelopeQuarantine(this.reason);

  /// Reason, e.g. `revoked`, `sigInvalid`, `payload: aeadFailed`.
  final String reason;
}

/// What the guard decided about a signed record.
@immutable
sealed class RecordVerdict {
  const RecordVerdict();
}

/// Chain intact — apply the record (ADR 05b §1).
final class RecordVerified extends RecordVerdict {
  /// Creates the verdict.
  const RecordVerified();
}

/// Not applied; logged as `RecordIgnored`.
final class RecordRejected extends RecordVerdict {
  /// Creates the verdict.
  const RecordRejected(this.reason);

  /// Why.
  final String reason;
}

/// The at-rest form of a `wrapped_keys` row this device just accepted
/// (03 §3.1 `key_cache`): the sealed box **exactly as it came off the wire**,
/// already wrapped to this user's own UMK.
///
/// Two rules are carried by construction rather than by a check downstream:
/// the blob is never re-wrapped, so nothing here can address a key to an
/// unverified fingerprint (04 §8.2 🔒), and the unwrapped key is not in this
/// object at all, so what rests is wrapped (03 §3.1). [recipient] is this
/// install's own UMK fingerprint — the guard unsealed the blob with that UMK,
/// which is what proves it.
@immutable
final class AcceptedBookKey {
  /// Creates the material.
  const AcceptedBookKey({
    required this.ref,
    required this.suiteVersion,
    required this.recipient,
    required this.sealed,
  });

  /// `(book_id, key_version)`.
  final BookKeyRef ref;

  /// `suite_version` of the seal.
  final int suiteVersion;

  /// The fingerprint the blob is sealed to — this user's own.
  final Fingerprint recipient;

  /// The `crypto_box_seal` ciphertext, unchanged.
  final Uint8List sealed;
}

/// What [EnvelopeGuard.acceptWrappedKey] did with a `wrapped_keys` row.
@immutable
sealed class KeyAcceptance {
  const KeyAcceptance();
}

/// Unwrapped and stored for the first time: [key] must reach `key_cache`
/// (03 §3.1) or it is lost at the next launch, because the meta cursor has
/// already passed the row.
final class KeyAccepted extends KeyAcceptance {
  /// Creates the acceptance.
  const KeyAccepted(this.key);

  /// What to persist.
  final AcceptedBookKey key;

  /// The key's reference.
  BookKeyRef get ref => key.ref;
}

/// This `(book, version)` was already held — `key_wait` still drains, and
/// nothing is written: the copy at rest is the one that opened.
final class KeyAlreadyHeld extends KeyAcceptance {
  /// Creates the acceptance.
  const KeyAlreadyHeld(this.ref);

  /// The key's reference.
  final BookKeyRef ref;
}

/// Not this device's key, or not a key at all: nothing stored, nothing
/// persisted, nothing drained. [reason] is a constant, never wire content.
final class KeyNotAccepted extends KeyAcceptance {
  /// Creates the outcome.
  const KeyNotAccepted(this.reason);

  /// `not_for_us`, `unsealable`, `incomplete_row`, `no_umk` or `wrong_kind`.
  final String reason;
}

/// Where an accepted key is written so it survives the process (03 §3.1).
///
/// The engine holds this as a seam rather than writing `key_cache` itself:
/// the at-rest layout of the blob belongs to the app's ledger, which is what
/// reads it back at open — `sync_engine` learns no storage layout, and the
/// two halves cannot drift apart into a row the reader cannot decode.
abstract interface class AcceptedKeySink {
  /// Persists [key]. Called once per newly accepted `(book, version)`, before
  /// `key_wait` drains, so a crash mid-drain still leaves the key on disk.
  Future<void> keyAccepted(AcceptedBookKey key);
}

/// The cryptographic seam the engine speaks through. One instance per tenant.
abstract interface class EnvelopeGuard {
  /// `blob_hash` function (BLAKE2b-256 in production).
  Uint8List hash(Uint8List blob);

  /// `payload_schema` this device writes.
  int get payloadSchema;

  /// Verifies a pulled envelope: chain, then revocation `seq`, then one
  /// decryption. The caller has already checked `blob_hash`.
  EnvelopeVerdict checkEnvelope(WireEnvelope envelope);

  /// Verifies a signed record's chain (sig → cert → ceremony-verified UMK).
  RecordVerdict checkRecord(WireSignedRecord record);

  /// Highest book-key version held for [bookId], or null (no keys).
  int? highestKeyVersion(String bookId);

  /// Re-seals a queued envelope under [toVersion] (05 §3): identical
  /// plaintext, `envelope_id`/`object_id`/`hlc` preserved; only `key_version`,
  /// `nonce`, `ciphertext`, `author_sig` (and therefore `blob_hash`) change.
  /// Returns null when either key is unavailable.
  WireEnvelope? reseal(WireEnvelope envelope, {required int toVersion});

  /// Unwraps a `wrapped_keys` row addressed to this device's user and stores
  /// the key. The result says whether anything changed: only [KeyAccepted]
  /// carries material to persist, and it is returned exactly once per
  /// `(book, version)` — a row seen again is [KeyAlreadyHeld].
  KeyAcceptance acceptWrappedKey(WireWrappedKey key);

  /// Builds the certificate a `device_certs` row carries (with the public keys
  /// from its `devices` row), or null when the row cannot be parsed.
  DeviceCert? buildCert(WireDeviceCert cert, WireDevice device);

  /// Drops every book key (own verified revocation or removal, 05 §5).
  void dropAllKeys();
}

/// The production guard: `core_crypto` over a [BookKeyStore] and a
/// [RecordTrustStore].
final class CryptoGuard implements EnvelopeGuard {
  /// Creates the guard. [me] signs re-sealed envelopes (the outbox is the
  /// author's own); [umk] opens `wrapped_keys` rows — null on a device that
  /// holds no UMK yet (nothing unwraps).
  CryptoGuard({
    required this.suite,
    required this.keys,
    required this.trust,
    required this.me,
    this.umk,
    this.payloadSchema = payloadSchemaCurrent,
  }) : _verifier = ChainVerifier(suite, trust);

  /// Crypto suite (libsodium + injected RNG).
  final CryptoSuite suite;

  /// Unwrapped book keys, every version retained.
  final BookKeyStore keys;

  /// Trust state (certs, verified UMKs, revocation records).
  final RecordTrustStore trust;

  /// This device's key pair.
  final DeviceKeyPair me;

  /// This user's UMK, if held here.
  final UmkKeyPair? umk;

  @override
  final int payloadSchema;

  final ChainVerifier _verifier;

  @override
  Uint8List hash(Uint8List blob) => suite.blake2b256(blob);

  Envelope? _envelopeOf(WireEnvelope e) {
    try {
      return Envelope.fromParts(
        suiteVersion: e.suiteVersion,
        tenantId: e.tenantId,
        bookId: e.bookId,
        objectId: e.objectId,
        objectType: e.objectType,
        keyVersion: e.keyVersion,
        payloadSchema: e.payloadSchema,
        authorDeviceId: e.authorDevice,
        hlc: e.hlc,
        envelopeId: e.envelopeId,
        blob: e.blob,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  @override
  EnvelopeVerdict checkEnvelope(WireEnvelope envelope) {
    final env = _envelopeOf(envelope);
    if (env == null) return const EnvelopeQuarantine('malformed');
    switch (_verifier.verifyEnvelope(env, seq: envelope.seq)) {
      case ChainCorrupt():
        return const EnvelopeCorrupt();
      case ChainQuarantine(:final reason):
        return EnvelopeQuarantine(reason.name);
      case ChainVerified():
        break;
    }
    final key = keys.bookKey(
      BookKeyRef(bookId: envelope.bookId, keyVersion: envelope.keyVersion),
    );
    if (key == null) return EnvelopeKeyWait(envelope.keyVersion);
    try {
      return EnvelopeVerified(env.open(suite, key).authorSeq);
    } on EnvelopeOpenFailed catch (e) {
      return EnvelopeQuarantine('payload: ${e.reason.name}');
    }
  }

  @override
  RecordVerdict checkRecord(WireSignedRecord record) {
    final SignedRecord r;
    try {
      r = SignedRecord(
        suiteVersion: record.suiteVersion,
        tenantId: record.tenantId,
        kind: record.kind,
        payloadJson: record.payloadJson,
        authorDeviceId: record.authorDeviceId,
        authorSig: record.authorSig,
        hlc: record.hlc,
        seq: record.seq,
      );
    } on FormatException catch (e) {
      return RecordRejected('malformed: ${e.message}');
    } on ArgumentError catch (e) {
      return RecordRejected('malformed: ${e.message}');
    }
    return switch (_verifier.verifySignedRecord(r)) {
      ChainVerified() => const RecordVerified(),
      ChainCorrupt() => const RecordRejected('corrupt'),
      ChainQuarantine(:final reason) => RecordRejected(reason.name),
    };
  }

  @override
  int? highestKeyVersion(String bookId) => keys.highestVersion(bookId);

  @override
  WireEnvelope? reseal(WireEnvelope envelope, {required int toVersion}) {
    final oldKey = keys.bookKey(
      BookKeyRef(bookId: envelope.bookId, keyVersion: envelope.keyVersion),
    );
    final newKey = keys.bookKey(
      BookKeyRef(bookId: envelope.bookId, keyVersion: toVersion),
    );
    if (oldKey == null || newKey == null) return null;
    final env = _envelopeOf(envelope);
    if (env == null) return null;
    final Envelope out;
    try {
      out = EnvelopeBuilder.reseal(
        suite,
        env,
        oldKey: oldKey,
        newKey: newKey,
        author: me,
      );
    } on EnvelopeOpenFailed {
      return null;
    } on ArgumentError {
      return null;
    }
    final blob = out.blob;
    return WireEnvelope(
      envelopeId: envelope.envelopeId,
      tenantId: envelope.tenantId,
      bookId: envelope.bookId,
      objectId: envelope.objectId,
      objectType: envelope.objectType,
      keyVersion: out.keyVersion,
      suiteVersion: out.suiteVersion,
      payloadSchema: out.payloadSchema,
      authorDevice: envelope.authorDevice,
      hlc: envelope.hlc,
      blobHash: hash(blob),
      blob: blob,
    );
  }

  @override
  KeyAcceptance acceptWrappedKey(WireWrappedKey key) {
    final me = umk;
    if (me == null) return const KeyNotAccepted('no_umk');
    if (key.kind != WireWrappedKey.kindBkForUser) {
      return const KeyNotAccepted('wrong_kind');
    }
    final bookId = key.bookId;
    final version = key.keyVersion;
    if (bookId == null || version == null) {
      return const KeyNotAccepted('incomplete_row');
    }
    // 03 §2.2 has no recipient column: the row is ours by `user_id` (the
    // engine filters) and the unseal proves it. A fingerprint, when a sender
    // does include one, must be ours too.
    final mine = Fingerprint.of(suite, me.public);
    final fp = key.recipientFingerprint;
    if (fp != null && (fp.length != 32 || Fingerprint(fp) != mine)) {
      return const KeyNotAccepted('not_for_us');
    }
    final recipient = mine;
    final ref = BookKeyRef(bookId: bookId, keyVersion: version);
    if (keys.has(bookId, version)) return KeyAlreadyHeld(ref);
    final sealed = SealedBlob(recipient: recipient, bytes: key.blob);
    try {
      keys.put(
        unwrapBookKey(suite, WrappedBookKey(ref: ref, sealed: sealed), me),
      );
    } on UnsealFailed {
      return const KeyNotAccepted('unsealable');
    }
    // The wire blob unchanged: it is already sealed to this user's own UMK,
    // and re-wrapping it anywhere would be wrapping to a fingerprint nothing
    // verified (04 §8.2 🔒).
    return KeyAccepted(
      AcceptedBookKey(
        ref: ref,
        suiteVersion: sealed.suiteVersion,
        recipient: recipient,
        sealed: key.blob,
      ),
    );
  }

  @override
  void dropAllKeys() => keys.clear();

  @override
  DeviceCert? buildCert(WireDeviceCert cert, WireDevice device) {
    // The cert row carries no user: the signed bytes are
    // uuid16(device) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at_ms), so the owner and
    // the keys both come from the `devices` row (verification needs it anyway).
    final issuedAtMs = cert.issuedAtMs;
    if (issuedAtMs == null) return null;
    try {
      return DeviceCert(
        suiteVersion: cert.suiteVersion,
        userId: device.userId,
        device: DevicePublic(
          deviceId: device.id,
          ed25519: device.pubEd,
          x25519: device.pubX,
        ),
        issuedAtMs: issuedAtMs,
        signature: cert.signature,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
