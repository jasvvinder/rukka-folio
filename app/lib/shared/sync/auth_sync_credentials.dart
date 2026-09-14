// The session credential the sync transport carries (05 §1, 06 §4): the
// 15-minute access JWT `features/auth`'s identity client mints and refreshes.
//
// Two rules this adapter exists to keep:
//
//  * **Never cached in the transport.** [eng.HttpSyncTransport] asks for a
//    token per request; this object asks the identity client per request, and
//    the identity client is the only thing that holds one. Nothing here stores
//    a token beyond the last value handed out, which exists solely so a 401
//    can name the token the server rejected.
//
//  * **A 401 is never a logout** (ADR 2026-09-05b §2 🔒: *a device never wipes
//    on the server's word*; an unsigned server assertion suspends, it does not
//    destroy). [invalidate] makes the next call fetch a fresh token — it does
//    not sign out, does not touch keys, and does not change [AuthState].
//
// Nothing here logs: the value is a bearer token (rule 4).
import 'package:sync_engine/sync_engine.dart' as eng;

/// The current access token, refreshed by the identity client when it is close
/// to expiry. Throwing means there is no live session — `HttpAuthClient`
/// throws `SessionEnded`.
typedef AccessTokenSource = Future<String> Function();

/// Drops the identity client's cached access token so the next
/// [AccessTokenSource] call refreshes. Optional: see [AuthSyncCredentials].
typedef ForgetAccessToken = Future<void> Function();

/// Thrown by [AuthSyncCredentials.accessToken] when the only token the
/// identity client will hand out is one the server has already rejected.
///
/// [eng.HttpSyncTransport] maps any throw from `accessToken()` onto
/// `AuthFailed(code: no_session)`: the engine backs off and retries next round
/// rather than treating it as a fact about the device — which is exactly the
/// posture ADR 2026-09-05b §2 asks for.
final class StaleAccessToken implements Exception {
  /// Creates the failure.
  const StaleAccessToken();

  @override
  String toString() => 'StaleAccessToken';
}

/// [eng.SyncCredentials] over the app's identity client.
///
/// [forget] is how a 401 is meant to be handled: drop the cached token, let
/// the next call refresh. When it is **not** supplied — today's case, because
/// `HttpAuthClient` exposes no public cache-buster and adding one is an edit
/// in `features/auth` (lane report) — this class falls back to refusing to
/// replay: a token the server answered 401 to is never sent again, and sync
/// stays offline until the identity client's own expiry margin refreshes it
/// (at most the token's 15 minutes, 06 §4). Refusing to replay is strictly
/// safer than replaying; it is not a weakening of the guard, only a slower
/// recovery.
final class AuthSyncCredentials implements eng.SyncCredentials {
  /// Creates the credential over [accessTokenOf].
  AuthSyncCredentials({required AccessTokenSource accessTokenOf, this.forget})
    : _source = accessTokenOf;

  final AccessTokenSource _source;

  /// Drops the identity client's cached token, when the app can.
  final ForgetAccessToken? forget;

  String? _lastHandedOut;
  String? _rejected;

  /// How many 401s reached [invalidate] (tests, and 05 §9's "needs attention"
  /// story if it ever grows a reason for it).
  int invalidations = 0;

  @override
  Future<String> accessToken() async {
    final token = await _source();
    if (token.isEmpty) throw const StaleAccessToken();
    final rejected = _rejected;
    if (rejected != null && rejected == token) throw const StaleAccessToken();
    _lastHandedOut = token;
    return token;
  }

  @override
  Future<void> invalidate() async {
    invalidations++;
    _rejected = _lastHandedOut;
    _lastHandedOut = null;
    final drop = forget;
    if (drop == null) return;
    try {
      await drop();
    } on Object {
      // The identity client's problem, not the route's. The typed 401 the
      // transport is about to throw is what the engine acts on either way.
    }
  }
}
