// Design capture for S1 Home · the baseline (ADR 2026-10-05 §2), drawn in the
// production shell. Pair with `python3 scripts/design_match.py pair S1`.
//
// default — canvas 15 / 2 / 7 frame S1 *Home · the baseline*: a populated
//           book, the four verbs pinned above the tab bar.
@Tags(['F1'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

void main() {
  testWidgets('F1-1006c-13 design capture S1 (default, populated)', (
    tester,
  ) async {
    for (final target in RkDesignTarget.values) {
      final seed = await seedSoloLedger();
      await rkDesignCapture(
        tester,
        sid: 'S1',
        target: target,
        tab: RkTab.home,
        ledger: seed.ledger,
        child: HomeScreen(onVerb: (_) {}),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
