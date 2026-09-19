// The live producers behind the recovery-ladder seams (04 §7.3 🔒, 06 §5,
// 13 §5 flow F11) — S11.2, S11.3 and S11.7 against the real 0010 routes.
//
// `shared/seams/recovery_ladder.dart` declares what the screens consume and
// is **settled**: 53 widget tests run on its fakes and nothing here changes a
// line of it. This file implements those interfaces over
// `recovery_api.dart`, and the whole of its job is to be the place where the
// server's answers are *carried*, not re-decided.
//
// ============================================================================
// THE TWO RULES THIS FILE EXISTS TO HOLD
// ============================================================================
//
// **1. The ladder is the server's, not this phone's.** ADR 2026-09-05d §1 🔒
// delays completion 24 h whenever the user still holds an active certified
// device, and 0010 measures that from the k-th approval inside
// `rf.recovery_derive` (E-06-56). So [recoveryStateOf] reads `state` as a
// word and maps it; nothing in this file compares `wait_until`, `expires_at`
// or `kth_approval_at` with a clock, and there is no clock here to compare
// them with. A phone whose owner moved it forward a day learns nothing. An
// unrecognised state maps to [RecoveryAttemptState.pending] — *keep waiting*
// — because the one direction a mapping may never fail in is toward
// `approved`.
//
// **2. Progress is derived from rows, and a row names a person.** 0010's
// decision 🔒 makes every guardian decision its own append-only row so the
// requester's screen can say *which* trusted members approved. This adapter
// therefore attributes an approval **only** to the guardian a decision row
// names. `progressToWire` does not send those rows yet (see
// [RecoveryDecisionWire]'s ⚠️ SPEC), and the answer to that is not to guess:
// marking "the first `approvals` members" would put a tick beside somebody
// who has not acted, on a screen whose entire job is to say who has. Until
// the route names them every roster row reads *waiting*, which under-reports
// and never misattributes.
//
// Nothing here holds key material. Reconstructing `UMK_priv` from k shares,
// opening this guardian's own sealed share and re-sealing it to a candidate
// key are all `core_crypto`'s, reached through the injected [RecoveryResealer]
// — so no share, no UMK and no private key is ever a field of this file
// (04 §7.4, 07 §5.6 🔒).
import 'dart:async';
import 'dart:typed_data';

import '../seams/recovery_ladder.dart';
import 'recovery_api.dart';

export 'recovery_api.dart';

/// The fresh phone an attempt is for, as much of it as ever leaves this file.
///
/// A device id and a 32-byte public key: what ADR 2026-09-13c §3 🔒 has the
/// guardian's phone compare against the `DeviceQrPayload` it scans, and what
/// its share is re-sealed to. Nothing secret, and nothing financial.
final class RecoveryCandidate {
  /// Creates the reference.
  const RecoveryCandidate({
    required this.requestId,
    required this.deviceId,
    required this.candidatePubX,
  });

  /// The attempt this candidate belongs to.
  final String requestId;

  /// The fresh phone's device id.
  final String deviceId;

  /// Its candidate X25519 public key — 32 opaque bytes.
  final Uint8List candidatePubX;
}

/// Opens the camera, compares what it read with [candidate], and answers.
///
/// The payload never comes back: only the outcome, which is what keeps
/// "no key material reaches a widget" a property of the contract. Supplied by
/// the composition root, because the comparison is `core_crypto`'s
/// (`Ceremony.verifyDeviceQr`) and the camera is the platform's.
typedef RecoveryScanner = Future<RecoveryScanOutcome> Function(
  RecoveryCandidate candidate,
);

/// Opens *this guardian's own* sealed share and re-seals it to the candidate
/// key (04 §7.3 step 3). Returns the sealed bytes, which this file forwards
/// and never inspects.
typedef RecoveryResealer = Future<Uint8List> Function(
  RecoveryCandidate candidate,
);

/// Mints and persists the candidate X25519 pair of 04 §7.3 step 1, returning
/// its public half.
///
/// ⚠️ SPEC: 04 §7.3 step 1 reads "generates fresh device keys **+** a
/// *candidate* X25519 pair", which is two pairs, not one. Reusing this
/// device's own `pub_x` would be the convenient reading and it is not taken
/// here: minting and persisting a second pair is `core_crypto`/`features/
/// devices` behaviour, so this is an injected producer and the composition
/// root passes null until one exists. With none, [HttpGuardianRecovery]
/// re-reads an attempt that is already open and refuses plainly rather than
/// inventing a key. Reported as an open item.
typedef RecoveryCandidateKeySource = Future<Uint8List> Function();

