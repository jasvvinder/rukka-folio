// The members feature's seam to the tenant's memberships (06 §1.1), the
// invitation state machine (06 §7) and the permanent verification log
// (04 §6.4). Phase A: S9 / S9.1 run against [FakeMembersRepository]; the real
// one lands with the sync/server lanes, where each of these changes is a
// signed record authored on a certified admin device (06 §7, ADR 2026-09-05b
// §1) and the server's rows are only its copy.
//
// ⚠️ WIRE — the whole interface is this lane's. `memberships`, `book_roles`
// and `invites` shape it at integration. The only money here is the per-book
// auto-post limit, and it is integer paise end to end (CLAUDE.md rule 1).
//
// Two things this seam deliberately cannot express, because the product
// deliberately cannot know them:
//   * **Whose invite it is.** An invited person's name lives only on the
//     device that picked the contact — the server holds an HMAC of the number
//     and nothing else (ADR 2026-09-05c §4). So [Member.displayName] is
//     nullable, and a second admin's screen reads *"Invited by Amrit ·
//     awaiting join"* (ADR 2026-09-05f §G 🔒).
//   * **A designation as power.** [Member.designationLabel] is a display
//     string and is never consulted by anything here; capability is
//     [BookGrant.role] plus its limit, and nothing else (06 §1.0 🔒 Option B).
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'members_api.dart' show InviteOffer;

export 'members_api.dart' show InviteOffer;

/// The five stored roles (06 §1.1). One per book, never global; this is the
/// entire permission system (06 §1.0 🔒).
enum BookRole { admin, head, member, operator, viewer }

/// Where a person is in the invitation & membership state machine (06 §7).
enum MembershipState {
  /// Invited; the link expires 7 days after it was sent.
  invited,

  /// Installed and OTP-verified: their personal book works immediately, the
  /// shared books wait for the ceremony.
  joinedPendingVerification,

  /// Ceremony passed, book keys wrapped.
  active,

  /// The 7 days ran out — one-tap re-invite (07 §12).
  expired,

  /// Ceremony mismatch: blocked plus a security event. An admin unblocks only
  /// after investigation, and a new invite is required.
  blocked,
}

/// How a membership was verified (04 §6.4). Direction is never mentioned.
enum VerificationMethod {
  /// `qr_in_person` — the default ceremony.
  qrInPerson,

  /// `code_remote` — the code read aloud on a voice/video call.
  codeRemote,
}

/// Which designation table 01 §2 publishes for this tenant (06 §1.1 types).
enum TenantType { family, businessGroup, organization }

/// One book of the tenant (03 §1). Names are plaintext on this device only.
@immutable
final class TenantBook {
  const TenantBook({required this.id, required this.name});

  final String id;
  final String name;
}

/// One person's capability in one book: the stored role and the auto-post
/// limit above which an entry still posts but is flagged (02 §3, 06 §1.0).
@immutable
final class BookGrant {
  const BookGrant({
    required this.bookId,
    required this.role,
    this.autoPostLimitPaise,
  });

  final String bookId;
  final BookRole role;

  /// Integer paise, or null for no limit (CLAUDE.md rule 1 — never a double).
  final int? autoPostLimitPaise;

  BookGrant copyWith({
    BookRole? role,
    int? autoPostLimitPaise,
    bool clearLimit = false,
  }) => BookGrant(
    bookId: bookId,
    role: role ?? this.role,
    autoPostLimitPaise: clearLimit
        ? null
        : (autoPostLimitPaise ?? this.autoPostLimitPaise),
  );
}

/// The permanent log line of 04 §6.4: who verified whom, by which method, on
/// which day — visible to the tenant's members forever.
@immutable
final class Verification {
  const Verification({
    required this.verifiedByName,
    required this.method,
    required this.on,
  });

  final String verifiedByName;
  final VerificationMethod method;
  final DateTime on;
}

/// One row of S9.
@immutable
final class Member {
  const Member({
    required this.id,
    required this.state,
    this.displayName,
    this.designationLabel,
    this.grants = const [],
    this.verification,
    this.invitedByName,
    this.expiresOn,
    this.isYou = false,
  });

