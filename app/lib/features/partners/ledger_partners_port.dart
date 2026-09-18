// [PartnersPort] over the real ledger (02 §7.1 🔒, 13 §3.2 rows S14, S14.2).
//
// **No parallel state.** Capacity and drift are `core_ledger`'s own
// derivations (`settlementCapacity`, `partnerDrift`, A-02-65…67); the per-owner
// put in / took out / share split is `packages/data`'s pure
// `partnerPositions` (E-02-1…10); the ratio is the book's recorded
// `partner_shares` and nothing else. This file attaches names and posts the
// two settlement routes — it computes no figure of its own.
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart'
    as data
    show BookOwnership, PartnerLedgerPosition, partnerPositions;

import '../../shared/ledger/local_ledger.dart';
import 'partners_port.dart';

/// The [PartnersPort] the app mounts above S14.
final class LedgerPartnersPort implements PartnersPort, DistributionPort {
  /// Reads and posts through [ledger].
  const LedgerPartnersPort(this.ledger);

  /// The one door to the ledger.
  final LocalLedger ledger;

  @override
  Stream<PartnersView> watch(String bookId) =>
      // The account stream ticks whenever a balance changes, and the
      // projection behind it is already rebuilt by then — reading the last
      // report here re-derives without ever triggering another rebuild.
      ledger.watchAccounts(bookId).asyncMap((_) => _view(bookId));

  Future<PartnersView> _view(String bookId) async {
    final report = ledger.lastRecompute(bookId) ?? await ledger.rebuild(bookId);
    final chart = report.chart;
    final state = report.state;
    final config = await ledger.configOf(bookId);
    // 02 §7.1 🔒: *Just me* never mentions partners, ratios or distribution.
    // A book with no config read yet is treated as *Just me* — the reading
    // that says the fewest words, and S14 has a state for it.
    final ownership = config?.ownership == data.BookOwnership.shared
        ? BookOwnership.shared
        : BookOwnership.justMe;
    // 02 §7.1 🔒: an absent or empty map means the ratio was **never
    // recorded**, never that the shares are equal — so the weight stays null
    // and S14 prints *not recorded*.
    final shares = config?.partnerShares ?? const <String, int>{};
    final positions = [
      for (final p in data.partnerPositions(state, chart))
        _position(p, chart.account(p.accountId).name, shares[p.accountId]),
    ];
    return PartnersView.fromEngine(
      ownership: ownership,
      capacity: settlementCapacity(state, chart),
      // 02 §7.1 🔒 *Drift visibility* names a **configurable margin** but no
      // storage and no default, and no `business_setting` key for it exists in
      // 03 or the ADRs. With no margin configured there is no threshold to
      // compare against, so no partner can be *above* one: the list is empty
      // and [PartnersView.driftMargin] stays null, which is what keeps the
      // S14.2 card off rather than nagging on a number nobody chose.
      drift: const [],
      driftMargin: null,
      positions: positions,
      names: {for (final p in positions) p.accountId: p.name},
      sources: [
        for (final row in await ledger.watchAccounts(bookId).first)
          // A collection account is never a spending source (02 §8.2 🔒).
          if (row.account.isCashOrBank && !row.archived)
            SettlementSource(
              accountId: row.account.id,
              name: row.account.name,
              balance: Paise(row.balancePaise),
            ),
      ],
    );
  }

  static PartnerPosition _position(
    data.PartnerLedgerPosition p,
    String name,
    int? weight,
  ) => PartnerPosition(
    accountId: p.accountId,
    name: name,
    putIn: p.putIn,
    tookOut: p.tookOut,
    share: p.share,
    other: p.other,
    net: p.net,
    ratioWeight: weight,
  );

  @override
  Future<void> payOut({
    required String bookId,
    required String partnerAccountId,
    required String fromAccountId,
    required Paise amount,
  }) => ledger.partnerPayOut(
    bookId: bookId,
    partnerAccountId: partnerAccountId,
    fromAccountId: fromAccountId,
    paise: amount.raw,
  );

  @override
  Future<void> settleBetweenPartners({
    required String bookId,
    required String fromPartnerAccountId,
    required String toPartnerAccountId,
    required Paise amount,
  }) => ledger.settleBetweenPartners(
    bookId: bookId,
    fromPartnerAccountId: fromPartnerAccountId,
    toPartnerAccountId: toPartnerAccountId,
    paise: amount.raw,
  );

  @override
  Future<DistributionView> distributionPreview(
    String bookId, {
    LocalDate? from,
    LocalDate? to,
  }) async => _distributionView(
    await ledger.distributionPreview(bookId, from: from, to: to),
  );

  @override
  Future<DistributionResult> distribute(
    String bookId, {
    LocalDate? from,
    LocalDate? to,
  }) async {
    try {
      final outcome = await ledger.proposeDistribution(
        bookId,
        from: from,
        to: to,
      );
      return switch (outcome) {
        DistributionPosted() => DistributionResult.posted,
        DistributionProposed() => DistributionResult.proposed,
      };
    } on DistributionRefused catch (e) {
      throw DistributionBlocked(_block(e.refusal)!, excess: e.excess);
    }
  }

  /// The facade's preview, renamed for the screen. Not one figure is
  /// recomputed: every amount is carried across as the engine produced it.
  static DistributionView _distributionView(DistributionPreview p) =>
      DistributionView(
        bookId: p.bookId,
        financialYearLabel: p.financialYear.label,
        from: p.from,
        to: p.to,
        netProfit: p.netProfit,
        owners: [
          for (final s in p.shares)
            DistributionOwnerView(
              accountId: s.accountId,
              name: s.name,
              ratioWeight: s.ratioWeight,
              interest: s.interest,
              share: s.share,
            ),
        ],
        headroom: p.headroom,
        excess: p.excess,
        interestEnabled: p.interestEnabled,
        quorumOfOne: p.quorumOfOne,
        block: _block(p.refusal),
      );

  /// The facade's typed refusal in the seam's own vocabulary. A one-for-one
  /// map, so a refusal the engine grows cannot be quietly dropped: the switch
  /// is exhaustive and a new value breaks the build here rather than showing
  /// the user a blank screen.
  static DistributionBlock? _block(
    DistributionRefusal? refusal,
  ) => switch (refusal) {
    null => null,
    DistributionRefusal.notShared => DistributionBlock.notShared,
    DistributionRefusal.noPartnerAccounts => DistributionBlock.noPartners,
    DistributionRefusal.noProfitDistributedAccount =>
      DistributionBlock.noProfitDistributed,
    DistributionRefusal.ratioNotRecorded => DistributionBlock.ratioNotRecorded,
    DistributionRefusal.ratioIncomplete => DistributionBlock.ratioIncomplete,
    DistributionRefusal.termsUnverified => DistributionBlock.termsUnverified,
    DistributionRefusal.nothingToDistribute =>
      DistributionBlock.nothingToDistribute,
    DistributionRefusal.ceiling => DistributionBlock.ceiling,
    // `checkStructuralRequest` refuses only the FY-start change today
    // (ADR 2026-09-05e §9), which this action can never be; a future
    // engine rule lands here and is shown as *terms cannot be read*
    // rather than as nothing at all.
    DistributionRefusal.structural => DistributionBlock.termsUnverified,
  };
}
