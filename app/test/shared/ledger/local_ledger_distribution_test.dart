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
//
// E-200-31…35 — **who signed** (02 §7.2.1 🔒: *each approval is authored on
// that owner's own device, so the server cannot manufacture one*). Every
// ledger here is wired the way `bootstrap.dart` wires it (`wireLedgerTrust`
// over the trust store the root builds), and another owner's approval
// reaches it only from that owner's own certified phone, chain-verified into
// the mirror as a pull would (structural_fixture.dart). Until TRUSTWIRE the
// tests below authored every owner's approval on *this* device and passed —
// they encoded the hole, and now go red if it reopens.
//
// E-200-37…39 — **who signed, after a removal and a relaunch** (03 *Deletion
// mechanics* 🔒 — *the signature chain still verifies on every device*;
// review TRUSTWIRE-1, -2). The server never serves a removed member's
// certificate again (`rf.device_visible`), and the engine keeps certificates
// in memory only, so each relaunch here is a real one: a new `LocalLedger`
// over the same database and key store, and a trust store rebuilt from what
// meta would serve. A certificate is retained the way production retains
// it: a structural read through the view `wireLedgerTrust` installs (the
// Inbox makes one whenever `envelopes_local` changes) offers each certificate
// the live store answers to `retainPeerCert` — F1-200-32 pins the view.
import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' as data show BookOwnership, EnvelopeRecord;
import 'package:data/data.dart' show StructuralQuarantineReason;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/bootstrap.dart' show wireLedgerTrust;
import 'package:rukka_folio/shared/ledger/device_certification.dart'
    show decodeRetainedCerts;
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart' show FakeKeyStore;
import 'package:sync_engine/sync_engine.dart' as eng;

import '../../features/inbox/structural_fixture.dart' as fx;
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

/// The farm's owners as real people: this phone's user (Amrit's partner A/c)
/// and the two whose phones are elsewhere (canonical uuids, as a device
/// certificate names its user — 04 §3.4).
List<String> realOwners(SeededLedger s) => [
  s.ledger.identity.userId,
  fx.sukhdev,
  fx.harjit,
];

/// The other owners' own phones and what they send, over the trust store the
/// composition root builds.
final class Phones {
  Phones(this.book, this.trust);

  /// The farm as structural_fixture.dart addresses a book.
  final fx.SharedBook book;

  /// `eng.RecordTrustStore(umks: eng.BoundUmkSource(ledger.binding))`.
  final eng.RecordTrustStore trust;

  /// User id → that user's own certified phone.
  final Map<String, fx.RemotePhone> of = {};

  var _seq = 0;
  final _authorSeq = <String, int>{};

  /// A phone for [userId]: a UMK verified by a ceremony on this phone, a
  /// device it certified, the certificate filed as the meta pull files it.
  Future<fx.RemotePhone> add(String userId) async {
    final phone = await fx.remotePhone(book, userId);
    phone.fileCertIn(trust);
    return of[userId] = phone;
  }

