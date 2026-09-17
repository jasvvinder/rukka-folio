// F1 widget tests for the S8.1 → S14 door (13 §3.2 row S14, 07 §14 🔒
// "Partner positions (02 §7.1, shared-ownership businesses only)").
//
// ADR 2026-09-09b 🔒 / 02 §7.1 🔒: a *Just me* business never mentions
// partners, ratios or profit distribution **anywhere**. The row is therefore
// absent — not merely disabled — for every book that is not a shared
// business, and the negative is asserted over the whole widget tree.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BookOwnership;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/partners/partners_paths.dart';
import 'package:rukka_folio/features/reports/screens/s8_1_reports_list_route.dart';
import 'package:rukka_folio/features/reports/screens/s8_1_reports_list_screen.dart';
import 'package:rukka_folio/features/reports/widgets/reports_row.dart';

import '../../shared/test_app.dart';

/// Tall enough that every one of 07 §14's rows is laid out and tappable.
const tall = Size(500, 1600);

/// Every string anywhere in the tree, for the negative assertion.
List<String> textsOn(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .toList();

/// The partner vocabulary ADR 2026-09-09b 🔒 forbids on a Just-me book, in
/// all three languages — taken from the ARB's own wordings
/// (`reports.partner_positions.row.title`, `partners.*`) so a retranslation
/// cannot quietly slip the word past this test.
const forbidden = [
  'Partner',
  'partner',
  'ਪਾਰਟਨਰ',
  'पार्टनर',
  'Ratio',
  'ratio',
  'Profit distribution',
];

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('S8.1 Partner positions row (07 §14 🔒, ADR 2026-09-09b 🔒)', () {
    testWidgets(
      'F1-07-128 a shared business shows Partner positions and it opens S14 '
      'for that book (13 §3.2 row S14)',
      (tester) async {
        final seed = await seedSoloLedger();
        final bookId = await seed.ledger.createBook(
          name: 'Singh Brothers',
          type: BookType.business,
          ownership: BookOwnership.shared,
          ownerNames: const ['Gurpreet', 'Harjit'],
          ownerShares: const [1, 1],
        );
        String? opened;
        await pumpRk(
          tester,
          ReportsListRoute(
            bookId: bookId,
            onOpenPartnerPositions: (id) => opened = PartnersPaths.of(id),
          ),
          ledger: seed.ledger,
          viewport: tall,
        );
        await tester.pumpAndSettle();

        expect(find.text('Partner positions'), findsOneWidget);
        await tester.tap(find.text('Partner positions'));
        await tester.pump();
        expect(opened, '/books/$bookId/partners');
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-128 a Just-me book never mentions partners anywhere in the tree '
      '— the row is absent, not disabled (ADR 2026-09-09b 🔒)',
      (tester) async {
        final seed = await seedSoloLedger();
        final justMeBooks = [
          // A personal book, and a business whose owner never took a partner.
          seed.bookId,
          await seed.ledger.createBook(
            name: 'My shop',
            type: BookType.business,
          ),
        ];
        for (final (book, locale) in [
          for (final book in justMeBooks)
            for (final locale in rkLocales) (book, locale),
        ]) {
          await pumpRk(
            tester,
            ReportsListRoute(bookId: book, onOpenPartnerPositions: (_) {}),
            ledger: seed.ledger,
            locale: locale,
            viewport: tall,
          );
          await tester.pumpAndSettle();

          final texts = textsOn(tester);
          for (final word in forbidden) {
            expect(
              texts.any((t) => t.contains(word)),
              isFalse,
              reason:
                  'a Just-me book said "$word" on S8.1 in '
                  '${locale.languageCode} (ADR 2026-09-09b)',
            );
          }
          // The rest of 07 §14's order is untouched: ten rows, not eleven.
          expect(find.byType(ReportsDisabledRow), findsNWidgets(10));
          await unmount(tester);
        }
      },
    );

    testWidgets(
      'F1-07-128 the screen itself holds the rule: no partner row unless it '
      'is told the book is a shared business',
      (tester) async {
        await pumpRk(tester, const ReportsListScreen(), viewport: tall);
        expect(find.text('Partner positions'), findsNothing);

        await pumpRk(
          tester,
          ReportsListScreen(
            showPartnerPositions: true,
            onOpenPartnerPositions: () {},
          ),
          viewport: tall,
        );
        expect(find.text('Partner positions'), findsOneWidget);
      },
    );

    testWidgets('F1-07-128 the row holds in EN, PA and HI at 200% on 360×800 '
        '(07 §1 rule 11)', (tester) async {
      for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
        await pumpRk(
          tester,
          ReportsListScreen(
            showPartnerPositions: true,
            onOpenPartnerPositions: () {},
          ),
          locale: locale,
          textScale: 2,
          viewport: rkPhone360,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'S8.1 overflowed in ${locale.languageCode}',
        );
      }
    });
  });
}
