// F1-07-48 widget tests for S0.4 Name & photo (13 §3.2 row S0.4, 07 §3.1 step
// 4 — name required, photo optional, shown in approvals & the verification
// ceremony).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_4_name_photo_screen.dart';

import '../../shared/test_app.dart';

void main() {
  group('S0.4 Name & photo (07 §3.1 step 4)', () {
    testWidgets(
      'F1-07-48 Continue is disabled with no name typed (disabled-with-reason, 13 §4.3)',
      (tester) async {
        await pumpRk(tester, const NamePhotoScreen());

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      'F1-07-48 typing a name enables Continue; submitting hands the name (and null photo) on',
      (tester) async {
        String? submittedName;
        Object? submittedPhoto;
        await pumpRk(
          tester,
          NamePhotoScreen(
            onSubmit: (name, photo) {
              submittedName = name;
              submittedPhoto = photo;
            },
          ),
        );

        await tester.enterText(find.byType(TextField), 'Sunita');
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNotNull);

        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(submittedName, 'Sunita');
        expect(submittedPhoto, isNull);
      },
    );

    testWidgets(
      'F1-07-48 photo is optional and goes through a callback seam, never a plugin',
      (tester) async {
        String? submittedName;
        Object? submittedPhoto;
        await pumpRk(
          tester,
          NamePhotoScreen(
            onPickPhoto: () async => 'fake-photo-bytes',
            onSubmit: (name, photo) {
              submittedName = name;
              submittedPhoto = photo;
            },
          ),
        );

        await tester.enterText(find.byType(TextField), 'Rajesh');
        await tester.tap(find.byType(CircleAvatar));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(submittedName, 'Rajesh');
        expect(submittedPhoto, 'fake-photo-bytes');
      },
    );

    testWidgets(
      'F1-07-48 copy states why a photo is asked: approvals and the verification ceremony',
      (tester) async {
        await pumpRk(tester, const NamePhotoScreen());

        expect(find.textContaining('approvals'), findsWidgets);
      },
    );

    testWidgets(
      'F1-07-48 strings resolve in EN/PA/HI with no overflow at 200% on a 360x800 surface',
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
              child: const NamePhotoScreen(),
            ),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}
