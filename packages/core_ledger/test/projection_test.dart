// Suite A — post-then-review (02 §3), corrections (§5), periods (§8), balances (§9),
// hostile-client quarantine (02 preamble, §11), determinism (03 §3.3, §7).
import 'dart:math';

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestBook book;
  late Account cash, bank, kirana, salary, verma, opening, advRamesh;
  late Chart chart;

  setUp(() {
    book = TestBook('fam');
    cash = book.cash('Cash');
    bank = book.money('Bank');
    kirana = book.expense('Kirana');
    salary = book.income('Salary');
    verma = book.party('Verma Dairy');
    opening = book.openingBalance();
    book.adjustments();
    advRamesh = book.advance('ramesh');
    chart = book.chart;
  });

  group('balances (02 §9)', () {
    test('balance = Σ signed lines of posted entries; placement by sign', () {
      final s = project([
        book.entry(
          Verbs.openingBalance(
            account: cash,
            balance: rs(4000),
            openingAccount: opening,
          ),
          kind: EntryKind.adjustment,
        ),
        book.entry(
          Verbs.moneyIn(into: cash, from: salary, amount: rs(1000)),
          kind: EntryKind.moneyIn,
        ),
        book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(300)),
          kind: EntryKind.moneyOut,
        ),
      ], chart);
      expect(s.balances[cash.id], rs(4700));
      expect(s.balances[opening.id], -rs(4000));
      expect(s.balances[salary.id], -rs(1000));
      expect(s.balances[kirana.id], rs(300));
      expect(s.balances.totalDebits, rs(5000));
      expect(s.balances.totalCredits, rs(5000));
      expect(s.balances.isBalanced, isTrue);
    });

    test('trial balance omits zero rows, totals agree, keeps chart order', () {
      final s = project([
        book.entry(
          Verbs.openingBalance(
            account: bank,
            balance: rs(500),
            openingAccount: opening,
          ),
          kind: EntryKind.adjustment,
        ),
        book.entry(
          Verbs.transfer(from: bank, to: cash, amount: rs(500)),
          kind: EntryKind.transfer,
        ),
      ], chart);
      final tb = trialBalance(s, chart);
      expect(tb.rows.map((r) => r.accountId), [cash.id, opening.id]);
      expect(tb.rows.first.dr, rs(500));
      expect(tb.rows.first.cr, isNull);
      expect(tb.totalDr, rs(500));
      expect(tb.totalCr, rs(500));
      expect(tb.isBalanced, isTrue);
    });

    test(
      'statement rows carry running balance and side; b/f from opening vector',
      () {
        final s = project(
          [
            book.entry(
              Verbs.moneyIn(into: cash, from: salary, amount: rs(100)),
              kind: EntryKind.moneyIn,
              date: d(2026, 5, 2),
            ),
            book.entry(
              Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(150)),
              kind: EntryKind.moneyOut,
              date: d(2026, 5, 3),
            ),
          ],
          chart,
          opening: BalanceVector({cash.id: rs(20), opening.id: -rs(20)}),
        );
        final rows = statement(s, cash.id);
        expect(rows.map((r) => r.running.raw), [12000, -3000]);
        expect(rows.map((r) => r.side), [Side.dr, Side.cr]);
        expect(rows.first.dr, rs(100));
        expect(rows.first.cr, isNull);
        expect(rows.last.cr, rs(150));
        expect(
          statement(s, cash.id, from: d(2026, 5, 3)).single.entryId,
          rows.last.entryId,
        );
      },
    );
  });

  group('post-then-review (02 §3)', () {
    test('over-limit entry posts instantly with an open flag; approve clears it, balances untouched', () {
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(7000)),
        kind: EntryKind.moneyOut,
        reviewRequired: true,
        reviewLimit: rs(5000),
        reviewApprover: 'head',
      );
      var s = project([e], chart);
      expect(s.balances[cash.id], -rs(7000));
      expect(s.entries[e.id]!.status, EffectiveStatus.posted);
      expect(s.entries[e.id]!.reviewState, ReviewState.open);
      expect(s.openReviewFlags.map((p) => p.entry.id), [e.id]);

      final approve = ApprovalDecision(
        id: 'a1',
        bookId: 'fam',
        entryId: e.id,
        decision: Decision.approve,
        byUser: 'head',
        hlc: book.nextHlc(),
      );
      s = project([e, approve], chart);
      expect(s.entries[e.id]!.reviewState, ReviewState.approved);
      expect(s.balances[cash.id], -rs(7000));
      expect(s.openReviewFlags, isEmpty);
    });

    test('reject: auto-reversal posts with the reason; both stay in history; balances return', () {
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(7000)),
        kind: EntryKind.moneyOut,
        reviewRequired: true,
        reviewLimit: rs(5000),
        reviewApprover: 'head',
      );
      final reject = ApprovalDecision(
        id: 'r1',
        bookId: 'fam',
        entryId: e.id,
        decision: Decision.reject,
        reason: 'duplicate',
        byUser: 'head',
        hlc: book.nextHlc(),
      );
      final reversal = e.reversal(
        newId: 'rev1',
        hlc: book.nextHlc(),
        accountingDate: d(2026, 5, 12),
        createdByUser: 'head',
        createdByDevice: 'd9',
        note: 'duplicate',
      );
      final s = project([e, reject, reversal], chart);
      expect(s.entries[e.id]!.reviewState, ReviewState.rejected);
      expect(s.entries[e.id]!.status, EffectiveStatus.voided);
      expect(s.entries[e.id]!.reversedBy, 'rev1');
      expect(s.entries['rev1']!.status, EffectiveStatus.posted);
      expect(s.balances[cash.id], Paise.zero);
      expect(s.balances[kirana.id], Paise.zero);
      expect(reversal.refs.reverses, e.id);
      expect(reversal.kind, e.kind);
    });

    test('nobody clears their own flag (02 §7.2 item 1)', () {
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(7000)),
        kind: EntryKind.moneyOut,
        reviewRequired: true,
        reviewLimit: rs(5000),
        createdByUser: 'admin',
      );
      final self = ApprovalDecision(
        id: 'a1',
        bookId: 'fam',
        entryId: e.id,
        decision: Decision.approve,
        byUser: 'admin',
        hlc: book.nextHlc(),
      );
      final s = project([e, self], chart);
      expect(s.entries[e.id]!.reviewState, ReviewState.open);
      expect(s.quarantined.single.violations.map((v) => v.kind), [
        ViolationKind.selfApproval,
      ]);
    });

    test('last decision in (hlc, id) order wins', () {
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(7000)),
        kind: EntryKind.moneyOut,
        reviewRequired: true,
        reviewLimit: rs(5000),
      );
      final a = ApprovalDecision(
        id: 'a',
        bookId: 'fam',
        entryId: e.id,
        decision: Decision.approve,
        byUser: 'h',
        hlc: const Hlc(5000),
      );
      final r = ApprovalDecision(
        id: 'r',
        bookId: 'fam',
        entryId: e.id,
        decision: Decision.reject,
        byUser: 'h',
        hlc: const Hlc(5001),
      );
      expect(
        project([e, r, a], chart).entries[e.id]!.reviewState,
        ReviewState.rejected,
      );
    });
  });

  group('corrections (02 §5)', () {
    test('amend in an open period: latest amendment shows, original superseded, history kept', () {
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(250)),
        kind: EntryKind.moneyOut,
        id: 'orig',
      );
      final a1 = e.amendWith(
        newId: 'a1',
        hlc: book.nextHlc(),
        lines: Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(205)),
      );
      final s = project([e, a1], chart);
      expect(s.entries['orig']!.status, EffectiveStatus.superseded);
      expect(s.entries['orig']!.supersededBy, 'a1');
      expect(s.entries['a1']!.status, EffectiveStatus.posted);
      expect(s.balances[cash.id], -rs(205));
      expect(a1.refs.amends, 'orig');
      expect(a1.kind, e.kind);
      expect(s.headOf('orig'), 'a1');
    });

    test('amend chains are linear: only the head may be amended', () {
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(250)),
        kind: EntryKind.moneyOut,
        id: 'orig',
      );
      final a1 = e.amendWith(newId: 'a1', hlc: book.nextHlc(), note: 'first');
      final a2 = e.amendWith(
        newId: 'a2',
        hlc: book.nextHlc(),
        note: 'second, of the wrong target',
      );
      final s = project([e, a1, a2], chart);
      expect(s.quarantined.single.eventId, 'a2');
      expect(s.quarantined.single.violations.map((v) => v.kind), [
        ViolationKind.amendNotHead,
      ]);
      expect(s.balances[cash.id], -rs(250));
    });

    test(
      'amendment must keep the kind; amending a missing target is quarantined',
      () {
        final e = book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(250)),
          kind: EntryKind.moneyOut,
          id: 'orig',
        );
        final wrongKind = book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(1)),
          kind: EntryKind.transfer,
          refs: const EntryRefs(amends: 'orig'),
        );
        final orphan = book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(1)),
          kind: EntryKind.moneyOut,
          refs: const EntryRefs(amends: 'ghost'),
        );
        final s = project([e, wrongKind, orphan], chart);
        expect(
          s.quarantined.map((q) => q.violations.single.kind),
          containsAll([
            ViolationKind.amendKindChanged,
            ViolationKind.amendTargetMissing,
          ]),
        );
      },
    );

    test(
      'reversal must mirror the target; a second reversal is quarantined',
      () {
        final e = book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(250)),
          kind: EntryKind.moneyOut,
          id: 'orig',
        );
        final fake = book.entry(
          Verbs.moneyIn(into: cash, from: salary, amount: rs(250)),
          kind: EntryKind.moneyOut,
          refs: const EntryRefs(reverses: 'orig'),
        );
        final good = e.reversal(
          newId: 'rev',
          hlc: book.nextHlc(),
          accountingDate: d(2026, 5, 11),
          createdByUser: 'u1',
          createdByDevice: 'd1',
        );
        final again = e.reversal(
          newId: 'rev2',
          hlc: book.nextHlc(),
          accountingDate: d(2026, 5, 11),
          createdByUser: 'u1',
          createdByDevice: 'd1',
        );
        final s = project([e, fake, good, again], chart);
        expect(s.quarantined.map((q) => q.eventId), [fake.id, 'rev2']);
        expect(
          s.quarantined.first.violations.single.kind,
          ViolationKind.reversalNotMirror,
        );
        expect(
          s.quarantined.last.violations.single.kind,
          ViolationKind.alreadyReversed,
        );
        expect(s.entries['orig']!.status, EffectiveStatus.voided);
        expect(s.balances[cash.id], Paise.zero);
      },
    );

    test('reversing the head of an amend chain voids the whole chain', () {
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(250)),
        kind: EntryKind.moneyOut,
        id: 'orig',
      );
      final a1 = e.amendWith(
        newId: 'a1',
        hlc: book.nextHlc(),
        lines: Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(300)),
      );
      final rev = a1.reversal(
        newId: 'rev',
        hlc: book.nextHlc(),
        accountingDate: d(2026, 5, 11),
        createdByUser: 'u1',
        createdByDevice: 'd1',
      );
      final s = project([e, a1, rev], chart);
      expect(s.entries['a1']!.status, EffectiveStatus.voided);
      expect(s.entries['orig']!.status, EffectiveStatus.superseded);
      expect(s.balances[cash.id], Paise.zero);
    });
  });

  group('periods and locks (02 §8)', () {
    test(
      'an entry dated in P is valid only if its HLC precedes the lock of P',
      () {
        final lock = PeriodLock(
          id: 'L',
          bookId: 'fam',
          period: YearMonth(2026, 5),
          byUser: 'admin',
          hlc: const Hlc(2000),
        );
        final before = book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(10)),
          kind: EntryKind.moneyOut,
          hlc: const Hlc(1999),
          date: d(2026, 5, 5),
        );
        final after = book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(20)),
          kind: EntryKind.moneyOut,
          hlc: const Hlc(2001),
          date: d(2026, 5, 6),
        );
        final open = book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(30)),
          kind: EntryKind.moneyOut,
          hlc: const Hlc(2002),
          date: d(2026, 6, 1),
        );
        final s = project([before, lock, after, open], chart);
        expect(s.entries[before.id]!.status, EffectiveStatus.posted);
        expect(s.quarantined.single.eventId, after.id);
        expect(
          s.quarantined.single.violations.single.kind,
          ViolationKind.periodLocked,
        );
        expect(s.balances[cash.id], -rs(40));
        expect(
          s.periods.statusAt(YearMonth(2026, 5), const Hlc(3000)),
          PeriodStatus.locked,
        );
        expect(
          s.periods.statusAt(YearMonth(2026, 6), const Hlc(3000)),
          PeriodStatus.open,
        );
      },
    );

    test('re-open (logged) makes the period accept entries again', () {
      final lock = PeriodLock(
        id: 'L',
        bookId: 'fam',
        period: YearMonth(2026, 5),
        byUser: 'admin',
        hlc: const Hlc(2000),
      );
      final unlock = PeriodUnlock(
        id: 'U',
        bookId: 'fam',
        period: YearMonth(2026, 5),
        byUser: 'admin',
        reason: 'late bill',
        hlc: const Hlc(2005),
      );
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(20)),
        kind: EntryKind.moneyOut,
        hlc: const Hlc(2010),
        date: d(2026, 5, 6),
      );
      final s = project([lock, unlock, e], chart);
      expect(s.quarantined, isEmpty);
      expect(
        s.periods.statusAt(YearMonth(2026, 5), const Hlc(2010)),
        PeriodStatus.open,
      );
      expect(
        s.periods.statusAt(YearMonth(2026, 5), const Hlc(2001)),
        PeriodStatus.locked,
      );
    });

    test('amendment in a locked period is forbidden; reversal dated in the open period is the path', () {
      final e = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(250)),
        kind: EntryKind.moneyOut,
        id: 'orig',
        hlc: const Hlc(1000),
        date: d(2026, 5, 5),
      );
      final lock = PeriodLock(
        id: 'L',
        bookId: 'fam',
        period: YearMonth(2026, 5),
        byUser: 'admin',
        hlc: const Hlc(2000),
      );
      final amend = e.amendWith(
        newId: 'a1',
        hlc: const Hlc(2001),
        note: 'too late',
      );
      final rev = e.reversal(
        newId: 'rev',
        hlc: const Hlc(2002),
        accountingDate: d(2026, 6, 1),
        createdByUser: 'u1',
        createdByDevice: 'd1',
      );
      final s = project([e, lock, amend, rev], chart);
      expect(s.quarantined.single.eventId, 'a1');
      expect(
        s.quarantined.single.violations.map((v) => v.kind),
        contains(ViolationKind.amendInLockedPeriod),
      );
      expect(s.entries['orig']!.status, EffectiveStatus.voided);
      expect(s.balances[cash.id], Paise.zero);
    });

    test('late arrival: valid by the rule, held in the tray, absent from totals until re-dated', () {
      final lock = PeriodLock(
        id: 'L',
        bookId: 'fam',
        period: YearMonth(2026, 5),
        byUser: 'admin',
        hlc: const Hlc(2000),
      );
      final late = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(10)),
        kind: EntryKind.moneyOut,
        hlc: const Hlc(1500),
        date: d(2026, 5, 5),
      );
      expect(isLateArrival(late, lock, arrivedAfterLock: true), isTrue);
      expect(isLateArrival(late, lock, arrivedAfterLock: false), isFalse);
      final held = project([late, lock], chart, heldInTray: {late.id});
      expect(held.balances[cash.id], Paise.zero);
      expect(held.entries[late.id]!.status, EffectiveStatus.held);
      // Re-dated into the open period by the closer: an amendment dated June.
      final redated = late.amendWith(
        newId: 'rd',
        hlc: const Hlc(2100),
        accountingDate: d(2026, 6, 1),
      );
      final s = project([late, lock, redated], chart);
      expect(s.balances[cash.id], -rs(10));
      expect(s.entries[late.id]!.status, EffectiveStatus.superseded);
    });

    test(
      'lock is routine; the close envelope carries declared balances + vector',
      () {
        final e = book.entry(
          Verbs.openingBalance(
            account: cash,
            balance: rs(100),
            openingAccount: opening,
          ),
          kind: EntryKind.adjustment,
          hlc: const Hlc(1),
          date: d(2026, 5, 1),
        );
        final s0 = project([e], chart);
        final lock = PeriodLock(
          id: 'L',
          bookId: 'fam',
          period: YearMonth(2026, 5),
          byUser: 'admin',
          hlc: const Hlc(2),
          declaredBalances: {cash.id: rs(100)},
          vectorCanonical: s0.balances.canonical(),
        );
        final s = project([e, lock], chart);
        expect(
          s.periods.lockFor(YearMonth(2026, 5))!.vectorCanonical,
          s.balances.canonical(),
        );
      },
    );
  });

  group('financial year close (02 §8.1)', () {
    test('closing vector becomes the certified opening of the next FY; rebuild from vector = full replay', () {
      final fy = FinancialYear.of(d(2026, 4, 1));
      final events = <LedgerEvent>[
        book.entry(
          Verbs.openingBalance(
            account: cash,
            balance: rs(4000),
            openingAccount: opening,
          ),
          kind: EntryKind.adjustment,
          hlc: const Hlc(1),
          date: d(2026, 4, 1),
        ),
        book.entry(
          Verbs.moneyIn(into: cash, from: salary, amount: rs(1000)),
          kind: EntryKind.moneyIn,
          hlc: const Hlc(2),
          date: d(2026, 9, 1),
        ),
        for (final m in fy.months)
          PeriodLock(
            id: 'L${m.year}${m.month}',
            bookId: 'fam',
            period: m,
            byUser: 'admin',
            hlc: Hlc(100 + fy.months.indexOf(m)),
          ),
      ];
      final closingVector = project(events, chart).balances;
      final close = YearClose(
        id: 'Y',
        bookId: 'fam',
        financialYear: fy,
        vector: closingVector,
        byUser: 'admin',
        hlc: const Hlc(200),
      );
      final next = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(500)),
        kind: EntryKind.moneyOut,
        hlc: const Hlc(300),
        date: d(2027, 4, 2),
      );

      final full = project([...events, close, next], chart);
      expect(full.years[fy]!.status, YearStatus.closed);
      expect(full.years[fy]!.certifiedVector, closingVector);

      final fromVector = project([next], chart, opening: closingVector);
      expect(fromVector.balances, full.balances);
      expect(fromVector.balances.canonical(), full.balances.canonical());
      expect(full.balances[cash.id], rs(4500));
    });

    test('year close is blocked while any month is open, a flag is open, or an advance is pending', () {
      final fy = FinancialYear.of(d(2026, 4, 1));
      final s = project([
        book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(7000)),
          kind: EntryKind.moneyOut,
          reviewRequired: true,
          reviewLimit: rs(5000),
          date: d(2026, 5, 1),
        ),
        book.entry(
          Verbs.advanceRequest(
            advance: advRamesh,
            from: cash,
            amount: rs(20000),
          ),
          kind: EntryKind.moneyOut,
          status: EntryStatus.pending,
          date: d(2026, 5, 2),
        ),
      ], chart);
      final blockers = yearClosePreconditions(s, chart, fy);
      expect(
        blockers.map((b) => b.kind),
        containsAll([
          CloseBlocker.monthOpen,
          CloseBlocker.reviewFlagOpen,
          CloseBlocker.advancePending,
        ]),
      );
    });

    test('unlocking a month of a closed year voids that certificate and every later one', () {
      final fy26 = FinancialYear.of(d(2026, 4, 1));
      final fy27 = FinancialYear.of(d(2027, 4, 1));
      final v = BalanceVector({});
      final s = project([
        YearClose(
          id: 'Y26',
          bookId: 'fam',
          financialYear: fy26,
          vector: v,
          byUser: 'a',
          hlc: const Hlc(10),
        ),
        YearClose(
          id: 'Y27',
          bookId: 'fam',
          financialYear: fy27,
          vector: v,
          byUser: 'a',
          hlc: const Hlc(20),
        ),
        PeriodUnlock(
          id: 'U',
          bookId: 'fam',
          period: YearMonth(2026, 7),
          byUser: 'a',
          reason: 'fix',
          hlc: const Hlc(30),
        ),
      ], chart);
      expect(s.years[fy26]!.status, YearStatus.uncertified);
      expect(s.years[fy27]!.status, YearStatus.uncertified);
    });
  });

  group('hostile client → quarantine, never summed (02 preamble, §11)', () {
    test(
      'lines summing to −100 are quarantined and raise a security event',
      () {
        final bad = book.entry([dr(kirana, rs(1)), cr(cash, rs(2))]);
        final s = project([bad], chart);
        expect(s.quarantined.single.eventId, bad.id);
        expect(s.quarantined.single.violations.map((v) => v.kind), [
          ViolationKind.linesUnbalanced,
        ]);
        expect(s.balances[cash.id], Paise.zero);
        expect(s.entries.containsKey(bad.id), isFalse);
      },
    );

    test('decisions for unknown entries are quarantined', () {
      final s = project([
        ApprovalDecision(
          id: 'a',
          bookId: 'fam',
          entryId: 'ghost',
          decision: Decision.approve,
          byUser: 'h',
          hlc: const Hlc(1),
        ),
      ], chart);
      expect(
        s.quarantined.single.violations.single.kind,
        ViolationKind.decisionTargetMissing,
      );
    });
  });

  group('determinism (03 §3.3, 02 §11 close step 4)', () {
    test('any input order yields identical balances and canonical vector', () {
      final events = <LedgerEvent>[];
      final rng = Random(7);
      for (var i = 0; i < 200; i++) {
        final amount = Paise(1 + rng.nextInt(100000));
        events.add(switch (i % 3) {
          0 => book.entry(
            Verbs.moneyIn(into: cash, from: salary, amount: amount),
            kind: EntryKind.moneyIn,
          ),
          1 => book.entry(
            Verbs.moneyOut(from: cash, forWhat: kirana, amount: amount),
            kind: EntryKind.moneyOut,
          ),
          _ => book.entry(
            Verbs.tookCredit(fromWhom: verma, took: kirana, amount: amount),
            kind: EntryKind.tookCredit,
          ),
        });
      }
      final a = project(events, chart);
      final shuffled = [...events]..shuffle(rng);
      final b = project(shuffled, chart);
      expect(b.balances, a.balances);
      expect(b.balances.canonical(), a.balances.canonical());
      expect(a.balances.canonical(), startsWith('${cash.id}\t'));
      expect(a.balances.isBalanced, isTrue);
    });
  });
}
