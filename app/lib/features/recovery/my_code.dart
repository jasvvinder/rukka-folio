// S11.2 *Show my code* — the fresh phone's half of the mutual recovery
// ceremony (ADR 2026-09-13c ruling 3 🔒, ADR 2026-09-24b §1 🔒, 04 §7.3 🔒
// rung 2).
//
// ============================================================================
// WHAT THIS FILE IS FOR
// ============================================================================
//
// Ruling 3 turns 04 §7.3 step 2's advice (*Call them before approving*) into
// a check: the fresh phone shows its **candidate** key as a 04 §9.1
// `DeviceQrPayload`; the guardian's phone scans it on S11.7 and compares it,
// byte for byte, with the request the server relayed
// (`Ceremony.verifyRecoveryCandidateQr`). A server that swapped the candidate
// key would have k guardians re-seal the real shares to a key of its own.
//
// So the one thing this code must never do is draw what the **server** says
// the candidate is. `candidate_pub_x` in the relayed request is exactly the
// value the guardian's phone compares against; a fresh phone that echoed it
// back would make the comparison compare the relay with itself, and the check
// would pass for the attacker every time.
//
// The key drawn is therefore **the one this phone holds**:
// [RecoveryCandidateKeys.held] (the platform key store item that
// `KeyStoreRecoveryCandidate` minted when this phone opened the attempt), and
// only when the attempt in hand is the one that key belongs to —
// `HttpGuardianRecovery.candidate`, which is null for any attempt whose key
// this phone does not hold. With either missing, there is no code: the screen
// says so in words, and draws no square.
//
// Only the QR text leaves here — a public key, an id and a nonce, nothing
// secret (the candidate's private half never leaves `recovery_candidate.dart`).
import 'package:core_crypto/core_crypto.dart'
    show CryptoSuite, DevicePublic, DeviceQrPayload, ceremonyNonceBytes;
import 'package:flutter/widgets.dart';

import '../../shared/seams/recovery_ladder.dart' show RecoveryFailure;
import '../../shared/sync/recovery_seams.dart'
    show RecoveryCandidate, RecoveryCandidateKeys;

/// What *Show my code* can draw now.
sealed class RecoveryMyCodeRead {
  const RecoveryMyCodeRead();
}

/// The QR text of this phone's own candidate key, ready to draw.
final class RecoveryMyCodeShown extends RecoveryMyCodeRead {
  /// Wraps the encoded `DeviceQrPayload`.
  const RecoveryMyCodeShown(this.qrText);

  /// The 04 §9.1 `DeviceQrPayload`, base64url — what the guardian scans.
  final String qrText;
}

/// This phone holds no candidate key for the attempt in hand — none at all,
/// or one that is not this attempt's. There is no code to show, and the
/// server's copy is never a stand-in for one.
final class RecoveryMyCodeNotHeld extends RecoveryMyCodeRead {
  /// The one value.
  const RecoveryMyCodeNotHeld();
}

/// This build cannot draw the code (no producer installed, or this phone's
/// own device keys cannot be read). Said plainly; nothing is drawn.
final class RecoveryMyCodeUnavailable extends RecoveryMyCodeRead {
  /// The one value.
  const RecoveryMyCodeUnavailable();
}

/// The seam S11.2's *Show my code* reads.
abstract interface class RecoveryMyCode {
  /// What to draw now. Throws [RecoveryFailure] when the key store could not
  /// be read — the screen's retryable error, never a guessed code.
  Future<RecoveryMyCodeRead> read();
}

/// [RecoveryMyCode] over the key this phone **holds**.
///
/// [keys] is the same `KeyStoreRecoveryCandidate` the live
/// `HttpGuardianRecovery` mints through; [pinned] is that seam's `candidate`
/// getter — the attempt in hand, null when this phone does not hold its key;
/// [thisDevice] is this phone's own device public keys (id and Ed25519 half
/// for the payload); [suite] draws the payload nonce (rule 7: libsodium, never
/// `dart:math`).
final class HeldCandidateMyCode implements RecoveryMyCode {
  /// Creates the producer.
  HeldCandidateMyCode({
    required RecoveryCandidateKeys keys,
    required RecoveryCandidate? Function() pinned,
    required Future<DevicePublic?> Function() thisDevice,
    required CryptoSuite suite,
  }) : _keys = keys,
       _pinned = pinned,
       _thisDevice = thisDevice,
       _suite = suite;

  final RecoveryCandidateKeys _keys;
  final RecoveryCandidate? Function() _pinned;
  final Future<DevicePublic?> Function() _thisDevice;
  final CryptoSuite _suite;

  @override
  Future<RecoveryMyCodeRead> read() async {
    final held = await () async {
      try {
        return await _keys.held();
      } on Object {
        throw const RecoveryFailure('key_store');
      }
    }();
    if (held == null) return const RecoveryMyCodeNotHeld();

    // The attempt in hand must be the one this key belongs to. A held key
    // with no attempt pinned to it is one no guardian will ever seal to, and
    // a pinned attempt whose key differs is somebody else's (or the relay's).
    final attempt = _pinned();
    if (attempt == null ||
        attempt.candidatePubX.length != held.length ||
        !_suite.constantTimeEquals(attempt.candidatePubX, held)) {
      return const RecoveryMyCodeNotHeld();
    }

    final DevicePublic? me;
    try {
      me = await _thisDevice();
    } on Object {
      return const RecoveryMyCodeUnavailable();
    }
    if (me == null) return const RecoveryMyCodeUnavailable();

    // ⚠️ SPEC: ADR 2026-09-13c §3 names the 04 §9.1 `DeviceQrPayload` but no
    // doc fixes its nonce for a recovery candidate (04 §9.1's is the link
    // nonce). `verifyRecoveryCandidateQr` compares only the device id and the
    // X25519 half, so a fresh 16 bytes from the suite are drawn per display —
    // the reseal test's `show` does the same (core_crypto
    // test/reseal_test.dart). Reported.
    return RecoveryMyCodeShown(
      DeviceQrPayload(
        device: DevicePublic(
          deviceId: me.deviceId,
          ed25519: me.ed25519,
          // The HELD bytes — never `attempt.candidatePubX`, even though they
          // were just compared equal: what this phone shows is its own.
          x25519: held,
        ),
        nonce: _suite.randomBytes(ceremonyNonceBytes),
      ).encode(),
    );
  }
}

/// Installs the [RecoveryMyCode] producer for S11.2, the way
/// `GuardianRecoveryScope` installs its seam. With none installed the screen
/// says this phone cannot show its code yet — never a made-up one.
class RecoveryMyCodeScope extends InheritedWidget {
  /// Wraps [child].
  const RecoveryMyCodeScope({
    super.key,
    required this.myCode,
    required super.child,
  });

  /// The producer.
  final RecoveryMyCode myCode;

  /// The installed producer, or null.
  static RecoveryMyCode? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecoveryMyCodeScope>()?.myCode;

  @override
  bool updateShouldNotify(RecoveryMyCodeScope old) => myCode != old.myCode;
}
