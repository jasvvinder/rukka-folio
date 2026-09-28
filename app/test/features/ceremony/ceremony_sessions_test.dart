@Tags(['F1'])
library;

// ADR 2026-09-24b §2, second bullet — *a missing `umk_pub_x` is said, not
// swallowed* — driven through the production seams: `MetaRelayedUmkSource`
// over meta pages shaped like sync-meta's `umk_public_keys` rows,
// `liveCeremonySessionOver` over the real `HttpCeremonyApi`, and
// `LiveCeremonySessions` installed in a `CeremonyScope` above the real S9.3
// route. Nothing here is a fake of the thing under test.
//
// The test-honesty pair: with a relayed row missing `pub_x` the route shows
// the *ask them to open the app once* state, no comparison runs and nothing
// reaches the sink; with both halves present and a matching QR the ceremony
// proceeds and the sink holds the proved key. Either seam answering null
// fails both.
//
// Synthetic ids and public keys only (CLAUDE.md rule 4).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ceremony/ceremony_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:sync_engine/sync_engine.dart' show MetaResponse;

import '../../shared/test_app.dart';

const _selfId = '7d2f9c1a-4b6e-4c8d-9e0f-1a2b3c4d5e6f';
const _memberId = '3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const _otherId = '11112222-3333-4444-8555-666677778888';
const _tenantId = '9e0f1a2b-3c4d-4e5f-8a6b-7c8d9e0f1a2b';
const _sessionId = '5c3e1a7f-2b9d-4e6a-8f1c-0d2e4a6b8c1e';

Uint8List _bytes(int seed, [int length = 32]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (seed + i * 7) % 256));

UmkPublic _umk(int seed) =>
    UmkPublic(x25519: _bytes(seed), ed25519: _bytes(seed + 1));

