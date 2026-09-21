// The live [RecoveryLadder] — S11.6's fork, answered from real sources
// (04 §7.0 🔒, §7.1, §7.2, §7.4 🔒; 13 §5 flow F11; 13 §3.2 row S11.6).
//
// Until now S11.6 ran on [FakeRecoveryLadder] in production, and the reason
// was a good one: rung 3's availability was not knowable, and a ladder true
// about one rung and invented about two would be worse than the fake. That
// changed when `GET sync-meta/recovery/sheet` landed (migration 0011, 04 §7.4
// 🔒). Rungs 0 and 1 are platform-key-sync and device knowledge, which are
// this side's, so all three can now be answered — and where one cannot, it is
// answered [RecoveryRungAvailability.unknown] rather than guessed.
//
// ============================================================================
// THE ONE RULE THIS FILE EXISTS TO HOLD
// ============================================================================
//
// **Unknown is a state, never a default of available.**
//
// The person reading S11.6 is already locked out. The two ways to be wrong
// are not symmetrical and neither is cheap:
//
//   * offering a rung that then fails spends the one attempt they steeled
//     themselves for, on the screen where their books are at stake;
//   * denying a rung they actually hold — "you have no recovery sheet" to
//     somebody holding one — can make them stop trying.
//
// So no probe here is allowed to conclude `available` from the absence of a
// refusal. Every offer traces to a source that said something: the platform
// key store, the devices repository, `guardian_sets`, or `recovery/sheet`. A
// probe that throws, that has no producer in this build, or that cannot reach
// the server yields [RecoveryRungOffer.unknown] — and [LiveRecoveryLadder]
// itself never throws, because a whole-screen error would hide the two rungs
// that *were* answered behind the one that was not.
//
// **Rung 3 reuses `recovery_api.dart`.** `HttpRecoverySheet.submit` already
// fetches the user's own `sealed_RK_blob` through [RecoveryApi.sheet]; the
// probe takes the same [RecoveryApi] instance rather than opening a second
// path to the same endpoint, so one route, one refusal table, one rate limit
// (ADR 2026-09-05b §7's `sheet_flood`).
//
// **Nothing here holds key material.** The rung-0 probe asks the key store
// *whether* an item is present and never reads one; the rung-3 probe learns
// that a sealed blob exists and never opens it. RK, the UMK and every device
// private key stay where 04 §7.4 / 07 §5.6 🔒 put them.
import 'dart:async';

import '../../features/devices/devices_repository.dart';
import '../seams/key_store.dart';
import '../seams/recovery_ladder.dart';
import 'guardians_api.dart';
import 'recovery_api.dart';

/// Answers one rung's question from a real source.
///
/// It returns the offer for its rung. Throwing is allowed and means
/// [RecoveryRungOffer.unknown]: a probe is never obliged to invent an answer
/// to avoid an exception, and [LiveRecoveryLadder] does the conversion in one
/// place so no probe can forget.
typedef RecoveryRungProbe = Future<RecoveryRungOffer> Function();

/// [RecoveryLadder] over this build's real sources.
///
/// It is a combinator and nothing more: it holds one [RecoveryRungProbe] per
/// rung, runs them, and turns a throw or a missing probe into
/// [RecoveryRungOffer.unknown]. The knowledge lives in the probes below, so a
/// rung that gains a producer later gains it without this class changing.
final class LiveRecoveryLadder implements RecoveryLadder {
  /// Creates the ladder over [probes].
  ///
  /// A rung with no entry in [probes] is [RecoveryRungOffer.unknown] — which
  /// is why the map is not required to be complete and why an incomplete one
  /// is safe. [progress] is the live count a rung reports while it runs; with
  /// none, a rung reports nothing, which S11.5 already reads as *this rung did
  /// not get there* and follows with the fork.
  const LiveRecoveryLadder({
    required Map<RecoveryRung, RecoveryRungProbe> probes,
    Stream<RecoveryProgress> Function(RecoveryRung rung)? progress,
  }) : _probes = probes,
       _progress = progress;

  final Map<RecoveryRung, RecoveryRungProbe> _probes;
  final Stream<RecoveryProgress> Function(RecoveryRung)? _progress;

  /// Which rungs are answered. Rung 0 is included as well as the three the
  /// fork draws, because S11.5 asks about it before any fork exists.
  static const _answered = [
    RecoveryRung.platformKeySync,
    ...RecoveryRung.forkOrder,
  ];

