// Design capture for S1 Home · the baseline (ADR 2026-10-05 §2; RESKIN1
// audit, ADR 2026-10-10b §1), drawn in the production shell through the
// production wiring ([homeScreenFor]). Pair with
// `python3 scripts/design_match.py pair S1`.
//
// default — canvas 15 / 2 / 7 frame S1 *Home · the baseline*: a populated
//           book past setup (the S0.7 checklist has left: every row ticked,
//           ADR 2026-10-07 ruling 3), someone owes you and you owe someone,
//           the four verbs pinned above the tab bar.
// below   — the same mounted screen with the list scrolled to its end, so the
//           part the frame draws under the position card (*This month*
//           In / Out, *TODAY · 30 AUG › day book* and its rows) is captured
//           and paired too (R1D review finding 3), not only described.
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_routes.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

/// Writes the screen as it stands now under the capture's own name — the
/// same root-layer picture [rkDesignCapture] takes, for a state a scroll
/// reached.
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

void main() {
  testWidgets('F1-1006c-13 design capture S1 (default, populated, setup '
      'done)', (tester) async {
    for (final target in RkDesignTarget.values) {
      final seed = await seedSoloLedger();
      // Someone this book owes (You will give), on top of the seed's Ramesh
      // who owes the book (You will get). Synthetic (CLAUDE.md rule 4).
      final supplier = await seed.ledger.addAccount(
        seed.bookId,
        name: 'Bharat Power',
        accountClass: AccountClass.party,
      );
      await seed.ledger.tookCredit(
        bookId: seed.bookId,
        fromWhom: supplier.id,
        took: seed.fuelId,
        paise: 287_500,
        date: seed.ledger.today(),
      );
      final prefs = MemoryPrefs()
        ..values[RkPrefKeys.openingBalancesOf(seed.bookId)] = '1'
        ..values[RkPrefKeys.recoverySheetVerified] = '1';
      final settings = AppSettings(prefs: prefs);
      await settings.load();
      await rkDesignCapture(
        tester,
        sid: 'S1',
        target: target,
        tab: RkTab.home,
        ledger: seed.ledger,
        child: AppSettingsScope(
          settings: settings,
          child: Builder(builder: homeScreenFor),
        ),
      );
      // The state the capture claims: setup has left, the position is drawn.
      expect(find.byType(HomeSetupChecklist), findsNothing);
      expect(find.byType(HomePositionCard), findsOneWidget);

      // below: the list scrolled to its end — This month, then Today with
      // today's row (the credit purchase above).
      final list = find
          .ancestor(
            of: find.byType(HomePositionCard),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(list, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(HomeTodayRow), findsWidgets);
      await _snap(tester, 'S1__below${target.suffix}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
