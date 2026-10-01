// F1-24b-11 / F1-24b-12 — S1's verb buttons when the tenant is read-only
// (ADR 2026-09-24b §13: read-only blocks every new envelope; ADR 2026-09-05g
// §5: lapsed ≠ locked — reading stays; 13 §4.3 disabled-with-reason; 07 §1
// rules 3 and 6).
//
// The verbs ask the public `entryRestrictionFor` (features/entry) — the same
// gate S2's Save asks — so Home and Save cannot disagree about read-only.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/features/home/widgets/home_verb_gate.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';

import '../../shared/test_app.dart';

Entitlement reading(
  EntitlementGraceKind grace, {
  EntitlementSourceKind source = EntitlementSourceKind.fresh,
}) => Entitlement.fromToken(
  tenantId: 'tenant-test',
  plan: RkPlan.family,
  limits: rkTierFor(RkPlan.family).limits,
  graceKind: grace,
  times: const EntitlementTokenTimes(),
  source: source,
  activeMembers: 1,
);

const _verbs = ['Money in', 'Money out', 'Gave on credit', 'Took on credit'];
const _reasonEn = 'New entries are paused because your plan has ended.';

Finder verbButton(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton));

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('F1-24b-11 Home verbs under read-only', () {
    testWidgets('F1-24b-11 read-only: every verb disabled, with the reason', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      final tapped = <EntryKind>[];
      await pumpRk(
        tester,
        EntitlementScope(
          source: FakeEntitlementSource(
            entitlement: reading(EntitlementGraceKind.lapsed),
          ),
          child: HomeScreen(onVerb: tapped.add),
        ),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );

      for (final label in _verbs) {
        final button = tester.widget<OutlinedButton>(verbButton(label));
        expect(button.onPressed, isNull, reason: '$label is still live');
        // Still drawn: a disabled verb never disappears (07 §1 rule 6).
        expect(find.text(label), findsOneWidget);
      }
      // Disabled-with-reason (13 §4.3), words and an icon — never colour
      // alone (07 §1 rule 3).
      final reason = find.byKey(HomeVerbButtons.reasonKey);
      expect(reason, findsOneWidget);
      expect(
        find.descendant(of: reason, matching: find.text(_reasonEn)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: reason, matching: find.byIcon(Icons.lock_outline)),
        findsOneWidget,
      );

      await tester.tap(find.text('Money in'), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isEmpty);
      // Lapsed ≠ locked: the position is still on screen.
      expect(find.text('Total money you have'), findsOneWidget);
      await unmount(tester);
    });

    final live = <String, EntitlementSource>{
      'active': FakeEntitlementSource(
        entitlement: reading(EntitlementGraceKind.none),
      ),
      'dunning grace': FakeEntitlementSource(
        entitlement: reading(EntitlementGraceKind.dunning),
      ),
      'offline grace (stale lapsed token)': FakeEntitlementSource(
        entitlement: reading(
          EntitlementGraceKind.lapsed,
          source: EntitlementSourceKind.stale,
        ),
      ),
      'failed read (ADR 2026-09-24b §14)': FakeEntitlementSource(
        failure: StateError('unreadable'),
      ),
    };
    for (final e in live.entries) {
      testWidgets('F1-24b-11 ${e.key}: verbs stay live, no reason line', (
        tester,
      ) async {
        final seed = await seedSoloLedger();
        final tapped = <EntryKind>[];
        await pumpRk(
          tester,
          EntitlementScope(
            source: e.value,
            child: HomeScreen(onVerb: tapped.add),
          ),
          ledger: seed.ledger,
          viewport: rkTallViewport,
        );
        expect(find.byKey(HomeVerbButtons.reasonKey), findsNothing);
        await tester.tap(find.text('Money out'));
        await tester.pump();
        expect(tapped, const [EntryKind.moneyOut]);
        await unmount(tester);
      });
    }

    testWidgets('F1-24b-11 no scope at all: untokened, verbs live', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      final tapped = <EntryKind>[];
      await pumpRk(
        tester,
        HomeScreen(onVerb: tapped.add),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );
      expect(find.byKey(HomeVerbButtons.reasonKey), findsNothing);
      await tester.tap(find.text('Money in'));
      await tester.pump();
      expect(tapped, const [EntryKind.moneyIn]);
      await unmount(tester);
    });

    testWidgets('F1-24b-11 the source is swapped: the verbs follow it', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      Widget home(EntitlementSource s) => EntitlementScope(
        source: s,
        child: HomeScreen(onVerb: (_) {}),
      );
      await pumpRk(
        tester,
        home(
          FakeEntitlementSource(
            entitlement: reading(EntitlementGraceKind.none),
          ),
        ),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );
      expect(find.byKey(HomeVerbButtons.reasonKey), findsNothing);
      await pumpRk(
        tester,
        home(
          FakeEntitlementSource(
            entitlement: reading(EntitlementGraceKind.lapsed),
          ),
        ),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );
      expect(find.byKey(HomeVerbButtons.reasonKey), findsOneWidget);
      await unmount(tester);
    });
  });

  group('F1-24b-12 the reason line at 200 % in EN/PA/HI', () {
    const reasons = {
      'en': _reasonEn,
      'pa': 'ਤੁਹਾਡਾ ਪਲਾਨ ਖ਼ਤਮ ਹੋ ਗਿਆ ਹੈ, ਇਸ ਲਈ ਨਵੀਆਂ ਐਂਟਰੀਆਂ ਰੁਕੀਆਂ ਹੋਈਆਂ ਹਨ।',
      'hi': 'आपका प्लान समाप्त हो गया है, इसलिए नई एंट्री रुकी हुई हैं।',
    };
    for (final locale in rkLocales) {
      for (final phone in rkPhones) {
        testWidgets('F1-24b-12 ${locale.languageCode} at 200 % on '
            '${phone.width.toInt()}x${phone.height.toInt()}', (tester) async {
          await pumpRk(
            tester,
            Center(
              child: EntitlementScope(
                source: FakeEntitlementSource(
                  entitlement: reading(EntitlementGraceKind.lapsed),
                ),
                child: const Material(
                  child: SingleChildScrollView(child: HomeVerbGate()),
                ),
              ),
            ),
            locale: locale,
            viewport: phone,
            textScale: 2,
          );
          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: find.byKey(HomeVerbButtons.reasonKey),
              matching: find.text(reasons[locale.languageCode]!),
            ),
            findsOneWidget,
          );
          expectTextFits(tester);
        });
      }
    }
  });
}
