// The in-memory [PartnersPort] S14's tests run against. The real
// implementation lands over `LocalLedger` + `readStructuralState` next lane;
// nothing in these tests depends on it, which is the point of the port.
//
// Figures are synthetic but not arbitrary: they are the Kaur Family
// Agriculture worked example already pinned by the engine's own A-02-62…67
// (`packages/core_ledger/test/partners_test.dart`), so a UI assertion here and
// the engine assertion there speak about the same book.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:rukka_folio/features/partners/partners_port.dart';

/// One recorded call to [PartnersPort.payOut].
typedef PayOutCall = ({
  String bookId,
  String partnerAccountId,
  String fromAccountId,
  Paise amount,
});

/// One recorded call to [PartnersPort.settleBetweenPartners].
typedef SettleCall = ({
  String bookId,
  String fromPartnerAccountId,
  String toPartnerAccountId,
  Paise amount,
});

/// A port that serves a fixed view (or an error, or nothing at all).
final class FakePartnersPort implements PartnersPort {
  /// Creates the fake. With [view] null and [error] false the stream never
  /// emits — the loading state.
  FakePartnersPort({this.view, this.error = false, this.throwOnPost = false});

  /// What [watch] emits.
  PartnersView? view;

  /// Emit an error instead (13 §4.3 error-with-retry).
  bool error;

  /// Make both posting calls fail (the sheet's failure line).
  bool throwOnPost;

  /// How many times [watch] has been called — the retry test reads this.
  int watchCount = 0;

  /// Every pay-out posted through the port.
  final payOuts = <PayOutCall>[];

  /// Every partner-to-partner settlement posted through the port.
  final settlements = <SettleCall>[];

  @override
  Stream<PartnersView> watch(String bookId) {
    watchCount++;
    if (error) {
      return Stream<PartnersView>.error(StateError('no book'));
    }
    final v = view;
    // A stream that never emits: the loading state (13 §4.3).
    if (v == null) return StreamController<PartnersView>().stream;
    return Stream<PartnersView>.value(v);
  }

  @override
  Future<void> payOut({
    required String bookId,
    required String partnerAccountId,
    required String fromAccountId,
    required Paise amount,
  }) async {
    if (throwOnPost) throw StateError('refused');
    payOuts.add((
      bookId: bookId,
      partnerAccountId: partnerAccountId,
      fromAccountId: fromAccountId,
      amount: amount,
    ));
  }

  @override
  Future<void> settleBetweenPartners({
    required String bookId,
    required String fromPartnerAccountId,
    required String toPartnerAccountId,
    required Paise amount,
  }) async {
    if (throwOnPost) throw StateError('refused');
    settlements.add((
      bookId: bookId,
      fromPartnerAccountId: fromPartnerAccountId,
      toPartnerAccountId: toPartnerAccountId,
      amount: amount,
    ));
  }
}

/// ₹[rupees] in integer paise (CLAUDE.md rule 1 — no float ever touches it).
Paise rs(int rupees) => Paise(rupees * 100);

/// The Kaur Family book after the season and the distribution, exactly as
/// A-02-65 and A-02-67 pin it: money ₹9,29,000 against ₹8,79,000 owed to the
/// owners, balances 3,28,000 / 2,93,000 / 2,58,000, average 2,93,000, so Amrit
/// is ₹35,000 above it and nobody else is.
///
/// [ratios] false drops `partner_shares` — 02 §7.1 🔒: an absent map means the
/// ratio was never recorded, **never** that the shares are equal.
PartnersView kaurView({
  BookOwnership ownership = BookOwnership.shared,
  bool ratios = true,
  bool drift = true,
  bool cash = true,
  bool readOnly = false,
  bool offline = false,
  bool soleOwner = false,
  bool harjitInDebit = false,
}) {
  final positions = <PartnerPosition>[
    PartnerPosition(
      accountId: 'amrit',
      name: 'Amrit Kaur',
      putIn: rs(240000),
      tookOut: rs(110000),
      share: rs(198000),
      net: rs(328000),
      ratioWeight: ratios ? 1 : null,
    ),
    if (!soleOwner)
      PartnerPosition(
        accountId: 'sukhdev',
        name: 'Sukhdev Singh',
        putIn: rs(160000),
        tookOut: rs(65000),
        share: rs(198000),
        net: rs(293000),
        ratioWeight: ratios ? 1 : null,
      ),
    if (!soleOwner)
      PartnerPosition(
        accountId: 'harjit',
        name: 'Harjit Kaur',
        putIn: rs(120000),
        tookOut: harjitInDebit ? rs(460000) : rs(60000),
        share: rs(198000),
        net: harjitInDebit ? rs(-142000) : rs(258000),
        ratioWeight: ratios ? 1 : null,
      ),
  ];
  return PartnersView(
    ownership: ownership,
    positions: positions,
    canSettleAll: true,
    shortBy: Paise.zero,
    moneyTotal: rs(929000),
    partnerCreditTotal: rs(879000),
    drift: drift
        ? [
            PartnerDriftView(
              accountId: 'amrit',
              name: 'Amrit Kaur',
              owed: rs(328000),
              aboveAverage: rs(35000),
            ),
          ]
        : const [],
    sources: cash
        ? [
            SettlementSource(
              accountId: 'bank',
              name: 'SBI Agri Current',
              balance: rs(929000),
            ),
          ]
        : const [],
    driftMargin: drift ? rs(30000) : null,
    readOnly: readOnly,
    offline: offline,
  );
}
