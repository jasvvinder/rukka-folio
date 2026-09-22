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

  group('tier catalogue — 08 §2 🔒 and 08 §3.1 🔒', () {
    test('F1-07-453 the quota table is 08 §2, row for row', () {
      int q(RkPlan p, int? Function(EntitlementLimits l) f) =>
          f(rkTierFor(p).limits)!;

      // Members / business books (08 §2 tier table).
      expect(rkTierFor(RkPlan.free).limits.members, 1);
      expect(rkTierFor(RkPlan.personal).limits.members, 1);
      expect(rkTierFor(RkPlan.family).limits.members, 5);
      expect(rkTierFor(RkPlan.familyPlus).limits.members, 15);
      expect(rkTierFor(RkPlan.free).limits.businessBooks, 1);
      // Unlimited is null, never a large number.
      expect(rkTierFor(RkPlan.personal).limits.businessBooks, isNull);
      expect(rkTierFor(RkPlan.family).limits.businessBooks, 3);
      expect(rkTierFor(RkPlan.familyPlus).limits.businessBooks, isNull);

      // Devices per user (08 §2 🔒 quota table).
      expect(
        [for (final p in RkPlan.values) q(p, (l) => l.devices)],
        [5, 5, 8, 15],
      );
      // Envelopes per book.
      expect(
        [for (final p in RkPlan.values) q(p, (l) => l.envelopesPerBook)],
        [10000, 100000, 250000, 1000000],
      );
      // Tenant envelope bytes: 250 MB · 2 GB · 5 GB · 15 GB.
      expect(
        [for (final p in RkPlan.values) q(p, (l) => l.tenantBytes)],
        [250 * 1024 * 1024, 2 << 30, 5 << 30, 15 << 30],
      );
      // Attachment bytes: 100 MB · 2 GB · 5 GB · 20 GB.
      expect(
        [for (final p in RkPlan.values) q(p, (l) => l.attachmentBytes)],
        [100 * 1024 * 1024, 2 << 30, 5 << 30, 20 << 30],
      );
      // Per-file cap is 10 MB on every tier.
      expect([
        for (final p in RkPlan.values) q(p, (l) => l.perFileBytes),
      ], List.filled(4, 10 * 1024 * 1024));
    });

    test('F1-07-453 prices are integer paise and the saving is integer '
        'arithmetic that never overstates (CLAUDE.md rule 1, 08 §3.1 🔒)', () {
      // 08 §2's annual prices, in paise. A float never touches money.
      expect(rkTierFor(RkPlan.free).annualPaise, 0);
      expect(rkTierFor(RkPlan.personal).annualPaise, 59900);
      expect(rkTierFor(RkPlan.family).annualPaise, 199900);
      expect(rkTierFor(RkPlan.familyPlus).annualPaise, 399900);
      for (final tier in rkTiers) {
        expect(tier.annualPaise, isA<int>());
        expect(tier.monthlyPaise, isA<int>());
        expect(tier.priceFor(RkBillingCycle.annual), tier.annualPaise);
        expect(tier.priceFor(RkBillingCycle.monthly), tier.monthlyPaise);
      }

      // Free saves nothing and claims nothing.
      expect(rkTierFor(RkPlan.free).annualSavingPercent, 0);

      for (final tier in rkTiers.where((t) => !t.isFree)) {
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

      // The one headline is true of every paid card under it.
      expect(
        rkAnnualSavingPercent,
        lessThanOrEqualTo(
          rkTiers
              .where((t) => !t.isFree)
              .map((t) => t.annualSavingPercent)
              .reduce((a, b) => a < b ? a : b),
        ),
      );
      expect(rkAnnualSavingPercent, 20);
    });

    test(
      'F1-07-453 exactly one tier carries the popular badge (08 §3.1 🔒)',
      () {
        expect(rkTiers.where((t) => t.popular).map((t) => t.plan), [
          RkPlan.family,
        ]);
        // The catalogue runs cheapest first, Free at the head.
        expect(rkTiers.map((t) => t.plan), RkPlan.values);
      },
    );

    test('F1-07-453 storage reads in whole GB where it divides', () {
      expect(rkStorageOf(5 << 30), (amount: 5, gigabytes: true));
      expect(rkStorageOf(250 * 1024 * 1024), (amount: 250, gigabytes: false));
    });
  });
}
