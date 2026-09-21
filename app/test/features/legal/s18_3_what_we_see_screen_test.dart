// F1-07-333 … F1-07-335 — S18.3 What we can and cannot see (07 §23 🔒,
// 12 §2 impossibility table, 12 §1 the other half, ADR 2026-09-05c §1
// residency).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/legal/screens/s18_3_what_we_see_screen.dart';
import 'package:rukka_folio/features/legal/widgets/legal_document.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

/// S18.3 is a long page: 8 claim cards, 4 headings and 6 paragraphs. A lazy
/// list builds no element below the fold, so a *content* assertion needs a
/// viewport tall enough to hold the lot (the layout cases below use the real
/// phone widths instead).
const _tall = Size(400, 8000);

void main() {
  group('S18.3 What we can and cannot see', () {
    testWidgets(
      'F1-07-333 renders all eight rows of the 12 §2 impossibility table, '
      'each with its reason',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpRk(tester, const WhatWeSeeScreen(), viewport: _tall);

        // 12 §2 has eight rows; the page is a copy of it, not a selection.
        final claims = whatWeSeeBlocks(l10n).whereType<LegalClaim>().toList();
        expect(claims, hasLength(8));
        for (final c in claims) {
          expect(find.text(c.claim), findsOneWidget, reason: c.claim);
          expect(find.text(c.why), findsOneWidget, reason: c.why);
        }
      },
    );

    testWidgets(
      'F1-07-334 carries the residency line (India), the rooted-phone line '
      'and the honest what-we-can-see half',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpRk(tester, const WhatWeSeeScreen(), viewport: _tall);

        // 07 §23 🔒 names both lines explicitly.
        expect(find.text(l10n.legalSeeIndiaHeading), findsOneWidget);
        expect(find.textContaining('India'), findsWidgets);
        expect(find.text(l10n.legalSeeRootedHeading), findsOneWidget);
        expect(find.text(l10n.legalSeeRootedBody), findsOneWidget);

        // 12 §1 — what the console *can* see, stated rather than skipped.
        expect(find.text(l10n.legalSeeCanHeading), findsOneWidget);
        expect(find.text(l10n.legalSeeCanBody), findsOneWidget);

        // The page never claims a *policy* where the guarantee is structural
        // (12 §2): the closing line says so in as many words.
        expect(find.text(l10n.legalSeeFooter), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-335 every line resolves in EN, PA and HI and nothing is cut at '
      '130 % or 200 % on either phone',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                const WhatWeSeeScreen(),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(find.text(l10n.legalSeeTitle), findsWidgets);
              // Scroll the whole page so every row is laid out and measured,
              // not only the ones above the fold.
              final list = find.byType(Scrollable).first;
              for (var i = 0; i < 12; i++) {
                expectTextFits(
                  tester,
                  reason: '${locale.languageCode} @$scale on $viewport',
                );
                await tester.drag(list, const Offset(0, -400));
                await tester.pump();
              }
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
