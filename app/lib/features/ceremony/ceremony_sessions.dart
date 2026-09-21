// Where a ceremony is *opened* — the missing last link of 04 §7.3 *Setup*.
//
// The gap this closes. `CeremonyScope` was declared at M7 and installed
// nowhere, so `CryptoVerifyMemberRepository` was constructed by nothing and
// S9.2/S9.3 rendered a placeholder although both screens and the repository
// had been green for weeks. The scope's own header said why it was left: the
// two repositories are **per invite**, and nothing that had an invite in hand
// installed them — "a ceremony with a made-up nonce would be worse than no
// screen."
//
// So the scope stops carrying finished repositories and starts carrying this:
// a **factory**, which the composition root can install once because it
// fabricates nothing. A repository exists only once a real subject, a real
// invite nonce and a real session are in hand; until then the factory answers
// null and the route keeps its placeholder. That is the same rule the old
// header stated, moved from a comment into the type.
//
// **What a completed ceremony must leave behind** (04 §8.2 🔒, CLAUDE.md rule
// 5). [keys] is required and non-nullable all the way down to
// `CryptoVerifyMemberRepository`: a ceremony that proves a member's UMK and
// drops it leaves that member permanently unverifiable, and 04 §7.3 *Setup*
// cannot publish a guardian set at all — which is exactly the defect this
// file exists to make impossible to reintroduce by omission. The sink takes a
// `VerifiedUmkPublic`, so nothing but a real match can reach it.
//
// **Three seams are declared here and cannot be implemented on today's
// wire.** Each is a *required* constructor parameter with a documented
// "answers null" default, so the composition root does not have to invent
// one, and so the day the server lands, one line binds it:
//
//   1. [RelayedUmkSource] — 04 §6.3 🔒 compares the scanned keys byte-for-byte
//      against **the keys the server relayed**, and `Ceremony.verifyQr`
//      compares BOTH halves (`core_crypto/lib/src/ceremony.dart:490`). The
//      server holds only the Ed25519 half: `umk_public_keys` (migration
//      0001:48) has `pub_ed` and no `pub_x`, sync-meta relays `pub_ed`, and
//      `POST devices/certify` uploads `umk_pub_ed` alone. The UMK's X25519
//      half is derived from its own seed (`core_crypto/lib/src/keys.dart:13`)
//      and is NOT recoverable from `pub_ed`. Comparing one half would weaken
//      a 🔒 rule silently, so this source answers null instead and S9.3 keeps
//      its placeholder.
//   2. [CeremonySessionLookup] — the verifier has to find the invitee's live
//      session. `sync-meta` exposes only `GET /ceremony?session_id=…`, the id
//      is minted server-side at commit, and it is in neither the QR payload
//      (04 §6.1) nor any other route. Migration 0007 already indexes
//      `(tenant_id, subject_user, committed_at desc)`, which is exactly this
//      lookup.
//   3. [InviteNonceSource] — 04 §6.1 🔒 says the per-invite nonce is
//      **server-generated**. It reaches the server inside the admin's signed
//      `invite` record (migration 0008) and comes back on no route the
//      invitee can attribute to itself: the `invites` meta row carries no
//      nonce and no `source_record_id`, and the `invite` record deliberately
//      carries no identifier of the invitee. Drawing one on the device would
//      contradict a 🔒 line — the one thing the old header forbade — so this
//      seam has no default at all and S9.2 waits for a real one.
//
// Nothing here logs: a session names two people (CLAUDE.md rule 4).
import 'package:core_crypto/core_crypto.dart'
    show CryptoSuite, UmkPublic, VerificationMethod;

import '../../shared/ledger/verified_members.dart' show VerifiedMemberSink;
import 'ceremony_api.dart';
import 'ceremony_repository.dart';

