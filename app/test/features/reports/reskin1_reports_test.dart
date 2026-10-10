// RESKIN1 round 2, slice R2C — audit captures for Reports (ADR 2026-10-05
// §2; ADR 2026-10-10b §1 phase 1 — an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S8.1 — canvas 15 *Reports list*.
// S8.2 — canvas 15 / 7: *Report viewer · Profit and Loss*, *Save or share*,
//        the two platform share sheets, *Nothing in this period yet*, *Trial
//        Balance*, *You will get, by age*, *Family match check*. The app's
//        S8.2 is the Day Book only (M5 scope; the other reports are M12, ADR
//        2026-09-12 Consequences), so the captures are the Day Book, its
//        empty period and its *Choose a format* sheet. The platform share
//        sheets are the OS's, not the app's, and cannot be drawn in a widget
//        test.
// S8.3 — canvas 13 / 15 *D5 Family reconciliation*, *D5b When a pair
//        disagrees*.
//
// TEST HONESTY: every screen is built with the constructor arguments its
// production route passes (reports_routes.dart: `ReportsListRoute(
// onOpenDayBook:, onOpenReconciliation:, onOpenPartnerPositions:)`, `const
// ReportViewerScreen()`, `const FamilyReconciliationScreen()`), inside the
// Menu tab (reportsRoutes nest under the Menu tab root, so the tab bar stays)
// and pushed, so the app bar carries its back button. Data is a real seeded
// `LocalLedger`; S8.3's pairs are real `transferBetweenBooks` postings, its
// mismatch a real reversal of one half (the F1-07-101 fixture). Amounts and
// names are synthetic (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/reports/screens/s8_1_reports_list_route.dart';
import 'package:rukka_folio/features/reports/screens/s8_2_report_viewer_screen.dart';
import 'package:rukka_folio/features/reports/screens/s8_3_family_reconciliation_screen.dart';
import 'package:rukka_folio/features/reports/widgets/export_actions.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

// ---- fixtures ---------------------------------------------------------------

/// The seeded solo book plus a family book with money moved between them —
/// the inter-book pair S8.3 reconciles.
///
/// Deterministic on purpose: `LocalLedger.reconciliation()` meets each pair
/// from the first of `mirror.bookIds()` (ORDER BY book_id), and book ids are
/// CSPRNG uuids, so which book is *This side* — and with it the pair title
/// and the sign of every figure — would change from run to run. The fixture
/// re-seeds until the reader's own book 'Me' sorts first, so every capture
/// (both targets, both states) reads 'Me and Sharma Family' from Me's side.
/// Each try succeeds with p = ½; twenty failures in a row (≈1e-6) fail loudly
/// rather than capture the other side.
Future<SeededLedger> _withFamily({bool mismatch = false}) async {
  late SeededLedger s;
  late String familyId;
  for (var attempt = 0; ; attempt++) {
    if (attempt == 20) {
      throw StateError('S8.3 fixture: Me never sorted before the family book');
    }
    s = await seedSoloLedger();
    familyId = await s.ledger.createBook(
      name: 'Sharma Family',
      type: BookType.family,
    );
    final order = await s.ledger.mirror.bookIds();
    if (order.first == s.bookId) break;
  }
  final familyCash = (await s.ledger.chartOf(familyId))
      .byClass(AccountClass.money)
      .first
      .id;
  final m = await s.ledger.transferBetweenBooks(
    fromBookId: s.bookId,
    fromAccountId: s.bankId,
    toBookId: familyId,
    toAccountId: familyCash,
    paise: 5_000_000,
    date: s.ledger.today(),
  );
  if (mismatch) await s.ledger.reverse(m.to.id, date: s.ledger.today());
  return s;
}

/// S8.1 exactly as reports_routes.dart builds it.
Widget _list() => ReportsListRoute(
  onOpenDayBook: () {},
  onOpenReconciliation: () {},
  onOpenPartnerPositions: (_) {},
);

/// A blank tab root with one door that pushes [child] onto the Menu tab's
/// navigator, as `/menu/reports…` does.
class _PushBase extends StatelessWidget {
  const _PushBase({required this.child});

