// The trusted-members (guardian) seam — what S11.1 consumes (04 §7.3 🔒).
//
// It lives here, beside `closed_years.dart` / `key_store.dart` /
// `review_policy.dart`, for the same reason they do: it is a domain seam whose
// real implementation is *not* this feature's. The screen chooses people and a
// threshold; the split itself — Shamir over `UMK_priv`, one sealed `share_i`
// per guardian's UMK public key, `share_set_version`, the re-split on every
// change (04 §7.3 🔒) — happens in `core_crypto` behind a repository over the
// server routes, which is a later lane. Until that lands the app runs on
// [FakeGuardians], and every widget test in this feature runs against it.
//
// 🔒 **No share, no key material, ever crosses this seam.** 04 §7.3's shares
// are sealed to a guardian's public key and reconstructed only on the
// recovering device; 04 §7.6 🔒 names "guardian shares in reconstructable
// form" among the things never backed up anywhere, by any route. So the types
// below carry names, ceremony state and ids and nothing else — there is no
// accessor a screen could call for bytes, which is what keeps "S11.1 renders
// no key material" a property of the *contract* rather than of one screen's
// build method (the S0.5b precedent, 04 §7.4 / 07 §5.6).
//
// Vocabulary: the user-facing word is **Trusted member** (DESIGN-PACK
// vocabulary table, 01 §2) — "guardian" is the spec's word and stays in code
// and comments only.
import 'dart:async';

import 'package:flutter/widgets.dart';

/// The **k** of a k-of-n trusted-member set: `k = ⌈(n+1)/2⌉` (04 §7.3 🔒).
///
/// n = 2 → 2 · n = 3 → 2 · n = 4 → 3 · n = 5 → 3. Never shown to the user as a
/// formula: S11.1 states it as a sentence ("Any 2 of the 3 you choose…").
int guardianThreshold(int n) {
  if (n < guardianMinCount || n > guardianMaxCount) {
    throw ArgumentError.value(
      n,
      'n',
      'a trusted-member set is $guardianMinCount..$guardianMaxCount people '
          '(04 §7.3)',
    );
  }
  return (n + 2) ~/ 2;
}

/// Fewest trusted members a set may have (04 §7.3 🔒: n = 2..5).
const guardianMinCount = 2;

/// Most trusted members a set may have (04 §7.3 🔒: n = 2..5).
const guardianMaxCount = 5;

/// The set size S11.1 suggests: the **default 2-of-3** of 04 §7.3 🔒.
const guardianDefaultCount = 3;

/// Whether [n] is the shape that needs the typed confirmation of
/// ADR 2026-09-06 checklist 4 🔒 — 2-of-2, which has no loss tolerance *and*
/// needs both people to act.
///
/// It is permitted, but only behind a phrase the user types. A dismissible
/// warning must never be able to enable it.
bool guardianNeedsTypedConfirmation(int n) => n == 2;

/// Where one candidate stands in the **mutual** verification ceremony
/// (04 §7.3: "mutual ceremony per guardian"; 04 §6).
enum GuardianCeremony {
  /// Both directions verified — this person can hold a share.
  done,

  /// Started, not finished (one direction only, or a scan pending).
  started,

  /// Not begun. S11.1 offers *Meet them*.
  notStarted,
}

/// A member of the book who could hold a share (04 §7.3 setup).
@immutable
final class TrustedMemberCandidate {
  /// Creates a candidate.
  const TrustedMemberCandidate({
    required this.memberId,
    required this.name,
    this.ceremony = GuardianCeremony.notStarted,
    this.inviteId,
  });

  /// Stable member id — never displayed.
  final String memberId;

  /// The member's display name, as the book holds it.
  final String name;

  /// Where the mutual ceremony stands with this person.
  final GuardianCeremony ceremony;

  /// The ceremony invite to open for this person (S9.3), or null when no
  /// invite exists yet — then *Meet them* is disabled **with its reason**
  /// (13 §4.3), never silently absent.
  final String? inviteId;

  @override
  bool operator ==(Object other) =>
      other is TrustedMemberCandidate &&
      other.memberId == memberId &&
      other.name == name &&
      other.ceremony == ceremony &&
      other.inviteId == inviteId;

  @override
  int get hashCode => Object.hash(memberId, name, ceremony, inviteId);
}

/// Everything S11.1 renders. Carries no key material by construction.
@immutable
final class GuardianSetup {
  /// Creates a snapshot.
  const GuardianSetup({
    this.candidates = const [],
    this.chosenIds = const [],
    this.readOnly = false,
  });

  /// The people who could be chosen — the book's other members.
  final List<TrustedMemberCandidate> candidates;