  @override
  Future<List<RecoveryRungOffer>> rungs() async {
    // Probed together, because three round trips in series on a lock-out
    // screen is a person watching a spinner for no reason. Each is isolated:
    // one failing source may not decide another rung's answer.
    final offers = await Future.wait([
      for (final rung in _answered) _probe(rung),
    ]);
    return List.unmodifiable(offers);
  }

  Future<RecoveryRungOffer> _probe(RecoveryRung rung) async {
    final probe = _probes[rung];
    // No producer in this build is not evidence that the rung is missing —
    // it is evidence that this phone did not look.
    if (probe == null) return RecoveryRungOffer.unknown(rung);
    try {
      final offer = await probe();
      // A probe that answered about the wrong rung is a wiring mistake, and
      // the honest reading of a wiring mistake is that nothing was learned.
      return offer.rung == rung ? offer : RecoveryRungOffer.unknown(rung);
    } on Object {
      // Deliberately swallowing: the exception is this phone's failure to
      // find out, and there is no shape of failure that would make
      // `available` the right answer. Nothing is logged — a recovery probe's
      // error can name a user's guardians or the existence of their sheet
      // (CLAUDE.md rule 4).
      return RecoveryRungOffer.unknown(rung);
    }
  }

  @override
  Stream<RecoveryProgress> progressOf(RecoveryRung rung) =>
      _progress?.call(rung) ?? const Stream.empty();
}

// ---------------------------------------------------------------------------
// Rung 0 — platform key sync / Keychain remnant (04 §7.0 🔒, §7.1)
// ---------------------------------------------------------------------------

/// Rung 0 from the platform key store.
///
/// 04 §7.0 🔒 is tried **before every other rung**: on iOS the wrapped UMK
/// rides iCloud Keychain, on Android Block Store, and a new phone on the same
/// account finds it already there. 04 §7.1 is the neighbouring case — a
/// reinstall on the *same* phone whose Keychain items survived. Both end the
/// same way and the seam names them one rung, so one probe answers both.
///
/// What it asks is deliberately the cheapest true question: **is the wrapped
/// UMK present** ([KeyIds.wrappedUmk]), and failing that, **are this phone's
/// device keys present** ([KeyIds.deviceSigningKey]) — 04 §7.1's "device keys
/// intact → normal certified device". It never *reads* an item, so no key
/// material is touched to answer a question about existence, and no biometric
/// prompt is raised on a screen that has not asked for one.
///
/// ⚠️ SPEC: an absent item is reported as [RecoveryRungBlocked
/// .notOnThisPhoneYet], which is the nearest true reason the seam has. Rung 0
/// has none of its own — the enum's three specific reasons are the fork's
/// three rungs — and adding one would break the exhaustive `switch` in
/// `features/recovery`'s S11.6, a file this lane does not own. The rung is
/// not drawn on the fork (it is not in [RecoveryRung.forkOrder]), so nothing
/// renders the reason today. Reported as an open item: rung 0 wants its own
/// `RecoveryRungBlocked` value and its own copy line.
RecoveryRungProbe platformKeySyncProbe(KeyStore keys) => () async {
  // Order matters only for cost: the wrapped UMK is the rung proper, the
  // device key is §7.1's remnant.
  if (await keys.contains(KeyIds.wrappedUmk)) {
    return const RecoveryRungOffer.available(RecoveryRung.platformKeySync);
  }
  if (await keys.contains(KeyIds.deviceSigningKey)) {
    return const RecoveryRungOffer.available(RecoveryRung.platformKeySync);
  }
  // A store that answered "no" twice is a real source saying no: 04 §7.0's
  // own honest limit — "a user who has disabled iCloud Keychain has nothing
  // here". A store that *threw* never reaches this line; the ladder turns
  // that into unknown.
  return const RecoveryRungOffer.blocked(
    RecoveryRung.platformKeySync,
    RecoveryRungBlocked.notOnThisPhoneYet,
  );
};

// ---------------------------------------------------------------------------
// Rung 1 — another of your own devices (04 §7.2, §9.1)
// ---------------------------------------------------------------------------

