// F1 tests for the entitlement seam and the tier catalogue (07 §20 🔒, 08 §2 🔒
// quota table, 08 §3.1 🔒 upgrade flow, ADR 2026-09-05g §1/§4/§14).
//
// These are the *rules* tests: the two graces kept apart, "no token is not a
// lock", and money that is integer paise end to end. They pump no widget —
// a screen cannot be trusted to enforce a 🔒 line that the value type lets it
// break.
@Tags(['F1'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';

Entitlement _reading({
  required EntitlementGraceKind grace,
  required EntitlementSourceKind source,
  RkPlan plan = RkPlan.family,
  int activeMembers = 3,
}) => Entitlement(
  tenantId: 't1',
  plan: plan,
  limits: rkTierFor(plan).limits,
  periodEnd: DateTime(2026, 10, 1),
  graceKind: grace,
  source: source,
  activeMembers: activeMembers,
);

void main() {
  group(
    'entitlement seam — two graces, two copies (ADR 2026-09-05g §4 🔒)',
    () {
      test(
        'F1-07-450 a stale reading is offline grace whatever the token said — '
        'the lapse state is unreachable from an off-network phone',
        () {
          for (final grace in EntitlementGraceKind.values) {
            final read = _reading(
              grace: grace,
              source: EntitlementSourceKind.stale,
            );
            expect(
              read.state,
              EntitlementState.offlineGrace,
              reason: 'stale + $grace must never resolve to a server state',
            );
            expect(read.state.blocksEntry, isFalse);
          }
        },
      );

      test(
        'F1-07-451 no token is not a lock — an absent reading is a live Free '
        'tenant (ADR 2026-09-05g §1 🔒)',
        () {
          final read = Entitlement.untokened();
          expect(read.plan, RkPlan.free);
          expect(read.source, EntitlementSourceKind.absent);
          expect(read.state, EntitlementState.active);
          expect(read.state.blocksEntry, isFalse);
          expect(read.periodEnd, isNull);
          expect(read.limits.members, 1);
        },
      );

      test(
        'F1-07-452 only a fresh, server-declared lapse blocks entry; export is '
        'blocked in no state at all (08 §1 🔒 lapsed ≠ locked)',
        () {
          expect(
            _reading(
              grace: EntitlementGraceKind.lapsed,
              source: EntitlementSourceKind.fresh,
            ).state,
            EntitlementState.readOnly,
          );
          expect(
            _reading(
              grace: EntitlementGraceKind.dunning,
              source: EntitlementSourceKind.fresh,
            ).state,
            EntitlementState.dunningGrace,
          );
          expect(
            _reading(
              grace: EntitlementGraceKind.trial,
              source: EntitlementSourceKind.fresh,
            ).state,
            EntitlementState.trial,
          );
          expect(
            _reading(
              grace: EntitlementGraceKind.none,
              source: EntitlementSourceKind.fresh,
            ).state,
            EntitlementState.active,
          );

          final blocking = EntitlementState.values
              .where((s) => s.blocksEntry)
              .toList();
          expect(blocking, [EntitlementState.readOnly]);
          // Dunning is *the grace*: it exists so entry carries on while the
          // payment is retried (ADR 2026-09-05g §4).
          expect(EntitlementState.dunningGrace.blocksEntry, isFalse);
          for (final state in EntitlementState.values) {
            expect(
              state.blocksExport,
              isFalse,
              reason: '$state blocked export',
            );
          }
        },
      );

      test('F1-07-450 above 15 members is told, not refused (08 §2, ADR '
          '2026-09-05g §14 🔒)', () {
        expect(rkLargestMemberBand, 15);
        expect(
          _reading(
            grace: EntitlementGraceKind.none,
            source: EntitlementSourceKind.fresh,
            plan: RkPlan.familyPlus,
            activeMembers: 40,
          ).aboveLargestBand,
          isTrue,
        );
        expect(
          _reading(
            grace: EntitlementGraceKind.none,
            source: EntitlementSourceKind.fresh,
            plan: RkPlan.familyPlus,
            activeMembers: 15,
          ).aboveLargestBand,
          isFalse,
        );
      });

      test('F1-07-451 the fake is a real seam — a failure is thrown, and reads '
          'are counted so a retry is observable', () async {
        final fake = FakeEntitlementSource();
        expect((await fake.read()).plan, RkPlan.free);
        expect(fake.reads, 1);
        fake.failure = StateError('no token store');
        await expectLater(fake.read(), throwsStateError);
        expect(fake.reads, 2);
      });
    },
  );

  // F1-07-453 asserted 08 §2's four rows number for number. ADR 2026-09-25
  // §5–§6 🔒 moved every number into the server's catalogue ("08 §2 keeps the
  // rules; the numbers live in the catalogue"), so the rows are now asserted
  // against the catalogue the app reads — 0018 itself, in F1-25-10 — and
  // what stays here is the rules 08 keeps (M13-CAT2).
  group('tier catalogue — the rules 08 §2 / §3.1 keep (ADR 2026-09-25 §6)', () {
    test('F1-07-453 unlimited is null, never a large number, and every '
        'number a row carries is the catalogue\'s', () {
      for (final tier in rkOfflineCatalogue.plans) {
        // The per-file cap is plan-independent (08 §2), in no catalogue row.
        expect(tier.limits.perFileBytes, rkPerFileBytes);
        final wire = tier.toJson();
        final back = RkTier.fromJson(wire);
        expect(back.limits.members, tier.limits.members);
        expect(back.limits.businessBooks, tier.limits.businessBooks);
      }
      final row = rkTierFor(RkPlan.family).toJson();
      (row['limits']! as Map<String, Object?>)['business_books'] = -1;
      expect(RkTier.fromJson(row).limits.businessBooks, isNull);
    });

    test('F1-07-453 prices are integer paise and the saving is integer '
        'arithmetic that never overstates (CLAUDE.md rule 1, 08 §3.1 🔒)', () {
      final tiers = rkOfflineCatalogue.plans;
      for (final tier in tiers) {
        expect(tier.annualPaise, isA<int>());
        expect(tier.monthlyPaise, isA<int>());
        expect(tier.priceFor(RkBillingCycle.annual), tier.annualPaise);
        expect(tier.priceFor(RkBillingCycle.monthly), tier.monthlyPaise);
      }

      // Free saves nothing and claims nothing.
      expect(rkTierFor(RkPlan.free).isFree, isTrue);
      expect(rkTierFor(RkPlan.free).annualSavingPercent, 0);

      for (final tier in tiers.where((t) => !t.isFree)) {
        expect(tier.twelveMonthsPaise, tier.monthlyPaise * 12);
        expect(
          tier.annualSavingPaise,
          tier.twelveMonthsPaise - tier.annualPaise,
        );
        // Truncated, so the headline is never larger than the truth.
        expect(
          tier.annualSavingPercent * tier.twelveMonthsPaise,
          lessThanOrEqualTo(tier.annualSavingPaise * 100),
        );
      }

      // The one headline is the least saving of the paid cards shown.
      expect(
        rkAnnualSavingPercentOf(tiers),
        tiers
            .where((t) => !t.isFree)
            .map((t) => t.annualSavingPercent)
            .reduce((a, b) => a < b ? a : b),
      );
    });

    test(
      'F1-07-453 the popular badge is the catalogue\'s flag: at most one per '
      'entity type (ADR 2026-09-25 §5)',
      () {
        final byType = <String, int>{};
        for (final t in rkOfflineCatalogue.plans.where((t) => t.popular)) {
          byType[t.entityType] = (byType[t.entityType] ?? 0) + 1;
        }
        expect(byType.values.every((n) => n == 1), isTrue);
        // Each entity type's plans run cheapest first.
        for (final type in [
          RkEntityType.individual,
          RkEntityType.family,
          RkEntityType.business,
          RkEntityType.trust,
        ]) {
          final prices = [
            for (final t in rkOfflineCatalogue.forEntity(type)) t.annualPaise,
          ];
          expect(prices, [...prices]..sort(), reason: type);
        }
      },
    );

    test('F1-07-453 storage reads in whole GB where it divides', () {
      expect(rkStorageOf(5 << 30), (amount: 5, gigabytes: true));
      expect(rkStorageOf(250 * 1024 * 1024), (amount: 250, gigabytes: false));
    });
  });
}
