// The ceremony feature's seam over `core_crypto` (04 §6) and the server relay.
//
// Nothing here derives a key, a code or a QR payload by hand: the QR bytes come
// out of `core_crypto`'s [QrPayload] (04 §6.1), the eight digits out of its
// [SasShower] / [SasChallenge], and the comparisons out of [Ceremony.verifyQr]
// and [SasVerifier]. The screens see only [MyCode] and core_crypto's sealed
// [CeremonyResult], so no widget can invent an outcome — and no widget can
// produce a [VerifiedUmkPublic], which is what keeps 04 §8.2 🔒 structural
// ("no book key is wrapped to an unverified fingerprint"): only the ceremony
// module mints that type, and only on a match.
//
// 🔒 **The code path is a commitment-based SAS** (04 §6.1, §6.3 as amended by
// ADR 2026-09-13d, ratified 13 Sep 2026). It is not the 04 §6.1 `verify-v1`
// derivation this feature shipped on the morning of 13 Sep: that code was a
// function of a fingerprint the server holds and a nonce the server issues, so
// a relay that substitutes the invitee's key pre-computes a colliding pair in
// ~2·10⁴ hashes and the ghost verifies on the *first* attempt, rate limits
// never engaged (B-04-87). The repair is structural, and it lives in the order
// of three relayed values:
//
//   1. the invitee's device draws `r_S`, relays only `commitment(FP, id, r_S)`;
//   2. the verifier's device draws `r_V` **only once it holds the relayed key
//      and that commitment**, and relays `r_V`;
//   3. the invitee's device reveals `r_S` — once — and both sides derive the
//      same eight digits from `(FP, id, r_S, r_V)`.
//
// Every value a relay could tune is therefore fixed before the value it would
// have to be tuned against exists (B-04-88). Two consequences reach the
// screens, and both are 🔒: the digits **do not exist** on S9.2 until the
// verifier has begun (so S9.2 waits), and the verifier's device **never
// displays the code it expects** (so typing stays a real check) —
// ADR 2026-09-13d §5.
//
// The QR path is untouched: [Ceremony.verifyQr] compares the 64 public-key
// bytes and the user id from the *scanned* payload and never reads the nonce,
// so it was never exposed to this (ADR 2026-09-13d §2).
//
// ⚠️ WIRE — the three SAS values travel through the server's ceremony-session
// record (ADR 2026-09-13d §4): opaque bytes it stores and forwards, computing
// nothing. That wire is the server lane's; here it is [ShowerSessionRelay] and
// [VerifierSessionRelay], with the keys still *server-relayed* through the
// `relayed…` constructor arguments. The crypto half below is real today.
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

/// A per-invite nonce as the server issued it (04 §6.1) — 16 bytes and not
/// secret.
///
/// Since ADR 2026-09-13d it **scopes the QR payload only**: no code is derived
/// from it any more, and the ten minutes of 04 §6.3 run from the server's
/// timestamp on the *commitment*, not from this. [issuedAt] is kept because
/// the invite row carries it, not because anything on screen counts from it.
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

  /// The nonce bytes, as they go into the QR payload.
  final Uint8List bytes;

  /// When the server issued it.
  final DateTime issuedAt;
}

/// Where a nonce comes from. `fresh: true` is *Regenerate* (04 §6.3).
typedef InviteNonceSource = Future<InviteNonce> Function({bool fresh});

/// What S9.2 renders — one ceremony session.
///
/// Both halves are *derived* (04 §6.1): never typed, never chosen, never a
/// password. [digits] is **null while the session is waiting**, because before
/// the verifier's `r_V` has arrived the eight digits do not exist — there is
/// nothing to hide and nothing to show (ADR 2026-09-13d §5 🔒). The QR is
/// there from the first frame either way.
@immutable
final class MyCode {
  /// Wraps a derived session. [digits] null is the waiting state.
  MyCode({
    required this.qrPayload,
    required this.digits,
    required this.expiresAt,
  }) {
    final d = digits;
    // Eight, per 04 §6.1 🔒 — unchanged by ADR 2026-09-13d, which is the point
    // of choosing the SAS over its § 4 sixteen-digit alternative.
    if (d != null && d.length != 8) {
      throw ArgumentError.value(d, 'digits', 'the code is 8 digits');
    }
  }

  /// `base64url( suite ‖ user_id ‖ ed ‖ x ‖ nonce )` — the QR's content.
  final String qrPayload;

