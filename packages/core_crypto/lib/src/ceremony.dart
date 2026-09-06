import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'bytes.dart';
import 'keys.dart';
import 'suite.dart';

// Verification ceremony (04 §6): binds a UMK fingerprint — or, for device
// linking (04 §9.1), a new device's keys — to a human. This module is the ONLY
// producer of [VerifiedUmkPublic] and [VerifiedDevicePublic]; everything that
// seals to a person or a device demands one of those types, which is what makes
// 04 §8.2 ("no book key is wrapped to an unverified fingerprint") structural.
//
// Pure: no clock (the code path takes `nowMs`), no I/O, no logging — the caller
// records `verification_mismatch` and the verification event (04 §6.3, §6.4).

/// Nonce length in bytes (04 §6.1: per-invite 128-bit nonce).
const int ceremonyNonceBytes = 16;

/// Lifetime of a code nonce (04 §6.3: "nonce lifetime 10 minutes").
const int codeNonceLifetimeMs = 10 * 60 * 1000;

/// Attempts allowed per nonce (04 §6.3: "3 attempts per nonce").
const int codeMaxAttempts = 3;

/// Length of an encoded [QrPayload]: `u8 ‖ uuid16 ‖ ed(32) ‖ x(32) ‖ nonce(16)`.
const int _qrPayloadBytes = 1 + 16 + 32 + 32 + ceremonyNonceBytes;

/// Length of an encoded [DeviceQrPayload]: `u8 ‖ uuid16 ‖ ed(32) ‖ x(32) ‖ nonce(16)`.
const int _deviceQrPayloadBytes = 1 + 16 + 32 + 32 + ceremonyNonceBytes;

/// File-scope alias of the package constant — the payload classes have a
/// `suiteVersion` field that would otherwise shadow it.
const int _currentSuite = suiteVersion;

/// The suffix hashed into the 8-digit code (04 §6.1).
final Uint8List _verifyV1 = Uint8List.fromList(utf8.encode('verify-v1'));

Uint8List _checkedNonce(Uint8List nonce) {
  if (nonce.length != ceremonyNonceBytes) {
    throw ArgumentError.value(
      nonce.length,
      'nonce',
      'ceremony nonce is $ceremonyNonceBytes bytes',
    );
  }
  return Uint8List.fromList(nonce);
}

/// What the invitee's *Show my code* screen renders as a QR (04 §6.1):
/// `base64url( suite_version ‖ user_id ‖ UMK_pub_ed ‖ UMK_pub_x ‖ nonce )`.
@immutable
final class QrPayload {
  /// Builds a payload; [nonce] is the per-invite 16-byte nonce.
  QrPayload({
    required this.userId,
    required this.umk,
    required Uint8List nonce,
    this.suiteVersion = _currentSuite,
  }) : nonce = _checkedNonce(nonce) {
    if (!Uuid16.isCanonical(userId)) {
      throw FormatException('user_id must be a canonical uuid', userId);
    }
  }

  /// Parses the base64url text a scanner produced. Refuses a wrong length or
  /// an unknown suite with [FormatException] — the ceremony never guesses.
  factory QrPayload.decode(String encoded) {
    final Uint8List b;
    try {
      b = Bytes.fromBase64Url(encoded);
    } on FormatException {
      throw const FormatException('qr payload is not base64url');
    }
    if (b.length != _qrPayloadBytes) {
      throw FormatException(
        'qr payload is $_qrPayloadBytes bytes, got ${b.length}',
      );
    }
    if (b[0] != _currentSuite) {
      throw FormatException('unknown suite_version ${b[0]}');
    }
    return QrPayload(
      suiteVersion: b[0],
      userId: Uuid16.fromBytes(Uint8List.sublistView(b, 1, 17)),
      umk: UmkPublic(
        ed25519: Uint8List.sublistView(b, 17, 49),
        x25519: Uint8List.sublistView(b, 49, 81),
      ),
      nonce: Uint8List.sublistView(b, 81, 97),
    );
  }

