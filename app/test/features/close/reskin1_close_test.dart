// RESKIN1 audit captures for the close feature (ADR 2026-10-05 §2; ADR
// 2026-10-10b §1 phase 1 — an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S10   — canvas 5 / 11 / 13 / 14: *Close August · step 1*, *Step 3 · the
//         tray*, *Step 4 · what you are signing* / *Confirm & lock*. The
//         wizard is a state machine; each step is reached by tapping *Next*
//         on the mounted screen, as a closer does.
// S10.1 — canvas 5 / 13 *Family close status*: in the app it is a section of
//         step 4, drawn only when this device holds more than one book.
// S10.2 — canvas 5 / 11 *Month summary card*: the reward that replaces step 4
//         once the lock lands, and the same card on its own route.
// S10.3 — canvas 5 *Late arrivals tray* (features/inbox).
// S10.4 — canvas 5 *Year close · the ceremony*, *Sealed · brought forward*,
//         *Reopened · certificate voided*.
// S10.5 — canvas 5 *Before the lock · one phone still out*: the panel that
//         takes the lock action's place in step 4.
//
// TEST HONESTY: every screen is built with the constructor arguments its
// production route passes (close_routes.dart, inbox_routes.dart) and reads
// the same ledger-backed sources bootstrap.dart installs above the router —
// LedgerCloseSource, LedgerYearCloseSource, LedgerClosedYearsSource,
// LedgerCashCountSource, LedgerLateArrivals — over a real in-memory
// LocalLedger. No feature fake stands in for production data. Amounts and
// names are synthetic (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show AuthorGapsCompanion;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/cash_count/cash_count_source.dart';
import 'package:rukka_folio/features/cash_count/ledger_cash_count_source.dart';
import 'package:rukka_folio/features/close/close_routes.dart';
import 'package:rukka_folio/features/close/ledger_close_source.dart';
import 'package:rukka_folio/features/close/ledger_year_close_source.dart';
import 'package:rukka_folio/features/inbox/late_arrivals.dart';
import 'package:rukka_folio/features/inbox/ledger_late_arrivals.dart';
import 'package:rukka_folio/features/inbox/screens/s10_3_late_arrivals_screen.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/closed_years.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

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

