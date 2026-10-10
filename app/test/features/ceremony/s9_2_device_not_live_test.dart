@Tags(['F1'])
library;

// PLAN desk 113 — S9.2 names the not-live refusal (ADR 2026-10-03c §3, ADR
// 2026-10-04-suspended-invites §1), as S0.9 does (desk 109, F1-03c-5…8).
//
// F1-03c-11  the S9.2 route, over the PRODUCTION chain — `HttpMembersApi`
//            (faked at the transport only) → `InviteNonceRelay` →
//            `relayedInviteNonceOver` → `buildLiveCeremonySessions` →
//            `ShowMyCodeRoute` — lands on the named not-live state when the
//            invites GET answers 403 `unknown_request`: the reason in words,
//            a `danger` icon WITH a semantics label (colour never alone), a
//            door that pushes Devices & security, Check again and Close; no
//            session opened, no QR. Check again recovers once GET answers.
//            Test honesty: a relay that swallowed the refusal again would
//            land on the *no code yet* state and fail every expectation here.
// F1-03c-12  control: every OTHER relay failure — offline, a 403 that is not
//            `unknown_request`, 401, 500, a non-members throw — still opens
//            the old *no code yet* state, never the not-live one.
// F1-03c-13  the not-live state fits and resolves in EN/PA/HI at 130 % and
//            200 % on both phones, with and without the door bound.
//
// Synthetic ids and bytes only (CLAUDE.md rule 4).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/ceremony/ceremony_routes.dart';
import 'package:rukka_folio/features/devices/devices_paths.dart';
import 'package:rukka_folio/features/members/invite_nonce_relay.dart';
import 'package:rukka_folio/features/members/members_api.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:sync_engine/sync_engine.dart' show KnownTenant, MetaResponse;

import '../../shared/test_app.dart';

const _selfId = '7d2f9c1a-4b6e-4c8d-9e0f-1a2b3c4d5e6f';
const _tenantId = '9e0f1a2b-3c4d-4e5f-8a6b-7c8d9e0f1a2b';
const _inviteId = '0b0b0b0b-1111-4222-8333-444455556666';

Uint8List _bytes(int seed, [int length = 32]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (seed + i * 7) % 256));

UmkPublic _umk(int seed) =>
    UmkPublic(x25519: _bytes(seed), ed25519: _bytes(seed + 1));