/// The UMK public halves the **server** relayed for [userId] (04 §6.3 🔒), or
/// null when this device cannot obtain them.
///
/// Null is not "not yet loaded"; it is "this device has no relayed key to
/// compare against", and the only correct response is to refuse to open the
/// verifier's side. A caller that supplied the *scanned* key here would have
/// the ceremony compare a key with itself.
typedef RelayedUmkSource = Future<UmkPublic?> Function(String userId);

/// The invitee's live ceremony session for [subjectUserId], or null when
/// there is none this device can see.
typedef CeremonySessionLookup = Future<String?> Function(String subjectUserId);

/// A member's display name, for the screens (04 §6.2, 07 §12). User-typed.
typedef CeremonyMemberName = String Function(String userId);

/// Opens the two sides of the ceremony (04 §6.2) for a **real** subject.
///
/// Both answers are nullable on purpose: a null is the honest state of a
/// device that cannot open that side yet, and is rendered as the route's
/// waiting placeholder. Neither method ever returns a repository built on an
/// invented nonce, an invented session or a key this device chose.
abstract class CeremonySessions {
  /// This install's own side (S9.2 Show my code) — the invitee proving their
  /// own UMK. Null when this device holds no key material or no invite.
  Future<ShowMyCodeRepository?> showMyCode();

  /// The verifier's side (S9.3) against [subjectUserId] — the **user id** of
  /// the person being verified, which is what a ceremony session is keyed by
  /// (migration 0007: `subject_user`). Null when the ceremony cannot be
  /// opened against a real subject.
  Future<VerifyMemberRepository?> verifyMember(String subjectUserId);
}

/// A [CeremonySessions] that can open nothing — the honest empty state, and
/// what the scope falls back to when the composition root installed none
/// (07 §1 rule 6: a missing scope is never a red screen).
final class NoCeremonySessions implements CeremonySessions {
  /// Creates the empty factory.
  const NoCeremonySessions();

  @override
  Future<ShowMyCodeRepository?> showMyCode() async => null;

  @override
  Future<VerifyMemberRepository?> verifyMember(String subjectUserId) async =>
      null;
}

/// The real factory: both sides over `core_crypto` and the 0007 session relay.
final class LiveCeremonySessions implements CeremonySessions {
  /// Creates the factory.
  ///
  /// [keys] is where a completed ceremony's proved key is kept — the ledger's
  /// `VerifiedMemberDirectory` in production. It is required and
  /// non-nullable; see this file's header.
  LiveCeremonySessions({
    required this.suite,
    required this.api,
    required this.tenantId,
    required this.selfUserId,
    required this.ownUmk,
    required this.nonces,
    required this.verifierName,
    required this.memberName,
    required this.now,
    required this.log,
    required this.keys,
    this.relayedUmk = noRelayedUmk,
    this.liveSessionOf = noLiveCeremonySession,
    this.polling = const CeremonyPolling(),
    this.mode = CeremonyMode.inPerson,
    this.canVerify = true,
  });

  /// Injected libsodium suite (CLAUDE.md rule 7).
  final CryptoSuite suite;

  /// The ceremony session relay.
  final CeremonyApi api;

  /// The tenant whose ceremony this is — migration 0007 keys a session by
  /// `(tenant_id, subject_user)`.
  final String tenantId;

  /// This install's own user.
  final String selfUserId;

  /// This install's own UMK public halves, or null before the ledger is open.
  /// A callback, not a field, so a closed ledger is never held here.
  final UmkPublic? Function() ownUmk;

  /// The **server-generated** per-invite nonce (04 §6.1 🔒).
  final InviteNonceSource nonces;

  /// Who is verifying this install's user — S9.2's waiting state names them
  /// rather than saying "someone" (07 §12).
  final String Function() verifierName;

  /// The person being verified, by user id.
  final CeremonyMemberName memberName;

  /// Injected clock (CLAUDE.md rule 3).
  final DateTime Function() now;

  /// Where 04 §6.3's `verification_mismatch` and 04 §6.4's entry go.
  final CeremonyEventLog log;

  /// Where a completed ceremony's key is kept (04 §8.2 🔒).
  final VerifiedMemberSink keys;