  /// `suite_version` byte (04 §2).
  final int suiteVersion;

  /// The invitee's user id.
  final String userId;

  /// The invitee's UMK public halves as *they* present them.
  final UmkPublic umk;

  /// Per-invite nonce (not secret; scopes and expires codes).
  final Uint8List nonce;

  /// Canonical bytes, in exactly the 04 §6.1 order.
  Uint8List toBytes() => Bytes.concat([
    Bytes.u8(suiteVersion),
    Uuid16.toBytes(userId),
    umk.ed25519,
    umk.x25519,
    nonce,
  ]);

  /// The QR text: unpadded base64url of [toBytes].
  String encode() => Bytes.base64Url(toBytes());
}

/// The 8-digit code printed beneath the QR (04 §6.1):
/// `decimal( first4bytes( BLAKE2b-256( FP ‖ nonce ‖ "verify-v1" ) ) ) mod 10⁸`,
/// zero-padded to 8 digits. The first four bytes are read big-endian.
String verificationCode(CryptoSuite suite, Fingerprint fp, Uint8List nonce) {
  final n = _checkedNonce(nonce);
  final h = suite.blake2b256(Bytes.concat([fp.bytes, n, _verifyV1]));
  final first4 = ByteData.sublistView(h, 0, 4).getUint32(0);
  return (first4 % 100000000).toString().padLeft(8, '0');
}

/// Outcome of a ceremony step. Sealed so the UI must handle every case.
sealed class CeremonyResult {
  const CeremonyResult();
}

/// The human confirmed the keys: here is the type everything may seal to.
final class CeremonyVerified extends CeremonyResult {
  /// Wraps the verified key.
  const CeremonyVerified(this.verified);

  /// The now-verified UMK public key (04 §8.2).
  final VerifiedUmkPublic verified;
}

/// Scanned keys or user id differ from the server-relayed ones (04 §6.3):
/// hard-fail, *"Do not proceed. Contact support."* The caller logs a
/// `verification_mismatch` security event. There is no override.
final class CeremonyMismatch extends CeremonyResult {
  /// Creates the mismatch outcome.
  const CeremonyMismatch();
}

/// The typed code did not match; [attemptsLeft] remain on this nonce.
final class CodeWrong extends CeremonyResult {
  /// Creates the outcome with the remaining attempt count (≥ 1).
  const CodeWrong({required this.attemptsLeft});

  /// Attempts remaining before the nonce dies.
  final int attemptsLeft;
}

/// The nonce is older than [codeNonceLifetimeMs]; *Regenerate* is required.
final class CodeExpired extends CeremonyResult {
  /// Creates the expired outcome.
  const CodeExpired();
}

/// The nonce is dead — three wrong attempts (04 §10) or already consumed.
/// Even a correct code fails now; *Regenerate* issues a fresh nonce.
final class CodeExhausted extends CeremonyResult {
  /// Creates the exhausted outcome.
  const CodeExhausted();
}

/// State of a code-path verification for one nonce (04 §6.3). Immutable: each
/// [attempt] returns the successor state beside its result, so the UI keeps
/// the latest challenge and nothing here touches a clock.
@immutable
final class CodeChallenge {
  /// Opens a challenge for the server-relayed keys and the invite nonce
  /// issued at [issuedAtMs] (server time of invite creation, ms since epoch).
  CodeChallenge({
    required this.relayed,
    required Uint8List nonce,
    required this.issuedAtMs,
  }) : nonce = _checkedNonce(nonce),
       attemptsUsed = 0,
       dead = false;

  const CodeChallenge._(
    this.relayed,
    this.nonce,
    this.issuedAtMs,
    this.attemptsUsed,
    this.dead,
  );

  /// Server-relayed UMK public halves of the person being verified.
  final UmkPublic relayed;

