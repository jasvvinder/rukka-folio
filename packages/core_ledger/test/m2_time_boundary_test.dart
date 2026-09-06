// Suite A — the M2 rulings: dangling refs are held and author gaps are visible
// (ADR 2026-09-05b §3–4), the ledger time boundary (ADR 2026-09-05e), and the
// projector version on certified closes (ADR 2026-09-05c §3).
@Tags(['A'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestBook book;
  late Account cash, bank, kirana, salary, verma, opening, advRamesh;
  late Chart chart;
  final fy = FinancialYear.of(d(2026, 4, 1));

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

  /// An entry authored on [device] with [seq].
  Entry seqEntry(
    List<Line> lines, {
    required String device,
    required int seq,
    EntryKind kind = EntryKind.moneyOut,
    String? id,
    Hlc? hlc,
    EntryRefs refs = const EntryRefs(),
    LocalDate? date,
  }) => book
      .entry(
        lines,
        kind: kind,
        id: id,
        hlc: hlc,
        refs: refs,
        date: date,
        createdByDevice: device,
      )
      .copyWith(authorSeq: seq);

  group('dangling references are held, not counted (ADR 2026-09-05b §4)', () {
    test('A-05b-1 an amendment that precedes its original in (hlc, id) order still folds once the original is in the set — counted exactly once', () {
      // Clock skew: the amendment carries a lower HLC than the entry it amends.
      final orig = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(250)),
        kind: EntryKind.moneyOut,
        id: 'orig',
        hlc: const Hlc(5000),
      );
      final amend = orig.amendWith(
        newId: 'amend',
        hlc: const Hlc(4000),
        lines: Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(300)),
      );
      for (final set in [
        [orig, amend],
        [amend, orig],
      ]) {
        final s = project(set, chart);
        expect(s.held, isEmpty);
        expect(s.quarantined, isEmpty);
        expect(s.balances[cash.id], -rs(300), reason: 'head counts once');
        expect(s.entries['orig']!.status, EffectiveStatus.superseded);
        expect(s.entries['orig']!.supersededBy, 'amend');
        expect(s.entries['amend']!.status, EffectiveStatus.posted);
      }
    });

    test('A-05b-2 a held reversal and a held decision fold in order when their target arrives; a chain held on one missing root releases as a whole', () {
      final root = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(100)),
        kind: EntryKind.moneyOut,
        id: 'root',
      );
      final a1 = root.amendWith(
        newId: 'a1',
        hlc: book.nextHlc(),
        lines: Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(110)),
      );
      final a2 = a1.amendWith(
        newId: 'a2',
        hlc: book.nextHlc(),
        lines: Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(120)),
      );
      final withoutRoot = project([a1, a2], chart);
      expect(withoutRoot.held.map((h) => h.event.id), ['a1', 'a2']);
      expect(withoutRoot.held.map((h) => h.heldFor), ['root', 'a1']);
      expect(withoutRoot.balances[cash.id], Paise.zero);

      final withRoot = project([a2, a1, root], chart);
      expect(withRoot.held, isEmpty);
      expect(withRoot.balances[cash.id], -rs(120));
      expect(withRoot.headOf('root'), 'a2');

      // Decision on an advance request that has not arrived: held, then applied.
      final req = book.entry(
        Verbs.advanceRequest(advance: advRamesh, from: cash, amount: rs(500)),
        kind: EntryKind.moneyOut,
        status: EntryStatus.pending,
        id: 'req',
        hlc: const Hlc(9000),
      );
      final approve = ApprovalDecision(
        id: 'ok',
        bookId: 'fam',
        entryId: 'req',
        decision: Decision.approve,
        byUser: 'head',
        hlc: const Hlc(8000), // skewed before the request
      );
      final heldDecision = project([approve], chart);
      expect(heldDecision.held.single.reason, HeldReason.decision);
      expect(heldDecision.balances[cash.id], Paise.zero);
      final applied = project([approve, req], chart);
      expect(applied.held, isEmpty);
      expect(applied.entries['req']!.status, EffectiveStatus.posted);
      expect(applied.balances[cash.id], -rs(500));
    });

    test('A-05b-3 a held envelope is quarantined target_missing only when every author sequence is contiguous — otherwise it stays held', () {
      final e1 = seqEntry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(10)),
        device: 'd1',
        seq: 1,
      );
      final orphan = seqEntry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(20)),
        device: 'd1',
        seq: 2,
        refs: const EntryRefs(amends: 'ghost'),
      );
      // Complete: seqs 1, 2 from the only author → the target never existed.
      final complete = project([e1, orphan], chart);
      expect(complete.authorGaps, isEmpty);
      expect(complete.held, isEmpty);
      expect(
        complete.quarantined.single.violations.single.kind,
        ViolationKind.targetMissing,
      );
      expect(complete.quarantined.single.eventId, orphan.id);

      // A gap (seq 4 without 3): the target may still be on its way → held.
      final e4 = seqEntry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(30)),
        device: 'd1',
        seq: 4,
      );
      final gapped = project([e1, orphan, e4], chart);
      expect(gapped.quarantined, isEmpty);
      expect(gapped.held.single.event.id, orphan.id);

      // A legacy envelope without author_seq: nothing can be proven → held.
      final legacy = book.entry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(40)),
        kind: EntryKind.moneyOut,
      );
      final mixed = project([e1, orphan, legacy], chart);
      expect(mixed.quarantined, isEmpty);
      expect(mixed.held.single.event.id, orphan.id);
    });
  });

  group('per-author sequence makes omission visible (ADR 2026-09-05b §3)', () {
    test('A-05b-4 a hole in one author\'s author_seq is reported with the first missing number and the HLC it became visible at; contiguous authors report nothing', () {
      List<Line> lines(int r) =>
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(r));
      final s = project([
        seqEntry(lines(1), device: 'd1', seq: 1, hlc: const Hlc(10)),
        seqEntry(lines(2), device: 'd1', seq: 2, hlc: const Hlc(20)),
        seqEntry(lines(4), device: 'd1', seq: 4, hlc: const Hlc(40)),
        seqEntry(lines(5), device: 'd1', seq: 5, hlc: const Hlc(35)),
        seqEntry(lines(7), device: 'd2', seq: 1, hlc: const Hlc(11)),
        seqEntry(lines(8), device: 'd2', seq: 2, hlc: const Hlc(12)),
      ], chart);
      expect(s.authorGaps.length, 1);
      final g = s.authorGaps.single;
      expect(g.authorDevice, 'd1');
      expect(g.expectedSeq, 3);
      expect(
        g.sinceHlc,
        const Hlc(35),
        reason: 'earliest envelope past the hole',
      );
      expect(s.isProvisional, isTrue);
      // Every envelope that did arrive still counts — the projection is shown, marked provisional.
      expect(s.balances[cash.id], -rs(1 + 2 + 4 + 5 + 7 + 8));

      final contiguous = project([
        seqEntry(lines(1), device: 'd1', seq: 1),
        seqEntry(lines(2), device: 'd1', seq: 2),
        seqEntry(lines(3), device: 'd1', seq: 3),
      ], chart);
      expect(contiguous.authorGaps, isEmpty);
      expect(contiguous.isProvisional, isFalse);
    });

    test('A-05b-5 a repeated author_seq from one device is refused (the later envelope in projection order); legacy envelopes without a sequence are not tracked', () {
      List<Line> lines(int r) =>
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(r));
      final first = seqEntry(
        lines(1),
        device: 'd1',
        seq: 1,
        hlc: const Hlc(10),
      );
      final replay = seqEntry(
        lines(99),
        device: 'd1',
        seq: 1,
        hlc: const Hlc(11),
      );
      final legacy = book.entry(lines(5), kind: EntryKind.moneyOut);
      final s = project([replay, first, legacy], chart);
      expect(s.quarantined.single.eventId, replay.id);
      expect(
        s.quarantined.single.violations.single.kind,
        ViolationKind.authorSeqDuplicate,
      );
      expect(s.authorGaps, isEmpty);
      expect(s.balances[cash.id], -rs(6));
    });

    test('A-05b-6 author_seq rides in the entry JSON and round-trips; it must be a positive integer', () {
      final e = seqEntry(
        Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(1)),
        device: 'd7',
        seq: 12,
      );
      final json = e.toJson();
      expect(json['author_seq'], 12);
      final back = Entry.fromJson(json);
      expect(back.authorSeq, 12);
      expect(back.authorDevice, 'd7');
      expect(back.extra, isEmpty, reason: 'author_seq is a known field now');
      expect(back.toJson(), json);
      expect(
        () => Entry.fromJson({...json, 'author_seq': 0}),
        throwsFormatException,
      );
      expect(
        () => Entry.fromJson({...json, 'author_seq': '3'}),
        throwsFormatException,
      );
      final legacy = Entry.fromJson({...json}..remove('author_seq'));
      expect(legacy.authorSeq, isNull);
      expect(legacy.toJson().containsKey('author_seq'), isFalse);
    });
  });

  group(
    'close preconditions gain the sync-layer blocks (ADR 2026-09-05e §4)',
    () {
      test('A-05e-1 an open author gap or a held envelope blocks both the month lock and the year close, naming the device or envelope', () {
        List<Line> lines(int r) =>
            Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(r));
        final s = project([
          seqEntry(lines(1), device: 'd1', seq: 1, date: d(2026, 5, 3)),
          seqEntry(lines(3), device: 'd1', seq: 3, date: d(2026, 5, 4)),
          seqEntry(
            lines(2),
            device: 'd2',
            seq: 1,
            refs: const EntryRefs(reverses: 'never'),
            date: d(2026, 5, 5),
          ),
        ], chart);
        final month = monthLockPreconditions(s, YearMonth(2026, 5));
        expect(
          month.map((b) => (b.kind, b.ref)),
          containsAll([
            (CloseBlocker.authorGapOpen, 'd1'),
            (CloseBlocker.heldEnvelope, s.held.single.event.id),
          ]),
        );
        final year = yearClosePreconditions(s, chart, fy);
        expect(
          year.map((b) => b.kind),
          containsAll([CloseBlocker.authorGapOpen, CloseBlocker.heldEnvelope]),
        );
        // A clean book has neither.
        final clean = project([
          seqEntry(lines(1), device: 'd1', seq: 1, date: d(2026, 5, 3)),
        ], chart);
        expect(monthLockPreconditions(clean, YearMonth(2026, 5)), isEmpty);
        expect(
          yearClosePreconditions(clean, chart, fy).map((b) => b.kind),
          everyElement(CloseBlocker.monthOpen),
        );
      });
    },
  );

  group('the certified vector (ADR 2026-09-05e §2)', () {
    test('A-05e-2 the year-close vector is cut by accounting_date, not HLC: an entry dated 3 April posted before a 5 April close belongs to the new year', () {
      final events = [
        book.entry(
          Verbs.openingBalance(
            account: cash,
            balance: rs(1000),
            openingAccount: opening,
          ),
          kind: EntryKind.adjustment,
          date: d(2026, 4, 1),
          hlc: const Hlc(1),
        ),
        book.entry(
          Verbs.moneyIn(into: cash, from: salary, amount: rs(500)),
          kind: EntryKind.moneyIn,
          date: d(2027, 3, 31),
          hlc: const Hlc(2),
        ),
        book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(200)),
          kind: EntryKind.moneyOut,
          date: d(2027, 4, 3), // next FY, but posted before the close
          hlc: const Hlc(3),
        ),
      ];
      final s = project(events, chart);
      final v = closingVector(s, chart, fy);
      expect(v[cash.id], rs(1500), reason: 'the 3 April entry is next year\'s');
      expect(v[opening.id], -rs(1000));
      expect(
        v[salary.id],
        Paise.zero,
        reason: 'category accounts are not carried',
      );
      expect(v[kirana.id], Paise.zero);
      expect(
        v[netResultKey(fy)],
        -rs(500),
        reason: 'the year\'s surplus, one line',
      );
      expect(v.nonZero.keys, isNot(contains(netResultKey(fy.next))));
      expect(v.isBalanced, isTrue);
      expect(
        v.canonical(),
        '${cash.id}\t150000\n${opening.id}\t-100000\n${netResultKey(fy)}\t-50000\n',
      );

      // The reader re-verifies the closer's as-of vector, not the live one.
      final close = YearClose(
        id: 'Y',
        bookId: 'fam',
        financialYear: fy,
        vector: v,
        byUser: 'a',
        hlc: const Hlc(10),
        projectorVersion: projectorVersion,
      );
      final closed = project([...events, close], chart);
      expect(closed.years[fy]!.verification, CloseVerification.verified);
      // Seeding next year from it: income/expense open at zero, the result carries.
      final next = project([events.last], chart, opening: v);
      expect(next.balances[salary.id], Paise.zero);
      expect(next.balances[kirana.id], rs(200));
      expect(next.balances[cash.id], rs(1300));
      expect(next.balances[netResultKey(fy)], -rs(500));
      final tb = trialBalance(next, chart);
      expect(tb.isBalanced, isTrue);
      expect(tb.rows.map((r) => r.accountId), contains(netResultKey(fy)));
    });

    test('A-05e-3 net profit is FY-scoped: income − expense − distributions posted in that year, from entries dated in it', () {
      final biz = TestBook('kaur', bookType: BookType.business);
      final bank = biz.money('Bank');
      final amrit = biz.partner('Amrit');
      final sukhdev = biz.partner('Sukhdev');
      final seed = biz.expense('Seed');
      final crop = biz.income('Crop');
      final pd = biz.profitDistributed();
      final c = biz.chart;
      final partners = [
        PartnerShare(account: amrit, ratio: 1),
        PartnerShare(account: sukhdev, ratio: 1),
      ];
      final lastYear = biz.entry(
        Verbs.moneyIn(into: bank, from: crop, amount: rs(999)),
        kind: EntryKind.moneyIn,
        date: d(2026, 3, 30),
      );
      final cost = biz.entry(
        Verbs.moneyOut(from: bank, forWhat: seed, amount: rs(400)),
        kind: EntryKind.moneyOut,
        date: d(2026, 5, 1),
      );
      final sale = biz.entry(
        Verbs.moneyIn(into: bank, from: crop, amount: rs(1000)),
        kind: EntryKind.moneyIn,
        date: d(2026, 6, 1),
      );
      final s = project([lastYear, cost, sale], c);
      expect(netProfit(s, c, fy), rs(600));
      expect(netProfit(s, c, FinancialYear.of(d(2025, 4, 1))), rs(999));

      final dist = biz.entry(
        Verbs.profitDistribution(
          profitDistributed: pd,
          partners: partners,
          netProfit: rs(600),
        ),
        kind: EntryKind.adjustment,
        date: d(2026, 7, 1),
      );
      final after = project([lastYear, cost, sale, dist], c);
      expect(
        netProfit(after, c, fy),
        Paise.zero,
        reason: 'already distributed',
      );
    });

    test('A-05e-4 accumulated surplus is a computed line — Σ certified results + opening equity − distributions — and the ceiling says by how much a distribution overshoots', () {
      final biz = TestBook('kaur', bookType: BookType.business);
      final bank = biz.money('Bank');
      final amrit = biz.partner('Amrit');
      final seed = biz.expense('Seed');
      final crop = biz.income('Crop');
      final pd = biz.profitDistributed();
      final open = biz.openingBalance();
      final c = biz.chart;
      final partners = [PartnerShare(account: amrit, ratio: 1)];
      final prior = FinancialYear.of(d(2025, 4, 1));
      // Certified last year: opening equity 100, result +300, distributed 50.
      final certified = BalanceVector({
        bank.id: rs(350),
        open.id: -rs(100),
        pd.id: rs(50),
        netResultKey(prior): -rs(300),
      });
      expect(certified.isBalanced, isTrue);
      final thisYear = [
        biz.entry(
          Verbs.moneyIn(into: bank, from: crop, amount: rs(200)),
          kind: EntryKind.moneyIn,
          date: d(2026, 5, 1),
        ),
        biz.entry(
          Verbs.moneyOut(from: bank, forWhat: seed, amount: rs(80)),
          kind: EntryKind.moneyOut,
          date: d(2026, 5, 2),
        ),
      ];
      final s = project(thisYear, c, opening: certified);
      expect(accumulatedSurplus(s, c, openFy: fy), rs(300 + 100 - 50));
      final room = distributionHeadroom(s, c, fy: fy, proposed: rs(500));
      expect(room.headroom, rs(350 + 120));
      expect(room.excess, rs(30));
      final fits = distributionHeadroom(s, c, fy: fy, proposed: rs(470));
      expect(fits.excess, Paise.zero);

      // Full replay (no seed) reaches the same surplus from the raw history.
      final history = [
        biz.entry(
          Verbs.openingBalance(
            account: bank,
            balance: rs(100),
            openingAccount: open,
          ),
          kind: EntryKind.adjustment,
          date: d(2025, 4, 1),
        ),
        biz.entry(
          Verbs.moneyIn(into: bank, from: crop, amount: rs(300)),
          kind: EntryKind.moneyIn,
          date: d(2025, 9, 1),
        ),
        biz.entry(
          Verbs.profitDistribution(
            profitDistributed: pd,
            partners: partners,
            netProfit: rs(50),
          ),
          kind: EntryKind.adjustment,
          date: d(2026, 3, 31),
        ),
        biz.entry(
          Verbs.partnerDrawing(partner: amrit, from: bank, amount: rs(50)),
          kind: EntryKind.moneyOut,
          date: d(2026, 3, 31),
        ),
        ...thisYear,
      ];
      final full = project(history, c);
      expect(accumulatedSurplus(full, c, openFy: fy), rs(350));
      expect(
        distributionHeadroom(full, c, fy: fy, proposed: rs(500)).excess,
        rs(30),
      );
    });
  });

  group('losses, ceiling, interest above profit (ADR 2026-09-05e §8)', () {
    test('A-05e-5 a negative total splits as the exact mirror of the positive split: same floors, remainder on the largest ratio, sums to the total', () {
      expect(splitByRatio(Paise(-335000_00), [1, 1, 1]).map((p) => p.raw), [
        -11166668,
        -11166666,
        -11166666,
      ]);
      for (var total = 1; total < 300; total += 7) {
        for (final ratios in [
          [1, 1, 1],
          [3, 2],
          [5, 5, 7, 1],
        ]) {
          final pos = splitByRatio(Paise(total), ratios);
          final neg = splitByRatio(Paise(-total), ratios);
          expect(neg, [for (final p in pos) -p], reason: '$total / $ratios');
          expect(Paise.sum(neg), Paise(-total));
        }
      }
      expect(() => splitByRatio(Paise(-1), [1, 0]), throwsArgumentError);
    });

    test('A-05e-6 a loss posts the mirror — Dr each partner · Cr Profit Distributed — and interest above profit is credited in full with the negative remainder shared as a loss', () {
      final biz = TestBook('kaur', bookType: BookType.business);
      final amrit = biz.partner('Amrit');
      final sukhdev = biz.partner('Sukhdev');
      final pd = biz.profitDistributed();
      final partners = [
        PartnerShare(account: amrit, ratio: 2),
        PartnerShare(account: sukhdev, ratio: 1),
      ];
      final loss = Verbs.profitDistribution(
        profitDistributed: pd,
        partners: partners,
        netProfit: -rs(300),
      );
      expect(loss, [
        cr(pd, rs(300)),
        Line(accountId: amrit.id, amount: rs(200), tag: 'share'),
        Line(accountId: sukhdev.id, amount: rs(100), tag: 'share'),
      ]);
      expect(Paise.sum(loss.map((l) => l.amount)), Paise.zero);

      // Profit 100, interest 150 → interest in full, −50 shared 2:1 as a loss.
      final over = Verbs.profitDistribution(
        profitDistributed: pd,
        partners: partners,
        netProfit: rs(100),
        interest: {amrit.id: rs(90), sukhdev.id: rs(60)},
      );
      expect(over, [
        dr(pd, rs(100)),
        Line(accountId: amrit.id, amount: -rs(90), tag: 'interest'),
        Line(accountId: sukhdev.id, amount: -rs(60), tag: 'interest'),
        Line(accountId: amrit.id, amount: Paise(3334), tag: 'share'),
        Line(accountId: sukhdev.id, amount: Paise(1666), tag: 'share'),
      ]);
      expect(Paise.sum(over.map((l) => l.amount)), Paise.zero);
      expect(
        () => Verbs.profitDistribution(
          profitDistributed: pd,
          partners: partners,
          netProfit: Paise.zero,
        ),
        throwsArgumentError,
      );
    });

    test('A-05e-7 interest on capital divides by 365 even across a leap year (Actual/365)', () {
      final biz = TestBook('kaur', bookType: BookType.business);
      final bank = biz.money('Bank');
      final amrit = biz.partner('Amrit');
      final open = biz.openingBalance();
      final c = biz.chart;
      final s = project([
        biz.entry(
          Verbs.openingBalance(
            account: amrit,
            balance: -rs(365000),
            openingAccount: open,
          ),
          kind: EntryKind.adjustment,
          date: d(2027, 12, 31),
        ),
        biz.entry(
          Verbs.openingBalance(
            account: bank,
            balance: rs(365000),
            openingAccount: open,
          ),
          kind: EntryKind.adjustment,
          date: d(2027, 12, 31),
        ),
      ], c);
      final interest = interestOnCapital(
        s,
        c,
        partners: [PartnerShare(account: amrit, ratio: 1)],
        from: d(2028, 1, 1),
        to: d(2028, 12, 31), // 366 days
        rateBasisPoints: 1000, // 10 %
      );
      // 3,65,000 × 10 % × 366 / 365 = 36,600.00
      expect(interest[amrit.id], rs(36600));
    });
  });

  group(
    'verb shapes are reader-enforced (02 §1.4 rule 7; ADR 2026-09-05e §6)',
    () {
      test('A-05e-8 every kind × a wrong class shape is quarantined shape_violation; every posting 02 prescribes passes, and a reversal is exempt', () {
        final due = book.dueToFrom('biz');
        final due2 = book.dueToFrom('other');
        final partner = book.partner('Amrit');
        final pd = book.profitDistributed();
        final c2 = book.chart;
        Entry make(EntryKind kind, List<Line> lines, {EntryRefs? refs}) =>
            book.entry(lines, kind: kind, refs: refs ?? const EntryRefs());
        ViolationKind? only(Entry e) {
          final v = checkUniversalInvariants(e, c2);
          return v.isEmpty ? null : v.single.kind;
        }

        final wrong = <EntryKind, List<Line>>{
          EntryKind.moneyIn: [dr(kirana, rs(1)), cr(cash, rs(1))],
          EntryKind.moneyOut: [dr(cash, rs(1)), cr(salary, rs(1))],
          EntryKind.gaveCredit: [dr(kirana, rs(1)), cr(cash, rs(1))],
          EntryKind.tookCredit: [dr(verma, rs(1)), cr(cash, rs(1))],
          EntryKind.transfer: [dr(cash, rs(1)), cr(salary, rs(1))],
          EntryKind.adjustment: [dr(cash, rs(1)), cr(salary, rs(1))],
        };
        for (final MapEntry(key: kind, value: lines) in wrong.entries) {
          expect(
            only(make(kind, lines)),
            ViolationKind.shapeViolation,
            reason: kind.wire,
          );
        }
        // Two equity_system accounts in one adjustment, and a transfer joining two Due to/from.
        expect(
          only(make(EntryKind.adjustment, [dr(opening, rs(1)), cr(pd, rs(1))])),
          ViolationKind.shapeViolation,
        );
        expect(
          only(
            book.entry([
              dr(due, rs(1)),
              cr(due2, rs(1)),
            ], kind: EntryKind.transfer),
          ),
          ViolationKind.shapeViolation,
        );

        final right = <(EntryKind, List<Line>)>[
          (
            EntryKind.moneyIn,
            Verbs.moneyIn(into: cash, from: salary, amount: rs(1)),
          ),
          (
            EntryKind.moneyIn,
            Verbs.moneyIn(into: cash, from: verma, amount: rs(1)),
          ),
          (
            EntryKind.moneyIn,
            Verbs.advanceReturn(advance: advRamesh, into: cash, amount: rs(1)),
          ),
          (
            EntryKind.moneyOut,
            Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(1)),
          ),
          (
            EntryKind.moneyOut,
            Verbs.moneyOut(from: cash, forWhat: verma, amount: rs(1)),
          ),
          (
            EntryKind.moneyOut,
            Verbs.advanceRequest(advance: advRamesh, from: cash, amount: rs(1)),
          ),
          (
            EntryKind.moneyOut,
            Verbs.advanceSpend(
              advance: advRamesh,
              forWhat: kirana,
              amount: rs(1),
            ),
          ),
          (
            EntryKind.moneyOut,
            Verbs.partnerDrawing(partner: partner, from: cash, amount: rs(1)),
          ),
          (
            EntryKind.moneyOut,
            [dr(kirana, rs(1)), cr(due, rs(1))],
          ), // pocket expense, payee half
          (
            EntryKind.gaveCredit,
            Verbs.gaveCredit(toWhom: verma, gave: cash, amount: rs(1)),
          ),
          (
            EntryKind.gaveCredit,
            Verbs.gaveCredit(toWhom: verma, gave: salary, amount: rs(1)),
          ),
          (
            EntryKind.tookCredit,
            Verbs.tookCredit(fromWhom: verma, took: kirana, amount: rs(1)),
          ),
          (
            EntryKind.tookCredit,
            Verbs.partnerPaidCost(
              partner: partner,
              expense: kirana,
              amount: rs(1),
            ),
          ),
          (
            EntryKind.transfer,
            Verbs.transfer(from: cash, to: bank, amount: rs(1)),
          ),
          (
            EntryKind.transfer,
            Verbs.transfer(from: cash, to: due, amount: rs(1)),
          ),
          (
            EntryKind.adjustment,
            Verbs.openingBalance(
              account: cash,
              balance: rs(1),
              openingAccount: opening,
            ),
          ),
          (
            EntryKind.adjustment,
            Verbs.profitDistribution(
              profitDistributed: pd,
              partners: [PartnerShare(account: partner, ratio: 1)],
              netProfit: rs(9),
            ),
          ),
        ];
        for (final (kind, lines) in right) {
          expect(
            only(make(kind, lines)),
            isNull,
            reason: '${kind.wire} $lines',
          );
        }
        // A reversal keeps the original kind with mirrored lines — exempt.
        final orig = make(
          EntryKind.moneyOut,
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(5)),
        );
        final rev = orig.reversal(
          newId: 'rev',
          hlc: book.nextHlc(),
          accountingDate: d(2026, 5, 11),
          createdByUser: 'u1',
          createdByDevice: 'd1',
        );
        expect(only(rev), isNull);
        final s = project([orig, rev], c2);
        expect(s.quarantined, isEmpty);
        expect(s.entries[orig.id]!.status, EffectiveStatus.voided);
      });
    },
  );

  group('smaller rulings (ADR 2026-09-05e §7, §12)', () {
    test('A-05e-9 statement rows are ordered by (accounting_date, hlc, envelope_id) — identical on every device', () {
      final e1 = book.entry(
        Verbs.moneyIn(into: cash, from: salary, amount: rs(10)),
        kind: EntryKind.moneyIn,
        date: d(2026, 5, 20),
        hlc: const Hlc(100),
        id: 'b',
      );
      final e2 = book.entry(
        Verbs.moneyIn(into: cash, from: salary, amount: rs(20)),
        kind: EntryKind.moneyIn,
        date: d(2026, 5, 1),
        hlc: const Hlc(300),
        id: 'z',
      );
      final e3 = book.entry(
        Verbs.moneyIn(into: cash, from: salary, amount: rs(30)),
        kind: EntryKind.moneyIn,
        date: d(2026, 5, 20),
        hlc: const Hlc(100),
        id: 'a',
      );
      for (final set in [
        [e1, e2, e3],
        [e3, e2, e1],
      ]) {
        final rows = statement(project(set, chart), cash.id);
        expect(rows.map((r) => r.entryId), ['z', 'a', 'b']);
        expect(rows.map((r) => r.running.raw), [2000, 5000, 6000]);
      }
    });

    test('A-05e-10 a due-to/from pair with a sealed side is reported unconfirmed, never as a mismatch', () {
      final fam = TestBook('fam');
      final famCash = fam.cash('Cash');
      final dueBiz = fam.dueToFrom('biz');
      final famState = project([
        fam.entry(
          Verbs.transfer(from: dueBiz, to: famCash, amount: rs(500)),
          kind: EntryKind.transfer,
        ),
      ], fam.chart);
      final sealed = InterBook.reconcile([
        InterBookPair(
          a: famState,
          accountA: dueBiz.id,
          b: null,
          accountB: 'biz:due',
        ),
      ]).single;
      expect(sealed.status, PairStatus.unconfirmed);
      expect(sealed.isUnconfirmed, isTrue);
      expect(sealed.isBalanced, isFalse);
      expect(sealed.net, -rs(500), reason: 'the readable side alone');
      expect(sealed.entryIdsA, hasLength(1));
      expect(sealed.entryIdsB, isEmpty);

      final biz = TestBook('biz');
      final bizBank = biz.money('Bank');
      final dueFam = biz.dueToFrom('fam');
      final bizState = project([
        biz.entry(
          Verbs.transfer(from: bizBank, to: dueFam, amount: rs(500)),
          kind: EntryKind.transfer,
        ),
      ], biz.chart);
      final both = InterBook.reconcile([
        InterBookPair(
          a: famState,
          accountA: dueBiz.id,
          b: bizState,
          accountB: dueFam.id,
        ),
      ]).single;
      expect(both.status, PairStatus.balanced);
      expect(both.isBalanced, isTrue);
    });

    test('A-05e-11 a negative cash balance warns; collection boxes and bank subtypes do not', () {
      final gollak = book.money('Gollak', subtype: MoneySubtype.cashCollection);
      final c2 = book.chart;
      final s = project([
        book.entry(
          Verbs.moneyOut(from: cash, forWhat: kirana, amount: rs(100)),
          kind: EntryKind.moneyOut,
        ),
        book.entry(
          Verbs.moneyOut(from: bank, forWhat: kirana, amount: rs(100)),
          kind: EntryKind.moneyOut,
        ),
        book.entry(
          Verbs.transfer(from: gollak, to: cash, amount: rs(50)),
          kind: EntryKind.transfer,
        ),
      ], c2);
      expect(s.balances[cash.id], -rs(50));
      expect(s.balances[bank.id], -rs(100));
      expect(s.balances[gollak.id], -rs(50));
      expect(negativeCashWarnings(s, c2), [cash.id]);
    });
  });

  group('projector version on certified closes (ADR 2026-09-05c §3)', () {
    test(
      'A-05c-1 core_ledger exports projectorVersion, and closes record it',
      () {
        expect(projectorVersion, 2);
        final lock = PeriodLock(
          id: 'L',
          bookId: 'fam',
          period: YearMonth(2026, 5),
          byUser: 'a',
          hlc: Hlc(1),
          projectorVersion: projectorVersion,
        );
        expect(lock.projectorVersion, 2);
      },
    );

    test('A-05c-2 a mismatch against a newer certifier reads "update to verify" (readerOutdated); against an older one the certifier is outdated; a matching vector verifies whatever the version', () {
      final e = book.entry(
        Verbs.moneyIn(into: cash, from: salary, amount: rs(10)),
        kind: EntryKind.moneyIn,
        date: d(2026, 5, 1),
        hlc: const Hlc(1),
      );
      final base = project([e], chart);
      final good = closingVector(base, chart, fy);
      final bad = BalanceVector({cash.id: rs(999)});
      YearClose close(BalanceVector v, int? version) => YearClose(
        id: 'Y$version',
        bookId: 'fam',
        financialYear: fy,
        vector: v,
        byUser: 'a',
        hlc: const Hlc(50),
        projectorVersion: version,
      );
      CloseVerification verify(BalanceVector v, int? version) =>
          project([e, close(v, version)], chart).years[fy]!.verification!;
      expect(verify(good, projectorVersion), CloseVerification.verified);
      expect(verify(good, 99), CloseVerification.verified);
      expect(verify(good, null), CloseVerification.verified);
      expect(verify(bad, projectorVersion), CloseVerification.mismatch);
      expect(verify(bad, null), CloseVerification.mismatch);
      expect(
        verify(bad, projectorVersion + 1),
        CloseVerification.readerOutdated,
      );
      expect(
        verify(bad, projectorVersion - 1),
        CloseVerification.certifierOutdated,
      );

      // Month locks carry a canonical vector and are verified the same way.
      final live = base.balances.canonical();
      final s = project([
        e,
        PeriodLock(
          id: 'Lok',
          bookId: 'fam',
          period: YearMonth(2026, 5),
          byUser: 'a',
          hlc: const Hlc(20),
          vectorCanonical: live,
          projectorVersion: projectorVersion,
        ),
        PeriodLock(
          id: 'Lnew',
          bookId: 'fam',
          period: YearMonth(2026, 6),
          byUser: 'a',
          hlc: const Hlc(21),
          vectorCanonical: 'tampered',
          projectorVersion: projectorVersion + 1,
        ),
      ], chart);
      expect(s.lockVerification['Lok'], CloseVerification.verified);
      expect(s.lockVerification['Lnew'], CloseVerification.readerOutdated);
      expect(s.years[fy]?.vectorMatchesReplay, isNull);
    });
  });
}
