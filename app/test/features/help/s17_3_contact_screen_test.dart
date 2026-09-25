// F1-07-396 … F1-07-398 — S17.3 Contact support (13 §3.2 row S17.3
// "WhatsApp primary; states what support cannot do"; 07 §22 🔒, which makes
// the four limits of 06 §8 🔒 normative on this screen).
//
// ⛔ The screen must not launch anything while ADR 2026-09-19 is unratified
// (PLAN-11). F1-07-397 pins that: the channel row is disabled-with-reason,
// and the page still offers the person a next action.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/help/faq_catalog.dart';
import 'package:rukka_folio/features/help/screens/s17_3_contact_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

void main() {
  group('S17.3 Contact support', () {
    testWidgets(
      'F1-07-396 the page states all four things support cannot do, and that '
      'none of them exists in the app (06 §8 🔒, 07 §22 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpRk(
          tester,
          ContactSupportScreen(onOpenDiagnostics: () {}, onOpenArticle: (_) {}),
          viewport: rkTallViewport,
        );

        expect(find.text(l10n.helpCannotTitle), findsOneWidget);
        for (final limit in [
          l10n.helpCannotRead,
          l10n.helpCannotKey,
          l10n.helpCannotMember,
          l10n.helpCannotCeremony,
        ]) {
          expect(find.text(limit), findsOneWidget, reason: 'missing: $limit');
        }
        // "None of these exist in the app, so nobody can be talked into one"
        // — the sentence that makes the list a defence and not a policy.
        expect(find.text(l10n.helpCannotFootnote), findsOneWidget);
        // Each limit is carried by an icon as well as by its words, so the
        // meaning survives grayscale (07 §1 rule 3).
        expect(find.byIcon(Icons.block), findsNWidgets(4));
      },
    );

    testWidgets(
      'F1-07-397 the WhatsApp row opens nothing and says why, and the page '
      'still offers a next action (PLAN-11 / ADR 2026-09-19; 07 §1 rule 6 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        var diagnostics = 0;
        final articles = <String>[];
        await pumpRk(
          tester,
          ContactSupportScreen(
            // `onOpenChannel` deliberately left null — this is the production
            // wiring in `helpRoutes`.
            onOpenDiagnostics: () => diagnostics++,
            onOpenArticle: articles.add,
          ),
          viewport: rkTallViewport,
        );

        // The channel is named and its row is inert, with the reason stated
        // in words beside a clock icon.
        expect(find.text(l10n.helpContactValue), findsOneWidget);
        expect(find.text(l10n.helpContactReason), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsOneWidget);

        // Tapping it does nothing at all — no callback, no exception.
        await tester.tap(find.text(l10n.helpContactValue));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(diagnostics, 0);
        expect(articles, isEmpty);

        // The ways on that do work.
        await tester.tap(find.text(faqText(l10n, 'support_powers')!.question));
        await tester.tap(find.text(l10n.helpDiagnosticsTitle));
        await tester.pumpAndSettle();
        expect(articles, ['support_powers']);
        expect(diagnostics, 1);
      },
      skip: true, // superseded by ADR 2026-09-25 §4; re-lands at M12
    );

    testWidgets(
      'F1-07-409 with the channel seam supplied the row becomes live — the '
      'seam is absent, not missing',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        var channel = 0;
        await pumpRk(
          tester,
          ContactSupportScreen(
            onOpenChannel: () => channel++,
            onOpenDiagnostics: () {},
            onOpenArticle: (_) {},
          ),
          viewport: rkTallViewport,
        );
        expect(find.text(l10n.helpContactReason), findsNothing);
        await tester.tap(find.text(l10n.helpContactValue));
        await tester.pumpAndSettle();
        expect(channel, 1);
      },
    );

    testWidgets(
      'F1-07-398 strings resolve in EN, PA and HI and nothing is cut at '
      '130 % or 200 % on either phone, scrolled to the end',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                ContactSupportScreen(
                  onOpenDiagnostics: () {},
                  onOpenArticle: (_) {},
                ),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(
                find.text(l10n.helpContactTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'above the fold',
              );
              await tester.scrollUntilVisible(
                find.text(l10n.helpDiagnosticsTitle),
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
