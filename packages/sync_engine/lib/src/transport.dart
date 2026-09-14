// The engine's two doors to the outside world, both injected (09 §1: no
// `DateTime.now()`, no direct network in a pure package).
import 'wire.dart';

/// Virtual or real clock, injected. Milliseconds since the epoch.
abstract interface class Clock {
  /// Current time in ms.
  int nowMs();
}

/// A clock a test drives by hand.
final class ManualClock implements Clock {
  /// Creates a clock at [nowMs].
  ManualClock([int nowMs = 0]) : _now = nowMs;
  int _now;

  @override
  int nowMs() => _now;

  /// Moves time forward by [ms].
  void advance(int ms) => _now += ms;

  /// Sets the time.
  set now(int ms) => _now = ms;
}

/// The three sync routes (05 §3–§5), already authenticated as one device.
/// Implementations: HTTPS + pinned SPKI in the app; the harness's in-memory
/// server under the seeded network in tests.
abstract interface class SyncTransport {
  /// `POST /sync/push`.
  Future<PushResponse> push(PushRequest request);

  /// `GET /sync/pull`.
  Future<PullResponse> pull(PullRequest request);

  /// `GET /sync/meta`.
  Future<MetaResponse> meta(MetaRequest request);
}

/// The **write** half of the metadata plane: publishing a signed record
/// (ADR 2026-09-05b §1 🔒). Without it a device can read every structural fact
/// the family authored and contribute none of its own — no revocation, no role
/// change, no verification event.
///
/// Kept as its own interface rather than folded into [SyncTransport] because
/// the three read routes and this one are separately implementable, and a test
/// double that only reads stays valid. A transport that can do both declares
/// [FullSyncTransport].
abstract interface class RecordTransport {
  /// `POST /sync-meta/records` — at most [PostRecordsRequest.batchMax] records
  /// per call; beyond that the whole batch is [BatchTooLarge] and **nothing**
  /// is stored, so the caller must split rather than assume a partial apply.
  ///
  /// A 200 judges each record on its own: a `rejected:` [RecordAck] is not a
  /// route failure and the record is still stored (append-only — it is a
  /// signed fact; the note says why it was not applied).
  Future<PostRecordsResponse> postRecords(PostRecordsRequest request);
}

/// 06 §7's invitation routes — the one place a phone number passes through the
/// server, and the only route that can mint an invite (a record of kind
/// `invite` posted to [RecordTransport.postRecords] is stored and refused
/// `rejected:invite_route`, because that route has no number to HMAC).
abstract interface class InviteTransport {
  /// `POST /sync-meta/invites` — the admin's signed `invite` record plus the
  /// invitee's number. Refusals: [RouteRefused.notAdmin],
  /// [RouteRefused.badPhone], [RouteRefused.badRecord],
  /// [RouteRefused.recordReplayed], [RouteRefused.unknownTenant].
  Future<InviteIssued> createInvite(CreateInviteRequest request);

  /// `GET /sync-meta/invites` — the invites addressed to **this** device's own
  /// OTP-verified number. Never anyone else's, and never an empty-vs-forbidden
  /// distinction a caller could probe with.
  Future<List<WireInviteOffer>> myInvites();

  /// `POST /sync-meta/invites/accept` — lands on
  /// [InviteAcceptance.joinedPendingVerification]; the ceremony, not this
  /// route, grants `active`. Refusals: [RouteRefused.inviteNotForYou]
  /// (identical for a wrong number and an unknown id),
  /// [RouteRefused.inviteExpired], [RouteRefused.inviteNotLive].
  Future<InviteAcceptance> acceptInvite(String inviteId);
}

/// Everything a certified device needs: the three sync routes plus the two
/// ways to write to the metadata plane. The app's real transport and the
/// harness's fake both implement this; the engine asks for the narrower
/// [SyncTransport] and tests a capability before using the rest.
abstract interface class FullSyncTransport
    implements SyncTransport, RecordTransport, InviteTransport {}

/// Why a route could not be completed. Every failure is typed so the engine
/// never parses strings (05 §9: a typed status, no spinners).
sealed class TransportFailure implements Exception {
  const TransportFailure();