String _b64(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

/// One `umk_public_keys` row exactly as sync-meta's `shapeRow` relays it.
Map<String, Object?> _row({
  String userId = _memberId,
  int version = 1,
  Uint8List? ed,
  Uint8List? x,
  Object? superseded,
}) => {
  'user_id': userId,
  'key_version': version,
  'pub_ed': ed == null ? null : _b64(ed),
  'pub_x': x == null ? null : _b64(x),
  'superseded_at': superseded,
  'updated_at': 1789000000000,
};

MetaResponse _page(
  List<Map<String, Object?>> rows, {
  String? next,
  bool hasMore = false,
}) => MetaResponse.fromJson({
  'store_epoch': 'epoch-1',
  'next': next,
  'has_more': hasMore,
  'umk_public_keys': rows,
});

/// A meta feed of [pages], recording every `after` it was asked for.
final class _Feed {
  _Feed(this.pages);

  List<MetaResponse> pages;
  final asked = <String?>[];
  bool fail = false;

  Future<MetaResponse> call({String? after}) async {
    asked.add(after);
    if (fail) throw const RkHttpFailure();
    final i = after == null ? 0 : int.parse(after);
    return pages[i];
  }
}

/// The server's live-session answer for the subject (sync-meta
/// `sessionToWire`), and a record of every ceremony route touched.
final class _Relay {
  String subject = _memberId;
  late final transport = FakeRkHttpTransport(_answer);

  List<Uri> get ceremonyCalls => [
    for (final c in transport.calls)
      if (c.url.path.contains('ceremony')) c.url,
  ];

  RkHttpResponse _answer(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) {
    if (method == 'GET' &&
        url.path.endsWith('sync-meta/ceremony') &&
        url.queryParameters['subject_user_id'] == _memberId) {
      return RkHttpResponse(
        200,
        jsonEncode({
          'session_id': _sessionId,
          'tenant_id': _tenantId,
          'subject_user_id': subject,
          'commitment': _b64(_bytes(40)),
          'committed_at': testNow().toUtc().toIso8601String(),
          'expires_at': testNow()
              .add(const Duration(minutes: 10))
              .toUtc()
              .toIso8601String(),
        }),
      );
    }
    return RkHttpResponse(404, jsonEncode({'error': 'no_live_session'}));
  }

  HttpCeremonyApi get api => HttpCeremonyApi(
    transport: transport,
    functionsRoot: Uri.parse('https://api.test/functions/v1/'),
    accessToken: () async => 'acc-1',
  );
}

/// The invitee's side of the 0007 relay: `POST sync-meta/ceremony` mints a
/// session per commitment (so *Regenerate* is visible as a second POST), and
/// `GET ?session_id=` answers it still waiting for the verifier.
final class _ShowerRelay {
  final commits = <Map<String, Object?>>[];
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

  HttpCeremonyApi get api => HttpCeremonyApi(
    transport: transport,
    functionsRoot: Uri.parse('https://api.test/functions/v1/'),
    accessToken: () async => 'acc-1',
  );
}

/// A relayed invite nonce (ADR 2026-09-25b §2): 16 bytes, synthetic.
Uint8List _relayedNonce([int seed = 90]) => _bytes(seed, ceremonyNonceBytes);

/// Polling that reads once and then never wakes — the verifier never begins,
/// and no timer is left pending in a widget test.
final _stall = CeremonyPolling(sleep: (_) => Completer<void>().future);

void main() {
  late CryptoSuite suite;
  setUpAll(() async => suite = await testSuite());

  group('relayedUmkFromRows — three answers, never two (ADR 2026-09-24b §2)', () {
    test('F1-24b-3 a row with pub_ed and no pub_x is EdOnly, both halves is '
        'Complete with the relayed bytes, and nothing else is a key', () {
      final umk = _umk(1);
      expect(
        relayedUmkFromRows([_row(ed: umk.ed25519)], _memberId),
        isA<RelayedUmkEdOnly>(),
      );
      final complete = relayedUmkFromRows([
        _row(ed: umk.ed25519, x: umk.x25519),
      ], _memberId);
      expect(complete, isA<RelayedUmkComplete>());
      expect((complete! as RelayedUmkComplete).umk, umk);

      // No row, another person's row, no ed half, a short x half.
      expect(relayedUmkFromRows(const [], _memberId), isNull);
      expect(
        relayedUmkFromRows([
          _row(userId: _otherId, ed: umk.ed25519),
        ], _memberId),
        isNull,
      );
      expect(relayedUmkFromRows([_row(x: umk.x25519)], _memberId), isNull);
      expect(
        relayedUmkFromRows([
          _row(ed: umk.ed25519, x: _bytes(3, 16)),
        ], _memberId),
        isNull,
        reason: 'a malformed x half is not a key, and never half a check',
      );
    });

    test('F1-24b-3 the backfill wins: a later copy of the same version that '
        'gained pub_x replaces the ed-only one; a superseded version is never '
        'current', () {
      final old = _umk(1), current = _umk(5);
      expect(
        relayedUmkFromRows([
          _row(ed: current.ed25519),
          _row(ed: current.ed25519, x: current.x25519),
        ], _memberId),
        isA<RelayedUmkComplete>(),
      );
      final r = relayedUmkFromRows([
        _row(ed: old.ed25519, x: old.x25519, superseded: 1789000000000),
        _row(version: 2, ed: current.ed25519),
      ], _memberId);
      expect(
        r,
        isA<RelayedUmkEdOnly>(),
        reason: 'v1 is superseded; v2 is ed-only',
      );
    });

    test(
      'F1-24b-3 MetaRelayedUmkSource reads the whole feed from the start, '
      'finds the row on a later page, and answers null when the pull fails',
      () async {
        final umk = _umk(1);
        final feed = _Feed([
          _page(
            [_row(userId: _otherId, ed: _bytes(9))],
            next: '1',
            hasMore: true,
          ),
          _page([_row(ed: umk.ed25519, x: umk.x25519)], next: '1'),
        ]);
        final source = MetaRelayedUmkSource(feed.call);
        final r = await source(_memberId);
        expect((r! as RelayedUmkComplete).umk, umk);
        expect(feed.asked, [null, '1']);

        feed.fail = true;
        expect(await source(_memberId), isNull);
      },
    );
  });

  group('S9.3 through the installed CeremonyScope (ADR 2026-09-24b §2)', () {
    late _Relay relay;
    late RecordingVerifiedMemberSink sink;
    late RecordingCeremonyEventLog log;
    late FakeCeremonyScanner scanner;

    setUp(() {
      relay = _Relay();
      sink = RecordingVerifiedMemberSink();
      log = RecordingCeremonyEventLog();
      scanner = FakeCeremonyScanner();
    });

    Widget route(_Feed feed) {
      final api = relay.api;
      // Exactly what `bootstrap()` installs: the production builder, handed
      // only the meta pull and the relay — its two seams are not ours to pick
      // here, which is the point (see F1-24b-3 *the root installs it* below).
      return CeremonyScope(
        sessions: buildLiveCeremonySessions(
          suite: suite,
          api: api,
          pullMeta: feed.call,
          tenantId: _tenantId,
          selfUserId: _selfId,
          ownUmk: () => _umk(70),
          verifierName: () => 'Aman',
          memberName: (_) => 'Sunita',
          now: testNow,
          log: log,
          keys: sink,
        ),
        scanner: scanner,
        child: const VerifyMemberRoute(subjectUserId: _memberId),
      );
    }

    testWidgets('F1-24b-3 a relayed row with pub_ed and no pub_x fails closed '
        'AND says so: the ask-them-to-open-the-app state, not the placeholder '
        'or the generic error — no session is looked up, no camera opens, '
        'nothing is compared and nothing reaches the sink', (tester) async {
      final umk = _umk(1);
      final feed = _Feed([
        _page([_row(ed: umk.ed25519)]),
      ]);
      await pumpRk(tester, route(feed), viewport: rkPhone360);

      expect(find.text('Not ready to check yet'), findsOneWidget);
      expect(
        find.text(
          'Ask Sunita to open the app on their phone once. Then check again '
          'here.',
        ),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.byType(VerifyMemberKeyIncompleteScreen), findsOneWidget);
      // Neither of the two things it must not be.
      expect(find.text('Checking.'), findsNothing);
      expect(find.text('Couldn’t check that just now.'), findsNothing);
      // No comparison can run: there is no repository at all.
      expect(find.byType(VerifyMemberScreen), findsNothing);
      expect(scanner.starts, 0);
      expect(relay.ceremonyCalls, isEmpty, reason: 'no session looked up');
      // A square scanned now reaches nothing.
      scanner.emit(
        QrPayload(
          userId: _memberId,
          umk: umk,
          nonce: _bytes(9, ceremonyNonceBytes),
        ).encode(),
      );
      await tester.pumpAndSettle();
      expect(sink.stored, isEmpty);
      expect(log.mismatches, isEmpty);
      expect(log.verifications, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('F1-24b-3 both halves relayed and a matching square: the '
        'ceremony proceeds — the live session is found by subject and tenant, '
        'the QR verifies, and the proved key is kept', (tester) async {
      final umk = _umk(1);
      final feed = _Feed([
        _page([_row(ed: umk.ed25519, x: umk.x25519)]),
      ]);
      await pumpRk(tester, route(feed), viewport: rkPhone360);

      expect(find.byType(VerifyMemberScreen), findsOneWidget);
      expect(find.byType(VerifyMemberKeyIncompleteScreen), findsNothing);
      final lookup = relay.ceremonyCalls.single;
      expect(lookup.queryParameters, {
        'subject_user_id': _memberId,
        'tenant_id': _tenantId,
      });

      scanner.emit(
        QrPayload(
          userId: _memberId,
          umk: umk,
          nonce: _bytes(9, ceremonyNonceBytes),
        ).encode(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verified'), findsOneWidget);
      expect(sink.stored.single.userId, _memberId);
      expect(log.verifications, [('Sunita', VerificationMethod.qrInPerson)]);
      expect(log.mismatches, isEmpty);
    });

    testWidgets('F1-24b-3 Check again re-reads the relay: once their phone has '
        'offered the x half, the same screen opens the ceremony', (
      tester,
    ) async {
      final umk = _umk(1);
      final feed = _Feed([
        _page([_row(ed: umk.ed25519)]),
      ]);
      await pumpRk(tester, route(feed), viewport: rkPhone360);
      expect(find.byType(VerifyMemberKeyIncompleteScreen), findsOneWidget);

      // They opened the app; their re-offer filled pub_x (rf.set_umk_pubs).
      feed.pages = [
        _page([_row(ed: umk.ed25519), _row(ed: umk.ed25519, x: umk.x25519)]),
      ];
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyMemberKeyIncompleteScreen), findsNothing);
      expect(find.byType(VerifyMemberScreen), findsOneWidget);
      expect(sink.stored, isEmpty, reason: 'opening is not verifying');
    });

    testWidgets('F1-24b-3 a live session that names anyone but the subject '
        'asked for is refused — the route waits rather than open it', (
      tester,
    ) async {
      relay.subject = _otherId;
      final umk = _umk(1);
      final feed = _Feed([
        _page([_row(ed: umk.ed25519, x: umk.x25519)]),
      ]);
      await pumpRk(tester, route(feed), viewport: rkPhone360);
      expect(find.byType(VerifyMemberScreen), findsNothing);
      expect(find.text('Checking.'), findsOneWidget);
    });
  });

  group('Layout — the fail-closed state, EN/PA/HI, 130 % and 200 %', () {
    for (final locale in rkLocales) {
      for (final scale in rkTextScales) {
        for (final viewport in rkPhones) {
          final where =
              '${locale.languageCode} @ $scale on '
              '${viewport.width.toInt()}×${viewport.height.toInt()}';
          testWidgets('F1-24b-3 S9.3 not-ready-yet fits and every line '
              'resolves — $where', (tester) async {
            await pumpRk(
              tester,
              const VerifyMemberKeyIncompleteScreen(memberName: 'Sunita'),
              locale: locale,
              textScale: scale,
              viewport: viewport,
            );
            expect(tester.takeException(), isNull);
            final l10n = await AppLocalizations.delegate.load(locale);
            expect(find.text(l10n.ceremonyVerifyKeyIncompleteTitle), findsOne);
            expect(
              find.text(l10n.ceremonyVerifyKeyIncompleteBody('Sunita')),
              findsOne,
            );
            expect(
              l10n.ceremonyVerifyKeyIncompleteBody('Sunita'),
              contains('Sunita'),
            );
            await tester.ensureVisible(
              find.text(l10n.ceremonyVerifyKeyIncompleteClose),
            );
            await tester.pumpAndSettle();
            expectTextFits(tester, reason: 'S9.3 not ready $where');
          });
        }
      }
    }
  });

  group('S9.2 shows the relayed nonce and never draws one '
      '(ADR 2026-09-25b §3)', () {
    late _ShowerRelay relay;
    late _Feed feed;

    setUp(() {
      relay = _ShowerRelay();
      feed = _Feed([_page(const [])]);
    });

    LiveCeremonySessions sessions(InviteNonceLookup nonces) =>
        buildLiveCeremonySessions(
          suite: suite,
          api: relay.api,
          pullMeta: feed.call,
          tenantId: _tenantId,
          selfUserId: _selfId,
          ownUmk: () => _umk(70),
          verifierName: () => 'Aman',
          memberName: (_) => 'Sunita',
          now: testNow,
          log: RecordingCeremonyEventLog(),
          keys: RecordingVerifiedMemberSink(),
          nonces: nonces,
          polling: _stall,
        );

    test('F1-25b-1 the QR carries the RELAYED nonce, byte for byte, through '
        'the production builder and the invite relay', () async {
      final bytes = _relayedNonce();
      final opening = await sessions(
        relayedInviteNonceOver(() async => Uint8List.fromList(bytes)),
      ).showMyCode();
      expect(opening, isA<ShowMyCodeReady>());
      final code = await (opening! as ShowMyCodeReady).repository.load();
      final qr = QrPayload.decode(code.qrPayload);
      expect(qr.nonce, bytes);
      expect(qr.userId, _selfId);
      expect(relay.commits, hasLength(1));
    });

    test('F1-25b-1 no relayed nonce fails closed: a named state, no session '
        'opened, nothing drawn — and a relay that throws or answers a '
        'wrong-length value is no nonce either', () async {
      for (final lookup in <InviteNonceLookup>[
        relayedInviteNonceOver(() async => null),
        relayedInviteNonceOver(() async => throw const RkHttpFailure()),
        relayedInviteNonceOver(() async => _bytes(3, 12)),
      ]) {
        final opening = await sessions(lookup).showMyCode();
        expect(opening, isA<ShowMyCodeNoInviteNonce>());
      }
      expect(relay.commits, isEmpty, reason: 'no session without a nonce');
      expect(relay.transport.calls, isEmpty);
    });

    test('F1-25b-1 a closed ledger (no own key) still opens nothing — the '
        'nonce is not even asked for', () async {
      var asked = 0;
      final s = buildLiveCeremonySessions(
        suite: suite,
        api: relay.api,
        pullMeta: feed.call,
        tenantId: _tenantId,
        selfUserId: _selfId,
        ownUmk: () => null,
        verifierName: () => 'Aman',
        memberName: (_) => 'Sunita',
        now: testNow,
        log: RecordingCeremonyEventLog(),
        keys: RecordingVerifiedMemberSink(),
        nonces: () async {
          asked++;
          return InviteNonce(bytes: _relayedNonce());
        },
      );
      expect(await s.showMyCode(), isNull);
      expect(asked, 0);
    });

    testWidgets('F1-25b-1 S9.2 route: relayed nonce → the code screen; none → '
        'the says-why state with Check again and Close, never the silent '
        'placeholder; Check again opens once the relay has it', (tester) async {
      Uint8List? relayed;
      final installed = sessions(relayedInviteNonceOver(() async => relayed));
      await pumpRk(
        tester,
        CeremonyScope(sessions: installed, child: const ShowMyCodeRoute()),
        viewport: rkPhone360,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ShowMyCodeNoInviteScreen), findsOneWidget);
      expect(find.byType(ShowMyCodeScreen), findsNothing);
      expect(find.text('Getting your code.'), findsNothing);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(relay.commits, isEmpty);

      relayed = _relayedNonce();
      await tester.tap(find.text('Check again'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ShowMyCodeNoInviteScreen), findsNothing);
      expect(find.byType(ShowMyCodeScreen), findsOneWidget);
      expect(relay.commits, hasLength(1));
      // Leave nothing running.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Regenerate opens a fresh session, not a fresh nonce '
      '(ADR 2026-09-25b §4)', () {
    test(
      'F1-25b-2 InviteNonceSource(fresh: true) returns the SAME nonce',
      () async {
        final nonce = InviteNonce(bytes: _relayedNonce());
        final source = fixedInviteNonceSource(nonce);
        final first = await source();
        final again = await source(fresh: true);
        expect(again.bytes, first.bytes);
        expect(again.bytes, _relayedNonce());
      },
    );

    test('F1-25b-2 Regenerate through the live repository: a second session '
        '(a second commitment on the wire) whose QR carries the same relayed '
        'nonce; the relay is not re-read', () async {
      final relay = _ShowerRelay();
      var reads = 0;
      final s = buildLiveCeremonySessions(
        suite: suite,
        api: relay.api,
        pullMeta: _Feed([_page(const [])]).call,
        tenantId: _tenantId,
        selfUserId: _selfId,
        ownUmk: () => _umk(70),
        verifierName: () => 'Aman',
        memberName: (_) => 'Sunita',
        now: testNow,
        log: RecordingCeremonyEventLog(),
        keys: RecordingVerifiedMemberSink(),
        nonces: relayedInviteNonceOver(() async {
          reads++;
          return _relayedNonce();
        }),
        polling: _stall,
      );
      final repo = (await s.showMyCode())! as ShowMyCodeReady;
      final first = await repo.repository.load();
      final second = await repo.repository.regenerate();
      expect(relay.commits, hasLength(2), reason: 'a fresh session');
      expect(
        relay.commits[0]['commitment'],
        isNot(relay.commits[1]['commitment']),
        reason: 'a fresh r_S, so a fresh commitment',
      );
      expect(QrPayload.decode(first.qrPayload).nonce, _relayedNonce());
      expect(QrPayload.decode(second.qrPayload).nonce, _relayedNonce());
      expect(reads, 1, reason: 'the nonce is fixed at issue');
    });
  });

  group('Layout — S9.2 no-invite state, EN/PA/HI, 130 % and 200 %', () {
    for (final locale in rkLocales) {
      for (final scale in rkTextScales) {
        for (final viewport in rkPhones) {
          final where =
              '${locale.languageCode} @ $scale on '
              '${viewport.width.toInt()}×${viewport.height.toInt()}';
          testWidgets('F1-25b-1 S9.2 no-invite state fits and every line '
              'resolves — $where', (tester) async {
            await pumpRk(
              tester,
              const ShowMyCodeNoInviteScreen(),
              locale: locale,
              textScale: scale,
              viewport: viewport,
            );
            expect(tester.takeException(), isNull);
            final l10n = await AppLocalizations.delegate.load(locale);
            expect(find.text(l10n.ceremonyShowNoInviteTitle), findsOne);
            expect(find.text(l10n.ceremonyShowNoInviteBody), findsOne);
            expect(find.text(l10n.ceremonyShowNoInviteWhy), findsOne);
            await tester.ensureVisible(
              find.text(l10n.ceremonyShowNoInviteClose),
            );
            await tester.pumpAndSettle();
            expectTextFits(tester, reason: 'S9.2 no invite $where');
          });
        }
      }
    }
  });

  group('the root installs it (ADR 2026-09-24b §2)', () {
    test('F1-24b-3 bootstrap builds the ceremony factory through '
        'buildLiveCeremonySessions — never the bare constructor, whose '
        'defaults relay no key and find no session — and hands THAT factory '
        'to the CeremonyScope around the app', () {
      final root = _bootstrapCode();
      // The stripper really kept the code, so nothing below can pass on an
      // empty string.
      expect(root, contains('Future<void> bootstrap() async {'));

      final built = RegExp(r'final\s+(\w+)\s*=\s*buildLiveCeremonySessions\(')
          .allMatches(root)
          .toList();
      expect(built, hasLength(1), reason: 'the root builds it, once');
      // The builder's meta pull is the members client's — the one feed
      // sync-meta relays `umk_public_keys` on.
      expect(
        RegExp(
          r'buildLiveCeremonySessions\([^;]*pullMeta:\s*membersApi\.pullMeta',
        ).hasMatch(root),
        isTrue,
        reason: 'the relayed keys come from the meta pull',
      );
      expect(
        RegExp(r'\bLiveCeremonySessions\(').hasMatch(root),
        isFalse,
        reason:
            'a bare constructor call could leave relayedUmk / liveSessionOf '
            'on their defaults and still compile',
      );
      expect(root, isNot(contains('noRelayedUmk')));
      expect(root, isNot(contains('noLiveCeremonySession')));

      // The binding, not the co-occurrence: the scope is given the identifier
      // the builder returned, and there is exactly one scope.
      final installed = RegExp(r'CeremonyScope\(\s*sessions:\s*(\w+)\s*,')
          .allMatches(root)
          .toList();
      expect(installed, hasLength(1), reason: 'one scope, naming a factory');
      expect(installed.single.group(1), built.single.group(1));
      expect(
        RegExp(r'CeremonyScope\(\s*sessions:\s*\w+\s*,\s*child:\s*app\s*,')
            .hasMatch(root),
        isTrue,
        reason: 'it wraps the app itself, so every route reads it',
      );
    });

    test('F1-25b-1 bootstrap binds S9.2’s nonce to the invite relay: one '
        'InviteNonceRelay over the members client’s GET and accept routes, '
        'its nonce handed to the ceremony builder through '
        'relayedInviteNonceOver, and the joiner’s accept going through that '
        'same relay — so the accepted invite id is the one paired, and kept '
        'in the protected item store so it is paired after a restart', () {
      final root = _bootstrapCode();
      expect(root, contains('Future<void> bootstrap() async {'));

      final relays = RegExp(r'final\s+(\w+)\s*=\s*InviteNonceRelay\(')
          .allMatches(root)
          .toList();
      expect(relays, hasLength(1), reason: 'one relay, built once');
      final relay = relays.single.group(1)!;
      expect(
        RegExp(
          r'InviteNonceRelay\(\s*offers:\s*membersApi\.myInvites\s*,\s*'
          r'accept:\s*membersApi\.acceptInviteRelayed\s*,\s*'
          r'store:\s*KeyStorePrefs\(\s*keys\s*\)\s*,?\s*\)',
        ).hasMatch(root),
        isTrue,
        reason:
            'over the members client’s two invite routes, with the '
            'accepted id kept in the device’s protected item store — the '
            'same `keys` the settings use — so S9.2 pairs after a restart',
      );
      expect(
        RegExp(r'final\s+keys\s*=\s*KeychainKeyStore\(\)').hasMatch(root),
        isTrue,
        reason: 'the store is the platform keystore, not a memory fake',
      );
      expect(
        RegExp(
          r'buildLiveCeremonySessions\([^;]*nonces:\s*relayedInviteNonceOver\(\s*'
          '$relay'
          r'\.nonce\s*\)',
        ).hasMatch(root),
        isTrue,
        reason: 'S9.2 reads the relayed nonce, not null and not a draw',
      );
      expect(
        RegExp(
          r'DelegatedInvitationGateway\([^;]*accept:\s*'
          '$relay'
          r'\.acceptInvite',
        ).hasMatch(root),
        isTrue,
        reason: 'the accept that records the invite id is the joiner’s own',
      );
      expect(RegExp(r'nonces:\s*null').hasMatch(root), isFalse);
      // Nothing in the root draws an invite nonce.
      expect(root, isNot(contains('randomBytes(ceremonyNonceBytes')));
    });
  });
}

/// `lib/bootstrap.dart` with comments stripped — the same reading as
/// F1-06-90's (`recovery_ladder_source_test.dart`), so a comment that names a
/// call can never stand in for the call.
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