  /// The eight digits printed beneath the square, or null while the session
  /// waits for the verifier to begin.
  final String? digits;

  /// When this session stops working — ten minutes from the **server's**
  /// timestamp on the commitment (04 §6.3, ADR 2026-09-13d §3).
  final DateTime expiresAt;

  /// True while `r_V` has not arrived: the boxes are empty and the screen says
  /// who it is waiting for.
  bool get isWaiting => digits == null;
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
// The relay — ADR 2026-09-13d §4, the server lane's wire
// ---------------------------------------------------------------------------

/// The invitee device's half of the ceremony-session relay.
///
/// Three opaque values per session; the server stores and forwards them and
/// computes nothing (04 §8.6 holds). Ordering is the security property, so it
/// is the interface: [open] before [verifierRandom], [verifierRandom] before
/// [reveal] — the opening never leaves the phone until the other side's
/// contribution is in hand.
abstract class ShowerSessionRelay {
  /// Opens a session by writing [commitment] (32 bytes) and returns the
  /// **server's** timestamp on it — 04 §6.3's ten minutes run from that, not
  /// from this phone's clock, so the two devices agree on when the code dies.
  Future<DateTime> open(Uint8List commitment);

  /// Resolves with the verifier's 16-byte `r_V`, once an already-verified
  /// active member's device has written it (04 §6.4 *delegated*). A relay that
  /// simply never answers is denial of service, accepted in 04 §1.2 bullet 1 —
  /// the screen shows the countdown running out, never a verified state.
  Future<Uint8List> verifierRandom();

  /// Writes the opening `r_S` for the verifier's device to check against the
  /// commitment.
  Future<void> reveal(Uint8List opening);
}

/// A commitment as the server relayed it, with the timestamp the lifetime runs
/// from (04 §6.3, ADR 2026-09-13d §3).
@immutable
final class RelayedCommitment {
  /// Wraps [bytes] as written at [issuedAt].
  RelayedCommitment({required Uint8List bytes, required this.issuedAt})
    : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != sasCommitmentBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'a SAS commitment is $sasCommitmentBytes bytes',
      );
    }
  }

  /// The 32 committed bytes.
  final Uint8List bytes;

  /// The server's timestamp on the commitment.
  final DateTime issuedAt;
}

/// The verifier device's half of the relay.
///
/// Again ordering is the interface: [commitment] must resolve before this
/// device draws `r_V`, which it [contribute]s before the invitee's [opening]
/// can be asked for. [SasVerifier.begin] enforces the same order structurally.
abstract class VerifierSessionRelay {
  /// The commitment the invitee's device wrote, with its server timestamp.
  Future<RelayedCommitment> commitment();

  /// Writes this device's 16-byte `r_V` to the session.
  Future<void> contribute(Uint8List verifierRandom);

  /// Resolves with the invitee's opening `r_S`.
  Future<Uint8List> opening();
}

// ---------------------------------------------------------------------------
// S9.2 Show my code
// ---------------------------------------------------------------------------

/// The invitee's side (04 §6.2).
abstract class ShowMyCodeRepository {
  /// Who is verifying — the person the invitee was told to meet (07 §12).
  /// S9.2's waiting state names them rather than saying "someone".
  String get verifierName;

  /// Opens a session: draws `r_S`, relays the commitment. The QR is ready at
  /// once; the returned [MyCode] is waiting, because the digits cannot exist
  /// before the verifier has begun.
  Future<MyCode> load();

  /// *Regenerate* — a fresh session, a fresh `r_S` (04 §6.3). Never a second
  /// code under the same commitment: that would hand a relay which has just
  /// learned `r_S` a new code to search against (ADR 2026-09-13d §2).
  Future<MyCode> regenerate();

  /// Completes when the verifier's `r_V` has been relayed: this device then
  /// reveals `r_S` once and the eight digits exist. Awaits the session opened
  /// by the most recent [load] or [regenerate].
  Future<MyCode> awaitVerifier();
}

/// The real one: every value through `core_crypto`, nothing derived here.
final class CryptoShowMyCodeRepository implements ShowMyCodeRepository {
  /// [umk] is this device's own UMK public pair; [nonces] supplies the invite
  /// nonce that scopes the QR payload; [relay] is the ceremony session.
  CryptoShowMyCodeRepository({
    required this.suite,
    required this.userId,
    required this.umk,
    required this.nonces,
    required this.relay,
    required this.verifierName,
  });

  /// Injected libsodium suite (CLAUDE.md rule 7).
  final CryptoSuite suite;

