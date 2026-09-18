// F1-02-52…59: the **profit-distribution surface** on `LocalLedger` — 02 §7.1
// 🔒 (profit distribution · interest on capital · losses, ceiling, interest
// above profit · the rounding rule · where the ratio lives), 02 §7.2.1 🔒
// (distribute profit is structural and needs a quorum), ADR 2026-09-14b §6
// (a distribution applies the ratio **in force** at its own order point) and
// ADR 2026-09-05e §8.
//
// The point of every test here is that the facade **computes nothing**: the
// split, the remainder, the interest and the ceiling are `core_ledger`'s and
// the ratio is `packages/data`'s structural fold. These tests pin that the
// facade carries those answers and refuses in the engine's own terms.
//
// The book is the Kaur Family Agriculture worked example A-02-62…67 and
// A-05e-3…6 already pin. Synthetic data (CLAUDE.md rule 4); in-memory SQLite,
// injected clock.
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' as data show BookOwnership;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

/// The farm, as a shared business with three owners.
final class Farm {
  Farm(this.s, this.bookId, this.memberIds);

  final SeededLedger s;
  final String bookId;
  final List<String> memberIds;

  late Chart chart;
  late Account bank;
  late Account amrit;
  late Account sukhdev;
  late Account harjit;
  late Account seed;
  late Account crop;

  LocalLedger get ledger => s.ledger;

  Future<void> load() async {
    chart = await ledger.chartOf(bookId);
    bank = _named('Business Cash');
    amrit = _named('Amrit');
    sukhdev = _named('Sukhdev');
    harjit = _named('Harjit');
    seed = _named('Seed');
    crop = _named('Crop');
  }

  Account _named(String name) =>
      chart.accounts.firstWhere((a) => a.name.startsWith(name));

  Future<Entry> post(
    List<Line> lines, {
    required EntryKind kind,
    LocalDate? date,
  }) => ledger.post(
    Entry(
      id: '',
      bookId: bookId,
      kind: kind,
      status: EntryStatus.posted,
      reviewRequired: false,
      accountingDate: date ?? ledger.today(),
      lines: lines,
      createdByUser: ledger.identity.userId,
      createdByDevice: ledger.identity.deviceId,
      hlc: const Hlc(0),
    ),
  );

  /// Costs from three pockets, one harvest banked: ₹5,94,000 of profit in the
  /// open FY and ₹9,79,000 of money in the bank.
  Future<void> season() async {
    await post(
      Verbs.partnerPaidCost(
        partner: amrit,
        expense: seed,
        amount: const Paise(1_80_000_00),
      ),
      kind: EntryKind.tookCredit,
      date: ledger.today().addDays(-6),
    );
    await post(
      Verbs.partnerPaidCost(
        partner: sukhdev,
        expense: seed,
        amount: const Paise(95_000_00),
      ),
      kind: EntryKind.tookCredit,
      date: ledger.today().addDays(-6),
    );
    await post(
      Verbs.partnerPaidCost(
        partner: harjit,
        expense: seed,
        amount: const Paise(60_000_00),
      ),
      kind: EntryKind.tookCredit,
      date: ledger.today().addDays(-6),
    );
    await post(
      Verbs.moneyIn(into: bank, from: crop, amount: const Paise(9_29_000_00)),
      kind: EntryKind.moneyIn,
      date: ledger.today().addDays(-1),
    );
  }
}

Future<Farm> kaurFarm(
  SeededLedger s, {
  List<int> shares = const [1, 1, 1],
  List<String> members = const ['m-amrit', 'm-sukhdev', 'm-harjit'],
  data.BookOwnership ownership = data.BookOwnership.shared,
  LocalDate? startDate,
}) async {
  final bookId = await s.ledger.createBook(
    name: 'Kaur Family Agriculture',
    type: BookType.business,
    ownership: ownership,
    ownerNames: const ['Amrit Kaur', 'Sukhdev Singh', 'Harjit Kaur'],
    ownerShares: shares,
    ownerMemberIds: members,
    startDate: startDate ?? s.ledger.today().addDays(-7),
    categories: const [
      SeedCategory('Seed & Fertiliser', AccountClass.categoryExpense),
      SeedCategory('Crop Sale', AccountClass.categoryIncome),
    ],
  );
  final farm = Farm(s, bookId, members);
  await farm.load();
  return farm;
}

