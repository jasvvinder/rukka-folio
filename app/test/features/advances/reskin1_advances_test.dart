// RESKIN1 audit captures for advances and the cash count (ADR 2026-10-05 §2;
// ADR 2026-10-10b §1 phase 1 — an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S5   — canvas 6 *Advances · who is holding what*, canvas 6 / 13 *The card,
//        four ages* / *The advance, four ages*.
// S5.1 — canvas 6 / 13 *Ask for an advance*, canvas 6 *Sent · waiting for
//        Sunita*: not built (advances_paths.dart, advances_routes.dart), so
//        nothing is captured under S5.1 — S5's empty state, which says why it
//        offers no request door, is captured as S5__empty.
// S5.5 — canvas 5 / 11 *Count the cash · nothing counted yet*, *Verify mode ·
//        a difference*, *Verify mode · matches*, *Collect mode · the gollak*
//        (features/cash_count).
//
// TEST HONESTY: S5 is built as `advancesRoutes` builds it
// (`const AdvancesScreen()`) and reads the LedgerScope over a real in-memory
// LocalLedger; its advances are released by a second member's approval, as
// 02 §7.2 item 1 🔒 requires (the `releaseAdvance` fixture of
// s5_advances_test.dart). S5.5 is built as `cashCountRoutes` builds it
// (`CashCountScreen(accountId:)`) under the CashCountScope bootstrap.dart
// installs (LedgerCashCountSource). Synthetic data (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/advances/screens/s5_advances_screen.dart';
import 'package:rukka_folio/features/cash_count/cash_count_source.dart';
import 'package:rukka_folio/features/cash_count/ledger_cash_count_source.dart';
import 'package:rukka_folio/features/cash_count/screens/s5_5_cash_count_screen.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';
import 's5_advances_test.dart' show releaseAdvance, seedAdvances;

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

/// Lets the ledger's real I/O land — the sources' reads never complete inside
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

int _seq = 0;

/// S5.5 as `cashCountRoutes` builds it, under bootstrap.dart's scope.
Widget _count(LocalLedger ledger, String accountId) => CashCountScope(
  source: LedgerCashCountSource(ledger),
  child: CashCountScreen(
    key: ValueKey('r2b-s5.5-${_seq++}'),
    accountId: accountId,
  ),
);

Future<void> _typeTotal(WidgetTester tester, String rupees) async {
  await tester.enterText(find.byType(TextField).first, rupees);
  await _settle(tester);
}

void main() {
  // ── S5 ─────────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-30 design capture S5 (who is holding what)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S5',
      state: 'holding',
      expectState: () {
        expect(_has('Advance with you'), findsOneWidget);
        expect(_has('No advance is out right now.'), findsNothing);
      },
      setup: () async {
        final f = await seedAdvances();
        // Two more out with other members, so the aged list has a spread of
        // ages (40 days from the fixture; 17 and 3 here).
        final today = f.ledger.today();
        for (final (name, user, paise, days) in [
          ('Advance – Amritpal Singh', 'user-amritpal', 800_000, 17),
          ('Advance – Balwinder', 'user-balwinder', 350_000, 3),
        ]) {
          final a = await f.ledger.addAccount(
            f.bookId,
            name: name,
            accountClass: AccountClass.advance,
            memberId: user,
          );
          await releaseAdvance(
            f.ledger,
            bookId: f.bookId,
            user: user,
            advanceId: a.id,
            fromId: f.cashId,
            paise: paise,
            date: today.addDays(-days),
            purpose: 'Diesel and driver',
          );
        }
        return (AdvancesScreen(key: ValueKey('r2b-s5-${_seq++}')), f.ledger);
      },
    );
  });

  testWidgets('F1-1010rB-31 design capture S5 (the advance out, scrolled)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S5',
      state: 'given-out',
      expectState: () {
        expect(_has('Advance out'), findsOneWidget);
      },
      setup: () async {
        final f = await seedAdvances();
        return (AdvancesScreen(key: ValueKey('r2b-s5-${_seq++}')), f.ledger);
      },
      act: () async {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await tester.pump();
      },
    );
  });

  testWidgets('F1-1010rB-32 design capture S5 (empty — no request door, S5.1 '
      'not built)', (tester) async {
    await _shoot(
      tester,
      sid: 'S5',
      state: 'empty',
      expectState: () {
        expect(_has('No advance is out right now.'), findsOneWidget);
      },
      setup: () async {
        final f = await seedAdvances(withMine: false, withGiven: false);
        return (AdvancesScreen(key: ValueKey('r2b-s5-${_seq++}')), f.ledger);
      },
    );
  });

  // ── S5.5 ───────────────────────────────────────────────────────────────────

  testWidgets('F1-1010rB-33 design capture S5.5 (verify, nothing counted)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S5.5',
      state: 'verify-empty',
      expectState: () {
        expect(_has('The book says'), findsOneWidget);
        expect(_has('Count the cash'), findsWidgets);
      },
      setup: () async {
        final s = await seedSoloLedger();
        return (_count(s.ledger, s.cashId), s.ledger);
      },
    );
  });

  testWidgets('F1-1010rB-34 design capture S5.5 (verify, a difference)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S5.5',
      state: 'verify-difference',
      expectState: () {
        expect(_has('less than the book'), findsOneWidget);
      },
      setup: () async {
        final s = await seedSoloLedger();
        return (_count(s.ledger, s.cashId), s.ledger);
      },
      // The book says ₹21,600; ₹21,000 counted.
      act: () => _typeTotal(tester, '21000'),
    );
  });

  testWidgets('F1-1010rB-35 design capture S5.5 (verify, matches)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S5.5',
      state: 'verify-matches',
      expectState: () {
        expect(_has('Matches the book'), findsOneWidget);
      },
      setup: () async {
        final s = await seedSoloLedger();
        return (_count(s.ledger, s.cashId), s.ledger);
      },
      act: () => _typeTotal(tester, '21600'),
    );
  });

  testWidgets('F1-1010rB-36 design capture S5.5 (collect, the gollak)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S5.5',
      state: 'collect',
      expectState: () {
        expect(_has('Open and count'), findsWidgets);
      },
      setup: () async {
        final s = await seedSoloLedger();
        final gollak = await s.ledger.addAccount(
          s.bookId,
          name: 'Gollak',
          accountClass: AccountClass.money,
          subtype: MoneySubtype.cashCollection,
        );
        return (_count(s.ledger, gollak.id), s.ledger);
      },
    );
  });
}
