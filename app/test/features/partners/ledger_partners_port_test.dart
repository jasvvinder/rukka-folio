// F1-02-40…46: [LedgerPartnersPort] over a real `LocalLedger` — 02 §7.1 🔒.
//
// The book is the Kaur Family Agriculture worked example the engine's own
// A-02-62…67 pin, so a figure here and a figure there mean the same thing.
// Synthetic data (CLAUDE.md rule 4); in-memory SQLite, injected clock.
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' as data show BookOwnership;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/partners/ledger_partners_port.dart';
import 'package:rukka_folio/features/partners/partners_port.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

/// The farm after its season: three owners, costs paid from three pockets, a
/// harvest banked, one drawing, and the profit distributed.
final class Farm {
  Farm(this.s, this.bookId);

  final SeededLedger s;
  final String bookId;

  late Chart chart;
  late Account bank;
  late Account amrit;
  late Account sukhdev;
  late Account harjit;
  late Account seed;
  late Account profitDistributed;

  LocalLedger get ledger => s.ledger;

  Account named(String name) =>
      chart.accounts.firstWhere((a) => a.name.startsWith(name));

  Future<void> load() async {
    chart = await ledger.chartOf(bookId);
    bank = named('Business Cash');
    amrit = named('Amrit');
    sukhdev = named('Sukhdev');
    harjit = named('Harjit');
    seed = named('Seed');
    profitDistributed = named('Profit Distributed');
  }

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

  Future<void> season() async {
    await post(
      Verbs.partnerPaidCost(
        partner: amrit,
        expense: seed,
        amount: const Paise(1_80_000_00),
      ),
      kind: EntryKind.tookCredit,
    );
    await post(
      Verbs.partnerPaidCost(
        partner: sukhdev,
        expense: seed,
        amount: const Paise(95_000_00),
      ),
      kind: EntryKind.tookCredit,
    );
    await post(
      Verbs.partnerPaidCost(
        partner: harjit,
        expense: seed,
        amount: const Paise(60_000_00),
      ),
      kind: EntryKind.tookCredit,
    );
    await post(
      Verbs.moneyIn(
        into: bank,
        from: named('Crop'),
        amount: const Paise(9_79_000_00),
      ),
      kind: EntryKind.moneyIn,
    );
    await post(
      Verbs.partnerDrawing(
        partner: amrit,
        from: bank,
        amount: const Paise(50_000_00),
      ),
      kind: EntryKind.moneyOut,
    );
    await post(
      Verbs.profitDistribution(
        profitDistributed: profitDistributed,
        partners: [
          PartnerShare(account: amrit, ratio: 1),
          PartnerShare(account: sukhdev, ratio: 1),
          PartnerShare(account: harjit, ratio: 1),
        ],
        netProfit: const Paise(5_94_000_00),
      ),
      kind: EntryKind.adjustment,
    );
  }
}

Future<Farm> kaurFarm(
  SeededLedger s, {
  List<int> shares = const [1, 1, 1],
}) async {
  final bookId = await s.ledger.createBook(
    name: 'Kaur Family Agriculture',
    type: BookType.business,
    ownership: data.BookOwnership.shared,
    ownerNames: const ['Amrit Kaur', 'Sukhdev Singh', 'Harjit Kaur'],
    ownerShares: shares,
    categories: const [
      SeedCategory('Seed & Fertiliser', AccountClass.categoryExpense),
      SeedCategory('Crop Sale', AccountClass.categoryIncome),
    ],
  );
  final farm = Farm(s, bookId);
  await farm.load();
  return farm;
}

