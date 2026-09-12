// F1 widget tests for S0.6c — *Add another business?*, the loop control of the
// multi-business branch (13 §3.2 row S0.6c, 07 §3.1.1).
//
// 07 §3.1.1's table is what decides who ever sees this screen: the **My
// businesses** row reads O6a → O6b → **O6c** looping back to O6a → O6 your own
// → checklist, and the **My shop** row does not — a shop goes O6a → O6b → O6 →
// checklist. So the purpose card, not the fact that a business was created, is
// what opens the loop.
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
import 'package:rukka_folio/features/onboarding/onboarding_flow.dart';
import 'package:rukka_folio/features/onboarding/onboarding_paths.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a_business_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6c_add_another_business_screen.dart';
import 'package:rukka_folio/features/onboarding/widgets/business_opening_host.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

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
      'F1-07-83 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final locale in _locales) {
          await pumpRk(
            tester,
            const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: AddAnotherBusinessScreen(
                businesses: [
                  AddedBusiness(name: 'Sharma Traders', fyStartMonth: 4),
                  AddedBusiness(name: 'Sharma Agri', fyStartMonth: 4),
                ],
              ),
            ),
            locale: locale,
          );
          expect(tester.takeException(), isNull, reason: 'overflow in $locale');
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

    test('F1-07-83 only the My businesses card reaches S0.6c — My shop falls '
        'through to the checklist (07 §3.1.1 branch table)', () {
      final businesses = OnboardingFlow()
        ..setPurpose(OnboardingPurpose.businesses);
      expect(afterBusinessOpening(businesses), OnboardingPaths.businessAnother);

      final shop = OnboardingFlow()..setPurpose(OnboardingPurpose.shop);
      expect(afterBusinessOpening(shop), HomePaths.home);
    });

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