  /// This device's user id, as it goes into the QR payload and the commitment.
  final String userId;

  /// This device's UMK public halves.
  final UmkPublic umk;

  /// Where the invite nonce comes from (QR payload only, 04 §6.1).
  final InviteNonceSource nonces;

  /// The ceremony session on the server.
  final ShowerSessionRelay relay;

  @override
  final String verifierName;

  SasShower? _shower;
  InviteNonce? _nonce;
  DateTime? _expiresAt;
  MyCode? _opened;

  @override
  Future<MyCode> load() async => _open(await nonces());

  @override
  Future<MyCode> regenerate() async => _open(await nonces(fresh: true));

  Future<MyCode> _open(InviteNonce nonce) async {
    // A fresh `r_S` per session, drawn on this device from the suite's RNG —
    // the server never sees it and cannot choose it.
    final shower = SasShower.open(suite, userId: userId, umk: umk);
    final issuedAt = await relay.open(shower.commitment);
    _shower = shower;
    _nonce = nonce;
    _opened = null;
    _expiresAt = issuedAt.add(
      const Duration(milliseconds: codeNonceLifetimeMs),
    );
    return _waiting();
  }

  MyCode _waiting() => MyCode(
    qrPayload: QrPayload(
      userId: userId,
      umk: umk,
      nonce: _nonce!.bytes,
    ).encode(),
    digits: null,
    expiresAt: _expiresAt!,
  );

  @override
  Future<MyCode> awaitVerifier() async {
    final shower = _shower;
    if (shower == null) {
      throw StateError('awaitVerifier before load(): no session is open');
    }
    // One code per commitment (ADR 2026-09-13d §2). A second await on the same
    // session returns the code already shown rather than asking `SasShower` to
    // respond twice, which it refuses.
    final already = _opened;
    if (already != null) return already;
    final rV = await relay.verifierRandom();
    final response = shower.respond(suite, rV);
    await relay.reveal(response.opening);
    return _opened = MyCode(
      qrPayload: _waiting().qrPayload,
      digits: response.code,
      expiresAt: _expiresAt!,
    );
  }
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

/// What arming the code path produced (ADR 2026-09-13d §1 step 4).
enum CodePathArming {
  /// The relayed opening opened the relayed commitment under the relayed key
  /// and id: the eight boxes may now be typed into.
  armed,

  /// It did not — the relay lied about the key, the person or the opening.
  /// 04 §6.3's hard fail, handled exactly as a QR mismatch: off to S9.4, the
  /// `verification_mismatch` event already written, no override.
  mismatch,
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

  /// Arms the code path: holds the relayed key **and the relayed commitment**,
  /// only then draws `r_V`, relays it, and checks the opening that comes back
  /// (ADR 2026-09-13d §1 steps 2 and 4). Idempotent — a second call on an
  /// armed session re-uses it rather than drawing a second `r_V`. Throws
  /// [CeremonyFailure] when the relay could not be reached.
  Future<CodePathArming> armCodePath();

  /// Code path — 3 attempts per session, 10-minute lifetime from the
  /// commitment's server timestamp (04 §6.3). Only after [armCodePath] has
  /// returned [CodePathArming.armed].
  Future<CeremonyResult> verifyTyped(String digits);

  /// How many `verification_mismatch` events this repository has written
  /// (04 §6.3). Read by S9.4's test; the screen never writes one itself.
  int get mismatchesLogged;
}

/// Records a `verification_mismatch` security event (04 §6.3) and, on a match,
/// the permanent verification entry (04 §6.4: who verified whom, method,
/// timestamp). Injected so the app layer holds no logging policy.
abstract class CeremonyEventLog {
  /// A real ceremony payload whose keys did not match — or a SAS opening that
  /// did not open the relayed commitment (ADR 2026-09-13d §2).
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
  /// (04 §6.3) — never what the QR said. [relay] carries the ceremony session
  /// and [now] is the injected clock.
  CryptoVerifyMemberRepository({
    required this.suite,
    required this.relayedUmk,
    required this.relayedUserId,
    required this.relay,
    required this.memberName,
    required this.now,
    required this.log,
    this.mode = CeremonyMode.inPerson,
    this.canVerify = true,
  });

  /// Injected libsodium suite (CLAUDE.md rule 7).
  final CryptoSuite suite;

  /// The UMK public halves the *server* relayed for this person (04 §6.3).
  final UmkPublic relayedUmk;

