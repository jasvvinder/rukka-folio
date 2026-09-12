// F1-07-28 (07 §14 🔒 — S8.1's report list) for S8.1 Reports list.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/reports/screens/s8_1_reports_list_screen.dart';

import '../../shared/test_app.dart';

void main() {
  // 07 §14 🔒 report list order.
  const expectedOrder = [
    'Day Book',
    'Cash Book',
    'A/C statement (any)',
    'Trial Balance',
    'You-will-get / You-will-give with ageing',
    'Profit/Loss (per FY/range)',
    'Full Position',
    'Advances ageing',
    'Family Reconciliation',
    'Partner positions',
    'Business comparison',
  ];

  group('S8.1 Reports list (07 §14 report order)', () {
    testWidgets('F1-07-28 S8.1 Reports list screen renders (07 §14)', (
      tester,
    ) async {
      await pumpRk(tester, const ReportsListScreen());

      expect(find.text('Reports'), findsOneWidget);
    });

    testWidgets(
      'F1-07-28 renders every report from 07 §14 in order, Day Book first, Business comparison last',
      (tester) async {
        await pumpRk(tester, const ReportsListScreen());

        final titles = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .toList();
        var cursor = -1;
        for (final title in expectedOrder) {
          final at = titles.indexOf(title);
          expect(at, greaterThan(-1), reason: 'missing report: $title');
          expect(at, greaterThan(cursor), reason: '$title out of 07 §14 order');
          cursor = at;
        }
      },
    );

    testWidgets(
      'F1-07-28 every report is disabled-with-reason — S8.2 has not landed, never a silently inert tap (07 §1 rule 6)',
      (tester) async {
        await pumpRk(tester, const ReportsListScreen());

        expect(
          find.byIcon(Icons.schedule),
          findsNWidgets(expectedOrder.length),
        );
        expect(
          find.text('The report viewer has not been built yet.'),
          findsNWidgets(expectedOrder.length),
        );
      },
    );

    for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
      testWidgets(
        'F1-07-28 Reports list resolves in ${locale.languageCode} without overflow at 200%',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: const ReportsListScreen(),
            ),
            locale: locale,
          );

          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
