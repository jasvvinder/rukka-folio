// Suite A / H2 — jointly-owned businesses (02 §7.1): partner accounts, ratio rounding,
// one-entry profit distribution, interest on capital, settlement capacity, drift.
import 'dart:math';

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('ratio rounding rule (02 §7.1 🔒)', () {
    test('floor each share; remainder to the largest ratio', () {
      // 100 paise split 50/30/20 → 50/30/20 exactly.
      expect(splitByRatio(const Paise(100), [50, 30, 20]).map((p) => p.raw), [
        50,
        30,
        20,
      ]);
      // 101 paise split 50/30/20 → floors 50/30/20, remainder 1 → largest ratio.
      expect(splitByRatio(const Paise(101), [50, 30, 20]).map((p) => p.raw), [
        51,
        30,
        20,
      ]);
      // 100 split 1/1/1 → 33/33/33 + 1 → tie broken by the earliest-created (index 0).
      expect(splitByRatio(const Paise(100), [1, 1, 1]).map((p) => p.raw), [
        34,
        33,
        33,
      ]);
      // Largest ratio not first: remainder goes to it, not to index 0.
      expect(splitByRatio(const Paise(101), [20, 50, 30]).map((p) => p.raw), [
        20,
        51,
        30,
      ]);
    });

    test('worked: ₹3,35,000 of costs shared equally in paise → 1,11,666.68 / 1,11,666.66 / 1,11,666.66', () {
      final shares = splitByRatio(rs(335000), [1, 1, 1]);
      expect(shares.map((p) => p.raw), [11166668, 11166666, 11166666]);
    });

    test('property: sums exactly, deterministic, remainder only ever on the largest ratio', () {
      final rng = Random(71);
      for (var i = 0; i < 2000; i++) {
        final n = 2 + rng.nextInt(5);
        final ratios = List.generate(n, (_) => 1 + rng.nextInt(99));
        final total = Paise(rng.nextInt(1 << 32) * 1024 + rng.nextInt(1024));
        final shares = splitByRatio(total, ratios);
        expect(Paise.sum(shares), total, reason: '$total / $ratios');
        expect(shares, splitByRatio(total, ratios));
        final sum = ratios.fold<int>(0, (a, b) => a + b);
        var largest = 0;
        for (var k = 1; k < n; k++) {
          if (ratios[k] > ratios[largest]) largest = k;
        }
        for (var k = 0; k < n; k++) {
          final exactFloor =
              (BigInt.from(total.raw) *
                      BigInt.from(ratios[k]) ~/
                      BigInt.from(sum))
                  .toInt();
          // Everyone gets their floor; only the largest ratio (earliest on ties) carries the remainder, < n paise.
          expect(
            shares[k].raw - exactFloor,
            k == largest ? inInclusiveRange(0, n - 1) : 0,
            reason: '$total / $ratios [$k]',
          );
        }
      }
    });

    test('rejects empty or non-positive ratios and negative totals', () {
      expect(() => splitByRatio(const Paise(1), []), throwsArgumentError);
      expect(() => splitByRatio(const Paise(1), [1, 0]), throwsArgumentError);
      expect(() => splitByRatio(const Paise(-1), [1, 1]), throwsArgumentError);
    });
  });

  group('Kaur Family Agriculture (worked example, 02 §7.1)', () {
    final book = TestBook('kaur', bookType: BookType.business);
    final bank = book.money('SBI Agri Current');
    final amrit = book.partner('Amrit Kaur');
    final sukhdev = book.partner('Sukhdev Singh');
    final harjit = book.partner('Harjit Kaur');
    final seed = book.expense('Seed & Fertiliser');
    final diesel = book.expense('Diesel & Machinery');
    final labour = book.expense('Labour');
    final repair = book.expense('Machinery Repair');
    final crop = book.income('Crop Sale');
    final milk = book.income('Milk Sale');
    final profitDistributed = book.profitDistributed();
    final opening = book.openingBalance();
    final chart = book.chart;

    final partners = [
      PartnerShare(account: amrit, ratio: 1),
      PartnerShare(account: sukhdev, ratio: 1),
      PartnerShare(account: harjit, ratio: 1),
    ];

    List<Entry> season() => [
      book.entry(
        Verbs.openingBalance(
          account: bank,
          balance: rs(50000),
          openingAccount: opening,
        ),
        kind: EntryKind.adjustment,
        date: d(2026, 4, 1),
      ),
      book.entry(
        Verbs.partnerPaidCost(
          partner: amrit,
          expense: seed,
          amount: rs(180000),
        ),
        kind: EntryKind.tookCredit,
        date: d(2026, 4, 8),
      ),
      book.entry(
        Verbs.partnerPaidCost(
          partner: sukhdev,
          expense: diesel,
          amount: rs(95000),
        ),
        kind: EntryKind.tookCredit,
        date: d(2026, 4, 12),
      ),
      book.entry(
        Verbs.partnerPaidCost(
          partner: harjit,
          expense: labour,
          amount: rs(60000),
        ),
        kind: EntryKind.tookCredit,
        date: d(2026, 4, 20),
      ),
      book.entry(
        Verbs.moneyOut(from: bank, forWhat: repair, amount: rs(41000)),
        kind: EntryKind.moneyOut,
        date: d(2026, 5, 6),
      ),
      book.entry(
        Verbs.moneyIn(into: bank, from: crop, amount: rs(850000)),
        kind: EntryKind.moneyIn,
        date: d(2026, 6, 18),
      ),
      book.entry(
        Verbs.moneyIn(into: bank, from: milk, amount: rs(120000)),
        kind: EntryKind.moneyIn,
        date: d(2026, 6, 30),
      ),
      book.entry(
        Verbs.partnerDrawing(partner: amrit, from: bank, amount: rs(50000)),
        kind: EntryKind.moneyOut,
        date: d(2026, 7, 10),
      ),
    ];

    test('three events, three postings: cost paid, drawing, profit share', () {
      expect(
        Verbs.partnerPaidCost(
          partner: amrit,
          expense: seed,
          amount: rs(180000),
        ),
        [dr(seed, rs(180000)), cr(amrit, rs(180000))],
      );
      expect(
        Verbs.partnerDrawing(partner: amrit, from: bank, amount: rs(50000)),
        [dr(amrit, rs(50000)), cr(bank, rs(50000))],
      );
      expect(
        () =>
            Verbs.partnerPaidCost(partner: seed, expense: seed, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.partnerDrawing(partner: amrit, from: seed, amount: rs(1)),
        throwsArgumentError,
      );
    });

    test('net profit for the period is computed, never typed', () {
      final s = project(season(), chart);
      expect(netProfit(s, chart), rs(594000));
    });

    test('distribution is one multi-line entry: Dr Profit Distributed · Cr each partner', () {
      final lines = Verbs.profitDistribution(
        profitDistributed: profitDistributed,
        partners: partners,
        netProfit: rs(594000),
      );
      expect(lines, [
        dr(profitDistributed, rs(594000)),
        Line(accountId: amrit.id, amount: -rs(198000), tag: 'share'),
        Line(accountId: sukhdev.id, amount: -rs(198000), tag: 'share'),
        Line(accountId: harjit.id, amount: -rs(198000), tag: 'share'),
      ]);
      final dist = book.entry(
        lines,
        kind: EntryKind.adjustment,
        date: d(2026, 7, 31),
      );
      final s = project([...season(), dist], chart);
      expect(s.balances[amrit.id], -rs(328000));
      expect(s.balances[sukhdev.id], -rs(293000));
      expect(s.balances[harjit.id], -rs(258000));
      expect(s.balances[bank.id], rs(929000));
      expect(trialBalance(s, chart).totalDr, rs(1899000));
      expect(s.balances.isBalanced, isTrue);
    });

    test('settlement capacity states in words whether the business could pay everyone out today', () {
      final dist = book.entry(
        Verbs.profitDistribution(
          profitDistributed: profitDistributed,
          partners: partners,
          netProfit: rs(594000),
        ),
        kind: EntryKind.adjustment,
        date: d(2026, 7, 31),
      );
      final s = project([...season(), dist], chart);
      final cap = settlementCapacity(s, chart);
      expect(cap.moneyTotal, rs(929000));
      expect(cap.partnerCreditTotal, rs(879000));
      expect(cap.canSettleAll, isTrue);
      expect(cap.shortBy, Paise.zero);
    });

    test('a partner who draws more than put in plus share carries a Dr balance — shown plainly', () {
      final over = book.entry(
        Verbs.partnerDrawing(partner: harjit, from: bank, amount: rs(70000)),
        kind: EntryKind.moneyOut,
        date: d(2026, 8, 1),
      );
      final s = project([...season(), over], chart);
      expect(s.balances[harjit.id], rs(10000));
      expect(s.balances[harjit.id].side, Side.dr);
      expect(
        placementOf(chart.account(harjit.id), s.balances[harjit.id]),
        Placement.asset,
      );
      final cap = settlementCapacity(s, chart);
      expect(
        cap.partnerCreditTotal,
        rs(225000),
        reason: 'debit partners are not owed anything',
      );
    });

    test(
      'drift card: a partner more than the margin above the group average',
      () {
        final dist = book.entry(
          Verbs.profitDistribution(
            profitDistributed: profitDistributed,
            partners: partners,
            netProfit: rs(594000),
          ),
          kind: EntryKind.adjustment,
          date: d(2026, 7, 31),
        );
        final s = project([...season(), dist], chart);
        // Balances 3,28,000 / 2,93,000 / 2,58,000; average 2,93,000.
        final drift = partnerDrift(s, chart, margin: rs(30000));
        expect(drift.single.accountId, amrit.id);
        expect(drift.single.aboveAverage, rs(35000));
        expect(partnerDrift(s, chart, margin: rs(40000)), isEmpty);
      },
    );

    group('interest on capital (02 §7.1, 8% for the 122-day season)', () {
      final from = d(2026, 4, 1);
      final to = d(2026, 7, 31);

      test(
        'average-daily-balance interest per partner, half-up to the paisa',
        () {
          final s = project(season(), chart);
          final interest = interestOnCapital(
            s,
            chart,
            partners: partners,
            from: from,
            to: to,
            rateBasisPoints: 800,
          );
          expect(interest[amrit.id]!.raw, 429589); // ₹4,295.89
          expect(interest[sukhdev.id]!.raw, 231123); // ₹2,311.23
          expect(interest[harjit.id]!.raw, 135452); // ₹1,354.52
        },
      );

      test('interest is credited first, tagged, then the remainder splits by ratio', () {
        final s = project(season(), chart);
        final interest = interestOnCapital(
          s,
          chart,
          partners: partners,
          from: from,
          to: to,
          rateBasisPoints: 800,
        );
        final lines = Verbs.profitDistribution(
          profitDistributed: profitDistributed,
          partners: partners,
          netProfit: rs(594000),
          interest: interest,
        );
        expect(lines.first, dr(profitDistributed, rs(594000)));
        expect(lines.where((l) => l.tag == 'interest').length, 3);
        expect(lines.where((l) => l.tag == 'share').length, 3);
        expect(Paise.sum(lines.map((l) => l.amount)), Paise.zero);
        final remaining = rs(594000) - Paise.sum(interest.values);
        expect(remaining.raw, 59400000 - 796164);
        final shares = lines
            .where((l) => l.tag == 'share')
            .map((l) => -l.amount)
            .toList();
        expect(shares, splitByRatio(remaining, [1, 1, 1]));
        // Never an expense account: only Profit Distributed is debited.
        expect(lines.where((l) => l.amount.isDebit).map((l) => l.accountId), [
          profitDistributed.id,
        ]);
      });

      test('debit balances are charged at the same rate by default; not when the setting says otherwise', () {
        final over = book.entry(
          Verbs.partnerDrawing(partner: harjit, from: bank, amount: rs(70000)),
          kind: EntryKind.moneyOut,
          date: d(2026, 4, 1),
        );
        // Harjit: Dr 70,000 from 1 Apr (19 days), then Cr 60,000 from 20 Apr leaves Dr 10,000 for 103 days.
        final s = project([...season(), over], chart);
        final charged = interestOnCapital(
          s,
          chart,
          partners: partners,
          from: from,
          to: to,
          rateBasisPoints: 800,
        );
        // Σ signed Cr-balance days = −(70,000×19 + 10,000×103) = −2,360,000 rupee-days × 8% ÷ 365 → −₹517.26.
        expect(charged[harjit.id]!.raw, -51726);
        final spared = interestOnCapital(
          s,
          chart,
          partners: partners,
          from: from,
          to: to,
          rateBasisPoints: 800,
          chargeDebitBalances: false,
        );
        expect(spared[harjit.id], Paise.zero);
      });
    });
  });

  group('half-up rounding helper', () {
    test('rounds .5 up, exact integers unchanged, negatives toward +∞', () {
      expect(roundHalfUp(numerator: 7, denominator: 2), 4);
      expect(roundHalfUp(numerator: 5, denominator: 2), 3);
      expect(roundHalfUp(numerator: 4, denominator: 2), 2);
      expect(roundHalfUp(numerator: -7, denominator: 2), -3);
      expect(roundHalfUp(numerator: -5, denominator: 2), -2);
      expect(roundHalfUp(numerator: 1, denominator: 3), 0);
      expect(roundHalfUp(numerator: 2, denominator: 3), 1);
    });
  });
}
