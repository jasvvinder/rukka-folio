// The joiner's side of the invitation (06 §7 🔒, ADR 2026-09-05d §9 🔒).
//
// S0.9 is the only screen that reads this. `features/members` already owns the
// *inviter's* side and the transport — [InviteOffer], [MembersFailure] and the
// refusal names all come from there, unchanged, so the joiner and the inviter
// speak about the same invite in the same words. This file adds nothing to the
// protocol; it is the seam that lets S0.9 be pumped in a widget test without a
// server and without `features/members`' whole repository.
//
// ⚠️ WIRE — integration binds [DelegatedInvitationGateway] to the concrete
// `ServerMembersRepository`, whose `myInvites()` and `acceptInvite()` are the
// two routes this needs (`sync-meta/invites` GET and `sync-meta/invites/accept`
// POST). `pendingBooks` reads `MembersSnapshot.pendingBooks`.
//
// **The one rule that shapes the whole seam** (ADR 2026-09-05d §9 🔒): a
// number that was never invited and an invite id that does not exist are the
// *same* answer — [MembersRefusal.inviteNotForYou]. Nothing here asks a second
// question to tell them apart, and nothing here has a second failure that
// could. An empty [myInvites] is not a different fact from a refused accept:
// S0.9 renders both with one string, so the screen is no oracle either.
//
// Nothing here logs: an offer names a tenant and books (rule 4).
import 'package:flutter/widgets.dart';

import '../members/members_api.dart' show InviteOffer;
import '../members/members_repository.dart' show MembersFailure, PendingBook;

export '../members/members_api.dart' show InviteOffer;
export '../members/members_repository.dart'
    show MembersFailure, MembersRefusal, PendingBook;

/// What S0.9 needs from the server.
abstract class InvitationGateway {
  /// The invites addressed to this device's OTP-verified number (06 §7).
  ///
  /// Empty means *no invitation this phone may accept* — never *no such
  /// invite*: the two are indistinguishable by design (ADR 2026-09-05d §9 🔒).
  /// Throws [MembersFailure].
  Future<List<InviteOffer>> myInvites();

  /// Accepts one offer. Returns the membership status the server moved to —
  /// `joined_pending_verification`, never `active`: the ceremony grants that
  /// (06 §7 🔒). Throws [MembersFailure].
  Future<String> acceptInvite(String inviteId);

  /// The shared books the joiner can now see but not yet open — the *"Meet
  /// Sunita to activate"* placeholders of 07 §12 🔒. Empty until the meta pull
  /// has run, which is why S0.9 never blocks on it.
  Future<List<PendingBook>> pendingBooks();
}

/// An [InvitationGateway] over three closures — how integration binds the
/// concrete `ServerMembersRepository` without S0.9 importing it.
final class DelegatedInvitationGateway implements InvitationGateway {
  /// Creates the adapter. [pending] defaults to none, so a host that has not
  /// pulled meta yet still wires cleanly.
  DelegatedInvitationGateway({
    required this.offers,
    required this.accept,
    this.pending,
  });

  /// Yields the invites addressed to this device's OTP-verified number.
  final Future<List<InviteOffer>> Function() offers;

  /// Accepts one by id.
  final Future<String> Function(String inviteId) accept;

  /// The greyed shared books of 07 §12; null where the host has none to give.
  final Future<List<PendingBook>> Function()? pending;

  @override
  Future<List<InviteOffer>> myInvites() => offers();

  @override
  Future<String> acceptInvite(String inviteId) => accept(inviteId);

  @override
  Future<List<PendingBook>> pendingBooks() async =>
      await pending?.call() ?? const <PendingBook>[];
}

/// In-memory fake for tests and the Phase A shell.
class FakeInvitationGateway implements InvitationGateway {
  /// Creates the fake.
  FakeInvitationGateway({
    this.offers = const [],
    this.joined = const [],
    this.status = 'joined_pending_verification',
  });

  /// What [myInvites] returns.
  List<InviteOffer> offers;

  /// What [pendingBooks] returns once the invite is accepted.
  List<PendingBook> joined;

  /// What [acceptInvite] returns.
  String status;

  /// Next call to [myInvites] throws this once, then clears.
  MembersFailure? failNextList;

  /// Next call to [acceptInvite] throws this once, then clears.
  MembersFailure? failNextAccept;

  /// Invite ids passed to [acceptInvite], in order.
  final accepted = <String>[];

  /// How many times [myInvites] was called — 0 proves S0.9 never asked, which
  /// is what the uncertified-device variant must do (ADR 2026-09-05d §2 🔒).
  int listCalls = 0;

  @override
  Future<List<InviteOffer>> myInvites() async {
    listCalls++;
    final f = failNextList;
    if (f != null) {
      failNextList = null;
      throw f;
    }
    return offers;
  }

  @override
  Future<String> acceptInvite(String inviteId) async {
    final f = failNextAccept;
    if (f != null) {
      failNextAccept = null;
      throw f;
    }
    accepted.add(inviteId);
    return status;
  }

  @override
  Future<List<PendingBook>> pendingBooks() async => joined;
}

/// Provides the gateway to S0.9. Absent, the screen falls back to an empty
/// fake — which renders the *"this invitation can't be used on this phone"*
/// state, the safe one.
class InvitationGatewayScope extends InheritedWidget {
  /// Creates the scope.
  const InvitationGatewayScope({
    super.key,
    required this.gateway,
    required super.child,
  });

  /// The gateway S0.9 reads.
  final InvitationGateway gateway;

  static final _fallback = FakeInvitationGateway();

  /// The nearest gateway, or an empty fake.
  static InvitationGateway of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<InvitationGatewayScope>()
          ?.gateway ??
      _fallback;

  @override
  bool updateShouldNotify(InvitationGatewayScope old) => gateway != old.gateway;
}