  static const door = Key('r2c-reports-push-door');

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: door,
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => child)),
        child: const SizedBox.square(dimension: 48),
      ),
    ),
  );
}

// ---- capture plumbing -------------------------------------------------------

Finder _has(String text) => find.textContaining(text, findRichText: true);

Future<void> _snap(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  // The face check of rkDesignCapture (ADR 2026-10-05 §2 🔒), run on the
  // frame this PNG is written from, not on the deleted '-pre' frame.
  final unfaced = rkUnfacedText(view, allowed: rkDesignFaces);
  if (unfaced.isNotEmpty) {
    fail(
      'design capture $name draws text outside the design faces '
      "(ADR 2026-10-05 §2):\n${unfaced.join('\n')}",
    );
  }
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _shoot(
  WidgetTester tester, {
  required String sid,
  required String state,
  required Future<SeededLedger> Function() setup,
  required Widget screen,
  required void Function() expectState,
  Future<void> Function()? act,
}) async {
  for (final target in RkDesignTarget.values) {
    final seed = (await tester.runAsync(setup))!;
    final first = '$state-pre';
    await rkDesignCapture(
      tester,
      sid: sid,
      state: first,
      target: target,
      tab: RkTab.menu,
      ledger: seed.ledger,
      child: _PushBase(child: screen),
    );
    debugDefaultTargetPlatformOverride = target.platform;
    try {
      await _settle(tester);
      await tester.tap(find.byKey(_PushBase.door));
      await _settle(tester);
      if (act != null) await act();
      await _settle(tester);
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

/// A bootstrapped book with nothing entered — S8.2's empty period.
Future<SeededLedger> _emptyBook() async {
  final ledger = await openTestLedger();
  await ledger.bootstrapSolo(
    firstBookName: 'Me',
    startDate: ledger.today().addDays(-7),
  );
  final bookId = (await ledger.mirror.bookIds()).single;
  return SeededLedger(
    ledger: ledger,
    bookId: bookId,
    cashId: '',
    bankId: '',
    partyId: '',
    salesId: '',
    fuelId: '',
    entries: const [],
  );
}

void main() {
  testWidgets('F1-1010r2C-10 design capture S8.1 reports list', (tester) async {
    await _shoot(
      tester,
      sid: 'S8.1',
      state: 'default',
      setup: seedSoloLedger,
      screen: _list(),
      expectState: () => expect(_has('Day Book'), findsWidgets),
    );
  });

  testWidgets('F1-1010r2C-11 design capture S8.2 report viewer (Day Book, '
      'the one report the app builds)', (tester) async {
    await _shoot(
      tester,
      sid: 'S8.2',
      state: 'day-book',
      setup: seedSoloLedger,
      screen: const ReportViewerScreen(),
      expectState: () =>
          expect(find.byType(ReportChooseFormatAction), findsOneWidget),
    );
  });

  testWidgets('F1-1010r2C-12 design capture S8.2 choose a format sheet', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S8.2',
      state: 'choose-format',
      setup: seedSoloLedger,
      screen: const ReportViewerScreen(),
      act: () async {
        await tester.tap(find.byType(ReportChooseFormatAction));
      },
      expectState: () => expect(find.byType(BottomSheet), findsOneWidget),
    );
  });

  testWidgets('F1-1010r2C-13 design capture S8.2 nothing in this period', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S8.2',
      state: 'empty',
      setup: _emptyBook,
      screen: const ReportViewerScreen(),
      expectState: () => expect(
        _has('Nothing has been entered in this period.'),
        findsOneWidget,
      ),
    );
  });

  testWidgets('F1-1010r2C-14 design capture S8.3 every pair agrees', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S8.3',
      state: 'default',
      setup: _withFamily,
      screen: const FamilyReconciliationScreen(),
      expectState: () => expect(_has('Everything matches'), findsOneWidget),
    );
  });

  testWidgets('F1-1010r2C-15 design capture S8.3 a pair disagrees', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S8.3',
      state: 'mismatch',
      setup: () => _withFamily(mismatch: true),
      screen: const FamilyReconciliationScreen(),
      expectState: () => expect(_has('Does not match'), findsOneWidget),
    );
  });
}
