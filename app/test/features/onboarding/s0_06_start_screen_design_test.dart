// Design capture for S0.06 Start (ADR 2026-10-05 §2; ADR 2026-10-05c §1,
// canvas 1b L0). Pair with `python3 scripts/design_match.py pair S0.06`.
@Tags(['F1'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_06_start_screen.dart';

import '../../shared/design_capture.dart';
import '../lock/lock_harness.dart' show unmount;

void main() {
  testWidgets('F1-1005c-1 design capture S0.06 (canvas 1b L0)', (tester) async {
    for (final target in RkDesignTarget.values) {
      await rkDesignCapture(
        tester,
        sid: 'S0.06',
        target: target,
        child: StartScreen(onNew: () {}, onSignIn: () {}),
      );
      await unmount(tester);
    }
  });
}
