@Tags(['F1'])
library;

// S11's guardians row says when the trusted-member set can no longer switch
// off a lost phone (ADR 2026-10-03b §4 🔒, 07 §15 Devices & security).
//
// The rule runs on the sync engine's own fact types — [GuardianSetVersion]
// with its tenant, and the verified [MembershipFact]s — so every widget case
// below feeds facts through [guardianRevokeGapOf] rather than handing the
// screen a ready-made answer: a seam that returned nothing would leave every
// "shown" case without its line, and the "not shown" case is held against a
// live flip in the same pump.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/devices/devices_repository.dart';
import 'package:rukka_folio/features/devices/devices_routes.dart';
import 'package:rukka_folio/features/devices/guardian_standing.dart';
import 'package:rukka_folio/features/devices/screens/s11_devices_screen.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/guardians.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/sync/guardians_seams.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:sync_engine/sync_engine.dart'
    show GuardianSetVersion, MapUmkSource, MembershipFact, RecordTrustStore;

import '../../shared/test_app.dart';

const _me = 'u-me';
const _t = 't-family';
const _other = 't-shop';
const _g = ['g-1', 'g-2', 'g-3'];

const _warning =
    'Your trusted members can still help you get back in, but can no longer '
    'switch off a lost phone together — choose your trusted members again.';
const _ordinary = 'The people who can help you get back in';

/// v1 lived in another tenant; v2 — the set in force — is a 2-of-3 in [_t].
List<GuardianSetVersion> _history({String? tenant = _t}) => [
  const GuardianSetVersion(
    subjectUserId: _me,
    shareSetVersion: 1,
    k: 2,
    guardianUserIds: {'g-old-1', 'g-old-2'},
    tenantId: _other,
  ),
  GuardianSetVersion(
    subjectUserId: _me,
    shareSetVersion: 2,
    k: 2,
    guardianUserIds: _g.toSet(),
    tenantId: tenant,
  ),
];

var _id = 0;
MembershipFact _fact(String user, String status, int seq, {String t = _t}) =>
    MembershipFact(
      recordId: 'r-${_id++}',
      tenantId: t,
      userId: user,
      status: status,
      seq: seq,
    );

MembershipFact _removed(String user, int seq, {String t = _t}) =>
    _fact(user, MembershipFact.removed, seq, t: t);

/// g-1 removed for good; g-2 removed and taken back; g-3 removed only in
/// another tenant. Two of three still belong to [_t] — k still holds.
List<MembershipFact> _kHolds() => [
  _removed('g-1', 3),
  _removed('g-2', 4),
  _fact('g-2', 'active', 9),
  _removed('g-3', 5, t: _other),
];

final _thisPhone = LinkedDevice(
  id: 'd-this',
  name: 'My phone',
  model: 'Pixel 8',
  addedOn: DateTime(2026, 8, 1),
  lastActive: DateTime(2026, 9, 7, 9),
  status: DeviceStatus.certified,
  isThisDevice: true,
);

FakeDevicesRepository _repo() {
  final r = FakeDevicesRepository(
    initial: DevicesSnapshot(devices: [_thisPhone]),
  );
  return r;
}

GuardianStanding _source(
  List<GuardianSetVersion> history,
  List<MembershipFact> facts, {
  Iterable<Stream<Object?>> changes = const [],
}) => GuardianStanding(
  () => guardianRevokeGapOf(
    subjectUserId: _me,
    history: history,
    memberships: facts,
  ),
  changes: changes,
);

/// A trust store as the engine leaves it after a meta pull: [_history] and
/// [facts] filed, plus another user's tenantless set this user guards (the
/// meta pull carries those too) — which must never be read as this user's.
RecordTrustStore _store(List<MembershipFact> facts) {
  final trust = RecordTrustStore(umks: const MapUmkSource({}));
  trust.guardianHistory
    ..addAll(_history())
    ..add(
      const GuardianSetVersion(
        subjectUserId: 'u-someone-else',
        shareSetVersion: 7,
        k: 2,
        guardianUserIds: {_me, 'g-9'},
      ),
    );
  trust.memberships.addAll(facts);
  return trust;
}