  final String id;

  /// Null where this device does not hold the contact — see the file header
  /// (ADR 2026-09-05c §4, ADR 2026-09-05f §G 🔒).
  final String? displayName;

  /// Display-only label (06 §1.0 🔒). Never a permission.
  final String? designationLabel;

  final MembershipState state;
  final List<BookGrant> grants;

  /// The 04 §6.4 log entry, once the ceremony has happened.
  final Verification? verification;

  /// Who sent the invite, for the *"Invited by Amrit · awaiting join"* row.
  final String? invitedByName;

  /// When an `invited` link stops working (06 §7: 7 days).
  final DateTime? expiresOn;

  final bool isYou;

  /// The grant for [bookId], or null when they have no access to that book
  /// (no `book_roles` row).
  BookGrant? grantFor(String bookId) {
    for (final g in grants) {
      if (g.bookId == bookId) return g;
    }
    return null;
  }
}

/// A shared book the signed-in user can see but not yet open — the invitee
/// experience of 07 §12 / 06 §7: the personal book works immediately, shared
/// books are named placeholders until someone verifies them.
@immutable
final class PendingBook {
  const PendingBook({required this.name, required this.activateWithName});

  final String name;

  /// The member to meet — *"Meet Sunita to activate"* (07 §12 🔒).
  final String activateWithName;
}

/// What S9 renders.
@immutable
final class MembersSnapshot {
  const MembersSnapshot({
    this.tenantType = TenantType.family,
    this.books = const [],
    this.members = const [],
    this.pendingBooks = const [],
    this.yourRoles = const {},
    this.readOnly = false,
  });

  /// Decides which 01 §2 designation table S9.1 suggests.
  final TenantType tenantType;

  /// The tenant's books, in display order.
  final List<TenantBook> books;

  /// Everyone in the tenant, including the signed-in user.
  final List<Member> members;

  /// Shared books awaiting this user's own ceremony (07 §12 invitee bullet).
  final List<PendingBook> pendingBooks;

  /// The signed-in user's own role per book — what decides which actions are
  /// drawn (13 §2.3.1). A missing book means no access to it.
  final Map<String, BookRole> yourRoles;

  /// S12.5 pattern: the surface is shown, nothing can be changed.
  final bool readOnly;

  /// Invite / remove / roles / limits are **admin only** (06 §1.0 verbs
  /// table, 13 §7) — admin of any one book of the tenant is enough to invite,
  /// because the grant grid is per book.
  bool get youAreAdminSomewhere => yourRoles.values.contains(BookRole.admin);

  /// Whether the signed-in user may change grants in [bookId].
  bool adminOf(String bookId) => yourRoles[bookId] == BookRole.admin;

  MembersSnapshot copyWith({
    TenantType? tenantType,
    List<TenantBook>? books,
    List<Member>? members,
    List<PendingBook>? pendingBooks,
    Map<String, BookRole>? yourRoles,
    bool? readOnly,
  }) => MembersSnapshot(
    tenantType: tenantType ?? this.tenantType,
    books: books ?? this.books,
    members: members ?? this.members,
    pendingBooks: pendingBooks ?? this.pendingBooks,
    yourRoles: yourRoles ?? this.yourRoles,
    readOnly: readOnly ?? this.readOnly,
  );
}

/// What S9.1 sends. The phone number is plaintext **only** on the way out:
/// the server keeps an HMAC of it and sends nothing (ADR 2026-09-25 §2,
/// amending ADR 2026-09-05c §4) — the inviter's own phone sends the link.
/// Nothing here is ever logged (CLAUDE.md rule 4).
@immutable
final class InviteRequest {
  const InviteRequest({
    required this.phoneE164,
    required this.grants,
    this.designationLabel,
  });

  final String phoneE164;

  /// One grant per book they get access to; books they get no access to are
  /// simply absent.
  final List<BookGrant> grants;

