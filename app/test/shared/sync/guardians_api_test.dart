// The wire contract of 04 §7.3 Setup — what leaves this device and what it
// makes of what comes back.
//
// ⚠️ WIRE: every expectation here is taken from
// `server/supabase/functions/sync-meta/index.ts` (`pull`'s `guardian_sets`
// block and `parseGuardianDraft`) and migration 0010. A change on either side
// lands here first.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/sync/guardians_api.dart';
import 'package:rukka_folio/shared/sync/recovery_api.dart';

import 'guardian_test_keys.dart';

const _root = 'https://api.example.test/functions/v1/';

HttpGuardiansApi _api(RkHttpTransport transport) => HttpGuardiansApi(
  transport: transport,
  functionsRoot: Uri.parse(_root),
  accessToken: () async => 'tok',
);

void main() {
  test('C-06-42 the read side is the meta pull, asked with no cursor and no '
      'subject — the server names the subject, and this read never moves the '
      "engine's cursor (05 §5)", () async {
    late Uri asked;
    final transport = FakeRkHttpTransport((method, url, headers, body) {
      asked = url;
      return RkHttpResponse(
        200,
        jsonEncode({
          'store_epoch': 1,
          'guardian_sets': [
            {
              'subject_user_id': userMe,
              'share_set_version': 1,
              'k': 2,
              'n': 3,
              'guardian_user_ids': ['g1', 'g2', 'g3'],
              'guardians': [
                {
                  'guardian_user_id': 'g1',
                  'umk_pub_ed': encodeB64Url(
                    Uint8List.fromList(List.filled(32, 7)),
                  ),
                },
                {'guardian_user_id': 'g2', 'umk_pub_ed': ''},
                {'guardian_user_id': 'g3', 'umk_pub_ed': ''},
              ],
            },
          ],
        }),
      );
    });

    final sets = await _api(transport).sets();

    expect(asked.toString(), '${_root}sync-meta');
    expect(asked.hasQuery, isFalse, reason: 'no after=, no subject_user_id=');
    expect(sets, hasLength(1));
    expect(sets.single.subjectUserId, userMe);
    expect(sets.single.shareSetVersion, 1);
    expect(sets.single.k, 2);
    expect(sets.single.n, 3);
    expect(sets.single.guardianUserIds, ['g1', 'g2', 'g3']);
    expect(sets.single.members.first.umkPubEd, hasLength(32));
  });

  test('C-06-43 a body carrying only guardian_user_ids still yields the '
      'membership, with no keys — a set is read, never inferred', () async {
    final transport = FakeRkHttpTransport(
      (method, url, headers, body) => RkHttpResponse(
        200,
        jsonEncode({
          'guardian_sets': [
            {
              'subject_user_id': userMe,
              'share_set_version': 4,
              'k': 3,
              'n': 4,
              'guardian_user_ids': ['g1', 'g2', 'g3', 'g4'],
            },
          ],
        }),
      ),
    );

    final sets = await _api(transport).sets();
    expect(sets.single.guardianUserIds, ['g1', 'g2', 'g3', 'g4']);
    expect(sets.single.members.every((m) => m.umkPubEd.isEmpty), isTrue);
  });

  test('C-06-44 the write body is {share_set_version, k, n, guardians:[…]} and '
      'umk_pub_ed is read off the VERIFIED key, never off the wire (rule 5, '
      '04 §8.2 🔒)', () async {
    final suite = await liveSuite();
    final g1 = TestGuardian.generate(suite, userGuardians[0]);
    final g2 = TestGuardian.generate(suite, userGuardians[1]);
    addTearDown(() {
      g1.umk.dispose();
      g2.umk.dispose();
    });
    String? sent;
    final transport = FakeRkHttpTransport((method, url, headers, body) {
      sent = body;
      return RkHttpResponse(200, jsonEncode({'share_set_version': 5}));
    });

    final shares = [
      for (final g in [g1, g2])
        SealedGuardianShare(
          guardian: VerifiedGuardian(userId: g.userId, umk: g.verified),
          blob: sealToVerified(
            suite,
            g.verified,
            Uint8List.fromList([1, 2, 3]),
          ),
        ),
    ];

    final version = await _api(transport)
        .publish(shareSetVersion: 5, k: 2, shares: shares);

    expect(version, 5);
    final body = jsonDecode(sent!) as Map<String, Object?>;
    expect(body['share_set_version'], 5);
    expect(body['k'], 2);
    expect(body['n'], 2);
    final guardians = (body['guardians']! as List).cast<Map<String, Object?>>();
    expect(guardians.map((g) => g['guardian_user_id']), [
      userGuardians[0],
      userGuardians[1],
    ]);
    // Unpadded base64url of the 32-byte Ed25519 half of the verified key —
    // `parseGuardianDraft` refuses anything else.
    expect(
      guardians.first['umk_pub_ed'],
      encodeB64Url(g1.verified.public.ed25519),
    );
    expect(
      decodeB64Url(guardians.first['umk_pub_ed'] as String),
      hasLength(32),
    );
    expect((guardians.first['umk_pub_ed'] as String).contains('='), isFalse);
    expect(decodeB64Url(guardians.first['blob'] as String), isNotEmpty);
    expect(
      Uri.parse(transport.calls.single.url.toString()).path,
      endsWith('/sync-meta/recovery/guardians'),
    );
  });

  test(
    'C-06-45 a share can only be filed under the guardian it was sealed to — '
    "a sealer's slip is an ArgumentError here, not a set that cannot reach "
    'its own quorum',
    () async {
      final suite = await liveSuite();
      final g1 = TestGuardian.generate(suite, userGuardians[0]);
      final g2 = TestGuardian.generate(suite, userGuardians[1]);
      addTearDown(() {
        g1.umk.dispose();
        g2.umk.dispose();
      });

      expect(
        () => SealedGuardianShare(
          guardian: VerifiedGuardian(userId: g1.userId, umk: g1.verified),
          // Sealed to g2, filed under g1.
          blob: sealToVerified(suite, g2.verified, Uint8List.fromList([9])),
        ),
        throwsArgumentError,
      );
      expect(
        () => SealedGuardianShare(
          guardian: VerifiedGuardian(userId: g1.userId, umk: g1.verified),
          blob: SealedBlob(
            recipient: g1.verified.fingerprint,
            bytes: Uint8List(0),
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'C-06-46 refusals are named, not guessed: the guardian routes answer with '
    "`recoveryError`'s words and a transport that never answered is offline",
    () async {
      Future<RecoveryRefusal> refusalOf(int status, String? error) async {
        final api = _api(
          FakeRkHttpTransport(
            (method, url, headers, body) => RkHttpResponse(
              status,
              error == null ? '' : jsonEncode({'error': error}),
            ),
          ),
        );
        try {
          await api.sets();
          fail('expected a refusal');
        } on RecoveryApiFailure catch (e) {
          return e.refusal;
        }
      }

      expect(
        await refusalOf(400, 'share_set_version_out_of_order'),
        RecoveryRefusal.badRequest,
      );
      expect(
        await refusalOf(400, 'guardian_quorum'),
        RecoveryRefusal.badRequest,
      );
      expect(
        await refusalOf(400, 'guardian_set_size'),
        RecoveryRefusal.badRequest,
      );
      expect(
        await refusalOf(400, 'guardian_is_subject'),
        RecoveryRefusal.badRequest,
      );
      expect(
        await refusalOf(409, 'no_guardian_set'),
        RecoveryRefusal.noGuardianSet,
      );
      expect(await refusalOf(401, null), RecoveryRefusal.unauthorized);
      expect(
        await refusalOf(426, 'upgrade_required'),
        RecoveryRefusal.upgradeRequired,
      );

      final dead = _api(
        FakeRkHttpTransport((method, url, headers, body) {
          throw const RkHttpFailure('down');
        }),
      );
      await expectLater(
        dead.sets(),
        throwsA(
          isA<RecoveryApiFailure>().having(
            (e) => e.refusal,
            'refusal',
            RecoveryRefusal.offline,
          ),
        ),
      );
    },
  );

  group('F1-24b-4 GET sync-meta/recovery/has-guardian-set (ADR 2026-09-24b '
      '§3, ⚠️ WIRE sync-meta/index.ts `recovery` + migration 0016)', () {
    test('F1-24b-4 the bit is asked on its own route: GET, the session\'s '
        'Bearer, no query at all — the server keys it on the claims, and a '
        '`subject_user_id=` here would be the enumeration oracle the ADR '
        'forbids', () async {
      final transport = FakeRkHttpTransport(
        (method, url, headers, body) =>
            RkHttpResponse(200, jsonEncode({'has_guardian_set': true})),
      );
      final api = HttpGuardiansApi(
        transport: transport,
        functionsRoot: Uri.parse(_root),
        accessToken: () async => 'tok',
        clientVersion: '0.1.0',
      );

      expect(await api.hasGuardianSet(), isTrue);

      final call = transport.calls.single;
      expect(call.method, 'GET');
      expect(
        call.url.toString(),
        '${_root}sync-meta/recovery/has-guardian-set',
      );
      expect(call.url.hasQuery, isFalse, reason: 'no subject, no cursor');
      expect(call.headers['authorization'], 'Bearer tok');
      expect(call.headers[HttpRecoveryApi.clientVersionHeader], '0.1.0');
    });

    test('F1-24b-4 `true` and `false` are read as themselves — the two '
        'answers are not collapsed into one', () async {
      Future<bool> read(bool wire) => _api(
        FakeRkHttpTransport(
          (method, url, headers, body) =>
              RkHttpResponse(200, jsonEncode({'has_guardian_set': wire})),
        ),
      ).hasGuardianSet();

      expect(await read(true), isTrue);
      expect(await read(false), isFalse);
    });

    test('F1-24b-4 only a JSON boolean is an answer: a missing field, null, '
        'a string, a number, an array body or a body that is not JSON is an '
        'ERROR, never `false` — `false` is the one reading that tells a '
        'locked-out person they set nobody up', () async {
      final bodies = <String, String>{
        'field missing': jsonEncode(<String, Object?>{}),
        'field null': jsonEncode({'has_guardian_set': null}),
        'string "false"': jsonEncode({'has_guardian_set': 'false'}),
        'string "true"': jsonEncode({'has_guardian_set': 'true'}),
        'number 0': jsonEncode({'has_guardian_set': 0}),
        'number 1': jsonEncode({'has_guardian_set': 1}),
        'misspelt field': jsonEncode({'hasGuardianSet': false}),
        'array body': jsonEncode([false]),
        'empty body': '',
        'not JSON': 'false',
      };
      for (final MapEntry(key: name, value: text) in bodies.entries) {
        final api = _api(
          FakeRkHttpTransport(
            (method, url, headers, body) => RkHttpResponse(200, text),
          ),
        );
        await expectLater(
          api.hasGuardianSet(),
          throwsA(isA<RecoveryApiFailure>()),
          reason: name,
        );
      }
    });

    test('F1-24b-4 a refusal or a silent transport is a named failure, never '
        'an answer', () async {
      for (final (status, error, refusal) in const [
        (401, 'unauthorized', RecoveryRefusal.unauthorized),
        (403, 'rls', RecoveryRefusal.unauthorized),
        (500, null, RecoveryRefusal.server),
      ]) {
        final api = _api(
          FakeRkHttpTransport(
            (method, url, headers, body) => RkHttpResponse(
              status,
              error == null ? '' : jsonEncode({'error': error}),
            ),
          ),
        );
        await expectLater(
          api.hasGuardianSet(),
          throwsA(
            isA<RecoveryApiFailure>().having(
              (f) => f.refusal,
              'refusal',
              recoveryRefusalOf(error, status),
            ),
          ),
        );
        expect(recoveryRefusalOf(error, status), refusal);
      }

      final silent = _api(
        FakeRkHttpTransport(
          (method, url, headers, body) => throw const RkHttpFailure('down'),
        ),
      );
      await expectLater(
        silent.hasGuardianSet(),
        throwsA(
          isA<RecoveryApiFailure>().having(
            (f) => f.refusal,
            'refusal',
            RecoveryRefusal.offline,
          ),
        ),
      );

      final signedOut = HttpGuardiansApi(
        transport: FakeRkHttpTransport(
          (method, url, headers, body) => fail('no session, no request'),
        ),
        functionsRoot: Uri.parse(_root),
        accessToken: () async => null,
      );
      await expectLater(
        signedOut.hasGuardianSet(),
        throwsA(
          isA<RecoveryApiFailure>().having(
            (f) => f.refusal,
            'refusal',
            RecoveryRefusal.unauthorized,
          ),
        ),
      );
    });
  });
}
