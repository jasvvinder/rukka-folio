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

/// **Retired derivation** (ADR 2026-09-13d §1 🔒, ratified 13 Sep 2026; the
/// app switched at U4c): `decimal( first4bytes( BLAKE2b-256( FP ‖ nonce ‖
/// "verify-v1" ) ) ) mod 10⁸`, zero-padded, first four bytes big-endian. A
/// relay that holds the registered key and issues the nonces pre-computes it
/// (B-04-87), so **no production path derives a code from it** — 04 §6.1 now
/// says the invite nonce "no longer derives any code". Kept only so B-04-87
/// can demonstrate the break against the real function; the live code is
/// [sasCode]. Do not call this from `app/`.
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

/// **Retired** with [verificationCode] (ADR 2026-09-13d §1): the code-path
/// state over a server-issued nonce. The live verifier-side state is
/// [SasChallenge], reached through [SasVerifier]; this class stays only as
/// B-04-87's target. Immutable: each [attempt] returns the successor state
/// beside its result; nothing here touches a clock.
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

/// A recovery **candidate** — the X25519 key a fresh phone asked its guardians
/// to re-seal their shares to (04 §7.3 step 1) — **confirmed by ceremony on
/// the guardian's device** (ADR 2026-09-13c §3 🔒). The only type a guardian
/// share may be re-sealed to. Constructed solely by
/// [Ceremony.verifyRecoveryCandidateQr]; there is no other constructor, so a
/// server-relayed `candidate_pub_x` or a bare X25519 key is a compile error at
/// the re-seal, not a runtime check (CLAUDE.md rule 5, 04 §8.2).
///
/// Why not [VerifiedDevicePublic]: the recovery request relays the candidate
/// as `candidate_device` + `candidate_pub_x` (migration 0010; `GET
/// /sync-meta/recovery/asks`) and nothing else — the guardian holds no relayed
/// Ed25519 half to compare the payload's against, so a [DevicePublic] for
/// [Ceremony.verifyDeviceQr] could only be fabricated from the scan itself.
/// This type carries exactly what was compared: the device id and the 32
/// X25519 bytes. The fresh device's Ed25519 key is bound later, by the
/// certificate it self-issues under the recovered UMK (04 §7.3 step 6), and
/// verified by the members then — never by the guardian.
@immutable
final class VerifiedRecoveryCandidate {
  const VerifiedRecoveryCandidate._(this.deviceId, this.x25519, this.method);

  /// The candidate device's id, as scanned and as the request named it.
  final String deviceId;

  /// The candidate X25519 public key — the 32 bytes the guardian's screen
  /// compared and the re-seal goes to (`sealed_to_pub_x` on the wire).
  final Uint8List x25519;

  /// How it was verified — always [VerificationMethod.qrInPerson]: ruling 2
  /// of ADR 2026-09-13c admits no code path at recovery.
  final VerificationMethod method;
}

/// Outcome of the guardian's candidate ceremony (ADR 2026-09-13c §3).
sealed class RecoveryCandidateResult {
  const RecoveryCandidateResult();
}

/// The scanned candidate matches the relayed request: *Approve* may proceed.
final class RecoveryCandidateVerified extends RecoveryCandidateResult {
  /// Wraps the verified candidate.
  const RecoveryCandidateVerified(this.verified);

  /// The candidate a share may now be re-sealed to.
  final VerifiedRecoveryCandidate verified;
}

/// The scanned candidate key or device id differs from the relayed request —
/// the phone in front of the guardian is not the one the request names, or
/// the relay substituted the key (ADR 2026-09-13c §3: "a server that swaps
/// the candidate public key … has k guardians re-seal the real shares to a
/// server key"). Hard fail as 04 §6.3: *"Do not proceed. Contact support."*,
/// log `verification_mismatch`, no override, *Approve* stays disabled.
final class RecoveryCandidateMismatch extends RecoveryCandidateResult {
  /// Creates the mismatch outcome.
  const RecoveryCandidateMismatch();
}

/// The QR-path checks (04 §6.3) for members, for devices and for recovery
/// candidates.
final class Ceremony {
  Ceremony._();

