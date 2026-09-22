// Unit tests for the two feature-local seams behind S12.3, S12.4 and S12.6 —
// `SubscriptionCommands`, `InvoiceSource`, the pure GST split and the pure
// dunning countdown (08 §3 🔒, 08 §3.1 🔒, ADR 2026-09-05g §4, §10, §11 🔒).
//
// 💰 Every figure here is integer paise (CLAUDE.md rule 1). The GST split is
// pinned **at the paisa** on a real catalogue price, because a split that is
// only asserted to "roughly balance" is a split that can drift by a paisa a
// year and never be caught.
@Tags(['F1'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/dunning_grace.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/invoice_source.dart';
import 'package:rukka_folio/features/subscription/subscription_commands.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';

void main() {
  group('GST split (ADR 2026-09-05g §10 🔒)', () {
    test(
      'F1-07-468 the Family annual price splits to the paisa: 18 % inclusive, '
      'half-up, and every part sums back exactly',
      () {
        // 08 §2 🔒 — ₹1,999 a year, GST-inclusive, as integer paise.
        final total = rkTierFor(RkPlan.family).annualPaise;
        expect(total, 199900);

        final split = rkGstSplit(total);
        // 199900 × 10000 ÷ 11800 = 169406.78… → half-up → ₹1,694.07.
        expect(split.taxablePaise, 169407);
        expect(split.taxPaise, 30493);
        // 30493 ÷ 2 = 15246.5 → half-up → 15247, the other half takes the
        // remainder so the pair is exact.
        expect(split.cgstPaise, 15247);
        expect(split.sgstPaise, 15246);
        expect(split.cgstPaise + split.sgstPaise, split.taxPaise);
        // A whole-rupee price needs no round_off line.
        expect(split.roundOffPaise, 0);
        expect(
          split.taxablePaise + split.taxPaise + split.roundOffPaise,
          split.roundedTotalPaise,
        );
      },
    );

    test('F1-07-468 every catalogue price balances to the paisa', () {
      for (final tier in rkTiers) {
        for (final paise in [tier.annualPaise, tier.monthlyPaise]) {
          final split = rkGstSplit(paise);
          expect(
            split.taxablePaise + split.taxPaise,
            paise,
            reason: 'taxable + tax must equal the inclusive total ($paise)',
          );
          expect(
            split.cgstPaise + split.sgstPaise,
            split.taxPaise,
            reason: 'the two halves must be exact ($paise)',
          );
          expect(split.cgstPaise - split.sgstPaise, inInclusiveRange(0, 1));
        }
      }
    });

    test(
      'F1-07-468 round_off is the nearest whole rupee, half-up, shown as its '
      'own line (ADR 2026-09-05g §10 🔒)',
      () {
        // 49 paise rounds down, 50 rounds up: the line carries the difference.
        expect(rkGstSplit(199949).roundOffPaise, -49);
        expect(rkGstSplit(199950).roundOffPaise, 50);
        expect(rkGstSplit(199950).roundedTotalPaise, 200000);
        expect(rkGstSplit(199949).roundedTotalPaise, 199900);
        expect(rkGstSplit(0).roundOffPaise, 0);
        expect(rkGstSplit(0).taxPaise, 0);
      },
    );
  });

  group('InvoiceSource (S12.6)', () {
    test('F1-07-469 the shipped source reads empty — there is no invoice '
        'producer and none is invented (ADR 2026-09-05g §8 🔒)', () async {
      expect(await const UnwiredInvoiceSource().read(), isEmpty);
    });

    test('F1-07-469 the fake is a real seam: reads are counted and a failure '
        'is thrown', () async {
      final fake = FakeInvoiceSource(failure: StateError('no store'));
      await expectLater(fake.read(), throwsStateError);
      expect(fake.reads, 1);
      fake.failure = null;
      expect(await fake.read(), isEmpty);
      expect(fake.reads, 2);
    });

    test('F1-07-470 rkInvoicesNewestFirst sorts newest first and never '
        'mutates its argument', () {
      final given = [
        RkInvoice(
          serial: 'RF/2026-27/0001',
          issuedOn: DateTime(2026, 4, 2),
          totalPaise: 199900,
          kind: RkInvoiceKind.invoice,
        ),
        RkInvoice(
          serial: 'RF/2026-27/0003',
          issuedOn: DateTime(2026, 9, 1),
          totalPaise: 199900,
          kind: RkInvoiceKind.creditNote,
        ),
        RkInvoice(
          serial: 'RF/2026-27/0002',
          issuedOn: DateTime(2026, 9, 1),
          totalPaise: 59900,
          kind: RkInvoiceKind.invoice,
        ),
      ];
      final order = rkInvoicesNewestFirst(given).map((i) => i.serial).toList();
      expect(order, ['RF/2026-27/0003', 'RF/2026-27/0002', 'RF/2026-27/0001']);
      // Same day → the higher serial first, so the order is total.
      expect(given.first.serial, 'RF/2026-27/0001', reason: 'input mutated');
    });
  });

  group('SubscriptionCommands (S12.3, S12.4)', () {
    test(
      'F1-07-469 the shipped commands answer UNAVAILABLE — no payment channel '
      'is wired, and nothing pretends one is (PLAN desk item 11)',
      () async {
        const commands = UnwiredSubscriptionCommands();
        expect(await commands.cancelAtPeriodEnd(), isA<RkCommandUnavailable>());
        expect(await commands.retryPayment(), isA<RkCommandUnavailable>());
      },
    );

    test('F1-07-469 the fake records what was asked of it', () async {
      final fake = FakeSubscriptionCommands(cancel: const RkCommandFailed());
      expect(await fake.cancelAtPeriodEnd(), isA<RkCommandFailed>());
      expect(await fake.retryPayment(), isA<RkCommandDone>());
      expect(fake.cancels, 1);
      expect(fake.retries, 1);
    });
  });

  group('Dunning countdown (08 §3 🔒)', () {
    final periodEnd = DateTime(2026, 9, 1, 10);

    test('F1-07-471 the grace is 7 days from period_end and counts down in '
        'whole days', () {
      expect(rkDunningGrace, const Duration(days: 7));
      expect(rkDunningEndsAt(periodEnd), DateTime(2026, 9, 8, 10));
      expect(rkDunningDaysLeft(periodEnd: periodEnd, now: periodEnd), 7);
      expect(
        rkDunningDaysLeft(periodEnd: periodEnd, now: DateTime(2026, 9, 5, 10)),
        3,
      );
    });

    test(
      'F1-07-471 a part day is truncated — the screen can only understate the '
      'time left — and the count floors at zero',
      () {
        // 2 days and 23 hours left reads as 2, never 3.
        expect(
          rkDunningDaysLeft(
            periodEnd: periodEnd,
            now: DateTime(2026, 9, 5, 11),
          ),
          2,
        );
        expect(
          rkDunningDaysLeft(
            periodEnd: periodEnd,
            now: DateTime(2026, 9, 8, 9, 59),
          ),
          0,
        );
        expect(
          rkDunningDaysLeft(periodEnd: periodEnd, now: DateTime(2026, 10, 1)),
          0,
        );
      },
    );
  });
}
