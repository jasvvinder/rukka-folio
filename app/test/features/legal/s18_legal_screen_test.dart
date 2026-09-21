// F1-07-330 … F1-07-332 — S18 Legal & trust hub (13 §3.2 row S18, 07 §23 🔒,
// ADR 2026-09-02: the hub carries the designed summary card).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/legal/screens/s18_legal_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

void main() {
  group('S18 Legal & trust hub', () {
    testWidgets('F1-07-330 shows a summary card for each of S18.1–S18.4, with '
        'what-we-can-and-cannot-see first and privacy in four lines', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await pumpRk(tester, const LegalScreen(), viewport: rkTallViewport);

      for (final title in [
        l10n.legalSeeCardTitle,
        l10n.legalPrivacyCardTitle,
        l10n.legalTermsCardTitle,
        l10n.legalLicencesCardTitle,
      ]) {
        expect(find.text(title), findsOneWidget, reason: 'missing $title');
      }

      // S18.3's card leads: it is the one page with content of its own and
      // the brand's trust claim (12 §2, 11 §1).
      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(
        titles.indexOf(l10n.legalSeeCardTitle),
        lessThan(titles.indexOf(l10n.legalPrivacyCardTitle)),
      );

      // "Privacy, in four lines" is four lines, not three and not five.
      for (final line in [
        l10n.legalPrivacyCardLine1,
        l10n.legalPrivacyCardLine2,
        l10n.legalPrivacyCardLine3,
        l10n.legalPrivacyCardLine4,
      ]) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.text('4.'), findsOneWidget);
      expect(find.text('5.'), findsNothing);
    });

    testWidgets('F1-07-331 every card opens its document, and a card with no '
        'destination still shows its door rather than hiding it', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final opened = <String>[];
      await pumpRk(
        tester,
        LegalScreen(
          onOpenWhatWeSee: () => opened.add('see'),
          onOpenPrivacy: () => opened.add('privacy'),
          onOpenTerms: () => opened.add('terms'),
          onOpenLicences: () => opened.add('licences'),
        ),
        viewport: rkTallViewport,
      );

      for (final label in [
        l10n.legalSeeCardAction,
        l10n.legalPrivacyCardAction,
        l10n.legalTermsCardAction,
        l10n.legalLicencesCardAction,
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(opened, ['see', 'privacy', 'terms', 'licences']);

      // With no callbacks the doors are still drawn (07 §1 rule 6: a card
      // that simply vanished would be a door nobody can find).
      await pumpRk(tester, const LegalScreen(), viewport: rkTallViewport);
      expect(find.text(l10n.legalSeeCardAction), findsOneWidget);
    });

    testWidgets(
      'F1-07-332 hub strings resolve in EN, PA and HI and nothing is cut at '
      '130 % or 200 % on either phone',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                const LegalScreen(),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(
                find.text(l10n.legalTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason: '${locale.languageCode} @$scale on $viewport',
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
