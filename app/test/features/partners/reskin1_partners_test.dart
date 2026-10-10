// RESKIN1 audit captures for the partners feature (ADR 2026-10-05 §2; ADR
// 2026-10-10b §1 phase 1 — an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S14   — canvas 6 / 12 / 13 *Partner positions*; canvas 6 *Shortfall and
//         debit variants*.
// S14.1 — canvas 6 *Distribution · 1 Period*, *2 Preview*, *3 Confirm*: the
//         wizard, stepped by tapping Next as an owner does.
// S14.2 — canvas 6 *Drift · three equal routes*, *Carried forward*.
//
// TEST HONESTY: S14 and S14.1 are built exactly as `partnersRoutes` builds
// them (`PartnerPositionsScreen(bookId:)`, `DistributeProfitScreen(bookId:)`)
// and read the port bootstrap.dart installs — `PartnersScope(port:
// LedgerPartnersPort(ledger))` — over a real in-memory LocalLedger. The book
// is the Kaur Family Agriculture book `kaurFarm` creates, carrying the
// worked example's own season (G-001…G-008, joint-business-partnership.md
// §2), so the profit S14.1 previews and the distribution S14 shows are one
// figure, ₹5,94,000. Every capture asserts its state is on screen before it
// is snapped. Synthetic data (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/partners/ledger_partners_port.dart';
import 'package:rukka_folio/features/partners/partners_port.dart';
import 'package:rukka_folio/features/partners/partners_scope.dart';
import 'package:rukka_folio/features/partners/screens/s14_1_distribute_screen.dart';
import 'package:rukka_folio/features/partners/screens/s14_partner_positions_screen.dart';
import 'package:rukka_folio/features/partners/widgets/drift_settlement_card.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';
import 'ledger_partners_port_test.dart' show Farm, kaurFarm;

/// Writes the screen as it stands now — the same root-layer picture
/// [rkDesignCapture] takes, for a state a tap reached.
Future<void> _snap(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: rkDesignPixelRatio,
    );
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('$rkDesignCaptureDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png.buffer.asUint8List());
    image.dispose();
  });
}

