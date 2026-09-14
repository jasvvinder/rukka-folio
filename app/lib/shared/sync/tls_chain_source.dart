// The platform half of SPKI pinning (05 §1 🔒, ADR 2026-09-05 §1).
//
// `packages/sync_engine` is pure Dart and cannot see a socket, so
// [eng.HttpSyncTransport] asks an injected [eng.TlsChainSource] what the TLS
// layer presented and hands the digests to [eng.SpkiPins]. This file is that
// source, over `dart:io`. Returning null — *"I do not know what was
// presented"* — is a **failure** there, not a pass: every path below that
// cannot produce a digest returns null, and the transport then refuses the
// request. No fallback, no override.
//
// ⚠️ SPEC 05 §1 (two gaps, both named in the lane report — neither is a licence
// to relax the pin, both make it *stricter* than the spec asks):
//
//  1. **Leaf only.** `dart:io` exposes the peer certificate and nothing else:
//     `SecureSocket.peerCertificate` and `badCertificateCallback` both hand
//     over one [X509Certificate], never the intermediates. 05 §1's
//     *"⚠️ pin at the intermediate-CA level for hosted Supabase"* therefore
//     cannot be satisfied by this source as written; it reports a one-element
//     chain holding the **leaf** SPKI. A leaf pin is a shorter-lived pin, so
//     the rotation runbook 05 §1 defers to M4 has to move at leaf cadence
//     until a platform channel can report the full chain.
//
//  2. **Observed connection ≠ used connection.** The probe opens its own TLS
//     handshake to the same host and closes it; the request then travels over
//     `package:http`'s connection. A host that presented a pinned key to the
//     probe and a different one to the request would not be caught. Closing
//     this needs the request and the observation to share one socket —
//     `HttpClient.connectionFactory` with an `IOClient`, or a platform
//     channel — and is the one thing here that cannot be tested without a
//     real server.
//
// Nothing here logs; a hostname is not financial data but it is the user's
// tenant, and rule 4's habit is cheaper to keep than to relearn.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:sync_engine/sync_engine.dart' as eng;

/// SHA-256 over bytes. **Injected**: `app/pubspec.yaml` carries no SHA-256
/// source — libsodium exposes BLAKE2b (`CryptoSuite.blake2b256`) and HKDF-
/// SHA256, neither of which is a plain digest — and CLAUDE.md rule 7 forbids
/// hand-rolling one. Wiring `package:crypto`'s `sha256.convert(b).bytes` here
/// is a one-line change to a pubspec this lane does not own (lane report).
typedef Sha256Digest = Uint8List Function(Uint8List bytes);

/// Reports the DER of the certificate the peer presented for [url], or null
/// when the handshake did not happen or said nothing. Injected so the pure
/// half of this file is testable without a socket.
typedef LeafCertificateProbe = Future<Uint8List?> Function(Uri url);

/// The `SubjectPublicKeyInfo` of an X.509 certificate, as the DER bytes that
/// get hashed — tag and length included, which is what "SPKI hash" means.
///
/// ```text
/// Certificate     ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
/// TBSCertificate  ::= SEQUENCE { [0] EXPLICIT Version DEFAULT v1,
///                                serialNumber, signature, issuer, validity,
///                                subject, subjectPublicKeyInfo, ... }
/// ```
///
/// Returns null for anything that is not a well-formed certificate — a
/// malformed input must fail the pin, never pass it.
Uint8List? subjectPublicKeyInfoDer(Uint8List der) {
  final cert = _readTlv(der, 0);
  if (cert == null || cert.tag != _sequence) return null;
  final tbs = _readTlv(der, cert.contentStart);
  if (tbs == null || tbs.tag != _sequence || tbs.end > cert.end) return null;

  var at = tbs.contentStart;
  final first = _readTlv(der, at);
  if (first == null || first.end > tbs.end) return null;
  // [0] EXPLICIT version is optional (absent ⇒ v1).
  if (first.tag == _contextExplicit0) at = first.end;

  // serialNumber · signature · issuer · validity · subject
  for (var skipped = 0; skipped < 5; skipped++) {
    final field = _readTlv(der, at);
    if (field == null || field.end > tbs.end) return null;
    at = field.end;
  }

  final spki = _readTlv(der, at);
  if (spki == null || spki.tag != _sequence || spki.end > tbs.end) return null;
  return Uint8List.sublistView(der, at, spki.end);
}

