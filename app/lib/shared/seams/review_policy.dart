// The auto-post-limit seam (02 §3 🔒, 03 §3.3 rule 5 🔒, 06 §1.1).
//
// `auto_post_limit_paise` lives in `book_roles` — **plaintext server
// metadata, not an envelope** — so the projector may never read it (03 §3.3
// rule 2/5 🔒). The *authoring* client evaluates it at save time and writes
// `review_required` + `review_limit_paise` into the entry payload; every
// reader then re-checks the flag against that limit
// (`checkUniversalInvariants` → `ViolationKind.reviewFlagMissing`). That is
// the whole reason this seam exists on the **write** path and nowhere else.
//
// It lives here, beside `closed_years.dart` / `key_store.dart`, because
// `shared/ledger` may not import `features/` and the only source of the limit
// is `features/members` (`MembersRepository` → `Member.grantFor(bookId)` →
// `BookGrant.autoPostLimitPaise`). `features/members/members_review_policy.dart`
// is the adapter; [noReviewPolicy] is what the app shipped before it existed
// and what every test that does not care gets by default.
//
// Async, not a synchronous read off a snapshot: the members snapshot is
// loaded from the server after sign-in and is `null` until the first load
// (`MembersRepository.current`), while `LocalLedger`'s verbs are already
// `Future`s that await `chartOf` before drafting. A `Future<int?>` therefore
// lets the adapter wait for (or answer from) the snapshot without any verb
// changing shape, and keeps the door open for a limit read from the database
// later. Every post reads it **once**, at save time — the limit in force at
// that entry's HLC (03 §3.3 rule 5) — and a later change to the grant never
// re-flags an entry that is already in the book.

/// The limit above which an entry still posts but is **flagged for review**
/// (02 §3: a review threshold, never a gate).
///
/// `null` means *no limit applies to this member in this book*, and therefore
/// **no review is required**. 06 §1.1 types `auto_post_limit_paise` as a
/// nullable column and does not say what its absence means; 02 §3 🔒 calls it
/// "a review threshold, not a gate" and names the two cases where nothing is
/// ever flagged — *a member in their own personal book*, and (§7.2 item 1 🔒)
/// *a book with exactly one member*. Nothing anywhere says a missing limit
/// reviews everything.
///
/// ⚠️ SPEC: the opposite reading would be defensible for the inter-book case
/// alone — 02 §6 says the half where *the actor lacks posting rights* carries
/// the flag, and "no `book_roles` row" is exactly no rights. It is not taken,
/// for two reasons that are about damage rather than taste: this app is
/// offline-first, so *no grant known here* is indistinguishable from *metadata
/// not pulled yet*, and a flag raised on absent metadata cannot be cleared by
/// its author (02 §7.2 item 1 🔒) and **blocks month close** (02 §8 step 3 🔒)
/// in exactly the single-member book where nobody can clear it. So: never drop
/// a flag the limit demands, never invent one from metadata that is missing.
/// Settling it properly needs the seam to distinguish *no grant* from *no
/// limit*, which `BookGrant` can already express and this contract cannot —
/// reported to the owner.
abstract interface class ReviewPolicy {
  /// The auto-post limit in force for [userId] in [bookId], integer paise, or
  /// null for *no limit applies* (CLAUDE.md rule 1 — never a double).
  ///
  /// Read once per post. Must not throw: a policy that cannot answer answers
  /// null, because a failed lookup must never be reported as *reviewed*.
  Future<int?> autoPostLimitPaise({
    required String bookId,
    required String userId,
  });
}

/// The policy the app shipped before the members adapter existed: no limit
/// anywhere, so every entry posts unflagged. `LocalLedger`'s default, so every
/// existing caller and test compiles and behaves unchanged.
const ReviewPolicy noReviewPolicy = _NoReviewPolicy();

final class _NoReviewPolicy implements ReviewPolicy {
  const _NoReviewPolicy();

  @override
  Future<int?> autoPostLimitPaise({
    required String bookId,
    required String userId,
  }) async => null;
}

/// In-memory policy for tests and the Phase A shell: limits by
/// `(bookId, userId)`, everything else unlimited.
class FakeReviewPolicy implements ReviewPolicy {
  /// Creates the fake. [limits] is keyed by `(bookId, userId)`; a key that is
  /// absent — or present with a null value — is *no limit*.
  FakeReviewPolicy({Map<({String bookId, String userId}), int?>? limits})
    : limits = {...?limits};

  /// The limits in force, mutable so a test can change one **after** an entry
  /// is posted and assert the posted entry is not re-flagged.
  final Map<({String bookId, String userId}), int?> limits;

  /// Every lookup this policy answered, oldest first — so a test can pin that
  /// one post reads the limit exactly **once**.
  final reads = <({String bookId, String userId})>[];

  /// Sets (or, with null, clears) one limit.
  void setLimit({required String bookId, required String userId, int? paise}) {
    limits[(bookId: bookId, userId: userId)] = paise;
  }

  @override
  Future<int?> autoPostLimitPaise({
    required String bookId,
    required String userId,
  }) async {
    reads.add((bookId: bookId, userId: userId));
    return limits[(bookId: bookId, userId: userId)];
  }
}

/// A policy that delegates to one installed later — the composition root's
/// late binding (`bootstrap.dart`), the same arrangement as
/// `LocalLedger.onOwnCert`.
///
/// `LocalLedger` is constructed *before* `ServerMembersRepository`, and must
/// be: the repository is built from `identity.tenantId` / `identity.userId`,
/// which exist only once the ledger has bootstrapped. Reordering is therefore
/// impossible, so the ledger is handed this holder and the real policy is set
/// into it a few lines later, in the same synchronous stretch of `bootstrap`
/// — before `runApp`, so no screen can post through the empty window.
///
/// Until then it answers *no limit*, which is [noReviewPolicy]'s answer and
/// the app's behaviour before this seam existed. It never answers *reviewed*
/// on missing information.
class LateReviewPolicy implements ReviewPolicy {
  /// Creates the holder, optionally with a policy already installed.
  LateReviewPolicy([this.policy]);

  /// The policy in force, or null while none is installed.
  ReviewPolicy? policy;

  @override
  Future<int?> autoPostLimitPaise({
    required String bookId,
    required String userId,
  }) async {
    final installed = policy;
    if (installed == null) return null;
    return installed.autoPostLimitPaise(bookId: bookId, userId: userId);
  }
}
