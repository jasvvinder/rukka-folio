import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium.dart';

import 'ceremony.dart';
import 'keys.dart';
import 'shamir.dart';
import 'suite.dart';

// Key wrapping (04 §3, §5.1–§5.3, §8.2, §9.1): X25519 sealed boxes
// (`crypto_box_seal`) to a *ceremony-verified* recipient. The recipient
// parameters are [VerifiedUmkPublic] / [VerifiedDevicePublic] — types only
// `ceremony.dart` can produce — so passing a server-relayed [UmkPublic] or
// [DevicePublic] is a compile error, not a runtime check (CLAUDE.md rule 5).
//
// Every intermediate plaintext buffer is zeroised in `finally`; long-lived
// secrets stay in `SecureKey` (ADR 2026-09-05 §8).

/// File-scope alias — the artefact classes carry a `suiteVersion` field.
const int _currentSuite = suiteVersion;

/// Opening a sealed box failed: wrong recipient, corrupt bytes, unknown
/// suite, or a payload of the wrong shape. Deliberately carries no detail
/// beyond [reason] — nothing about the plaintext leaks.
final class UnsealFailed implements Exception {
  /// Creates the failure.
  const UnsealFailed(this.reason);

  /// Short machine-readable reason (`suite`, `recipient`, `box`, `length`).
  final String reason;

  @override
  String toString() => 'UnsealFailed($reason)';
}

/// An X25519 sealed box addressed to one person (04 §2 "key wrapping to a
/// person"). Opaque to the server; carries its suite and recipient so a
/// device can pick its own copies out of a relay without trying each.
@immutable
final class SealedBlob {
  /// Wraps sealed bytes.
  SealedBlob({
    required this.recipient,
    required Uint8List bytes,
    this.suiteVersion = _currentSuite,
  }) : bytes = Uint8List.fromList(bytes);

  /// `suite_version` byte (04 §2).
  final int suiteVersion;

  /// Fingerprint of the UMK the box is sealed to.
  final Fingerprint recipient;

  /// `crypto_box_seal` output (ephemeral pk ‖ ciphertext ‖ tag).
  final Uint8List bytes;
}

/// Seals [plaintext] to a ceremony-verified UMK (04 §5.1, §8.2). Generic —
/// book keys, guardian shares (04 §7.3) and head escrow (04 §7.5) all use it.
/// [plaintext] is the caller's buffer and the caller zeroises it.
SealedBlob sealToVerified(
  CryptoSuite suite,
  VerifiedUmkPublic to,
  Uint8List plaintext,
) => SealedBlob(
  recipient: to.fingerprint,
  bytes: suite.sodium.crypto.box.seal(
    message: plaintext,
    publicKey: to.public.x25519,
  ),
);

/// Opens a [SealedBlob] addressed to [me]. Throws [UnsealFailed] when the
/// suite is unknown, the recipient is someone else, or the box does not open.
/// The returned buffer is the caller's to zeroise.
Uint8List openSealed(CryptoSuite suite, UmkKeyPair me, SealedBlob blob) {
  if (blob.suiteVersion != _currentSuite) throw const UnsealFailed('suite');
  if (blob.recipient != Fingerprint.of(suite, me.public)) {
    throw const UnsealFailed('recipient');
  }
  try {
    return suite.sodium.crypto.box.sealOpen(
      cipherText: blob.bytes,
      publicKey: me.public.x25519,
      secretKey: me.x25519Secret,
    );
  } on SodiumException {
    throw const UnsealFailed('box');
  }
}

/// A book key sealed to one member (04 §3.2, §5.1): what the server stores in
/// `wrapped_keys` and relays — it never sees the key.
@immutable
final class WrappedBookKey {
  /// Wraps a sealed copy of [ref].
  const WrappedBookKey({required this.ref, required this.sealed});

  /// Which `(book_id, key_version)` is inside.
  final BookKeyRef ref;

  /// The sealed box.
  final SealedBlob sealed;

  /// `suite_version` byte.
  int get suiteVersion => sealed.suiteVersion;

  /// Fingerprint of the member it is sealed to.
  Fingerprint get recipient => sealed.recipient;

  /// The sealed bytes.
  Uint8List get blob => sealed.bytes;
}