  /// [event] signed on [phone] and pulled into the mirror — `verified` only
  /// because the chain held at receipt (fixture `receiveFrom`). With
  /// [objectId], the envelope carries that object id instead of the
  /// payload's own (a record the Inbox refuses `notThisObject`).
  Future<void> send(
    fx.RemotePhone phone,
    StructuralEvent event, {
    String? objectId,
  }) async {
    final authorSeq = _authorSeq.update(
      phone.deviceId,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    final ok = objectId == null
        ? await fx.receiveFrom(
            book,
            phone,
            event,
            trust: trust,
            authorSeq: authorSeq,
            seq: ++_seq,
          )
        : await _receiveAs(phone, event, objectId, authorSeq, ++_seq);
    expect(ok, isTrue, reason: 'the chain holds for ${phone.userId}\'s phone');
  }

  /// structural_fixture.dart's `receiveFrom`, with the envelope's object id
  /// set apart from the payload's — sealed and signed on [phone] all the
  /// same, verified by the chain at receipt as a pull verifies it.
  Future<bool> _receiveAs(
    fx.RemotePhone phone,
    StructuralEvent event,
    String objectId,
    int authorSeq,
    int seq,
  ) async {
    final l = book.ledger;
    final keys = l.keyMaterial.bookKeys;
    final version = keys.highestVersion(book.bookId)!;
    final env = EnvelopeBuilder.seal(
      l.suite,
      tenantId: keys.tenantIdOf(book.bookId)!,
      bookId: book.bookId,
      objectId: objectId,
      objectType: 'structural_approval',
      envelopeId: l.newId(),
      hlc: event.hlc.raw,
      authorSeq: authorSeq,
      object: encodeStructuralEvent(event),
      bookKey: keys.bookKey(
        BookKeyRef(bookId: book.bookId, keyVersion: version),
      )!,
      author: phone.device,
    );
    final hash = env.blobHash(l.suite);
    final ok = ChainVerifier(
      l.suite,
      trust,
    ).verifyEnvelope(env, seq: seq, expectedBlobHash: hash) is ChainVerified;
    await l.mirror.append(
      data.EnvelopeRecord(
        envelopeId: env.envelopeId,
        bookId: book.bookId,
        objectId: objectId,
        objectType: 'structural_approval',
        keyVersion: version,
        hlc: event.hlc.raw,
        authorDevice: phone.deviceId,
        authorSeq: authorSeq,
        blob: env.blob,
        blobHash: hash,
        seq: seq,
        verified: ok,
      ),
    );
    return ok;
  }
}

/// [farm] with Sukhdev's and Harjit's own phones.
Future<Phones> phonesFor(
  Farm farm,
  TestClock clock,
  eng.RecordTrustStore trust,
) async {
  final phones = Phones(
    fx.SharedBook(farm.ledger, clock, farm.bookId, farm.chart),
    trust,
  );
  await phones.add(fx.sukhdev);
  await phones.add(fx.harjit);
  return phones;
}

/// The two layers ADR 2026-09-14b §2 names: a structural request raised and
/// approved on this phone by its own user, the other owners' approvals each
/// signed on the phone [signedOn] names for them (default: their own), then
/// the dated `business_setting` naming the request. Returns the request.
Future<StructuralRequest> approveAndRecord(
  Farm farm,
  Phones phones,
  TestClock clock, {
  required StructuralAction action,
  required Map<String, Object?> settings,
  Map<String, fx.RemotePhone> signedOn = const {},
  Future<void> Function(fx.RemotePhone phone, StructuralApproval approval)?
  deliver,
}) async {
  final me = farm.ledger.identity.userId;
  final request = await farm.ledger.authorStructural(
    (hlc, id) => StructuralRequest(
      id: id,
      bookId: farm.bookId,
      hlc: hlc,
      action: action,
      byUser: me,
      ownerSetVersion: 1,
      payload: settings,
    ),
  );
  await farm.ledger.authorStructural(
    (hlc, id) => StructuralApproval(
      id: id,
      bookId: farm.bookId,
      hlc: hlc,
      requestId: request.id,
      byUser: me,
      ownerSetVersion: 1,
    ),
  );
  var minutes = 0;
  for (final owner in [fx.sukhdev, fx.harjit]) {
    final phone = signedOn[owner] ?? phones.of[owner]!;
    final approval = fx.approvalOf(
      phones.book,
      request,
      owner,
      minutes: ++minutes,
    );
    await (deliver ?? phones.send)(phone, approval);
  }
  clock.advance(const Duration(minutes: 10));
  await farm.ledger.authorBusinessSetting(
    bookId: farm.bookId,
    requestId: request.id,
    settings: settings,
  );
  return request;
}

/// A 2:1:1 ratio for [farm] (Amrit's A/c first).
Map<String, Object?> twoOneOne(Farm farm) => {
  'partner_shares': {farm.amrit.id: 2, farm.sukhdev.id: 1, farm.harjit.id: 1},
};

/// A relaunch of [ledger]: disposed, and a new [LocalLedger] opened over the
/// same database and key store, as the composition root opens it at the next
/// launch. Wired over [trust] — what this launch's meta serves.
Future<LocalLedger> relaunch(
  LocalLedger ledger,
  TestClock clock, {
  required void Function(eng.RecordTrustStore trust) meta,
}) async {
  final keys = ledger.keys as FakeKeyStore;
  final db = ledger.db;
  ledger.dispose();
  final again = await openTestLedger(now: clock.call, keys: keys, db: db);
  await again.bootstrapSolo();
  final trust = eng.RecordTrustStore(umks: eng.BoundUmkSource(again.binding));
  meta(trust);
  wireLedgerTrust(again, trust, again.suite);
  return again;
}

void main() {
  late SeededLedger s;
  late TestClock clock;
  late eng.RecordTrustStore trust;

  setUp(() async {
    clock = TestClock();
    s = await seedSoloLedger(clock: clock.call);
    // The composition root's trust store and wiring (bootstrap.dart), so the
    // signer every structural read asks is the one production asks.
    trust = eng.RecordTrustStore(umks: eng.BoundUmkSource(s.ledger.binding));
    wireLedgerTrust(s.ledger, trust, s.ledger.suite);
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
    /// `interest_on_capital` request every owner approved **on their own
    /// certified phone**, then the dated record naming it.
    Future<void> enableInterest(Farm farm, {required int rateBp}) async {
      await approveAndRecord(
        farm,
        await phonesFor(farm, clock, trust),
        clock,
        action: StructuralAction.interestOnCapital,
        settings: {
          interestOnCapitalKey: true,
          interestOnCapitalRateKey: rateBp,
        },
      );
    }

    test('F1-02-55 off by default, and on only through an approved dated '
        'record — both lines per partner then, interest first', () async {
      final farm = await kaurFarm(s, members: realOwners(s));
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
      final farm = await kaurFarm(s, members: realOwners(s));
      await farm.season();
      expect(
        (await s.ledger.distributionPreview(farm.bookId)).shares
            .map((r) => r.ratioWeight),
        [1, 1, 1],
      );

      await approveAndRecord(
        farm,
        await phonesFor(farm, clock, trust),
        clock,
        action: StructuralAction.ownershipRatio,
        settings: twoOneOne(farm),
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

  group('who signed is the certified device, never the by_user claim '
      '(02 §7.2.1 🔒; TRUST200 hand-off)', () {
    test('E-200-31 an approval naming owner B but signed on someone else\'s '
        'certified phone is not counted: the ratio change does not apply and '
        'the distribution refuses rather than read the deed', () async {
      // Two forgers, each a certified phone whose envelope the chain verified
      // at receipt: another owner (Harjit) and a member who owns nothing
      // (Ramesh). Each signs "Sukhdev approves"; Sukhdev never does.
      for (final forger in [fx.harjit, fx.ramesh]) {
        final farm = await kaurFarm(s, members: realOwners(s));
        await farm.season();
        final phones = await phonesFor(farm, clock, trust);
        final forging = phones.of[forger] ?? await phones.add(forger);

        await approveAndRecord(
          farm,
          phones,
          clock,
          action: StructuralAction.ownershipRatio,
          settings: twoOneOne(farm),
          signedOn: {fx.sukhdev: forging},
        );

        final reading = await s.ledger.structuralStateOf(farm.bookId);
        expect(
          reading.recordRefusals.map((q) => q.reason),
          contains(StructuralQuarantineReason.signerNotBound),
          reason: '$forger\'s phone is certified to $forger, not Sukhdev',
        );
        expect(
          reading.signersConfirmed,
          isTrue,
          reason: 'every signer is known — one simply is not who it claims',
        );
        expect(reading.settings.applied, isEmpty);
        expect(reading.partnerShares.values, [1, 1, 1], reason: 'the deed');

        final preview = await s.ledger.distributionPreview(farm.bookId);
        expect(
          preview.refusal,
          DistributionRefusal.termsUnverified,
          reason: 'the dated record names a request that never reached quorum',
        );
        expect(
          preview.signersUnconfirmed,
          isFalse,
          reason: 'a forged signer is a verdict, not a wait for sync',
        );
        expect(preview.lines, isEmpty);
        expect(preview.shares, isEmpty);
      }
    });

    test('E-200-32 positive control: the same change, each owner approving '
        'on their own certified phone, applies — 2:1:1 to the paisa', () async {
      final farm = await kaurFarm(s, members: realOwners(s));
      await farm.season();
      await approveAndRecord(
        farm,
        await phonesFor(farm, clock, trust),
        clock,
        action: StructuralAction.ownershipRatio,
        settings: twoOneOne(farm),
      );

      final reading = await s.ledger.structuralStateOf(farm.bookId);
      expect(reading.recordRefusals, isEmpty);
      expect(reading.signersConfirmed, isTrue);
      expect(reading.quarantined, isEmpty);
      expect(reading.settings.applied, hasLength(1));

      final preview = await s.ledger.distributionPreview(farm.bookId);
      expect(preview.refusal, isNull);
      expect(preview.shares.map((r) => r.ratioWeight), [2, 1, 1]);
      expect(
        preview.shares.map((r) => r.share),
        splitByRatio(const Paise(5_94_000_00), const [2, 1, 1]),
      );
    });

    test(
      'E-200-33 an approval from a phone whose certificate this phone does '
      'not hold yet counts for nobody: signersConfirmed is false and the '
      'distribution is refused termsUnverified, told apart as a wait '
      '(signersUnconfirmed) — then applies once the certificate arrives',
      () async {
        final farm = await kaurFarm(s, members: realOwners(s));
        await farm.season();
        final phones = await phonesFor(farm, clock, trust);
        await approveAndRecord(
          farm,
          phones,
          clock,
          action: StructuralAction.ownershipRatio,
          settings: twoOneOne(farm),
        );
        // Sukhdev's certificate is not in this launch's store, and this install
        // never retained it (nothing here offered it to `retainPeerCert`): a
        // certificate this phone has never held, before the meta page that
        // brings it.
        final sukhdevs = phones.of[fx.sukhdev]!;
        trust.certs.remove(sukhdevs.deviceId);
        expect(s.ledger.retainedCertOf(sukhdevs.deviceId), isNull);

        final before = await s.ledger.structuralStateOf(farm.bookId);
        expect(before.signersConfirmed, isFalse);
        expect(
          before.recordRefusals.map((q) => q.reason),
          contains(StructuralQuarantineReason.signerUnknown),
        );
        expect(before.partnerShares.values, [1, 1, 1]);
        final refused = await s.ledger.distributionPreview(farm.bookId);
        expect(refused.refusal, DistributionRefusal.termsUnverified);
        expect(
          refused.signersUnconfirmed,
          isTrue,
          reason: 'a wait a sync ends, not the final block (07 §1 rule 6 🔒)',
        );
        expect(refused.lines, isEmpty);
        await expectLater(
          () => s.ledger.proposeDistribution(farm.bookId),
          throwsA(
            isA<DistributionRefused>()
                .having(
                  (e) => e.refusal,
                  'refusal',
                  DistributionRefusal.termsUnverified,
                )
                .having(
                  (e) => e.signersUnconfirmed,
                  'signersUnconfirmed',
                  isTrue,
                ),
          ),
        );

        // The meta page arrives: the same stored envelope now names Sukhdev.
        sukhdevs.fileCertIn(trust);
        final after = await s.ledger.structuralStateOf(farm.bookId);
        expect(after.signersConfirmed, isTrue);
        expect(after.recordRefusals, isEmpty);
        final preview = await s.ledger.distributionPreview(farm.bookId);
        expect(preview.refusal, isNull);
        expect(preview.signersUnconfirmed, isFalse);
        expect(preview.shares.map((r) => r.ratioWeight), [2, 1, 1]);
      },
    );

    test('E-200-34 a record of the book nobody here can attribute holds every '
        'distribution, even one no business_setting names: it may be the veto '
        'or the approval that decided the terms', () async {
      final farm = await kaurFarm(s, members: realOwners(s));
      await farm.season();
      final phones = await phonesFor(farm, clock, trust);
      // Sukhdev raises a ratio change on his own phone; nothing records it.
      final sukhdevs = phones.of[fx.sukhdev]!;
      clock.advance(const Duration(minutes: 1));
      await phones.send(
        sukhdevs,
        StructuralRequest(
          id: farm.ledger.newId(),
          bookId: farm.bookId,
          hlc: Hlc.compose(
            physicalMs: clock().millisecondsSinceEpoch,
            counter: 0,
          ),
          action: StructuralAction.ownershipRatio,
          byUser: fx.sukhdev,
          ownerSetVersion: 1,
          payload: twoOneOne(farm),
        ),
      );
      clock.advance(const Duration(minutes: 1));

      // A certificate this phone has never held: not in this launch's store,
      // and no read has offered it for retention yet (TRUSTWIRE-1 — once a
      // read has seen it, it is kept).
      trust.certs.remove(sukhdevs.deviceId);
      expect(s.ledger.retainedCertOf(sukhdevs.deviceId), isNull);
      final reading = await s.ledger.structuralStateOf(farm.bookId);
      expect(
        reading.quarantined,
        isEmpty,
        reason: 'the refusal below is the signers gate alone',
      );
      expect(reading.signersConfirmed, isFalse);
      final held = await s.ledger.distributionPreview(farm.bookId);
      expect(held.refusal, DistributionRefusal.termsUnverified);
      expect(held.signersUnconfirmed, isTrue);

      sukhdevs.fileCertIn(trust);
      final preview = await s.ledger.distributionPreview(farm.bookId);
      expect(
        preview.refusal,
        isNull,
        reason: 'a pending request with a known signer changes nothing',
      );
      expect(preview.shares.map((r) => r.ratioWeight), [1, 1, 1]);
    });

    test('E-200-35 a certificate relabelled after receipt (a later meta page '
        'naming a member\'s device as an owner\'s) names nobody: the signer '
        're-runs the chain at every read, never trusts the label', () async {
      final farm = await kaurFarm(s, members: realOwners(s));
      await farm.season();
      final phones = await phonesFor(farm, clock, trust);
      final ramesh = await phones.add(fx.ramesh);
      // Ramesh's phone signs "Sukhdev approves"; verified at receipt under
      // Ramesh's own certificate (the chain held — it is his envelope).
      await approveAndRecord(
        farm,
        phones,
        clock,
        action: StructuralAction.ownershipRatio,
        settings: twoOneOne(farm),
        signedOn: {fx.sukhdev: ramesh},
      );
      // His genuine certificate is retained by the read that saw his record
      // (TRUSTWIRE-1) — and the live store still answers first. The server's
      // devices row now says that device is Sukhdev's. The signature is
      // untouched (04 §3.4 does not sign the user id).
      await s.ledger.structuralStateOf(farm.bookId);
      expect(s.ledger.retainedCertOf(ramesh.deviceId), same(ramesh.cert));
      trust.certs[ramesh.deviceId] = fx.relabelled(ramesh.cert, fx.sukhdev);
      expect(trust.userOf(ramesh.deviceId), fx.sukhdev, reason: 'the label');

      final reading = await s.ledger.structuralStateOf(farm.bookId);
      expect(
        reading.recordRefusals.map((q) => q.reason),
        contains(StructuralQuarantineReason.signerUnknown),
        reason:
            'the relabelled certificate does not verify under '
            'Sukhdev\'s UMK, so nobody is named — never Sukhdev',
      );
      expect(reading.settings.applied, isEmpty);
      expect(reading.partnerShares.values, [1, 1, 1]);
      expect(
        (await s.ledger.distributionPreview(farm.bookId)).refusal,
        DistributionRefusal.termsUnverified,
      );
    });

    test('E-200-36 a record the Inbox will not show is not counted here '
        'either: an owner\'s own signed approval carried under another object '
        'id, or naming another book, completes nothing', () async {
      for (final skew in ['objectId', 'bookId']) {
        final farm = await kaurFarm(s, members: realOwners(s));
        await farm.season();
        final phones = await phonesFor(farm, clock, trust);
        await approveAndRecord(
          farm,
          phones,
          clock,
          action: StructuralAction.ownershipRatio,
          settings: twoOneOne(farm),
          deliver: (phone, approval) async {
            if (phone.userId != fx.sukhdev) return phones.send(phone, approval);
            // Sukhdev's own phone, Sukhdev's own name — only the carrier
            // is wrong.
            if (skew == 'objectId') {
              return phones.send(phone, approval, objectId: s.ledger.newId());
            }
            return phones.send(
              phone,
              StructuralApproval(
                id: approval.id,
                bookId: s.bookId,
                hlc: approval.hlc,
                requestId: approval.requestId,
                byUser: approval.byUser,
                ownerSetVersion: approval.ownerSetVersion,
              ),
            );
          },
        );

        final reading = await s.ledger.structuralStateOf(farm.bookId);
        expect(reading.settings.applied, isEmpty, reason: skew);
        expect(reading.partnerShares.values, [1, 1, 1], reason: skew);
        expect(
          (await s.ledger.distributionPreview(farm.bookId)).refusal,
          DistributionRefusal.termsUnverified,
          reason: '$skew: the record names a request still short of quorum',
        );
      }
    });
    test('E-200-37 a removed owner\'s approval still counts after a relaunch: '
        'the server never serves their certificate again, and the one this '
        'install retained when it proved their signature still names them — '
        'the ratio change they approved stays in force (03 Deletion '
        'mechanics 🔒)', () async {
      final farm = await kaurFarm(s, members: realOwners(s));
      await farm.season();
      final phones = await phonesFor(farm, clock, trust);
      await approveAndRecord(
        farm,
        phones,
        clock,
        action: StructuralAction.ownershipRatio,
        settings: twoOneOne(farm),
      );
      // The read the Inbox makes as the records arrive, while the server
      // still serves every certificate: each one is offered and kept.
      await s.ledger.structuralStateOf(farm.bookId);
      await pumpEventQueue();
      final sukhdevs = phones.of[fx.sukhdev]!;
      final harjits = phones.of[fx.harjit]!;
      expect(s.ledger.retainedCertOf(harjits.deviceId), same(harjits.cert));

      // Harjit is removed. The next launch's meta serves Sukhdev's
      // certificate, never Harjit's again (`rf.device_visible`), and the
      // signed removal — cut-off after every record he signed here.
      void meta(eng.RecordTrustStore t) {
        sukhdevs.fileCertIn(t);
        t.removals.add(
          eng.RemovalRecord(
            recordId: s.ledger.newId(),
            seq: 1000,
            removedUserId: fx.harjit,
          ),
        );
      }

      final after = await relaunch(s.ledger, clock, meta: meta);
      expect(
        after.retainedCertOf(harjits.deviceId),
        isNotNull,
        reason: 'read back from the key store at open',
      );
      final reading = await after.structuralStateOf(farm.bookId);
      expect(reading.signersConfirmed, isTrue);
      expect(reading.recordRefusals, isEmpty);
      expect(reading.quarantined, isEmpty);
      expect(reading.settings.applied, hasLength(1));
      expect(reading.partnerShares.values, [2, 1, 1]);
      final preview = await after.distributionPreview(farm.bookId);
      expect(preview.refusal, isNull);
      expect(preview.signersUnconfirmed, isFalse);
      expect(preview.shares.map((r) => r.ratioWeight), [2, 1, 1]);
      expect(
        preview.shares.map((r) => r.share),
        splitByRatio(const Paise(5_94_000_00), const [2, 1, 1]),
      );

      // The counterfactual — the defect the review found: without the
      // retained copy, the same relaunch names nobody for Harjit's records,
      // and his approval no longer completes the change.
      await (after.keys as FakeKeyStore).delete(LocalLedgerKeys.peerCerts);
      final bare = await relaunch(after, clock, meta: meta);
      expect(bare.retainedCertOf(harjits.deviceId), isNull);
      final unnamed = await bare.structuralStateOf(farm.bookId);
      expect(unnamed.signersConfirmed, isFalse);
      expect(
        unnamed.recordRefusals.map((q) => q.reason),
        contains(StructuralQuarantineReason.signerUnknown),
      );
      expect(unnamed.settings.applied, isEmpty);
      expect(
        (await bare.distributionPreview(farm.bookId)).refusal,
        DistributionRefusal.termsUnverified,
      );
    });

    test('E-200-38 the retained certificate never lets a removed owner sign '
        'after the removal: their approval at or after the removal\'s seq is '
        'cut off and counts for nobody, while the approval before it still '
        'counts (ADR 2026-09-05b §5)', () async {
      final farm = await kaurFarm(s, members: realOwners(s));
      await farm.season();
      final phones = await phonesFor(farm, clock, trust);
      await approveAndRecord(
        farm,
        phones,
        clock,
        action: StructuralAction.ownershipRatio,
        settings: twoOneOne(farm),
      );
      // The removal is filed after every record so far…
      final removalSeq = await _maxSeq(s.ledger) + 1;
      // …and Harjit's phone then approves a second change, which the chain
      // verified at receipt (the removal had not reached this phone yet).
      String? lateApproval;
      final threeOneOne = {
        'partner_shares': {
          farm.amrit.id: 3,
          farm.sukhdev.id: 1,
          farm.harjit.id: 1,
        },
      };
      await approveAndRecord(
        farm,
        phones,
        clock,
        action: StructuralAction.ownershipRatio,
        settings: threeOneOne,
        deliver: (phone, approval) async {
          if (phone.userId == fx.harjit) lateApproval = approval.id;
          await phones.send(phone, approval);
        },
      );
      expect(lateApproval, isNotNull);
      await s.ledger.structuralStateOf(farm.bookId);
      await pumpEventQueue();

      final after = await relaunch(
        s.ledger,
        clock,
        meta: (t) {
          phones.of[fx.sukhdev]!.fileCertIn(t);
          t.removals.add(
            eng.RemovalRecord(
              recordId: s.ledger.newId(),
              seq: removalSeq,
              removedUserId: fx.harjit,
            ),
          );
        },
      );
      final reading = await after.structuralStateOf(farm.bookId);
      expect(
        [
          for (final q in reading.recordRefusals)
            if (q.reason == StructuralQuarantineReason.signerUnknown)
              q.objectId,
        ],
        [lateApproval],
        reason:
            'only the approval past the removal is refused — the '
            'retained certificate is cut off by its owner\'s removal',
      );
      expect(
        reading.settings.applied,
        hasLength(1),
        reason: 'the 2:1:1 change he approved before the removal stands',
      );
      expect(reading.partnerShares.values, [2, 1, 1]);
      expect(
        (await after.distributionPreview(farm.bookId)).refusal,
        DistributionRefusal.termsUnverified,
        reason:
            'a record of the book is signed by nobody this phone can '
            'name: never a 3:1:1 split nobody agreed to',
      );
    });

    test('E-200-39 only a certificate this phone already believes is '
        'retained: one relabelled to another user, or of a user no ceremony '
        'here verified, is kept for nobody; a record is read back only by the '
        'install that wrote it', () async {
      final farm = await kaurFarm(s, members: realOwners(s));
      final phones = await phonesFor(farm, clock, trust);
      final ramesh = await phones.add(fx.ramesh);
      final stranger = await fx.remotePhone(
        phones.book,
        s.ledger.newId(),
        verifiedHere: false,
      );

      await s.ledger.retainPeerCert(fx.relabelled(ramesh.cert, fx.sukhdev));
      expect(
        s.ledger.retainedCertOf(ramesh.deviceId),
        isNull,
        reason: 'does not verify under Sukhdev\'s UMK',
      );
      await s.ledger.retainPeerCert(stranger.cert);
      expect(
        s.ledger.retainedCertOf(stranger.deviceId),
        isNull,
        reason: 'no ceremony on this phone verified that user (04 §8.2 🔒)',
      );
      final keys = s.ledger.keys as FakeKeyStore;
      expect(keys.writes, isNot(contains(LocalLedgerKeys.peerCerts)));

      await s.ledger.retainPeerCert(ramesh.cert);
      expect(s.ledger.retainedCertOf(ramesh.deviceId)?.userId, fx.ramesh);
      final raw = (await keys.read(LocalLedgerKeys.peerCerts))!;
      expect(
        decodeRetainedCerts(
          raw,
          holderDeviceId: s.ledger.identity.deviceId,
        ).map((c) => c.deviceId),
        [ramesh.deviceId],
      );
      expect(
        decodeRetainedCerts(raw, holderDeviceId: s.ledger.newId()),
        isEmpty,
        reason: 'a record another install wrote is not this one\'s',
      );
    });
  });
}

/// The highest server `seq` in [ledger]'s mirror.
Future<int> _maxSeq(LocalLedger ledger) async {
  final row = await ledger.db
      .customSelect('SELECT MAX(seq) AS m FROM envelopes_local')
      .getSingle();
  return row.read<int?>('m') ?? 0;
}
