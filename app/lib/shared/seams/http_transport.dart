// The app's one HTTP door (05 §1, 06 §2–§4). `features/auth`'s [AuthTransport]
// (POST only) and `features/members`' [MembersTransport] (GET + POST) were the
// same seam written twice, with two response types and two "the request never
// answered" exceptions. This file owns the seam; each feature's interface is
// satisfied by a one-line adapter over it, so there is exactly one place in the
// app that calls `package:http` for a JSON route.
//
// The two feature interfaces could not simply be merged by one class: both
// declare `post(Uri, {headers, body})` with *different* return types
// ([AuthHttpResponse] vs [MembersHttpResponse]), which Dart cannot implement
// together. Deleting the two declarations and pointing both features at
// [RkHttpTransport] is a three-file edit inside `features/auth` and
// `features/members` — directories this lane does not own, and a lane running
// beside it might. The adapters below remove the duplicated *behaviour* today;
// the duplicated *declarations* are one deletion away and are named in the lane
// report.
//
// Nothing here logs: bodies carry phone numbers, OTP codes and bearer tokens
// (CLAUDE.md rule 4).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/auth/auth_transport.dart';
import '../../features/members/members_api.dart'
    show MembersHttpResponse, MembersTransport, MembersTransportException;

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

/// GET/POST JSON. Implementations throw [RkHttpFailure] on transport failure
/// and never log a URL's body.
abstract interface class RkHttpTransport {
  /// GET [url].
  Future<RkHttpResponse> get(Uri url, {required Map<String, String> headers});

  /// POST [body] (already encoded) to [url].
  Future<RkHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  });
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

/// `features/auth`'s seam over [RkHttpTransport].
final class AuthTransportOverRkHttp implements AuthTransport {
  /// Adapts [transport].
  const AuthTransportOverRkHttp(this.transport);

  /// The one door.
  final RkHttpTransport transport;

  @override
  Future<AuthHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final RkHttpResponse r;
    try {
      r = await transport.post(url, headers: headers, body: body);
    } on RkHttpFailure catch (e) {
      throw AuthTransportException(e.cause);
    }
    return AuthHttpResponse(r.statusCode, r.body);
  }
}

/// `features/members`' seam over [RkHttpTransport].
final class MembersTransportOverRkHttp implements MembersTransport {
  /// Adapts [transport].
  const MembersTransportOverRkHttp(this.transport);

  /// The one door.
  final RkHttpTransport transport;

  @override
  Future<MembersHttpResponse> get(
    Uri url, {
    required Map<String, String> headers,
  }) => _run(() => transport.get(url, headers: headers));

  @override
  Future<MembersHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) => _run(() => transport.post(url, headers: headers, body: body));

  Future<MembersHttpResponse> _run(
    Future<RkHttpResponse> Function() call,
  ) async {
    final RkHttpResponse r;
    try {
      r = await call();
    } on RkHttpFailure catch (e) {
      throw MembersTransportException(e.cause);
    }
    return MembersHttpResponse(r.statusCode, r.body);
  }
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
