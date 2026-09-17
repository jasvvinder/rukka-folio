// Suite E — put in / took out / share, per partner (13 §3.2 row S14) derived
// as a pure function of (projected state, chart), 02 §7.1 🔒.
//
// The figures are the Kaur Family Agriculture worked example the engine's own
// A-02-62…67 already pin (`core_ledger/test/partners_test.dart`), so this
// split and the engine's capacity/drift speak about the same book. Synthetic
// data only (CLAUDE.md rule 4).
@Tags(['E'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

/// ₹[rupees] in integer paise — no float ever touches money (rule 1).
Paise rs(int rupees) => Paise(rupees * 100);

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

/// The Kaur farm: three owners, a bank, four expense heads, two income heads.
final class Farm {
  Farm() {
    var order = 0;
    Account a(
      String id,
      String name,
      AccountClass c, {
      MoneySubtype? subtype,
      SystemRole? role,
    }) => Account(
      id: 'farm:$id',
      bookId: 'farm',
      name: name,
      accountClass: c,
      subtype: subtype,
      systemRole: role,
      createdOrder: order++,
    );
    bank = a(
      'bank',
      'SBI Agri Current',
      AccountClass.money,
      subtype: MoneySubtype.current,
    );
    amrit = a('amrit', 'Amrit Kaur — Partner Current', AccountClass.partner);
    sukhdev = a(
      'sukhdev',
      'Sukhdev Singh — Partner Current',
      AccountClass.partner,
    );
    harjit = a('harjit', 'Harjit Kaur — Partner Current', AccountClass.partner);
    seed = a('seed', 'Seed & Fertiliser', AccountClass.categoryExpense);
    diesel = a('diesel', 'Diesel & Machinery', AccountClass.categoryExpense);
    labour = a('labour', 'Labour', AccountClass.categoryExpense);
    repair = a('repair', 'Machinery Repair', AccountClass.categoryExpense);
    crop = a('crop', 'Crop Sale', AccountClass.categoryIncome);
    milk = a('milk', 'Milk Sale', AccountClass.categoryIncome);
    profitDistributed = a(
      'pd',
      'Profit Distributed',
      AccountClass.equitySystem,
      role: SystemRole.profitDistributed,
    );
    opening = a(
      'opening',
      'Opening Balance / Capital',
      AccountClass.equitySystem,
      role: SystemRole.openingBalance,
    );
  }

  late final Account bank;
  late final Account amrit;
  late final Account sukhdev;
  late final Account harjit;
  late final Account seed;
  late final Account diesel;
  late final Account labour;
  late final Account repair;
  late final Account crop;
  late final Account milk;
  late final Account profitDistributed;
  late final Account opening;

  int _n = 0;
  int _hlc = 1000;

  List<Account> get accounts => [
    bank,
    amrit,
    sukhdev,
    harjit,
    seed,
    diesel,
    labour,
    repair,
    crop,
    milk,
    profitDistributed,
    opening,
  ];

  Chart get chart => Chart(bookId: 'farm', accounts: accounts);

  Entry entry(
    List<Line> lines, {
    required EntryKind kind,
    required LocalDate date,
  }) => Entry(
    id: 'e${++_n}',
    bookId: 'farm',
    kind: kind,
    status: EntryStatus.posted,
    reviewRequired: false,
    accountingDate: date,
    lines: lines,
    createdByUser: 'amrit',
    createdByDevice: 'dev-a',
    hlc: Hlc(_hlc++),
  );

  /// The season exactly as A-02-62…65 post it.
  List<Entry> season() => [
    entry(
      Verbs.openingBalance(
        account: bank,
        balance: rs(50000),
        openingAccount: opening,
      ),
      kind: EntryKind.adjustment,
      date: d(2026, 4, 1),
    ),
    entry(
      Verbs.partnerPaidCost(partner: amrit, expense: seed, amount: rs(180000)),
      kind: EntryKind.tookCredit,
      date: d(2026, 4, 8),
    ),
    entry(
      Verbs.partnerPaidCost(
        partner: sukhdev,
        expense: diesel,
        amount: rs(95000),
      ),
      kind: EntryKind.tookCredit,
      date: d(2026, 4, 12),
    ),
    entry(
      Verbs.partnerPaidCost(
        partner: harjit,
        expense: labour,
        amount: rs(60000),
      ),
      kind: EntryKind.tookCredit,
      date: d(2026, 4, 20),
    ),
    entry(
      Verbs.moneyOut(from: bank, forWhat: repair, amount: rs(41000)),
      kind: EntryKind.moneyOut,
      date: d(2026, 5, 6),
    ),
    entry(
      Verbs.moneyIn(into: bank, from: crop, amount: rs(850000)),
      kind: EntryKind.moneyIn,
      date: d(2026, 6, 18),
    ),
    entry(
      Verbs.moneyIn(into: bank, from: milk, amount: rs(120000)),
      kind: EntryKind.moneyIn,
      date: d(2026, 6, 30),
    ),
    entry(
      Verbs.partnerDrawing(partner: amrit, from: bank, amount: rs(50000)),
      kind: EntryKind.moneyOut,
      date: d(2026, 7, 10),
    ),
  ];

  Entry distribution(
    Paise netProfit, {
    Map<String, Paise> interest = const {},
  }) => entry(
    Verbs.profitDistribution(
      profitDistributed: profitDistributed,
      partners: [
        PartnerShare(account: amrit, ratio: 1),
        PartnerShare(account: sukhdev, ratio: 1),
        PartnerShare(account: harjit, ratio: 1),
      ],
      netProfit: netProfit,
      interest: interest,
    ),
    kind: EntryKind.adjustment,
    date: d(2026, 7, 31),
  );
}

void main() {
  late Farm farm;
  setUp(() => farm = Farm());

  PartnerLedgerPosition of(List<PartnerLedgerPosition> ps, String id) =>
      ps.firstWhere((p) => p.accountId == id);

  test('E-02-1 the three events of 02 §7.1 🔒 land in their own buckets, and '
      'nothing is folded together', () {
    final state = project([
      ...farm.season(),
      farm.distribution(rs(594000)),
    ], farm.chart);
    final positions = partnerPositions(state, farm.chart);
    expect(positions.map((p) => p.accountId), [
      'farm:amrit',
      'farm:sukhdev',
      'farm:harjit',
    ], reason: 'chart creation order — §7.1 remainder rule keys on it');

    final amrit = of(positions, 'farm:amrit');
    expect(amrit.putIn, rs(180000), reason: 'Dr Seed · Cr Amrit');
    expect(amrit.tookOut, rs(50000), reason: 'Dr Amrit · Cr bank');
    expect(amrit.share, rs(198000), reason: 'Dr Profit Distributed · Cr Amrit');
    expect(amrit.other, Paise.zero);
    expect(amrit.net, rs(328000), reason: 'the business owes Amrit');

    final sukhdev = of(positions, 'farm:sukhdev');
    expect(sukhdev.putIn, rs(95000));
    expect(sukhdev.tookOut, Paise.zero);
    expect(sukhdev.share, rs(198000));
    expect(sukhdev.net, rs(293000));

    final harjit = of(positions, 'farm:harjit');
    expect(harjit.putIn, rs(60000));
    expect(harjit.tookOut, Paise.zero);
    expect(harjit.share, rs(198000));
    expect(harjit.net, rs(258000));
  });

  test('E-02-2 the split reconciles to the balance: '
      'net == putIn − tookOut + share + other', () {
    final state = project([
      ...farm.season(),
      farm.distribution(rs(594000)),
    ], farm.chart);
    for (final p in partnerPositions(state, farm.chart)) {
      expect(p.reconciles, isTrue, reason: '$p');
      expect(p.net, -state.balances[p.accountId]);
    }
  });

  test('E-02-3 a loss is a negative share, not an unclassified line '
      '(ADR 2026-09-05e §8 mirror posting)', () {
    final state = project([
      ...farm.season(),
      farm.distribution(-rs(30000)),
    ], farm.chart);
    final amrit = of(partnerPositions(state, farm.chart), 'farm:amrit');
    expect(amrit.share, -rs(10000));
    expect(amrit.other, Paise.zero);
    expect(amrit.reconciles, isTrue);
  });

  test('E-02-4 interest on capital rides with the share — one entry, two '
      'lines, one event (02 §7.1 *Order of operations*)', () {
    final state = project([
      ...farm.season(),
      farm.distribution(
        rs(594000),
        interest: {'farm:amrit': rs(4296), 'farm:sukhdev': rs(2311)},
      ),
    ], farm.chart);
    final positions = partnerPositions(state, farm.chart);
    final amrit = of(positions, 'farm:amrit');
    // Interest ₹4,296, then the **remaining** ₹5,87,393 split three ways —
    // floor each, the 2-paisa remainder to the largest ratio, ties broken by
    // the earliest-created partner account (02 §7.1 🔒 rounding rule).
    expect(amrit.share, rs(4296) + const Paise(19579768));
    expect(amrit.other, Paise.zero);
    expect(Paise.sum(positions.map((p) => p.share)), rs(594000));
  });

  test('E-02-5 a cash contribution is *other*, never folded into one of the '
      'three (02 §7.1 names three events, and this is not one) ⚠️ SPEC', () {
    // An owner puts cash into the business: `Dr bank · Cr Partner Current`
    // (ADR 2026-09-09c §4's opening contribution). Raw lines because no verb
    // builds it — `Verbs.moneyIn` admits income, party and Capital only, while
    // `checkShape` admits a partner on that side. Reported in the lane report.
    final contribution = farm.entry(
      [
        Line(accountId: farm.bank.id, amount: rs(20000)),
        Line(accountId: farm.amrit.id, amount: -rs(20000)),
      ],
      kind: EntryKind.moneyIn,
      date: d(2026, 8, 1),
    );
    final state = project([
      ...farm.season(),
      farm.distribution(rs(594000)),
      contribution,
    ], farm.chart);
    final amrit = of(partnerPositions(state, farm.chart), 'farm:amrit');
    expect(amrit.putIn, rs(180000), reason: 'cash in is not a cost paid');
    expect(amrit.tookOut, rs(50000), reason: 'it is not a drawing either');
    expect(amrit.other, rs(20000));
    expect(amrit.reconciles, isTrue);
  });

  test('E-02-6 a partner-to-partner settlement is *other* on both sides '
      '(02 §7.1 settlement route 2)', () {
    // `Dr {over-funded} · Cr {under-funded}`. Classified directly rather than
    // through `project`, because no `EntryKind` admits `Dr partner · Cr
    // partner` today and the projector quarantines the entry — the engine
    // blocker this lane reports, not a statement about this derivation.
    final settlement = farm.entry(
      [
        Line(accountId: farm.amrit.id, amount: rs(15000)),
        Line(accountId: farm.harjit.id, amount: -rs(15000)),
      ],
      kind: EntryKind.adjustment,
      date: d(2026, 8, 2),
    );
    for (final line in settlement.lines) {
      expect(
        classifyPartnerLine(entry: settlement, line: line, chart: farm.chart),
        PartnerFlow.other,
      );
    }
  });

  test('E-02-7 a certified opening balance rides in *other*, so the split '
      'still reconciles after a year close (02 §8.1)', () {
    final state = project(
      farm.season(),
      farm.chart,
      opening: BalanceVector({
        'farm:amrit': -rs(100000),
        'farm:bank': rs(100000),
      }),
    );
    final amrit = of(partnerPositions(state, farm.chart), 'farm:amrit');
    expect(amrit.other, rs(100000));
    expect(amrit.putIn, rs(180000));
    expect(amrit.reconciles, isTrue);
  });

  test('E-02-8 a *Just me* business has no positions at all — the caller '
      'never says the word partner (02 §7.1 🔒)', () {
    final chart = Chart(
      bookId: 'farm',
      accounts: [farm.bank, farm.seed, farm.opening],
    );
    expect(partnerPositions(project(const [], chart), chart), isEmpty);
  });

  test('E-02-9 a debit balance is real: net is negative and owesBusiness is '
      'true (02 §7.1 🔒)', () {
    final over = farm.entry(
      Verbs.partnerDrawing(
        partner: farm.harjit,
        from: farm.bank,
        amount: rs(70000),
      ),
      kind: EntryKind.moneyOut,
      date: d(2026, 8, 1),
    );
    final state = project([...farm.season(), over], farm.chart);
    final harjit = of(partnerPositions(state, farm.chart), 'farm:harjit');
    expect(harjit.tookOut, rs(70000));
    expect(harjit.putIn, rs(60000));
    expect(harjit.net, -rs(10000));
    expect(harjit.owesBusiness, isTrue);
  });

  test('E-02-10 a line whose counterpart is not in the chart is *other*, '
      'never guessed at', () {
    final stray = farm.entry(
      [
        Line(accountId: 'farm:unknown', amount: rs(500)),
        Line(accountId: farm.amrit.id, amount: -rs(500)),
      ],
      kind: EntryKind.tookCredit,
      date: d(2026, 8, 3),
    );
    expect(
      classifyPartnerLine(
        entry: stray,
        line: stray.lines[1],
        chart: farm.chart,
      ),
      PartnerFlow.other,
    );
  });
}
