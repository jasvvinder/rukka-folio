// F1-07-406, F1-07-411, F1-07-413, F1-07-414 — the Help feature's route table
// (13 §3.2 rows S17, S17.2, S17.3, S17.4; features/README "Routes").
//
// F1-07-413 and F1-07-414 read the page *stack*, not the uri: `push`,
// `pushReplacement` and `pop` all leave `/help` in the uri, so a uri
// assertion cannot tell a way back from a second hub pushed on top of the
// first (07 §1 rule 6 🔒).
//
// The four screen tests pump the screens directly, so none of them can see
// whether `helpRoutes` actually mounts the destinations its callbacks push:
// a route registered at a different spelling, or an `:id` parameter read
// under the wrong name, passes every one of them and still leaves the reader
// on a blank page. This file drives a real router over `helpRoutes`.
//
// It builds its own minimal router rather than going through `main.dart`, so
// the Help feature's routing is checked without compiling the whole app.
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/help/help_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

Future<GoRouter> _pumpHelp(WidgetTester tester) async {
  final db = await openTestDb();
  final router = GoRouter(initialLocation: HelpPaths.root, routes: helpRoutes);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RkScope(
      db: db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: FakeKeyStore(),
      now: testNow,
      child: MaterialApp.router(
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: rkLocalizationsDelegates,
        theme: rkTheme(Brightness.light),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('Help routes (13 §3.2 rows S17, S17.2, S17.3, S17.4)', () {
    testWidgets(
      'F1-07-406 the hub reaches every answer, contact support and the '
      'diagnostics page through the real router — the paths are declared '
      'once and the :id parameter is read under its own name',
      (tester) async {
        rkViewport(tester, rkTallViewport);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final router = await _pumpHelp(tester);

        expect(find.text(l10n.helpTitle), findsWidgets);

        // Every catalogued id resolves to its own answer, not to the
        // missing state — which is what a mis-named path parameter would
        // give (`state.pathParameters['id']` returning null).
        for (final article in faqArticles) {
          unawaited(router.push(HelpPaths.articleOf(article.id)));
          await tester.pumpAndSettle();
          expect(
            find.text(faqText(l10n, article.id)!.question),
            findsOneWidget,
            reason: '${article.id} did not resolve through the router',
          );
          expect(find.text(l10n.helpArticleMissingTitle), findsNothing);
          router.pop();
          await tester.pumpAndSettle();
        }

        // Tapping the hub's own doors — not pushing the paths by hand —
        // reaches S17.3 and S17.4.
        await tester.tap(find.text(l10n.helpContactTitle));
        await tester.pumpAndSettle();
        expect(find.text(l10n.helpCannotTitle), findsOneWidget);
        expect(router.state.uri.toString(), HelpPaths.contact);

        await tester.tap(find.text(l10n.helpDiagnosticsTitle));
        await tester.pumpAndSettle();
        expect(find.text(l10n.diagIntro), findsOneWidget);
        expect(router.state.uri.toString(), HelpPaths.diagnostics);

        // ⛔ Production wiring: no channel and no device producer, so the
        // send states its reason and the person is never stuck
        // (PLAN-11 / ADR 2026-09-19, 07 §1 rule 6 🔒).
        expect(find.text(l10n.diagSendReasonChannel), findsOneWidget);
        expect(find.text(l10n.diagActionCopy), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-411 an unknown answer id resolves to the missing state, and its '
      'action lands back on the hub (13 §4.3)',
      (tester) async {
        rkViewport(tester, rkTallViewport);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final router = await _pumpHelp(tester);

        unawaited(router.push(HelpPaths.articleOf('renamed_last_year')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.helpArticleMissingTitle), findsOneWidget);

        await tester.tap(find.text(l10n.helpArticleMissingAction));
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), HelpPaths.root);
        expect(find.text(l10n.helpSectionFaq), findsOneWidget);
        // The uri alone cannot tell `push`, `pushReplacement` and `pop`
        // apart — all three end on `/help`. The *stack* can.
        expect(find.byType(HelpScreen, skipOffstage: false), findsOneWidget);
        expect(router.canPop(), isFalse);
      },
    );

    testWidgets(
      'F1-07-413 taking the answer\'s way back to the hub pops the answer — '
      'one hub on the stack, and the system Back gesture is not left '
      'revealing the same page (07 §1 rule 6 🔒)',
      (tester) async {
        rkViewport(tester, rkTallViewport);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final router = await _pumpHelp(tester);

        unawaited(router.push(HelpPaths.articleOf('offline')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.helpArticleMore), findsOneWidget);

        await tester.tap(find.text(l10n.helpArticleMore));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), HelpPaths.root);
        // `pushReplacement` (go_router 17.5.0: "Replaces the top-most page of
        // the page stack") turned [/help, /help/answer/x] into [/help, /help]
        // — two hubs, both in the tree, and a Back that showed the hub again.
        expect(find.byType(HelpScreen, skipOffstage: false), findsOneWidget);
        expect(
          find.byType(FaqArticleScreen, skipOffstage: false),
          findsNothing,
        );
        expect(
          router.canPop(),
          isFalse,
          reason: 'nothing may be left standing above the hub',
        );
      },
    );

    testWidgets(
      'F1-07-414 the same way back clears Contact support too — an answer '
      'opened from S17.3 lands on the hub it names, not on the page below it',
      (tester) async {
        rkViewport(tester, rkTallViewport);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final router = await _pumpHelp(tester);

        // Hub → Contact support → the answer Contact support draws.
        await tester.tap(find.text(l10n.helpContactTitle));
        await tester.pumpAndSettle();
        final powers = faqText(l10n, 'support_powers')!;
        await tester.tap(find.text(powers.question));
        await tester.pumpAndSettle();
        expect(
          router.state.uri.toString(),
          HelpPaths.articleOf('support_powers'),
        );

        await tester.tap(find.text(l10n.helpArticleMore));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), HelpPaths.root);
        expect(find.byType(HelpScreen, skipOffstage: false), findsOneWidget);
        expect(
          find.byType(ContactSupportScreen, skipOffstage: false),
          findsNothing,
          reason:
              'the door says "Read the other questions", so the other '
              'questions are what must be on screen',
        );
        expect(router.canPop(), isFalse);
      },
    );
  });
}
