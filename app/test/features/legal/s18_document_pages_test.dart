// F1-07-336 / F1-07-337 — S18.1 Terms and S18.2 Privacy through the one
// shared document template (13 §3.2 rows S18.1/S18.2, ADR 2026-09-02), and
// the honest missing-content state that stands in for prose the app is not
// allowed to invent (07 §1 rule 6 — no dead ends).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/legal/screens/s18_1_terms_screen.dart';
import 'package:rukka_folio/features/legal/screens/s18_2_privacy_screen.dart';
import 'package:rukka_folio/features/legal/widgets/legal_document.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

void main() {
  group('S18.1 / S18.2 document pages', () {
    testWidgets(
      'F1-07-336 both render the same template, and say plainly that the '
      'document is not published yet rather than showing invented prose',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        for (final (screen, title) in <(Widget, String)>[
          (const TermsScreen(), l10n.legalTermsTitle),
          (const PrivacyScreen(), l10n.legalPrivacyTitle),
        ]) {
          await pumpRk(tester, screen, viewport: rkPhone360);
          expect(find.byType(LegalDocumentPage), findsOneWidget);
          expect(find.text(title), findsOneWidget);
          expect(find.text(l10n.legalDocumentPendingBadge), findsOneWidget);
          expect(find.text(l10n.legalDocumentPendingBody), findsOneWidget);
          // The state is carried by an icon and words, not by a tint
          // (07 §1 rule 3).
          expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
        }
      },
    );

    testWidgets(
      'F1-07-337 the missing-content state is not a dead end: it offers the '
      'page that is published, in all three languages',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              var went = 0;
              await pumpRk(
                tester,
                PrivacyScreen(onOpenWhatWeSee: () => went++),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              final action = find.text(l10n.legalDocumentPendingAction);
              expect(
                action,
                findsOneWidget,
                reason: '${locale.languageCode} @$scale on $viewport',
              );
              expectTextFits(
                tester,
                reason: '${locale.languageCode} @$scale on $viewport',
              );
              // At 200 % the card runs past the fold on a 360 px phone: the
              // door has to be scrolled to before it can be pressed.
              await tester.ensureVisible(action);
              await tester.pumpAndSettle();
              await tester.tap(action);
              await tester.pump();
              expect(went, 1);
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