/// Maps the server's derived `state` onto the seam's enum.
///
/// The server's word, taken verbatim — never recomputed from `wait_until` or
/// `expires_at` against a local clock (ADR 2026-09-05d §1 🔒, E-06-56). An
/// unknown word reads as [RecoveryAttemptState.pending]: the screen keeps
/// waiting, which is the one safe way to be wrong.
RecoveryAttemptState recoveryStateOf(String state) => switch (state) {
  'pending' => RecoveryAttemptState.pending,
  'waiting_24h' => RecoveryAttemptState.waiting24h,
  'approved' => RecoveryAttemptState.approved,
  // 03 §2.2 has no `denied`, so three denials and 72 h are the same word here
  // and S11.2's copy may not claim it was refused (the seam says so too).
  'expired' => RecoveryAttemptState.expired,
  'cancelled' => RecoveryAttemptState.cancelled,
  _ => RecoveryAttemptState.pending,
};

/// [GuardianRecovery] over the 0010 routes — S11.2's live producer.
///
/// It polls, because the attempt changes on other people's phones and this
/// one has no push seam yet. The tick is **injected** ([ticker]) rather than
/// taken from `Timer.periodic` here, so a widget test drives it by adding to
/// a controller and no test has to wait a real second. Polling stops the
/// moment the attempt reaches a state that cannot change again — approved,
/// expired or cancelled — so a closed attempt is not a battery drain and not
/// a slow flood of the route ADR 2026-09-05b §7 rate-limits.
final class HttpGuardianRecovery implements GuardianRecovery {
  /// Creates the producer.
  ///
  /// [roster] answers with the trusted members of the pinned share set, in
  /// the order S11.2 draws them, each in its resting state; [candidateKey]
  /// opens a *new* attempt when none is live, and null means this build can
  /// only re-read one that already exists.
  HttpGuardianRecovery({
    required RecoveryApi api,
    required Future<List<TrustedApprover>> Function() roster,
    RecoveryCandidateKeySource? candidateKey,
    RecoveryScanner? scanner,
    Stream<void> Function(Duration)? ticker,
    this.pollEvery = const Duration(seconds: 20),
  }) : _api = api,
       _roster = roster,
       _candidateKey = candidateKey,
       _scanner = scanner,
       _ticker = ticker ?? _realTicker;

  static Stream<void> _realTicker(Duration every) =>
      Stream<void>.periodic(every, (_) {});

  final RecoveryApi _api;
  final Future<List<TrustedApprover>> Function() _roster;
  final RecoveryCandidateKeySource? _candidateKey;
  final RecoveryScanner? _scanner;
  final Stream<void> Function(Duration) _ticker;

  /// How often the attempt is re-read while it can still change.
  final Duration pollEvery;

  GuardianRecoveryAttempt? _current;
  RecoveryCandidate? _candidate;
  StreamSubscription<void>? _tick;
  late final StreamController<GuardianRecoveryAttempt> _out =
      StreamController<GuardianRecoveryAttempt>.broadcast(
        onListen: _startPolling,
        onCancel: _stopPolling,
      );

  @override
  GuardianRecoveryAttempt? get current => _current;

  @override
  Stream<GuardianRecoveryAttempt> watch() => _out.stream;

  /// The candidate of the attempt in hand, for the ceremony. Null until one
  /// has been read.
  RecoveryCandidate? get candidate => _candidate;

  @override
  Future<void> refresh() async {
    try {
      final request = await _liveRequest();
      final p = await _api.progress(request.requestId);
      final attempt = await _attemptOf(request, p);
      _current = attempt;
      if (!_out.isClosed) _out.add(attempt);
      if (attempt.isClosed || attempt.state == RecoveryAttemptState.approved) {
        _stopPolling();
      }
    } on RecoveryApiFailure catch (e) {
      // A named refusal, never a status code and never the server's string
      // (07 §1 rule 12). `unknown_request` reaches here for both "no such
      // attempt" and "not yours", and stays one reason — asking again to tell
      // them apart is exactly the oracle 0010 refuses to be.
      throw RecoveryFailure(e.refusal.name);
    }
  }

  /// The attempt this phone is watching: the one already pinned, else the
  /// newest of its own, else a fresh one when this build can mint a candidate
  /// key.
  Future<RecoveryRequestWire> _liveRequest() async {
    final mine = await _api.myRequests();
    if (mine.isNotEmpty) {
      final pinned = _candidate?.requestId;
      for (final r in mine) {
        if (r.requestId == pinned) return _pin(r);
      }
      // Newest by the server's own `created_at`, which is the database's
      // clock — this phone's is not consulted, only compared against itself.
      var newest = mine.first;
      for (final r in mine) {
        if (r.createdAtMs > newest.createdAtMs) newest = r;
      }
      return _pin(newest);
    }
    final mint = _candidateKey;
    if (mint == null) {
      // No attempt and no way to open one honestly. S11.2 shows its
      // error-with-retry state, which is true, rather than a made-up attempt.
      throw const RecoveryFailure('no attempt');
    }
    return _pin(await _api.open(await mint()));
  }