  /// The guardian's half of the recovery ceremony (ADR 2026-09-13c §3 🔒,
  /// 04 §7.3 step 2 — *"Call them before approving"* made a check): the
  /// fresh device shows its candidate key as a [DeviceQrPayload]; the
  /// guardian's device scans it and compares the payload's device id and
  /// X25519 half **byte-for-byte** (constant time) against the request the
  /// server relayed — [relayedDeviceId] (`candidate_device`) and
  /// [relayedCandidateX25519] (`candidate_pub_x`). Equal →
  /// [RecoveryCandidateVerified]; otherwise [RecoveryCandidateMismatch].
  ///
  /// The payload's Ed25519 half has no relayed counterpart in a recovery
  /// request and is neither compared nor carried into the result (see
  /// [VerifiedRecoveryCandidate]). QR only — the remote mode is a scan off a
  /// video call (04 §6.4); no code path exists here (ADR 2026-09-13c §2).
  static RecoveryCandidateResult verifyRecoveryCandidateQr(
    CryptoSuite suite, {
    required DeviceQrPayload scanned,
    required String relayedDeviceId,
    required Uint8List relayedCandidateX25519,
  }) {
    if (relayedCandidateX25519.length != 32) {
      throw ArgumentError.value(
        relayedCandidateX25519.length,
        'relayedCandidateX25519',
        'candidate X25519 public key is 32 bytes',
      );
    }
    final keyMatch = suite.constantTimeEquals(
      scanned.device.x25519,
      relayedCandidateX25519,
    );
    final idMatch = scanned.device.deviceId == relayedDeviceId;
    if (!keyMatch || !idMatch) return const RecoveryCandidateMismatch();
    return RecoveryCandidateVerified(
      VerifiedRecoveryCandidate._(
        relayedDeviceId,
        Uint8List.fromList(relayedCandidateX25519),
        VerificationMethod.qrInPerson,
      ),
    );
  }

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

// ---------------------------------------------------------------------------
// Commitment-based short authentication string (SAS) — the code path against
// a substituting relay. ADR 2026-09-13d (proposed 13 Sep 2026, escalation lane
// M7-K4; owner to ratify). Nothing above this line changed.
//
// Why it exists. `verificationCode` is a function of two values the server
// holds or chooses — the registered fingerprint (06 §3 item 3) and the invite
// nonce (04 §6.1) — so a relay that substitutes UMK′ can *predict* the honest
// eight digits and search its own inputs until the codes collide: ~10⁸
// BLAKE2b evaluations when it controls one nonce, ~2·10⁴ (a birthday search)
// when it relays independent nonces to the two sides. First attempt, no
// mismatch shown, rate limits never engaged (B-04-87). The 3-attempt and
// 10-minute rules of 04 §6.3 bound an *online guesser*; they do nothing
// against an *offline searcher* who controls one side's inputs.
//
// The repair is the textbook one (Vaudenay 2005 SAS authentication; Bluetooth
// numeric comparison): each side contributes randomness the other cannot see
// in time. The shower commits to r_S before anyone learns it; the verifier
// draws r_V only once it holds the commitment *and* the relayed key; the
// shower opens r_S only after r_V has arrived — and exactly once. Every value
// the relay could tune is therefore fixed before the value it would have to
// be tuned against exists, and a substituting relay is reduced to one blind
// guess in 10⁸ per attempt (B-04-88) — which is what "3 attempts per nonce"
// was always sized for.
//
// Ratified 13 Sep 2026; S9.2 / S9.3 run on this path since U4c
// (`app/lib/features/ceremony/ceremony_repository.dart`), and the server
// relays the three values (commitment → r_V → opening; `ceremony_sessions`,
// 0007). `verificationCode` / `CodeChallenge` above are retired and remain
// only as B-04-87's target. Purity as above: randomness from the injected
// suite, the clock from `nowMs`, no I/O.
// ---------------------------------------------------------------------------

/// Bytes in each side's random contribution (`r_S`, `r_V`): 128-bit.
const int sasContributionBytes = 16;

/// Bytes in a commitment: BLAKE2b-256.
const int sasCommitmentBytes = 32;

/// Domain tag hashed into a commitment.
final Uint8List _sasCommitV1 = Uint8List.fromList(
  utf8.encode('rf-sas-commit-v1'),
);

/// Domain tag hashed into the code.
final Uint8List _sasCodeV1 = Uint8List.fromList(utf8.encode('rf-sas-code-v1'));

Uint8List _checkedContribution(Uint8List r, String name) {
  if (r.length != sasContributionBytes) {
    throw ArgumentError.value(
      r.length,
      name,
      'SAS contribution is $sasContributionBytes bytes',
    );
  }
  return Uint8List.fromList(r);
}

String _checkedUserId(String userId) {
  if (!Uuid16.isCanonical(userId)) {
    throw FormatException('user_id must be a canonical uuid', userId);
  }
  return userId;
}

/// `c = BLAKE2b-256( "rf-sas-commit-v1" ‖ FP ‖ user_id ‖ r_S )`.
///
/// Every field is fixed-length, so the concatenation is unambiguous. Binding
/// the fingerprint and the user id into the commitment is what stops a relay
/// from replaying an honest commitment under a substituted key or another
/// person (B-04-89); `r_S` (128 random bits) is what makes it hiding.
Uint8List sasCommitment(
  CryptoSuite suite, {
  required Fingerprint fp,
  required String userId,
  required Uint8List showerRandom,
}) {
  final rS = _checkedContribution(showerRandom, 'showerRandom');
  return suite.blake2b256(
    Bytes.concat([
      _sasCommitV1,
      fp.bytes,
      Uuid16.toBytes(_checkedUserId(userId)),
      rS,
    ]),
  );
}

/// The eight-digit SAS:
/// `decimal( first4bytes( BLAKE2b-256( "rf-sas-code-v1" ‖ FP ‖ user_id ‖ r_S ‖ r_V ) ) ) mod 10⁸`,
/// zero-padded, first four bytes big-endian — the same shape as
/// [verificationCode], so 07 §12's eight boxes and S9.3's entry field need no
/// change when the switch is made.
String sasCode(
  CryptoSuite suite, {
  required Fingerprint fp,
  required String userId,
  required Uint8List showerRandom,
  required Uint8List verifierRandom,
}) {
  final rS = _checkedContribution(showerRandom, 'showerRandom');
  final rV = _checkedContribution(verifierRandom, 'verifierRandom');
  final h = suite.blake2b256(
    Bytes.concat([
      _sasCodeV1,
      fp.bytes,
      Uuid16.toBytes(_checkedUserId(userId)),
      rS,
      rV,
    ]),
  );
  final first4 = ByteData.sublistView(h, 0, 4).getUint32(0);
  return (first4 % 100000000).toString().padLeft(8, '0');
}

/// What the shower's device relays and shows once `r_V` has arrived.
@immutable
final class SasResponse {
  const SasResponse._(this.opening, this.code);