/// Finds [text] in a Text or a RichText (money and placeholders are often
/// spans).
Finder _has(String text) => find.textContaining(text, findRichText: true);

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Lets the ledger's real I/O land — the port's reads never complete inside
/// the fake clock.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Captures [state] of [sid] on both targets, snapped after the loads land
/// and after [act] (run under the target's platform). The pre-load picture is
/// deleted.
Future<void> _shoot(
  WidgetTester tester, {
  required String sid,
  required String state,
  required Future<(Widget, LocalLedger)> Function() setup,
  required void Function() expectState,
  Future<void> Function()? act,
}) async {
  for (final target in RkDesignTarget.values) {
    final (child, ledger) = (await tester.runAsync(setup))!;
    final first = '$state-pre';
    await rkDesignCapture(
      tester,
      sid: sid,
      state: first,
      target: target,
      ledger: ledger,
      child: child,
    );
    debugDefaultTargetPlatformOverride = target.platform;
    try {
      await _settle(tester);
      if (act != null) await act();
      await _settle(tester);
      // The state the capture is named for must be on screen: a load that
      // threw, a source that came back empty or a tap that landed elsewhere
      // fails here instead of writing a PNG of the skeleton or error state.
      expectState();
      await _snap(tester, '${sid}__$state${target.suffix}');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    final pre = File('$rkDesignCaptureDir/${sid}__$first${target.suffix}.png');
    if (pre.existsSync()) pre.deleteSync();
    await _unmount(tester);
  }
}

/// The farm's season — vouchers G-001…G-008 of
/// `docs/reference/worked-examples/joint-business-partnership.md` §2: the bank
/// opens at ₹50,000; Amrit pays seed ₹1,80,000, Sukhdev diesel ₹95,000 and
/// Harjit labour ₹60,000 from their own pockets; the tractor repair ₹41,000
/// leaves the bank; crop ₹8,50,000 and milk ₹1,20,000 are banked; Amrit draws
/// ₹50,000. Profit is ₹9,70,000 − ₹3,76,000 = ₹5,94,000 (the example's
/// *Profit computation shown in full*), so the preview S14.1 draws from this
/// book (`distribute: false`) is the same figure that, when [distribute], is
/// shared 1:1:1 here — ₹1,98,000 each, bank ₹9,29,000, the example's §5
/// positions.
Future<Farm> _farm({bool distribute = true}) async {
  final s = await seedSoloLedger();
  final farm = await kaurFarm(s);
  final ledger = farm.ledger;
  Future<Account> add(String name, AccountClass c) =>
      ledger.addAccount(farm.bookId, name: name, accountClass: c);
  final diesel = await add('Diesel & Machinery', AccountClass.categoryExpense);
  final labour = await add('Labour', AccountClass.categoryExpense);
  final repair = await add('Machinery Repair', AccountClass.categoryExpense);
  final milk = await add('Milk Sale', AccountClass.categoryIncome);
  await ledger.openingBalances(
    farm.bookId,
    balances: {farm.bank.id: 50_000_00},
  );
  await farm.post(
    Verbs.partnerPaidCost(
      partner: farm.amrit,
      expense: farm.seed,
      amount: const Paise(1_80_000_00),
    ),
    kind: EntryKind.tookCredit,
  );
  await farm.post(
    Verbs.partnerPaidCost(
      partner: farm.sukhdev,
      expense: diesel,
      amount: const Paise(95_000_00),
    ),
    kind: EntryKind.tookCredit,
  );
  await farm.post(
    Verbs.partnerPaidCost(
      partner: farm.harjit,
      expense: labour,
      amount: const Paise(60_000_00),
    ),
    kind: EntryKind.tookCredit,
  );
  await farm.post(
    Verbs.moneyOut(
      from: farm.bank,
      forWhat: repair,
      amount: const Paise(41_000_00),
    ),
    kind: EntryKind.moneyOut,
  );
  await farm.post(
    Verbs.moneyIn(
      into: farm.bank,
      from: farm.named('Crop'),
      amount: const Paise(8_50_000_00),
    ),
    kind: EntryKind.moneyIn,
  );
  await farm.post(
    Verbs.moneyIn(
      into: farm.bank,
      from: milk,
      amount: const Paise(1_20_000_00),
    ),
    kind: EntryKind.moneyIn,
  );
  await farm.post(
    Verbs.partnerDrawing(
      partner: farm.amrit,
      from: farm.bank,
      amount: const Paise(50_000_00),
    ),
    kind: EntryKind.moneyOut,
  );
  if (distribute) {
    await farm.post(
      Verbs.profitDistribution(
        profitDistributed: farm.profitDistributed,
        partners: [
          PartnerShare(account: farm.amrit, ratio: 1),
          PartnerShare(account: farm.sukhdev, ratio: 1),
          PartnerShare(account: farm.harjit, ratio: 1),
        ],
        netProfit: const Paise(5_94_000_00),
      ),
      kind: EntryKind.adjustment,
    );
  }
  return farm;
}

/// A partner who has taken more than they put in plus their share: Harjit
/// draws ₹3,10,000 from the bank, so the business is owed by him.
Future<void> _harjitOverdraws(Farm farm) => farm.post(
  Verbs.partnerDrawing(
    partner: farm.harjit,
    from: farm.bank,
    amount: const Paise(3_10_000_00),
  ),
  kind: EntryKind.moneyOut,
);

int _seq = 0;

void main() {
  // ── S14 ────────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-20 design capture S14 (partner positions)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S14',
      state: 'positions',
      expectState: () {
        // The worked example's §5: ₹1,98,000 each, and the bank can
        // settle every balance.
        expect(_has('1,98,000'), findsWidgets);
        expect(
          _has('The business can settle all partner balances today.'),
          findsOneWidget,
        );
      },
      setup: () async {
        final farm = await _farm();
        return (
          PartnersScope(
            port: LedgerPartnersPort(farm.ledger),
            child: PartnerPositionsScreen(
              key: ValueKey('r2b-s14-${_seq++}'),
              bookId: farm.bookId,
            ),
          ),
          farm.ledger,
        );
      },
    );
  });

  testWidgets('F1-1010rB-21 design capture S14 (shortfall)', (tester) async {
    await _shoot(
      tester,
      sid: 'S14',
      state: 'shortfall',
      expectState: () {
        expect(_has('Short by'), findsOneWidget);
      },
      setup: () async {
        final farm = await _farm();
        await _harjitOverdraws(farm);
        return (
          PartnersScope(
            port: LedgerPartnersPort(farm.ledger),
            child: PartnerPositionsScreen(
              key: ValueKey('r2b-s14-${_seq++}'),
              bookId: farm.bookId,
            ),
          ),
          farm.ledger,
        );
      },
    );
  });

  testWidgets(
    'F1-1010rB-26 design capture S14 (a partner who owes the business)',
    (tester) async {
      await _shoot(
        tester,
        sid: 'S14',
        state: 'debit',
        expectState: () {
          expect(_has('owes the business'), findsOneWidget);
        },
        setup: () async {
          final farm = await _farm();
          await _harjitOverdraws(farm);
          return (
            PartnersScope(
              port: LedgerPartnersPort(farm.ledger),
              child: PartnerPositionsScreen(
                key: ValueKey('r2b-s14-${_seq++}'),
                bookId: farm.bookId,
              ),
            ),
            farm.ledger,
          );
        },
        act: () async {
          // Harjit's card is the last one.
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -600),
          );
          await tester.pump();
        },
      );
    },
  );

  // ── S14.1 ──────────────────────────────────────────────────────────────────

  Future<(Widget, LocalLedger)> distribute() async {
    final farm = await _farm(distribute: false);
    return (
      PartnersScope(
        port: LedgerPartnersPort(farm.ledger),
        child: DistributeProfitScreen(
          key: ValueKey('r2b-s14.1-${_seq++}'),
          bookId: farm.bookId,
        ),
      ),
      farm.ledger,
    );
  }

  Future<void> next(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(DistributeKeys.next));
    await tester.tap(find.byKey(DistributeKeys.next));
    await _settle(tester);
  }

  testWidgets('F1-1010rB-22 design capture S14.1 step 1 (period)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S14.1',
      state: 'step1-period',
      expectState: () {
        expect(_has('Which stretch of the year?'), findsOneWidget);
      },
      setup: distribute,
    );
  });

  testWidgets('F1-1010rB-23 design capture S14.1 step 2 (preview)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S14.1',
      state: 'step2-preview',
      expectState: () {
        expect(_has('What each owner gets'), findsOneWidget);
        // The profit S14 distributes is the one this book previews.
        expect(_has('5,94,000'), findsWidgets);
      },
      setup: distribute,
      act: () => next(tester),
    );
  });

  testWidgets('F1-1010rB-24 design capture S14.1 step 3 (confirm)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S14.1',
      state: 'step3-confirm',
      expectState: () {
        expect(_has('Ready to record'), findsOneWidget);
        expect(_has('Propose to the owners'), findsOneWidget);
      },
      setup: distribute,
      act: () async {
        await next(tester);
        await next(tester);
      },
    );
  });

  // ── S14.2 ──────────────────────────────────────────────────────────────────

  // ⚠️ SPEC: production never draws S14.2. LedgerPartnersPort hands S14 an
  // empty drift list with `driftMargin: null` because 02 §7.1 🔒 names a
  // *configurable* margin with no storage and no default
  // (ledger_partners_port.dart, partners_port.dart `driftMargin`). This
  // capture is the only way to see the card at all: it wraps the production
  // port and supplies a margin of ₹10,000, then derives the drift with the
  // engine's own `partnerDrift` over the same projection. The state is
  // unreachable in production until the margin setting lands.
  testWidgets('F1-1010rB-25 design capture S14.2 (drift card — margin '
      'supplied by the test, unreachable in production)', (tester) async {
    await _shoot(
      tester,
      sid: 'S14.2',
      state: 'drift-test-margin',
      expectState: () {
        expect(find.byType(DriftSettlementCard), findsWidgets);
        expect(_has('more with the business than the others'), findsWidgets);
      },
      setup: () async {
        final farm = await _farm();
        return (
          PartnersScope(
            port: _MarginPort(
              LedgerPartnersPort(farm.ledger),
              farm.ledger,
              const Paise(10_000_00),
            ),
            child: PartnerPositionsScreen(
              key: ValueKey('r2b-s14.2-${_seq++}'),
              bookId: farm.bookId,
            ),
          ),
          farm.ledger,
        );
      },
      act: () async {
        await tester.ensureVisible(find.byType(DriftSettlementCard).first);
        await tester.pump();
      },
    );
  });
}