  /// The user id the server relayed.
  final String relayedUserId;

  /// The ceremony session on the server.
  final VerifierSessionRelay relay;

  /// Injected clock — the session's ten minutes are measured against it.
  final DateTime Function() now;

  /// Where the security event and the permanent entry go (04 §6.3, §6.4).
  final CeremonyEventLog log;

  Future<CodePathArming>? _arming;
  SasChallenge? _challenge;

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
  Future<CodePathArming> armCodePath() => _arming ??= _arm();

  Future<CodePathArming> _arm() async {
    try {
      final relayed = await relay.commitment();
      // The order is the security property: `r_V` is drawn *inside* begin(),
      // which cannot run without the relayed key and the commitment in hand.
      final verifier = SasVerifier.begin(
        suite,
        relayed: relayedUmk,
        relayedUserId: relayedUserId,
        commitment: relayed.bytes,
        issuedAtMs: relayed.issuedAt.millisecondsSinceEpoch,
      );
      await relay.contribute(verifier.verifierRandom);
      final opening = await relay.opening();
      switch (verifier.open(suite, opening)) {
        case SasOpeningMismatch():
          mismatchesLogged++;
          await log.mismatch(memberName: memberName);
          return CodePathArming.mismatch;
        case SasOpened(:final challenge):
          _challenge = challenge;
          return CodePathArming.armed;
      }
    } on CeremonyFailure {
      // Nothing was compared, so nothing is logged and nothing is spent: let
      // the screen offer the retry over a clean session.
      _arming = null;
      rethrow;
    }
  }

