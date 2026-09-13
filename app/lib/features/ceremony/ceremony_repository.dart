// The ceremony feature's seam over `core_crypto` (04 §6) and the server relay.
//
// Nothing here derives a key, a code or a QR payload by hand: the 8 digits and
// the QR bytes come out of `core_crypto`'s `verificationCode` / `QrPayload`
// (04 §6.1), the comparison out of `Ceremony.verifyQr` / `CodeChallenge`
// (04 §6.3). The screens see only [MyCode] and core_crypto's sealed
// [CeremonyResult], so no widget can invent an outcome — and no widget can
// produce a [VerifiedUmkPublic], which is what keeps 04 §8.2 🔒 structural
// ("no book key is wrapped to an unverified fingerprint"): only the ceremony
// module mints that type, and only on a match.
//
// ⚠️ WIRE — the nonce comes from the server at invite creation and the keys
// being compared are *server-relayed* (04 §6.1, §6.3). Those two calls are
// [InviteNonceSource] and the `relayed…` constructor arguments; the sync/server
// lane supplies them. The crypto half below is real today.
import 'dart:async';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';

export 'package:core_crypto/core_crypto.dart'
    show
        CeremonyMismatch,
        CeremonyResult,
        CeremonyVerified,
        CodeExhausted,
        CodeExpired,
        CodeWrong,
        codeMaxAttempts,
        codeNonceLifetimeMs;

/// A per-invite nonce as the server issued it (04 §6.1) — 16 bytes, not
/// secret, and the moment it was issued, which is what makes the countdown
/// on S9.2 honest rather than a guess.
@immutable
final class InviteNonce {
  /// Wraps [bytes] issued at [issuedAt].
  InviteNonce({required Uint8List bytes, required this.issuedAt})
    : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != ceremonyNonceBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'invite nonce is $ceremonyNonceBytes bytes (04 §6.1)',
      );
    }
  }

  /// The nonce bytes.
  final Uint8List bytes;

  /// When the server issued it.
  final DateTime issuedAt;

  /// The moment the nonce dies (04 §6.3: ten minutes).
  DateTime get expiresAt =>
      issuedAt.add(const Duration(milliseconds: codeNonceLifetimeMs));
}

/// Where a nonce comes from. `fresh: true` is *Regenerate* (04 §6.3).
typedef InviteNonceSource = Future<InviteNonce> Function({bool fresh});

/// What S9.2 renders. Both halves are *derived* (04 §6.1) — never typed,
/// never chosen, never a password.
@immutable
final class MyCode {
  /// Wraps a derived pair.
  MyCode({
    required this.qrPayload,
    required this.digits,
    required this.expiresAt,
  }) {
    if (digits.length != 8) {
      throw ArgumentError.value(digits, 'digits', 'the code is 8 digits');
    }
  }

  /// `base64url( suite ‖ user_id ‖ ed ‖ x ‖ nonce )` — the QR's content.
  final String qrPayload;

  /// The eight digits printed beneath it.
  final String digits;

  /// When this code stops working.
  final DateTime expiresAt;
}

/// A ceremony call that failed before any comparison happened. Never a
/// verification outcome: a failure here says *we could not ask*, which is a
/// retry, not a mismatch.
final class CeremonyFailure implements Exception {
  /// [offline] separates "no connection" from "something broke".
  const CeremonyFailure({this.offline = false, this.message = ''});

  /// True when the device has no connection.
  final bool offline;

  /// Diagnostic text — never rendered raw (07 §1 rule 12).
  final String message;

  @override
  String toString() => 'CeremonyFailure(offline: $offline, $message)';
}

/// What the scanned text was, before anything is compared. A stranger's QR is
/// **not** a mismatch: 04 §6.3's hard fail is for a real ceremony payload
/// whose keys differ, and a false entry in the permanent log (04 §6.4) is a
/// real cost. Kept out of [CeremonyResult] for exactly that reason.
final class NotACeremonyCode implements Exception {
  /// Creates the outcome.
  const NotACeremonyCode();

  @override
  String toString() => 'NotACeremonyCode()';
}

// ---------------------------------------------------------------------------
// S9.2 Show my code
// ---------------------------------------------------------------------------

/// The invitee's side (04 §6.2).
abstract class ShowMyCodeRepository {
  /// The code for the invite's current nonce.
  Future<MyCode> load();

  /// *Regenerate* — a fresh nonce from the server (04 §6.3).
  Future<MyCode> regenerate();
}

