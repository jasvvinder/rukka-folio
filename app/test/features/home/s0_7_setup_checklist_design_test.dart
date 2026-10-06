// Design captures for S0.7 Setup checklist · Home, first run (ADR 2026-10-05
// §2; desk 172), drawn on S1 in the production shell. Pair with
// `python3 scripts/design_match.py pair S0.7`.
//
// default — canvas 1 frame O8: S0.6's *Finish* pressed (the row ticked), no
//           entry yet.
// open    — S0.6 skipped: every row open (no frame; the variant the ruling
//           describes).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/onboarding/opening_setup_record.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

void main() {
  testWidgets('F1-1006c-8 design capture S0.7 (default ticked · open)', (
    tester,
  ) async {
    Future<void> capture(String state, {required bool finished}) async {
      for (final target in RkDesignTarget.values) {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Amrit Kaur');
        final prefs = MemoryPrefs();
        final bookId = (await ledger.mirror.bookIds()).single;
        // The record is per book (P1A review, finding 6).
        if (finished) prefs.values[OpeningSetupRecord.keyFor(bookId)] = '1';
        final settings = AppSettings(prefs: prefs);
        await settings.load();
        await rkDesignCapture(
          tester,
          sid: 'S0.7',
          state: state,
          target: target,
          tab: RkTab.home,
          ledger: ledger,
          child: AppSettingsScope(
            settings: settings,
            child: HomeScreen(
              onVerb: (_) {},
              onSetupStep: (_) {},
              setupDoors: const {0, 1},
            ),
          ),
        );
        // The state the capture claims to show: O8's ticked row, or none.
        expect(
          find.byIcon(Icons.check_circle),
          finished ? findsOneWidget : findsNothing,
        );
        await _unmount(tester);
        await tester.pump(const Duration(milliseconds: 1));
      }
    }

    await capture('default', finished: true);
    await capture('open', finished: false);
  });
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