  @override
  Future<CeremonyResult> verifyTyped(String digits) async {
    final challenge = _challenge;
    if (challenge == null) {
      throw StateError(
        'verifyTyped before armCodePath(): the verifier has no session, so '
        'there is no expected code (ADR 2026-09-13d §1)',
      );
    }
    final step = challenge.attempt(
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
/// widget a code it did not derive from a session, because [MyCode] is the
/// only shape the screen accepts and its digits are checked for length.
///
/// [waitForVerifier] is the ADR 2026-09-13d §5 state: with it set, [load]
/// returns the waiting session and [awaitVerifier] hangs until [arrive] is
/// called, which is exactly what the relay does when the verifier has not yet
/// tapped *Enter code instead*.
final class FakeShowMyCodeRepository implements ShowMyCodeRepository {
  /// [code] is what arrives once `r_V` has been relayed; [next] is what
  /// *Regenerate* produces (defaulting to [code]); [failure] makes every call
  /// fail.
  FakeShowMyCodeRepository({
    required this.code,
    this.next,
    this.failure,
    this.waitForVerifier = false,
    this.verifierName = 'Sunita',
  });

  /// The session as it looks once the verifier has begun.
  MyCode code;

  /// What *Regenerate* produces.
  MyCode? next;

  /// Non-null makes every call fail — the error / offline states.
  CeremonyFailure? failure;

  /// True holds [awaitVerifier] open until [arrive] is called.
  bool waitForVerifier;

  @override
  final String verifierName;

  /// How many times [load] ran.
  int loads = 0;

  /// How many times [regenerate] ran.
  int regenerations = 0;

  /// How many times [awaitVerifier] ran.
  int waits = 0;

  Completer<MyCode>? _verifier;

  /// The waiting face of [code]: same square, same countdown, no digits.
  MyCode get waiting => MyCode(
    qrPayload: code.qrPayload,
    digits: null,
    expiresAt: code.expiresAt,
  );

  /// The verifier's `r_V` lands: [awaitVerifier] completes with [code].
  void arrive() {
    final completer = _verifier;
    if (completer == null || completer.isCompleted) return;
    completer.complete(code);
  }

  /// The relay fails while waiting.
  void failWaiting(CeremonyFailure error) {
    final completer = _verifier;
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  @override
  Future<MyCode> load() async {
    loads++;
    return _start();
  }

  @override
  Future<MyCode> regenerate() async {
    regenerations++;
    code = next ?? code;
    return _start();
  }

  MyCode _start() {
    final f = failure;
    if (f != null) throw f;
    _verifier = Completer<MyCode>();
    return waiting;
  }

  @override
  Future<MyCode> awaitVerifier() {
    waits++;
    final f = failure;
    if (f != null) return Future<MyCode>.error(f);
    final completer = _verifier ??= Completer<MyCode>();
    if (!waitForVerifier && !completer.isCompleted) completer.complete(code);
    return completer.future;
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
  /// [NotACeremonyCode] or [CeremonyFailure]. [onArm] decides what arming the
  /// code path does — [CodePathArming.armed] unless a test says otherwise.
  FakeVerifyMemberRepository({
    this.mode = CeremonyMode.inPerson,
    this.canVerify = true,
    this.memberName = 'Sunita',
    Future<CeremonyResult> Function(String scanned)? onScanned,
    Future<CeremonyResult> Function(String typed)? onTyped,
    Future<CodePathArming> Function()? onArm,
  }) : _onScanned = onScanned ?? _mismatch,
       _onTyped = onTyped ?? _mismatch,
       _onArm = onArm ?? _armed;

  static Future<CeremonyResult> _mismatch(String _) async =>
      const CeremonyMismatch();

  static Future<CodePathArming> _armed() async => CodePathArming.armed;

  final Future<CeremonyResult> Function(String) _onScanned;
  final Future<CeremonyResult> Function(String) _onTyped;
  final Future<CodePathArming> Function() _onArm;

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

  /// How many times the code path was armed — the screen must not draw a
  /// second `r_V` for one session (ADR 2026-09-13d §2).
  int arms = 0;

  @override
  Future<CeremonyResult> verifyScanned(String text) async {
    scanned.add(text);
    return _record(await _onScanned(text));
  }

  @override
  Future<CodePathArming> armCodePath() async {
    arms++;
    final result = await _onArm();
    if (result == CodePathArming.mismatch) mismatchesLogged++;
    return result;
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

/// A scripted [ShowerSessionRelay] — the invitee's half of the wire, with the
/// verifier's contribution under the test's control.
final class FakeShowerSessionRelay implements ShowerSessionRelay {
  /// [issuedAt] is the server's timestamp on the commitment; [verifier] is the
  /// `r_V` that comes back, delivered at once unless [hold] is set.
  FakeShowerSessionRelay({
    required this.issuedAt,
    required Uint8List verifier,
    this.hold = false,
  }) : verifier = Uint8List.fromList(verifier);

  /// Server timestamp returned by [open].
  final DateTime issuedAt;

  /// The verifier's `r_V`.
  final Uint8List verifier;

  /// True holds [verifierRandom] open until [arrive].
  bool hold;

  /// Commitments written, in order.
  final List<Uint8List> commitments = [];

  /// Openings written, in order.
  final List<Uint8List> openings = [];

  Completer<Uint8List>? _waiting;

  /// Releases a held [verifierRandom].
  void arrive() {
    final completer = _waiting;
    if (completer != null && !completer.isCompleted) {
      completer.complete(verifier);
    }
  }

  @override
  Future<DateTime> open(Uint8List commitment) async {
    commitments.add(Uint8List.fromList(commitment));
    return issuedAt;
  }

  @override
  Future<Uint8List> verifierRandom() {
    if (!hold) return Future.value(verifier);
    return (_waiting ??= Completer<Uint8List>()).future;
  }

  @override
  Future<void> reveal(Uint8List opening) async =>
      openings.add(Uint8List.fromList(opening));
}

/// A scripted [VerifierSessionRelay] — the verifier's half of the wire.
///
/// A test that wants the ghost-member case simply hands [opening] bytes that
/// do not open [commitmentBytes] under the relayed key: the repository must
/// answer [CodePathArming.mismatch], never let the typing begin.
final class FakeVerifierSessionRelay implements VerifierSessionRelay {
  /// [commitmentBytes] and [opening] are what the server relays.
  FakeVerifierSessionRelay({
    required Uint8List commitmentBytes,
    required Uint8List openingBytes,
    required this.issuedAt,
  }) : commitmentBytes = Uint8List.fromList(commitmentBytes),
       openingBytes = Uint8List.fromList(openingBytes);

  /// The relayed commitment.
  final Uint8List commitmentBytes;

  /// The relayed opening.
  final Uint8List openingBytes;

  /// The server's timestamp on the commitment.
  final DateTime issuedAt;

  /// Every `r_V` this device wrote — exactly one per session.
  final List<Uint8List> contributions = [];

  @override
  Future<RelayedCommitment> commitment() async =>
      RelayedCommitment(bytes: commitmentBytes, issuedAt: issuedAt);

  @override
  Future<void> contribute(Uint8List verifierRandom) async =>
      contributions.add(Uint8List.fromList(verifierRandom));

  @override
  Future<Uint8List> opening() async => openingBytes;
}