  /// The invite nonce.
  final Uint8List nonce;

  /// When the nonce was issued (ms since epoch).
  final int issuedAtMs;

  /// Wrong attempts consumed so far.
  final int attemptsUsed;

  /// True once the nonce can never verify again (exhausted or consumed).
  final bool dead;

  /// Attempts still available on this nonce.
  int get attemptsLeft => dead ? 0 : codeMaxAttempts - attemptsUsed;

  /// True when [nowMs] is past the nonce's lifetime.
  // ⚠️ SPEC: 04 §6.3 gives the lifetime ("10 minutes") but not the boundary;
  // exactly 10:00.000 is accepted, 10:00.001 is expired (09 §2 clock-jump
  // convention: "at N + 1, not at N − 1").
  bool isExpiredAt(int nowMs) => nowMs - issuedAtMs > codeNonceLifetimeMs;

  /// Checks [typed] against the expected code derived from the *relayed* keys
  /// and the nonce (04 §6.3). Order of checks: dead → expired → compare. A
  /// malformed entry counts as a wrong attempt. The third wrong attempt kills
  /// the nonce and reports [CodeExhausted]; success also retires the nonce
  /// (one verification per nonce).
  ({CodeChallenge next, CeremonyResult result}) attempt(
    CryptoSuite suite, {
    required String typed,
    required int nowMs,
  }) {
    if (dead) return (next: this, result: const CodeExhausted());
    if (isExpiredAt(nowMs)) return (next: this, result: const CodeExpired());

    final expected = verificationCode(
      suite,
      Fingerprint.of(suite, relayed),
      nonce,
    );
    final cleaned = typed.replaceAll(RegExp(r'\s'), '');
    final ok = suite.constantTimeEquals(
      Uint8List.fromList(utf8.encode(expected)),
      Uint8List.fromList(utf8.encode(cleaned)),
    );
    if (ok) {
      return (
        next: CodeChallenge._(relayed, nonce, issuedAtMs, attemptsUsed, true),
        result: CeremonyVerified(
          VerifiedUmkPublic.internal(
            relayed,
            Fingerprint.of(suite, relayed),
            VerificationMethod.codeRemote,
          ),
        ),
      );
    }
    final used = attemptsUsed + 1;
    if (used >= codeMaxAttempts) {
      return (
        next: CodeChallenge._(relayed, nonce, issuedAtMs, used, true),
        result: const CodeExhausted(),
      );
    }
    return (
      next: CodeChallenge._(relayed, nonce, issuedAtMs, used, false),
      result: CodeWrong(attemptsLeft: codeMaxAttempts - used),
    );
  }
}

/// A device's public keys **confirmed by ceremony** on an existing certified
/// device (04 §9.1). The only type the UMK may be wrapped to. Constructed
/// solely by [Ceremony.verifyDeviceQr].
@immutable
final class VerifiedDevicePublic {
  const VerifiedDevicePublic._(this.public, this.method);

  /// The verified device keys and id.
  final DevicePublic public;

  /// How they were verified.
  final VerificationMethod method;
}

/// What a *new device's* Show-my-code screen renders (04 §9.1 — "the QR
/// carries the new device's keys"): `base64url( suite_version ‖ device_id ‖
/// device_pub_ed ‖ device_pub_x ‖ nonce )`, mirroring [QrPayload].
@immutable
final class DeviceQrPayload {
  /// Builds a payload for [device] under the link nonce.
  DeviceQrPayload({
    required this.device,
    required Uint8List nonce,
    this.suiteVersion = _currentSuite,
  }) : nonce = _checkedNonce(nonce);

