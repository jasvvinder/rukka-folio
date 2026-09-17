// D-05-14 … D-05-31 — contract tests for [HttpSyncTransport] (05 §1, §3, §4,
// §5, §8; 06 §4, §7; ADR 2026-09-05b §1, §6; ADR 2026-09-05d §9).
//
// These are deliberately *contract* tests: every expectation below is written
// against a named line in `server/supabase/functions`, so that wire drift
// fails here, in `dart test`, instead of on two phones. The server side is
// quoted in the comment above each group. No live server, no socket: the
// `http.Client`, the session credential and the TLS chain are all injected.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

// ── fixtures ────────────────────────────────────────────────────────────────

const _root = 'https://rukka.example/functions/v1/';
const _tenant = '11111111-1111-4111-8111-111111111111';
const _book = '22222222-2222-4222-8222-222222222222';
const _object = '33333333-3333-4333-8333-333333333333';
const _device = '44444444-4444-4444-8444-444444444444';
const _envelope = '55555555-5555-4555-8555-555555555555';

/// A physical-ms ‖ counter HLC (03 §1): 48-bit ms shifted left 16. Well beyond
/// 2^53, which is the whole point of the server's `jsonBig` / `parseJsonBig`.
const int _hlc = 1757808000000 << 16;

Uint8List _fill(int n, int seed) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (seed + i * 7) & 0xff));

