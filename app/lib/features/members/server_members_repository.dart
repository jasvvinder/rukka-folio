// The real [MembersRepository] (06 §1, §1.0 🔒, §1.1 🔒, §7 🔒): the tenant's
// people, built from the meta pull of 05 §5 and the invite routes of 06 §7,
// against the server that migration 0008 hardened.
//
// **The trust rule, which is the whole point.** `rf.membership_guard` now
// refuses to *believe* a `verification_events` row that no signed record
// backs (ADR 2026-09-05d §7 🔒, migration 0008). This client is never more
// credulous than that database. A membership reads `active` only when
//
//   1. a `verification_events` row says `verified` for that person, **and**
//   2. that row names a `source_record_id`, **and**
//   3. that record is in this tenant, of kind `verification_event`, **and**
//   4. the record's own payload says the same subject, verifier, method and
//      result the row claims, **and**
//   5. the chain verifies — sig → device cert → ceremony-verified UMK → not
//      revoked at this `seq` (04 §3.4; the injected [RecordBelief]).
//
// Anything less and the membership stays `joined_pending_verification`. A
// server that says *"she was verified"* without the signed record is exactly
// the attack ADR 2026-09-05d §7 removes, and a client that displayed the
// green tick on the server's word alone would put it straight back.
//
// The one membership that becomes `active` without a ceremony is the tenant's
// founder, who has nobody to verify them (06 §5) — recognised here the way
// the server recognises it (`records.ts` bootstrap): a believed
// `membership_status` record naming that same user, authored by a device of
// that same user. ⚠️ SPEC: the server also requires it to be the *first*
// membership of the tenant, which a client reading one pull cannot re-derive;
// it is safe to omit because `rf.membership_guard` refuses a second
// unceremonied `active` (`ceremony_required`), so a row citing such a record
// can only have come from the founding write — and belief still demands a
// ceremony-verified UMK for the author in this tenant, so nothing is
// trusted that the reader had not already verified by hand.
//
// Two things this file deliberately cannot know, because the product cannot:
//   * **whom an invite is for** — the server holds an HMAC of the number and
//     nothing else (ADR 2026-09-05c §4), so an invited row is named only by
//     the contact card on the device that sent it ([MemberDirectory]);
//   * **what a designation means** — it is a display label and is never
//     consulted by any permission check (06 §1.0 🔒 Option B). Capability is
//     the per-book role plus its limit, and the limit is integer paise.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sync_engine/sync_engine.dart'
    show
        EnvelopeGuard,
        MetaResponse,
        RecordVerified,
        WireBookRole,
        WireSignedRecord;

import 'members_api.dart';
import 'members_repository.dart';

/// Whether this device believes a signed record: signature → device cert →
/// ceremony-verified UMK → not revoked at this `seq` (04 §3.4; ADR
/// 2026-09-05b §1). Deliberately a seam and deliberately required — a
/// repository with no way to check a chain must believe nothing, not
/// everything.
typedef RecordBelief = bool Function(WireSignedRecord record);

/// Belief through the sync engine's production guard.
RecordBelief guardBelief(EnvelopeGuard guard) =>
    (record) => guard.checkRecord(record) is RecordVerified;

/// Believes nothing — the posture of a device that has not verified anybody
/// yet. Every membership then reads as pending, which is the truth.
bool believeNothing(WireSignedRecord record) => false;

/// What **this device** knows about people, and no server does: the display
/// names it learned in a ceremony or from its own contact book, and the
/// numbers it itself invited.
///
/// Names are not the server's to hold (06 §9.1 keeps a display name per user,
/// but the invitee of an unaccepted invite has no user row at all — ADR
/// 2026-09-05c §4), so a second admin's screen legitimately shows
/// *"Invited by Amrit · awaiting join"* and no name (ADR 2026-09-05f §G 🔒).
abstract class MemberDirectory {
  /// Display name for a user id, or null when this device does not know it.
  String? nameOf(String userId);