  /// Maps a non-2xx HTTP answer to its typed failure. The server's error
  /// body is `{error: code, detail?}` (`_shared/http.ts`); 426 adds
  /// `min_client_version`. The app's HTTPS transport and the contract test
  /// share this one mapping.
  static TransportFailure fromHttp(int status, Map<String, Object?>? body) {
    final code = body?['error'] as String?;
    // `check` is `detail` by another name on the record routes: a 400
    // `{error:"bad_record", check:"payload_json"}` says which field the server
    // refused (`sync-meta/index.ts` invites). Losing it would leave the Inbox
    // with a refusal it cannot explain.
    final detail = (body?['detail'] ?? body?['check']) as String?;
    return switch (status) {
      401 => AuthFailed(code: code),
      426 => UpdateRequired(
        minClientVersion: body?['min_client_version'] as String?,
      ),
      413 => BatchTooLarge(detail: detail),
      _ => RouteRefused(status: status, code: code, detail: detail),
    };
  }
}

/// `4xx` other than 401/413/426: the server refused the route as a whole
/// with `{error: code}`. On pull: 404 `unknown_book` (also for a non-member's
/// tenant and an uncertified device — no existence oracle), 403 `no_role`;
/// 400 `bad_request` / `bad_cursor` are client bugs. Nothing is lost: outbox
/// rows and cursors stay where they were.
final class RouteRefused extends TransportFailure {
  /// Creates the failure.
  const RouteRefused({required this.status, this.code, this.detail});

  /// HTTP status.
  final int status;

  /// The `error` code.
  final String? code;

  /// The `detail`, if any.
  final String? detail;

  /// 404: the book does not exist for this caller.
  static const String unknownBook = 'unknown_book';

  /// 403: a member without a role on the book.
  static const String noRole = 'no_role';

  // The invite routes' refusals (06 §7, ADR 2026-09-05d §9; `inviteError` in
  // `sync-meta/index.ts`). Named so the engine and the UI branch on a constant
  // rather than a string literal, and so the two that must stay
  // indistinguishable are visibly one code.

  /// 403 on accept: **either** the invite is addressed to another number
  /// **or** it does not exist. One code for both, deliberately: the link alone
  /// admits nobody and the route is no oracle for who was invited
  /// (ADR 2026-09-05d §9 🔒).
  static const String inviteNotForYou = 'invite_not_for_you';

  /// 410: past 06 §7's 7-day window. The offer is gone; re-invite is one tap.
  static const String inviteExpired = 'invite_expired';

  /// 409: already accepted, revoked or superseded — an invite is spent once.
  static const String inviteNotLive = 'invite_not_live';

  /// 403 on issue: issuing is an admin power (06 §1.0).
  static const String notAdmin = 'not_admin';

  /// 409: this exact signed record was already taken. The record **is** the
  /// action, so a retry must not mint a second invite; the first one stands
  /// and the admin's device finds it by `source_record_id` in the meta pull.
  static const String recordReplayed = 'record_replayed';

  /// 400: the number was not E.164 (`_shared/phone.ts` `normaliseE164`). It
  /// never reached the HMAC, and no invite was created.
  static const String badPhone = 'bad_phone';

  /// 400: the signed record itself was refused; [detail] carries the server's
  /// `check` (the field at fault).
  static const String badRecord = 'bad_record';

  /// 404 on issue: no such tenant for this caller.
  static const String unknownTenant = 'unknown_tenant';

  @override
  String toString() => 'RouteRefused($status ${code ?? ''})';
}

/// `413 {error:"batch_too_large"}` — the whole push batch was refused (more
/// than 100 envelopes or more than 1 MB of blob bytes, 05 §3); no envelope
/// in it was stored or judged. The engine shrinks the batch and retries.
final class BatchTooLarge extends TransportFailure {
  /// Creates the failure.
  const BatchTooLarge({this.detail});

  /// The `detail`, e.g. `max 100 envelopes`.
  final String? detail;

  /// The `error` code.
  static const String code = 'batch_too_large';
}

/// No connectivity, a dropped request or a dropped response (05 §3 retry).
final class TransportOffline extends TransportFailure {
  /// Creates the failure.
  const TransportOffline([this.detail]);

  /// Trace detail.
  final String? detail;

  @override
  String toString() => 'TransportOffline(${detail ?? ''})';
}

/// `426` min-version gate (05 §1, 06 §4.5): stop syncing, show the update screen.
final class UpdateRequired extends TransportFailure {
  /// Creates the failure.
  const UpdateRequired({this.minClientVersion});

  /// `min_client_version` from the 426 body, if sent.
  final String? minClientVersion;
}

/// `401`. [code] `device_revoked` is the server's *unsigned* word — the
/// engine suspends and wipes nothing (ADR 05b §2).
final class AuthFailed extends TransportFailure {
  /// Creates the failure.
  const AuthFailed({this.code});

  /// Server error code, e.g. `device_revoked`.
  final String? code;

  /// The 401 code for an asserted revocation.
  static const String deviceRevoked = 'device_revoked';
}