  /// The member ids of the set currently in force (empty = never set up).
  final List<String> chosenIds;

  /// True for a role that may view but not change the set (13 §2.3.1 viewer;
  /// the S12.5 read-only pattern).
  final bool readOnly;

  /// Whether a set is in force.
  bool get isConfigured => chosenIds.length >= guardianMinCount;

  @override
  bool operator ==(Object other) =>
      other is GuardianSetup &&
      other.readOnly == readOnly &&
      _sameList(other.candidates, candidates) &&
      _sameList(other.chosenIds, chosenIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(candidates),
    Object.hashAll(chosenIds),
    readOnly,
  );
}

bool _sameList(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A failed read or save. Carries a plain reason, never a server code
/// (07 §1 rule 12).
final class GuardiansFailure implements Exception {
  /// Creates the failure.
  const GuardiansFailure([this.reason = '']);

  /// What failed, for logs only — never rendered raw.
  final String reason;

  @override
  String toString() => 'GuardiansFailure($reason)';
}

/// The seam S11.1 consumes.
///
/// [save] takes the chosen ids only. The **threshold is not a parameter**: it
/// is a function of n that 04 §7.3 🔒 fixes, so letting a caller pass one would
/// let a screen bug write a k the spec forbids. The implementation derives it
/// with [guardianThreshold].
abstract interface class GuardiansRepository {
  /// The latest snapshot, or null before the first load.
  GuardianSetup? get current;

  /// Snapshots as they change.
  Stream<GuardianSetup> watch();

  /// Loads (or reloads) the snapshot. Throws [GuardiansFailure] on failure.
  Future<void> refresh();

  /// Records the chosen set — the split, seal and upload of 04 §7.3 happen
  /// behind this call, never on the screen. Throws [GuardiansFailure].
  ///
  /// Implementations must reject a set outside [guardianMinCount]..
  /// [guardianMaxCount], and one containing a member whose ceremony is not
  /// [GuardianCeremony.done] — 04 §8.2 🔒: no key material is ever wrapped to
  /// an unverified fingerprint.
  Future<void> save(List<String> memberIds);
}

/// In-memory [GuardiansRepository] for tests and the Phase A shell.
class FakeGuardians implements GuardiansRepository {
  /// Creates the fake over [initial].
  FakeGuardians({
    GuardianSetup? initial,
    this.failRefresh = false,
    this.failSave = false,
  }) : _current = initial;

  GuardianSetup? _current;
  final _controller = StreamController<GuardianSetup>.broadcast();

  /// When true, [refresh] throws.
  bool failRefresh;

  /// When true, [save] throws.
  bool failSave;

  /// Every set handed to [save], oldest first.
  final List<List<String>> saved = [];

  @override
  GuardianSetup? get current => _current;

  @override
  Stream<GuardianSetup> watch() => _controller.stream;

  @override
  Future<void> refresh() async {
    if (failRefresh) throw const GuardiansFailure('refresh');
    final s = _current ?? const GuardianSetup();
    _current = s;
    _controller.add(s);
  }

  @override
  Future<void> save(List<String> memberIds) async {
    if (failSave) throw const GuardiansFailure('save');
    if (memberIds.length < guardianMinCount ||
        memberIds.length > guardianMaxCount) {
      throw const GuardiansFailure('size');
    }
    final byId = {
      for (final c
          in (_current?.candidates ?? const <TrustedMemberCandidate>[]))
        c.memberId: c,
    };
    for (final id in memberIds) {
      if (byId[id]?.ceremony != GuardianCeremony.done) {
        throw const GuardiansFailure('unverified');
      }
    }
    saved.add(List.unmodifiable(memberIds));
    final next = GuardianSetup(
      candidates: _current?.candidates ?? const <TrustedMemberCandidate>[],
      chosenIds: List.unmodifiable(memberIds),
      readOnly: _current?.readOnly ?? false,
    );
    _current = next;
    _controller.add(next);
  }

  /// Replaces the snapshot, as a server push would.
  void emit(GuardianSetup s) {
    _current = s;
    _controller.add(s);
  }

  /// Closes the stream.
  void dispose() => _controller.close();
}

/// Hands a [GuardiansRepository] down to S11.1.
class GuardiansScope extends InheritedWidget {
  /// Installs [repository] above [child].
  const GuardiansScope({
    super.key,
    required this.repository,
    required super.child,
  });

  /// The seam in force.
  final GuardiansRepository repository;

  /// The nearest repository, or null when none is installed.
  static GuardiansRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuardiansScope>()?.repository;

  @override
  bool updateShouldNotify(GuardiansScope old) => repository != old.repository;
}