/// Unpadded base64url, as sync-meta writes it.
String _b64(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

Uint8List _relayedNonce() => _bytes(90, ceremonyNonceBytes);

/// Polling that reads once and never wakes, so no timer is left pending.
final _stall = CeremonyPolling(sleep: (_) => Completer<void>().future);

/// One fake server for both relays: sync-meta's invites GET (scripted by
/// [invites]) and the ceremony session routes (recorded in [commits]).
final class _Server {
  /// What the invites GET answers; null answers our invite with its nonce.
  RkHttpResponse? Function()? invites;
  final commits = <Map<String, Object?>>[];
  var inviteGets = 0;
  late final transport = FakeRkHttpTransport(_answer);

  RkHttpResponse _session(int n, String commitment) => RkHttpResponse(
    200,
    jsonEncode({
      'session_id': 'sess-$n',
      'tenant_id': _tenantId,
      'subject_user_id': _selfId,
      'commitment': commitment,
      'committed_at': testNow().toUtc().toIso8601String(),
      'expires_at': testNow()
          .add(const Duration(minutes: 10))
          .toUtc()
          .toIso8601String(),
    }),
  );

  RkHttpResponse _answer(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) {
    if (method == 'GET' && url.path.endsWith('sync-meta/invites')) {
      inviteGets++;
      final scripted = invites?.call();
      if (scripted != null) return scripted;
      return RkHttpResponse(
        200,
        jsonEncode({
          'invites': [
            {
              'invite_id': _inviteId,
              'tenant_id': _tenantId,
              'roles': [
                {'book_id': 'b1', 'role': 'viewer'},
              ],
              'expires_at': 1789000000000,
              'created_by': 'u-admin',
              'status': 'accepted',
              'nonce': _b64(_relayedNonce()),
            },
          ],
        }),
      );
    }
    if (method == 'POST' && url.path.endsWith('sync-meta/ceremony')) {
      final b = (jsonDecode(body!) as Map).cast<String, Object?>();
      commits.add(b);
      return _session(commits.length, b['commitment']! as String);
    }
    if (method == 'GET' && url.queryParameters.containsKey('session_id')) {
      final n = int.parse(url.queryParameters['session_id']!.split('-').last);
      return _session(n, commits[n - 1]['commitment']! as String);
    }
    return RkHttpResponse(404, jsonEncode({'error': 'not_found'}));
  }

  Uri get _root => Uri.parse('https://api.test/functions/v1/');

  HttpMembersApi get members => HttpMembersApi(
    transport: transport,
    functionsRoot: _root,
    accessToken: () async => 'acc-1',
  );

  HttpCeremonyApi get ceremony => HttpCeremonyApi(
    transport: transport,
    functionsRoot: _root,
    accessToken: () async => 'acc-1',
  );
}

RkHttpResponse _refusal(int status, String error) =>
    RkHttpResponse(status, jsonEncode({'error': error}));

void main() {
  late CryptoSuite suite;
  setUpAll(() async => suite = await testSuite());

  /// A launch after the accept (the realistic case: the phone was paused or
  /// removed later): the kept invite id is in the store, so the relay must
  /// read the invites GET — the device-gated route.
  Future<InviteNonceRelay> restartedRelay(_Server server) async {
    final store = MemoryPrefs();
    await store.write(InviteNonceRelay.acceptedInviteKey, _inviteId);
    return InviteNonceRelay(
      offers: server.members.myInvites,
      accept: server.members.acceptInviteRelayed,
      store: store,
    );
  }

  LiveCeremonySessions sessions(_Server server, InviteNonceLookup nonces) =>
      buildLiveCeremonySessions(
        suite: suite,
        api: server.ceremony,
        pullMeta: ({after}) async => MetaResponse.fromJson({
          'store_epoch': 'epoch-1',
          'next': null,
          'has_more': false,
          'umk_public_keys': const <Object?>[],
        }),
        tenantOf: () => const KnownTenant(_tenantId),
        selfUserIdOf: () => _selfId,
        ownUmk: () => _umk(70),
        verifierName: () => 'Aman',
        memberName: (_) => 'Sunita',
        now: testNow,
        log: RecordingCeremonyEventLog(),
        keys: RecordingVerifiedMemberSink(),
        nonces: nonces,
        polling: _stall,
      );

  group('S9.2 names the not-live refusal (desk 113)', () {
    testWidgets('F1-03c-11 the invites GET refusing this phone as not live '
        '(403 unknown_request) reaches S9.2 through the real relay as the '
        'named state — words, danger icon with a label, Devices & security '
        'pushed, Check again, Close — with no session opened; Check again '
        'recovers once the relay answers', (tester) async {
      final server = _Server()
        ..invites = () => _refusal(403, 'unknown_request');
      final relay = await restartedRelay(server);
      final installed = sessions(server, relayedInviteNonceOver(relay.nonce));
      // S9.2 is pushed over a host page, as the app pushes it, so Close has
      // somewhere to go back to (a root page cannot pop).
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('host marker')),
          ),
          GoRoute(
            path: '/s92',
            builder: (_, _) => CeremonyScope(
              sessions: installed,
              child: const ShowMyCodeRoute(),
            ),
          ),
          GoRoute(
            path: DevicesPaths.devices,
            builder: (_, _) => const Scaffold(body: Text('S11 marker')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRk(
        tester,
        Router.withConfig(config: router),
        viewport: rkPhone360,
      );
      await tester.pumpAndSettle();
      unawaited(router.push('/s92'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.byType(ShowMyCodeDeviceNotLiveScreen), findsOneWidget);
      expect(
        find.byType(ShowMyCodeNoInviteScreen),
        findsNothing,
        reason: 'the refusal is named, not folded into "no code yet"',
      );
      expect(find.byType(ShowMyCodeScreen), findsNothing);
      expect(server.inviteGets, greaterThan(0), reason: 'the relay was read');
      expect(server.commits, isEmpty, reason: 'no session, no QR');

      // The reason, in words true for removed AND paused.
      expect(find.text(l10n.ceremonyShowDeviceNotLiveTitle), findsOneWidget);
      expect(find.text(l10n.ceremonyShowDeviceNotLiveBody), findsOneWidget);
      expect(l10n.ceremonyShowDeviceNotLiveBody, contains('removed or paused'));

      // Colour never alone: the danger icon carries a label.
      final context = tester.element(
        find.byType(ShowMyCodeDeviceNotLiveScreen),
      );
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.phonelink_erase_outlined),
      );
      expect(icon.color, RkStatusColors.of(context).danger);
      expect(
        find.bySemanticsLabel(l10n.ceremonyShowDeviceNotLiveSemantics),
        findsOneWidget,
      );

      // No dead end: all three ways on, each one TAPPED — a label alone
      // would pass over a disabled (null-callback) button.
      expect(find.text(l10n.ceremonyShowNoInviteRetry), findsOneWidget);
      expect(find.text(l10n.ceremonyShowNoInviteClose), findsOneWidget);
      await tester.tap(find.text(l10n.ceremonyShowDeviceNotLiveDevices));
      await tester.pumpAndSettle();
      expect(find.text('S11 marker'), findsOneWidget);
      expect(router.state.uri.path, DevicesPaths.devices);

      // Back on S9.2; the pause is cancelled elsewhere, and Check again
      // re-reads the relay and opens the code.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ShowMyCodeDeviceNotLiveScreen), findsOneWidget);

      // Close goes back to where S9.2 was opened from.
      await tester.ensureVisible(find.text(l10n.ceremonyShowNoInviteClose));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.ceremonyShowNoInviteClose));
      await tester.pumpAndSettle();
      expect(find.byType(ShowMyCodeDeviceNotLiveScreen), findsNothing);
      expect(find.text('host marker'), findsOneWidget);
      expect(router.state.uri.path, '/');

      // Opened again, still refused: the named state again.
      unawaited(router.push('/s92'));
      await tester.pumpAndSettle();
      expect(find.byType(ShowMyCodeDeviceNotLiveScreen), findsOneWidget);
      server.invites = null;
      await tester.tap(find.text(l10n.ceremonyShowNoInviteRetry));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ShowMyCodeDeviceNotLiveScreen), findsNothing);
      expect(find.byType(ShowMyCodeScreen), findsOneWidget);
      expect(server.commits, hasLength(1));
      // Leave nothing running.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('control: every other failure is still "no code yet" (desk 113)', () {
    test('F1-03c-12 through the real relay, offline, 403 forbidden, 401, '
        '500 and a 200 without our row open ShowMyCodeNoInviteNonce, never '
        'the not-live state; no session is opened', () async {
      for (final answer in <RkHttpResponse Function()>[
        () => throw const RkHttpFailure(),
        () => _refusal(403, 'forbidden'),
        () => _refusal(401, 'unauthorized'),
        () => _refusal(500, 'internal'),
        () => RkHttpResponse(200, jsonEncode({'invites': const <Object?>[]})),
      ]) {
        final server = _Server()..invites = answer;
        final relay = await restartedRelay(server);
        final opening = await sessions(
          server,
          relayedInviteNonceOver(relay.nonce),
        ).showMyCode();
        expect(opening, const ShowMyCodeNoInviteNonce());
        expect(opening, isNot(const ShowMyCodeDeviceNotLive()));
        expect(server.inviteGets, 1);
        expect(server.commits, isEmpty);
      }
    });

    test('F1-03c-12 relayedInviteNonceOver throws InviteNonceDeviceNotLive '
        'for deviceNotLive ONLY; every other MembersRefusal, and any other '
        'throw, is still no nonce', () async {
      await expectLater(
        relayedInviteNonceOver(
          () async => throw const MembersFailure(
            'http 403',
            MembersRefusal.deviceNotLive,
          ),
        )(),
        throwsA(isA<InviteNonceDeviceNotLive>()),
      );
      for (final reason in MembersRefusal.values) {
        if (reason == MembersRefusal.deviceNotLive) continue;
        expect(
          await relayedInviteNonceOver(
            () async => throw MembersFailure('x', reason),
          )(),
          isNull,
          reason: '$reason stays "no nonce"',
        );
      }
      expect(
        await relayedInviteNonceOver(() async => throw StateError('x'))(),
        isNull,
      );
    });
  });

  group('Layout — S9.2 not-live state, EN/PA/HI, 130 % and 200 %', () {
    for (final locale in rkLocales) {
      for (final scale in rkTextScales) {
        for (final viewport in rkPhones) {
          for (final door in [true, false]) {
            final where =
                '${locale.languageCode} @ $scale on '
                '${viewport.width.toInt()}×${viewport.height.toInt()}'
                '${door ? '' : ', no door bound'}';
            testWidgets('F1-03c-13 S9.2 not-live state fits and every line '
                'resolves — $where', (tester) async {
              var doors = 0, checks = 0, closes = 0;
              await pumpRk(
                tester,
                ShowMyCodeDeviceNotLiveScreen(
                  onOpenDevices: door ? () => doors++ : null,
                  onCheckAgain: () => checks++,
                  onClose: () => closes++,
                ),
                locale: locale,
                textScale: scale,
                viewport: viewport,
              );
              expect(tester.takeException(), isNull);
              final l10n = await AppLocalizations.delegate.load(locale);
              expect(find.text(l10n.ceremonyShowDeviceNotLiveTitle), findsOne);
              expect(find.text(l10n.ceremonyShowDeviceNotLiveBody), findsOne);
              expect(
                find.text(l10n.ceremonyShowDeviceNotLiveDevices),
                door ? findsOne : findsNothing,
                reason: 'an unbound door is hidden, never shown disabled',
              );
              expect(find.text(l10n.ceremonyShowNoInviteRetry), findsOne);
              await tester.ensureVisible(
                find.text(l10n.ceremonyShowNoInviteClose),
              );
              await tester.pumpAndSettle();
              expectTextFits(tester, reason: 'S9.2 not live $where');

              // Every way on that is shown is live: tapped, it calls out.
              Future<void> tapLabel(String label) async {
                await tester.ensureVisible(find.text(label));
                await tester.pumpAndSettle();
                await tester.tap(find.text(label));
                await tester.pump();
              }

              if (door) {
                await tapLabel(l10n.ceremonyShowDeviceNotLiveDevices);
              }
              await tapLabel(l10n.ceremonyShowNoInviteRetry);
              await tapLabel(l10n.ceremonyShowNoInviteClose);
              expect(doors, door ? 1 : 0);
              expect(checks, 1);
              expect(closes, 1);
            });
          }
        }
      }
    }
  });
}