/// Seals [bk] to a ceremony-verified member (04 §5.1). Only a
/// [VerifiedUmkPublic] is accepted — 04 §8.2 is a type, not a check. The key
/// bytes leave guarded memory only inside `runUnlockedSync` and are zeroised
/// as soon as the box is sealed.
WrappedBookKey wrapBookKey(
  CryptoSuite suite,
  BookKey bk,
  VerifiedUmkPublic to,
) {
  final copy = bk.key.runUnlockedSync((b) => Uint8List.fromList(b));
  try {
    return WrappedBookKey(ref: bk.ref, sealed: sealToVerified(suite, to, copy));
  } finally {
    suite.zeroize(copy);
  }
}

/// Opens [wrapped] with [me]'s UMK and returns the book key in guarded
/// memory. Throws [UnsealFailed] for anyone but the intended member (04 §10:
/// a removed member's device fails on every post-rotation key).
BookKey unwrapBookKey(
  CryptoSuite suite,
  WrappedBookKey wrapped,
  UmkKeyPair me,
) {
  final plain = openSealed(suite, me, wrapped.sealed);
  try {
    if (plain.length !=
        suite.sodium.crypto.aeadXChaCha20Poly1305IETF.keyBytes) {
      throw const UnsealFailed('length');
    }
    return BookKey(wrapped.ref, suite.sodium.secureCopy(plain));
  } finally {
    suite.zeroize(plain);
  }
}

/// The UMK's 64 secret bytes sealed to one of the user's own devices
/// (04 §3 "wrapped to each Device Key"; §9.1 linking).
@immutable
final class WrappedUmk {
  /// Wraps sealed bytes for [deviceId].
  WrappedUmk({
    required this.deviceId,
    required Uint8List bytes,
    this.suiteVersion = _currentSuite,
  }) : bytes = Uint8List.fromList(bytes);

  /// `suite_version` byte.
  final int suiteVersion;

  /// The device the UMK is sealed to.
  final String deviceId;

  /// `crypto_box_seal` output.
  final Uint8List bytes;
}

/// Linking (04 §9.1): after the device ceremony, the old device seals the UMK
/// secret bytes to the new device's X25519 key. Accepts only a
/// [VerifiedDevicePublic]. Never produces anything but the sealed form —
/// the UMK is not backed up in plaintext anywhere (04 §7.6).
WrappedUmk wrapUmkToDevice(
  CryptoSuite suite,
  UmkKeyPair umk,
  VerifiedDevicePublic device,
) {
  final secret = umk.exportSecretBytes();
  try {
    return WrappedUmk(
      deviceId: device.public.deviceId,
      bytes: suite.sodium.crypto.box.seal(
        message: secret,
        publicKey: device.public.x25519,
      ),
    );
  } finally {
    suite.zeroize(secret);
  }
}

/// Opens the UMK wrapped to [device]. Throws [UnsealFailed] when the suite is
/// unknown, the blob is for another device, or the box does not open.
UmkKeyPair unwrapUmk(
  CryptoSuite suite,
  WrappedUmk wrapped,
  DeviceKeyPair device,
) {
  if (wrapped.suiteVersion != _currentSuite) throw const UnsealFailed('suite');
  if (wrapped.deviceId != device.deviceId) {
    throw const UnsealFailed('recipient');
  }
  final Uint8List secret;
  try {
    secret = suite.sodium.crypto.box.sealOpen(
      cipherText: wrapped.bytes,
      publicKey: device.public.x25519,
      secretKey: device.x25519Secret,
    );
  } on SodiumException {
    throw const UnsealFailed('box');
  }
  try {
    if (secret.length != 64) {
      throw const UnsealFailed('length');
    }
    return UmkKeyPair.fromSecretBytes(suite, secret);
  } finally {
    suite.zeroize(secret);
  }
}

/// A guardian's share **re-sealed to a recovery candidate** (04 §7.3 step 3):
/// what `POST /sync-meta/recovery/approve` carries as `{sealed_to_pub_x,
/// blob}` and what the server files as a `wrapped_keys` row of kind
/// `recovery_blob` addressed to the candidate device (migration 0010,
/// `rf.recovery_decide`). Opaque to the server: it compares [sealedTo]
/// against the request's `candidate_pub_x` and never opens [bytes].
@immutable
final class ResealedShare {
  /// Wraps the parts.
  ResealedShare({
    required this.deviceId,
    required Uint8List sealedTo,
    required this.shareSetVersion,
    required Uint8List bytes,
    this.suiteVersion = _currentSuite,
  }) : sealedTo = Uint8List.fromList(sealedTo),
       bytes = Uint8List.fromList(bytes) {
    if (this.sealedTo.length != 32) {
      throw ArgumentError.value(
        this.sealedTo.length,
        'sealedTo',
        'candidate X25519 public key is 32 bytes',
      );
    }
  }

  /// `suite_version` byte (04 §2).
  final int suiteVersion;

