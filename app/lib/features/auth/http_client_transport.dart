// `package:http` behind the auth client's two-method seam (auth_transport.dart).
// Integration-only: main.dart constructs it; tests use a fake AuthTransport.
// Nothing here logs — bodies carry phone numbers and codes (CLAUDE.md rule 4).
import 'package:http/http.dart' as http;

import 'auth_transport.dart';

/// The production [AuthTransport]: POST JSON over an injected [http.Client].
final class HttpClientTransport implements AuthTransport {
  /// Wraps [client]; the caller owns its lifetime.
  HttpClientTransport(this._client);

  final http.Client _client;

  @override
  Future<AuthHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final http.Response r;
    try {
      r = await _client.post(url, headers: headers, body: body);
    } on Exception catch (e) {
      throw AuthTransportException(e);
    }
    return AuthHttpResponse(r.statusCode, r.body);
  }
}
