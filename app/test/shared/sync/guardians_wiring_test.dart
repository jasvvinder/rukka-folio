// The shell's side of 04 §7.3 Setup: the scope that hands S11.1 a real
// repository instead of the seam's fake.
//
// This is a wiring fact of the kind that fails silently. With no scope the
// screen falls back to [FakeGuardians], which **accepts a set and reports a
// split that never happened** — a green trusted-member screen over a recovery
// that cannot work. So the test that matters is not that the scope compiles
// but that what comes out of it is not the fake.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/guardians.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/sync/guardians_seams.dart';
import 'package:sync_engine/sync_engine.dart' show MapUmkSource;

import 'guardian_test_keys.dart';

/// Synthetic tenant ids (rule 4) — canonical uuids, as `parseGuardianDraft`
/// takes nothing else.
const _tenantA = '55555555-5555-4555-8555-555555555551';
const _tenantB = '55555555-5555-4555-8555-555555555552';

/// A transport that answers the meta pull with no history and the publish
/// with the version it was sent, recording every POST body.
({FakeRkHttpTransport transport, List<Map<String, Object?>> posts}) _server() {
  final posts = <Map<String, Object?>>[];
  final transport = FakeRkHttpTransport((method, url, headers, body) {
    if (method == 'POST') {
      final b = (jsonDecode(body!) as Map).cast<String, Object?>();
      posts.add(b);
      return RkHttpResponse(
        200,
        jsonEncode({'share_set_version': b['share_set_version']}),
      );
    }
    return RkHttpResponse(200, jsonEncode({'guardian_sets': <Object?>[]}));
  });
  return (transport: transport, posts: posts);
}

void main() {
  testWidgets(
    'F1-06-45 GuardiansScope hands the live producer down, a screen reads it '
    'without knowing which it got, and what it gets is not the fake',
    (tester) async {
      final repository = ServerGuardians(
        api: HttpGuardiansApi(
          transport: FakeRkHttpTransport(
            (method, url, headers, body) => const RkHttpResponse(200, '{}'),
          ),
          functionsRoot: Uri.parse('https://api.example.test/functions/v1/'),
          accessToken: () async => 'tok',
        ),
        roster: () async => const GuardianRoster(),
        verified: const MapUmkSource({}),
      );
      addTearDown(repository.dispose);

      GuardiansRepository? seen;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GuardiansScope(
            repository: repository,
            child: Builder(
              builder: (context) {
                seen = GuardiansScope.maybeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(seen, same(repository));
      expect(seen, isNot(isA<FakeGuardians>()));
    },
  );

  testWidgets(
    'F1-06-46 with no scope the seam answers null, which is what lets a '
    'screen fall back on its own rather than throw (07 §1 rule 6)',
    (tester) async {
      GuardiansRepository? seen = FakeGuardians();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              seen = GuardiansScope.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, isNull);
    },
  );

  group('F1-03b-2 S11.1 save publishes into the current tenant '
      '(ADR 2026-10-03b §1 🔒)', () {
    late CryptoSuite suite;
    late List<TestGuardian> guardians;

    setUpAll(() async {
      suite = await liveSuite();
      guardians = [
        for (final id in userGuardians.take(3))
          TestGuardian.generate(suite, id),
      ];
    });
    tearDownAll(() {
      for (final g in guardians) {
        g.umk.dispose();
      }
    });

    ServerGuardians build(
      FakeRkHttpTransport transport, {
      required String? Function() tenant,
      List<GuardianSplitRequest>? sealed,
    }) {
      final repo = ServerGuardians(
        api: HttpGuardiansApi(
          transport: transport,
          functionsRoot: Uri.parse('https://api.example.test/functions/v1/'),
          accessToken: () async => 'tok',
        ),
        roster: () async => GuardianRoster(
          candidates: [
            for (final g in guardians)
              GuardianCandidateRow(
                userId: g.userId,
                name: 'Member',
                ceremony: GuardianCeremony.done,
              ),
            const GuardianCandidateRow(
              userId: userMe,
              name: 'You',
              ceremony: GuardianCeremony.done,
              isYou: true,
            ),
          ],
          tenantId: tenant(),
        ),
        verified: MapUmkSource({
          for (final g in guardians) g.userId: g.verified,
        }),
        sealer: (request) async {
          sealed?.add(request);
          return [
            for (final g in request.guardians)
              SealedGuardianShare(
                guardian: g,
                blob: sealToVerified(suite, g.umk, Uint8List.fromList([7])),
              ),
          ];
        },
      );
      addTearDown(repo.dispose);
      return repo;
    }

    test('the publish body names the tenant the roster was read in — and '
        'the tenant of the LATEST reading, not a remembered one', () async {
      final server = _server();
      var tenant = _tenantA;
      final repo = build(server.transport, tenant: () => tenant);

      await repo.refresh();
      await repo.save([guardians[0].userId, guardians[1].userId]);

      expect(server.posts, hasLength(1));
      final body = server.posts.single;
      expect(body['tenant_id'], _tenantA);
      expect(body['share_set_version'], 1);
      expect(body['k'], 2);
      expect(body['n'], 2);
      final post = server.transport.calls.lastWhere((c) => c.method == 'POST');
      expect(post.url.path, endsWith('/sync-meta/recovery/guardians'));

      // The roster moved to another tenant: the next set goes there.
      tenant = _tenantB;
      await repo.refresh();
      await repo.save([for (final g in guardians) g.userId]);
      expect(server.posts, hasLength(2));
      expect(server.posts.last['tenant_id'], _tenantB);
    });

    test('no tenant, no publish: refused as no_tenant before a share is '
        'sealed or a byte is sent (the server would answer 400)', () async {
      for (final missing in <String?>[null, '']) {
        final server = _server();
        final sealed = <GuardianSplitRequest>[];
        final repo = build(
          server.transport,
          tenant: () => missing,
          sealed: sealed,
        );
        await repo.refresh();
        await expectLater(
          repo.save([guardians[0].userId, guardians[1].userId]),
          throwsA(
            isA<GuardiansFailure>().having(
              (f) => f.reason,
              'reason',
              'no_tenant',
            ),
          ),
          reason: 'tenant $missing',
        );
        expect(server.posts, isEmpty, reason: 'tenant $missing');
        expect(sealed, isEmpty, reason: 'tenant $missing');
      }
    });

    test('the api itself refuses an empty tenant without sending', () async {
      final server = _server();
      final api = HttpGuardiansApi(
        transport: server.transport,
        functionsRoot: Uri.parse('https://api.example.test/functions/v1/'),
        accessToken: () async => 'tok',
      );
      await expectLater(
        api.publishInTenant(
          tenantId: '',
          shareSetVersion: 1,
          k: 2,
          shares: const [],
        ),
        throwsA(
          isA<RecoveryApiFailure>().having(
            (f) => f.refusal,
            'refusal',
            RecoveryRefusal.badRequest,
          ),
        ),
      );
      expect(server.transport.calls, isEmpty);
    });
  });
}
