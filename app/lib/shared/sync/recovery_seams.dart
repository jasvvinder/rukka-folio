// The live producers behind the recovery-ladder seams (04 §7.3 🔒, 06 §5,
// 13 §5 flow F11) — S11.2, S11.3 and S11.7 against the real 0010 (rung 2)
// and 0011 (rung 3) routes.
//
// `shared/seams/recovery_ladder.dart` declares what the screens consume and
// is **settled**: 53 widget tests run on its fakes and nothing here changes a
// line of it. This file implements those interfaces over
// `recovery_api.dart`, and the whole of its job is to be the place where the
// server's answers are *carried*, not re-decided.
//
// ============================================================================
// THE THREE RULES THIS FILE EXISTS TO HOLD
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
// requester's screen can say *which* trusted members approved, and
// `progressToWire` now sends those rows. This adapter attributes a decision
// **only** to the guardian the row names. Marking "the first `approvals`
// members" would put a tick beside somebody who has not acted, on a screen
// whose entire job is to say who has — so a member no row names reads
// *waiting*, which under-reports and never misattributes. A denial is a row
// and silence is the absence of one, which is why the two are drawn
// differently and why neither may be inferred from a count.
//
// **3. The roster is the set the attempt PINNED.** 0010 pins
// `share_set_version` when an attempt opens, so a re-split in the middle
// moves neither the quorum nor the membership. [RecoveryRosterSource] is
// asked for *that* generation and never for "the current set": drawing
// today's members beside a pinned attempt's decisions would hide a member who
// did answer and show a row for one who was never asked.
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

/// The per-attempt candidate X25519 pair of 04 §7.3 step 1, seen from the
/// seam — **public halves only**.
///
/// ADR 2026-09-24b §1 🔒 settled the reading the ⚠️ SPEC here used to flag:
/// the candidate is **its own pair**, never this device's `pub_x`. It is
/// minted when this device opens an attempt, held in the platform key store
/// until the attempt closes (approved, cancelled, denied or expired), and
/// zeroised after `reconstructVerified` and on every close. It never wraps a
/// book key and is never registered as a device key. The secret half lives
/// behind this interface (`recovery_candidate.dart`); nothing in this file
/// ever holds it, which keeps rule *nothing here holds key material* true.
abstract interface class RecoveryCandidateKeys {
  /// Mints a fresh pair for a **new** attempt, holds its secret in the key
  /// store — replacing, and so zeroising, any pair held before — and returns
  /// its 32-byte public half. Called once per attempt opened, never to
  /// re-read one.
  Future<Uint8List> mint();

  /// The public half of the pair held now, or null when none is.
  Future<Uint8List?> held();

  /// Zeroises and removes the held secret **if** it is the pair whose public
  /// half is [publicHalf]; anything else held is left alone. Idempotent.
  Future<void> discard(Uint8List publicHalf);
}

/// The trusted members of one **generation** of the guardian set, in the
/// order S11.2 draws them, each in its resting state.
///
/// The parameter is the attempt's pinned `share_set_version` (0010), never
/// "the latest": see rule 3 at the top of this file. A source that does not
/// hold that generation answers with an empty list — nobody named — rather
/// than substituting another generation's people.
typedef RecoveryRosterSource = Future<List<TrustedApprover>> Function(
  int shareSetVersion,
);

/// Opens the user's own sealed sheet blob with the recovery key printed on
/// paper, and puts the recovered `UMK_priv` back (04 §7.4 🔒 rung 3).
///
/// **The bool is the whole security of the rung.** `true` means the key is
/// back. `false` means *this code did not open this blob* — and that verdict
/// is reached **on this phone**, from one of the two local checks:
/// `recoverySheetFromTyped` refusing the payload (a foreign symbol, the wrong
/// length, or the 2-char checksum of 04 §7.4 🔒 not matching — a mistype), or
/// `openUmkWithRecoveryKey` refusing the ciphertext (`RecoveryUnsealFailed`,
/// which is a sheet reprinted since: regenerating rotates RK). Those are
/// exactly R2.4's two stated causes, and they are indistinguishable to
/// everyone including this device, which is why the copy states both.
///
/// Anything else — no sheet on the server, no session, a dead socket, a blob
/// this build cannot frame, a key that could not be installed — is a
/// **throw**, because none of those learned anything about the code.
///
/// It is injected for the same reason [RecoveryResealer] is: the decryption
/// is `core_crypto`'s (`recoverySheetFromTyped` → `openUmkWithRecoveryKey`)
/// and installing a key is the ledger's, so no RK, no UMK and no sealed blob
/// framing is ever a field of this file (04 §7.6, 07 §5.6 🔒).
typedef RecoverySheetOpener = Future<bool> Function(
  RecoverySheetCode code,
  RecoverySheetWire sheet,
);

