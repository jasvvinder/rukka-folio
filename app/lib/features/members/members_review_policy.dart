// The members adapter for the auto-post-limit seam (02 §3 🔒, 03 §3.3 rule 5
// 🔒, 06 §1.1).
//
// `shared/ledger` may not import `features/`, so `LocalLedger` measures its
// own entries through `ReviewPolicy` (`shared/seams/review_policy.dart`) and
// this is the one implementation that answers from real `book_roles` metadata:
// `MembersRepository.current` → `Member.grantFor(bookId)` →
// `BookGrant.autoPostLimitPaise`, integer paise end to end (CLAUDE.md rule 1).
//
// Nothing here reads an envelope, and nothing the projector reads passes
// through here: `auto_post_limit_paise` is plaintext server metadata, and the
// whole point of 03 §3.3 rule 5 🔒 is that only the *authoring* client ever
// consults it, so two devices with different cached role metadata still
// compute an identical close-hash.
import 'dart:async';

import '../../shared/seams/review_policy.dart';
import 'members_repository.dart';

/// The auto-post limit of the signed-in user's own `book_roles` grant.
///
/// **Never blocks a save.** It answers from the snapshot the repository
/// already holds and never awaits the network: 02 §3 🔒 promises the entry
/// posts the moment it is saved, so a limit lookup that waited on a server
/// round trip would turn a threshold into the gate that section forbids. A
/// snapshot that has not loaded yet therefore answers *no limit* — the same
/// conservative rule the seam states: never drop a flag the limit demands,
/// never invent one from metadata that is missing.
///
/// Because *not loaded yet* would otherwise be permanent on a device whose
/// owner never opens S9, the first miss starts **one** background
/// [MembersRepository.refresh] — fire-and-forget, every failure swallowed
/// (offline is the normal case), so the next post is measured. It is started
/// at most once per instance, so a hundred posts are never a hundred
/// requests.
class MembersReviewPolicy implements ReviewPolicy {
  /// Creates the adapter over [repository].
  ///
  /// [warmOnMiss] false disables the one background refresh — for a test, or
  /// for a shell that loads the snapshot itself.
  MembersReviewPolicy(this.repository, {this.warmOnMiss = true});

  /// Where the grants come from.
  final MembersRepository repository;

  /// Whether a first miss may start one background refresh.
  final bool warmOnMiss;

  bool _warmed = false;

  /// True once the one background refresh has been started (test seam).
  bool get warmStarted => _warmed;

  @override
  Future<int?> autoPostLimitPaise({
    required String bookId,
    required String userId,
  }) async {
    final snapshot = repository.current;
    if (snapshot == null) {
      _warm();
      return null;
    }
    BookGrant? mine;
    var membersOfBook = 0;
    for (final member in snapshot.members) {
      final grant = member.grantFor(bookId);
      if (grant == null) continue;
      if (member.id == userId) mine = grant;
      // Only a member who is **active** can clear anything: an `invited` row
      // carries the grant it will get (06 §7) and holds no key yet, and a
      // member awaiting their ceremony cannot open the book at all.
      if (member.state == MembershipState.active) membersOfBook++;
    }
    if (mine != null) {
      // 02 §7.2 item 1 🔒: "If a book has exactly one member, no flag is
      // raised (there is nothing to check and nobody to check it)" — and
      // 02 §3 🔒 "A member in their own personal book is never flagged",
      // which is the same book counted a different way. Without this, an
      // admin who set a limit on themselves in a one-member book would raise
      // a flag only another member could clear (item 1) and which blocks
      // month close (02 §8 step 3 🔒) — a deadlock with no way out.
      if (membersOfBook < 2) return null;
      return mine.autoPostLimitPaise;
    }
    // No membership row for this user — which is *no grant known here*, not
    // *no rights*: this device may simply not have pulled the metadata (05
    // §5). Flagging on that absence would raise a flag its author may not
    // clear (02 §7.2 item 1 🔒) and would block that book's month close
    // (02 §8 step 3 🔒). See the ⚠️ SPEC on [ReviewPolicy].
    _warm();
    return null;
  }

  void _warm() {
    if (_warmed || !warmOnMiss) return;
    _warmed = true;
    unawaited(repository.refresh().catchError((Object _) {}));
  }
}