  /// Display name for an invite this device sent, or null.
  String? inviteeNameOf(String inviteId);

  /// The number this device invited, for 06 §7's one-tap re-invite. Null on
  /// every other device — and re-invite is then not this phone's to offer.
  /// Never logged, never uploaded, never part of a record.
  String? inviteePhoneOf(String inviteId);

  /// Remembers an invite this device just sent.
  Future<void> rememberInvitee({
    required String inviteId,
    required String phoneE164,
    String? name,
  });
}

/// In-memory directory — the Phase A shell and tests.
final class InMemoryMemberDirectory implements MemberDirectory {
  /// Creates a directory over optional seed data.
  InMemoryMemberDirectory({
    Map<String, String>? names,
    Map<String, ({String phone, String? name})>? invitees,
  }) : _names = {...?names},
       _invitees = {...?invitees};

  final Map<String, String> _names;
  final Map<String, ({String phone, String? name})> _invitees;

  @override
  String? nameOf(String userId) => _names[userId];

  @override
  String? inviteeNameOf(String inviteId) => _invitees[inviteId]?.name;

  @override
  String? inviteePhoneOf(String inviteId) => _invitees[inviteId]?.phone;

  @override
  Future<void> rememberInvitee({
    required String inviteId,
    required String phoneE164,
    String? name,
  }) async {
    _invitees[inviteId] = (phone: phoneE164, name: name);
  }
}

/// Signs a structural fact on this certified device (ADR 2026-09-05b §1 🔒:
/// *"every transition and every role/limit/designation change is a signed
/// record authored on a certified admin device"*).
///
/// The author encodes the payload itself, so the bytes it signs are exactly
/// the bytes that travel — unknown fields included (rule 6).
abstract class MembersRecordAuthor {
  /// 16 bytes from the platform CSPRNG — 06 §7's 128-bit ceremony nonce.
  Uint8List nonce16();

  /// Signs [payload] as a record of [kind] for [tenantId] and returns the
  /// wire map the routes take (`{id, suite_version, tenant_id, kind,
  /// payload_json, author_device_id, author_sig, hlc}`).
  Future<Map<String, Object?>> sign({
    required String tenantId,
    required String kind,
    required Map<String, Object?> payload,
  });
}

/// Record kinds this feature authors (⚠️ WIRE `_shared/registry.ts`
/// RECORD_KINDS; migration 0008 added `invite`).
abstract final class MembersRecordKind {
  /// 06 §7's invite — payload `{roles, nonce}` and **no** identifier of the
  /// invitee (0008 ⚠️ SPEC: the admin's device cannot compute `invitee_hmac`,
  /// the HMAC key is the server's).
  static const String invite = 'invite';

  /// Per-book role and limit (06 §1.1).
  static const String bookRole = 'book_role';

  /// Display label only — never a permission (06 §1.0 🔒).
  static const String designation = 'designation';

  /// Who verified whom, by which method (ADR 2026-09-05d §7).
  static const String verificationEvent = 'verification_event';

  /// A membership transition (06 §7).
  static const String membershipStatus = 'membership_status';
}

/// Ceremony methods that verify **a person into a tenant** (04 §6.4).
///
/// ⚠️ SPEC: the `verification_events.method` check also allows
/// `device_link`, which is one user linking their own second device (04
/// §9.1) — not a membership ceremony. Conservative reading: a `device_link`
/// event does not make anybody an active member, so it is not believed here.
const Set<String> _membershipCeremonyMethods = {'qr_in_person', 'code_remote'};

/// Membership statuses on the wire (03 §2.1, 06 §7).
abstract final class _Status {
  static const invited = 'invited';
  static const pending = 'joined_pending_verification';
  static const active = 'active';
  static const blocked = 'blocked';
  static const removed = 'removed';
}