/// Decides, **without the blob and without the network**, whether a typed
/// code is a sheet code at all: the right number of Crockford symbols, a
/// known sheet version, and the 2-char checksum of 04 §7.4 🔒 matching.
///
/// `true` means *worth trying*; `false` means *this is a mistype*.
///
/// It exists because the checksum is real. `core_crypto`'s `_sheetChecksum`
/// (`packages/core_crypto/lib/src/recovery.dart:318`) is the first two
/// Crockford symbols of `BLAKE2b-256(version ‖ user_id ‖ RK)`, and
/// `recoverySheetFromTyped` (`:360`) throws `RecoverySheetChecksumFailed`
/// when the typed group does not match — so a typo is caught here with
/// probability 1 − 2⁻¹⁰ on top of the alphabet's own rejection of I/L/O/U,
/// on this phone, before anything is spent. Two things follow, and both are
/// the point:
///
///   1. **No fetch.** `recovery/sheet` is rate limited (`sheet_flood`, ADR
///      2026-09-05b §7) and a person who has just mistyped 81 characters is
///      about to type them again. Spending a request to be told what the
///      checksum already said would be spending the one resource that runs
///      out on the attempt that needs it.
///   2. **No oracle.** The check is arithmetic over what the person typed. It
///      reaches the server for nothing, so it cannot leak that a code was
///      tried, and it learns nothing about whether a sheet exists.
///
/// It is injected, not called directly, for the reason the opener is: running
/// it materialises `RK` (the checksum covers the payload, and the payload
/// *is* the key), so it belongs where `core_crypto` and a `CryptoSuite` are
/// and where the result can be disposed — never in this file and never in a
/// widget (04 §7.4, 07 §5.6 🔒).
typedef RecoverySheetPrecheck = bool Function(RecoverySheetCode code);

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
  /// the order S11.2 draws them, each in its resting state; [candidateKeys]
  /// holds the per-attempt candidate pair (ADR 2026-09-24b §1 🔒) and lets the
  /// screen's refresh open a *new* attempt — when this user has none listed,
  /// or when the one it would show is not this phone's and is over (see
  /// `_mayAskAgain`) — and null means this build can only re-read one that
  /// already exists.
  HttpGuardianRecovery({
    required RecoveryApi api,
    required RecoveryRosterSource roster,
    RecoveryCandidateKeys? candidateKeys,
    RecoveryScanner? scanner,
    Stream<void> Function(Duration)? ticker,
    this.pollEvery = const Duration(seconds: 20),
  }) : _api = api,
       _roster = roster,
       _candidateKeys = candidateKeys,
       _scanner = scanner,
       _ticker = ticker ?? _realTicker;

  static Stream<void> _realTicker(Duration every) =>
      Stream<void>.periodic(every, (_) {});

  final RecoveryApi _api;
  final RecoveryRosterSource _roster;
  final RecoveryCandidateKeys? _candidateKeys;
  final RecoveryScanner? _scanner;
  final Stream<void> Function(Duration) _ticker;

  /// How often the attempt is re-read while it can still change.
  final Duration pollEvery;

  GuardianRecoveryAttempt? _current;
  RecoveryCandidate? _candidate;
  StreamSubscription<void>? _tick;

  // Reads are serialised. Two overlapping refreshes — the screen's and a
  // poll's — could otherwise both find no attempt and both mint, or one could
  // read the listing between another's mint and its open and take the fresh
  // key for an orphan. Either leaves a held key that belongs to no attempt,
  // or an attempt whose key is gone. One read at a time makes the order of
  // list → mint → open → pin a property of this object, not of timing.
  Future<void> _last = Future<void>.value();
  bool _running = false;
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
  Future<void> refresh() => _serialised(mayOpen: true);

  /// Runs one read after every earlier one has finished. Only the screen's
  /// own [refresh] may open an attempt ([mayOpen]); a poll re-reads and never
  /// mints, so a timer can never be the thing that asks the guardians.
  Future<void> _serialised({required bool mayOpen}) {
    final run = _last.then((_) async {
      _running = true;
      try {
        await _read(mayOpen: mayOpen);
      } finally {
        _running = false;
      }
    });
    _last = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _read({required bool mayOpen}) async {
    try {
      var live = await _liveRequest();
      var p = live == null ? null : await _api.progress(live.request.requestId);
      final keys = _candidateKeys;
      var opened = false;
      if (keys != null && mayOpen && _mayAskAgain(live, p)) {
        // 04 §7.3 step 1, from the screen's own refresh and nothing else.
        live = (request: await _open(keys), owned: true);
        p = await _api.progress(live.request.requestId);
        opened = true;
      }
      if (live == null || p == null) {
        // No attempt and no way to open one honestly (or a poll, which never
        // opens). S11.2 shows its error-with-retry state, which is true,
        // rather than a made-up attempt.
        throw const RecoveryFailure('no attempt');
      }
      final request = live.request;
      final attempt = await _attemptOf(request, p);
      if (attempt.isClosed) {
        // ADR 2026-09-24b §1 🔒 — every close zeroises. Cancelled, and
        // expired (which is also three denials: 03 §2.2 has no `denied`),
        // are final on the server's word, so the candidate secret goes
        // before the screen hears the attempt is over. Only the pair whose
        // public half THIS attempt carries is touched — a close of somebody
        // else's attempt deletes nothing. `approved` is not handled here: the
        // pair is still needed to open the shares (04 §7.3 step 4), and it is
        // deleted after reconstruct instead.
        await _discard(request.candidatePubX);
      }
      _current = attempt;
      if (!_out.isClosed) _out.add(attempt);
      if (attempt.isClosed || attempt.state == RecoveryAttemptState.approved) {
        _stopPolling();
      } else if (opened && _out.hasListener) {
        // A fresh attempt after a close: the close stopped polling, and the
        // screen that is still listening must hear the new one move without
        // re-entering. Idempotent while a ticker already runs.
        _startPolling();
      }
    } on RecoveryApiFailure catch (e) {
      // A named refusal, never a status code and never the server's string
      // (07 §1 rule 12). `unknown_request` reaches here for both "no such
      // attempt" and "not yours", and stays one reason — asking again to tell
      // them apart is exactly the oracle 0010 refuses to be.
      throw RecoveryFailure(e.refusal.name);
    }
  }

  /// The listed attempt this phone is watching — the one its held candidate
  /// key belongs to ([owned]), else the one already pinned, else the newest
  /// of the user's — or null when nothing is listed. It never opens one:
  /// that is [_read]'s decision, on the screen's refresh alone.
  Future<({RecoveryRequestWire request, bool owned})?> _liveRequest() async {
    final mine = await _api.myRequests();
    final keys = _candidateKeys;
    if (keys != null) {
      final held = await _held(keys);
      if (held != null) {
        // The attempt THIS phone can finish is the one sealed shares will
        // come back to this key for — matched on the key bytes, never on a
        // request id or on which attempt is newest. Another of the user's
        // phones may have an attempt of its own in the same listing.
        for (final r in mine) {
          if (_sameBytes(r.candidatePubX, held)) {
            return (request: _pin(r, held: held), owned: true);
          }
        }
        // Held, but no attempt carries it: the open never landed, or the
        // attempt has aged out of the listing. Either way no attempt will
        // ever seal a share to it, so it is not kept "until the attempt
        // closes" — there is no attempt.
        await _discard(held);
      }
    }
    if (mine.isEmpty) return null;
    final pinned = _candidate?.requestId;
    for (final r in mine) {
      if (r.requestId == pinned) return (request: _pin(r), owned: false);
    }
    // Newest by the server's own `created_at`, which is the database's
    // clock — this phone's is not consulted, only compared against itself.
    var newest = mine.first;
    for (final r in mine) {
      if (r.createdAtMs > newest.createdAtMs) newest = r;
    }
    return (request: _pin(newest), owned: false);
  }

  /// Whether the screen's refresh opens a fresh attempt (only ever asked when
  /// this build holds candidate pairs): the user has none listed, or the one
  /// this phone would show is **not its own** and the server says it is
  /// **over**.
  ///
  /// The server lists closed attempts for 30 days after they expire (0010's
  /// retention guard, `rf.sweep_recovery`), so "open only when the listing is
  /// empty" would pin a closed attempt for about 33 days while its card says
  /// *you can start a new one* (`recovery.ask.closed.body`,
  /// `recovery.ask.cancelled.body`) — a dead end (07 §1 rule 6).
  ///
  /// What it may never do is re-ask the guardians over a close this phone has
  /// not yet shown. An attempt whose key this phone holds is [owned]: the
  /// refresh that finds it closed zeroises and **shows** the close — for a
  /// cancel, the warning to call the people you trust before asking again —
  /// and opens nothing; only the next screen refresh, by which the key is
  /// gone, asks again. At most one attempt per refresh, and a poll never.
  ///
  /// "Over" is the server's word mapped by [recoveryStateOf] — never a clock
  /// here, and an unknown word reads `pending`, which asks nobody. Only
  /// `cancelled` and `expired` (which is also three denials) count.
  /// ⚠️ SPEC: an `approved` attempt this phone cannot finish, and a live one
  /// of another phone, are shown and not re-asked: neither close's copy
  /// promises a new request, and asking twice is visible to other people.
  /// Reported for a features/recovery ruling.
  static bool _mayAskAgain(
    ({RecoveryRequestWire request, bool owned})? live,
    RecoveryProgressWire? p,
  ) {
    if (live == null) return true;
    if (live.owned || p == null) return false;
    final s = recoveryStateOf(p.state);
    return s == RecoveryAttemptState.cancelled ||
        s == RecoveryAttemptState.expired;
  }

  /// 04 §7.3 step 1: a fresh pair for this attempt and no other (ADR
  /// 2026-09-24b §1 🔒), and the attempt opened on its public half.
  Future<RecoveryRequestWire> _open(RecoveryCandidateKeys keys) async {
    final Uint8List pub;
    try {
      pub = await keys.mint();
    } on Object {
      // The key store would not take the secret. Nothing was sent, and
      // nothing may be: an attempt whose key this phone does not hold is one
      // whose shares nobody can open.
      throw const RecoveryFailure('key_store');
    }
    final RecoveryRequestWire r;
    try {
      r = await _api.open(pub);
    } on RecoveryApiFailure catch (e) {
      // A refusal the server stated means no attempt was opened, so the pair
      // belongs to nothing and goes now. `offline` and `server` claim nothing
      // about whether the insert landed: the pair is kept, and the next read
      // either finds the attempt carrying it or discards it.
      if (e.refusal != RecoveryRefusal.offline &&
          e.refusal != RecoveryRefusal.server) {
        await _discard(pub);
      }
      rethrow;
    }
    if (!_sameBytes(r.candidatePubX, pub)) {
      // The server says it opened an attempt on a key this phone did not
      // send. Guardians would be asked to seal to a key nobody here holds —
      // or to the relay's own (ADR 2026-09-13c §3). Nothing is pinned, and
      // the pair goes: it is not that attempt's, and no attempt carries it.
      await _discard(pub);
      throw RecoveryFailure(RecoveryRefusal.candidateKeyMismatch.name);
    }
    return _pin(r, held: pub);
  }

  Future<Uint8List?> _held(RecoveryCandidateKeys keys) async {
    try {
      return await keys.held();
    } on Object {
      throw const RecoveryFailure('key_store');
    }
  }

  Future<void> _discard(Uint8List publicHalf) async {
    final keys = _candidateKeys;
    if (keys == null) return;
    try {
      await keys.discard(publicHalf);
    } on Object {
      // Loud, not swallowed: a close that could not zeroise is retried by the
      // next read (the attempt is still listed, still carries the key), and
      // the screen says something went wrong rather than that all is well.
      throw const RecoveryFailure('key_store');
    }
  }

  RecoveryRequestWire _pin(RecoveryRequestWire r, {Uint8List? held}) {
    if (held == null && _candidateKeys != null) {
      // Shown, not owned. This build holds candidate pairs, and this attempt
      // carries a key it does not hold — another phone's, one from before a
      // reinstall, or one the server substituted on open. Its shares can never
      // be opened here, so no candidate is exposed for it: nothing downstream
      // can render the server's bytes as *this phone's* code for a guardian
      // to match (ADR 2026-09-13c §3), and the ceremony reads `unavailable`.
      _candidate = null;
      return r;
    }
    _candidate = RecoveryCandidate(
      requestId: r.requestId,
      deviceId: r.candidateDevice,
      // The phone's own copy when it holds the pair (byte-equal to the
      // relayed one — that is how the attempt was matched), so what this
      // phone would show a guardian is never merely what the server said.
      candidatePubX: held != null ? Uint8List.fromList(held) : r.candidatePubX,
    );
    return r;
  }

  Future<GuardianRecoveryAttempt> _attemptOf(
    RecoveryRequestWire r,
    RecoveryProgressWire p,
  ) async {
    // The set the ATTEMPT is pinned to (0010 pins it at open), taken from the
    // request rather than from the progress body so that the two can never
    // disagree about which generation is being drawn. Rule 3 at the top.
    final members = await _roster(r.shareSetVersion);
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
      // A read already under way is not queued behind: a hung socket must not
      // grow a line of polls that all land at once.
      if (_running) return;
      try {
        await _serialised(mayOpen: false);
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

/// [RecoverySheetEntry] over rung 3's own routes (04 §7.4 🔒, migration
/// 0011) — S11.3's live producer.
///
/// The server holds `sealed_RK_blob = XChaCha20(RK, UMK_priv)` and cannot
/// open it: RK is a 256-bit key that exists on a sheet of paper. So the whole
/// of this producer is *fetch the user's own current blob and hand it, with
/// the code, to something that can try the AEAD* — and the one rule it exists
/// to hold is where the verdict comes from.
///
/// ============================================================================
/// THE VERDICT IS THE AEAD OPEN, NEVER THE FETCH
/// ============================================================================
///
/// [RecoverySheetRejected] is R2.4's *"that code didn't work"*. It may be
/// thrown only when a check **on this phone** refused the code, and there are
/// exactly two such checks, in this order:
///
///   1. [RecoverySheetPrecheck] — 04 §7.4 🔒's 2-char checksum, run before
///      any fetch. A failure is a mistype, decided from what the person
///      typed, with the rate-limited route never touched.
///   2. [RecoverySheetOpener] — the AEAD open, for a code that is well formed
///      but opens nothing: a sheet reprinted since (regenerating rotates RK).
///
/// Those are the two causes R2.4 states, they are indistinguishable to the
/// person, and nothing else may produce this exception. In particular the
/// server never does: it is never asked about a code.
///
/// Everything else is [RecoveryFailure], because nothing about the code was
/// learned:
///
///   * `no_sheet` — this user never published one. **The server was asked for
///     a user's blob, not for a code**: it has never seen RK, holds nothing it
///     could compare one against, and answers `no_sheet` identically for a
///     user who printed nothing. Rendering that as a rejected code would tell
///     somebody holding a correctly copied sheet that they mistyped it.
///   * offline, no session, rate-limited, a body this build cannot read.
///   * no opener installed — this build cannot try the AEAD at all, so it
///     reports that the attempt could not be made rather than a verdict it
///     never reached.
final class HttpRecoverySheet implements RecoverySheetEntry {
  /// Creates the producer.
  ///
  /// [opener] is what actually opens the blob and puts the key back; with
  /// none, [submit] refuses plainly and no code is ever called wrong.
  /// [restoreProgress] is the count of what comes back afterwards — a count,
  /// never a percentage (11 §4.5 🔒) — and is empty until a restore can
  /// report one.
  /// [precheck] is the local verdict of 04 §7.4 🔒's 2-char checksum; with
  /// none, no code is refused before the fetch and the AEAD open stays the
  /// only verdict, exactly as before.
  const HttpRecoverySheet({
    required RecoveryApi api,
    RecoverySheetOpener? opener,
    RecoverySheetPrecheck? precheck,
    Stream<RecoveryProgress> Function()? restoreProgress,
  }) : _api = api,
       _open = opener,
       _precheck = precheck,
       _restore = restoreProgress;

  final RecoveryApi _api;
  final RecoverySheetOpener? _open;
  final RecoverySheetPrecheck? _precheck;
  final Stream<RecoveryProgress> Function()? _restore;

  /// Whether [code] is worth spending a fetch on — R2.4's *Restore* may be
  /// drawn **disabled-with-reason** (13 §4.3) off this, rather than enabled
  /// into a round trip that is already known to fail. With no precheck
  /// installed it answers `true`, because an unknown verdict is not a
  /// refusal.
  ///
  /// It is not on [RecoverySheetEntry]: adding it there would oblige every
  /// implementation, including the seam's fake, to own a `CryptoSuite`. A
  /// screen that wants it reads it off the concrete producer, or the verdict
  /// still arrives as [RecoverySheetRejected] from [submit].
  bool isWorthTrying(RecoverySheetCode code) {
    final check = _precheck;
    if (check == null) return true;
    try {
      return check(code);
    } on Object {
      // A precheck that failed to run is not a verdict on the code. The
      // fetch is the fallback, not a refusal.
      return true;
    }
  }

  @override
  Future<RecoveryScanOutcome> scanSheet() async =>
      // No camera package is in the app, and 04 §7.4's QR path needs one
      // (the ADR 2026-09-12e precedent: the choice is an owner ruling).
      RecoveryScanOutcome.unavailable;

  @override
  Future<void> submit(RecoverySheetCode code) async {
    final open = _open;
    // Checked before the fetch: with nothing that can try the AEAD there is
    // no verdict to reach, and the route ADR 2026-09-05b §7 rate-limits is
    // not worth spending to learn that.
    if (open == null) throw const RecoveryFailure('no opener');

    // 04 §7.4 🔒's checksum, before the fetch. A code that fails it is a
    // mistype and nothing else — the verdict is arithmetic over what the
    // person typed, not something the server was asked — so it is R2.4's
    // rejection, reached without spending the rate-limited route.
    if (!isWorthTrying(code)) throw const RecoverySheetRejected();

    final RecoverySheetWire? sheet;
    try {
      sheet = await _api.sheet();
    } on RecoveryApiFailure catch (e) {
      // A named refusal, never a status code and never the server's string
      // (07 §1 rule 12) — and never a rejection.
      throw RecoveryFailure(e.refusal.name);
    }
    if (sheet == null) throw const RecoveryFailure('no_sheet');

    final bool opened;
    try {
      opened = await open(code, sheet);
    } on RecoverySheetRejected {
      // An opener that prefers to throw the verdict rather than return it
      // says the same thing: the AEAD refused.
      rethrow;
    } on Object {
      // Any other throw is this device failing, not the code being wrong.
      throw const RecoveryFailure('open');
    }
    if (!opened) throw const RecoverySheetRejected();
  }

  @override
  Stream<RecoveryProgress> restore() =>
      _restore?.call() ?? const Stream.empty();
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
}

/// Plain byte equality: both operands are **public** keys the attacker
/// already holds, so there is no secret for a timing difference to leak,
/// and rule 7 keeps a hand-rolled primitive out of the app layer. Empty never
/// equals anything — a key the wire failed to carry matches no key.
bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length || a.isEmpty) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
