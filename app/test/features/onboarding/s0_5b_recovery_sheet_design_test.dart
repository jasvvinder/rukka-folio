// Design capture for S0.5b Recovery sheet (ADR 2026-10-05 §2). Pair with
// `python3 scripts/design_match.py pair S0.5b`.
//
// default — canvas 1 frame O5b "Recovery sheet · print or save", as the
//           shipped build reaches it: no sheet maker is wired (desk 171), so
//           *Make the sheet* is disabled with its reason beneath it.
@Tags(['F1'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';

import '../../shared/design_capture.dart';

void main() {
  testWidgets('F1-1006c-18 design capture S0.5b (default)', (tester) async {
    for (final target in RkDesignTarget.values) {
      await rkDesignCapture(
        tester,
        sid: 'S0.5b',
        state: 'default',
        target: target,
        child: RecoverySheetScreen(onSkip: () {}),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
