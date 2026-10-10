// RESKIN1 audit captures for the lock (ADR 2026-10-05 §2; ADR 2026-10-10b §1
// phase 1): the states the canvas draws that s15_lock_screen_design_test.dart
// does not already capture. S15 and S15.3 (c3 S15 iPhone/Android twins, c1/c1b
// S15.3) stay in that file; this one adds S15.1 (c3 *Privacy cover ·
// backgrounded*, *Both themes, side by side*). S15.2 (c3 *Personal book lock*)
// is not built, so it has nothing to capture (design/match/S15.2.json).
//
// Pair with `python3 scripts/design_match.py pair S15.1`.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/lock/widgets/privacy_cover.dart';

import '../../shared/design_capture.dart';
import 'lock_harness.dart' show unmount;

void main() {
  testWidgets('F1-R1C-1 design capture S15.1 privacy cover, light and dark '
      '(canvas 3 S15.1 *Privacy cover · backgrounded*, *Both themes, side by '
      'side*)', (tester) async {
    for (final (state, brightness) in const [
      ('default', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      for (final target in RkDesignTarget.values) {
        final out = await rkDesignCapture(
          tester,
          sid: 'S15.1',
          state: state,
          target: target,
          brightness: brightness,
          child: const PrivacyCoverSheet(),
        );
        // The cover drew (a mark on paper is more than one colour).
        expect(out.distinctColours, greaterThan(1));
        await unmount(tester);
      }
    }
  });
}