  /// Optional display label (06 §1.0 🔒 Option B) — never a permission.
  final String? designationLabel;
}

/// The link an invitee opens, for one invite id — or null while no format is
/// ruled.
///
/// ⚠️ SPEC (M11-INV2): the client has **no invite-link format**. ADR 2026-09-15
/// §4 puts invite deep links on `rukkafolio.com`, and the S0.9 route reads an
/// `invite` query parameter (`onboarding_routes.dart`'s ⚠️ WIRE note sketches
/// `https://…/join/<id>`), but no spec fixes the external path, so none is
/// invented here. Production binds none until the owner rules it; the share
/// panel then offers **nothing to send** and says why (`invite.nolink.*`) — it
/// never names a join path the spec does not have (13 §3.2 S0.9 enters only by
/// deep link). The link is not a secret and admits nobody on its own (ADR
/// 2026-09-05d §9 🔒).
typedef InviteLinkOf = Uri? Function(String inviteId);

/// What *Send invite* (and *Invite again*) produced: the invite row, and the
/// link to hand the inviter's share sheet (ADR 2026-09-25 §2). No number and
/// no figure rides here.
@immutable
final class CreatedInvite {
  const CreatedInvite({required this.inviteId, this.link});

  /// The new invite row.
  final String inviteId;

  /// The link for [inviteId], or null while no link format is ruled
  /// ([InviteLinkOf]).
  final Uri? link;
}

/// Why a members call failed. Named, because 07 §1 rule 6 forbids a dead end
/// and a screen cannot offer the right way out of an unnamed failure — and
/// because ADR 2026-09-05d §9 🔒 needs [inviteNotForYou] to mean *exactly*
/// what the server means by it: a wrong number **or** an invite that does not
/// exist, indistinguishable on purpose, so the client is no oracle either.
enum MembersRefusal {
  /// The request never reached a response. The server said nothing.
  offline,

  /// No session, or the session is not allowed here (06 §4).
  unauthorized,

  /// Invite / roles / limits are admin-only (06 §1.0 verbs table 🔒).
  notAdmin,

  /// This link is not for this phone — or there is no such link
  /// (ADR 2026-09-05d §9 🔒: the two are one answer).
  inviteNotForYou,

  /// The 7-day window closed (06 §7). One-tap re-invite is the way out.
  inviteExpired,

  /// Already accepted, revoked or superseded by a newer invite (06 §7).
  inviteNotLive,

  /// This exact signed record was already applied — a retry, not a new
  /// invite (06 §7's one-tap re-invite must not fire twice).
  recordReplayed,

  /// The action needed a signed record and none backed it
  /// (ADR 2026-09-05b §1).
  noRecord,

  /// This phone does not hold the contact card for that invite, so it cannot
  /// re-invite: the number never left the device that sent it
  /// (ADR 2026-09-05c §4, ADR 2026-09-05f §G 🔒).
  unknownInvitee,

  /// The number is not E.164.
  badPhone,

  /// The record's shape or payload was refused.
  badRecord,

  /// No such tenant for this caller.
  unknownTenant,

  /// The tenant is frozen: pushes are refused, reads and exports continue
  /// (06 §8 🔒).
  tenantFrozen,

  /// This build is below the server's floor (05 §7).
  upgradeRequired,

  /// The plan's seats are full — `invited` + `joined_pending_verification` +
  /// `active` already fill it (ADR 2026-09-05g §6 🔒; server `seat_cap`).
  /// Terminal: asking again cannot make room; the way on is S12.1 Plans.
  seatCap,

  /// The plan's changes of member for the year are used up — the rolling
  /// 2 × seats distinct members (ADR 2026-09-05g §6 🔒; `seat_rotation_cap`).
  /// Terminal, like [seatCap].
  seatRotationCap,

  /// The plan's business books are full (ADR 2026-09-05g §2 🔒; `book_cap`).
  /// Terminal, like [seatCap].
  bookCap,

  /// Anything else the server said. Never guessed into a friendlier name.
  server,
}

