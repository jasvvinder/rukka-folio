// F1-05-14 … F1-05-19: the platform half of SPKI pinning (05 §1 🔒, ADR
// 2026-09-05 §1) and the point where it finally meets `sync_engine`'s
// `SpkiPins` — a pin set with nothing to check was the gap this closes.
//
// The digest is injected everywhere here, so these tests pin the *plumbing*
// (which bytes get hashed, what happens when nothing can be hashed) and never
// a SHA-256 implementation. Certificates are hand-built DER: synthetic, no
// real host, no socket.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rukka_folio/shared/sync/tls_chain_source.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

/// One DER tag-length-value.
Uint8List tlv(int tag, List<int> content) {
  final out = <int>[tag];
  final n = content.length;
  if (n < 0x80) {
    out.add(n);
  } else if (n < 0x100) {
    out
      ..add(0x81)
      ..add(n);
  } else {
    out
      ..add(0x82)
      ..add(n >> 8)
      ..add(n & 0xff);
  }
  return Uint8List.fromList(out..addAll(content));
}

const int seq = 0x30;
const int integer = 0x02;
const int bitString = 0x03;
const int explicit0 = 0xa0;

/// The SPKI every fixture carries, as its own DER element.
final spki = tlv(seq, [
  ...tlv(seq, [
    ...tlv(0x06, [0x2a, 0x86, 0x48]),
    0x05,
    0x00,
  ]),
  ...tlv(bitString, [0x00, ...List<int>.filled(32, 0x7b)]),
]);

/// A structurally valid certificate carrying [spki] in the right slot.
Uint8List certificate({bool withVersion = true, Uint8List? publicKey}) {
  final tbs = tlv(seq, [
    if (withVersion) ...tlv(explicit0, tlv(integer, [0x02])),
    ...tlv(integer, [0x01, 0x02, 0x03]),
    ...tlv(seq, tlv(0x06, [0x2a, 0x86])),
    ...tlv(seq, tlv(0x31, tlv(seq, tlv(0x13, utf8.encode('issuer'))))),
    ...tlv(seq, [
      ...tlv(0x17, utf8.encode('260101000000Z')),
      ...tlv(0x17, utf8.encode('270101000000Z')),
    ]),
    ...tlv(seq, tlv(0x31, tlv(seq, tlv(0x13, utf8.encode('subject'))))),
    ...(publicKey ?? spki),
  ]);
  return tlv(seq, [
    ...tbs,
    ...tlv(seq, tlv(0x06, [0x2a, 0x86])),
    ...tlv(bitString, [0x00, ...List<int>.filled(8, 0x11)]),
  ]);
}

/// A digest that is not SHA-256 — these tests never assert a hash value, only
/// which bytes were handed to it.
Uint8List stubDigest(Uint8List bytes) {
  final out = Uint8List(32);
  for (var i = 0; i < bytes.length; i++) {
    out[i % 32] = (out[i % 32] + bytes[i]) & 0xff;
  }
  return out;
}

