// F1-25-6 … F1-25-10 — the client half of the plan catalogue (ADR 2026-09-25
// §5–§6 🔒; server half M11-CAT1: 0018, `GET /sync-meta/plans`, the token's
// `features`).
//
// Rules tests, no widget: the catalogue reads what the server serves, unknown
// plan ids and fields round-trip (CLAUDE.md rule 6), money is integer paise
// or nothing (rule 1), the token's `features` are sorted, unique and `[]`
// when a plan has none, and the offline fallback cannot drift from 0018.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/plan_catalogue_source.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';

/// One row as `planToWire` writes it (sync-meta/index.ts). Synthetic numbers:
/// these tests assert the reader, not a price.
Map<String, Object?> _row(
  String id, {
  String entity = 'family',
  int yearly = 120000,
  int monthly = 12000,
  bool popular = false,
  List<String> features = const ['pdf_output', 'statement_import'],
  int books = 4,
  int sort = 1,
  Map<String, Object?> more = const {},
}) => {
  'id': id,
  'entity_type': entity,
  'name': 'Console label $id',
  'sort_order': sort,
  'limits': {
    'members': 6,
    'business_books': books,
    'devices': 8,
    'envelopes_per_book': 250000,
    'tenant_bytes': 5 << 30,
    'attachment_bytes': 5 << 30,
  },
  'features': features,
  'price_yearly_paise': yearly,
  'price_monthly_paise': monthly,
  'popular': popular,
  'placeholder': true,
  'updated_at': 1790000000000,
  ...more,
};

Map<String, Object?> _body(List<Object?> rows) => {
  'plans': rows,
  'catalogue_updated_at': 1790000000000,
};

/// A deep, JSON-level copy — what a real round trip through the wire does.
Object? _wire(Object? o) => jsonDecode(jsonEncode(o));

