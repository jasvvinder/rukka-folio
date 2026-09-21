// The live producer behind `shared/seams/guardians.dart` — S11.1 against the
// real 04 §7.3 🔒 routes instead of [FakeGuardians].
//
// The seam is **settled**: the screen and its widget tests run on it and
// nothing here changes a line of it. This file implements
// [GuardiansRepository] over `guardians_api.dart`, and its whole job is to be
// the one place where a set is *assembled* — who may hold a share, what
// generation it belongs to, and what the server is then told.
//
// ============================================================================
// THE FOUR RULES THIS FILE EXISTS TO HOLD
// ============================================================================
//
// **1. A share is sealed to a verified key or it is not sealed at all.**
// CLAUDE.md rule 5 / 04 §8.2 🔒. The only way into [GuardianShareSealer] is a
// [VerifiedGuardian], which needs a [VerifiedUmkPublic] — a type `core_crypto`
// mints solely inside `ceremony.dart`, after a fingerprint matched. So a
// chosen member is turned into a guardian *only* when [VerifiedUmkSource]
// answers for them: a green tick in the roster is not enough, because a
// ceremony record this device merely read is a claim, and a claim is not a
// key. When the source answers null the save refuses — plainly, and without
// uploading anything.
//
// **2. No share and no key material crosses the seam, in either direction.**
// [GuardianSetup] carries names, ids and ceremony state; there is no
// accessor on it a screen could call for bytes. The split itself is the
// injected [GuardianShareSealer]'s (`guardian_sealing.dart`), so `UMK_priv`
// is never a field of this file, and the sealed blobs it returns are
// forwarded once and dropped. 04 §7.6 🔒 — "guardian shares in
// reconstructable form" are never backed up by any route — is kept by there
// being no route here that could.
//
// **3. The generation is the server's history + 1, and never a guess.**
// 0010 `rf.guardian_set_guard` 🔒 accepts exactly `max(share_set_version) + 1`
// for the subject, which is what stops an older set being slipped in behind a
// live one (ADR 2026-09-06 §3). This file therefore derives the next version
// from the history it last read and, when the server refuses the draft, does
// **not** retry at the next number up: a version that moved means another of
// this user's devices published a set in the meantime, and re-publishing over
// it would quietly retire a set the user may have just made. It re-reads and
// reports instead.
//
// **4. The read side is a history, not a row.** A guardian set is never
// rewritten; a change is a new version. The set in force is the highest
// version in `guardian_sets`, recomputed on every refresh and never cached
// across one — the same discipline ADR 2026-09-06 §3 gives k-of-n counting.
import 'dart:async';

import 'package:sync_engine/sync_engine.dart' show VerifiedUmkSource;

import '../seams/guardians.dart';
import 'guardians_api.dart';
import 'recovery_api.dart';

export 'guardians_api.dart';

/// One person this device could name as a guardian, as the app's own member
/// list knows them.
///
/// ⚠️ This is a **port**, not a reach into `features/members`: the roster is
/// that feature's fact, and the composition root adapts it. Nothing here
/// imports a feature.
final class GuardianCandidateRow {
  /// Creates the row.
  const GuardianCandidateRow({
    required this.userId,
    required this.name,
    required this.ceremony,
    this.inviteId,
    this.isYou = false,
  });

  /// The member's user id — the `guardian_user_id` the write route takes.
  ///
  /// Member id and user id are the same string in this app (`bootstrap`'s
  /// `memberName` matches `Member.id` against a user id from the trust
  /// store), which is why the seam's `memberIds` reach the wire unchanged.
  final String userId;

  /// Their display name, or the *someone in this book* string — never an id
  /// (ADR 2026-09-05c §4).
  final String name;

  /// Where the mutual ceremony stands (04 §7.3 "mutual ceremony per
  /// guardian"). A roster's word, and on its own never enough to seal —
  /// see rule 1 in the header.
  final GuardianCeremony ceremony;

  /// The ceremony invite S11.1 opens for this person, or null.
  final String? inviteId;

  /// True for the signed-in user. A guardian is somebody else (0010
  /// `guardian_is_subject`), so this row is offered to nobody.
  final bool isYou;
}

/// The roster, with whether this user may change the set at all.
final class GuardianRoster {
  /// Creates the roster.
  const GuardianRoster({this.candidates = const [], this.readOnly = false});

  /// Everyone who could be chosen, the signed-in user included (they are
  /// filtered out here, not by the caller).
  final List<GuardianCandidateRow> candidates;

  /// True for a role that may view but not change the set (13 §2.3.1).
  final bool readOnly;
}

/// Where the roster comes from. Injected by the composition root.
typedef GuardianRosterSource = Future<GuardianRoster> Function();