/// Rung 1 from the devices repository.
///
/// The question is 06 §5's: *does this user still have a phone to link from?*
/// Only a device that is **certified and is not this one** counts. A
/// suspended device cannot certify anything, a revoked one must not, and an
/// uncertified one has nothing to give — counting any of them would put a
/// live row on the fork for a phone that will refuse.
///
/// **A stale snapshot is not an answer.** The probe refreshes, and a refresh
/// that fails yields unknown even when a cached snapshot is sitting there:
/// the cached list was true at some past moment, and the one thing it cannot
/// establish is that the device is still certified *now* — which is exactly
/// what the row would be promising.
RecoveryRungProbe anotherDeviceProbe(DevicesRepository devices) => () async {
  await devices.refresh(); // throws ⇒ unknown, by the ladder's conversion
  final snapshot = devices.current;
  if (snapshot == null) {
    // A refresh that succeeded and left nothing behind told us nothing.
    return const RecoveryRungOffer.unknown(RecoveryRung.anotherDevice);
  }
  final linkable = snapshot.devices.any(
    (d) => !d.isThisDevice && d.status == DeviceStatus.certified,
  );
  return linkable
      ? const RecoveryRungOffer.available(RecoveryRung.anotherDevice)
      : const RecoveryRungOffer.blocked(
          RecoveryRung.anotherDevice,
          RecoveryRungBlocked.noOtherDevice,
        );
};

// ---------------------------------------------------------------------------
// Rung 2 — trusted members (04 §7.3)
// ---------------------------------------------------------------------------

/// Rung 2 from the published guardian sets.
///
/// The meta pull's `guardian_sets` is the **whole history** of the caller's
/// sets, append-only, one entry per `share_set_version` (0010). The set in
/// force is simply the highest version, so that is the only row this probe
/// reads: an earlier generation's `n` describes people who no longer hold a
/// share, and offering the rung on its strength would send somebody to ask
/// members who cannot answer.
///
/// [subjectUserId], when the caller knows its own id, restricts the history
/// to the user's own sets. The route already answers for `rf.user_id()`, so
/// the filter is belt-and-braces for the one failure that would matter: a
/// body that also carried a set this user is a *guardian of* would otherwise
/// read as "you have trusted members" to somebody who set none up.
///
/// **An empty history is [RecoveryRungOffer.unknown], not a refusal** — and
/// this is the correction of a real false denial, not caution. The read is
/// RLS-gated on certification and the device that reaches S11.6 is
/// uncertified *by construction*:
///
///   * `guardian_sets_select` (`0005_rls_and_grants.sql:357`) is
///     `using (rf.is_certified() and (subject_user_id = rf.user_id() or …))`,
///     and `rf.is_certified()` (`0005:21`) requires this device's own
///     `devices.status = 'certified'`;
///   * the recovering phone is 06 §5's "new phone, no old device", holding
///     nothing but its own keys (`0010:134`), and ADR 2026-09-05d §2 🔒 —
///     *uncertified devices see nothing but themselves* — names four things
///     such a device may read. `guardian_sets` is not one of them;
///   * `sync-meta` authenticates without requiring certification
///     (`sync-meta/index.ts:47`: "the ONE sync route a caller reaches without
///     a certified device"), and **RLS filters rather than errors** — so the
///     caller gets `200` with `guardian_sets: []`, which
///     `GuardiansApi.sets` reads off that same body
///     (`guardians_api.dart:309`).
///
/// So `[]` does not mean *you set nobody up*; on the one screen this probe is
/// drawn on it means *this device is not allowed to know*. Saying the former
/// to a locked-out person who has five trusted members is the sentence that
/// makes them stop trying — the false denial 04 §7.3 and this seam's 🔒
/// forbid. Rung 3 may say no for the opposite reason, stated in the same
/// breath by the same schema: `recovery_sheets_select`
/// (`0011_recovery_sheet.sql:117`) is "deliberately NOT gated on
/// rf.is_certified()", so `no_sheet` really is the server answering.
///
/// The honest consequence is that [RecoveryRungBlocked.noTrustedMembers] is
/// unreachable from this probe: nothing an uncertified device can read
/// distinguishes an empty set-history from one it was filtered out of.
/// Settling it needs one bit the server does not expose yet — reported as an
/// open item, never guessed here.
RecoveryRungProbe trustedMembersProbe(
  GuardiansApi guardians, {
  String? subjectUserId,
}) => () async {
  final sets = [
    for (final s in await guardians.sets())
      if (subjectUserId == null || s.subjectUserId == subjectUserId) s,
  ];
  if (sets.isEmpty) {
    // Nothing was learned — see the RLS note above. Not a refusal, and not
    // available either: this device asked a question it is not cleared to
    // have answered.
    return const RecoveryRungOffer.unknown(RecoveryRung.trustedMembers);
  }
  final inForce = sets.reduce(
    (a, b) => b.shareSetVersion > a.shareSetVersion ? b : a,
  );
  // Is the row in force one this build can read at all? `n` is the size the
  // 0010 trigger bounded to 2..5 and `k` the quorum it stored; a row outside
  // that is a row the server could not have written, so this build did not
  // understand the body it got.
  //
  // It is therefore **unknown, not blocked** — and the difference is the whole
  // point of the third state. `GuardianSetWire.fromJson` decodes an absent
  // `k` as `0` (guardians_api.dart:157), so a body that omitted one field
  // would otherwise have told somebody with five trusted members that they
  // set none up. The one thing this row does establish is that a set exists:
  // it was published, it has a subject and a version. Reporting
  // [RecoveryRungBlocked.noTrustedMembers] on the strength of an unreadable
  // `k` would be the false denial 04 §7.3 and the seam's 🔒 forbid, and
  // 'you set nobody up' is the sentence that makes a person stop trying.
  //
  // The exact quorum formula k = ⌈(n+1)/2⌉ is deliberately **not** re-checked
  // here. 0010's own ⚠️ SPEC records that reading as unsettled — 04 §7.3 states
  // the formula as the rule, ADR 2026-09-06 §2 as a default — and recovery
  // runs against the `k` the row carries (0010 pins it at open and
  // `rf.recovery_progress` reads `g.k`), not against a number this phone
  // recomputed. A probe that re-derived a rule the server owns would answer
  // `unknown` about a set that works.
  final readable =
      inForce.n >= 2 &&
      inForce.n <= 5 &&
      inForce.k >= 1 &&
      inForce.k <= inForce.n;
  return readable
      ? const RecoveryRungOffer.available(RecoveryRung.trustedMembers)
      : const RecoveryRungOffer.unknown(RecoveryRung.trustedMembers);
};

