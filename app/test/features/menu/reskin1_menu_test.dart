// RESKIN1 audit captures for S8 Menu (ADR 2026-10-05 §2; ADR 2026-10-10b §1
// phase 1 — an audit, not a build), drawn in the production shell. Pair with
// `python3 scripts/design_match.py pair S8`.
//
// default — canvas 15 *Menu · a hub, not a dump · iPhone* (and its Android
//           twin): the top of the hub, one book with August waiting.
// end     — canvas 15 *Menu · scrolled to the end · Legal, then the
//           version*: the list scrolled to its last row.
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/menu/close_month_books.dart';
import 'package:rukka_folio/features/menu/screens/s8_menu_screen.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/design_capture.dart';

/// Writes the screen as it stands now — the same root-layer picture
/// [rkDesignCapture] takes, for a state a scroll reached.
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

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Widget _menu() => MenuScreen(
  onOpenReports: () {},
  onOpenBooks: () {},
  onOpenBackup: () {},
  onOpenDevices: () {},
  onOpenSubscription: () {},
  onOpenSettings: () {},
  onOpenHelp: () {},
  onOpenLegal: () {},
  onOpenCloseMonth: (_) {},
  closeMonth: MenuCloseMonthLoad(
    MenuCloseMonthState.ready,
    books: [
      MenuCloseMonthBook(
        bookId: 'book-1',
        bookName: 'Sharma Textile',
        period: YearMonth(2026, 8),
        waiting: 3,
      ),
    ],
  ),
);

void main() {
  testWidgets('F1-1010rD-9 design capture S8 (default · scrolled to the end)', (
    tester,
  ) async {
    for (final target in RkDesignTarget.values) {
      await rkDesignCapture(
        tester,
        sid: 'S8',
        target: target,
        tab: RkTab.menu,
        child: _menu(),
      );
      expect(find.text('Reports'), findsOneWidget);
      // To the end of the list: Legal, then whatever closes it.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Legal'), findsOneWidget);
      await _snap(tester, 'S8__end${target.suffix}');
      await _unmount(tester);
    }
  });
}
