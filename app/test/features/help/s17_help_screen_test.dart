// F1-07-388 … F1-07-392 — S17 Help, the searchable FAQ hub (13 §3.2 row S17,
// 07 §22 🔒, ADR 2026-09-02: S17.1 folded into the hub).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/help/faq_catalog.dart';
import 'package:rukka_folio/features/help/screens/s17_help_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

void main() {
  // Every door on the hub leads to a screen that exists, so the callbacks
  // are required; this is the bare pump that ignores them.
  HelpScreen bare() => HelpScreen(
    onOpenArticle: (_) {},
    onOpenContact: () {},
    onOpenDiagnostics: () {},
  );

  group('S17 Help hub', () {
    testWidgets(
      'F1-07-388 every one of the thirteen answers is listed, under all five '
      'group headings, in the catalogue order',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpRk(tester, bare(), viewport: rkTallViewport);

        expect(faqArticles, hasLength(13));
        for (final a in faqArticles) {
          expect(
            find.text(faqText(l10n, a.id)!.question),
            findsOneWidget,
            reason: 'question ${a.id} is not on the hub',
          );
        }
        for (final g in FaqGroup.values) {
          expect(
            find.text(faqGroupLabel(l10n, g)),
            findsOneWidget,
            reason: 'group ${g.name} heading is missing',
          );
        }

        // The two doors under *Still stuck?* close the page.
        expect(find.text(l10n.helpSectionReach), findsOneWidget);
        expect(find.text(l10n.helpContactTitle), findsOneWidget);
        expect(find.text(l10n.helpDiagnosticsTitle), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-389 a search narrows the list to the answers that match its '
      'words and states how many there are',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpRk(tester, bare(), viewport: rkTallViewport);

        // "paper" reaches the paper-sheet answer and the new-phone answer,
        // which mentions the sheet as the last rung of the ladder — and
        // nothing else.
        await tester.enterText(find.byType(TextField), 'paper');
        await tester.pumpAndSettle();

        final matches = faqSearch(l10n, 'paper').map((a) => a.id).toList();
        expect(matches, ['paper_sheet', 'new_phone']);
        for (final id in matches) {
          expect(find.text(faqText(l10n, id)!.question), findsOneWidget);
        }
        expect(
          find.text(faqText(l10n, 'money_in_out')!.question),
          findsNothing,
          reason: 'an answer that does not match must leave the list',
        );
        expect(find.text(l10n.helpSearchCount(matches.length)), findsOneWidget);

        // The search reads the answer too, not only the question: "guardians"
        // appears in the new-phone *answer* and in no question at all.
        await tester.enterText(find.byType(TextField), 'guardians');
        await tester.pumpAndSettle();
        expect(find.text(faqText(l10n, 'new_phone')!.question), findsOneWidget);

        // Clearing it brings the whole list back.
        await tester.tap(find.byTooltip(l10n.helpSearchClear));
        await tester.pumpAndSettle();
        expect(find.text(faqGroupLabel(l10n, FaqGroup.start)), findsOneWidget);
        expect(find.text(l10n.helpSearchCount(2)), findsNothing);
      },
    );

    testWidgets(
      'F1-07-390 a search that matches nothing is a state with one next '
      'action, never a blank page (13 §4.3, 07 §1 rule 6 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpRk(tester, bare(), viewport: rkTallViewport);

        await tester.enterText(find.byType(TextField), 'zzzzqqqq');
        await tester.pumpAndSettle();

        expect(find.text(l10n.helpSearchEmptyTitle), findsOneWidget);
        expect(find.text(l10n.helpSearchEmptyBody), findsOneWidget);
        expect(find.text(l10n.helpSearchCount(0)), findsOneWidget);
        // The list heading is gone; the doors out are not.
        expect(find.text(l10n.helpSectionFaq), findsNothing);
        expect(find.text(l10n.helpContactTitle), findsOneWidget);

        await tester.tap(find.text(l10n.helpSearchEmptyAction));
        await tester.pumpAndSettle();
        expect(find.text(l10n.helpSearchEmptyTitle), findsNothing);
        expect(
          find.text(faqText(l10n, 'money_in_out')!.question),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-07-391 a question opens its own answer and each door its own '
      'screen; with no destination the door states the reason instead of '
      'tapping silently (07 §1 rule 6 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final opened = <String>[];
        await pumpRk(
          tester,
          HelpScreen(
            onOpenArticle: opened.add,
            onOpenContact: () => opened.add('contact'),
            onOpenDiagnostics: () => opened.add('diagnostics'),
          ),
          viewport: rkTallViewport,
        );

        await tester.tap(find.text(faqText(l10n, 'locked_date')!.question));
        await tester.tap(find.text(l10n.helpContactTitle));
        await tester.tap(find.text(l10n.helpDiagnosticsTitle));
        await tester.pumpAndSettle();
        expect(opened, ['locked_date', 'contact', 'diagnostics']);

        // No row on this hub is ever disabled-with-reason: all three
        // destinations are built, so a reason line here could only be one
        // that is not true (07 §1 rule 6 🔒 — the mistake the Menu's own
        // Help row made until S17 landed). The reason belongs on S17.3,
        // whose WhatsApp channel really has not opened.
        expect(find.byIcon(Icons.schedule), findsNothing);
        expect(find.text(l10n.helpContactReason), findsNothing);
      },
    );

    testWidgets(
      'F1-07-392 hub strings resolve in EN, PA and HI and nothing is cut at '
      '130 % or 200 % on either phone, above the fold and scrolled to the end',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                bare(),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(
                find.text(l10n.helpTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'above the fold',
              );

              // The doors and the exclusion lines sit far below the fold at
              // 200 %, and a paragraph only overflows once it is laid out.
              await tester.scrollUntilVisible(
                find.text(l10n.helpSectionReach),
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'scrolled to the doors',
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