  RecoveryRequestWire _pin(RecoveryRequestWire r) {
    _candidate = RecoveryCandidate(
      requestId: r.requestId,
      deviceId: r.candidateDevice,
      candidatePubX: r.candidatePubX,
    );
    return r;
  }

  Future<GuardianRecoveryAttempt> _attemptOf(
    RecoveryRequestWire r,
    RecoveryProgressWire p,
  ) async {
    final members = await _roster();
    return GuardianRecoveryAttempt(
      requestId: r.requestId,
      k: p.k,
      n: p.n,
      approvers: _attribute(members, p),
      state: recoveryStateOf(p.state),
      waitUntil: _at(p.waitUntilMs),
      expiresAt: _at(p.expiresAtMs ?? r.expiresAtMs),
      // The restore count is this device's own, once the key is back; the
      // server has no idea how many entries it holds and never will.
      restore: null,
    );
  }

  /// One row per member of the set, approved/declined **only** where a
  /// decision row names them. See this file's rule 2.
  List<TrustedApprover> _attribute(
    List<TrustedApprover> roster,
    RecoveryProgressWire p,
  ) {
    final byMember = <String, String>{
      for (final d in p.decisions) d.guardianUserId: d.decision,
    };
    return [
      for (final m in roster)
        TrustedApprover(
          memberId: m.memberId,
          name: m.name,
          phone: m.phone,
          state: switch (byMember[m.memberId]) {
            'approved' => TrustedApproverState.approved,
            'denied' => TrustedApproverState.declined,
            // The attempt is open, so every member of the set has been asked.
            _ => TrustedApproverState.waiting,
          },
        ),
    ];
  }

  @override
  Future<RecoveryScanOutcome> verifyOwnKeyByScan() async {
    // ADR 2026-09-13c ruling 2 🔒 — QR only. There is no typed branch here to
    // fall back to, by construction.
    final scan = _scanner;
    final c = _candidate;
    if (scan == null || c == null) return RecoveryScanOutcome.unavailable;
    return scan(c);
  }

  void _startPolling() {
    _tick ??= _ticker(pollEvery).listen((_) async {
      try {
        await refresh();
      } on Object {
        // A poll that failed is not a screen change: the last good snapshot
        // stands and the next tick tries again. Only the explicit refresh()
        // the screen awaits surfaces a failure.
      }
    });
  }

  void _stopPolling() {
    unawaited(_tick?.cancel());
    _tick = null;
  }

  /// Stops polling and closes the stream.
  Future<void> dispose() async {
    _stopPolling();
    await _out.close();
  }