// ---------------------------------------------------------------------------
// Rung 3 — the recovery sheet (04 §7.4 🔒)
// ---------------------------------------------------------------------------

/// Rung 3 from `GET sync-meta/recovery/sheet` — the route that made this
/// ladder worth building.
///
/// [RecoveryApi.sheet] returns the caller's own current `sealed_RK_blob`, or
/// **null** when the server said `no_sheet`, and throws
/// [RecoveryApiFailure] for everything else. Those three outcomes are already
/// the three states this seam wants, which is why no other reading is taken:
///
///   * a **non-empty** blob → a sheet exists, and the rung is real;
///   * `no_sheet` → the server, which holds one blob per user, says this user
///     published none — a real source saying no;
///   * any refusal (offline, no session, rate limited, a body this build
///     cannot read) → unknown. **Especially `unauthorized`**: a phone without
///     a live session has learned nothing about whether a sheet exists, and
///     "you have no recovery sheet" is the sentence that makes somebody
///     holding one put it back in the drawer.
///
/// **A non-null wire is not by itself a sheet.** `RecoverySheetWire.fromJson`
/// decodes the blob through `decodeB64Url` (`recovery_api.dart:495`), which
/// answers `Uint8List(0)` both for an absent or empty `sealed_rk_blob` and
/// for a string it could not decode — it swallows the `FormatException` so
/// that no malformed byte is ever handed on as if it were ciphertext. A `200`
/// whose one load-bearing field is missing or unreadable is therefore exactly
/// the fourth case above — *a body this build cannot read* — and it is
/// [RecoveryRungOffer.unknown]. `available` there would offer S11.3 a sheet
/// the person would then be told did not work, and a sealed
/// `XChaCha20(RK, UMK_priv)` is never zero bytes (04 §7.4 🔒), so no real
/// sheet is ever denied by this check.
///
/// Only the blob is read this way. A missing `sheet_version` or `user_id`
/// does not unmake the ciphertext, and existence is the whole question.
///
/// It never opens the blob and never sees RK — existence is the whole
/// question (04 §7.4 🔒, 07 §5.6 🔒).
RecoveryRungProbe recoverySheetProbe(RecoveryApi api) => () async {
  final sheet = await api.sheet();
  if (sheet == null) {
    return const RecoveryRungOffer.blocked(
      RecoveryRung.recoverySheet,
      RecoveryRungBlocked.noRecoverySheet,
    );
  }
  if (sheet.blob.isEmpty) {
    return const RecoveryRungOffer.unknown(RecoveryRung.recoverySheet);
  }
  return const RecoveryRungOffer.available(RecoveryRung.recoverySheet);
};

// ---------------------------------------------------------------------------
// The map the composition root installs
// ---------------------------------------------------------------------------