/// The real repository. One instance per tenant: 06 §1.1 🔒 keeps roles
/// per book and access tokens free of any tenant, so the tenant is the
/// client's scope and every row of another tenant in the same pull is
/// dropped here.
final class ServerMembersRepository implements MembersRepository {
  /// Creates the repository.
  ///
  /// [believes] is the trust rule; there is no default, because a repository
  /// that cannot check a chain must believe nothing (see [believeNothing]).
  /// [unknownVerifierName] and [someoneToMeetName] are localized strings the
  /// integrator passes in (ARB `members.verified.someone` and
  /// `members.pending_books.someone`) for the case where a ceremony is
  /// believed but this device does not know the other person's name.
  ServerMembersRepository({
    required MembersApi api,
    required this.tenantId,
    required this.userId,
    required RecordBelief believes,
    required String unknownVerifierName,
    required String someoneToMeetName,
    String? Function(String bookId)? bookName,
    MemberDirectory? directory,
    MembersRecordAuthor? author,
    TenantType tenantType = TenantType.family,
    DateTime Function()? clock,
    int maxPages = 50,
  }) : _server = api,
       _belief = believes,
       _unknownVerifier = unknownVerifierName,
       _someoneToMeet = someoneToMeetName,
       _bookName = bookName ?? ((_) => null),
       _directory = directory ?? InMemoryMemberDirectory(),
       _signer = author,
       _type = tenantType,
       _clock = clock ?? DateTime.now,
       _pageCap = maxPages;

  final MembersApi _server;
  final RecordBelief _belief;
  final String _unknownVerifier;
  final String _someoneToMeet;
  final String? Function(String bookId) _bookName;
  final MemberDirectory _directory;
  final MembersRecordAuthor? _signer;
  final TenantType _type;
  final DateTime Function() _clock;
  final int _pageCap;

  /// The tenant this instance shows.
  final String tenantId;

  /// The signed-in user (06 §1: one number, one human, one account).
  final String userId;

  final _controller = StreamController<MembersSnapshot>.broadcast();
  MembersSnapshot? _current;

  /// This device's own contact knowledge, for the screens that need it.
  MemberDirectory get directory => _directory;

  @override
  MembersSnapshot? get current => _current;

