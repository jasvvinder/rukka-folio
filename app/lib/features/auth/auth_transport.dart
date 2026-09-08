// The one HTTP seam the auth client uses. `package:http` is not declared in
// app/pubspec.yaml (owned by the shell lane), so the client speaks to this
// two-method interface and integration wraps `http.Client` in it:
//
//   final class HttpClientTransport implements AuthTransport {
//     HttpClientTransport(this._client);
//     final http.Client _client;
//     @override
//     Future<AuthHttpResponse> post(Uri url, {required Map<String, String> headers, required String body}) async {
//       final r = await _client.post(url, headers: headers, body: body);
//       return AuthHttpResponse(r.statusCode, r.body);
//     }
//   }
//
// Nothing in here logs; bodies carry phone numbers and codes (rule 4).

/// A minimal response: status and UTF-8 body.
final class AuthHttpResponse {
  const AuthHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// Thrown by an [AuthTransport] when the request never reached a response
/// (no network, DNS, TLS, timeout). The client maps it to
/// `AuthFailureKind.unavailable`.
final class AuthTransportException implements Exception {
  const AuthTransportException([this.cause]);

  final Object? cause;

  @override
  String toString() => 'AuthTransportException';
}

/// POST JSON, get a status + body. Implementations must throw
/// [AuthTransportException] (or any [Exception]) on transport failure and
/// never log the body.
abstract class AuthTransport {
  Future<AuthHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  });
}
