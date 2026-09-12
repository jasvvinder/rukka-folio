// F1 widget tests for S15.1 Privacy cover (13 §3.2 row S15.1, 07 §5.6 🔒 —
// "no balance ever appears in the iOS app switcher"). The cover must be up
// before the system takes its snapshot, which happens in the `inactive` phase
// on iOS, so `inactive` is tested as carefully as `paused`.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/lock/widgets/privacy_cover.dart';
import 'package:rukka_folio/features/onboarding/widgets/sealed_mark.dart';

import 'lock_harness.dart';
import '../../shared/test_app.dart';

/// A screen with a balance on it — exactly what must never reach the switcher.
const _balance = Scaffold(body: Center(child: Text('₹4,81,000')));

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  tester.binding.handleAppLifecycleStateChanged(state);
  await tester.pumpAndSettle();
}

void main() {
  group('F1-07-19 S15.1 Privacy cover (07 §5.6 🔒)', () {
    testWidgets(
      'F1-07-64 nothing covers the app while it is in the foreground',
      (tester) async {
        sizeView(tester);
        await pumpRk(tester, const PrivacyCover(child: _balance));

        expect(find.byType(PrivacyCoverSheet), findsNothing);
        expect(find.text('₹4,81,000'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-64 the cover is up in the inactive phase — before iOS takes the '
      'app-switcher snapshot — and hides the balance',
      (tester) async {
        sizeView(tester);
        await pumpRk(tester, const PrivacyCover(child: _balance));

        await _lifecycle(tester, AppLifecycleState.inactive);
        expect(find.byType(PrivacyCoverSheet), findsOneWidget);
        // The amount is still in the tree but painted over; what matters for
        // the switcher snapshot is that the cover is opaque and on top.
        final sheet = tester.widget<Material>(
          find.descendant(
            of: find.byType(PrivacyCoverSheet),
            matching: find.byType(Material),
          ),
        );
        expect(sheet.color?.a, 1.0);
      },
    );

    testWidgets(
      'F1-07-64 every phase down to paused stays covered; resumed uncovers',
      (tester) async {
        sizeView(tester);
        await pumpRk(tester, const PrivacyCover(child: _balance));

        // The legal backgrounding sequence: resumed → inactive → hidden →
        // paused. Every rung is covered, so the snapshot can be taken at any
        // of them without a balance in it.
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          await _lifecycle(tester, state);
          expect(
            find.byType(PrivacyCoverSheet),
            findsOneWidget,
            reason: '$state must be covered',
          );
        }

        // Coming back up: still covered until the app is fully resumed.
        await _lifecycle(tester, AppLifecycleState.hidden);
        await _lifecycle(tester, AppLifecycleState.inactive);
        expect(find.byType(PrivacyCoverSheet), findsOneWidget);
        await _lifecycle(tester, AppLifecycleState.resumed);
        expect(find.byType(PrivacyCoverSheet), findsNothing);
      },
    );

    testWidgets(
      'F1-07-64 the cover carries the mark and nothing else — no book, no '
      'name, no number',
      (tester) async {
        sizeView(tester);
        await pumpRk(
          tester,
          const PrivacyCover(
            child: Scaffold(
              body: Center(child: Text('Ramesh · ₹4,81,000 · SBI Saving')),
            ),
          ),
        );
        await _lifecycle(tester, AppLifecycleState.inactive);

        final cover = find.byType(PrivacyCoverSheet);
        expect(
          find.descendant(of: cover, matching: find.byType(SealedMark)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cover, matching: find.byType(Text)),
          findsNothing,
        );
      },
    );

    testWidgets(
      'F1-07-64 the cover renders in EN/PA/HI on a 360x800 phone at 200%',
      (tester) async {
        sizeView(tester, width: 360, height: 800);
        for (final locale in lockLocales) {
          await pumpRk(
            tester,
            const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: PrivacyCover(child: _balance),
            ),
            locale: locale,
          );
          await _lifecycle(tester, AppLifecycleState.inactive);
          expect(find.byType(PrivacyCoverSheet), findsOneWidget);
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      },
    );
  });
}