  @override
  Stream<MembersSnapshot> watch() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _controller.stream;
  }

  void _emit(MembersSnapshot s) {
    _current = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();

  // ------------------------------------------------------------------ read

  @override
  Future<void> refresh() async {
    // A screen wants the whole picture, so every refresh starts at the
    // beginning of the meta feed rather than resuming a cursor: the cursor
    // is the sync engine's to keep, and a partial page would silently drop
    // people from the list.
    final pages = <MetaResponse>[];
    String? after;
    for (var i = 0; i < _pageCap; i++) {
      final page = await _server.pullMeta(after: after);
      pages.add(page);
      if (!page.hasMore || page.next == null || page.next == after) break;
      after = page.next;
    }
    _emit(_build(pages));
  }

  MembersSnapshot _build(List<MetaResponse> pages) {
    final now = _clock();

    // Signed records, by id — only this tenant's, and only those whose chain
    // this device actually believes. Everything below reads from here, so an
    // unbelieved record is indistinguishable from a missing one.
    final believed = <String, WireSignedRecord>{};
    for (final page in pages) {
      for (final r in page.signedRecords) {
        if (r.tenantId != tenantId) continue;
        if (!_belief(r)) continue;
        believed[r.id] = r;
      }
    }

    // devices → owner, so a self-authored founding record can be recognised.
    final deviceOwner = <String, String>{};
    for (final page in pages) {
      for (final d in page.devices) {
        deviceOwner[d.id] = d.userId;
      }
    }

    // Books of this tenant (06 §1.1: a role is per book, never global).
    final books = <String, TenantBook>{};
    for (final row in _extraRows(pages, 'books')) {
      if (row['tenant_id'] != tenantId) continue;
      final id = row['id'] as String?;
      if (id == null) continue;
      books[id] = TenantBook(id: id, name: _bookName(id) ?? '');
    }

    // Roles, per user, for this tenant's books only.
    final grants = <String, List<BookGrant>>{};
    for (final page in pages) {
      for (final r in page.bookRoles) {
        if (!books.containsKey(r.bookId)) continue;
        final role = _roleOf(r.role);
        if (role == null) continue; // `role: null` removed the row's grant
        final limit = r.limits?[WireBookRole.autoPostLimitPaise];
        (grants[r.userId] ??= []).add(
          BookGrant(
            bookId: r.bookId,
            role: role,
            // Money is integer paise end to end (rule 1): a non-integer here
            // is a wire fault, not a rounding opportunity.
            autoPostLimitPaise: limit is int
                ? limit
                : limit is String
                ? int.tryParse(limit)
                : null,
          ),
        );
      }
    }

    // Ceremonies this device believes, newest first per subject.
    final ceremonies = _believedCeremonies(pages, believed);

    final members = <Member>[];
    for (final page in pages) {
      for (final m in page.memberships) {
        if (m.tenantId != tenantId) continue;
        if (m.status == _Status.removed) continue;
        if (members.any((x) => x.id == m.userId)) continue;
        final ceremony = ceremonies[m.userId];
        final state = _stateOf(
          m.status,
          ceremony: ceremony,
          founding: _isFoundingMembership(
            pages,
            believed,
            deviceOwner,
            m.userId,
          ),
        );
        members.add(
          Member(
            id: m.userId,
            state: state,
            displayName: m.userId == userId
                ? null
                : _directory.nameOf(m.userId),
            designationLabel: _designationOf(believed, m.userId),
            grants: grants[m.userId] ?? const [],
            verification: state == MembershipState.active && ceremony != null
                ? Verification(
                    verifiedByName:
                        _directory.nameOf(ceremony.verifier) ??
                        _unknownVerifier,
                    method: ceremony.method,
                    on: ceremony.at,
                  )
                : null,
            isYou: m.userId == userId,
          ),
        );
      }
    }

    // Invites are not memberships: an invited person has no `user_id` yet —
    // that is the whole point of 06 §7's `invited` state — so the rows come
    // from the `invites` table and are keyed by the invite id.
    for (final row in _extraRows(pages, 'invites')) {
      if (row['tenant_id'] != tenantId) continue;
      final id = row['id'] as String?;
      final status = row['status'] as String?;
      if (id == null || status == null) continue;
      // accepted / revoked invites are gone from the list.
      if (status != 'sent' && status != 'expired') continue;
      final expiresAt = _msOrNull(row['expires_at']);
      // Lazy expiry, binding at read time exactly as the server binds it at
      // accept time (E-06-33) — a missed sweep never shows a live link.
      final expired =
          status == 'expired' || (expiresAt != null && !expiresAt.isAfter(now));
      members.add(
        Member(
          id: id,
          state: expired ? MembershipState.expired : MembershipState.invited,
          displayName: _directory.inviteeNameOf(id),
          grants: _grantsFromInviteRoles(row['roles'], books),
          invitedByName: _directory.nameOf(row['created_by'] as String? ?? ''),
          expiresOn: expiresAt,
        ),
      );
    }

    final yourRoles = {
      for (final g in grants[userId] ?? const <BookGrant>[]) g.bookId: g.role,
    };
    final me = _first(members.where((m) => m.isYou));
    final iAmActive = me?.state == MembershipState.active;

    return MembersSnapshot(
      tenantType: _type,
      books: books.values.toList(growable: false),
      members: members,
      pendingBooks: iAmActive
          ? const []
          : _pendingBooks(books, yourRoles, members),
      yourRoles: yourRoles,
      // Nothing here can be changed while my own membership is not active, or
      // while the tenant is frozen — a freeze refuses every push while reads
      // and exports continue (06 §8 🔒). S12.5's read-only pattern.
      readOnly: !iAmActive || _frozen(pages, now),
    );
  }

  /// The believed ceremony per subject: the newest `verified` event that
  /// clears all five conditions in this file's header.
  Map<String, ({String verifier, VerificationMethod method, DateTime at})>
  _believedCeremonies(
    List<MetaResponse> pages,
    Map<String, WireSignedRecord> believed,
  ) {
    final out =
        <String, ({String verifier, VerificationMethod method, DateTime at})>{};
    final at = <String, DateTime>{};
    for (final row in _extraRows(pages, 'verification_events')) {
      if (row['tenant_id'] != tenantId) continue;
      if (row['result'] != 'verified') continue;
      final subject = row['subject_user'] as String?;
      final verifier = row['verifier_user'] as String?;
      final method = row['method'] as String?;
      final when = _msOrNull(row['at']);
      if (subject == null || verifier == null || method == null) continue;
      if (!_membershipCeremonyMethods.contains(method)) continue;

      // (2) the row must name a record, (3) which must be one this device
      // believes, of the right kind, in this tenant …
      final recordId = row['source_record_id'] as String?;
      if (recordId == null) continue;
      final record = believed[recordId];
      if (record == null) continue;
      if (record.kind != MembersRecordKind.verificationEvent) continue;

      // … and (4) the record must itself say what the row claims. The row is
      // the server's copy; where the two differ, the signed bytes win.
      final payload = _payloadOf(record);
      if (payload['subject_user_id'] != subject) continue;
      if (payload['verifier_user_id'] != verifier) continue;
      if (payload['method'] != method) continue;
      if (payload['result'] != 'verified') continue;

      final previous = at[subject];
      if (when != null && previous != null && !when.isAfter(previous)) continue;
      out[subject] = (
        verifier: verifier,
        method: method == 'code_remote'
            ? VerificationMethod.codeRemote
            : VerificationMethod.qrInPerson,
        at: when ?? previous ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
      if (when != null) at[subject] = when;
    }
    return out;
  }

  /// Whether this user's membership is the tenant's founding one — see the
  /// file header's ⚠️ SPEC note.
  bool _isFoundingMembership(
    List<MetaResponse> pages,
    Map<String, WireSignedRecord> believed,
    Map<String, String> deviceOwner,
    String user,
  ) {
    for (final page in pages) {
      for (final m in page.memberships) {
        if (m.tenantId != tenantId || m.userId != user) continue;
        // `source_record_id` rides in the row but not in [WireMembership];
        // the record is found by what it says instead.
        for (final r in believed.values) {
          if (r.kind != MembersRecordKind.membershipStatus) continue;
          if (deviceOwner[r.authorDeviceId] != user) continue;
          final p = _payloadOf(r);
          if (p['user_id'] == user && p['status'] == _Status.active) {
            return true;
          }
        }
      }
    }
    return false;
  }

  MembershipState _stateOf(
    String status, {
    required ({String verifier, VerificationMethod method, DateTime at})?
    ceremony,
    required bool founding,
  }) => switch (status) {
    // The trust rule: `active` on the server's word alone is not believed —
    // the membership stays where the ceremony left it (C-05d-7).
    _Status.active when ceremony != null || founding => MembershipState.active,
    _Status.active => MembershipState.joinedPendingVerification,
    _Status.pending => MembershipState.joinedPendingVerification,
    _Status.blocked => MembershipState.blocked,
    _Status.invited => MembershipState.invited,
    _ => MembershipState.joinedPendingVerification,
  };

  /// The newest believed `designation` record for this user — a label, never
  /// a permission (06 §1.0 🔒). The server keeps no column for it.
  String? _designationOf(Map<String, WireSignedRecord> believed, String user) {
    String? label;
    var hlc = -1;
    for (final r in believed.values) {
      if (r.kind != MembersRecordKind.designation) continue;
      final p = _payloadOf(r);
      if (p['user_id'] != user) continue;
      if (r.hlc < hlc) continue;
      hlc = r.hlc;
      final value = p['designation_label'] ?? p['label'];
      label = value is String && value.isNotEmpty ? value : null;
    }
    return label;
  }

  List<BookGrant> _grantsFromInviteRoles(
    Object? roles,
    Map<String, TenantBook> books,
  ) {
    if (roles is! List) return const [];
    final out = <BookGrant>[];
    for (final entry in roles) {
      if (entry is! Map) continue;
      final bookId = entry['book_id'];
      final role = _roleOf(entry['role'] as String?);
      if (bookId is! String || role == null) continue;
      if (!books.containsKey(bookId)) continue;
      final limit = entry['auto_post_limit_paise'];
      out.add(
        BookGrant(
          bookId: bookId,
          role: role,
          autoPostLimitPaise: limit is int
              ? limit
              : limit is String
              ? int.tryParse(limit)
              : null,
        ),
      );
    }
    return out;
  }

  /// Shared books I hold a role in but cannot open until somebody verifies
  /// me — *"Meet Sunita to activate"* (06 §7, 07 §12 🔒).
  List<PendingBook> _pendingBooks(
    Map<String, TenantBook> books,
    Map<String, BookRole> yourRoles,
    List<Member> members,
  ) {
    final whoToMeet = _first(
      members.where(
        (m) =>
            !m.isYou &&
            m.state == MembershipState.active &&
            m.displayName != null,
      ),
    );
    final name = whoToMeet?.displayName ?? _someoneToMeet;
    return [
      for (final id in yourRoles.keys)
        if (books[id] != null)
          PendingBook(name: books[id]!.name, activateWithName: name),
    ];
  }

  bool _frozen(List<MetaResponse> pages, DateTime now) {
    for (final row in _extraRows(pages, 'tenant_freezes')) {
      if (row['tenant_id'] != tenantId) continue;
      if (row['lifted_at'] != null) continue;
      final expires = _msOrNull(row['expires_at']);
      if (expires == null || expires.isAfter(now)) return true;
    }
    return false;
  }

  // ----------------------------------------------------------------- write

  @override
  Future<void> setAutoPostLimit({
    required String memberId,
    required String bookId,
    required int? paise,
  }) async {
    final snapshot = _current;
    if (snapshot == null || !snapshot.adminOf(bookId)) {
      throw const MembersFailure(
        'not an admin of this book',
        MembersRefusal.notAdmin,
      );
    }
    final grant = _first(snapshot.members.where((m) => m.id == memberId))
        ?.grantFor(bookId);
    if (grant == null) {
      throw const MembersFailure(
        'no role in this book',
        MembersRefusal.badRecord,
      );
    }
    if (paise != null && paise < 0) {
      throw const MembersFailure(
        'limit is paise, never negative',
        MembersRefusal.badRecord,
      );
    }
    await _postOne(MembersRecordKind.bookRole, {
      'book_id': bookId,
      'user_id': memberId,
      'role': grant.role.name,
      // Integer paise or nothing (rule 1); null clears the limit.
      'auto_post_limit_paise': paise,
    });
    await refresh();
  }

  @override
  Future<void> invite(InviteRequest request) async {
    final snapshot = _current;
    // 06 §1.0 🔒 verbs table: invite is admin-only. The client refuses before
    // the number leaves the phone; the server refuses again (`not_admin`).
    if (snapshot != null && !snapshot.youAreAdminSomewhere) {
      throw const MembersFailure(
        'invite is admin-only',
        MembersRefusal.notAdmin,
      );
    }
    if (request.grants.isEmpty) {
      throw const MembersFailure(
        'a role in at least one book',
        MembersRefusal.badRecord,
      );
    }
    final author = _requireAuthor();
    final record = await author.sign(
      tenantId: tenantId,
      kind: MembersRecordKind.invite,
      // {roles, nonce} — and no identifier of the invitee, because this
      // device cannot compute `invitee_hmac` and a record carrying the number
      // would be broadcast to every member (0008 ⚠️ SPEC).
      payload: {
        'roles': [
          for (final g in request.grants)
            {
              'book_id': g.bookId,
              'role': g.role.name,
              if (g.autoPostLimitPaise != null)
                'auto_post_limit_paise': g.autoPostLimitPaise,
            },
        ],
        'nonce': _b64url(author.nonce16()),
      },
    );
    final issued = await _server.issueInvite(
      record: record,
      phoneE164: request.phoneE164,
    );
    // The contact card stays here, on the device that picked it (ADR
    // 2026-09-05f §G 🔒) — it is also the only thing that can re-invite.
    await _directory.rememberInvitee(
      inviteId: issued.inviteId,
      phoneE164: request.phoneE164,
    );
    await refresh();
  }

  @override
  Future<void> reinvite(String memberId) async {
    final phone = _directory.inviteePhoneOf(memberId);
    if (phone == null) {
      // A second admin sees the invite but not the contact card — 06 §7 and
      // ADR 2026-09-05f §G 🔒. Re-inviting is the sending phone's to do.
      throw const MembersFailure(
        'this phone does not hold that contact',
        MembersRefusal.unknownInvitee,
      );
    }
    final snapshot = _current;
    final grants =
        (snapshot == null
            ? null
            : _first(snapshot.members.where((m) => m.id == memberId))
                  ?.grants) ??
        const <BookGrant>[];
    // Issuing again to the same number revokes the live invite and mints a
    // new one, so only the newest link can be accepted (06 §7, E-06-35).
    await invite(InviteRequest(phoneE164: phone, grants: grants));
  }

  /// Accepts an invite addressed to this phone. Returns the membership status
  /// the server moved to — `joined_pending_verification`, never `active`.
  ///
  /// ADR 2026-09-05d §9 🔒: a joiner whose number does not match the invite,
  /// and a joiner naming an invite that does not exist, get the **same**
  /// [MembersRefusal.inviteNotForYou]. The link alone admits nobody, and the
  /// refusal tells nobody whether the link was real.
  Future<String> acceptInvite(String inviteId) =>
      _server.acceptInvite(inviteId);

  /// The invites addressed to this device's OTP-verified number (06 §7).
  Future<List<InviteOffer>> myInvites() => _server.myInvites();

  MembersRecordAuthor _requireAuthor() {
    final author = _signer;
    if (author == null) {
      throw const MembersFailure(
        'no signing device',
        MembersRefusal.unauthorized,
      );
    }
    return author;
  }

  Future<void> _postOne(String kind, Map<String, Object?> payload) async {
    final author = _requireAuthor();
    final record = await author.sign(
      tenantId: tenantId,
      kind: kind,
      payload: payload,
    );
    final results = await _server.postRecords([record]);
    final note = results.isEmpty ? 'rejected:empty' : results.first;
    if (note.startsWith('rejected:')) {
      throw MembersFailure(
        note,
        refusalOf(note.substring('rejected:'.length), 400),
      );
    }
  }

  // ---------------------------------------------------------------- helpers

  /// Rows of a meta table the sync engine carries through untouched (rule 6).
  Iterable<Map<String, Object?>> _extraRows(
    List<MetaResponse> pages,
    String table,
  ) sync* {
    for (final page in pages) {
      final rows = page.extra[table];
      if (rows is! List) continue;
      for (final row in rows) {
        if (row is Map) yield row.cast<String, Object?>();
      }
    }
  }

  Map<String, Object?> _payloadOf(WireSignedRecord r) {
    try {
      final decoded = jsonDecode(utf8.decode(r.payloadJson));
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    } on FormatException {
      return const {};
    }
  }

  static BookRole? _roleOf(String? wire) => switch (wire) {
    'admin' => BookRole.admin,
    'head' => BookRole.head,
    'member' => BookRole.member,
    'operator' => BookRole.operator,
    'viewer' => BookRole.viewer,
    _ => null,
  };

  static DateTime? _msOrNull(Object? v) => v is num
      ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
      : v is String
      ? DateTime.tryParse(v)
      : null;

  static T? _first<T>(Iterable<T> xs) {
    for (final x in xs) {
      return x;
    }
    return null;
  }

  static String _b64url(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