  /// The server-relayed keys of the person being verified (04 §6.3 🔒).
  final RelayedUmkSource relayedUmk;

  /// Finds the subject's live session.
  final CeremonySessionLookup liveSessionOf;

  /// Poll interval and sleep for both relays.
  final CeremonyPolling polling;

  /// In person or remote (04 §6.4) — an admin toggle per invite.
  final CeremonyMode mode;

  /// Whether this member may run the ceremony at all (04 §6.4 *Delegated*).
  final bool canVerify;

  @override
  Future<ShowMyCodeRepository?> showMyCode() async {
    final umk = ownUmk();
    if (umk == null) return null;
    return CryptoShowMyCodeRepository(
      suite: suite,
      userId: selfUserId,
      umk: umk,
      nonces: nonces,
      relay: ServerShowerSessionRelay(
        api: api,
        tenantId: tenantId,
        now: now,
        polling: polling,
      ),
      verifierName: verifierName(),
    );
  }

  @override
  Future<VerifyMemberRepository?> verifyMember(String subjectUserId) async {
    // 0007 refuses `self_verification` in the database. Refusing it here too
    // means the screen never opens a session that cannot exist — and a device
    // can never be talked into comparing its own key with itself.
    if (subjectUserId.isEmpty || subjectUserId == selfUserId) return null;
    final relayed = await relayedUmk(subjectUserId);
    if (relayed == null) return null;
    final sessionId = await liveSessionOf(subjectUserId);
    if (sessionId == null) return null;
    return CryptoVerifyMemberRepository(
      suite: suite,
      relayedUmk: relayed,
      relayedUserId: subjectUserId,
      relay: ServerVerifierSessionRelay(
        api: api,
        sessionId: sessionId,
        now: now,
        polling: polling,
      ),
      memberName: memberName(subjectUserId),
      now: now,
      log: log,
      keys: keys,
      mode: mode,
      canVerify: canVerify,
    );
  }
}

/// The default [RelayedUmkSource]: no relayed key. See this file's header —
/// the server carries `umk_pub_ed` and no `pub_x`, and half a comparison is
/// not 04 §6.3's comparison.
Future<UmkPublic?> noRelayedUmk(String userId) async => null;

/// The default [CeremonySessionLookup]: no session. See this file's header —
/// `sync-meta` has no "the live session for this subject" route yet.
Future<String?> noLiveCeremonySession(String subjectUserId) async => null;

/// A [CeremonyEventLog] over two injected callbacks.
///
/// 04 §6.3 requires a `verification_mismatch` security event and 04 §6.4 a
/// permanent verification entry. The **entry** is already durable without
/// this: `VerifiedMemberSink.storeVerified` writes the signed
/// `verification_event` record that 06 §7 and ADR 2026-09-05d §7 make the
/// authoritative one, so [verified] here is for a surface that wants to
/// react, never the record itself.
///
/// ⚠️ SPEC 04 §6.3: the **mismatch** event has no durable home in the app
/// yet — there is no security-event store in `app/` or `packages/`. Until one
/// exists this delegates, so a mismatch is never silently dropped by this
/// class; whether it is kept is the caller's. A member name is contact data
/// and is never written to a log line (CLAUDE.md rule 4).
final class DelegatedCeremonyEventLog implements CeremonyEventLog {
  /// Creates the log. Both callbacks are optional; an absent one is a no-op.
  const DelegatedCeremonyEventLog({this.onMismatch, this.onVerified});

  /// Called with the member's name when a comparison failed.
  final Future<void> Function(String memberName)? onMismatch;

  /// Called when a ceremony completed.
  final Future<void> Function(String memberName, VerificationMethod method)?
  onVerified;

  @override
  Future<void> mismatch({required String memberName}) async =>
      onMismatch?.call(memberName);

  @override
  Future<void> verified({
    required String memberName,
    required VerificationMethod method,
  }) async => onVerified?.call(memberName, method);
}
