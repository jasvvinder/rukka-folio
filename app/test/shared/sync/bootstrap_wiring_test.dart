// F1-05-30, F1-05-31: the composition root's half of the socket — the pin
// decision (05 §1 🔒), the transport it builds, and the identity it reads
// before anything is opened.
//
// F1-03b-3, F1-03b-4: the root's half of ADR 2026-10-03b §1 and §4 🔒 — the
// roster S11.1 publishes from names the install's tenant, and the S11
// guardians row's reading is installed over the trust store the engine fills.
// Both were green in their own suites and wired to nothing (M13-REV89U review
// findings 1–2), so each test here drives the production builder the root
// calls and then pins that the root calls it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show CryptoSuite, UmkKeyPair;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rukka_folio/bootstrap.dart';
import 'package:rukka_folio/features/devices/guardian_standing.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/sync/guardian_sealing.dart';
import 'package:rukka_folio/shared/sync/guardians_seams.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import 'guardian_test_keys.dart';

/// Synthetic tenant id (rule 4) — canonical, as `parseGuardianDraft` takes
/// nothing else.
const _tenant = '55555555-5555-4555-8555-555555555553';

/// The live S11.1 client over a transport that answers the read with [sets]
/// (no history by default) and the publish with the version it was sent,
/// recording every POST body — what actually leaves the device.
HttpGuardiansApi _api(
  List<Map<String, Object?>> posts, {
  List<Map<String, Object?>> sets = const [],
}) => HttpGuardiansApi(
  transport: FakeRkHttpTransport((method, url, headers, body) {
    if (method == 'POST') {
      final b = (jsonDecode(body!) as Map).cast<String, Object?>();
      posts.add(b);
      return RkHttpResponse(
        200,
        jsonEncode({'share_set_version': b['share_set_version']}),
      );
    }
    return RkHttpResponse(200, jsonEncode({'guardian_sets': sets}));
  }),
  functionsRoot: Uri.parse('https://api.example.test/functions/v1/'),
  accessToken: () async => 'tok',
);

/// `lib/bootstrap.dart` with `//` comments stripped, so a pin cannot pass on
/// prose that merely names the call (the F1-24b-3 reader).
String _bootstrapCode() {
  for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    expect(text, isNotEmpty, reason: 'the root was really read');
    return [
      for (final line in text.split('\n'))
        line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
    ].join('\n');
  }
  fail('lib/bootstrap.dart not found from ${Directory.current.path}');
}