/// The real one: derives both halves through `core_crypto`.
final class CryptoShowMyCodeRepository implements ShowMyCodeRepository {
  /// [umk] is this device's own UMK public pair; [nonces] reaches the server.
  const CryptoShowMyCodeRepository({
    required this.suite,
    required this.userId,
    required this.umk,
    required this.nonces,
  });

  /// Injected libsodium suite (CLAUDE.md rule 7).
  final CryptoSuite suite;

  /// This device's user id, as it goes into the QR payload (04 §6.1).
  final String userId;

  /// This device's UMK public halves.
  final UmkPublic umk;

  /// Where the invite nonce comes from.
  final InviteNonceSource nonces;

  @override
  Future<MyCode> load() async => _derive(await nonces());

  @override
  Future<MyCode> regenerate() async => _derive(await nonces(fresh: true));

  MyCode _derive(InviteNonce nonce) => MyCode(
    qrPayload: QrPayload(userId: userId, umk: umk, nonce: nonce.bytes).encode(),
    digits: verificationCode(suite, Fingerprint.of(suite, umk), nonce.bytes),
    expiresAt: nonce.expiresAt,
  );
}

// ---------------------------------------------------------------------------
// S9.3 Verify member
// ---------------------------------------------------------------------------

/// How the verification was arranged (04 §6.4). Remote is an admin toggle per
/// invite; the screen changes its instruction, never its checks.
enum CeremonyMode {
  /// Default: QR, in person.
  inPerson,

  /// Verifier is on a voice or video call with the person.
  remote,
}

/// The verifier's side (04 §6.2, §6.3).
abstract class VerifyMemberRepository {
  /// In person or remote (04 §6.4).
  CeremonyMode get mode;

  /// Whether this member may run the ceremony at all — delegated verification
  /// is open to any *already-verified, active* member (04 §6.4, 13 §2.3.1).
  bool get canVerify;

  /// The person being verified. User-typed: render it with its own `lang`.
  String get memberName;

  /// QR path. Throws [NotACeremonyCode] when the camera read something else,
  /// [CeremonyFailure] when the relayed keys could not be fetched.
  Future<CeremonyResult> verifyScanned(String scanned);

  /// Code path — 3 attempts per nonce, 10-minute lifetime (04 §6.3).
  Future<CeremonyResult> verifyTyped(String digits);

  /// How many `verification_mismatch` events this repository has written
  /// (04 §6.3). Read by S9.4's test; the screen never writes one itself.
  int get mismatchesLogged;
}

/// Records a `verification_mismatch` security event (04 §6.3) and, on a match,
/// the permanent verification entry (04 §6.4: who verified whom, method,
/// timestamp). Injected so the app layer holds no logging policy.
abstract class CeremonyEventLog {
  /// A real ceremony payload whose keys did not match.
  Future<void> mismatch({required String memberName});

  /// A completed verification.
  Future<void> verified({
    required String memberName,
    required VerificationMethod method,
  });
}

/// The real verifier: every check is `core_crypto`'s.
final class CryptoVerifyMemberRepository implements VerifyMemberRepository {
  /// [relayedUmk] / [relayedUserId] are what the *server* holds for the person
  /// (04 §6.3) — never what the QR said. [nonce] is the invite nonce and
  /// [now] the injected clock.
  CryptoVerifyMemberRepository({
    required this.suite,
    required this.relayedUmk,
    required this.relayedUserId,
    required InviteNonce nonce,
    required this.memberName,
    required this.now,
    required this.log,
    this.mode = CeremonyMode.inPerson,
    this.canVerify = true,
  }) : _challenge = CodeChallenge(
         relayed: relayedUmk,
         nonce: nonce.bytes,
         issuedAtMs: nonce.issuedAt.millisecondsSinceEpoch,
       );

  /// Injected libsodium suite (CLAUDE.md rule 7).
  final CryptoSuite suite;

  /// The UMK public halves the *server* relayed for this person (04 §6.3).
  final UmkPublic relayedUmk;

  /// The user id the server relayed.
  final String relayedUserId;

  /// Injected clock — the nonce's ten minutes are measured against it.
  final DateTime Function() now;

  /// Where the security event and the permanent entry go (04 §6.3, §6.4).
  final CeremonyEventLog log;

  CodeChallenge _challenge;

  @override
  final CeremonyMode mode;

  @override
  final bool canVerify;

  @override
  final String memberName;

  @override
  int mismatchesLogged = 0;

  @override
  Future<CeremonyResult> verifyScanned(String scanned) async {
    final QrPayload payload;
    try {
      payload = QrPayload.decode(scanned);
    } on FormatException {
      throw const NotACeremonyCode();
    }
    final result = Ceremony.verifyQr(
      suite,
      scanned: payload,
      relayed: relayedUmk,
      relayedUserId: relayedUserId,
    );
    return _record(result, VerificationMethod.qrInPerson);
  }