  /// The candidate device the box is addressed to (`wrapped_keys.device_id`).
  final String deviceId;

  /// The candidate X25519 public key the share was sealed to —
  /// `sealed_to_pub_x`, the 32 bytes the server compares (ADR 2026-09-13c §3).
  final Uint8List sealedTo;

  /// The share's generation, read from its own header (04 §7.3
  /// `share_set_version`) — fills `recovery_approvals.share_set_version`.
  final int shareSetVersion;

  /// `crypto_box_seal` output — the opaque `blob`.
  final Uint8List bytes;
}

/// 04 §7.3 step 3 on the guardian's device, ADR 2026-09-13c §3 🔒: opens this
/// guardian's [stored] share (sealed to [guardian]'s UMK at setup) and
/// re-seals it to the [candidate] the guardian's device **verified by
/// ceremony**. The recipient is [VerifiedRecoveryCandidate] — a type only
/// [Ceremony.verifyRecoveryCandidateQr] produces — so the server-relayed
/// `candidate_pub_x`, a scanned-but-unchecked key or any bare X25519 key
/// cannot be passed: the substitution that would hand k real shares to a
/// server key (ADR 2026-09-13c §3) has no call to make (CLAUDE.md rule 5).
///
/// The plaintext share is decoded only to check it is a guardian share of
/// this suite and to read its generation, then re-sealed **unchanged** and
/// zeroised in `finally`; [stored] is not modified. Throws [UnsealFailed]
/// when [stored] does not open for [guardian] (`recipient`, `box`, `suite`)
/// or does not hold a guardian share (`share`).
ResealedShare resealShareToCandidate(
  CryptoSuite suite, {
  required UmkKeyPair guardian,
  required SealedBlob stored,
  required VerifiedRecoveryCandidate candidate,
}) {
  final plain = openSealed(suite, guardian, stored);
  GuardianShare? share;
  try {
    try {
      share = GuardianShare.decode(plain);
    } on FormatException {
      throw const UnsealFailed('share');
    } on ArgumentError {
      throw const UnsealFailed('share');
    }
    return ResealedShare(
      deviceId: candidate.deviceId,
      sealedTo: candidate.x25519,
      shareSetVersion: share.shareSetVersion,
      bytes: suite.sodium.crypto.box.seal(
        message: plain,
        publicKey: candidate.x25519,
      ),
    );
  } finally {
    share?.dispose();
    suite.zeroize(plain);
  }
}

/// 04 §7.3 step 4 on the fresh device: opens a [ResealedShare] addressed to
/// its [candidate] pair. Throws [UnsealFailed] when the suite is unknown, the
/// box names another candidate key (`recipient`), the box does not open
/// (`box`) or the plaintext is not a guardian share (`share`). The returned
/// share is the caller's to [GuardianShare.dispose] after reconstruction.
GuardianShare openResealedShare(
  CryptoSuite suite,
  ResealedShare resealed,
  RecoveryCandidateKeyPair candidate,
) {
  if (resealed.suiteVersion != _currentSuite) {
    throw const UnsealFailed('suite');
  }
  if (!suite.constantTimeEquals(resealed.sealedTo, candidate.x25519)) {
    throw const UnsealFailed('recipient');
  }
  final Uint8List plain;
  try {
    plain = suite.sodium.crypto.box.sealOpen(
      cipherText: resealed.bytes,
      publicKey: candidate.x25519,
      secretKey: candidate.x25519Secret,
    );
  } on SodiumException {
    throw const UnsealFailed('box');
  }
  try {
    return GuardianShare.decode(plain);
  } on FormatException {
    throw const UnsealFailed('share');
  } on ArgumentError {
    throw const UnsealFailed('share');
  } finally {
    suite.zeroize(plain);
  }
}

/// Rotation (04 §5.3 step 2): a fresh `BK(v+1)` for [current]'s book, sealed
/// to every [remaining] member and to nobody else. The leaver is simply absent
/// from [remaining] — there is no list to strike them from. [current] is not
/// disposed: old versions stay wrapped so history remains readable (04 §3.2).
({BookKey next, List<WrappedBookKey> wrapped}) rotateBookKey(
  CryptoSuite suite,
  BookKey current,
  Iterable<VerifiedUmkPublic> remaining,
) {
  final next = BookKey.generate(
    suite,
    bookId: current.ref.bookId,
    keyVersion: current.ref.keyVersion + 1,
  );
  return (
    next: next,
    wrapped: [for (final m in remaining) wrapBookKey(suite, next, m)],
  );
}