void main() {
  test('F1-05-30 the transport this build ships carries a fresh token and the '
      'version header to the real routes, and a 401 refreshes rather than '
      'ends the session', () async {
    final seen = <http.Request>[];
    var issued = 0;
    var calls = 0;
    final transport = buildSyncTransport(
      client: MockClient((request) async {
        seen.add(request);
        if (calls++ == 0) {
          return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
        }
        return http.Response(
          jsonEncode({
            'store_epoch': 'e1',
            'devices': <Object?>[],
            'memberships': <Object?>[],
            'book_roles': <Object?>[],
            'wrapped_keys': <Object?>[],
            'signed_records': <Object?>[],
            'has_more': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessTokenOf: () async => 'jwt-${++issued}',
      functionsRoot: Uri.parse('http://127.0.0.1:54321/functions/v1/'),
    );

    await expectLater(
      transport.meta(const eng.MetaRequest()),
      throwsA(isA<eng.AuthFailed>()),
    );
    await transport.meta(const eng.MetaRequest());

    expect(seen.map((r) => r.url.path), [
      '/functions/v1/sync-meta',
      '/functions/v1/sync-meta',
    ]);
    // ⚠️ WIRE `_shared/http.ts`: no version header ⇒ 426 from every route.
    expect(
      seen.map((r) => r.headers[eng.HttpSyncTransport.clientVersionHeader]),
      everyElement(isNotNull),
    );
    // The 401 dropped the token; the retry carried a new one.
    expect(seen.map((r) => r.headers['authorization']), [
      'Bearer jwt-1',
      'Bearer jwt-2',
    ]);
  });

  test('F1-05-31 the default build pins nothing and says so; a configured pin '
      'set that cannot be verified refuses to build rather than ship '
      'unpinned; and the stored identity survives a garbage record', () async {
    final (pins, chain) = spkiPins();
    // No `--dart-define=RF_SPKI_PINS` in a test build: local dev, pins off,
    // and the transport is then allowed to have no chain source.
    expect(pins.localDevDisabled, isTrue);
    expect(chain, isNull);

    final keys = FakeKeyStore();
    expect(await storedIdentity(keys), isNull);

    await keys.write(
      LocalLedgerKeys.identity,
      Uint8List.fromList(utf8.encode('not json')),
    );
    expect(await storedIdentity(keys), isNull);

    await keys.write(
      LocalLedgerKeys.identity,
      Uint8List.fromList(utf8.encode(jsonEncode({'device_id': 'd'}))),
    );
    expect(
      await storedIdentity(keys),
      isNull,
      reason: 'a partial record is none',
    );

    const identity = {
      'device_id': '11111111-2222-4333-8444-555555555555',
      'user_id': '99999999-8888-4777-8666-555555555555',
      'tenant_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      'suite_version': 1,
    };
    await keys.write(
      LocalLedgerKeys.identity,
      Uint8List.fromList(utf8.encode(jsonEncode(identity))),
    );
    final read = await storedIdentity(keys);
    expect(read?.tenantId, identity['tenant_id']);
    expect(read?.userId, identity['user_id']);
    expect(read?.deviceId, identity['device_id']);
  });

  group('F1-03b-3 S11.1 save through the production wiring publishes with '
      'the install’s tenant (ADR 2026-10-03b §1 🔒)', () {
    late CryptoSuite suite;
    late UmkKeyPair mine;
    late List<TestGuardian> guardians;

    setUpAll(() async {
      suite = await liveSuite();
      mine = UmkKeyPair.generate(suite);
      guardians = [
        for (final id in userGuardians.take(3))
          TestGuardian.generate(suite, id),
      ];
    });
    tearDownAll(() {
      mine.dispose();
      for (final g in guardians) {
        g.umk.dispose();
      }
    });

    test('the roster the root builds from the members snapshot names the '
        'tenant, so the body carries tenant_id and the save is not refused '
        'no_tenant', () async {
      final posts = <Map<String, Object?>>[];
      final snapshot = MembersSnapshot(
        members: [
          for (final g in guardians)
            Member(
              id: g.userId,
              state: MembershipState.active,
              displayName: 'Member',
              verification: Verification(
                verifiedByName: 'You',
                method: VerificationMethod.qrInPerson,
                on: DateTime.utc(2026, 10, 3),
              ),
            ),
          const Member(id: userMe, state: MembershipState.active, isYou: true),
        ],
      );
      final repo = ServerGuardians(
        api: _api(posts),
        // The root's own builder — the line under test.
        roster: () async => guardianRosterOf(
          snapshot,
          tenantId: _tenant,
          nameOf: (_) => 'Member',
        ),
        verified: eng.MapUmkSource({
          for (final g in guardians) g.userId: g.verified,
        }),
        // The production sealer, as the root binds it.
        sealer: CryptoGuardianSealer(suite: suite, umk: () => mine).call,
      );
      addTearDown(repo.dispose);

      await repo.refresh();
      await repo.save([guardians[0].userId, guardians[1].userId]);

      expect(posts, hasLength(1), reason: 'the save reached the wire');
      expect(posts.single['tenant_id'], _tenant);
      expect(posts.single['k'], 2);
    });

    test('the root reads S11.1’s roster through that builder, in '
        'identity.tenantId, and builds no roster of its own', () {
      final root = _bootstrapCode();
      expect(root, contains('Future<void> bootstrap() async {'));
      expect(
        RegExp(
          r'ServerGuardians\([^;]*roster:\s*\(\)\s*async\s*=>\s*'
          r'guardianRosterOf\(\s*members\.current\s*,\s*'
          r'tenantId:\s*identity\.tenantId\b',
        ).hasMatch(root),
        isTrue,
        reason:
            'the set is published into the tenant its guardians were '
            'chosen from — the install’s, whose members the snapshot holds',
      );
      expect(
        RegExp(r'\bGuardianRoster\(').allMatches(root),
        hasLength(1),
        reason:
            'one roster constructor — the builder’s — so no second '
            'roster without a tenant can stand in for it',
      );
    });

    // M13-GSEL53 review finding 2: who S11.1 lets you *choose* is read off
    // `MembersRepositoryScope` (devices_routes.dart, `guardianMeetBlockFrom`),
    // while its rows come from `members.current` above. If the scope fell back
    // to its empty fake, every row would still list and none could be chosen.
    test('F1-03c-4 the root binds MembersRepositoryScope to the same '
        '`members` the S11.1 roster reads, so who may be chosen is judged '
        'against the members the rows list (ADR 2026-10-03c §4)', () {
      final root = _bootstrapCode();
      expect(root, contains('Future<void> bootstrap() async {'));
      expect(
        RegExp(r'\bfinal\s+members\s*=').allMatches(root),
        hasLength(1),
        reason: 'one `members` binding — the roster and the scope share it',
      );
      expect(
        RegExp(
          r'runApp\(\s*MembersRepositoryScope\(\s*repository:\s*members\s*,',
        ).hasMatch(root),
        isTrue,
        reason:
            'the scope over the whole app is that repository, not the '
            'empty fake MembersRepositoryScope.of falls back to',
      );
      expect(
        RegExp(r'\bMembersRepositoryScope\(').allMatches(root),
        hasLength(1),
        reason: 'no second scope deeper in the tree can shadow it',
      );
      expect(
        RegExp(r'guardianRosterOf\(\s*members\.current\b').hasMatch(root),
        isTrue,
        reason: 'and the rows are read from that same repository',
      );
    });
  });

  group(
    'F1-03b-4 the root installs GuardianStandingScope above S11 over the '
    'live trust store, and disposes its producer (ADR 2026-10-03b §4 🔒)',
    () {
      testWidgets('the installed reading follows the store the engine files '
          'into, for the subject it was given, and dies with the tree', (
        tester,
      ) async {
        final trust = eng.RecordTrustStore(umks: const eng.MapUmkSource({}));
        final guardians = ServerGuardians(
          api: _api([]),
          roster: () async => const GuardianRoster(),
          verified: const eng.MapUmkSource({}),
        );
        addTearDown(guardians.dispose);

        GuardianStanding? seen;
        await tester.pumpWidget(
          GuardianStandingHost(
            trust: trust,
            subjectUserId: userMe,
            guardians: guardians,
            child: Builder(
              builder: (context) {
                seen = GuardianStandingScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final standing = seen;
        expect(standing, isNotNull, reason: 'a scope is installed');
        expect(
          standing!.gap,
          isNull,
          reason: 'no set filed yet: nothing to say',
        );

        // Another user's tenantless set in the same store is not this one's.
        trust.guardianHistory.add(
          eng.GuardianSetVersion(
            subjectUserId: userGuardians[4],
            shareSetVersion: 1,
            k: 2,
            guardianUserIds: {userGuardians[0], userGuardians[1]},
          ),
        );
        expect(standing.gap, isNull, reason: 'read for the subject given');

        // The engine files this user's pre-ADR set, as `_applyMeta` does.
        trust.guardianHistory.add(
          eng.GuardianSetVersion(
            subjectUserId: userMe,
            shareSetVersion: 1,
            k: 2,
            guardianUserIds: {userGuardians[0], userGuardians[1]},
          ),
        );
        expect(
          standing.gap,
          GuardianRevokeGap.noTenant,
          reason: 'the reading is over the live store, not a copy',
        );

        // S11 listening arms the backstop poll; the tree going away must take
        // it down, or the timer outlives the app (and this test fails on a
        // pending timer).
        standing.addListener(() {});
        await tester.pumpWidget(const SizedBox());
        expect(
          () => standing.addListener(() {}),
          throwsFlutterError,
          reason: 'the host disposed the standing it made',
        );
      });

      testWidgets('the host hands the standing S11.1’s read-back as a change '
          'signal and arms the backstop poll, so a listener — S11’s '
          'ListenableBuilder — is told the moment either reading moves', (
        tester,
      ) async {
        // The engine still holds this user's pre-ADR v1 (no tenant); the
        // server already holds v2, re-split into the tenant.
        final trust = eng.RecordTrustStore(umks: const eng.MapUmkSource({}))
          ..guardianHistory.add(
            eng.GuardianSetVersion(
              subjectUserId: userMe,
              shareSetVersion: 1,
              k: 2,
              guardianUserIds: {userGuardians[0], userGuardians[1]},
            ),
          );
        final guardians = ServerGuardians(
          api: _api(
            [],
            sets: [
              for (final v in [1, 2])
                {
                  'subject_user_id': userMe,
                  'share_set_version': v,
                  'k': 2,
                  'n': 2,
                  'guardian_user_ids': [userGuardians[0], userGuardians[1]],
                  if (v == 2) 'tenant_id': _tenant,
                },
            ],
          ),
          roster: () async => const GuardianRoster(tenantId: _tenant),
          verified: const eng.MapUmkSource({}),
        );
        addTearDown(guardians.dispose);

        GuardianStanding? seen;
        await tester.pumpWidget(
          GuardianStandingHost(
            trust: trust,
            subjectUserId: userMe,
            guardians: guardians,
            child: Builder(
              builder: (context) {
                seen = GuardianStandingScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        );
        final standing = seen!;
        var notified = 0;
        // What S11's ListenableBuilder does: listen, and rebuild on a notify.
        standing.addListener(() => notified++);
        expect(standing.gap, GuardianRevokeGap.noTenant);

        // (a) S11.1's save ends in a read-back. Nothing else moves and no
        // time passes — only `ServerGuardians.watch` can carry this, and only
        // if the host gave the standing `guardians`.
        await guardians.refresh();
        await tester.pump();
        expect(
          notified,
          1,
          reason: 'the read-back is a change signal: S11 is told at once',
        );
        expect(
          standing.gap,
          isNull,
          reason: 'v2 names the tenant and both guardians still hold',
        );

        // (b) The engine files a removal on a meta pull and tells nobody
        // (`_applyMeta`). No read of `gap` in between: the poll alone must
        // notice it.
        trust.memberships.add(
          eng.MembershipFact(
            recordId: 'r-1',
            tenantId: _tenant,
            userId: userGuardians[0],
            status: eng.MembershipFact.removed,
            seq: 7,
          ),
        );
        await tester.pump(guardianStandingPoll);
        expect(
          notified,
          2,
          reason: 'the backstop poll re-reads the store while S11 listens',
        );
        expect(standing.gap, GuardianRevokeGap.belowThreshold);

        await tester.pumpWidget(const SizedBox());
      });

      test('the root installs that host around the app, over `trust`, the '
          'engine’s subject id and S11.1’s repository', () {
        final root = _bootstrapCode();
        expect(root, contains('Future<void> bootstrap() async {'));
        final hosts = RegExp(
          r'final\s+app\s*=\s*GuardianStandingHost\(\s*trust:\s*trust\s*,\s*'
          r'subjectUserId:\s*identity\.userId\s*,\s*'
          r'guardians:\s*guardians\s*,\s*child:\s*(\w+)\s*,?\s*\)',
        ).allMatches(root).toList();
        expect(
          hosts,
          hasLength(1),
          reason:
              'once, over the RecordTrustStore the engine is built with, '
              'and it is what the root calls `app`',
        );
        expect(
          RegExp(r'\bGuardianStandingHost\(').allMatches(root),
          hasLength(2),
          reason: 'the class’s constructor and this one install — no other',
        );
        // What it wraps is the shell that holds RukkaFolioApp, so every
        // route, S11 among them, is below it.
        expect(
          RegExp(
            'final\\s+${hosts.single.group(1)}\\s*=\\s*ShareSheetScope\\('
            r'[^;]*child:\s*RukkaFolioApp\(',
          ).hasMatch(root),
          isTrue,
          reason: 'above S11: the host wraps the app shell itself',
        );
        // …and `app` is what the scope tree around it receives (F1-24b-3
        // pins the CeremonyScope that does).
        expect(RegExp(r'\bchild:\s*app\s*,').allMatches(root), hasLength(1));
        expect(
          RegExp(r'trustStoreGuardianStanding\(').allMatches(root),
          hasLength(1),
          reason: 'the host’s own call — no second, undisposed standing',
        );
        expect(
          RegExp(r'final\s+trust\s*=\s*eng\.RecordTrustStore\(').hasMatch(root),
          isTrue,
          reason: '`trust` is the engine’s store, not a stand-in',
        );
        expect(
          RegExp(r'eng\.SyncEngine\([^;]*\btrust:\s*trust\s*,').hasMatch(root),
          isTrue,
          reason: 'the same store the engine files guardian sets into',
        );
      });
    },
  );
}