  @override
  Future<CeremonyResult> verifyTyped(String digits) async {
    final step = _challenge.attempt(
      suite,
      typed: digits,
      nowMs: now().millisecondsSinceEpoch,
    );
    _challenge = step.next;
    return _record(step.result, VerificationMethod.codeRemote);
  }

  Future<CeremonyResult> _record(
    CeremonyResult result,
    VerificationMethod method,
  ) async {
    switch (result) {
      case CeremonyMismatch():
        mismatchesLogged++;
        await log.mismatch(memberName: memberName);
      case CeremonyVerified():
        await log.verified(memberName: memberName, method: method);
      case CodeWrong() || CodeExpired() || CodeExhausted():
        break;
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Fakes — the seam's other half (features/README "Dependencies").
// ---------------------------------------------------------------------------

/// A scripted S9.2 side. Note what it *cannot* do: there is no way to hand a
/// widget a code it did not derive from a nonce, because [MyCode] is the only
/// shape the screen accepts and its digits are checked for length.
final class FakeShowMyCodeRepository implements ShowMyCodeRepository {
  /// [code] is what [load] returns; [next] is what [regenerate] returns
  /// (defaulting to [code]); [failure] makes both throw.
  FakeShowMyCodeRepository({required this.code, this.next, this.failure});

  /// The current code.
  MyCode code;

  /// What *Regenerate* produces.
  MyCode? next;

  /// Non-null makes every call fail — the error / offline states.
  CeremonyFailure? failure;

  /// How many times [load] ran.
  int loads = 0;

  /// How many times [regenerate] ran.
  int regenerations = 0;

  @override
  Future<MyCode> load() async {
    loads++;
    final f = failure;
    if (f != null) throw f;
    return code;
  }

  @override
  Future<MyCode> regenerate() async {
    regenerations++;
    final f = failure;
    if (f != null) throw f;
    return code = next ?? code;
  }
}

/// A scripted S9.3 side.
///
/// It can produce every *failing* outcome — that is what a screen has to
/// render. It cannot produce [CeremonyVerified], because only `core_crypto`
/// mints the [VerifiedUmkPublic] inside it (04 §8.2 🔒): a test that wants a
/// success must run the real [CryptoVerifyMemberRepository] over keys that
/// actually match, which is exactly the property worth protecting.
final class FakeVerifyMemberRepository implements VerifyMemberRepository {
  /// [onScanned] / [onTyped] decide each call's outcome; either may throw
  /// [NotACeremonyCode] or [CeremonyFailure].
  FakeVerifyMemberRepository({
    this.mode = CeremonyMode.inPerson,
    this.canVerify = true,
    this.memberName = 'Sunita',
    Future<CeremonyResult> Function(String scanned)? onScanned,
    Future<CeremonyResult> Function(String typed)? onTyped,
  }) : _onScanned = onScanned ?? _mismatch,
       _onTyped = onTyped ?? _mismatch;

  static Future<CeremonyResult> _mismatch(String _) async =>
      const CeremonyMismatch();

  final Future<CeremonyResult> Function(String) _onScanned;
  final Future<CeremonyResult> Function(String) _onTyped;

  @override
  final CeremonyMode mode;

  @override
  final bool canVerify;

  @override
  final String memberName;

  @override
  int mismatchesLogged = 0;

  /// Every string [verifyScanned] was given.
  final List<String> scanned = [];

  /// Every string [verifyTyped] was given.
  final List<String> typed = [];

  @override
  Future<CeremonyResult> verifyScanned(String text) async {
    scanned.add(text);
    return _record(await _onScanned(text));
  }

  @override
  Future<CeremonyResult> verifyTyped(String digits) async {
    typed.add(digits);
    return _record(await _onTyped(digits));
  }

  CeremonyResult _record(CeremonyResult result) {
    if (result is CeremonyMismatch) mismatchesLogged++;
    return result;
  }
}

/// Collects what would have gone to the security log (04 §6.3, §6.4).
final class RecordingCeremonyEventLog implements CeremonyEventLog {
  /// Creates an empty log.
  RecordingCeremonyEventLog();

  /// Names passed to [mismatch], in order.
  final List<String> mismatches = [];

  /// `(name, method)` pairs passed to [verified], in order.
  final List<(String, VerificationMethod)> verifications = [];

  @override
  Future<void> mismatch({required String memberName}) async =>
      mismatches.add(memberName);

  @override
  Future<void> verified({
    required String memberName,
    required VerificationMethod method,
  }) async => verifications.add((memberName, method));
}