/// The production port with a drift margin the app does not yet have — see
/// the ⚠️ SPEC above F1-1010rB-25. Everything else is delegated untouched.
final class _MarginPort implements PartnersPort, DistributionPort {
  _MarginPort(this.inner, this.ledger, this.margin);

  final LedgerPartnersPort inner;
  final LocalLedger ledger;
  final Paise margin;

  @override
  Stream<PartnersView> watch(String bookId) => inner.watch(bookId).asyncMap((
    v,
  ) async {
    final report = ledger.lastRecompute(bookId) ?? await ledger.rebuild(bookId);
    final names = {for (final p in v.positions) p.accountId: p.name};
    return PartnersView(
      ownership: v.ownership,
      positions: v.positions,
      canSettleAll: v.canSettleAll,
      shortBy: v.shortBy,
      moneyTotal: v.moneyTotal,
      partnerCreditTotal: v.partnerCreditTotal,
      drift: [
        for (final d in partnerDrift(
          report.state,
          report.chart,
          margin: margin,
        ))
          PartnerDriftView.fromEngine(d, names[d.accountId] ?? ''),
      ],
      sources: v.sources,
      driftMargin: margin,
      readOnly: v.readOnly,
      offline: v.offline,
    );
  });

  @override
  Future<void> payOut({
    required String bookId,
    required String partnerAccountId,
    required String fromAccountId,
    required Paise amount,
  }) => inner.payOut(
    bookId: bookId,
    partnerAccountId: partnerAccountId,
    fromAccountId: fromAccountId,
    amount: amount,
  );

  @override
  Future<void> settleBetweenPartners({
    required String bookId,
    required String fromPartnerAccountId,
    required String toPartnerAccountId,
    required Paise amount,
  }) => inner.settleBetweenPartners(
    bookId: bookId,
    fromPartnerAccountId: fromPartnerAccountId,
    toPartnerAccountId: toPartnerAccountId,
    amount: amount,
  );

  @override
  Future<DistributionView> distributionPreview(
    String bookId, {
    LocalDate? from,
    LocalDate? to,
  }) => inner.distributionPreview(bookId, from: from, to: to);

  @override
  Future<DistributionResult> distribute(
    String bookId, {
    LocalDate? from,
    LocalDate? to,
  }) => inner.distribute(bookId, from: from, to: to);
}