/// The three hard caps of ADR 2026-09-05g §2 / §6 🔒, as the members feature
/// names them. A cap refusal is **terminal**: the screen says what is full
/// and offers S12.1 Plans, never a retry of the same request (the server
/// already holds that signed record — a re-send of it would be answered
/// `record_replayed` / `acked` without anything happening).
extension MembersRefusalPlanCap on MembersRefusal {
  /// Whether this refusal is one of the plan's hard caps.
  bool get isPlanCap =>
      this == MembersRefusal.seatCap ||
      this == MembersRefusal.seatRotationCap ||
      this == MembersRefusal.bookCap;
}

/// Thrown by repository calls that failed; screens show the error state and
/// keep the retry path (07 §1 rule 6 — no dead ends).
final class MembersFailure implements Exception {
  const MembersFailure([
    this.message = '',
    this.reason = MembersRefusal.server,
  ]);

  final String message;

  /// What went wrong, in the vocabulary a screen can act on.
  final MembersRefusal reason;

  @override
  String toString() => 'MembersFailure(${reason.name}: $message)';
}

/// What S9 and S9.1 need.
abstract class MembersRepository {
  /// Current snapshot, then every change. Emits the current value on listen.
  Stream<MembersSnapshot> watch();

  /// Latest snapshot without subscribing; null until the first load.
  MembersSnapshot? get current;

  /// (Re)loads; throws [MembersFailure].
  Future<void> refresh();

  /// Sets (or, with null, removes) the auto-post limit for one member in one
  /// book — integer paise. Admin only; the screen never offers it otherwise
  /// (06 §1.0 verbs table).
  Future<void> setAutoPostLimit({
    required String memberId,
    required String bookId,
    required int? paise,
  });

  /// Creates an invite (06 §7 `invited`). The server sends nothing; the
  /// caller hands [CreatedInvite.link] to the inviter's share sheet (ADR
  /// 2026-09-25 §2).
  Future<CreatedInvite> invite(InviteRequest request);

  /// One-tap re-invite of an `expired` row (07 §12): a fresh invite, whose
  /// link the inviter sends again.
  Future<CreatedInvite> reinvite(String memberId);

  /// The link of an invite that already exists — an `invited` row is keyed by
  /// its invite id — so S9's *Resend* can reopen the share sheet for a live
  /// invite after S9.1 is gone (ADR 2026-09-25 §2). Mints nothing, writes
  /// nothing; null while no link format is ruled ([InviteLinkOf]).
  Uri? inviteLink(String inviteId);

  /// The joiner's side (06 §7): the invites addressed to this device's
  /// OTP-verified number, and those it accepted, inside the 7-day window —
  /// each row with its `nonce` (ADR 2026-09-25b §2) and the invite's own
  /// `status` (M11-INV1 repair; ⚠️ SPEC desk 36). Empty means *no invitation
  /// this phone may accept*, never *no such invite* (ADR 2026-09-05d §9 🔒).
  /// Throws [MembersFailure].
  Future<List<InviteOffer>> myInvites();

  /// Accepts an invite addressed to this phone. Returns the **membership**
  /// status the server moved to — `joined_pending_verification`, never
  /// `active`: the ceremony grants that (06 §7 🔒). A number the invite was
  /// not for and an id that does not exist are the same
  /// [MembersRefusal.inviteNotForYou] (ADR 2026-09-05d §9 🔒). Throws
  /// [MembersFailure].
  Future<String> acceptInvite(String inviteId);
}

/// In-memory fake for tests and the Phase A shell.
class FakeMembersRepository implements MembersRepository {
  FakeMembersRepository({MembersSnapshot? initial, this.linkOf})
    : _current = initial;

  /// The link each created invite carries; null → no link format.
  final InviteLinkOf? linkOf;

  var _issued = 0;

  CreatedInvite _created() {
    final id = 'invite-${++_issued}';
    return CreatedInvite(inviteId: id, link: linkOf?.call(id));
  }

  final _controller = StreamController<MembersSnapshot>.broadcast();
  MembersSnapshot? _current;

