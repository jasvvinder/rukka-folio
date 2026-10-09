// F1 widget tests for S0.6c — *Add another business?*, the loop control of the
// multi-business branch (13 §3.2 row S0.6c, 07 §3.1.1).
//
// 07 §3.1.1's table, as amended by ADR 2026-10-04c §1, decides who sees this
// screen: the one **My business** card reads O6a → O6b → **O6c** looping back
// to O6a → O6 your own → checklist. Every *My business* user reaches S0.6c; a
// one-business person answers *No, that's all* and goes on exactly as the
// retired *My shop* card did. (The former `F1-07-83 only the My businesses
// card reaches S0.6c — My shop falls through` was superseded by that ADR and
// re-lands as F1-04c-2.)
//
// Sources: 13 §3.2 row S0.6c, 07 §3.1.1 (the branch table; every step
// skippable and resumable), ADR 2026-09-09 §1–3 (owners and share weights are
// collected on S0.6a1, per business), ADR 2026-09-09c §3 and ADR 2026-09-09d §1
// (what each created book seeds).
@Tags(['F1'])
library;

import 'dart:io';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';
import 'onboarding_router_harness.dart';

final _start = LocalDate(2026, 9, 7);

const _locales = [Locale('en'), Locale('pa'), Locale('hi')];

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget child, {
  Locale? locale,
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpRk(tester, child, locale: locale);
}

Future<void> _pumpHost(
  WidgetTester tester,
  LocalLedger ledger,
  OnboardingFlow flow,
) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpRk(
    tester,
    BusinessOpeningHost(flow: flow, startDate: _start),
    ledger: ledger,
  );
  await tester.pumpAndSettle();
}

BusinessDraft _draft(String name) => BusinessDraft(
  name: name,
  ownership: BusinessOwnershipChoice.justMe,
  fyStartMonth: 4,
);

