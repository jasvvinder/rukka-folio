// The app's one HTTP door (05 §1, 06 §2–§4).
//
// `features/auth` and `features/members` each declared their own seam — two
// interfaces, two response classes and two "the request never answered"
// exceptions, differing in nothing but their names and the fact that auth
// never GETs. This file now owns all of it: one [RkHttpResponse], one
// [RkHttpFailure], and one interface in two widths — [RkHttpPoster] (POST
// only, what the auth client needs) and [RkHttpTransport] (GET + POST, what
// the members client needs), the second a subtype of the first. Each
// feature's names survive as aliases of these (`auth_transport.dart`,
// `members_api.dart`), so callers and the tests that fake the seam read the
// same as before while there is exactly one declaration behind them.
//
// The two adapters below are therefore pass-throughs, kept because the
// composition root names them (`bootstrap.dart`, which this lane does not
// own) and because a narrowing adapter is the honest way to hand a GET+POST
// transport to something that may only POST. There is nothing left for them
// to convert.
//
// Nothing here logs: bodies carry phone numbers, OTP codes and bearer tokens
// (CLAUDE.md rule 4).
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A minimal response: status and UTF-8 body.
final class RkHttpResponse {
  /// Creates a response.
  const RkHttpResponse(this.statusCode, this.body);

  /// HTTP status.
  final int statusCode;

  /// UTF-8 body, possibly empty.
  final String body;
}

/// Thrown when the request never reached a response (no network, DNS, TLS,
/// timeout). Callers map it to their own "offline" refusal — never to one that
/// would claim the server said something.
final class RkHttpFailure implements Exception {
  /// Creates the failure.
  const RkHttpFailure([this.cause]);

  /// What went wrong, for the caller's own handling. Never logged.
  final Object? cause;

  @override
  String toString() => 'RkHttpFailure';
}

/// POST JSON. The narrow half of the door: `features/auth` speaks only this,
/// because none of 06 §2–§4's routes is a GET.
abstract interface class RkHttpPoster {
  /// POST [body] (already encoded) to [url]. Throws [RkHttpFailure] when the
  /// request never reached a response.
  Future<RkHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  });
}

/// GET + POST JSON. Implementations throw [RkHttpFailure] on transport
/// failure and never log a body.
abstract interface class RkHttpTransport implements RkHttpPoster {
  /// GET [url].
  Future<RkHttpResponse> get(Uri url, {required Map<String, String> headers});
}

/// The production transport: `package:http` over an injected [http.Client].
///
/// Bodies are decoded as UTF-8 from the raw bytes rather than through
/// `http.Response.body`, which falls back to **latin-1** when a response
/// carries no `charset` — a member name in Punjabi or Hindi would come back
/// mojibake from a server that omits it.
final class HttpClientRkTransport implements RkHttpTransport {
  /// Wraps [client]; the caller owns its lifetime.
  const HttpClientRkTransport(this._client);

  final http.Client _client;

  @override
  Future<RkHttpResponse> get(Uri url, {required Map<String, String> headers}) =>
      _run(() => _client.get(url, headers: headers));

  @override
  Future<RkHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) => _run(() => _client.post(url, headers: headers, body: body));

  Future<RkHttpResponse> _run(Future<http.Response> Function() call) async {
    final http.Response r;
    try {
      r = await call();
    } on Exception catch (e) {
      throw RkHttpFailure(e);
    }
    return RkHttpResponse(
      r.statusCode,
      utf8.decode(r.bodyBytes, allowMalformed: true),
    );
  }
}

/// Hands a full [RkHttpTransport] to `features/auth` as the POST-only seam it
/// declares. Narrowing only — no response is rewrapped and no exception is
/// translated, because there is one of each.
final class AuthTransportOverRkHttp implements RkHttpPoster {
  /// Adapts [transport].
  const AuthTransportOverRkHttp(this.transport);

  /// The one door.
  final RkHttpTransport transport;

  @override
  Future<RkHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) => transport.post(url, headers: headers, body: body);
}

/// `features/members`' seam **is** [RkHttpTransport] (its `MembersTransport`
/// is an alias of it), so this is a pass-through kept only because
/// `bootstrap.dart` names it. Passing the door itself is equivalent.
final class MembersTransportOverRkHttp implements RkHttpTransport {
  /// Adapts [transport].
  const MembersTransportOverRkHttp(this.transport);

  /// The one door.
  final RkHttpTransport transport;

  @override
  Future<RkHttpResponse> get(Uri url, {required Map<String, String> headers}) =>
      transport.get(url, headers: headers);

  @override
  Future<RkHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) => transport.post(url, headers: headers, body: body);
}

/// In-memory transport for tests: scripted answers, recorded requests.
final class FakeRkHttpTransport implements RkHttpTransport {
  /// Creates the fake. [answer] decides what each request returns; throwing
  /// [RkHttpFailure] from it models a request that never answered.
  FakeRkHttpTransport(this.answer);

  /// Answers one request.
  final RkHttpResponse Function(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  )
  answer;

  /// Every request made, in order.
  final calls = <({String method, Uri url, Map<String, String> headers})>[];

  @override
  Future<RkHttpResponse> get(Uri url, {required Map<String, String> headers}) {
    calls.add((method: 'GET', url: url, headers: headers));
    return Future.value(answer('GET', url, headers, null));
  }

  @override
  Future<RkHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) {
    calls.add((method: 'POST', url: url, headers: headers));
    return Future.value(answer('POST', url, headers, body));
  }
}