/// The server's side of S11.1 for [ServerGuardians]: `guardian_sets` as the
/// meta route returns it, decoded through the real wire parser.
final class _Api implements GuardiansApi {
  List<Map<String, Object?>> rows = const [];

  @override
  Future<List<GuardianSetWire>> sets() async => [
    for (final r in rows) GuardianSetWire.fromJson(r),
  ];

  @override
  Future<bool> hasGuardianSet() async => rows.isNotEmpty;

  @override
  Future<int> publish({
    required int shareSetVersion,
    required int k,
    required List<SealedGuardianShare> shares,
  }) => throw UnimplementedError('not exercised');
}

Map<String, Object?> _row(int version, List<String> guardians, String? t) => {
  'subject_user_id': _me,
  'share_set_version': version,
  'tenant_id': t,
  'k': 2,
  'n': guardians.length,
  'guardian_user_ids': guardians,
};

Future<List<String>> _pumpS11(
  WidgetTester tester,
  GuardianStanding standing, {
  Locale? locale,
  double textScale = 1,
  Size viewport = rkTallViewport,
}) async {
  final opened = <String>[];
  await pumpRk(
    tester,
    DevicesRepositoryScope(
      repository: _repo(),
      child: GuardianStandingScope(
        standing: standing,
        child: DevicesScreen(onOpenRow: opened.add),
      ),
    ),
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
  return opened;
}

Finder _rowIcon(IconData icon) => find.descendant(
  of: find.byKey(const Key('devices.row.guardians')),
  matching: find.byIcon(icon),
);

void main() {
  group('F1-03b-1 the guardians row says when the set can no longer switch '
      'off a lost phone (ADR 2026-10-03b §4 🔒)', () {
    test('the rule: below k · the user left · no tenant · k still hold · '
        'no set at all', () {
      GuardianRevokeGap? gap(
        List<MembershipFact> facts, {
        List<GuardianSetVersion>? history,
      }) => guardianRevokeGapOf(
        subjectUserId: _me,
        history: history ?? _history(),
        memberships: facts,
      );

      expect(
        gap([_removed('g-1', 3), _removed('g-2', 4)]),
        GuardianRevokeGap.belowThreshold,
      );
      expect(gap([_removed(_me, 6)]), GuardianRevokeGap.subjectLeft);
      expect(
        gap([_removed(_me, 6), _fact(_me, 'active', 8)]),
        isNull,
        reason: 'the latest fact decides — a re-admitted user belongs again',
      );
      expect(
        gap(const [], history: _history(tenant: null)),
        GuardianRevokeGap.noTenant,
        reason: 'the set in force (v2) names no tenant, though v1 did',
      );
      expect(gap(_kHolds()), isNull);
      expect(
        gap([
          _removed('g-1', 3, t: _other),
          _removed('g-2', 4, t: _other),
          _removed(_me, 5, t: _other),
        ]),
        isNull,
        reason: 'only the set’s own tenant counts',
      );
      expect(gap(const [], history: const []), isNull, reason: 'no set');
    });

    testWidgets('shown when fewer than k guardians still belong', (
      tester,
    ) async {
      await _pumpS11(
        tester,
        _source(_history(), [_removed('g-1', 3), _removed('g-2', 4)]),
      );
      expect(find.text(_warning), findsOneWidget);
      expect(find.text(_ordinary), findsNothing);
      // Colour never alone: the icon itself changes, not just its tint.
      expect(_rowIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(_rowIcon(Icons.group_outlined), findsNothing);
    });

    testWidgets('shown when the user no longer belongs to the set’s tenant', (
      tester,
    ) async {
      await _pumpS11(tester, _source(_history(), [_removed(_me, 6)]));
      expect(find.text(_warning), findsOneWidget);
      expect(_rowIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shown when the set in force has no tenant', (tester) async {
      await _pumpS11(tester, _source(_history(tenant: null), const []));
      expect(find.text(_warning), findsOneWidget);
      expect(_rowIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('NOT shown while k still hold — and one standing, installed '
        'once, flips the row when its change signal fires', (tester) async {
      final facts = _kHolds();
      final filed = StreamController<Object?>.broadcast();
      addTearDown(filed.close);
      final standing = _source(_history(), facts, changes: [filed.stream]);
      addTearDown(standing.dispose);
      await _pumpS11(tester, standing);
      expect(find.text(_warning), findsNothing);
      expect(find.text(_ordinary), findsOneWidget);
      expect(_rowIcon(Icons.group_outlined), findsOneWidget);

      // Nothing above S11 rebuilds: the scope and the screen are the ones
      // pumped above. Only the standing's own signal moves the row.
      facts.add(_removed('g-2', 12));
      await tester.pump();
      expect(find.text(_warning), findsNothing, reason: 'no signal yet');
      filed.add(null);
      await tester.pumpAndSettle();
      expect(find.text(_warning), findsOneWidget);
      expect(find.text(_ordinary), findsNothing);

      // …and back, the moment g-2 is taken back.
      facts.add(_fact('g-2', 'active', 13));
      filed.add(null);
      await tester.pumpAndSettle();
      expect(find.text(_warning), findsNothing);
      expect(find.text(_ordinary), findsOneWidget);
    });

    test('trustStoreGuardianStanding reads the engine’s own store, for this '
        'subject only', () {
      final trust = _store([_removed('g-1', 3), _removed('g-2', 4)]);
      final standing = trustStoreGuardianStanding(
        trust,
        subjectUserId: _me,
        pollEvery: null,
      );
      addTearDown(standing.dispose);
      expect(standing.gap, GuardianRevokeGap.belowThreshold);

      // The store is read live, not copied at construction.
      trust.memberships.add(_fact('g-2', 'active', 9));
      expect(standing.gap, isNull);
      trust.memberships.add(_removed(_me, 10));
      expect(standing.gap, GuardianRevokeGap.subjectLeft);

      // Whose set it is comes from the subject given: the other user's
      // tenantless set in the same store is not this user's noTenant…
      final clean = _store(_kHolds());
      expect(
        trustStoreGuardianStanding(
          clean,
          subjectUserId: _me,
          pollEvery: null,
        ).gap,
        isNull,
      );
      // …and read as that user's, it is.
      expect(
        trustStoreGuardianStanding(
          clean,
          subjectUserId: 'u-someone-else',
          pollEvery: null,
        ).gap,
        GuardianRevokeGap.noTenant,
      );
    });

    testWidgets('trustStoreGuardianStanding, installed once, flips S11 when '
        'the engine files a removal while the screen is open', (tester) async {
      final trust = _store(_kHolds());
      final standing = trustStoreGuardianStanding(
        trust,
        subjectUserId: _me,
        pollEvery: const Duration(seconds: 1),
      );
      addTearDown(standing.dispose);
      await _pumpS11(tester, standing);
      expect(find.text(_ordinary), findsOneWidget);

      // What `SyncEngine._applyMeta` does on a pull — and it tells nobody.
      trust.memberships.add(_removed('g-2', 12));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(_warning), findsOneWidget);
      expect(_rowIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('a set chosen again in S11.1 clears the row when S11.1 reads '
        'it back — not at the next meta pull', (tester) async {
      // The engine still holds v2, below k; the server already holds v3.
      final trust = _store([_removed('g-1', 3), _removed('g-2', 4)]);
      final api = _Api()..rows = [_row(2, _g, _t)];
      final guardians = ServerGuardians(
        api: api,
        roster: () async => const GuardianRoster(tenantId: _t),
        verified: const MapUmkSource({}),
      );
      addTearDown(guardians.dispose);
      final standing = trustStoreGuardianStanding(
        trust,
        subjectUserId: _me,
        guardians: guardians,
        pollEvery: null,
      );
      addTearDown(standing.dispose);
      await _pumpS11(tester, standing);
      expect(find.text(_warning), findsOneWidget);

      // S11.1's save ends in a read-back (ServerGuardians.save → refresh).
      api.rows = [
        _row(2, _g, _t),
        _row(3, ['g-3', 'g-4', 'g-5'], _t),
      ];
      await guardians.refresh();
      await tester.pumpAndSettle();
      expect(find.text(_warning), findsNothing);
      expect(find.text(_ordinary), findsOneWidget);
      // The engine's history is untouched — the read-back carried it.
      expect(trust.guardianHistory.map((v) => v.shareSetVersion), [1, 2, 7]);
    });

    test('mergedGuardianHistory keeps the engine’s row where both hold a '
        'generation, and the wire’s tenant where only it does', () {
      final merged = mergedGuardianHistory(_history(), [
        GuardianSetWire.fromJson(_row(2, _g, _other)),
        GuardianSetWire.fromJson(_row(3, _g, _t)),
        GuardianSetWire.fromJson(_row(4, _g, null)),
      ]).toList();
      expect(merged.map((v) => (v.shareSetVersion, v.tenantId)), [
        (1, _other),
        (2, _t),
        (3, _t),
        (4, null),
      ]);
    });

    testWidgets('tapping the row opens S11.1 through the real devices route '
        '— never a dead end (07 §1)', (tester) async {
      rkViewport(tester, rkTallViewport);
      final guardians = FakeGuardians(initial: const GuardianSetup());
      addTearDown(guardians.dispose);
      final router = GoRouter(
        initialLocation: DevicesPaths.devices,
        routes: devicesRoutes,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        RkScope(
          db: await openTestDb(),
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          keys: FakeKeyStore(),
          now: testNow,
          child: DevicesRepositoryScope(
            repository: _repo(),
            child: MembersRepositoryScope(
              repository: FakeMembersRepository(),
              child: GuardiansScope(
                repository: guardians,
                child: GuardianStandingScope(
                  standing: _source(_history(), [_removed(_me, 6)]),
                  child: MaterialApp.router(
                    routerConfig: router,
                    supportedLocales: AppLocalizations.supportedLocales,
                    localizationsDelegates: rkLocalizationsDelegates,
                    theme: rkTheme(Brightness.light),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_warning), findsOneWidget);

      await tester.tap(find.text(_warning));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        DevicesPaths.guardians,
      );
      expect(find.byType(GuardianSetupScreen), findsOneWidget);
    });

    testWidgets('the row hands S11 its guardians action, and EN, ਪੰਜਾਬੀ and '
        'हिन्दी fit at 200 % on 360×800', (tester) async {
      for (final (locale, line) in [
        (const Locale('en'), _warning),
        (
          const Locale('pa'),
          'ਤੁਹਾਡੇ ਭਰੋਸੇਮੰਦ ਮੈਂਬਰ ਹਾਲੇ ਵੀ ਤੁਹਾਨੂੰ ਵਾਪਸ ਅੰਦਰ ਆਉਣ ਵਿੱਚ ਮਦਦ ਕਰ '
              'ਸਕਦੇ ਹਨ, ਪਰ ਹੁਣ ਮਿਲ ਕੇ ਗੁਆਚੇ ਫ਼ੋਨ ਨੂੰ ਬੰਦ ਨਹੀਂ ਕਰ ਸਕਦੇ — ਆਪਣੇ '
              'ਭਰੋਸੇਮੰਦ ਮੈਂਬਰ ਦੁਬਾਰਾ ਚੁਣੋ।',
        ),
        (
          const Locale('hi'),
          'आपके भरोसेमंद सदस्य अब भी आपको वापस अंदर आने में मदद कर सकते हैं, '
              'लेकिन अब मिलकर खोए फ़ोन को बंद नहीं कर सकते — अपने भरोसेमंद '
              'सदस्य फिर से चुनें।',
        ),
      ]) {
        final opened = await _pumpS11(
          tester,
          _source(_history(), [_removed('g-1', 3), _removed('g-3', 4)]),
          locale: locale,
          textScale: 2,
          viewport: rkPhone360,
        );
        final row = find.text(line);
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(row, findsOneWidget, reason: '$locale');
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale');
        await tester.tap(row);
        expect(opened, ['guardians'], reason: '$locale');
      }
    });
  });
}
