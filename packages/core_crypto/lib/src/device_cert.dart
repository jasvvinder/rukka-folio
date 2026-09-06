import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'bytes.dart';
import 'keys.dart';
import 'suite.dart';

// The class field `suiteVersion` shadows the library constant inside the
// class body; this alias resolves at file scope.
const int _currentSuite = suiteVersion;

/// A device certificate (04 §3.4 🔒): the user's UMK Ed25519 half vouches
/// for a device's keys.
///
/// `cert = Sign_UMK_ed(device_id ‖ device_pub_ed ‖ device_pub_x ‖ issued_at)`
/// — at signup the first device self-certifies with the UMK it just
/// generated; later devices are certified by an existing certified device
/// (04 §9.1) or at recovery completion (04 §7.3). All three are the same
/// [DeviceCert.issue] call; only who holds the UMK differs.
///
/// ⚠️ SPEC: 04 §3.4 puts neither `user_id` nor `suite_version` inside the
/// signed bytes. Both are carried plaintext beside the signature. The chain
/// still holds because a verifier only accepts the cert under the *claimed*
/// user's ceremony-verified UMK (04 §3.4 third bullet) — a cert relabelled to
/// another user fails under that user's key. Implemented exactly as 04 writes
/// it; flagged for the owner.
@immutable
final class DeviceCert {
  /// Assembles a certificate from stored parts (validates shape only).
  DeviceCert({
    required this.suiteVersion,
    required this.userId,
    required this.device,
    required this.issuedAtMs,
    required Uint8List signature,
  }) : signature = Uint8List.fromList(signature) {
    if (!Uuid16.isCanonical(userId)) {
      throw FormatException('user_id must be a canonical uuid', userId);
    }
    if (signature.length != deviceCertSigBytes) {
      throw ArgumentError.value(signature.length, 'signature', '64 bytes');
    }
  }

  /// Issues a certificate for [device] under [issuer]'s Ed25519 half.
  /// [issuedAtMs] is injected by the caller — this package never reads a
  /// clock (CLAUDE.md rule 3).
  factory DeviceCert.issue(
    CryptoSuite suite, {
    required UmkKeyPair issuer,
    required String userId,
    required DevicePublic device,
    required int issuedAtMs,
  }) {
    final sig = suite.sodium.crypto.sign.detached(
      message: signedBytes(device: device, issuedAtMs: issuedAtMs),
      secretKey: issuer.ed25519Secret,
    );
    return DeviceCert(
      suiteVersion: _currentSuite,
      userId: userId,
      device: device,
      issuedAtMs: issuedAtMs,
      signature: sig,
    );
  }

  /// Ed25519 detached signature length.
  static const int deviceCertSigBytes = 64;

  /// The bytes the UMK signs (04 §3.4 🔒 order):
  /// `uuid16(device_id) ‖ device_pub_ed(32) ‖ device_pub_x(32) ‖ i64be(issued_at_ms)`.
  static Uint8List signedBytes({
    required DevicePublic device,
    required int issuedAtMs,
  }) => Bytes.concat([
    Uuid16.toBytes(device.deviceId),
    device.ed25519,
    device.x25519,
    Bytes.i64be(issuedAtMs),
  ]);

  /// `suite_version` (04 §2 — every stored artefact carries it).
  final int suiteVersion;

  /// The user whose UMK issued this certificate (plaintext, unsigned — see
  /// the class note).
  final String userId;

  /// The certified device: id and public keys.
  final DevicePublic device;

  /// Issue time in Unix milliseconds, as stamped by the issuing device.
  final int issuedAtMs;

  /// `Sign_UMK_ed(...)` over [signedBytes].
  final Uint8List signature;

  /// Device id shorthand.
  String get deviceId => device.deviceId;

  /// True when [signature] verifies under [issuerUmk]'s Ed25519 half.
  ///
  /// Accepting a plain [UmkPublic] here is deliberate: `ChainVerifier` is
  /// where "this UMK is ceremony-verified for the tenant" is enforced (it
  /// passes `VerifiedUmkPublic.public`).
  bool verify(CryptoSuite suite, UmkPublic issuerUmk) =>
      suite.sodium.crypto.sign.verifyDetached(
        message: signedBytes(device: device, issuedAtMs: issuedAtMs),
        signature: signature,
        publicKey: issuerUmk.ed25519,
      );
}