void main() {
  late SeededLedger s;

  setUp(() async {
    s = await seedSoloLedger();
  });

  group('the preview is the engine\'s own arithmetic (02 §7.1 🔒)', () {
    test('F1-02-52 net profit is the open FY\'s figure, the split is the '
        'engine\'s lines, and interest is off by default', () async {
      final farm = await kaurFarm(s);
      await farm.season();
      final preview = await s.ledger.distributionPreview(farm.bookId);

      expect(preview.netProfit, const Paise(5_94_000_00));
      expect(preview.refusal, isNull);
      expect(preview.interestEnabled, isFalse, reason: '02 §7.1 🔒 default');
      expect(preview.interest, isEmpty);
      expect(preview.shares.map((r) => r.name), [
        farm.amrit.name,
        farm.sukhdev.name,
        farm.harjit.name,
      ], reason: 'creation order — the 02 §7.1 🔒 tie-break keys on it');
      expect(preview.shares.map((r) => r.share), [
        const Paise(1_98_000_00),
        const Paise(1_98_000_00),
        const Paise(1_98_000_00),
      ]);
      expect(preview.shares.map((r) => r.interest), everyElement(Paise.zero));
      expect(preview.shareTotal, preview.netProfit);
      expect(preview.isLoss, isFalse);

      // The lines are `Verbs.profitDistribution`'s, unchanged.
      expect(
        preview.lines,
        Verbs.profitDistribution(
          profitDistributed: farm.chart.accounts.firstWhere(
            (a) => a.systemRole == SystemRole.profitDistributed,
          ),
          partners: [
            PartnerShare(account: farm.amrit, ratio: 1),
            PartnerShare(account: farm.sukhdev, ratio: 1),
            PartnerShare(account: farm.harjit, ratio: 1),
          ],
          netProfit: const Paise(5_94_000_00),
        ),
      );
      expect(
        Paise.sum([for (final l in preview.lines) l.amount]),
        Paise.zero,
        reason: '02 §1.4 sum-to-zero',
      );
    });

    test('F1-02-53 the remainder is the engine\'s: an odd amount on a 2:1:1 '
        'ratio lands on the largest weight, and the facade never re-divides '
        '(02 §7.1 🔒 rounding rule)', () async {
      final farm = await kaurFarm(s, shares: const [2, 1, 1]);
      await farm.post(
        Verbs.moneyIn(
          into: farm.bank,
          from: farm.crop,
          amount: const Paise(1_00_000_01),
        ),
        kind: EntryKind.moneyIn,
      );
      final preview = await s.ledger.distributionPreview(farm.bookId);

      expect(preview.netProfit, const Paise(1_00_000_01));
      final split = splitByRatio(const Paise(1_00_000_01), const [2, 1, 1]);
      expect(
        preview.shares.map((r) => r.share),
        split,
        reason: 'exactly splitByRatio — no second implementation exists',
      );
      expect(preview.shareTotal, preview.netProfit);
      expect(preview.shares.map((r) => r.ratioWeight), [2, 1, 1]);
    });

    test('F1-02-54 a loss is the mirror posting the engine builds, same ratio, '
        'same remainder (ADR 2026-09-05e §8)', () async {
      final farm = await kaurFarm(s);
      // Costs only: the FY is ₹3,35,000 in deficit.
      await farm.post(
        Verbs.partnerPaidCost(
          partner: farm.amrit,
          expense: farm.seed,
          amount: const Paise(3_35_000_00),
        ),
        kind: EntryKind.tookCredit,
      );
      final preview = await s.ledger.distributionPreview(farm.bookId);

      expect(preview.isLoss, isTrue);
      expect(preview.netProfit, const Paise(-3_35_000_00));
      expect(
        preview.refusal,
        isNull,
        reason: 'the ceiling does not bite a loss',
      );
      // Dr each Partner Current · Cr Profit Distributed — the mirror.
      expect(
        preview.lines.first.amount,
        const Paise(-3_35_000_00),
        reason: 'Profit Distributed is credited on a loss',
      );
      expect(
        preview.shares.map((r) => r.share),
        splitByRatio(const Paise(-3_35_000_00), const [1, 1, 1]),
      );
      expect(preview.shareTotal, preview.netProfit);
    });
  });

  group('interest on capital (02 §7.1 🔒)', () {
    /// Turns interest on through the two layers ADR 2026-09-14b §2 names: an
    /// approved `interest_on_capital` request, then the dated record naming it.
    Future<void> enableInterest(Farm farm, {required int rateBp}) async {
      final settings = <String, Object?>{
        interestOnCapitalKey: true,
        interestOnCapitalRateKey: rateBp,
      };
      final request = await farm.ledger.authorStructural(
        (hlc, id) => StructuralRequest(
          id: id,
          bookId: farm.bookId,
          hlc: hlc,
          action: StructuralAction.interestOnCapital,
          byUser: farm.memberIds.first,
          ownerSetVersion: 1,
          payload: settings,
        ),
      );
      for (final member in farm.memberIds) {
        await farm.ledger.authorStructural(
          (hlc, id) => StructuralApproval(
            id: id,
            bookId: farm.bookId,
            hlc: hlc,
            requestId: request.id,
            byUser: member,
            ownerSetVersion: 1,
          ),
        );
      }
      await farm.ledger.authorBusinessSetting(
        bookId: farm.bookId,
        requestId: request.id,
        settings: settings,
      );
    }

    test('F1-02-55 off by default, and on only through an approved dated '
        'record — both lines per partner then, interest first', () async {
      final farm = await kaurFarm(s);
      await farm.season();
      expect(
        (await s.ledger.distributionPreview(farm.bookId)).interestEnabled,
        isFalse,
      );

      await enableInterest(farm, rateBp: 800);
      final preview = await s.ledger.distributionPreview(farm.bookId);
      expect(preview.interestEnabled, isTrue);
      expect(preview.rateBasisPoints, 800);

      // The figures are `interestOnCapital`'s, to the paisa.
      final report = await s.ledger.rebuild(farm.bookId);
      final engine = interestOnCapital(
        report.state,
        report.chart,
        partners: [
          PartnerShare(account: farm.amrit, ratio: 1),
          PartnerShare(account: farm.sukhdev, ratio: 1),
          PartnerShare(account: farm.harjit, ratio: 1),
        ],
        from: preview.from,
        to: preview.to,
        rateBasisPoints: 800,
      );
      expect(preview.interest, engine);
      for (final row in preview.shares) {
        expect(row.interest, engine[row.accountId]);
      }
      // Interest first, then the remainder splits by the ratio (02 §7.1 🔒).
      expect(preview.interestTotal + preview.shareTotal, preview.netProfit);
      expect(
        preview.lines.where((l) => l.tag == 'interest').length,
        preview.interest.values.where((v) => !v.isZero).length,
      );
      expect(
        preview.lines.indexWhere((l) => l.tag == 'share') >
            preview.lines.indexWhere((l) => l.tag == 'interest'),
        isTrue,
        reason: 'interest is credited before the ratio split',
      );
    });
  });

  group('the ratio in force, not the deed (ADR 2026-09-14b §6)', () {
    test('F1-02-56 an approved ratio change moves the split; the deed keeps '
        'the ratio agreed at creation', () async {
      final farm = await kaurFarm(s);
      await farm.season();
      expect(
        (await s.ledger.distributionPreview(farm.bookId)).shares
            .map((r) => r.ratioWeight),
        [1, 1, 1],
      );

      final newRatio = <String, Object?>{
        'partner_shares': {
          farm.amrit.id: 2,
          farm.sukhdev.id: 1,
          farm.harjit.id: 1,
        },
      };
      final request = await s.ledger.authorStructural(
        (hlc, id) => StructuralRequest(
          id: id,
          bookId: farm.bookId,
          hlc: hlc,
          action: StructuralAction.ownershipRatio,
          byUser: farm.memberIds.first,
          ownerSetVersion: 1,
          payload: newRatio,
        ),
      );
      for (final member in farm.memberIds) {
        await s.ledger.authorStructural(
          (hlc, id) => StructuralApproval(
            id: id,
            bookId: farm.bookId,
            hlc: hlc,
            requestId: request.id,
            byUser: member,
            ownerSetVersion: 1,
          ),
        );
      }
      await s.ledger.authorBusinessSetting(
        bookId: farm.bookId,
        requestId: request.id,
        settings: newRatio,
      );

      final after = await s.ledger.distributionPreview(farm.bookId);
      expect(after.shares.map((r) => r.ratioWeight), [2, 1, 1]);
      expect(
        after.shares.map((r) => r.share),
        splitByRatio(const Paise(5_94_000_00), const [2, 1, 1]),
      );
      // The deed is unmoved: it is the ratio agreed at creation (§2, §4).
      final deed = await s.ledger.configOf(farm.bookId);
      expect(deed!.partnerShares.values, [1, 1, 1]);
    });

    test('F1-02-57 an unauthorised business_setting refuses the distribution '
        'rather than falling back to the deed (ADR 2026-09-14b §5)', () async {
      final farm = await kaurFarm(s);
      await farm.season();
      // No request, no approvals: the reader quarantines the record.
      await s.ledger.authorBusinessSetting(
        bookId: farm.bookId,
        requestId: 'never-approved',
        settings: {
          'partner_shares': {farm.amrit.id: 9},
        },
      );
      final preview = await s.ledger.distributionPreview(farm.bookId);
      expect(preview.refusal, DistributionRefusal.termsUnverified);
      expect(preview.lines, isEmpty);
      expect(
        () => s.ledger.proposeDistribution(farm.bookId),
        throwsA(
          isA<DistributionRefused>().having(
            (e) => e.refusal,
            'refusal',
            DistributionRefusal.termsUnverified,
          ),
        ),
      );
    });

    test('F1-02-58 no ratio recorded is *not recorded*, never equal shares, '
        'and nothing is divided (02 §7.1 🔒)', () async {
      final farm = await kaurFarm(s, shares: const []);
      await farm.season();
      final preview = await s.ledger.distributionPreview(farm.bookId);
      expect(preview.refusal, DistributionRefusal.ratioNotRecorded);
      expect(preview.shares, isEmpty);
      expect(preview.lines, isEmpty);

      // A *Just me* business never hears the word at all (ADR 2026-09-09b 🔒).
      final solo = await s.ledger.createBook(
        name: 'Singh Kirana',
        type: BookType.business,
      );
      expect(
        (await s.ledger.distributionPreview(solo)).refusal,
        DistributionRefusal.notShared,
      );
    });
  });

  group('the ceiling and the quorum (ADR 2026-09-05e §8; 02 §7.2.1 🔒)', () {
    test('F1-02-59 a proposal over accumulated surplus is refused and says by '
        'how much; a shared book proposes and applies nothing; a single-owner '
        'book posts the one multi-line entry', () async {
      final farm = await kaurFarm(s);
      await farm.season();

      final first = await s.ledger.proposeDistribution(farm.bookId);
      expect(
        first,
        isA<DistributionProposed>(),
        reason: 'three owners, all-owners quorum: nothing is applied early',
      );
      final proposed = (first as DistributionProposed).request;
      expect(proposed.action, StructuralAction.profitDistribution);
      expect(proposed.ownerSetVersion, 1);
      expect(
        (proposed.payload['lines']! as List).length,
        4,
        reason: 'Profit Distributed + one line per owner',
      );
      expect(proposed.payload['net_profit_paise'], 5_94_000_00);
      // Applied nothing: no entry, and the balances have not moved.
      final report = await s.ledger.rebuild(farm.bookId);
      expect(report.state.balances[farm.amrit.id], const Paise(-1_80_000_00));

      // The ceiling (ADR 2026-09-05e §8): a year in profit standing on a
      // deficit carried in from the year before. This FY earns ₹1,00,000, the
      // accumulated surplus is ₹2,00,000 in deficit, so nothing may go out and
      // the refusal says by how much.
      final carried = await kaurFarm(s, startDate: LocalDate(2025, 4, 1));
      await carried.post(
        Verbs.partnerPaidCost(
          partner: carried.amrit,
          expense: carried.seed,
          amount: const Paise(2_00_000_00),
        ),
        kind: EntryKind.tookCredit,
        date: LocalDate(2026, 1, 15),
      );
      await carried.post(
        Verbs.moneyIn(
          into: carried.bank,
          from: carried.crop,
          amount: const Paise(1_00_000_00),
        ),
        kind: EntryKind.moneyIn,
      );
      final over = await s.ledger.distributionPreview(carried.bookId);
      expect(over.netProfit, const Paise(1_00_000_00));
      expect(over.headroom, const Paise(-1_00_000_00));
      expect(over.refusal, DistributionRefusal.ceiling);
      expect(
        over.excess,
        const Paise(2_00_000_00),
        reason: '02 §7.1 🔒 — the wizard refuses and says by how much',
      );
      expect(
        () => s.ledger.proposeDistribution(carried.bookId),
        throwsA(
          isA<DistributionRefused>()
              .having((e) => e.refusal, 'refusal', DistributionRefusal.ceiling)
              .having((e) => e.excess, 'excess', const Paise(2_00_000_00)),
        ),
      );

      // A single-owner shared book is a quorum of one and posts now.
      final soleId = await s.ledger.createBook(
        name: 'Amrit Dairy',
        type: BookType.business,
        ownership: data.BookOwnership.shared,
        ownerNames: const ['Amrit Kaur'],
        ownerShares: const [1],
        ownerMemberIds: const ['m-amrit'],
        startDate: s.ledger.today().addDays(-7),
        categories: const [
          SeedCategory('Feed', AccountClass.categoryExpense),
          SeedCategory('Milk', AccountClass.categoryIncome),
        ],
      );
      final soleChart = await s.ledger.chartOf(soleId);
      await s.ledger.post(
        Entry(
          id: '',
          bookId: soleId,
          kind: EntryKind.moneyIn,
          status: EntryStatus.posted,
          reviewRequired: false,
          accountingDate: s.ledger.today(),
          lines: Verbs.moneyIn(
            into: soleChart.accounts.firstWhere((a) => a.isMoney),
            from: soleChart.accounts.firstWhere((a) => a.name == 'Milk'),
            amount: const Paise(40_000_00),
          ),
          createdByUser: s.ledger.identity.userId,
          createdByDevice: s.ledger.identity.deviceId,
          hlc: const Hlc(0),
        ),
      );
      final sole = await s.ledger.distributionPreview(soleId);
      expect(sole.quorumOfOne, isTrue);
      expect(sole.approvalsRequired, 1);
      final posted = await s.ledger.proposeDistribution(soleId);
      expect(posted, isA<DistributionPosted>());
      final entry = (posted as DistributionPosted).entry;
      expect(entry.kind, EntryKind.adjustment);
      expect(entry.lines, sole.lines);

      // Now the ceiling: the same book cannot hand out the same surplus twice.
      final again = await s.ledger.distributionPreview(soleId);
      expect(again.refusal, DistributionRefusal.nothingToDistribute);
    });
  });
}
