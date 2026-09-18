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

  // 07 §14 🔒 lists Partner positions as *"shared-ownership businesses
  // only"*, and ADR 2026-09-09b 🔒 keeps the word off a Just-me book
  // altogether, so the row only exists when the screen is told the book is a
  // shared business. The order cases therefore pump the shared-business
  // screen — the one book whose list is the full eleven.
  // (`s8_1_partner_positions_row_test.dart` owns the other half: that a
  // Just-me book says no partner word anywhere.)
  const shared = ReportsListScreen(showPartnerPositions: true);

  group('S8.1 Reports list (07 §14 report order)', () {
    testWidgets('F1-07-28 S8.1 Reports list screen renders (07 §14)', (
      tester,
    ) async {
      await pumpRk(tester, shared);

      expect(find.text('Reports'), findsOneWidget);
    });

    testWidgets(
      'F1-07-28 renders every report from 07 §14 in order, Day Book first, Business comparison last',
      (tester) async {
        await pumpRk(tester, shared);

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
      'F1-07-28 with no destination wired, every report is disabled-with-reason — never a silently inert tap (07 §1 rule 6)',
      (tester) async {
        await pumpRk(tester, shared);

        expect(
          find.byIcon(Icons.schedule),
          findsNWidgets(expectedOrder.length),
        );
        expect(
          find.text('This report has not been built yet.'),
          findsNWidgets(expectedOrder.length),
        );
      },
    );

    // `pumpRk`'s own `textScale:`/`viewport:` (M5-T1). The wrapper this loop
    // used to build — a bare `MediaQueryData(textScaler: …)` — carries
    // `size: Size.zero`, so the list was being asserted against a screen with
    // no area: nothing can overflow nothing, and the case passed for the wrong
    // reason.
    for (final locale in rkLocales) {
      for (final phone in rkPhones) {
        for (final scale in rkTextScales) {
          testWidgets(
            'F1-07-28 Reports list resolves in ${locale.languageCode} without '
            'a cut word at ${scale}x on ${phone.width.toInt()}x'
            '${phone.height.toInt()}',
            (tester) async {
              await pumpRk(
                tester,
                shared,
                locale: locale,
                textScale: scale,
                viewport: phone,
              );

              expect(tester.takeException(), isNull);
              expectTextFits(tester, reason: 'S8.1 at ${scale}x on $phone');
            },
          );
        }
      }
    }
  });
}