  /// Next call to any method throws this once, then clears.
  MembersFailure? failNext;

  /// Limit changes seen, newest last.
  final limits = <({String memberId, String bookId, int? paise})>[];

  /// Invites sent.
  final invites = <InviteRequest>[];

  /// Member ids passed to [reinvite].
  final reinvited = <String>[];

  /// What [myInvites] returns — the joiner's rows, as the server would list
  /// them.
  List<InviteOffer> offered = const [];

  /// What [acceptInvite] returns for an id in [offered]: the membership
  /// status, never `active` (06 §7 🔒).
  String acceptStatus = 'joined_pending_verification';

  /// Invite ids [acceptInvite] accepted, in order.
  final acceptedInvites = <String>[];

  /// How many times [myInvites] ran.
  int myInvitesCalls = 0;

  /// What [refresh] loads when it runs (null keeps the current snapshot).
  MembersSnapshot? onRefresh;

  @override
  MembersSnapshot? get current => _current;

  set current(MembersSnapshot? s) {
    _current = s;
    if (s != null) _controller.add(s);
  }

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Stream<MembersSnapshot> watch() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _controller.stream;
  }

  @override
  Future<void> refresh() async {
    _maybeFail();
    final next = onRefresh;
    if (next != null) current = next;
  }

  @override
  Future<void> setAutoPostLimit({
    required String memberId,
    required String bookId,
    required int? paise,
  }) async {
    _maybeFail();
    limits.add((memberId: memberId, bookId: bookId, paise: paise));
    final c = _current;
    if (c == null) return;
    current = c.copyWith(
      members: [
        for (final m in c.members)
          if (m.id != memberId)
            m
          else
            Member(
              id: m.id,
              state: m.state,
              displayName: m.displayName,
              designationLabel: m.designationLabel,
              grants: [
                for (final g in m.grants)
                  if (g.bookId != bookId)
                    g
                  else
                    BookGrant(
                      bookId: g.bookId,
                      role: g.role,
                      autoPostLimitPaise: paise,
                    ),
              ],
              verification: m.verification,
              invitedByName: m.invitedByName,
              expiresOn: m.expiresOn,
              isYou: m.isYou,
            ),
      ],
    );
  }

  @override
  Future<CreatedInvite> invite(InviteRequest request) async {
    _maybeFail();
    invites.add(request);
    return _created();
  }

  @override
  Future<CreatedInvite> reinvite(String memberId) async {
    _maybeFail();
    reinvited.add(memberId);
    return _created();
  }

  @override
  Uri? inviteLink(String inviteId) => linkOf?.call(inviteId);

  @override
  Future<List<InviteOffer>> myInvites() async {
    myInvitesCalls++;
    _maybeFail();
    return List.unmodifiable(offered);
  }

  /// An id not in [offered] is refused the way the server refuses it — one
  /// [MembersRefusal.inviteNotForYou] for a wrong number and a missing id
  /// alike (ADR 2026-09-05d §9 🔒), so a caller tested on the fake cannot
  /// learn to tell them apart.
  @override
  Future<String> acceptInvite(String inviteId) async {
    _maybeFail();
    if (!offered.any((o) => o.inviteId == inviteId)) {
      throw const MembersFailure(
        'invite not for you',
        MembersRefusal.inviteNotForYou,
      );
    }
    acceptedInvites.add(inviteId);
    return acceptStatus;
  }

  Future<void> dispose() => _controller.close();
}

/// Provides the repository to the members screens. Integration wraps the app
/// in one; absent, screens fall back to an empty [FakeMembersRepository].
class MembersRepositoryScope extends InheritedWidget {
  const MembersRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final MembersRepository repository;

  static final _fallback = FakeMembersRepository(
    initial: const MembersSnapshot(),
  );

  /// The nearest repository, or an empty fake.
  static MembersRepository of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MembersRepositoryScope>()
          ?.repository ??
      _fallback;

  @override
  bool updateShouldNotify(MembersRepositoryScope old) =>
      repository != old.repository;
}
