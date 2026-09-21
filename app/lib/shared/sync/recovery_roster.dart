// Who the trusted members of one recovery attempt are (S11.2's rows;
// 04 §7.3 🔒, migration 0010).
//
// It is a [RecoveryRosterSource] over `GuardiansApi.sets()` — the same
// `guardian_sets` history S11.1 reads — and it exists as its own file because
// it holds one rule and holds it alone:
//
// **A roster is asked for by generation, and only the generation asked for is
// answered.** 0010 pins `share_set_version` when an attempt opens, so a user
// who re-splits their set while a recovery is in flight has two generations in
// the history at once. Answering with "the latest" would draw today's people
// beside yesterday's decisions: a member who really did approve would vanish
// from the screen (they are not in the new set) and somebody who was never
// asked would appear, waiting, in their place. Both are falsehoods on the one
// screen whose job is to say who acted. So an unknown generation answers with
// **nobody**, and the attempt then shows k, n and its state with no named
// rows — which under-reports and never misattributes (`recovery_seams.dart`
// rule 2).
//
// It carries no key material: `GuardianSetMemberWire.umkPubEd` is a public
// key and is deliberately not read here. What crosses into [TrustedApprover]
// is a user id, a name and, where the device happens to hold one, a phone
// number — exactly what R2.2 draws.
import '../seams/recovery_ladder.dart';
import 'guardians_api.dart';
import 'recovery_seams.dart';

/// Resolves a guardian's user id to the name this device holds for them.
///
/// Names are never the server's (ADR 2026-09-05c §4 🔒), so the composition
/// root adapts the member list; a user this device cannot name still gets a
/// row, because a set of three people must show three rows.
typedef GuardianNameSource = String Function(String userId);

/// Resolves a guardian's phone number, or null when this device holds none.
///
/// R2.2's *Call* link is drawn only where one exists — a number is never
/// guessed and never the server's (ADR 2026-09-05c §4 🔒).
typedef GuardianPhoneSource = String? Function(String userId);

/// A [RecoveryRosterSource] over the published guardian-set history.
final class PinnedGuardianRoster {
  /// Creates the source.
  const PinnedGuardianRoster({
    required GuardiansApi api,
    required GuardianNameSource nameOf,
    GuardianPhoneSource? phoneOf,
  }) : _api = api,
       _nameOf = nameOf,
       _phoneOf = phoneOf;

  final GuardiansApi _api;
  final GuardianNameSource _nameOf;
  final GuardianPhoneSource? _phoneOf;

  /// The members of generation [shareSetVersion], in the order the route sent
  /// them — which is the order S11.2 draws, and is not re-sorted by anything
  /// here (a screen that reordered rows as decisions landed would move the
  /// name under the reader's thumb).
  ///
  /// Every row comes back in its resting state: *who is in the set* is all
  /// this source knows. Whether a person approved is the decision rows' to
  /// say, and `HttpGuardianRecovery` applies them (rule 2).
  Future<List<TrustedApprover>> call(int shareSetVersion) async {
    final List<GuardianSetWire> sets;
    try {
      sets = await _api.sets();
    } on RecoveryApiFailure catch (_) {
      // A roster this device could not read is nobody named — never a guess,
      // and never an error that would hide the attempt's own k/n/state.
      return const [];
    }
    final seen = <String>{};
    final out = <TrustedApprover>[];
    for (final set in sets) {
      // Exact generation only. The `>=`/"nearest" readings are both a way of
      // showing people who were not asked.
      if (set.shareSetVersion != shareSetVersion) continue;
      for (final m in set.members) {
        final id = m.guardianUserId;
        // An append-only history holds one row per version, but a body that
        // repeated a member would otherwise draw them twice and let one
        // decision tick two rows.
        if (id.isEmpty || !seen.add(id)) continue;
        out.add(
          TrustedApprover(
            memberId: id,
            name: _nameOf(id),
            phone: _phoneOf?.call(id),
          ),
        );
      }
    }
    return out;
  }
}