/// The ladder S11.5 and S11.6 run on **in production** (04 §7.0 🔒, §7.1,
/// §7.2, §7.4 🔒; 13 §5 flow F11).
///
/// S11.6 is the screen that tells a person which way back in actually exists,
/// and until this slice it ran on `FakeRecoveryLadder` **in production** —
/// three rows, all cheerfully available, none of them asked. That was the
/// right call while rung 3 was unknowable: a ladder true about one rung and
/// invented about two would be worse than the fake. `GET
/// sync-meta/recovery/sheet` ended it (migration 0011), and rung 0 is this
/// device's own key store, so three of the four can be asked now.
///
/// Each probe reports from a real source or reports **unknown**; none of them
/// defaults to available.
///
/// **Rung 1 is not in the map, and that is the honest answer, not an
/// omission.** `DevicesRepository` has no server implementation in this build
/// and nothing here installs one, so this phone cannot find out whether the
/// user still holds another certified device. An absent probe is
/// [RecoveryRungOffer.unknown] by [LiveRecoveryLadder]'s own conversion, which
/// is the state 04 §7.2 deserves here: offering a phone the person may not
/// have would spend the one attempt they steeled themselves for, and denying
/// one they do have would make them stop trying.
///
/// **What draws an unknown rung is not this file's to fix, and it is not
/// fixed.** `s11_6_fork_screen.dart:216` renders an offer with no `blocked`
/// reason exactly as it renders an available one — a live row with no reason
/// line — so rung 1's honest `unknown` reaches the person as *Use another
/// phone*, a working door. The ladder may not lie its way around that: the
/// answer here stays `unknown`, and the screen is reported as an open item
/// for the lane that owns `features/recovery`.
///
/// ⚠️ SPEC: the only other signal that would settle rung 1 is the *derived
/// state* of an open recovery attempt — ADR 2026-09-05d §1 🔒 makes the server
/// wait 24 h precisely when the user still holds an active certified device,
/// so `waiting24h` versus `pending` answers the question. It is deliberately
/// not used: learning it means **opening a rung-2 attempt**, which walks the
/// ladder backwards, and a fork that asked the user's trusted members in
/// order to draw a row would be indefensible. Reported as an open item for
/// the owner; it is not implemented here under either reading.
/// **No `progress` producer exists in this build, and [progress] is the seam
/// for the one that will.** [RecoveryLadder.progressOf] is what S11.5 watches
/// while rung 0 runs, and nothing in the app constructs a
/// [RecoveryProgress] today outside this seam's own fake — the restore that
/// would count books back (unwrap the UMK, open each book, replay its
/// envelopes) lives in `core_crypto` and the ledger, neither of which this
/// file may reach. Passing nothing therefore leaves `progressOf` an empty
/// stream, and S11.5 reads a stream that closes with no finished reading as
/// *this rung did not get there* and offers the fork
/// (`s11_5_silent_restore_screen.dart:88`, `:107`).
///
/// That is the conservative outcome rather than the right one, and the
/// difference is recorded rather than papered over: a person whose wrapped
/// UMK *is* in the key store — rung 0 `available` — is still narrated a
/// failure, because the alternative is a count of books nothing restored.
/// Reported as an open item; the day a restore driver exists it is installed
/// here, in one argument, and no other file changes.
LiveRecoveryLadder buildRecoveryLadder({
  required KeyStore keys,
  required GuardiansApi guardians,
  required RecoveryApi recovery,
  Stream<RecoveryProgress> Function(RecoveryRung rung)? progress,
}) => LiveRecoveryLadder(
  progress: progress,
  probes: {
    // 04 §7.0 🔒 / §7.1 — asked of the same key store the app opens its
    // database with, and asked only for *presence*: no item is read, so no
    // key material is touched and no biometric prompt is raised to answer a
    // question about existence.
    RecoveryRung.platformKeySync: platformKeySyncProbe(keys),
    // 04 §7.3 — the meta pull's `guardian_sets`, through the same client
    // S11.1 and S11.2 use, so the set the fork counts and the set a recovery
    // attempts against can never come from two readings.
    RecoveryRung.trustedMembers: trustedMembersProbe(guardians),
    // 04 §7.4 🔒 — the same `RecoveryApi` instance `HttpRecoverySheet`
    // submits through. One door to `recovery/sheet`, one refusal table, one
    // rate limit (ADR 2026-09-05b §7's `sheet_flood`).
    RecoveryRung.recoverySheet: recoverySheetProbe(recovery),
  },
);