void main() {
  group('S0.6c Add another business? (13 §3.2, 07 §3.1.1 O6c)', () {
    testWidgets(
      'F1-07-83 names the businesses set up so far and offers both ways on — '
      'the loop and the way out (07 §1: no dead ends)',
      (tester) async {
        await _pumpScreen(
          tester,
          const AddAnotherBusinessScreen(
            businesses: [
              AddedBusiness(name: 'Sharma Traders', fyStartMonth: 4),
              AddedBusiness(name: 'Sharma Agri', fyStartMonth: 4),
            ],
          ),
        );

        expect(find.text('Add another business?'), findsOneWidget);
        expect(find.text('Sharma Traders'), findsOneWidget);
        expect(find.text('Sharma Agri'), findsOneWidget);
        // The month word follows 07 §1 rule 5 (abbreviated in EN), not the
        // canvas's long "April".
        expect(find.text('FY from 1 Apr'), findsNWidgets(2));
        // Colour is never the only signal (07 §1 rule 3): the tick is an icon
        // and it speaks a word.
        expect(find.bySemanticsLabel('set up'), findsNWidgets(2));
        // The canvas ranks these: the loop is a row, the way out is the
        // filled primary (canvas 1, screen S0.6c).
        expect(find.text('Add another business'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'No, that’s all'),
          findsOneWidget,
        );
        expect(find.text('Skip for now'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-83 Add another business loops back; No, I am done falls through — '
      'neither action is hidden behind the other',
      (tester) async {
        var added = 0;
        var done = 0;
        var skipped = 0;
        await _pumpScreen(
          tester,
          AddAnotherBusinessScreen(
            businesses: const [AddedBusiness(name: 'Sharma Traders')],
            onAddAnother: () => added++,
            onDone: () => done++,
            onSkip: () => skipped++,
          ),
        );

        await tester.tap(find.text('Add another business'));
        await tester.pumpAndSettle();
        expect(added, 1);
        expect(done, 0);

        await tester.tap(find.text('No, that’s all'));
        await tester.pumpAndSettle();
        expect(done, 1);
        expect(added, 1);

        // Every branch step is skippable (07 §3.1.1).
        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();
        expect(skipped, 1);
      },
    );

    testWidgets(
      'F1-07-83 with nothing set up yet the screen is still not a dead end — '
      'both actions remain',
      (tester) async {
        await _pumpScreen(
          tester,
          const AddAnotherBusinessScreen(businesses: []),
        );

        expect(find.bySemanticsLabel('set up'), findsNothing);
        expect(find.text('Add another business'), findsOneWidget);
        expect(find.text('No, that’s all'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-83 strings resolve in EN/PA/HI with no overflow at 1.3x and '
      '200% on both F1 phones',
      (tester) async {
        for (final locale in _locales) {
          for (final vp in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                const AddAnotherBusinessScreen(
                  businesses: [
                    AddedBusiness(name: 'Sharma Traders', fyStartMonth: 4),
                    AddedBusiness(name: 'Sharma Agri', fyStartMonth: 4),
                  ],
                ),
                locale: locale,
                textScale: scale,
                viewport: vp,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: 'overflow in $locale @ $scale on $vp',
              );
              expectTextFits(
                tester,
                reason: '${locale.languageCode} @ $scale on $vp',
              );
            }
          }
        }
      },
    );

    test(
      'F1-07-83 the flow carries a list: the second business never overwrites '
      'the first, and each keeps its own owners and book',
      () {
        final flow = OnboardingFlow()..setYourName('Amrit Kaur');
        flow.setBusiness(_draft('Sharma Traders'));
        flow.businessBookId = 'book-1';
        expect(flow.businesses, hasLength(1));

        flow.addAnotherBusiness();
        // A fresh S0.6a: nothing pre-filled from the business just finished
        // (07 §3.1.1 — the loop returns to O6a, it does not edit O6a).
        expect(flow.business, isNull);
        expect(flow.owners, isEmpty);
        expect(flow.businessBookId, isNull);

        flow.setBusiness(_draft('Sharma Agri'));
        flow.businessBookId = 'book-2';

        expect(flow.businesses, hasLength(2));
        expect(flow.businessNames, ['Sharma Traders', 'Sharma Agri']);
        expect(flow.businesses.map((b) => b.bookId), ['book-1', 'book-2']);
        expect(flow.business?.name, 'Sharma Agri');
      },
    );

    test('F1-04c-2 the My business card always reaches S0.6c after S0.6b — '
        'one business or many (ADR 2026-10-04c §1)', () {
      final flow = OnboardingFlow()..setPurpose(OnboardingPurpose.businesses);
      // S0.8's Continue takes the business branch (S0.6a) …
      expect(afterSetPin(flow), OnboardingPaths.business);
      // … and S0.6b always hands on to S0.6c, before and after a first book.
      expect(afterBusinessOpening(flow), OnboardingPaths.businessAnother);
      flow.setBusiness(_draft('Sharma IT Services'));
      flow.businessBookId = 'book-1';
      expect(afterBusinessOpening(flow), OnboardingPaths.businessAnother);
      // No other card is routed to S0.6c.
      for (final p in OnboardingPurpose.values) {
        if (p == OnboardingPurpose.businesses) continue;
        expect(
          afterBusinessOpening(OnboardingFlow()..setPurpose(p)),
          isNot(OnboardingPaths.businessAnother),
          reason: p.name,
        );
      }
    });

    testWidgets(
      'F1-04c-2 through the router, a one-business person goes S0.6a → S0.6b '
      '→ S0.6c, sees their business there, answers No, that’s all and lands '
      'on Home\'s checklist exactly as the old My shop path did',
      (tester) async {
        resetOnboardingFlow();
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo();
        onboardingFlow.setPurpose(OnboardingPurpose.businesses);
        // S0.8's hand-off for this card is S0.6a (afterSetPin); start there.
        final router = await pumpOnboardingRouter(
          tester,
          ledger,
          initialLocation: afterSetPin(onboardingFlow),
        );
        expect(router.state.uri.path, OnboardingPaths.business);

        // S0.6a — the name, *Just me* by default → S0.6b's host.
        await tester.enterText(find.byType(TextField).first, 'Sharma Traders');
        await tapContinue(tester);
        expect(router.state.uri.path, OnboardingPaths.businessOpening);
        expect(onboardingFlow.businessBookId, isNotNull);

        // S0.6b — Save (at ₹0: ADR 2026-10-07 ruling 1 removed *Skip for
        // now*) is the host's onDone, the seam ADR 2026-10-04c §1 changed: it
        // must reach S0.6c, not Home.
        await tester.tap(find.text('Save and continue'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, OnboardingPaths.businessAnother);
        expect(onboardingFlow.businesses, hasLength(1));
        expect(find.text('Add another business?'), findsOneWidget);
        expect(find.text('Sharma Traders'), findsOneWidget);

        await tester.tap(find.text('No, that’s all'));
        await tester.pumpAndSettle();

        // The old *My shop* row: O6a → O6b → **O6 your own** → checklist
        // (07 §3.1.1 🔒; desk 172): S0.6, whose *Finish* is the hand-over to
        // Home's checklist (ADR 2026-10-07 ruling 1: ₹0 + Finish is valid).
        expect(router.state.uri.path, OnboardingPaths.openingBalances);
        expect(find.text('What do you have?'), findsOneWidget);
        await tester.tap(find.text('Finish'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, HomePaths.home);
      },
    );

    test('F1-07-83 S0.6c is in the 13 §3.2 inventory after S0.6b', () {
      final doc = File('../docs/13-ux-architecture.md').readAsLinesSync();
      final b = doc.indexWhere((l) => l.startsWith('| **S0.6b**'));
      final c = doc.indexWhere((l) => l.startsWith('| **S0.6c**'));
      expect(b, greaterThan(-1));
      expect(c, greaterThan(b));
      expect(doc[c], contains('O6b'));
    });

    testWidgets(
      'F1-07-83 each business becomes its own book through the existing seed '
      'path — two books, each with its own seeded chart',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = OnboardingFlow()..setYourName('Amrit Kaur');

        flow.setBusiness(_draft('Sharma Traders'));
        await _pumpHost(tester, ledger, flow);
        final first = flow.businessBookId;
        expect(first, isNotNull);

        // S0.6c's loop: back to S0.6a for the next business.
        flow.addAnotherBusiness();
        flow.setBusiness(_draft('Sharma Agri'));
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpHost(tester, ledger, flow);
        final second = flow.businessBookId;

        expect(second, isNotNull);
        expect(second, isNot(first));
        expect(flow.businessNames, ['Sharma Traders', 'Sharma Agri']);
        expect(await ledger.mirror.bookIds(), hasLength(3));

        final books = await ledger.db.select(ledger.db.booksP).get();
        expect(books.firstWhere((b) => b.id == first).name, 'Sharma Traders');
        expect(books.firstWhere((b) => b.id == second).name, 'Sharma Agri');
        expect((await ledger.chartOf(first!)).accounts, isNotEmpty);
        expect((await ledger.chartOf(second!)).accounts, isNotEmpty);
      },
    );
  });
}