void main() {
  group(
    'F1-25-6 the catalogue reads GET /sync-meta/plans (ADR 2026-09-25 §6)',
    () {
      test('F1-25-6 ids, entity types, prices in paise, popular, limits and '
          'features come from the wire, not from the app', () {
        final c = RkPlanCatalogue.fromJson(
          _body([
            _row('family_lite', sort: 1, features: [], yearly: 100000),
            _row('family', sort: 2, popular: true, yearly: 200000),
            _row('personal', entity: 'individual', sort: 2, books: 3),
          ]),
        );
        expect(c.offline, isFalse);
        expect(c.unreadable, isEmpty);
        expect(c.plans.map((t) => t.plan.id), [
          'family_lite',
          'family',
          'personal',
        ]);
        final family = c.tierFor(RkPlan.family)!;
        expect(family.entityType, RkEntityType.family);
        expect(family.annualPaise, 200000);
        expect(family.monthlyPaise, 12000);
        expect(family.popular, isTrue);
        expect(family.limits.members, 6);
        expect(family.limits.businessBooks, 4);
        expect(family.describes(RkFeature.pdfOutput), isTrue);
        expect(c.tierFor(RkPlan.familyLite)!.features, isEmpty);
        // Grouped by entity type, cheapest first — the order S12.1 draws.
        expect(c.plansAlongside(RkPlan.family).map((t) => t.plan.id), [
          'family_lite',
          'family',
        ]);
        expect(c.plansAlongside(RkPlan.personal).map((t) => t.plan.id), [
          'personal',
        ]);
      });

      test('F1-25-6 unlimited is -1 on the wire and null in the app, and goes '
          'back as -1 (ADR 2026-09-24b §7 (b) 🔒)', () {
        final row = _row('family');
        (row['limits']! as Map)['business_books'] = -1;
        final tier = RkTier.fromJson(row);
        expect(tier.limits.businessBooks, isNull);
        expect((tier.toJson()['limits']! as Map)['business_books'], -1);
      });

      test('F1-25-6 the saving headline is integer arithmetic over the cards '
          'shown and never overstates (CLAUDE.md rule 1, 08 §3.1 🔒)', () {
        final c = RkPlanCatalogue.fromJson(
          _body([
            _row('free', yearly: 0, monthly: 0),
            // 12 × 12000 = 144000 against 120000 → 16.66…% → 16.
            _row('a', yearly: 120000, monthly: 12000),
            // 12 × 10000 = 120000 against 90000 → 25%.
            _row('b', yearly: 90000, monthly: 10000),
          ]),
        );
        expect(c.tierFor(const RkPlan('a'))!.annualSavingPercent, 16);
        expect(c.tierFor(const RkPlan('b'))!.annualSavingPercent, 25);
        // The smallest paid saving, so it is true of every card under it.
        expect(rkAnnualSavingPercentOf(c.plans), 16);
        expect(rkAnnualSavingPercentOf([c.tierFor(RkPlan.free)!]), 0);
      });
    },
  );

  group('F1-25-7 unknown ids and fields round-trip, never crash (CLAUDE.md '
      'rule 6)', () {
    test('F1-25-7 a plan id this build has no words for is still a plan, '
        'and every field it does not read is written back', () {
      final body = _body([
        _row(
          'kirana_max',
          entity: 'cooperative',
          more: {
            'tagline_key': 'x.y',
            'nested': {'a': 1},
          },
        ),
      ]);
      ((body['plans']! as List).first as Map)['limits'] = {
        ...((body['plans']! as List).first as Map)['limits'] as Map,
        'branches': 3,
      };
      body['currency'] = 'INR';
      final c = RkPlanCatalogue.fromJson(
        (_wire(body)! as Map).cast<String, Object?>(),
      );
      final t = c.plans.single;
      expect(t.plan, const RkPlan('kirana_max'));
      expect(RkPlan.named, isNot(contains(t.plan)));
      expect(t.entityType, 'cooperative');
      // The whole body comes back as it went — unknown row fields, unknown
      // limits keys, unknown top-level keys, and the name column.
      expect(_wire(c.toJson()), _wire(body));
      // A plan outside the catalogue draws every plan rather than guessing a
      // type (ADR 25 §5: nothing is hidden).
      expect(c.plansAlongside(const RkPlan('elsewhere')), c.plans);
    });

    test('F1-25-7 a row that cannot be read is kept whole and not drawn; a '
        'price that is not an integer is refused, never rounded (rule 1)', () {
      final body = _body([
        _row('family'),
        _row('floaty', yearly: 0)..['price_yearly_paise'] = 2499.5,
        _row('stringy')..['price_monthly_paise'] = '24990',
        {'id': 'no_limits', 'entity_type': 'family'},
        'not even a row',
      ]);
      final c = RkPlanCatalogue.fromJson(
        (_wire(body)! as Map).cast<String, Object?>(),
      );
      expect(c.plans.map((t) => t.plan.id), ['family']);
      expect(c.unreadable, hasLength(4));
      // Unreadable rows are still in the round trip.
      expect((c.toJson()['plans']! as List), hasLength(5));
    });

    test('F1-25-7 a body without a plans list is malformed', () {
      expect(
        () => RkPlanCatalogue.fromJson({'plans': 'nope'}),
        throwsFormatException,
      );
      expect(() => RkPlanCatalogue.fromJson({}), throwsFormatException);
    });
  });

  group('F1-25-8 the HTTP adapter and the fake', () {
    final root = Uri.parse('https://api.example.test/functions/v1');

    test('F1-25-8 GET sync-meta/plans with the bearer token and client '
        'version; a 200 is parsed', () async {
      final http = FakeRkHttpTransport(
        (method, url, headers, body) =>
            RkHttpResponse(200, jsonEncode(_body([_row('family')]))),
      );
      final source = HttpPlanCatalogueSource(
        transport: http,
        functionsRoot: root,
        accessToken: () async => 'jwt-synthetic',
        clientVersion: '1.2.3',
      );
      final c = await source.read();
      expect(c.plans.single.plan, RkPlan.family);
      final call = http.calls.single;
      expect(call.method, 'GET');
      expect(
        call.url.toString(),
        'https://api.example.test/functions/v1/sync-meta/plans',
      );
      expect(call.headers['authorization'], 'Bearer jwt-synthetic');
      expect(
        call.headers[HttpPlanCatalogueSource.clientVersionHeader],
        '1.2.3',
      );
    });

    test(
      'F1-25-8 offline with nothing read is a named failure; offline '
      'after a good read hands back that read — never the offline mirror',
      () async {
        var online = false;
        final http = FakeRkHttpTransport((method, url, headers, body) {
          if (!online) throw const RkHttpFailure();
          return RkHttpResponse(200, jsonEncode(_body([_row('family')])));
        });
        final source = HttpPlanCatalogueSource(
          transport: http,
          functionsRoot: root,
          accessToken: () async => 'jwt',
        );
        await expectLater(
          source.read(),
          throwsA(
            isA<PlanCatalogueFailure>().having(
              (f) => f.reason,
              'reason',
              PlanCatalogueRefusal.offline,
            ),
          ),
        );
        online = true;
        final first = await source.read();
        online = false;
        final again = await source.read();
        expect(identical(again, first), isTrue);
        expect(again.offline, isFalse);
      },
    );

    test('F1-25-8 no session asks nothing; 401, 500 and a non-catalogue 200 '
        'are each their own failure', () async {
      var status = 401;
      var text = '{}';
      final http = FakeRkHttpTransport(
        (method, url, headers, body) => RkHttpResponse(status, text),
      );
      final noSession = HttpPlanCatalogueSource(
        transport: http,
        functionsRoot: root,
        accessToken: () async => null,
      );
      await expectLater(
        noSession.read(),
        throwsA(
          isA<PlanCatalogueFailure>().having(
            (f) => f.reason,
            'reason',
            PlanCatalogueRefusal.unauthorized,
          ),
        ),
      );
      expect(http.calls, isEmpty);

      final source = HttpPlanCatalogueSource(
        transport: http,
        functionsRoot: root,
        accessToken: () async => 'jwt',
      );
      Future<PlanCatalogueRefusal> reason() async {
        try {
          await source.read();
        } on PlanCatalogueFailure catch (f) {
          return f.reason;
        }
        fail('read() did not fail');
      }

      expect(await reason(), PlanCatalogueRefusal.unauthorized);
      status = 500;
      expect(await reason(), PlanCatalogueRefusal.server);
      status = 200;
      text = '{"plans": 7}';
      expect(await reason(), PlanCatalogueRefusal.malformed);
      text = 'not json';
      expect(await reason(), PlanCatalogueRefusal.malformed);
    });

    test('F1-25-8 the fake is a real seam: reads are counted and a failure '
        'is thrown', () async {
      final fake = FakePlanCatalogueSource();
      expect((await fake.read()).offline, isTrue);
      fake.failure = const PlanCatalogueFailure(PlanCatalogueRefusal.server);
      await expectLater(fake.read(), throwsA(isA<PlanCatalogueFailure>()));
      expect(fake.reads, 2);
      // With no scope mounted, the screens read the labelled fallback.
      expect(
        await const OfflinePlanCatalogueSource().read(),
        same(rkOfflineCatalogue),
      );
    });
  });

  group('F1-25-9 the entitlement carries the token\'s features (ADR '
      '2026-09-25 §6)', () {
    test('F1-25-9 sorted, unique, [] when a plan has none; unknown names are '
        'kept; a malformed list is an error, never a Free reading', () {
      expect(rkFeaturesFromWire(null), isEmpty);
      expect(rkFeaturesFromWire(<Object?>[]), isEmpty);
      expect(
        rkFeaturesFromWire([
          'statement_import',
          'pdf_output',
          'statement_import',
          'future_thing',
        ]),
        ['future_thing', 'pdf_output', 'statement_import'],
      );
      expect(() => rkFeaturesFromWire('pdf_output'), throwsFormatException);
      expect(() => rkFeaturesFromWire([1]), throwsFormatException);
      expect(() => rkFeaturesFromWire(['']), throwsFormatException);

      final read = Entitlement.fromToken(
        tenantId: 't1',
        plan: RkPlan.fromWire('shop'),
        limits: EntitlementLimits.fromWire({
          'members': 2,
          'business_books': 1,
          'devices': 8,
          'envelopes_per_book': 250000,
          'tenant_bytes': 5 << 30,
          'attachment_bytes': 5 << 30,
        }),
        graceKind: EntitlementGraceKind.none,
        times: const EntitlementTokenTimes(),
        source: EntitlementSourceKind.fresh,
        activeMembers: 1,
        features: const ['statement_import', 'pdf_output', 'pdf_output'],
      );
      expect(read.features, ['pdf_output', 'statement_import']);
      expect(read.has(RkFeature.pdfOutput), isTrue);
      expect(read.has(RkFeature.statementImport), isTrue);
      expect(read.plan, RkPlan.shop);
      expect(read.limits.perFileBytes, rkPerFileBytes);
    });

    test('F1-25-9 no token is Free, and Free holds neither extra (ADR '
        '2026-09-05g §1 🔒, ADR 2026-09-25 §5 🔒)', () {
      final read = Entitlement.untokened();
      expect(read.plan, RkPlan.free);
      expect(read.features, isEmpty);
      expect(read.has(RkFeature.pdfOutput), isFalse);
      expect(read.has(RkFeature.statementImport), isFalse);
    });

    test('F1-25-9 a gate asks the features, not the name: a free-named plan '
        'with pdf_output has it, a family-named plan without does not', () {
      Entitlement reading(RkPlan plan, List<String> features) => Entitlement(
        tenantId: 't1',
        plan: plan,
        limits: rkTierFor(RkPlan.family).limits,
        periodEnd: null,
        graceKind: EntitlementGraceKind.none,
        source: EntitlementSourceKind.fresh,
        activeMembers: 1,
        features: features,
      );
      expect(
        reading(RkPlan.free, ['pdf_output']).has(RkFeature.pdfOutput),
        isTrue,
      );
      expect(reading(RkPlan.family, []).has(RkFeature.pdfOutput), isFalse);
      // A stale reading keeps its extras: offline grace blocks nothing.
      final stale = Entitlement(
        tenantId: 't1',
        plan: RkPlan.family,
        limits: rkTierFor(RkPlan.family).limits,
        periodEnd: null,
        graceKind: EntitlementGraceKind.none,
        source: EntitlementSourceKind.stale,
        activeMembers: 1,
        features: const ['pdf_output'],
      );
      expect(stale.state, EntitlementState.offlineGrace);
      expect(stale.has(RkFeature.pdfOutput), isTrue);
    });

    test('F1-25-9 plan and limits read off the wire; a limit that is not a '
        'count is malformed', () {
      expect(RkPlan.fromWire('business_plus'), RkPlan.businessPlus);
      expect(() => RkPlan.fromWire(''), throwsFormatException);
      expect(() => RkPlan.fromWire(3), throwsFormatException);
      expect(
        () => EntitlementLimits.fromWire({'members': '6'}),
        throwsFormatException,
      );
      expect(
        () => EntitlementLimits.fromWire({
          'members': -2,
          'business_books': 1,
          'devices': 1,
          'envelopes_per_book': 1,
          'tenant_bytes': 1,
          'attachment_bytes': 1,
        }),
        throwsFormatException,
      );
    });
  });

  group('F1-25-10 the offline fallback is labelled and mirrors 0018', () {
    test('F1-25-10 every seeded row, number for number, as the server seeds '
        'it — so the fallback cannot drift from the catalogue', () {
      final sql = File('../server/supabase/migrations/0018_plan_catalogue.sql')
          .readAsStringSync();
      final row = RegExp(
        r"\('(\w+)',\s*'(\w+)',\s*'[^']*',\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),"
        r"\s*(\d+),\s*(\d+),\s*(\d+),\s*'\{([a-z_,]*)\}',\s*(\d+),\s*(\d+),"
        r'\s*(true|false),\s*(true|false)\)',
      );
      final seeded = row.allMatches(sql).toList();
      expect(seeded, hasLength(10), reason: '0018 seeds ten plans');
      expect(rkOfflineCatalogue.offline, isTrue);
      expect(rkOfflineCatalogue.plans, hasLength(seeded.length));
      for (final m in seeded) {
        final t = rkTierFor(RkPlan(m[1]!));
        int n(int g) => int.parse(m[g]!);
        expect(t.entityType, m[2], reason: m[1]);
        expect(t.sortOrder, n(3), reason: m[1]);
        expect(t.limits.members, n(4), reason: m[1]);
        expect(t.limits.businessBooks, n(5), reason: m[1]);
        expect(t.limits.devices, n(6), reason: m[1]);
        expect(t.limits.envelopesPerBook, n(7), reason: m[1]);
        expect(t.limits.tenantBytes, n(8), reason: m[1]);
        expect(t.limits.attachmentBytes, n(9), reason: m[1]);
        expect(
          t.features,
          rkNormalisedFeatures(m[10]!.split(',').where((f) => f.isNotEmpty)),
          reason: m[1],
        );
        expect(t.annualPaise, n(11), reason: m[1]);
        expect(t.monthlyPaise, n(12), reason: m[1]);
        expect(t.popular, m[13] == 'true', reason: m[1]);
        expect(t.placeholder, m[14] == 'true', reason: m[1]);
      }
    });

    test('F1-25-10 every seeded id has words in this build', () {
      for (final t in rkOfflineCatalogue.plans) {
        expect(RkPlan.named, contains(t.plan));
      }
      expect(() => rkTierFor(const RkPlan('nope')), throwsStateError);
    });
  });
}