void main() {
  group('subjectPublicKeyInfoDer', () {
    test('F1-05-14 lifts the SubjectPublicKeyInfo — tag and length included — '
        'out of a certificate, with or without the optional [0] version', () {
      for (final withVersion in [true, false]) {
        final found = subjectPublicKeyInfoDer(
          certificate(withVersion: withVersion),
        );
        expect(found, isNotNull, reason: 'withVersion: $withVersion');
        expect(found, equals(spki), reason: 'withVersion: $withVersion');
      }
    });

    test('F1-05-15 anything that is not a well-formed certificate is null — '
        'a chain that cannot be read fails the pin, it never passes it', () {
      final good = certificate();
      expect(subjectPublicKeyInfoDer(Uint8List(0)), isNull);
      expect(subjectPublicKeyInfoDer(Uint8List.fromList([0x30])), isNull);
      // Truncated: the outer length promises more than is there.
      expect(
        subjectPublicKeyInfoDer(
          Uint8List.sublistView(good, 0, good.length - 5),
        ),
        isNull,
      );
      // Not a SEQUENCE at the top.
      final notSeq = Uint8List.fromList(good)..[0] = 0x31;
      expect(subjectPublicKeyInfoDer(notSeq), isNull);
      // A tbs that runs out of fields before the SPKI slot.
      expect(
        subjectPublicKeyInfoDer(tlv(seq, tlv(seq, tlv(integer, [1])))),
        isNull,
      );
    });
  });

  group('IoTlsChainSource', () {
    test('F1-05-16 reports the digest of the certificate SPKI, once per host '
        'per ttl — and never caches a failure', () async {
      var now = DateTime.utc(2026, 9, 14, 10);
      Uint8List? der = certificate();
      final source = IoTlsChainSource(
        sha256: stubDigest,
        probe: (_) async => der,
        ttl: const Duration(minutes: 5),
        now: () => now,
      );
      final url = Uri.parse('https://api.example.test/functions/v1/sync-pull');

      expect(await source.spkiSha256(url), equals([stubDigest(spki)]));
      expect(source.probes, 1);
      // A second request inside the ttl reuses the digest.
      expect(await source.spkiSha256(url), equals([stubDigest(spki)]));
      expect(source.probes, 1);
      // Past the ttl it looks again.
      now = now.add(const Duration(minutes: 6));
      expect(await source.spkiSha256(url), isNotNull);
      expect(source.probes, 2);

      // A failing probe answers null and is not remembered as one.
      der = null;
      now = now.add(const Duration(minutes: 6));
      expect(await source.spkiSha256(url), isNull);
      der = certificate();
      expect(await source.spkiSha256(url), isNotNull);
    });

    test(
      'F1-05-17 every way of not knowing answers null: plain http, no '
      'certificate, a probe that threw, unreadable DER, a bad digest',
      () async {
        final https = Uri.parse('https://api.example.test/');
        Future<List<Uint8List>?> ask(IoTlsChainSource s, [Uri? url]) =>
            s.spkiSha256(url ?? https);

        final ok = IoTlsChainSource(
          sha256: stubDigest,
          probe: (_) async => certificate(),
        );
        expect(await ask(ok, Uri.parse('http://api.example.test/')), isNull);

        expect(
          await ask(
            IoTlsChainSource(sha256: stubDigest, probe: (_) async => null),
          ),
          isNull,
        );
        expect(
          await ask(
            IoTlsChainSource(
              sha256: stubDigest,
              probe: (_) async => throw const SocketFailure(),
            ),
          ),
          isNull,
        );
        expect(
          await ask(
            IoTlsChainSource(
              sha256: stubDigest,
              probe: (_) async => Uint8List.fromList([0x30, 0x80]),
            ),
          ),
          isNull,
        );
        expect(
          await ask(
            IoTlsChainSource(
              sha256: (_) => Uint8List(16), // not 32 bytes: not a SHA-256
              probe: (_) async => certificate(),
            ),
          ),
          isNull,
        );
        expect(
          await ask(
            IoTlsChainSource(
              sha256: (_) => throw StateError('no digest wired'),
              probe: (_) async => certificate(),
            ),
          ),
          isNull,
        );
      },
    );
  });

  group('the pin set and the chain source, meeting', () {
    final root = Uri.parse('https://api.example.test/functions/v1/');

    eng.HttpSyncTransport transportWith({
      required List<eng.SpkiPin> pins,
      required Uint8List? der,
      required List<Uri> sent,
    }) => eng.HttpSyncTransport(
      client: MockClient((request) async {
        sent.add(request.url);
        return http.Response(
          jsonEncode({
            'store_epoch': 'e1',
            'devices': [],
            'memberships': [],
            'book_roles': [],
            'wrapped_keys': [],
            'signed_records': [],
            'has_more': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      functionsRoot: root,
      credentials: eng.StaticSyncCredentials('token'),
      clientVersion: '0.1.0',
      pins: eng.SpkiPins(pins),
      tlsChainSource: IoTlsChainSource(
        sha256: stubDigest,
        probe: (_) async => der,
      ),
    );

    test('F1-05-18 a matching pin lets the request through; a mismatch stops '
        'it before it leaves — nothing is sent, nothing is believed', () async {
      final matching = <Uri>[];
      await transportWith(
        pins: [
          eng.SpkiPin(stubDigest(spki), label: 'current'),
          eng.SpkiPin(Uint8List(32)..[0] = 0xaa, label: 'backup'),
        ],
        der: certificate(),
        sent: matching,
      ).meta(const eng.MetaRequest());
      expect(matching, hasLength(1));

      final refused = <Uri>[];
      final wrongPins = transportWith(
        pins: [
          eng.SpkiPin(Uint8List(32)..[0] = 0x01, label: 'current'),
          eng.SpkiPin(Uint8List(32)..[0] = 0x02, label: 'backup'),
        ],
        der: certificate(),
        sent: refused,
      );
      await expectLater(
        wrongPins.meta(const eng.MetaRequest()),
        throwsA(
          // ADR 2026-09-15 §7 🔒: a pin failure is its own cause, mapped to
          // *Needs attention* — never `Offline`, which would tell the user to
          // wait for a network they may already have.
          isA<eng.PinFailed>().having(
            (e) => e.detail,
            'detail',
            eng.ClientFailureCode.pinFailed,
          ),
        ),
      );
      expect(refused, isEmpty, reason: 'the request must never leave');

      // A chain source that knows nothing fails exactly like a mismatch.
      final unknown = <Uri>[];
      await expectLater(
        transportWith(
          pins: [
            eng.SpkiPin(stubDigest(spki), label: 'current'),
            eng.SpkiPin(Uint8List(32)..[0] = 0xaa, label: 'backup'),
          ],
          der: null,
          sent: unknown,
        ).meta(const eng.MetaRequest()),
        throwsA(isA<eng.PinFailed>()),
      );
      expect(unknown, isEmpty);
    });

    test('F1-05-19 a live pin set with no chain source cannot be constructed '
        '— the app must not be able to ship unpinned by accident', () {
      expect(
        () => eng.HttpSyncTransport(
          client: MockClient((_) async => http.Response('{}', 200)),
          functionsRoot: root,
          credentials: eng.StaticSyncCredentials('token'),
          clientVersion: '0.1.0',
          pins: eng.SpkiPins([
            eng.SpkiPin(Uint8List(32)..[0] = 0x01, label: 'current'),
            eng.SpkiPin(Uint8List(32)..[0] = 0x02, label: 'backup'),
          ]),
        ),
        throwsA(isA<ArgumentError>()),
      );
      // Only a local-dev build may go without one.
      expect(
        eng.HttpSyncTransport(
          client: MockClient((_) async => http.Response('{}', 200)),
          functionsRoot: root,
          credentials: eng.StaticSyncCredentials('token'),
          clientVersion: '0.1.0',
          pins: const eng.SpkiPins.localDev(),
        ),
        isNotNull,
      );
    });
  });
}

/// Stands in for a `SocketException` without importing `dart:io` into a test
/// that otherwise needs no socket.
final class SocketFailure implements Exception {
  const SocketFailure();
}
