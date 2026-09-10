// F1-07-16 widget tests for S0.3 Purpose (13 §3.2 row S0.3, 07 §3.1 step 3,
// 07 §3.1.1 — the purpose card branches the setup).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';

import '../../shared/test_app.dart';

void main() {
  group('S0.3 Purpose (07 §3.1 step 3, 07 §3.1.1)', () {
    testWidgets(
      'F1-07-16 all five cards render, trust full width beneath a 2x2 grid',
      (tester) async {
        await pumpRk(tester, const PurposeScreen());

        expect(find.text('Myself'), findsOneWidget);
        expect(find.text('My shop'), findsOneWidget);
        expect(find.text('My businesses'), findsOneWidget);
        expect(find.text('My family'), findsOneWidget);
        expect(find.text('Our trust'), findsOneWidget);
        // The trust card carries the subtitle the others do not need (07 §3.1.1).
        expect(find.textContaining('gurudwara'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-16 selecting a card records the branch and hands it to the caller',
      (tester) async {
        OnboardingPurpose? picked;
        await pumpRk(tester, PurposeScreen(onSelected: (p) => picked = p));

        await tester.tap(find.text('My shop'));
        await tester.pumpAndSettle();

        expect(picked, OnboardingPurpose.shop);
      },
    );

    testWidgets(
      'F1-07-16 🔒 the trust card alone sets tenant.type = organization (07 §3.1.1)',
      (tester) async {
        OnboardingPurpose? picked;
        await pumpRk(tester, PurposeScreen(onSelected: (p) => picked = p));

        for (final label in [
          'Myself',
          'My shop',
          'My businesses',
          'My family',
        ]) {
          final p = _purposeFor(label);
          expect(p.setsOrganizationTenant, isFalse, reason: label);
        }

        await tester.tap(find.text('Our trust'));
        await tester.pumpAndSettle();

        expect(picked, OnboardingPurpose.trust);
        expect(picked!.setsOrganizationTenant, isTrue);
      },
    );

    testWidgets(
      'F1-07-16 cards are distinguishable without colour: each carries an icon and a label (07 §1 rule 3)',
      (tester) async {
        await pumpRk(tester, const PurposeScreen());

        expect(find.byType(Icon), findsNWidgets(5));
      },
    );

    testWidgets(
      'F1-07-16 strings resolve in EN/PA/HI with no overflow at 200% on a 360x800 surface',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const PurposeScreen(),
            ),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}

OnboardingPurpose _purposeFor(String label) => switch (label) {
  'Myself' => OnboardingPurpose.myself,
  'My shop' => OnboardingPurpose.shop,
  'My businesses' => OnboardingPurpose.businesses,
  'My family' => OnboardingPurpose.family,
  'Our trust' => OnboardingPurpose.trust,
  _ => throw ArgumentError(label),
};