  /// `r_S` — relayed to the verifier, whose device checks it against the
  /// commitment it already holds.
  final Uint8List opening;

  /// The eight digits to show beneath the QR and read aloud.
  final String code;
}

/// The invitee's side of the SAS code path (04 §6.2 *Show my code*).
///
/// One session is one `r_S`, one commitment and **one** response. [respond]
/// is single-use on purpose: a second code under the same `r_S` would hand a
/// relay that has just learned `r_S` a fresh code to search `r_V′` against
/// (B-04-88). When a verifier needs another try, *Regenerate* opens a new
/// session — the same gesture 04 §6.3 already has.
final class SasShower {
  SasShower._(this.userId, this.umk, this._rS, this.commitment);

  /// Draws `r_S` from the suite's RNG and commits to it under this device's
  /// own [umk] and [userId]. Only [commitment] leaves the device before `r_V`
  /// arrives.
  factory SasShower.open(
    CryptoSuite suite, {
    required String userId,
    required UmkPublic umk,
  }) {
    final id = _checkedUserId(userId);
    final rS = suite.randomBytes(sasContributionBytes);
    return SasShower._(
      id,
      umk,
      rS,
      sasCommitment(
        suite,
        fp: Fingerprint.of(suite, umk),
        userId: id,
        showerRandom: rS,
      ),
    );
  }

