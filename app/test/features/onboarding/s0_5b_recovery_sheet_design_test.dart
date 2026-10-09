// Design capture for S0.5b Recovery sheet (ADR 2026-10-05 §2). Pair with
// `python3 scripts/design_match.py pair S0.5b`.
//
// default    — canvas 1 frame O5b "Recovery sheet · print or save": the
//              sign-up chain on arrival, *I've kept it safe* asleep.
// opened     — after the page was opened once: the button wakes (O5b's
//              own note; not drawn separately).
// not_made   — a failed publish: its reason, *Try again* and *Skip for now*
//              (ADR 2026-10-06d ruling 3; no frame — O5b's layout).
// check      — reopened from S0.7 with a sheet on the server: scan or type
//              it back (no frame — O5b's layout with R2.4's two actions).
@Tags(['F1'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart' show pumpRk;

final class _Service implements RecoverySheetService {
  _Service({this.fail});

  final RecoverySheetNotMadeReason? fail;

  @override
  Future<RecoverySheetPrintout> make(Locale locale) async {
    if (fail != null) throw RecoverySheetNotMade(fail!);
    return RecoverySheetPrintout(
      Uint8List(4),
      (pdf, name) async => true,
      version: 1,
    );
  }

  @override
  Future<bool> sheetOnServer() async => true;

  @override
  Future<RecoverySheetCheckResult> checkTyped(String typed) async =>
      RecoverySheetCheckResult.opens;

  @override
  Future<RecoverySheetCheckResult> scan() async =>
      RecoverySheetCheckResult.opens;
}

void main() {
  // The screen keeps one GlobalKey across a state's two captures, so the
  // second capture re-parents the same State (the tap's result) rather than
  // building a fresh intro.
  Future<void> capture(
    WidgetTester tester,
    Widget Function(Key key) child, {
    required List<String> states,
    Future<void> Function()? between,
  }) async {
    for (final target in RkDesignTarget.values) {
      final key = GlobalKey();
      for (var i = 0; i < states.length; i++) {
        if (i > 0) await between!();
        // A leading `_` pumps the state without writing a capture.
        if (states[i].startsWith('_')) {
          await pumpRk(tester, child(key), viewport: target.size);
          continue;
        }
        await rkDesignCapture(
          tester,
          sid: 'S0.5b',
          state: states[i],
          target: target,
          child: child(key),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Future<void> tapPrimary(WidgetTester tester) async {
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  testWidgets('F1-1006d-1 design capture S0.5b (default, opened)', (
    tester,
  ) async {
    await capture(
      tester,
      // `onDone` is wired as production wires it (onboarding_routes.dart):
      // without it *I've kept it safe* has nothing to wake to and the
      // `opened` capture would draw it asleep.
      (key) => RecoverySheetScreen(
        key: key,
        service: _Service(),
        onBack: () {},
        onDone: () {},
      ),
      states: const ['default', 'opened'],
      between: () => tapPrimary(tester),
    );
  });

  testWidgets('F1-1006d-1 design capture S0.5b (not_made)', (tester) async {
    await capture(
      tester,
      (key) => RecoverySheetScreen(
        key: key,
        service: _Service(fail: RecoverySheetNotMadeReason.offline),
        onBack: () {},
        onSkip: () {},
      ),
      states: const ['_intro', 'not_made'],
      between: () => tapPrimary(tester),
    );
  });

  testWidgets('F1-1006d-3 design capture S0.5b (check)', (tester) async {
    await capture(
      tester,
      (key) => RecoverySheetScreen(
        key: key,
        service: _Service(),
        entry: RecoverySheetEntry.checkIfMade,
        onBack: () {},
      ),
      states: const ['check'],
    );
  });
}