const int _sequence = 0x30;
const int _contextExplicit0 = 0xa0;

/// One DER tag-length-value header, resolved against the buffer.
final class _Tlv {
  const _Tlv(this.tag, this.contentStart, this.end);

  final int tag;
  final int contentStart;
  final int end;
}

/// Reads the TLV at [i]. Null when the buffer is short, the length is
/// indefinite or longer than four bytes, or the value runs past the end —
/// every one of which is a certificate this build refuses to read.
_Tlv? _readTlv(Uint8List b, int i) {
  if (i < 0 || i + 2 > b.length) return null;
  final tag = b[i];
  var at = i + 1;
  var length = b[at++];
  if (length & 0x80 != 0) {
    final count = length & 0x7f;
    if (count == 0 || count > 4 || at + count > b.length) return null;
    length = 0;
    for (var k = 0; k < count; k++) {
      length = (length << 8) | b[at++];
    }
  }
  if (length < 0 || at + length > b.length) return null;
  return _Tlv(tag, at, at + length);
}

/// [eng.TlsChainSource] over `dart:io`. See the file header for what it can
/// and cannot see.
///
/// The digest for a host is cached for [ttl] so a sync round does not open a
/// probe handshake per request; a failure is **not** cached, so a transient
/// network error does not pin-fail the next six hours of syncing.
final class IoTlsChainSource implements eng.TlsChainSource {
  /// Creates the source. [sha256] is the digest (see [Sha256Digest]); [probe]
  /// defaults to a short-lived `SecureSocket` handshake.
  IoTlsChainSource({
    required Sha256Digest sha256,
    LeafCertificateProbe? probe,
    this.ttl = const Duration(minutes: 5),
    Duration timeout = const Duration(seconds: 10),
    this.now = DateTime.now,
  }) : _sha256 = sha256,
       _probe = probe ?? ((url) => secureSocketProbe(url, timeout: timeout));

  final Sha256Digest _sha256;
  final LeafCertificateProbe _probe;

  /// Injected wall clock, for the cache's time-to-live.
  final DateTime Function() now;

  /// How long a successful digest is reused for a host.
  final Duration ttl;

  final Map<String, ({List<Uint8List> chain, DateTime at})> _cache = {};

  /// Probes actually run (tests; also the cache-hit assertion).
  int probes = 0;

  @override
  Future<List<Uint8List>?> spkiSha256(Uri url) async {
    if (url.scheme != 'https') return null;
    final key = '${url.host}:${url.hasPort ? url.port : 443}';
    final hit = _cache[key];
    if (hit != null && now().difference(hit.at) < ttl) return hit.chain;

    probes++;
    final Uint8List? der;
    try {
      der = await _probe(url);
    } on Object {
      return null; // a probe that threw knows nothing; nothing is believed
    }
    if (der == null) return null;
    final spki = subjectPublicKeyInfoDer(der);
    if (spki == null) return null;
    final Uint8List digest;
    try {
      digest = _sha256(spki);
    } on Object {
      return null;
    }
    if (digest.length != 32) return null;
    final chain = List<Uint8List>.unmodifiable([digest]);
    _cache[key] = (chain: chain, at: now());
    return chain;
  }

  /// Drops every cached digest (a network change, a 401, a manual retry).
  void forget() => _cache.clear();
}

/// The default probe: one TLS handshake to [url]'s host, the peer certificate
/// read off it, socket destroyed. A certificate the OS itself refuses fails
/// the handshake and yields null — pinning is *in addition to* chain
/// validation, never instead of it.
Future<Uint8List?> secureSocketProbe(
  Uri url, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (url.scheme != 'https') return null;
  SecureSocket? socket;
  try {
    socket = await SecureSocket.connect(
      url.host,
      url.hasPort ? url.port : 443,
      timeout: timeout,
      onBadCertificate: (_) => false,
    );
    final der = socket.peerCertificate?.der;
    return der == null ? null : Uint8List.fromList(der);
  } on Object {
    return null;
  } finally {
    socket?.destroy();
  }
}
