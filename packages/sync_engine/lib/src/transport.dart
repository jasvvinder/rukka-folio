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
    final detail = body?['detail'] as String?;
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
