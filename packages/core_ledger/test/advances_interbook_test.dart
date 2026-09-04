// Suite A — advances (02 §7) and inter-book movement (02 §6).
import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('advances (02 §7)', () {
    late TestBook kirana;
    late Account bank, cash, repair, advRamesh, adjustments;
    late Chart chart;

    setUp(() {
      kirana = TestBook('kirana', bookType: BookType.business);
      bank = kirana.money('Kirana Bank');
      cash = kirana.cash('Kirana Cash');
      repair = kirana.expense('Shop Repair');
      advRamesh = kirana.advance('ramesh');
      adjustments = kirana.adjustments();
      chart = kirana.chart;
    });

    test('a request is pending and moves nothing until approved; approval moves the money', () {
      final req = kirana.entry(
        Verbs.advanceRequest(advance: advRamesh, from: bank, amount: rs(20000)),
        kind: EntryKind.moneyOut,
        status: EntryStatus.pending,
        createdByUser: 'ramesh',
        date: d(2026, 8, 9),
      );
      expect(req.lines, [dr(advRamesh, rs(20000)), cr(bank, rs(20000))]);
      var s = project([req], chart);
      expect(s.entries[req.id]!.status, EffectiveStatus.pending);
      expect(s.balances[advRamesh.id], Paise.zero);
      expect(s.balances[bank.id], Paise.zero);
      expect(s.pendingAdvances.single.entry.id, req.id);
      expect(s.openReviewFlags, isEmpty, reason: 'two distinct queues');

      final approve = ApprovalDecision(
        id: 'ok',
        bookId: 'kirana',
        entryId: req.id,
        decision: Decision.approve,
        byUser: 'karta',
        hlc: kirana.nextHlc(),
      );
      s = project([req, approve], chart);
      expect(s.entries[req.id]!.status, EffectiveStatus.posted);
      expect(s.balances[advRamesh.id], rs(20000));
      expect(s.balances[bank.id], -rs(20000));
      expect(s.pendingAdvances, isEmpty);
    });

    test('a rejected request never counts', () {
      final req = kirana.entry(
        Verbs.advanceRequest(advance: advRamesh, from: bank, amount: rs(20000)),
        kind: EntryKind.moneyOut,
        status: EntryStatus.pending,
        createdByUser: 'ramesh',
      );
      final reject = ApprovalDecision(
        id: 'no',
        bookId: 'kirana',
        entryId: req.id,
        decision: Decision.reject,
        reason: 'no',
        byUser: 'karta',
        hlc: kirana.nextHlc(),
      );
      final s = project([req, reject], chart);
      expect(s.entries[req.id]!.status, EffectiveStatus.rejected);
      expect(s.balances[advRamesh.id], Paise.zero);
    });

    test('₹20,000 advance, ₹17,400 settled, ₹2,600 returned → balance zero, gone from ageing (02 §11)', () {
      final req = kirana.entry(
        Verbs.advanceRequest(advance: advRamesh, from: bank, amount: rs(20000)),
        kind: EntryKind.moneyOut,
        status: EntryStatus.pending,
        createdByUser: 'ramesh',
        date: d(2026, 8, 9),
      );
      final approve = ApprovalDecision(
        id: 'ok',
        bookId: 'kirana',
        entryId: req.id,
        decision: Decision.approve,
        byUser: 'karta',
        hlc: kirana.nextHlc(),
      );
      final spend = kirana.entry(
        Verbs.advanceSpend(
          advance: advRamesh,
          forWhat: repair,
          amount: rs(17400),
        ),
        kind: EntryKind.moneyOut,
        date: d(2026, 8, 17),
      );
      expect(spend.lines, [dr(repair, rs(17400)), cr(advRamesh, rs(17400))]);

      var s = project([req, approve, spend], chart);
      final open = openAdvances(s, chart, asOf: d(2026, 8, 20));
      expect(open.single.accountId, advRamesh.id);
      expect(open.single.balance, rs(2600));
      expect(open.single.oldestUnsettled, d(2026, 8, 9));
      expect(open.single.ageDays, 11);

      final ret = kirana.entry(
        Verbs.advanceReturn(advance: advRamesh, into: cash, amount: rs(2600)),
        kind: EntryKind.moneyIn,
        date: d(2026, 8, 21),
      );
      expect(ret.lines, [dr(cash, rs(2600)), cr(advRamesh, rs(2600))]);
      s = project([req, approve, spend, ret], chart);
      expect(s.balances[advRamesh.id], Paise.zero);
      expect(openAdvances(s, chart, asOf: d(2026, 8, 31)), isEmpty);
    });

    test(
      'ageing is FIFO: a second advance keeps the oldest unsettled date',
      () {
        final a1 = kirana.entry(
          Verbs.advanceRequest(
            advance: advRamesh,
            from: bank,
            amount: rs(1000),
          ),
          kind: EntryKind.moneyOut,
          date: d(2026, 8, 1),
        );
        final a2 = kirana.entry(
          Verbs.advanceRequest(
            advance: advRamesh,
            from: bank,
            amount: rs(1000),
          ),
          kind: EntryKind.moneyOut,
          date: d(2026, 8, 10),
        );
        final part = kirana.entry(
          Verbs.advanceSpend(
            advance: advRamesh,
            forWhat: repair,
            amount: rs(700),
          ),
          kind: EntryKind.moneyOut,
          date: d(2026, 8, 12),
        );
        var s = project([a1, a2, part], chart);
        expect(
          openAdvances(s, chart, asOf: d(2026, 8, 20)).single.oldestUnsettled,
          d(2026, 8, 1),
        );
        final more = kirana.entry(
          Verbs.advanceSpend(
            advance: advRamesh,
            forWhat: repair,
            amount: rs(400),
          ),
          kind: EntryKind.moneyOut,
          date: d(2026, 8, 13),
        );
        s = project([a1, a2, part, more], chart);
        expect(
          openAdvances(s, chart, asOf: d(2026, 8, 20)).single.oldestUnsettled,
          d(2026, 8, 10),
        );
      },
    );

    test('write-off is a guided adjustment against Adjustments', () {
      expect(
        Verbs.writeOff(
          account: advRamesh,
          balance: rs(300),
          adjustmentsAccount: adjustments,
        ),
        [dr(adjustments, rs(300)), cr(advRamesh, rs(300))],
      );
    });

    test('class checks', () {
      expect(
        () => Verbs.advanceRequest(advance: repair, from: bank, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.advanceRequest(
          advance: advRamesh,
          from: repair,
          amount: rs(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => Verbs.advanceSpend(
          advance: advRamesh,
          forWhat: bank,
          amount: rs(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => Verbs.advanceReturn(
          advance: advRamesh,
          into: repair,
          amount: rs(1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('inter-book movement (02 §6)', () {
    late TestBook biz, fam;
    late Account bizBank, bizDueFam, famBank, famDueBiz, famExpense;

    setUp(() {
      biz = TestBook('biz', bookType: BookType.business);
      bizBank = biz.money('Bank');
      bizDueFam = biz.dueToFrom('fam');
      fam = TestBook('fam');
      famBank = fam.money('Bank');
      famDueBiz = fam.dueToFrom('biz');
      famExpense = fam.expense('House Repair');
    });

    test('one action → two envelopes sharing transfer_group, one per book', () {
      final pair = InterBook.transfer(
        amount: rs(50000),
        accountingDate: d(2026, 8, 5),
        from: (money: bizBank, dueToFrom: bizDueFam),
        to: (money: famBank, dueToFrom: famDueBiz),
        transferGroup: 'g1',
        ids: (from: 'k01', to: 'j01'),
        hlcs: (from: const Hlc(10), to: const Hlc(11)),
        createdByUser: 'karta',
        createdByDevice: 'd1',
        reviewRequiredIn: (from: false, to: true),
        reviewLimitPaise: (from: null, to: rs(5000)),
      );
      expect(pair.from.lines, [
        dr(bizDueFam, rs(50000)),
        cr(bizBank, rs(50000)),
      ]);
      expect(pair.to.lines, [dr(famBank, rs(50000)), cr(famDueBiz, rs(50000))]);
      expect(pair.from.refs.transferGroup, 'g1');
      expect(pair.to.refs.transferGroup, 'g1');
      expect(pair.from.kind, EntryKind.transfer);
      expect(pair.to.reviewRequired, isTrue);
      expect(pair.from.bookId, 'biz');
      expect(pair.to.bookId, 'fam');
    });

    test('both halves post at once; the flagged half shows in transit; reconciliation nets to zero', () {
      final pair = InterBook.transfer(
        amount: rs(50000),
        accountingDate: d(2026, 8, 5),
        from: (money: bizBank, dueToFrom: bizDueFam),
        to: (money: famBank, dueToFrom: famDueBiz),
        transferGroup: 'g1',
        ids: (from: 'k01', to: 'j01'),
        hlcs: (from: const Hlc(10), to: const Hlc(11)),
        createdByUser: 'karta',
        createdByDevice: 'd1',
        reviewRequiredIn: (from: false, to: true),
        reviewLimitPaise: (from: null, to: rs(5000)),
      );
      final sBiz = project([pair.from], biz.chart);
      final sFam = project([pair.to], fam.chart);
      expect(sBiz.balances[bizBank.id], -rs(50000));
      expect(sFam.balances[famBank.id], rs(50000));
      expect(
        InterBook.isInTransit(sBiz.entries['k01']!, sFam.entries['j01']!),
        isTrue,
      );

      final recon = InterBook.reconcile([
        InterBookPair(
          a: sBiz,
          accountA: bizDueFam.id,
          b: sFam,
          accountB: famDueBiz.id,
        ),
      ]);
      expect(recon.single.net, Paise.zero);
      expect(recon.single.isBalanced, isTrue);

      final approve = ApprovalDecision(
        id: 'ok',
        bookId: 'fam',
        entryId: 'j01',
        decision: Decision.approve,
        byUser: 'head',
        hlc: const Hlc(12),
      );
      final sFam2 = project([pair.to, approve], fam.chart);
      expect(
        InterBook.isInTransit(sBiz.entries['k01']!, sFam2.entries['j01']!),
        isFalse,
      );
    });

    test('pocket expense: personal book Dr Due to/from Family · Cr Cash; family Dr Expense · Cr Due to/from Personal', () {
      final personal = TestBook('amit');
      final amitCash = personal.cash('Cash');
      final amitDueFam = personal.dueToFrom('fam');
      final famDueAmit = fam.dueToFrom('amit');
      final pair = InterBook.pocketExpense(
        amount: rs(2300),
        accountingDate: d(2026, 8, 7),
        payer: (money: amitCash, dueToFrom: amitDueFam),
        payee: (expense: famExpense, dueToFrom: famDueAmit),
        transferGroup: 'g2',
        ids: (from: 'p01', to: 'f03'),
        hlcs: (from: const Hlc(20), to: const Hlc(21)),
        createdByUser: 'amit',
        createdByDevice: 'd2',
        reviewRequiredIn: (from: false, to: false),
        reviewLimitPaise: (from: null, to: null),
      );
      expect(pair.from.lines, [
        dr(amitDueFam, rs(2300)),
        cr(amitCash, rs(2300)),
      ]);
      expect(pair.to.lines, [
        dr(famExpense, rs(2300)),
        cr(famDueAmit, rs(2300)),
      ]);
      final sA = project([pair.from], personal.chart);
      final sF = project([pair.to], fam.chart);
      final recon = InterBook.reconcile([
        InterBookPair(
          a: sA,
          accountA: amitDueFam.id,
          b: sF,
          accountB: famDueAmit.id,
        ),
      ]);
      expect(recon.single.net, Paise.zero);
    });

    test('a non-zero pair is listed with the entries composing it', () {
      final lonely = biz.entry(
        Verbs.transfer(from: bizBank, to: bizDueFam, amount: rs(100)),
        kind: EntryKind.transfer,
        id: 'x',
      );
      final sBiz = project([lonely], biz.chart);
      final sFam = project(const <LedgerEvent>[], fam.chart);
      final recon = InterBook.reconcile([
        InterBookPair(
          a: sBiz,
          accountA: bizDueFam.id,
          b: sFam,
          accountB: famDueBiz.id,
        ),
      ]);
      expect(recon.single.isBalanced, isFalse);
      expect(recon.single.net, rs(100));
      expect(recon.single.entryIdsA, ['x']);
      expect(recon.single.entryIdsB, isEmpty);
    });

    test('builder rejects a non due-to/from counterpart', () {
      expect(
        () => InterBook.transfer(
          amount: rs(1),
          accountingDate: d(2026, 8, 5),
          from: (money: bizBank, dueToFrom: bizBank),
          to: (money: famBank, dueToFrom: famDueBiz),
          transferGroup: 'g',
          ids: (from: 'a', to: 'b'),
          hlcs: (from: const Hlc(1), to: const Hlc(2)),
          createdByUser: 'u',
          createdByDevice: 'd',
          reviewRequiredIn: (from: false, to: false),
          reviewLimitPaise: (from: null, to: null),
        ),
        throwsArgumentError,
      );
    });
  });
}