/// Exactly what Deno's `@std/encoding/base64url` `encodeBase64Url` emits:
/// base64url with the padding stripped (`_shared/bytes.ts` `b64url.enc`).
String denoB64Url(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

WireEnvelope envelope({int? seq}) => WireEnvelope(
  envelopeId: _envelope,
  seq: seq,
  tenantId: _tenant,
  bookId: _book,
  objectId: _object,
  objectType: 'entry',
  keyVersion: 1,
  suiteVersion: 1,
  payloadSchema: 1,
  authorDevice: _device,
  hlc: _hlc,
  blobHash: _fill(32, 3),
  blob: _fill(100, 11),
);

/// The wire form of one envelope exactly as `sync-pull`'s `envelopeToWire`
/// writes it (`_shared/route.ts`): bytes unpadded base64url, `seq` and `hlc`
/// bare integer literals, `blob` inline.
Map<String, Object?> pulledEnvelopeJson({required int seq}) => {
  'envelope_id': _envelope,
  'seq': seq,
  'tenant_id': _tenant,
  'book_id': _book,
  'object_id': _object,
  'object_type': 'entry',
  'key_version': 1,
  'suite_version': 1,
  'payload_schema': 1,
  'author_device': _device,
  'hlc': _hlc,
  'blob_hash': denoB64Url(_fill(32, 3)),
  'size': 100,
  'blob': denoB64Url(_fill(100, 11)),
};

/// One pin set and a chain that matches it.
final _pinned = _fill(32, 200);
SpkiPins livePins() => SpkiPins([
  SpkiPin(_pinned, label: 'current'),
  SpkiPin(_fill(32, 201), label: 'backup'),
]);

final class _Rig {
  _Rig({
    required this.body,
    this.status = 200,
    this.pins,
    this.chain,
    this.credentials,
    this.timeout = const Duration(seconds: 30),
    this.hang = false,
  });

  /// Body the mock answers with; a `Map` is JSON-encoded, a `String` sent raw.
  final Object? body;
  final int status;
  final SpkiPins? pins;
  final TlsChainSource? chain;
  final SyncCredentials? credentials;
  final String clientVersion = '1.4.0';
  final Duration timeout;

  /// Accept the request and never answer it (a stalled connection).
  final bool hang;

  final List<http.Request> requests = [];
  Object? throwOnSend;

  late final HttpSyncTransport transport = HttpSyncTransport(
    client: MockClient((req) async {
      requests.add(req);
      final t = throwOnSend;
      if (t != null) {
        // ignore: only_throw_errors — standing in for the platform client
        throw t;
      }
      if (hang) return Completer<http.Response>().future;
      final b = body;
      return http.Response(
        b is String ? b : jsonEncode(b),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
    functionsRoot: Uri.parse(_root),
    credentials: credentials ?? StaticSyncCredentials('jwt-token'),
    clientVersion: clientVersion,
    pins: pins ?? const SpkiPins.localDev(),
    tlsChainSource: chain,
    timeout: timeout,
  );

  http.Request get only => requests.single;
  Map<String, Object?> get sentJson =>
      jsonDecode(only.body) as Map<String, Object?>;
}

void main() {
  // ── D-05-14 ───────────────────────────────────────────────────────────────
  // `_shared/bytes.ts`: `b64url.enc` is Deno's `encodeBase64Url`, which emits
  // base64url WITHOUT padding; `b64any` accepts base64 or base64url, padded or
  // not. Dart's `base64Url.decode` throws on unpadded input, so an unnormalised
  // decoder would have failed on every blob, hash, key and signature the server
  // has ever sent — on the phone, never in CI.
  group('D-05-14 bytes on the wire', () {
    test('D-05-14 unpadded base64url from the server decodes', () {
      final hash = _fill(32, 3);
      expect(denoB64Url(hash).length, 43, reason: '32 bytes, no padding');
      expect(
        () => base64Url.decode(denoB64Url(hash)),
        throwsFormatException,
        reason: 'the naive decoder is what this test exists to prevent',
      );

      final e = WireEnvelope.fromJson(pulledEnvelopeJson(seq: 7));
      expect(e.blobHash, hash);
      expect(e.blob.length, 100);
    });

    test('D-05-14 a 64-byte signature and a 32-byte key decode unpadded', () {
      final sig = _fill(64, 21);
      final pub = _fill(32, 31);
      final record = WireSignedRecord.fromJson({
        'id': _object,
        'seq': 12,
        'suite_version': 1,
        'tenant_id': _tenant,
        'kind': 'book_role',
        'payload_json': denoB64Url(_fill(50, 41)),
        'author_device_id': _device,
        'author_sig': denoB64Url(sig),
        'hlc': _hlc,
      });
      expect(record.authorSig, sig);
      expect(record.payloadJson.length, 50);

      final device = WireDevice.fromJson({
        'id': _device,
        'user_id': _tenant,
        'pub_ed': denoB64Url(pub),
        'pub_x': denoB64Url(_fill(32, 32)),
        'status': 'certified',
      });
      expect(device.pubEd, pub);
    });

    test('D-05-14 what this client emits is what b64any accepts', () {
      // `b64any` maps `-_` → `+/`, strips trailing `=`, then requires the
      // standard alphabet. Padded base64url passes that filter.
      final emitted = envelope().toJson()['blob_hash']! as String;
      expect(emitted, matches(RegExp(r'^[A-Za-z0-9\-_]+={0,2}$')));
      final asServerReads = emitted
          .replaceAll('-', '+')
          .replaceAll('_', '/')
          .replaceAll(RegExp(r'=+$'), '');
      expect(RegExp(r'^[A-Za-z0-9+/]*$').hasMatch(asServerReads), isTrue);
      expect(base64.decode(base64.normalize(emitted)), _fill(32, 3));
    });
  });

  // ── D-05-15 ───────────────────────────────────────────────────────────────
  // `sync-push/index.ts` + `_shared/shape.ts` `parseEnvelope`: POST, body
  // `{envelopes[]}`, five canonical-lowercase uuid fields, `object_type` in the
  // registry, four non-negative integers, `hlc` an integer (or decimal string),
  // `blob_hash` 32 bytes, and EXACTLY ONE of `blob` / `blob_ref`.
  group('D-05-15 push request shape', () {
    test('D-05-15 push posts the JSON parseEnvelope accepts', () async {
      final rig = _Rig(body: {'store_epoch': 'e1', 'results': <Object?>[]});
      await rig.transport.push(PushRequest(envelopes: [envelope()]));

      expect(rig.only.method, 'POST');
      expect(rig.only.url.toString(), '${_root}sync-push');
      expect(rig.only.headers['content-type'], startsWith('application/json'));

      final envelopes = rig.sentJson['envelopes']! as List<Object?>;
      final e = envelopes.single! as Map<String, Object?>;
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      );
      for (final f in [
        'envelope_id',
        'tenant_id',
        'book_id',
        'object_id',
        'author_device',
      ]) {
        expect(uuid.hasMatch(e[f]! as String), isTrue, reason: 'check $f');
      }
      expect(e['object_type'], 'entry');
      for (final f in [
        'key_version',
        'suite_version',
        'payload_schema',
        'size',
      ]) {
        expect(e[f], isA<int>(), reason: 'check $f');
        expect(e[f]! as int, greaterThanOrEqualTo(0), reason: 'check $f');
      }
      expect(e['hlc'], isA<int>());
      expect(
        base64.decode(base64.normalize(e['blob_hash']! as String)).length,
        32,
      );
      // `(blob === null) === (blob_ref === null)` is the server's refusal.
      expect(e.containsKey('blob'), isTrue);
      expect(e.containsKey('blob_ref'), isFalse);
      // `checkShape`: blob.length must equal `size`.
      expect(
        base64.decode(base64.normalize(e['blob']! as String)).length,
        e['size'],
      );
      // `seq` is the server's to stamp; an unstored envelope must not claim one.
      expect(e.containsKey('seq'), isFalse);
    });
  });

  // ── D-05-16 ───────────────────────────────────────────────────────────────
  // `_shared/route.ts` `gate` + `_shared/registry.ts` `belowMinVersion`:
  // `belowMinVersion(null, min)` is TRUE, so a request without
  // `x-rukka-client-version` is answered 426 by every sync route before auth
  // even runs. `_shared/claims.ts` `bearer` requires the `Bearer ` prefix.
  group('D-05-16 session credential and version header', () {
    test('D-05-16 every route carries Bearer and the client version', () async {
      final creds = StaticSyncCredentials('jwt-abc');
      for (final call in <Future<Object?> Function(HttpSyncTransport)>[
        (t) => t.push(const PushRequest(envelopes: [])),
        (t) => t.pull(const PullRequest(bookId: _book, afterSeq: 0)),
        (t) => t.meta(const MetaRequest()),
      ]) {
        final rig = _Rig(
          credentials: creds,
          body: {
            'store_epoch': 'e1',
            'results': <Object?>[],
            'envelopes': <Object?>[],
            'next_seq': 0,
            'next': 'cursor',
            'has_more': false,
          },
        );
        await call(rig.transport);
        expect(rig.only.headers['authorization'], 'Bearer jwt-abc');
        expect(rig.only.headers['x-rukka-client-version'], '1.4.0');
      }
    });

    test(
      'D-05-16 a fresh token is fetched per call, never cached here',
      () async {
        final creds = StaticSyncCredentials('first');
        final rig = _Rig(
          credentials: creds,
          body: {'store_epoch': 'e1', 'results': <Object?>[]},
        );
        await rig.transport.push(const PushRequest(envelopes: []));
        creds.token = 'second';
        await rig.transport.push(const PushRequest(envelopes: []));
        expect(rig.requests.map((r) => r.headers['authorization']), [
          'Bearer first',
          'Bearer second',
        ]);
      },
    );
  });

  // ── D-05-17 ───────────────────────────────────────────────────────────────
  // `sync-push/index.ts`: `{store_epoch, results:[{envelope_id, result, seq?,
  // check?, retry_after_ms?}]}` through `jsonBigResponse`, so `seq` is a bare
  // integer literal.
  group('D-05-17 push response', () {
    test(
      'D-05-17 acked, shape-refused and rate-limited rows all parse',
      () async {
        final rig = _Rig(
          body: {
            'store_epoch': 'epoch-7',
            'results': [
              {'envelope_id': _envelope, 'result': 'acked', 'seq': 4096},
              {
                'envelope_id': _object,
                'result': 'rejected:shape',
                'check': 'blob_hash',
              },
              {
                'envelope_id': _device,
                'result': 'rejected:rate_limited',
                'retry_after_ms': 60000,
              },
            ],
          },
        );
        final res = await rig.transport.push(
          PushRequest(envelopes: [envelope()]),
        );
        expect(res.storeEpoch, 'epoch-7');
        expect(res.results, hasLength(3));
        expect(res.results[0].isAcked, isTrue);
        expect(res.results[0].seq, 4096);
        expect(res.results[1].result, PushOutcome.rejectedShape);
        expect(res.results[1].check, 'blob_hash');
        expect(res.results[2].result, PushOutcome.rejectedRateLimited);
        expect(res.results[2].retryAfterMs, 60000);
      },
    );
  });

  // ── D-05-18 ───────────────────────────────────────────────────────────────
  // `_shared/bytes.ts` `jsonBig` / `_shared/http.ts` `parseJsonBig`: an HLC is
  // 48-bit ms ‖ 16-bit counter, which exceeds 2^53. It travels as a bare
  // integer literal in both directions and must survive exactly.
  group('D-05-18 integers beyond 2^53', () {
    test('D-05-18 an HLC past 2^53 round-trips exactly', () async {
      expect(_hlc > 9007199254740992, isTrue, reason: 'beyond 2^53');

      final rig = _Rig(
        body: {
          'store_epoch': 'e1',
          'envelopes': [pulledEnvelopeJson(seq: 1)],
          'next_seq': 1,
        },
      );
      await rig.transport.push(PushRequest(envelopes: [envelope()]));
      // Sent as a bare integer literal, not a float and not quoted.
      expect(rig.only.body, contains('"hlc":$_hlc'));

      final pulled = await _Rig(
        body: {
          'store_epoch': 'e1',
          'envelopes': [pulledEnvelopeJson(seq: 1)],
          'next_seq': 1,
        },
      ).transport.pull(const PullRequest(bookId: _book, afterSeq: 0));
      expect(pulled.envelopes.single.hlc, _hlc);
    });
  });

  // ── D-05-19 ───────────────────────────────────────────────────────────────
  // `sync-pull/index.ts`: GET with `book_id`, `after_seq`, `limit`, optional
  // `object_types` (comma-separated, filtered against OBJECT_TYPES) and `fy`;
  // answer `{store_epoch, envelopes[], next_seq}` with `next_seq` equal to
  // `after_seq` on an empty page.
  group('D-05-19 pull', () {
    test(
      'D-05-19 the cursor and the bootstrap hot set travel as query',
      () async {
        final rig = _Rig(
          body: {'store_epoch': 'e1', 'envelopes': <Object?>[], 'next_seq': 12},
        );
        await rig.transport.pull(
          const PullRequest(
            bookId: _book,
            afterSeq: 12,
            limit: 500,
            objectTypes: ['book_config', 'account', 'period_lock'],
          ),
        );
        expect(rig.only.method, 'GET');
        expect(rig.only.url.path, '/functions/v1/sync-pull');
        expect(rig.only.url.queryParameters, {
          'book_id': _book,
          'after_seq': '12',
          'limit': '500',
          'object_types': 'book_config,account,period_lock',
        });
        expect(rig.only.body, isEmpty);
      },
    );

    test('D-05-19 a page parses with seq on every row; an empty page holds '
        'the cursor', () async {
      final page = await _Rig(
        body: {
          'store_epoch': 'e1',
          'envelopes': [
            pulledEnvelopeJson(seq: 13),
            pulledEnvelopeJson(seq: 14),
          ],
          'next_seq': 14,
        },
      ).transport.pull(const PullRequest(bookId: _book, afterSeq: 12));
      expect(page.envelopes.map((e) => e.seq), [13, 14]);
      expect(page.nextSeq, 14);
      expect(page.hasMore, isTrue);

      final empty = await _Rig(
        body: {'store_epoch': 'e1', 'envelopes': <Object?>[], 'next_seq': 12},
      ).transport.pull(const PullRequest(bookId: _book, afterSeq: 12));
      expect(empty.nextSeq, 12);
      expect(empty.hasMore, isFalse);
    });
  });

  // ── D-05-20 ───────────────────────────────────────────────────────────────
  // `sync-meta/index.ts` `pull`: GET `/sync-meta?after=<opaque cursor>`, every
  // META_TABLES table on the body, `next` ALWAYS present, `has_more` true while
  // any table had more than a page. Tables this package does not read
  // (`invites`, `subscriptions`, `umk_public_keys`, `min_client_version`, …)
  // must survive untouched — rule 6.
  group('D-05-20 meta', () {
    test('D-05-20 `after` is sent only when held', () async {
      final none = _Rig(
        body: {'store_epoch': 'e1', 'next': 'c1', 'has_more': false},
      );
      await none.transport.meta(const MetaRequest());
      expect(none.only.url.toString(), '${_root}sync-meta');

      final held = _Rig(
        body: {'store_epoch': 'e1', 'next': 'c2', 'has_more': false},
      );
      await held.transport.meta(const MetaRequest(after: 'eyJ0YWJsZXMiOnt9fQ'));
      expect(held.only.url.queryParameters, {'after': 'eyJ0YWJsZXMiOnt9fQ'});
    });

    test(
      'D-05-20 the tables the engine reads parse and the rest survive',
      () async {
        final res = await _Rig(
          body: {
            'store_epoch': 'epoch-9',
            'next': 'cursor-2',
            'has_more': true,
            'memberships': [
              {
                'id': '$_tenant:$_object',
                'tenant_id': _tenant,
                'user_id': _object,
                'status': 'active',
                'source_record_id': null,
                'updated_at': 1757808000000,
              },
            ],
            'book_roles': [
              {
                'id': '$_book:$_object',
                'book_id': _book,
                'user_id': _object,
                'role': 'member',
                'limits': {'auto_post_limit_paise': 500000},
                'updated_at': 1757808000000,
              },
            ],
            'devices': [
              {
                'id': _device,
                'user_id': _object,
                'pub_ed': denoB64Url(_fill(32, 5)),
                'pub_x': denoB64Url(_fill(32, 6)),
                'status': 'certified',
                'model': null,
                'os': null,
                'revoked_at': null,
                'updated_at': 1757808000000,
              },
            ],
            'device_certs': [
              {
                'device_id': _device,
                'issued_by_device': null,
                'umk_key_version': 1,
                'cert': {
                  'suite_version': 1,
                  'issued_at_ms': 1757808000000,
                  'signature': denoB64Url(_fill(64, 9)),
                },
                'updated_at': 1757808000000,
              },
            ],
            'wrapped_keys': [
              {
                'id': _object,
                'kind': 'bk_for_user',
                'user_id': _object,
                'device_id': null,
                'book_id': _book,
                'key_version': 1,
                'share_set_version': null,
                'blob': denoB64Url(_fill(80, 13)),
                'created_at': 1757808000000,
                'revoked_at': null,
                'updated_at': 1757808000000,
              },
            ],
            'signed_records': [
              {
                'id': _object,
                'seq': 30,
                'suite_version': 1,
                'tenant_id': _tenant,
                'kind': 'book_role',
                'payload_json': denoB64Url(_fill(60, 17)),
                'author_device_id': _device,
                'author_sig': denoB64Url(_fill(64, 19)),
                'hlc': _hlc,
              },
            ],
            'guardian_sets': [
              {
                'subject_user_id': _object,
                'share_set_version': 2,
                'k': 2,
                'n': 3,
                'guardian_user_ids': [_tenant, _book, _device],
                'guardians': [
                  {
                    'guardian_user_id': _tenant,
                    'umk_pub_ed': denoB64Url(_fill(32, 23)),
                  },
                ],
              },
            ],
            // Not consumed here — rule 6 says they come back out untouched.
            'invites': [
              {'id': _object, 'tenant_id': _tenant, 'status': 'live'},
            ],
            'subscriptions': [
              {'tenant_id': _tenant, 'plan': 'family', 'status': 'active'},
            ],
            'umk_public_keys': [
              {'user_id': _object, 'key_version': 1},
            ],
            'min_client_version': {'sync': '1.2.0', 'auth': '1.0.0'},
          },
        ).transport.meta(const MetaRequest());

        expect(res.storeEpoch, 'epoch-9');
        expect(res.next, 'cursor-2');
        expect(res.hasMore, isTrue);
        expect(res.memberships.single.status, 'active');
        expect(
          res.bookRoles.single.limits?[WireBookRole.autoPostLimitPaise],
          500000,
        );
        expect(res.devices.single.pubEd, _fill(32, 5));
        expect(res.deviceCerts.single.signature, _fill(64, 9));
        expect(res.deviceCerts.single.issuedAtMs, 1757808000000);
        expect(res.wrappedKeys.single.kind, WireWrappedKey.kindBkForUser);
        expect(res.signedRecords.single.seq, 30);
        expect(res.signedRecords.single.hlc, _hlc);
        expect(res.guardianSets.single.k, 2);
        expect(res.guardianSets.single.n, 3);
        // Preserved, not dropped, and re-emitted on encode.
        expect(
          res.extra.keys,
          containsAll(<String>['invites', 'subscriptions']),
        );
        expect(res.minClientVersion?['sync'], '1.2.0');
        final round = res.toJson();
        expect(round['invites'], isNotNull);
        expect(round['umk_public_keys'], isNotNull);
        expect(round['min_client_version'], isNotNull);
      },
    );
  });

  // ── D-05-21 ───────────────────────────────────────────────────────────────
  // `_shared/http.ts` `error()` bodies and the statuses the three functions
  // actually return. `engine.dart` `_guarded` branches on these being
  // distinguishable, so collapsing any two is a silent behaviour change.
  group('D-05-21 status and network mapping', () {
    Future<Object> failureOf(_Rig rig) async {
      try {
        await rig.transport.pull(const PullRequest(bookId: _book, afterSeq: 0));
        fail('expected a TransportFailure');
      } on TransportFailure catch (e) {
        return e;
      }
    }

    test(
      'D-05-21 401 unauthenticated is AuthFailed and drops the token',
      () async {
        final creds = StaticSyncCredentials('stale');
        final f = await failureOf(
          _Rig(
            status: 401,
            body: {'error': 'unauthenticated'},
            credentials: creds,
          ),
        );
        expect(f, isA<AuthFailed>());
        expect((f as AuthFailed).code, 'unauthenticated');
        expect(creds.invalidations, 1, reason: 'next call must refresh');
      },
    );

    test('D-05-21 401 device_revoked keeps its code (ADR 05b §2: suspend, '
        'never wipe)', () async {
      final f = await failureOf(
        _Rig(status: 401, body: {'error': 'device_revoked'}),
      );
      expect((f as AuthFailed).code, AuthFailed.deviceRevoked);
    });

    test(
      'D-05-21 426 is UpdateRequired and carries min_client_version',
      () async {
        final f = await failureOf(
          _Rig(
            status: 426,
            body: {'error': 'upgrade_required', 'min_client_version': '2.0.0'},
          ),
        );
        expect(f, isA<UpdateRequired>());
        expect((f as UpdateRequired).minClientVersion, '2.0.0');
      },
    );

    test('D-05-21 413 is BatchTooLarge with the detail', () async {
      final f = await failureOf(
        _Rig(
          status: 413,
          body: {'error': 'batch_too_large', 'detail': 'max 100 envelopes'},
        ),
      );
      expect(f, isA<BatchTooLarge>());
      expect((f as BatchTooLarge).detail, 'max 100 envelopes');
    });

    test('D-05-21 every other non-2xx is a RouteRefused carrying status and '
        'code', () async {
      const cases = <int, String>{
        400: 'bad_cursor',
        403: RouteRefused.noRole,
        404: RouteRefused.unknownBook,
        405: 'method_not_allowed',
        409: 'record_replayed',
        429: 'ceremony_flood',
        500: 'internal',
      };
      for (final entry in cases.entries) {
        final f = await failureOf(
          _Rig(status: entry.key, body: {'error': entry.value}),
        );
        expect(f, isA<RouteRefused>(), reason: '${entry.key}');
        expect((f as RouteRefused).status, entry.key);
        expect(f.code, entry.value);
      }
    });

    test(
      'D-05-21 a non-2xx with an unreadable body is still typed by status',
      () async {
        final f = await failureOf(
          _Rig(status: 502, body: '<html>gateway</html>'),
        );
        expect(f, isA<RouteRefused>());
        expect((f as RouteRefused).status, 502);
        expect(f.code, isNull);
      },
    );

    test(
      'D-05-21 a dropped request and a timeout are TransportOffline',
      () async {
        final dropped = _Rig(body: const <String, Object?>{})
          ..throwOnSend = http.ClientException('connection closed');
        expect(await failureOf(dropped), isA<TransportOffline>());

        // A server that accepts the connection and then never answers: the
        // deadline, not the socket, is what makes this one offline.
        final hung = _Rig(
          body: const <String, Object?>{},
          timeout: const Duration(milliseconds: 20),
          hang: true,
        );
        expect(await failureOf(hung), isA<TransportOffline>());
        expect(hung.requests, hasLength(1), reason: 'sent, not refused');
      },
    );
  });

  // ── D-05-22 ───────────────────────────────────────────────────────────────
  // 05 §1 🔒 (ADR 2026-09-05 §1): SPKI pins, key not certificate, at least two,
  // hard fail with no fallback and no override. The pin set is the one in
  // `spki_pins.dart` — there is no second mechanism.
  group('D-05-22 SPKI pinning', () {
    test(
      'D-05-22 a matching chain goes through and is asked per request',
      () async {
        final chain = StaticTlsChainSource([_fill(32, 99), _pinned]);
        final rig = _Rig(
          body: {'store_epoch': 'e1', 'envelopes': <Object?>[], 'next_seq': 0},
          pins: livePins(),
          chain: chain,
        );
        await rig.transport.pull(const PullRequest(bookId: _book, afterSeq: 0));
        await rig.transport.pull(const PullRequest(bookId: _book, afterSeq: 0));
        expect(rig.requests, hasLength(2));
        expect(chain.asked, hasLength(2), reason: 'checked on every request');
      },
    );

    test('D-05-22 a chain that matches no pin sends nothing', () async {
      final rig = _Rig(
        body: {'store_epoch': 'e1', 'envelopes': <Object?>[], 'next_seq': 0},
        pins: livePins(),
        chain: StaticTlsChainSource([_fill(32, 77)]),
      );
      await expectLater(
        rig.transport.pull(const PullRequest(bookId: _book, afterSeq: 0)),
        // Its own cause since ADR 2026-09-15 §7 🔒 — *Needs attention*, not
        // *Offline*: the network may be fine and the server impersonated.
        throwsA(isA<PinFailed>()),
      );
      expect(rig.requests, isEmpty, reason: 'no fallback, no override');
    });

    test('D-05-22 an unknown chain fails closed', () async {
      final rig = _Rig(
        body: {'store_epoch': 'e1', 'results': <Object?>[]},
        pins: livePins(),
        chain: StaticTlsChainSource(null),
      );
      await expectLater(
        rig.transport.push(const PushRequest(envelopes: [])),
        throwsA(isA<PinFailed>()),
      );
      expect(rig.requests, isEmpty);
    });

    test(
      'D-05-22 a live pin set without a chain source is refused at build',
      () {
        expect(
          () => HttpSyncTransport(
            client: MockClient((_) async => http.Response('{}', 200)),
            functionsRoot: Uri.parse(_root),
            credentials: StaticSyncCredentials('t'),
            clientVersion: '1.0.0',
            pins: livePins(),
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('D-05-22 only a local-dev set may run unpinned', () async {
      final rig = _Rig(
        body: {'store_epoch': 'e1', 'results': <Object?>[]},
        pins: const SpkiPins.localDev(),
      );
      await rig.transport.push(const PushRequest(envelopes: []));
      expect(rig.requests, hasLength(1));
    });
  });

  // ── D-05-23 ───────────────────────────────────────────────────────────────
  // Nothing the engine acts on may be invented by this file: an answer it
  // cannot read is a route-level refusal (cursors and outbox rows untouched),
  // never an empty page that would advance a cursor past unseen envelopes.
  group('D-05-23 never invent an answer', () {
    test('D-05-23 a 2xx this build cannot read is a RouteRefused', () async {
      for (final body in <Object?>[
        '<html>ok</html>',
        {'store_epoch': 'e1'}, // pull without `envelopes` / `next_seq`
        {'envelopes': <Object?>[], 'next_seq': 3}, // no store_epoch
      ]) {
        final rig = _Rig(body: body);
        await expectLater(
          rig.transport.pull(const PullRequest(bookId: _book, afterSeq: 3)),
          throwsA(
            isA<RouteRefused>().having(
              (e) => e.code,
              'code',
              ClientFailureCode.malformedResponse,
            ),
          ),
        );
      }
    });

    test(
      'D-05-23 no live session is a plain 401, and nothing is sent',
      () async {
        final rig = _Rig(
          body: const <String, Object?>{},
          credentials: _NoSession(),
        );
        await expectLater(
          rig.transport.meta(const MetaRequest()),
          throwsA(
            isA<AuthFailed>().having(
              (e) => e.code,
              'code',
              ClientFailureCode.noSession,
            ),
          ),
        );
        expect(rig.requests, isEmpty);
      },
    );
  });
  // ── D-05-24 … D-05-31 ─────────────────────────────────────────────────────
  // The WRITE half of `/sync-meta`, which this transport could not reach at
  // all until now: a device could pull every structural fact the family
  // authored and contribute none of its own (ADR 2026-09-05b §1 🔒, 06 §7 🔒).
  //
  // Server side, line by line: `sync-meta/index.ts` `postRecords` /
  // `intakeRecord` / `invites` / `inviteError`, `_shared/records.ts`
  // `parseRecord` + `parseInvitePayload`, migration 0008's header. The suite
  // `server/supabase/functions/_tests/invites_route.test.ts` (E-06-30 …
  // E-06-35, C-05d-9) is the other half of every expectation below.

  /// A signed record on its way out, as `parseRecord` will read it.
  WireRecordPost post({String kind = 'book_role', String? id}) =>
      WireRecordPost(
        id: id ?? _object,
        suiteVersion: 1,
        tenantId: _tenant,
        kind: kind,
        payloadJson: Uint8List.fromList(
          utf8.encode(
            '{"user_id":"$_book","book_id":"$_book","role":"member"}',
          ),
        ),
        authorDeviceId: _device,
        authorSig: _fill(64, 5),
        hlc: _hlc,
      );

  group('D-05-24 publishing a signed record', () {
    test('D-05-24 postRecords sends exactly what parseRecord reads', () async {
      final rig = _Rig(
        body: {
          'store_epoch': 'e1',
          'results': [
            {'id': _object, 'result': 'acked', 'seq': '4210'},
          ],
        },
      );
      final res = await rig.transport.postRecords(
        PostRecordsRequest(records: [post()]),
      );

      expect(rig.only.method, 'POST');
      expect(rig.only.url.toString(), '${_root}sync-meta/records');
      expect(rig.only.headers['content-type'], startsWith('application/json'));
      expect(
        rig.only.headers[HttpSyncTransport.clientVersionHeader],
        '1.4.0',
        reason: 'every sync route is version-gated before auth runs',
      );

      final records = rig.sentJson['records']! as List<Object?>;
      final r = records.single! as Map<String, Object?>;
      expect(r.keys.toSet(), {
        'id',
        'suite_version',
        'tenant_id',
        'kind',
        'payload_json',
        'author_device_id',
        'author_sig',
        'hlc',
      }, reason: 'parseRecord reads these and no others');
      // `seq` is the server's to stamp at receipt (ADR 05b §5): a client that
      // claimed one would be asserting an ordering it cannot know.
      expect(r.containsKey('seq'), isFalse);
      expect(r['hlc'], isA<int>(), reason: 'a bare integer literal past 2^53');
      expect(_hlc > 9007199254740992, isTrue);
      expect(rig.only.body, contains('"hlc":$_hlc'));
      expect(
        base64.decode(base64.normalize(r['author_sig']! as String)),
        _fill(64, 5),
      );
      expect(
        utf8.decode(
          base64.decode(base64.normalize(r['payload_json']! as String)),
        ),
        startsWith('{"user_id"'),
        reason: 'the exact signed bytes, never re-encoded',
      );

      // `seq` comes back as a decimal STRING on this route (`seq.toString()`),
      // unlike the bare integer of a pulled record.
      expect(res.storeEpoch, 'e1');
      expect(res[_object]!.isAcked, isTrue);
      expect(res[_object]!.seq, 4210);
    });

    test('D-05-25 a refused record is a result, not a route failure', () async {
      final rig = _Rig(
        body: {
          'store_epoch': 'e1',
          'results': [
            {'id': _object, 'result': 'acked', 'seq': '9'},
            {
              'id': _envelope,
              'result': 'rejected:shape',
              'seq': '10',
              'check': 'payload_json',
            },
            {'id': _book, 'result': 'rejected:invite_route', 'seq': '11'},
          ],
        },
      );
      final res = await rig.transport.postRecords(
        PostRecordsRequest(
          records: [
            post(),
            post(id: _envelope),
            post(id: _book),
          ],
        ),
      );

      expect(res.results, hasLength(3));
      expect(res[_object]!.isAcked, isTrue);
      final refused = res[_envelope]!;
      expect(refused.isAcked, isFalse);
      expect(refused.rejection, 'shape');
      expect(refused.check, 'payload_json');
      // Stored even so — it is a signed fact (append-only); the server's note
      // says why it was not applied, and the seq proves it was kept.
      expect(refused.seq, 10);
      expect(res[_book]!.result, RecordAck.rejectedInviteRoute);
      // A record the server did not judge is UNACKNOWLEDGED, never acked by
      // position: an outbox that read results positionally would drop a
      // record the server quietly skipped.
      expect(res['never-sent'], isNull);
    });

    test('D-05-26 a batch over the cap never leaves the client', () async {
      final rig = _Rig(body: {'store_epoch': 'e1', 'results': <Object?>[]});
      final tooMany = [
        for (var i = 0; i <= PostRecordsRequest.batchMax; i++)
          post(id: '$_object-$i'),
      ];
      await expectLater(
        rig.transport.postRecords(PostRecordsRequest(records: tooMany)),
        throwsA(isA<BatchTooLarge>()),
      );
      expect(
        rig.requests,
        isEmpty,
        reason:
            'the server refuses the batch WHOLE — nothing may be assumed '
            'stored, so the caller must split rather than discover it',
      );
      expect(PostRecordsRequest.batchMax, 50, reason: 'RECORDS_BATCH_MAX');

      final refused = _Rig(status: 413, body: {'error': 'batch_too_large'});
      await expectLater(
        refused.transport.postRecords(PostRecordsRequest(records: [post()])),
        throwsA(isA<BatchTooLarge>()),
      );
    });
  });

  // ── 06 §7 invites ─────────────────────────────────────────────────────────
  group('D-05-27 issuing an invite', () {
    test('D-05-27 the record carries the grants, the request the number', () async {
      final rig = _Rig(
        body: {'invite_id': _envelope, 'record_id': _object, 'seq': '77'},
      );
      final issued = await rig.transport.createInvite(
        CreateInviteRequest(
          record: post(kind: 'invite'),
          phone: '+919876500011',
        ),
      );

      expect(rig.only.method, 'POST');
      expect(rig.only.url.toString(), '${_root}sync-meta/invites');
      final sent = rig.sentJson;
      expect(sent.keys.toSet(), {'record', 'phone'});
      expect(sent['phone'], '+919876500011');
      final r = sent['record']! as Map<String, Object?>;
      expect(r['kind'], 'invite');
      // ADR 2026-09-05c §4 / 0008 ⚠️ SPEC: the number is in the REQUEST, never
      // in the record — the admin's device cannot compute `invitee_hmac`, and
      // a record that named the invitee would be broadcast to every member.
      expect(r.containsKey('phone'), isFalse);
      expect(r.containsKey('invitee_hmac'), isFalse);

      expect(issued.inviteId, _envelope);
      expect(issued.recordId, _object);
      expect(issued.seq, 77);
    });

    test('D-05-28 every invite refusal keeps its own name', () async {
      Future<Object> refusalOf(int status, Map<String, Object?> body) async {
        try {
          await _Rig(status: status, body: body).transport.createInvite(
            CreateInviteRequest(
              record: post(kind: 'invite'),
              phone: '+919876500011',
            ),
          );
          fail('expected a TransportFailure');
        } on TransportFailure catch (e) {
          return e;
        }
      }

      final notAdmin = await refusalOf(403, {'error': RouteRefused.notAdmin});
      expect((notAdmin as RouteRefused).code, RouteRefused.notAdmin);
      expect(notAdmin.status, 403);

      final replay = await refusalOf(409, {
        'error': RouteRefused.recordReplayed,
      });
      expect((replay as RouteRefused).code, RouteRefused.recordReplayed);

      final badPhone = await refusalOf(400, {'error': RouteRefused.badPhone});
      expect((badPhone as RouteRefused).code, RouteRefused.badPhone);

      // `{error: bad_record, check}` — the 400 that names the field. `check` is
      // `detail` by another name; losing it leaves the Inbox unable to explain.
      final badRecord = await refusalOf(400, {
        'error': RouteRefused.badRecord,
        'check': 'payload_json',
      });
      expect((badRecord as RouteRefused).code, RouteRefused.badRecord);
      expect(badRecord.detail, 'payload_json');
    });
  });

  group('D-05-29 the joiner side', () {
    test('D-05-29 an offer says who invited me, and nothing about anyone '
        'else', () async {
      final rig = _Rig(
        body: {
          'invites': [
            {
              'invite_id': _envelope,
              'tenant_id': _tenant,
              'roles': [
                {'book_id': _book, 'role': 'member'},
              ],
              'expires_at': 1757808000000,
              'created_by': _object,
              // a column a later server adds — rule 6 keeps it
              'note': 'from Sunita',
            },
          ],
        },
      );
      final offers = await rig.transport.myInvites();

      expect(rig.only.method, 'GET');
      expect(rig.only.url.toString(), '${_root}sync-meta/invites');
      expect(offers, hasLength(1));
      final o = offers.single;
      expect(o.inviteId, _envelope);
      expect(o.tenantId, _tenant);
      expect(o.createdBy, _object);
      expect(o.expiresAtMs, 1757808000000, reason: '06 §7: a 7-day window');
      expect(o.roleGrants.single['role'], 'member');
      expect(o.extra['note'], 'from Sunita');
      expect(o.toJson()['note'], 'from Sunita', reason: 'rule 6 round-trip');
      // The offer is not an oracle: the wire carries no hmac, nonce or number,
      // so this type has nowhere to put one.
      expect(o.toJson().keys, isNot(contains('invitee_hmac')));
      expect(o.toJson().keys, isNot(contains('nonce')));

      final empty = _Rig(body: const <String, Object?>{});
      expect(await empty.transport.myInvites(), isEmpty);
    });

    test('D-05-30 accepting lands on joined_pending_verification, never '
        'active', () async {
      final rig = _Rig(
        body: {'invite_id': _envelope, 'status': 'joined_pending_verification'},
      );
      final accepted = await rig.transport.acceptInvite(_envelope);

      expect(rig.only.method, 'POST');
      expect(rig.only.url.toString(), '${_root}sync-meta/invites/accept');
      expect(rig.sentJson, {'invite_id': _envelope});
      expect(accepted.inviteId, _envelope);
      expect(accepted.status, InviteAcceptance.joinedPendingVerification);
      expect(
        accepted.status,
        isNot('active'),
        reason: '06 §7: only the ceremony grants active',
      );
    });

    test('D-05-30 a wrong number and an unknown invite refuse identically '
        '(ADR 2026-09-05d §9)', () async {
      Future<RouteRefused> refusalOf() async {
        try {
          await _Rig(
            status: 403,
            body: {'error': RouteRefused.inviteNotForYou},
          ).transport.acceptInvite(_envelope);
          fail('expected a TransportFailure');
        } on RouteRefused catch (e) {
          return e;
        }
      }

      // One code for both cases: the link alone admits nobody, and the route
      // must not tell a stranger whether that invite exists.
      expect((await refusalOf()).code, RouteRefused.inviteNotForYou);

      for (final c in <int, String>{
        410: RouteRefused.inviteExpired,
        409: RouteRefused.inviteNotLive,
      }.entries) {
        try {
          await _Rig(
            status: c.key,
            body: {'error': c.value},
          ).transport.acceptInvite(_envelope);
          fail('expected a TransportFailure');
        } on RouteRefused catch (e) {
          expect(e.status, c.key);
          expect(e.code, c.value);
        }
      }
    });
  });

  group('D-05-31 the write routes invent nothing either', () {
    test('D-05-31 a 2xx this build cannot read is a RouteRefused', () async {
      final calls = <String, Future<Object?> Function(HttpSyncTransport)>{
        'records': (t) => t.postRecords(PostRecordsRequest(records: [post()])),
        'invites': (t) => t.createInvite(
          CreateInviteRequest(
            record: post(kind: 'invite'),
            phone: '+919876500011',
          ),
        ),
        'accept': (t) => t.acceptInvite(_envelope),
      };
      for (final entry in calls.entries) {
        final rig = _Rig(body: {'unexpected': true});
        await expectLater(
          entry.value(rig.transport),
          throwsA(
            isA<RouteRefused>().having(
              (e) => e.code,
              'code',
              ClientFailureCode.malformedResponse,
            ),
          ),
          reason: entry.key,
        );
      }
    });
  });
}

final class _NoSession implements SyncCredentials {
  @override
  Future<String> accessToken() async => throw StateError('session ended');

  @override
  Future<void> invalidate() async {}
}