  /// This device's user id, as it goes into the commitment.
  final String userId;

  /// This device's own UMK public halves.
  final UmkPublic umk;

  final Uint8List _rS;

  /// The commitment to relay.
  final Uint8List commitment;

  bool _spent = false;

  /// True once [respond] has run; the session then never shows another code.
  bool get isSpent => _spent;

  /// Opens the commitment for the relayed [verifierRandom] and derives the
  /// code to show. Exactly once per session: a second call throws
  /// [StateError] — open a new [SasShower] instead.
  SasResponse respond(CryptoSuite suite, Uint8List verifierRandom) {
    if (_spent) {
      throw StateError(
        'SasShower.respond called twice: one code per commitment — '
        'open a new session (Regenerate)',
      );
    }
    final rV = _checkedContribution(verifierRandom, 'verifierRandom');
    _spent = true;
    return SasResponse._(
      Uint8List.fromList(_rS),
      sasCode(
        suite,
        fp: Fingerprint.of(suite, umk),
        userId: userId,
        showerRandom: _rS,
        verifierRandom: rV,
      ),
    );
  }
}

/// Outcome of opening the relayed commitment on the verifier's device.
sealed class SasOpenResult {
  const SasOpenResult();
}

/// The opening matched the commitment under the relayed key and id; the
/// [challenge] now takes the typed digits.
final class SasOpened extends SasOpenResult {
  /// Wraps the ready challenge.
  const SasOpened(this.challenge);

  /// Attempt state for this session.
  final SasChallenge challenge;
}

/// The relayed opening does not open the relayed commitment under the relayed
/// key and user id — the relay lied about at least one of the three. Treat
/// exactly as [CeremonyMismatch] (04 §6.3): hard fail, *"Do not proceed.
/// Contact support."*, log `verification_mismatch`, no override.
final class SasOpeningMismatch extends SasOpenResult {
  /// Creates the outcome.
  const SasOpeningMismatch();
}

/// The verifier's side of the SAS code path (04 §6.2 *Verify member* →
/// *Enter code instead*).
///
/// Ordering is structural, not advisory: `r_V` is drawn inside
/// [SasVerifier.begin], which cannot run without the relayed key **and** the
/// relayed commitment — so the relay has fixed both before `r_V` exists
/// (B-04-88). [open] is single-use; a mismatch there ends the session.
final class SasVerifier {
  SasVerifier._(
    this.relayed,
    this.relayedUserId,
    this.commitment,
    this.issuedAtMs,
    this.verifierRandom,
  );

  /// Holds the server-relayed [relayed] key, [relayedUserId] and
  /// [commitment] (issued at [issuedAtMs], the server's timestamp on the
  /// commitment, ms since epoch — 04 §6.3's ten minutes run from it), and
  /// only then draws `r_V`.
  factory SasVerifier.begin(
    CryptoSuite suite, {
    required UmkPublic relayed,
    required String relayedUserId,
    required Uint8List commitment,
    required int issuedAtMs,
  }) {
    if (commitment.length != sasCommitmentBytes) {
      throw ArgumentError.value(
        commitment.length,
        'commitment',
        'SAS commitment is $sasCommitmentBytes bytes',
      );
    }
    return SasVerifier._(
      relayed,
      _checkedUserId(relayedUserId),
      Uint8List.fromList(commitment),
      issuedAtMs,
      suite.randomBytes(sasContributionBytes),
    );
  }

  /// Server-relayed UMK public halves of the person being verified.
  final UmkPublic relayed;

  /// The user id the server relayed.
  final String relayedUserId;

  /// The commitment the server relayed.
  final Uint8List commitment;

  /// Server timestamp of the commitment (ms since epoch).
  final int issuedAtMs;

  /// `r_V` — relayed to the shower. It exists only because [relayed] and
  /// [commitment] were in hand first.
  final Uint8List verifierRandom;

  bool _opened = false;

  /// True once [open] has run.
  bool get isOpened => _opened;