  static DateTime? _at(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// [RecoverySheetEntry] over what the server offers today — which is nothing.
///
/// ⚠️ SPEC: **rung 3 has no server surface.** 04 §7.4 🔒 has the server hold
/// `sealed_RK_blob = XChaCha20(RK, UMK_priv)`; `wrapped_keys` has the
/// `recovery_blob` kind for it, but no migration uploads one and no route
/// fetches one by RK. Migration 0010 is rung 2 only. So this producer can do
/// exactly one honest thing and does it: it reports that the attempt could
/// not be made.
///
/// It matters *which* failure. [RecoverySheetRejected] means **the code did
/// not open the blob** and R2.4 renders it as "this sheet is not the current
/// one, or it was mistyped" — telling a user their correctly copied code is
/// wrong. This producer therefore throws [RecoveryFailure] and never
/// [RecoverySheetRejected]. Installing it is still strictly better than
/// leaving the scope empty: with no scope S11.3 falls back to
/// [FakeRecoverySheet], which **accepts any well-formed code and reports a
/// restore that did not happen**.
final class HttpRecoverySheet implements RecoverySheetEntry {
  /// Creates the producer.
  const HttpRecoverySheet();

  @override
  Future<RecoveryScanOutcome> scanSheet() async =>
      // No camera package is in the app, and 04 §7.4's QR path needs one.
      RecoveryScanOutcome.unavailable;

  @override
  Future<void> submit(RecoverySheetCode code) async =>
      throw const RecoveryFailure('no sheet route');

  @override
  Stream<RecoveryProgress> restore() => const Stream.empty();
}

/// [GuardianApprovals] over the 0010 routes — S11.7's live producer.
///
/// The one rule it holds beyond carrying the wire: **an approval is refused
/// until this phone has scanned the candidate and matched it.**
/// ADR 2026-09-13c ruling 3 🔒 turns 04 §7.3 step 2's *"call them before
/// approving"* from advice into a check, and the check lives here rather than
/// in the screen, so a layout bug cannot produce an unverified approval. The
/// verification is remembered against the **candidate key bytes**, not merely
/// the request id, so a scan of one attempt can never stand in for another.
final class HttpGuardianApprovals implements GuardianApprovals {
  /// Creates the producer. [requesterNameOf] and [deviceNameOf] resolve what
  /// the server does not know — names are never the server's (ADR
  /// 2026-09-05c §4) — and [fingerprintOf] renders the candidate key as the
  /// string 04 §7.3 step 2 🔒 has the guardian read aloud.
  HttpGuardianApprovals({
    required RecoveryApi api,
    required String Function(String userId) requesterNameOf,
    required String Function(String deviceId) deviceNameOf,
    required String Function(Uint8List candidatePubX) fingerprintOf,
    String? Function(String userId)? phoneOf,
    RecoveryScanner? scanner,
    RecoveryResealer? resealer,
  }) : _api = api,
       _nameOf = requesterNameOf,
       _deviceNameOf = deviceNameOf,
       _fingerprintOf = fingerprintOf,
       _phoneOf = phoneOf,
       _scanner = scanner,
       _resealer = resealer;

  final RecoveryApi _api;
  final String Function(String) _nameOf;
  final String Function(String) _deviceNameOf;
  final String Function(Uint8List) _fingerprintOf;
  final String? Function(String)? _phoneOf;
  final RecoveryScanner? _scanner;
  final RecoveryResealer? _resealer;

  /// Request id → the candidate key the scan actually matched.
  final Map<String, Uint8List> _verified = {};

  @override
  Future<GuardianRecoveryAsk> load(String requestId) async {
    final ask = await _ask(requestId);
    return GuardianRecoveryAsk(
      requestId: ask.requestId,
      requesterName: _nameOf(ask.subjectUserId),
      newDeviceName: _deviceNameOf(ask.candidateDevice),
      newDeviceFingerprint: _fingerprintOf(ask.candidatePubX),
      requesterPhone: _phoneOf?.call(ask.subjectUserId),
    );
  }

  @override
  Future<RecoveryScanOutcome> verifyCandidateByScan(String requestId) async {
    final scan = _scanner;
    if (scan == null) return RecoveryScanOutcome.unavailable;
    final ask = await _ask(requestId);
    final outcome = await scan(_candidateOf(ask));
    if (outcome == RecoveryScanOutcome.verified) {
      _verified[requestId] = ask.candidatePubX;
    } else {
      // A mismatch or a cancel clears any earlier pass: the last word on this
      // attempt is the one that counts (ADR 2026-09-13c ruling 1 🔒 — hard
      // fail, no override).
      _verified.remove(requestId);
    }
    return outcome;
  }

  @override
  Future<void> approve(String requestId) async {
    final matched = _verified[requestId];
    if (matched == null) throw const RecoveryCandidateUnverified();
    final ask = await _ask(requestId);
    // The attempt's candidate key must still be the one the scan matched. The
    // server refuses a mismatch too (0010 `candidate_key_mismatch`), which is
    // the point: this check is the same rule held twice, and the client's
    // copy is the one that stops an unverified share ever being sealed.
    if (!_sameBytes(matched, ask.candidatePubX)) {
      _verified.remove(requestId);
      throw const RecoveryCandidateUnverified();
    }
    final reseal = _resealer;
    if (reseal == null) throw const RecoveryFailure('no resealer');
    final candidate = _candidateOf(ask);
    final blob = await reseal(candidate);
    try {
      await _api.approve(
        requestId: requestId,
        blob: blob,
        sealedToPubX: candidate.candidatePubX,
      );
    } on RecoveryApiFailure catch (e) {
      throw RecoveryFailure(e.refusal.name);
    }
  }

  @override
  Future<void> decline(String requestId) async {
    // Refusing is always safe, so it needs no scan (04 §7.3 step 7).
    try {
      await _api.deny(requestId);
    } on RecoveryApiFailure catch (e) {
      throw RecoveryFailure(e.refusal.name);
    }
  }

  Future<RecoveryAskWire> _ask(String requestId) async {
    final List<RecoveryAskWire> asks;
    try {
      asks = await _api.asks();
    } on RecoveryApiFailure catch (e) {
      throw RecoveryFailure(e.refusal.name);
    }
    for (final a in asks) {
      if (a.requestId == requestId) return a;
    }
    // An attempt that does not exist and one this guardian may not see answer
    // identically here, exactly as the route answers them (0010).
    throw const RecoveryFailure('unknown_request');
  }

  RecoveryCandidate _candidateOf(RecoveryAskWire a) => RecoveryCandidate(
    requestId: a.requestId,
    deviceId: a.candidateDevice,
    candidatePubX: a.candidatePubX,
  );

  /// Plain byte equality: both operands are **public** keys the attacker
  /// already holds, so there is no secret for a timing difference to leak,
  /// and rule 7 keeps a hand-rolled primitive out of the app layer.
  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length || a.isEmpty) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
