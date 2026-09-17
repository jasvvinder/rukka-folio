// The HTTP seam the auth client uses. It is no longer a seam of its own: the
// app has one door (`shared/seams/http_transport.dart`) and these three names
// are aliases of it, kept because the client, the screens and the tests that
// fake a server all read in terms of "auth transport".
//
// Auth POSTs and never GETs (06 §2–§4 has no GET route), so it speaks the
// narrow half, [RkHttpPoster]; `features/members` speaks the full
// [RkHttpTransport]. One response type, one "never answered" exception, one
// implementation over `package:http` — `HttpClientRkTransport`, built once in
// `bootstrap.dart`.
//
// Nothing in here logs; bodies carry phone numbers and codes (rule 4).
import '../../shared/seams/http_transport.dart';

export '../../shared/seams/http_transport.dart'
    show AuthTransportOverRkHttp, RkHttpFailure, RkHttpPoster, RkHttpResponse;

/// A minimal response: status and UTF-8 body.
typedef AuthHttpResponse = RkHttpResponse;

/// Thrown by an [AuthTransport] when the request never reached a response
/// (no network, DNS, TLS, timeout). The client maps it to
/// `AuthFailureKind.unavailable`.
typedef AuthTransportException = RkHttpFailure;

/// POST JSON, get a status + body. Implementations must throw
/// [AuthTransportException] (or any [Exception]) on transport failure and
/// never log the body.
typedef AuthTransport = RkHttpPoster;