  /// Checks that [showerRandom] opens [commitment] under the *relayed* key
  /// and id (constant time) and hands back the challenge. Exactly once: a
  /// second call throws [StateError].
  SasOpenResult open(CryptoSuite suite, Uint8List showerRandom) {
    if (_opened) {
      throw StateError(
        'SasVerifier.open called twice: one opening per session',
      );
    }
    final rS = _checkedContribution(showerRandom, 'showerRandom');
    _opened = true;
    final fp = Fingerprint.of(suite, relayed);
    final expected = sasCommitment(
      suite,
      fp: fp,
      userId: relayedUserId,
      showerRandom: rS,
    );
    if (!suite.constantTimeEquals(expected, commitment)) {
      return const SasOpeningMismatch();
    }
    return SasOpened(
      SasChallenge._(
        relayed,
        fp,
        relayedUserId,
        rS,
        Uint8List.fromList(verifierRandom),
        issuedAtMs,
        0,
        false,
      ),
    );
  }
}

/// Attempt state of one SAS session on the verifier's device. 04 §6.3's
/// rules are unchanged — [codeMaxAttempts] wrong tries kill the session, it
/// expires [codeNonceLifetimeMs] after the commitment's server timestamp,
/// success retires it — and the shape mirrors [CodeChallenge]: immutable,
/// each [attempt] returns its successor beside the result, no clock inside.
@immutable
final class SasChallenge {
  const SasChallenge._(
    this.relayed,
    this._fp,
    this.userId,
    this._rS,
    this._rV,
    this.issuedAtMs,
    this.attemptsUsed,
    this.dead,
  );

  /// Server-relayed UMK public halves — what a match verifies.
  final UmkPublic relayed;

  final Fingerprint _fp;

  /// The user id the server relayed.
  final String userId;

  final Uint8List _rS;
  final Uint8List _rV;

  /// Server timestamp of the commitment (ms since epoch).
  final int issuedAtMs;

  /// Wrong attempts consumed so far.
  final int attemptsUsed;

  /// True once the session can never verify again (exhausted or consumed).
  final bool dead;

  /// Attempts still available.
  int get attemptsLeft => dead ? 0 : codeMaxAttempts - attemptsUsed;

  /// True when [nowMs] is past the session's lifetime — same boundary as
  /// [CodeChallenge.isExpiredAt].
  bool isExpiredAt(int nowMs) => nowMs - issuedAtMs > codeNonceLifetimeMs;

  SasChallenge _next(int used, bool isDead) =>
      SasChallenge._(relayed, _fp, userId, _rS, _rV, issuedAtMs, used, isDead);

  /// Checks [typed] against `sasCode(FP_relayed, user_id, r_S, r_V)`. Order:
  /// dead → expired → compare (constant time). Whitespace read aloud in
  /// pairs is tolerated; a malformed entry is a wrong attempt; the third
  /// wrong attempt kills the session; success also retires it.
  ({SasChallenge next, CeremonyResult result}) attempt(
    CryptoSuite suite, {
    required String typed,
    required int nowMs,
  }) {
    if (dead) return (next: this, result: const CodeExhausted());
    if (isExpiredAt(nowMs)) return (next: this, result: const CodeExpired());

    final expected = sasCode(
      suite,
      fp: _fp,
      userId: userId,
      showerRandom: _rS,
      verifierRandom: _rV,
    );
    final cleaned = typed.replaceAll(RegExp(r'\s'), '');
    final ok = suite.constantTimeEquals(
      Uint8List.fromList(utf8.encode(expected)),
      Uint8List.fromList(utf8.encode(cleaned)),
    );
    if (ok) {
      return (
        next: _next(attemptsUsed, true),
        result: CeremonyVerified(
          VerifiedUmkPublic.internal(
            relayed,
            _fp,
            VerificationMethod.codeRemote,
          ),
        ),
      );
    }
    final used = attemptsUsed + 1;
    if (used >= codeMaxAttempts) {
      return (next: _next(used, true), result: const CodeExhausted());
    }
    return (
      next: _next(used, false),
      result: CodeWrong(attemptsLeft: codeMaxAttempts - used),
    );
  }
}