/// Captures [state] of [sid] on both targets.
///
/// The ledger-backed sources read through real I/O, which never completes
/// inside the test's fake clock — the first frame [rkDesignCapture] draws is
/// the ruled skeleton. So every state is snapped after [_settle] has let the
/// loads land, and after [act] has driven the mounted screen to the state
/// (under the target's platform, as the capture was drawn). The pre-load
/// picture is deleted.
Future<void> _shoot(
  WidgetTester tester, {
  required String sid,
  required String state,
  required Future<(Widget, LocalLedger)> Function() setup,
  required void Function() expectState,
  Future<void> Function()? act,
}) async {
  for (final target in RkDesignTarget.values) {
    // Signing (a lock, a year close) is real async work; outside the fake
    // clock it completes.
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

/// The ledger-backed sources bootstrap.dart installs above the router for
/// S5.5, S10, S10.3 and S10.4 (bootstrap.dart, the CashCountScope →
/// LateArrivalsScope stack).
Widget _production(LocalLedger ledger, Widget child) => CashCountScope(
  source: LedgerCashCountSource(ledger),
  child: CloseScope(
    source: LedgerCloseSource(ledger),
    child: YearCloseScope(
      source: LedgerYearCloseSource(ledger),
      child: ClosedYearsScope(
        source: LedgerClosedYearsSource(ledger).call,
        child: LateArrivalsScope(
          tray: LedgerLateArrivals(ledger),
          child: child,
        ),
      ),
    ),
  ),
);

final _august = YearMonth(2026, 8);

int _seq = 0;

/// S10 exactly as `closeRoutes` builds it for `/close/:book/:period`.
Widget _wizard(String bookId, YearMonth period) => MonthCloseScreen(
  key: ValueKey('r2b-close-${_seq++}'),
  bookId: bookId,
  period: period,
  onOpenCount: (_) {},
  onOpenYear: (_) {},
  onDone: () {},
);

/// An open author-sequence gap — the state sync leaves when another phone's
/// entries are known to be missing (ADR 2026-09-05b §3). Written straight
/// into `author_gaps`, as `ledger_close_status_test.dart` does: the sync
/// engine is the production writer and it is not mounted here.
Future<void> _gap(LocalLedger ledger, String bookId) => ledger.db
    .into(ledger.db.authorGaps)
    .insert(
      AuthorGapsCompanion.insert(
        bookId: bookId,
        authorDevice: 'device-7c1e',
        expectedSeq: 4,
        sinceHlc: 9,
      ),
    );

Future<void> _next(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.ensureVisible(find.byKey(CloseKeys.next));
    await tester.tap(find.byKey(CloseKeys.next));
    await _settle(tester);
  }
}

/// Lets the ledger's real I/O land: the sources' reads, and the progress the
/// wizard writes on every step change.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 1 Sep 2026: `seedSoloLedger` opens the book on 25 Aug and posts its week of
/// entries from 27 Aug, so the August being closed has money in, money out and
/// a credit sale in it — not just the opening balances.
DateTime _sep1() => DateTime(2026, 9, 1, 10);

DateTime _may2027() => DateTime(2027, 5, 10, 10);

DateTime _october() => DateTime(2026, 10, 5, 10);

/// FY 2026-27 wholly past (10 May 2027): a book with a cash and a bank A/C,
/// one party balance each way and a year's spending — what S10.4 certifies.
Future<(LocalLedger, String)> _yearBook() async {
  final ledger = await openTestLedger(now: _may2027);
  await ledger.bootstrapSolo(
    firstBookName: 'Me',
    startDate: LocalDate(2026, 4, 1),
  );
  final bookId = (await ledger.mirror.bookIds()).single;
  final cash = await ledger.addAccount(
    bookId,
    name: 'Cash in hand',
    accountClass: AccountClass.money,
    subtype: MoneySubtype.cash,
  );
  final bank = await ledger.addAccount(
    bookId,
    name: 'SBI Saving',
    accountClass: AccountClass.money,
    subtype: MoneySubtype.saving,
  );
  final fuel = await ledger.addAccount(
    bookId,
    name: 'Diesel',
    accountClass: AccountClass.categoryExpense,
  );
  final supplier = await ledger.addAccount(
    bookId,
    name: 'Bharat Fuels',
    accountClass: AccountClass.party,
  );
  await ledger.openingBalances(
    bookId,
    balances: {cash.id: 2_500_000, bank.id: 10_000_000},
    date: LocalDate(2026, 4, 1),
  );
  await ledger.moneyOut(
    bookId: bookId,
    from: cash.id,
    forWhat: fuel.id,
    paise: 240_000,
    date: LocalDate(2026, 6, 15),
    note: 'Diesel',
  );
  await ledger.tookCredit(
    bookId: bookId,
    fromWhom: supplier.id,
    took: fuel.id,
    paise: 1_700_000,
    date: LocalDate(2026, 11, 2),
  );
  return (ledger, bookId);
}

Future<void> _lockYear(LocalLedger ledger, String bookId) async {
  for (final m in FinancialYear(2026).months) {
    await ledger.lockMonth(bookId, m, declaredBalances: const {});
  }
}

/// S10.4 exactly as `closeRoutes` builds it for `/close/:book/year/:fy`.
Widget _year(String bookId) => YearCloseScreen(
  key: ValueKey('r2b-year-${_seq++}'),
  bookId: bookId,
  financialYear: FinancialYear(2026),
  onOpen: (_) {},
  onDone: () {},
);

void main() {
  // ── S10 ────────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-1 design capture S10 step 1 (count your cash)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10',
      state: 'step1-count',
      expectState: () {
        expect(find.byKey(CloseKeys.cashList), findsOneWidget);
      },
      setup: () async {
        final s = await seedSoloLedger(clock: _sep1);
        return (_production(s.ledger, _wizard(s.bookId, _august)), s.ledger);
      },
    );
  });

  testWidgets('F1-1010rB-2 design capture S10 step 2 (confirm each bank)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10',
      state: 'step2-banks',
      expectState: () {
        expect(find.byKey(CloseKeys.bankList), findsOneWidget);
      },
      setup: () async {
        final s = await seedSoloLedger(clock: _sep1);
        return (_production(s.ledger, _wizard(s.bookId, _august)), s.ledger);
      },
      act: () => _next(tester, 1),
    );
  });

  testWidgets('F1-1010rB-3 design capture S10 step 3 (the tray, one block '
      'and one warning)', (tester) async {
    await _shoot(
      tester,
      sid: 'S10',
      state: 'step3-tray',
      expectState: () {
        // The open author gap is a block (ADR 2026-09-05b §3).
        expect(find.byKey(CloseKeys.blocks), findsOneWidget);
        expect(find.byKey(CloseKeys.warns), findsOneWidget);
      },
      setup: () async {
        final s = await seedSoloLedger(clock: _sep1);
        await _gap(s.ledger, s.bookId);
        return (_production(s.ledger, _wizard(s.bookId, _august)), s.ledger);
      },
      act: () => _next(tester, 2),
    );
  });

  testWidgets('F1-1010rB-4 design capture S10 step 4 (what you are signing)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10',
      state: 'step4-lock',
      expectState: () {
        expect(find.byKey(CloseKeys.declared), findsOneWidget);
        expect(find.byKey(CloseKeys.lock), findsOneWidget);
        expect(find.byKey(CloseKeys.blocked), findsNothing);
      },
      setup: () async {
        final s = await seedSoloLedger(clock: _sep1);
        return (_production(s.ledger, _wizard(s.bookId, _august)), s.ledger);
      },
      act: () => _next(tester, 3),
    );
  });

  // ── S10.5 ──────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-5 design capture S10.5 (one phone still out)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10.5',
      state: 'phone-out',
      expectState: () {
        // S10.5 takes the lock action's place.
        expect(find.byKey(CloseKeys.blocked), findsOneWidget);
        expect(find.byKey(CloseKeys.lock), findsNothing);
      },
      setup: () async {
        final s = await seedSoloLedger(clock: _sep1);
        await _gap(s.ledger, s.bookId);
        return (_production(s.ledger, _wizard(s.bookId, _august)), s.ledger);
      },
      act: () => _next(tester, 3),
    );
  });

  // ── S10.1 ──────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-6 design capture S10.1 (family close status)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10.1',
      state: 'family',
      expectState: () {
        expect(find.byKey(CloseKeys.family), findsOneWidget);
        expect(_has('Sharma Super Store'), findsWidgets);
      },
      setup: () async {
        final s = await seedSoloLedger(clock: _sep1);
        final start = s.ledger.today().addDays(-7);
        final store = await s.ledger.createBook(
          name: 'Sharma Super Store',
          type: BookType.business,
          startDate: start,
        );
        final farm = await s.ledger.createBook(
          name: 'Agriculture Business',
          type: BookType.business,
          startDate: start,
        );
        await s.ledger.createBook(
          name: 'Sharma Joint Family',
          type: BookType.business,
          startDate: start,
        );
        // One book already closed, one waiting on a phone, one not started.
        await s.ledger.lockMonth(store, _august, declaredBalances: const {});
        await _gap(s.ledger, farm);
        return (_production(s.ledger, _wizard(s.bookId, _august)), s.ledger);
      },
      act: () => _next(tester, 3),
    );
  });

  // ── S10.2 ──────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-7 design capture S10.2 (the reward, in the wizard)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10.2',
      state: 'after-lock',
      expectState: () {
        // The lock landed: the reward replaced step 4, and no refusal.
        expect(find.byKey(CloseKeys.summary), findsOneWidget);
        expect(find.byKey(CloseKeys.lock), findsNothing);
        expect(_has('refused the lock'), findsNothing);
        expect(_has('couldn’t be locked'), findsNothing);
      },
      setup: () async {
        final s = await seedSoloLedger(clock: _sep1);
        return (_production(s.ledger, _wizard(s.bookId, _august)), s.ledger);
      },
      act: () async {
        await _next(tester, 3);
        await tester.ensureVisible(find.byKey(CloseKeys.lock));
        await tester.tap(find.byKey(CloseKeys.lock));
        await _settle(tester);
      },
    );
  });

  testWidgets('F1-1010rB-8 design capture S10.2 (the card on its own route)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10.2',
      state: 'card',
      expectState: () {
        expect(find.byKey(MonthSummaryKeys.card), findsOneWidget);
      },
      setup: () async {
        final s = await seedSoloLedger(clock: _sep1);
        final view = await LedgerCloseSource(s.ledger)
            .loadClose(s.bookId, _august);
        await s.ledger.lockMonth(
          s.bookId,
          _august,
          declaredBalances: view.declaredBalances,
        );
        // `closeRoutes` → ClosePaths.summaryPattern.
        return (
          _production(
            s.ledger,
            MonthSummaryScreen(
              bookId: s.bookId,
              period: _august,
              onDone: () {},
            ),
          ),
          s.ledger,
        );
      },
    );
  });

  // ── S10.3 ──────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-9 design capture S10.3 (one late arrival)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10.3',
      state: 'one-late',
      expectState: () {
        expect(_has('Money out'), findsWidgets);
        expect(_has('Nothing arrived late.'), findsNothing);
      },
      setup: () async {
        final ledger = await openTestLedger(now: _october);
        await ledger.bootstrapSolo(
          firstBookName: 'Me',
          startDate: LocalDate(2026, 8, 1),
        );
        final bookId = (await ledger.mirror.bookIds()).single;
        final cash = await ledger.addAccount(
          bookId,
          name: 'Cash in hand',
          accountClass: AccountClass.money,
          subtype: MoneySubtype.cash,
        );
        final fuel = await ledger.addAccount(
          bookId,
          name: 'Diesel',
          accountClass: AccountClass.categoryExpense,
        );
        await ledger.openingBalances(
          bookId,
          balances: {cash.id: 2_500_000},
          date: LocalDate(2026, 8, 1),
        );
        final late = await ledger.moneyOut(
          bookId: bookId,
          from: cash.id,
          forWhat: fuel.id,
          paise: 240_000,
          date: LocalDate(2026, 8, 28),
          note: 'Diesel',
        );
        for (final m in [YearMonth(2026, 8), YearMonth(2026, 9)]) {
          await ledger.lockMonth(bookId, m, declaredBalances: const {});
        }
        // The projector's verdict on an arrival after the lock, set by hand
        // the way `ledger_late_arrivals_test.dart` does: sync is the
        // production writer of `in_tray` and is not mounted here.
        await ledger.db.customStatement(
          "UPDATE entries_p SET status = 'in_tray' WHERE id = ?",
          [late.id],
        );
        ledger.db.markTablesUpdated({ledger.db.entriesP});
        // `inboxRoutes` → InboxPaths.lateArrivals.
        return (_production(ledger, LateArrivalsScreen(onDone: () {})), ledger);
      },
    );
  });

  // ── S10.4 ──────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-10 design capture S10.4 (the ceremony, ready)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10.4',
      state: 'ceremony',
      expectState: () {
        expect(find.byKey(YearCloseKeys.certify), findsOneWidget);
        expect(find.byKey(YearCloseKeys.blocks), findsNothing);
        expect(find.byKey(YearCloseKeys.sealed), findsNothing);
      },
      setup: () async {
        final (ledger, bookId) = await _yearBook();
        await _lockYear(ledger, bookId);
        return (_production(ledger, _year(bookId)), ledger);
      },
    );
  });

  testWidgets('F1-1010rB-11 design capture S10.4 (open, months still open)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10.4',
      state: 'blocked',
      expectState: () {
        // Twelve months still open: the checklist blocks, nothing certifies.
        expect(find.byKey(YearCloseKeys.blocks), findsOneWidget);
        expect(find.byKey(YearCloseKeys.certify), findsNothing);
      },
      setup: () async {
        final (ledger, bookId) = await _yearBook();
        return (_production(ledger, _year(bookId)), ledger);
      },
    );
  });

  testWidgets('F1-1010rB-12 design capture S10.4 (sealed, brought forward)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S10.4',
      state: 'sealed',
      expectState: () {
        expect(find.byKey(YearCloseKeys.sealed), findsOneWidget);
        expect(find.byKey(YearCloseKeys.certify), findsNothing);
      },
      setup: () async {
        final (ledger, bookId) = await _yearBook();
        await _lockYear(ledger, bookId);
        await ledger.closeYear(bookId, FinancialYear(2026));
        return (_production(ledger, _year(bookId)), ledger);
      },
    );
  });

  // ⚠️ SPEC: canvas 5 S10.4 *Reopened · certificate voided* is not captured.
  // The screen draws that state (YearCloseKeys.voided) for a projected
  // `uncertified` year, but this device cannot produce one: once FY 2026-27
  // is certified, `LocalLedger.unlockMonth` refuses every month inside it
  // (`MonthUnlockRefusal.closedYear`, local_ledger.dart — 02 §8.1 🔒), and
  // no other production path writes the state here. A capture would need a
  // state production cannot reach on this phone.
}
