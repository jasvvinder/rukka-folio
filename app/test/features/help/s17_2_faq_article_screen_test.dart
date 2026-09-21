// F1-07-393 … F1-07-395 — S17.2 FAQ article (13 §3.2 row S17.2 "one answer,
// plain language"; 07 §22 🔒).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/help/faq_catalog.dart';
import 'package:rukka_folio/features/help/screens/s17_2_faq_article_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

void main() {
  group('S17.2 FAQ article', () {
    testWidgets(
      'F1-07-393 every answer in the catalogue draws its question as the '
      'page heading and all of its paragraphs — none is a half-written page',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        for (final article in faqArticles) {
          await pumpRk(
            tester,
            FaqArticleScreen(
              id: article.id,
              onBackToHub: () {},
              onOpenContact: () {},
            ),
            viewport: rkTallViewport,
          );
          final text = faqText(l10n, article.id)!;
          expect(
            find.text(text.question),
            findsOneWidget,
            reason: '${article.id} has no heading',
          );
          expect(
            text.paragraphs,
            isNotEmpty,
            reason: '${article.id} has no answer',
          );
          for (final p in text.paragraphs) {
            expect(
              find.text(p),
              findsOneWidget,
              reason: '${article.id} is missing a paragraph',
            );
          }
          // No answer is a dead end: the ways on are always drawn
          // (07 §1 rule 6 🔒).
          expect(find.text(l10n.helpArticleStuck), findsOneWidget);
          expect(find.text(l10n.helpArticleMore), findsOneWidget);
          expect(find.text(l10n.helpContactTitle), findsOneWidget);
        }
      },
    );

    testWidgets('F1-07-408 the two doors reach their own callbacks', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final opened = <String>[];
      await pumpRk(
        tester,
        FaqArticleScreen(
          id: 'offline',
          onBackToHub: () => opened.add('hub'),
          onOpenContact: () => opened.add('contact'),
        ),
        viewport: rkTallViewport,
      );
      await tester.tap(find.text(l10n.helpArticleMore));
      await tester.tap(find.text(l10n.helpContactTitle));
      await tester.pumpAndSettle();
      expect(opened, ['hub', 'contact']);
    });

    testWidgets(
      'F1-07-394 an id the catalogue does not know draws the missing state '
      'with its way back, never an empty page (13 §4.3)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        var back = 0;
        await pumpRk(
          tester,
          FaqArticleScreen(
            id: 'renamed_last_year',
            onBackToHub: () => back++,
            onOpenContact: () {},
          ),
          viewport: rkTallViewport,
        );

        expect(find.text(l10n.helpArticleMissingTitle), findsOneWidget);
        expect(find.text(l10n.helpArticleMissingBody), findsOneWidget);
        // The answer-shaped furniture is absent: there is no answer here.
        expect(find.text(l10n.helpArticleStuck), findsNothing);

        await tester.tap(find.text(l10n.helpArticleMissingAction));
        await tester.pumpAndSettle();
        expect(back, 1);

        // An empty id — what a malformed link gives — lands in the same
        // state rather than throwing.
        await pumpRk(
          tester,
          FaqArticleScreen(id: '', onBackToHub: () {}, onOpenContact: () {}),
          viewport: rkTallViewport,
        );
        expect(find.text(l10n.helpArticleMissingTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'F1-07-395 the longest answer resolves in EN, PA and HI and nothing is '
      'cut at 130 % or 200 % on either phone, scrolled to the end',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          // `support_powers` is the three-paragraph answer with the longest
          // sentences — if any answer overflows, it is this one.
          for (final id in ['support_powers', 'locked_date']) {
            for (final viewport in rkPhones) {
              for (final scale in rkTextScales) {
                await pumpRk(
                  tester,
                  FaqArticleScreen(
                    id: id,
                    onBackToHub: () {},
                    onOpenContact: () {},
                  ),
                  locale: locale,
                  viewport: viewport,
                  textScale: scale,
                );
                expect(
                  find.text(l10n.helpArticleAppbar),
                  findsWidgets,
                  reason: '${locale.languageCode} app-bar title missing',
                );
                expectTextFits(
                  tester,
                  reason:
                      '$id ${locale.languageCode} @$scale on $viewport, '
                      'above the fold',
                );
                await tester.scrollUntilVisible(
                  find.text(l10n.helpArticleStuck),
                  300,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.pumpAndSettle();
                expectTextFits(
                  tester,
                  reason:
                      '$id ${locale.languageCode} @$scale on $viewport, '
                      'scrolled to the doors',
                );
                expect(tester.takeException(), isNull);
              }
            }
          }
        }
      },
    );
  });
}