/// What a sealer is asked for: one fresh split of `UMK_priv` into
/// `guardians.length` shares of generation [shareSetVersion], threshold [k],
/// each share sealed to its guardian's verified key (04 §7.3).
///
/// Every save is a **re-split**: shares are never reused across generations,
/// which is what `share_set_version` in the share header enforces on the way
/// back (`GuardianShareSet.reconstruct` refuses a mixed set).
final class GuardianSplitRequest {
  /// Creates the request.
  GuardianSplitRequest({
    required this.shareSetVersion,
    required this.k,
    required List<VerifiedGuardian> guardians,
  }) : guardians = List.unmodifiable(guardians);

  /// The generation being published.
  final int shareSetVersion;

  /// `⌈(n+1)/2⌉`, derived by [guardianThreshold] (04 §7.3 🔒).
  final int k;

  /// Who gets a share, each addressed by a ceremony-verified key.
  final List<VerifiedGuardian> guardians;

  /// How many shares.
  int get n => guardians.length;
}

/// Splits `UMK_priv` and seals one share per guardian (04 §7.3).
///
/// Supplied by the composition root because the split is `core_crypto`'s and
/// the UMK is the ledger's — so no key material is ever a field of this file
/// (the `RecoveryResealer` precedent, `recovery_seams.dart`).
typedef GuardianShareSealer = Future<List<SealedGuardianShare>> Function(
  GuardianSplitRequest request,
);

/// [GuardiansRepository] over the 0010 routes — S11.1's live producer.
///
/// Refusal reasons ([GuardiansFailure.reason]) are for this device's own
/// handling and logs, never for the screen to render raw (07 §1 rule 12):
/// `read_only` · `size` · `duplicate` · `unknown` · `self` · `unverified` ·
/// `no_sealer` · `seal` · `rejected` · `offline` · `unauthorized` ·
/// `server` · `shape`.
final class ServerGuardians implements GuardiansRepository {
  /// Creates the repository over [api].
  ///
  /// [roster] is the member list port; [verified] is the one door to a
  /// ceremony-verified key (`LedgerKeyMaterial` in production, which answers
  /// for this user alone); [sealer] performs the split. With no [sealer] the
  /// repository still *reads* — the set in force is shown — and refuses to
  /// publish rather than pretending.
  ServerGuardians({
    required GuardiansApi api,
    required GuardianRosterSource roster,
    required VerifiedUmkSource verified,
    GuardianShareSealer? sealer,
  }) : _api = api,
       _roster = roster,
       _verified = verified,
       _sealer = sealer;

  final GuardiansApi _api;
  final GuardianRosterSource _roster;
  final VerifiedUmkSource _verified;
  final GuardianShareSealer? _sealer;

  final _controller = StreamController<GuardianSetup>.broadcast();
  GuardianSetup? _current;
  List<GuardianCandidateRow> _rows = const [];

  /// The highest generation the last refresh saw, or 0 when none exists.
  /// Re-read every refresh, never carried forward on its own (header rule 4).
  int _version = 0;

  @override
  GuardianSetup? get current => _current;

  @override
  Stream<GuardianSetup> watch() => _controller.stream;

