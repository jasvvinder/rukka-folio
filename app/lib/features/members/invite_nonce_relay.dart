// The invite nonce the server relays to the invitee (ADR 2026-09-25b §2–§3).
//
// **What this is.** S9.2's QR carries the per-invite nonce (04 §6.1). Since
// 25b §1 the *inviter's* device draws it and signs it into the `invite`
// record; the server stores it and hands it back to the invitee on two routes:
// each `GET sync-meta/invites` row, and the `POST sync-meta/invites/accept`
// answer. This relay is the invitee's end of that. It **never draws a nonce**
// (§3): there is no RNG here and nothing to fall back on, so no relayed nonce
// is an answer of null, which S9.2 renders as its fail-closed state.
//
// **Paired by `invite_id`, and by nothing else.** The nonce S9.2 shows is the
// one of *the invite that brought this user into the tenant* (§3). That
// invite is known by its id — the one this device accepted — and a relayed
// nonce is used only when it was answered for exactly that id. Not the first
// row (position), not the live row (`status`, whose place in §2 is PLAN desk
// 36's open question), not whichever invite a membership happens to exist
// through. An accept answer that names another invite pairs nothing.
//
// **After a restart** (ADR 2026-09-25b §2: *"an accepted invite stays
// reachable for S9.2 after a restart without the device keeping a copy"*).
// The server keeps the invite reachable: `GET invites` lists the invites the
// caller accepted, nonce and all. To pair by `invite_id` the device must still
// know WHICH of those rows is its own, so the accepted id — and only the id —
// is kept in the device's protected item store ([RkPrefs], the same store the
// shell's settings use) under [InviteNonceRelay.acceptedInviteKey]. The nonce
// is never written: it is read back from the relay every time, so the device
// keeps no copy of the invite.
//
// ⚠️ SPEC 25b §2 — reading: *"without the device keeping a copy"* is taken to
// forbid a copy of the invite (nonce, roles), not the pointer §3 pairs by.
// The alternative that keeps nothing at all — pairing by the row's `status`
// — waits on PLAN desk 36 and is not done here. Reported (M11-NONCE2).
//
// Nothing here logs: the rows name a tenant and an admin (CLAUDE.md rule 4).
import 'dart:typed_data';

import '../../shared/prefs.dart';
import 'members_api.dart';
import 'members_repository.dart' show MembersFailure;

/// The invitee's end of ADR 2026-09-25b §2: accepts through the relay so the
/// accepted invite's id is known, and answers that invite's relayed nonce.
final class InviteNonceRelay {
  /// [offers] is `GET sync-meta/invites`; [accept] is the accept route with
  /// its whole answer ([HttpMembersApi.acceptInviteRelayed]); [store] is the
  /// device's protected item store, where the accepted invite's id outlives
  /// the launch.
  InviteNonceRelay({
    required this.offers,
    required this.accept,
    required this.store,
  });

  /// Where the accepted invite's id is kept.
  ///
  /// ⚠️ SPEC: `RkPrefKeys` (`shared/prefs.dart`) is meant to be the only place
  /// pref keys live; this one belongs there and is kept here until the owner
  /// of `shared/` hoists it (M11-NONCE2 report).
  static const acceptedInviteKey = 'invite.accepted';

  /// `GET sync-meta/invites` — the caller's own invites, each with its nonce.
  final Future<List<InviteOffer>> Function() offers;

  /// `POST sync-meta/invites/accept`, with its whole answer.
  final Future<AcceptedInvite> Function(String inviteId) accept;

  /// The device's protected item store — holds the accepted invite's **id**
  /// under [acceptedInviteKey], never its nonce.
  final RkPrefs store;

  String? _ownInviteId;
  Uint8List? _acceptedNonce;

  /// The invite this device accepted — this launch, or recalled from [store]
  /// by an earlier [nonce] — or null.
  String? get ownInviteId => _ownInviteId;

  /// Accepts [inviteId] and remembers it as this device's own invite — the
  /// joiner's accept (S0.9), with the same answer the gateway always had: the
  /// **membership** status. Refusals propagate unchanged, and pair nothing.
  Future<String> acceptInvite(String inviteId) async {
    final answer = await accept(inviteId);
    // The server's answer must be about the invite we asked for; one that
    // names another has told us nothing we may attribute to ourselves.
    if (answer.inviteId == inviteId) {
      _ownInviteId = inviteId;
      _acceptedNonce = answer.nonce;
      try {
        await store.write(acceptedInviteKey, inviteId);
      } on Object {
        // The accept stands on the server; only the restart memory is lost,
        // and S9.2 then says why rather than guessing a row.
      }
    }
    return answer.status;
  }

  /// The relayed nonce of this device's own invite, or null — no invite
  /// accepted on this device, no nonce relayed for that id, or the relay (or
  /// the store) could not be read. Never a throw, never a drawn value. Read
  /// afresh on every call, so S9.2's *Check again* recovers once the relay
  /// answers.
  Future<Uint8List?> nonce() async {
    final id = _ownInviteId ?? await _recall();
    if (id == null) return null;
    final accepted = _acceptedNonce;
    if (accepted != null) return Uint8List.fromList(accepted);
    final List<InviteOffer> rows;
    try {
      rows = await offers();
    } on MembersFailure {
      return null;
    }
    for (final row in rows) {
      if (row.inviteId != id) continue;
      final n = row.nonce;
      return n == null ? null : Uint8List.fromList(n);
    }
    return null;
  }

  /// The id an earlier launch accepted, from [store]; null when none was
  /// kept or the store cannot be read.
  Future<String?> _recall() async {
    final String? kept;
    try {
      kept = await store.read(acceptedInviteKey);
    } on Object {
      return null;
    }
    if (kept == null || kept.isEmpty) return null;
    return _ownInviteId = kept;
  }
}