  /// Parses scanned text; refuses wrong length / unknown suite.
  factory DeviceQrPayload.decode(String encoded) {
    final Uint8List b;
    try {
      b = Bytes.fromBase64Url(encoded);
    } on FormatException {
      throw const FormatException('device qr payload is not base64url');
    }
    if (b.length != _deviceQrPayloadBytes) {
      throw FormatException(
        'device qr payload is $_deviceQrPayloadBytes bytes, got ${b.length}',
      );
    }
    if (b[0] != _currentSuite) {
      throw FormatException('unknown suite_version ${b[0]}');
    }
    return DeviceQrPayload(
      suiteVersion: b[0],
      device: DevicePublic(
        deviceId: Uuid16.fromBytes(Uint8List.sublistView(b, 1, 17)),
        ed25519: Uint8List.sublistView(b, 17, 49),
        x25519: Uint8List.sublistView(b, 49, 81),
      ),
      nonce: Uint8List.sublistView(b, 81, 97),
    );
  }

  /// `suite_version` byte.
  final int suiteVersion;

  /// The new device's id and public keys as *it* presents them.
  final DevicePublic device;

  /// Per-link nonce.
  final Uint8List nonce;

  /// Canonical bytes.
  Uint8List toBytes() => Bytes.concat([
    Bytes.u8(suiteVersion),
    Uuid16.toBytes(device.deviceId),
    device.ed25519,
    device.x25519,
    nonce,
  ]);

  /// The QR text.
  String encode() => Bytes.base64Url(toBytes());
}

/// Outcome of the device-linking ceremony (04 §9.1).
sealed class DeviceCeremonyResult {
  const DeviceCeremonyResult();
}

/// The scanned device keys match the relayed ones.
final class DeviceVerified extends DeviceCeremonyResult {
  /// Wraps the verified device.
  const DeviceVerified(this.verified);

  /// The device the UMK may now be wrapped to.
  final VerifiedDevicePublic verified;
}

/// Scanned device keys or id differ from the relayed ones — hard-fail, log
/// `verification_mismatch`, no override (04 §6.3 applies unchanged).
final class DeviceMismatch extends DeviceCeremonyResult {
  /// Creates the mismatch outcome.
  const DeviceMismatch();
}

/// The QR-path checks (04 §6.3) for members and for devices.
final class Ceremony {
  Ceremony._();

  /// Compares the [scanned] payload against the [relayed] keys and
  /// [relayedUserId] the server supplied for that user. Every public key byte
  /// must match (constant-time) and the ids must agree; otherwise
  /// [CeremonyMismatch]. Method recorded: [VerificationMethod.qrInPerson] —
  /// the remote video-call scan is the same check (04 §6.4) and the caller
  /// may record it as remote in the verification event.
  static CeremonyResult verifyQr(
    CryptoSuite suite, {
    required QrPayload scanned,
    required UmkPublic relayed,
    required String relayedUserId,
  }) {
    final keysMatch =
        suite.constantTimeEquals(scanned.umk.ed25519, relayed.ed25519) &
        suite.constantTimeEquals(scanned.umk.x25519, relayed.x25519);
    final idMatch = scanned.userId == relayedUserId;
    if (!keysMatch || !idMatch) return const CeremonyMismatch();
    return CeremonyVerified(
      VerifiedUmkPublic.internal(
        relayed,
        Fingerprint.of(suite, relayed),
        VerificationMethod.qrInPerson,
      ),
    );
  }

  /// Device linking (04 §9.1): the old device scans the new device's QR and
  /// compares it byte-for-byte against the [relayed] device record.
  static DeviceCeremonyResult verifyDeviceQr(
    CryptoSuite suite, {
    required DeviceQrPayload scanned,
    required DevicePublic relayed,
  }) {
    final keysMatch =
        suite.constantTimeEquals(scanned.device.ed25519, relayed.ed25519) &
        suite.constantTimeEquals(scanned.device.x25519, relayed.x25519);
    final idMatch = scanned.device.deviceId == relayed.deviceId;
    if (!keysMatch || !idMatch) return const DeviceMismatch();
    return DeviceVerified(
      VerifiedDevicePublic._(relayed, VerificationMethod.qrInPerson),
    );
  }
}