  @override
  Future<void> refresh() async {
    final sets = await _read();
    final roster = await _rosterOrThrow();
    // The signed-in user is kept in `_rows` and left out of the candidates:
    // S11.1 must not offer them, and `save` must be able to answer *self*
    // rather than *unknown* when a caller names them anyway (0010
    // `guardian_is_subject` — a guardian is somebody else).
    _rows = List.unmodifiable(roster.candidates);

    // The set in force is the highest version — a set is never rewritten, so
    // the history's top row is the whole answer (0010 `current_guardian_set`).
    GuardianSetWire? live;
    for (final s in sets) {
      if (live == null || s.shareSetVersion > live.shareSetVersion) live = s;
    }
    _version = live?.shareSetVersion ?? 0;

    final next = GuardianSetup(
      candidates: [
        for (final c in _rows)
          if (!c.isYou)
            TrustedMemberCandidate(
              memberId: c.userId,
              name: c.name,
              ceremony: c.ceremony,
              inviteId: c.inviteId,
            ),
      ],
      // The server's members verbatim, including anyone this device holds no
      // roster row for: dropping them would under-report the set in force and
      // make a live 3-of-5 read as *not set up*.
      chosenIds: List.unmodifiable(live?.guardianUserIds ?? const <String>[]),
      readOnly: roster.readOnly,
    );
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> save(List<String> memberIds) async {
    if (_current == null) await refresh();
    if (_current?.readOnly ?? false) throw const GuardiansFailure('read_only');

    // Shape first, before a single key is touched (04 §7.3 🔒 n = 2..5).
    if (memberIds.length < guardianMinCount ||
        memberIds.length > guardianMaxCount) {
      throw const GuardiansFailure('size');
    }
    if (memberIds.toSet().length != memberIds.length) {
      // n distinct people, or the quorum is not the quorum it claims: two
      // shares to one person makes k-of-n an (k−1)-of-(n−1) in their hands.
      throw const GuardiansFailure('duplicate');
    }

    final rows = {for (final c in _rows) c.userId: c};
    final guardians = <VerifiedGuardian>[];
    for (final id in memberIds) {
      final row = rows[id];
      if (row == null) throw const GuardiansFailure('unknown');
      if (row.isYou) throw const GuardiansFailure('self');
      if (row.ceremony != GuardianCeremony.done) {
        throw const GuardiansFailure('unverified');
      }
      // Rule 5 🔒 — the roster says the ceremony happened; only this answers
      // with a key, and only a passed ceremony ever produced one.
      final key = _verified.verifiedUmkOf(id);
      if (key == null) throw const GuardiansFailure('unverified');
      guardians.add(VerifiedGuardian(userId: id, umk: key));
    }

    final sealer = _sealer;
    if (sealer == null) throw const GuardiansFailure('no_sealer');

    // k is 04 §7.3's function of n and nobody's choice — the seam derives it,
    // the database checks it, and no caller passes one.
    final k = guardianThreshold(guardians.length);
    final version = _version + 1;
    final shares = await sealer(
      GuardianSplitRequest(
        shareSetVersion: version,
        k: k,
        guardians: guardians,
      ),
    );
    _checkCover(shares, guardians);

    try {
      await _api.publish(shareSetVersion: version, k: k, shares: shares);
    } on RecoveryApiFailure catch (e) {
      // A refused draft is never retried a version up: the version moves when
      // another of this user's devices published a set, and publishing over
      // it would retire a set the user may have just made (header rule 3).
      // The snapshot is re-read so the screen shows what is actually in force.
      if (e.refusal == RecoveryRefusal.badRequest) {
        await _refreshQuietly();
        throw const GuardiansFailure('rejected');
      }
      throw GuardiansFailure(_reasonOf(e.refusal));
    }
    // The published set is read back rather than assumed: the server files it
    // for `rf.user_id()`, and its history is the only thing that decides what
    // the next generation may be.
    await refresh();
  }

  /// Every share accounted for, addressed to the person it is filed under.
  ///
  /// A sealer that returned four shares for five guardians, two shares for
  /// one person, or a share sealed to somebody else's key would otherwise
  /// publish a set that cannot reach its own quorum — a k-of-n that silently
  /// needs more than k. [SealedGuardianShare] already refuses a blob whose
  /// recipient is not its guardian's fingerprint; this is the cover check.
  void _checkCover(
    List<SealedGuardianShare> shares,
    List<VerifiedGuardian> guardians,
  ) {
    if (shares.length != guardians.length) {
      throw const GuardiansFailure('seal');
    }
    final want = {for (final g in guardians) g.userId: g.umk.fingerprint};
    final seen = <String>{};
    for (final s in shares) {
      final fingerprint = want[s.guardian.userId];
      if (fingerprint == null || !seen.add(s.guardian.userId)) {
        throw const GuardiansFailure('seal');
      }
      if (s.guardian.umk.fingerprint != fingerprint) {
        throw const GuardiansFailure('seal');
      }
    }
  }

  Future<List<GuardianSetWire>> _read() async {
    final List<GuardianSetWire> sets;
    try {
      sets = await _api.sets();
    } on RecoveryApiFailure catch (e) {
      throw GuardiansFailure(_reasonOf(e.refusal));
    }
    // One subject, or this device cannot tell whose set it is holding — and
    // whose set it is decides what may be published next. A body naming two
    // subjects is a shape error, not something to pick a winner from.
    final subjects = <String>{
      for (final s in sets)
        if (s.subjectUserId.isNotEmpty) s.subjectUserId,
    };
    if (subjects.length > 1) throw const GuardiansFailure('shape');
    // Two rows at the same generation would make "the highest version" an
    // ambiguous answer; append-only history has exactly one row per version.
    final versions = <int>{};
    for (final s in sets) {
      if (!versions.add(s.shareSetVersion)) {
        throw const GuardiansFailure('shape');
      }
    }
    return sets;
  }

  Future<GuardianRoster> _rosterOrThrow() async {
    try {
      return await _roster();
    } on GuardiansFailure {
      rethrow;
    } on Exception catch (_) {
      throw const GuardiansFailure('roster');
    }
  }

  Future<void> _refreshQuietly() async {
    try {
      await refresh();
    } on GuardiansFailure {
      // The publish already failed; a failed re-read must not replace its
      // reason with a second one.
    }
  }

  static String _reasonOf(RecoveryRefusal r) => switch (r) {
    RecoveryRefusal.offline => 'offline',
    RecoveryRefusal.unauthorized => 'unauthorized',
    RecoveryRefusal.upgradeRequired => 'upgrade_required',
    RecoveryRefusal.badRequest => 'rejected',
    _ => 'server',
  };

  /// Closes the stream.
  void dispose() {
    unawaited(_controller.close());
  }
}