void main() {
  late SeededLedger s;
  late PartnersPort port;

  setUp(() async {
    s = await seedSoloLedger();
    port = LedgerPartnersPort(s.ledger);
  });

  test('F1-02-40 the view is the engine\'s own derivations plus names: the '
      'three events split per owner, capacity as A-02-65 states it', () async {
    final farm = await kaurFarm(s);
    await farm.season();
    final view = await port.watch(farm.bookId).first;

    expect(view.ownership, BookOwnership.shared);
    expect(view.positions.map((p) => p.name), [
      'Amrit Kaur — Partner Current A/c',
      'Sukhdev Singh — Partner Current A/c',
      'Harjit Kaur — Partner Current A/c',
    ], reason: 'creation order — 02 §7.1 🔒 ties break on it');

    final amrit = view.positions.first;
    expect(amrit.putIn, const Paise(1_80_000_00));
    expect(amrit.tookOut, const Paise(50_000_00));
    expect(amrit.share, const Paise(1_98_000_00));
    expect(amrit.other, Paise.zero);
    expect(amrit.net, const Paise(3_28_000_00));
    expect(amrit.ratioWeight, 1, reason: 'the weight recorded at creation');

    expect(view.canSettleAll, isTrue);
    expect(view.moneyTotal, const Paise(9_29_000_00));
    expect(view.partnerCreditTotal, const Paise(8_79_000_00));
    expect(view.shortBy, Paise.zero);
  });

  test('F1-02-41 an absent partner_shares map is *not recorded*, never '
      '*equal* (02 §7.1 🔒)', () async {
    final farm = await kaurFarm(s, shares: const []);
    await farm.season();
    final view = await port.watch(farm.bookId).first;
    expect(view.positions.map((p) => p.ratioWeight), everyElement(isNull));
  });

  test('F1-02-42 a *Just me* business has no positions and no ratio — the '
      'screen never says the word partner (02 §7.1 🔒)', () async {
    final bookId = await s.ledger.createBook(
      name: 'Singh Kirana',
      type: BookType.business,
    );
    final view = await port.watch(bookId).first;
    expect(view.ownership, BookOwnership.justMe);
    expect(view.positions, isEmpty);
    expect(view.partnerCreditTotal, Paise.zero);
  });

  test('F1-02-43 pay out posts Dr Partner Current · Cr money, and the stream '
      'carries the new position (02 §7.1 settlement route 1 🔒)', () async {
    final farm = await kaurFarm(s);
    await farm.season();
    final views = <PartnersView>[];
    final sub = port.watch(farm.bookId).listen(views.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await port.payOut(
      bookId: farm.bookId,
      partnerAccountId: farm.amrit.id,
      fromAccountId: farm.bank.id,
      amount: const Paise(1_00_000_00),
    );
    await pumpEventQueue();

    final latest = views.last;
    final amrit = latest.positions.first;
    expect(amrit.tookOut, const Paise(1_50_000_00), reason: '50k + 100k');
    expect(amrit.net, const Paise(2_28_000_00));
    expect(latest.moneyTotal, const Paise(8_29_000_00));
  });

  test(
    'F1-02-44 a partner-to-partner settlement posts Dr over-funded · Cr '
    'under-funded (02 §7.1 settlement route 2 🔒)',
    () async {
      final farm = await kaurFarm(s);
      await farm.season();
      await port.settleBetweenPartners(
        bookId: farm.bookId,
        fromPartnerAccountId: farm.amrit.id,
        toPartnerAccountId: farm.harjit.id,
        amount: const Paise(35_000_00),
      );
      final view = await port.watch(farm.bookId).first;
      expect(view.positions.first.net, const Paise(2_93_000_00));
      expect(view.positions.last.net, const Paise(2_93_000_00));
    },
    skip:
        'BLOCKED on the engine: `checkShape` admits no EntryKind for '
        'Dr partner · Cr partner, so `post` refuses the 🔒 posting 02 §7.1 '
        'names. Needs a Verbs.partnerSettlement builder + a shape rule (an '
        'engine ruling, not a UI lane\'s call) — see the M8-U5e lane report.',
  );

  test('F1-02-45 no drift margin is configured, so no partner is above one '
      'and the S14.2 card stays off ⚠️ SPEC', () async {
    final farm = await kaurFarm(s);
    await farm.season();
    final view = await port.watch(farm.bookId).first;
    expect(view.driftMargin, isNull);
    expect(view.drift, isEmpty);
    expect(view.hasDrift, isFalse);
  });

  test('F1-02-46 the pay-out door offers the book\'s money accounts, and a '
      'collection account is never one of them (02 §8.2 🔒)', () async {
    final farm = await kaurFarm(s);
    await farm.season();
    await s.ledger.addAccount(
      farm.bookId,
      name: 'Donation Box',
      accountClass: AccountClass.money,
      subtype: MoneySubtype.cashCollection,
    );
    final view = await port.watch(farm.bookId).first;
    expect(view.sources.map((x) => x.name), ['Business Cash A/c']);
    expect(view.sources.single.balance, const Paise(9_29_000_00));
  });
}
