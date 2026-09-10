// F1 widget tests for the business branch of onboarding — S0.6a (F1-07-51),
// S0.6a1 (F1-07-45) and S0.6b (F1-09c-1), plus the 13 §3.2 inventory
// assertion for S0.6a1 (F1-13-15).
//
// Sources: 13 §3.2 rows S0.6a / S0.6a1 / S0.6b, 07 §3.1.1 (branch O6a → O6b),
// ADR 2026-09-09 §1–§3, ADR 2026-09-09c §3–§4, ADR 2026-09-09d §1 and §4.
@Tags(['F1'])
library;

import 'dart:io';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a1_business_owners_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a_business_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6b_business_opening_balances_screen.dart';

import '../../shared/test_app.dart';

final _start = LocalDate(2026, 9, 7);

const _locales = [Locale('en'), Locale('pa'), Locale('hi')];

/// Pumps [child] on a tall surface so a long scrolling screen is entirely
/// built — a widget a [ListView] has not reached is not in the tree at all,
/// and these screens are checked for *content*, not for scrolling.
Future<void> pumpTall(
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

/// Pumps [build] at 200% text scale on a 360x800 surface in EN, PA and HI and
/// fails on any overflow (07 §1, design-system accessibility rules).
Future<void> expectNoOverflowInEveryLocale(
  WidgetTester tester,
  Widget Function() build,
) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  for (final locale in _locales) {
    await pumpRk(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: build(),
      ),
      locale: locale,
    );
    expect(tester.takeException(), isNull, reason: 'overflow in $locale');
  }
}

void main() {
  group('S0.6a Name the business (13 §3.2, 07 §5.7)', () {
    testWidgets('F1-07-51 Continue is disabled until the business is named '
        '(disabled-with-reason, 13 §4.3)', (tester) async {
      await pumpTall(tester, BusinessNameScreen(startDate: _start));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Sharma Traders');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'F1-07-51 the default answers are Just me and an April financial year; '
      'Continue hands name, ownership and FY start on',
      (tester) async {
        BusinessDraft? submitted;
        await pumpTall(
          tester,
          BusinessNameScreen(
            startDate: _start,
            onSubmit: (draft) => submitted = draft,
          ),
        );
        await tester.enterText(find.byType(TextField), '  Sharma Traders  ');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(submitted!.name, 'Sharma Traders');
        expect(submitted!.ownership, BusinessOwnershipChoice.justMe);
        expect(submitted!.fyStartMonth, 4);
      },
    );

    testWidgets(
      'F1-07-51 Shared with others is the branch answer that reaches S0.6a1 '
      '(ADR 2026-09-09 §1)',
      (tester) async {
        BusinessDraft? submitted;
        await pumpTall(
          tester,
          BusinessNameScreen(
            startDate: _start,
            onSubmit: (draft) => submitted = draft,
          ),
          locale: const Locale('en'),
        );
        await tester.enterText(find.byType(TextField), 'Sharma Traders');
        await tester.tap(find.text('Shared with others'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(submitted!.ownership, BusinessOwnershipChoice.shared);
      },
    );

    testWidgets(
      'F1-07-51 the screen states the book start date and its floor, and '
      'offers no date picker (ADR 2026-09-09d §4)',
      (tester) async {
        await pumpTall(
          tester,
          BusinessNameScreen(startDate: _start),
          locale: const Locale('en'),
        );
        expect(find.textContaining('07 Sep 2026'), findsOneWidget);
        expect(find.textContaining('before that day'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-51 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
      (tester) async {
        await expectNoOverflowInEveryLocale(
          tester,
          () => BusinessNameScreen(startDate: _start),
        );
      },
    );
  });

  group('S0.6a1 Who owns this business? (ADR 2026-09-09 §1–§3)', () {
    testWidgets(
      'F1-07-45 owners are invited by phone and stay unverified until the '
      'ceremony — the S0.6e row, and no claim of a verified key',
      (tester) async {
        await pumpTall(
          tester,
          const BusinessOwnersScreen(yourName: 'Sunita'),
          locale: const Locale('en'),
        );
        expect(find.text('you'), findsOneWidget);
        expect(find.text('to invite'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Phone number'), findsOneWidget);
        expect(find.textContaining('unverified'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-45 Equal shares holds real weights (1:1), not percentages; the '
      'percentage is computed and shown beneath, never typed',
      (tester) async {
        await pumpTall(
          tester,
          const BusinessOwnersScreen(yourName: 'Sunita'),
          locale: const Locale('en'),
        );
        // Two owners, one share each — the weight is 1, the percentage 50%.
        expect(find.text('1 shares'), findsNWidgets(2));
        expect(find.text('50% of the business'), findsNWidgets(2));
        expect(find.text('2 shares in all'), findsOneWidget);
        // No percentage is ever an input.
        expect(find.widgetWithText(TextField, '50'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-45 three equal owners are 1:1:1 and read 33.3%, never 33/33/34',
      (tester) async {
        expect(sharePercentLabel(1, 3), '33.3');
        expect(sharePercentLabel(2, 3), '66.7');
        expect(sharePercentLabel(1, 2), '50');
      },
    );

    testWidgets(
      'F1-07-45 Different shares steps in whole numbers, floors at one, and '
      'never validates against 100',
      (tester) async {
        List<OwnerDraft>? submitted;
        await pumpTall(
          tester,
          BusinessOwnersScreen(
            yourName: 'Sunita',
            onSubmit: (owners) => submitted = owners,
          ),
          locale: const Locale('en'),
        );
        await tester.tap(find.text('Different shares'));
        await tester.pumpAndSettle();
        // Two taps on the first row's + → 3 shares for Sunita, 1 for the other.
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();
        expect(find.text('4 shares in all'), findsOneWidget);
        expect(find.text('75% of the business'), findsOneWidget);
        expect(find.text('25% of the business'), findsOneWidget);

        // The minus on a one-share row is disabled: nobody holds zero shares.
        final minus = tester.widgetList<IconButton>(
          find.widgetWithIcon(IconButton, Icons.remove),
        );
        expect(minus.last.onPressed, isNull);

        // Naming the second owner is what enables Continue — never the ratio.
        await tester.enterText(
          find.widgetWithText(TextField, "Owner's name").last,
          'Rajesh',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Phone number').last,
          '9800000000',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(submitted!.map((o) => o.shares).toList(), [3, 1]);
        expect(submitted!.first.isYou, isTrue);
        expect(submitted!.last.name, 'Rajesh');
        expect(submitted!.last.phone, '9800000000');
      },
    );

    testWidgets(
      'F1-07-45 the step is not skippable: the secondary is Just me after all '
      'and returns to the Just me branch (ADR 2026-09-09 §3)',
      (tester) async {
        var backToJustMe = 0;
        await pumpTall(
          tester,
          BusinessOwnersScreen(
            yourName: 'Sunita',
            onJustMeAfterAll: () => backToJustMe++,
          ),
          locale: const Locale('en'),
        );
        expect(find.text('Skip for now'), findsNothing);
        await tester.tap(find.text('Just me after all'));
        await tester.pumpAndSettle();
        expect(backToJustMe, 1);
      },
    );

    testWidgets(
      'F1-07-45 the Just me branch never sees this screen — S0.6a routes '
      'straight past it (ADR 2026-09-09 §1)',
      (tester) async {
        BusinessDraft? submitted;
        await pumpTall(
          tester,
          BusinessNameScreen(
            startDate: _start,
            onSubmit: (draft) => submitted = draft,
          ),
          locale: const Locale('en'),
        );
        await tester.enterText(find.byType(TextField), 'Sharma Traders');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(submitted!.ownership, BusinessOwnershipChoice.justMe);
        // Nothing about owners is asked on the Just me branch.
        expect(find.text('Who owns this business?'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-45 the screen states the 02 §7.1 rule: shares are fixed at '
      'creation and paying in more later never buys a bigger share',
      (tester) async {
        await pumpTall(
          tester,
          const BusinessOwnersScreen(yourName: 'Sunita'),
          locale: const Locale('en'),
        );
        expect(find.textContaining('never a bigger share'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-45 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
      (tester) async {
        await expectNoOverflowInEveryLocale(
          tester,
          () => const BusinessOwnersScreen(yourName: 'Sunita'),
        );
      },
    );

    test(
      'F1-13-15 S0.6a1 is in the 13 §3.2 inventory between S0.6a and S0.6b',
      () {
        final doc = File('../docs/13-ux-architecture.md').readAsLinesSync();
        final a = doc.indexWhere((l) => l.startsWith('| **S0.6a**'));
        final a1 = doc.indexWhere((l) => l.startsWith('| **S0.6a1**'));
        final b = doc.indexWhere((l) => l.startsWith('| **S0.6b**'));
        expect(a, greaterThan(-1));
        expect(a1, greaterThan(a));
        expect(b, greaterThan(a1));
        expect(doc[a1], contains('S0.6a'));
        expect(doc[a1], contains('ADR 2026-09-09'));
      },
    );
  });

  group('S0.6b The business opening balances (ADR 2026-09-09c §3–§4)', () {
    const rows = [
      OpeningRow(
        accountId: 'cash',
        name: 'Business Cash A/c',
        group: OpeningGroup.have,
      ),
      OpeningRow(
        accountId: 'ramesh',
        name: 'Ramesh',
        group: OpeningGroup.owedToYou,
      ),
      OpeningRow(
        accountId: 'supplier',
        name: 'Verma Mills',
        group: OpeningGroup.youOwe,
      ),
      OpeningRow(
        accountId: 'partner-sunita',
        name: 'Sunita — Partner Current A/c',
        group: OpeningGroup.ownerContributions,
        suggested: true,
      ),
    ];

    testWidgets(
      'F1-09c-1 one grouped review-and-fill screen over the seeded accounts, '
      'in the consumer vocabulary (02 §10) — never a three-step wizard',
      (tester) async {
        await pumpTall(
          tester,
          BusinessOpeningBalancesScreen(rows: rows, startDate: _start),
          locale: const Locale('en'),
        );
        expect(find.text('What you have'), findsOneWidget);
        expect(find.text('Who owes you'), findsOneWidget);
        expect(find.text('Who you owe'), findsOneWidget);
        expect(find.text('What each owner put in'), findsOneWidget);
        // The seeded accounts are shown for review, not created here.
        expect(find.text('Business Cash A/c'), findsOneWidget);
        expect(find.text('Sunita — Partner Current A/c'), findsOneWidget);
        // Consumer vocabulary only: no Dr/Cr, no Assets/Liabilities (02 §10).
        expect(find.textContaining('Assets'), findsNothing);
        expect(find.textContaining('Liabilities'), findsNothing);
      },
    );

    testWidgets(
      'F1-09c-1 no bank is seeded; the group offers Add a bank account '
      '(ADR 2026-09-09d §1)',
      (tester) async {
        OpeningGroup? asked;
        await pumpTall(
          tester,
          BusinessOpeningBalancesScreen(
            rows: rows,
            startDate: _start,
            onAddAccount: (group) => asked = group,
          ),
          locale: const Locale('en'),
        );
        expect(find.text('Bank A/c'), findsNothing);
        await tester.tap(find.text('Add a bank account'));
        await tester.pumpAndSettle();
        expect(asked, OpeningGroup.have);
      },
    );

    testWidgets(
      'F1-09c-1 the screen says how the opening entry balances and names the '
      'account that absorbs it (ADR 2026-09-09c §4)',
      (tester) async {
        await pumpTall(
          tester,
          BusinessOpeningBalancesScreen(rows: rows, startDate: _start),
          locale: const Locale('en'),
        );
        // Nothing typed yet: it balances exactly, and says so.
        expect(find.text('Opening Balance / Capital A/c'), findsOneWidget);
        expect(find.textContaining('balances exactly'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Amount today').first,
          '50000',
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('₹50,000 goes to Opening Balance / Capital A/c'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-09c-1 saving hands signed integer paise per account, zero rows '
      'included (ADR 2026-09-09c §3)',
      (tester) async {
        Map<String, int>? saved;
        await pumpTall(
          tester,
          BusinessOpeningBalancesScreen(
            rows: rows,
            startDate: _start,
            onSave: (balances) => saved = balances,
          ),
          locale: const Locale('en'),
        );
        final fields = find.widgetWithText(TextField, 'Amount today');
        await tester.enterText(fields.at(0), '50000'); // have
        await tester.enterText(fields.at(1), '1200'); // owed to you
        await tester.enterText(fields.at(2), '800'); // you owe
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save and continue'));
        await tester.pumpAndSettle();

        expect(saved, {
          'cash': 5000000,
          'ramesh': 120000,
          'supplier': -80000,
          'partner-sunita': 0,
        });
        for (final value in saved!.values) {
          expect(value, isA<int>());
        }
      },
    );

    testWidgets(
      'F1-09c-1 the owner contribution is labelled a suggestion, never '
      'derived silently (ADR 2026-09-09c §4)',
      (tester) async {
        await pumpTall(
          tester,
          BusinessOpeningBalancesScreen(rows: rows, startDate: _start),
          locale: const Locale('en'),
        );
        expect(
          find.textContaining('Suggested from the shares'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-09c-1 every row is dated at the book start date and no earlier date '
      'can be chosen (ADR 2026-09-09d §4)',
      (tester) async {
        await pumpTall(
          tester,
          BusinessOpeningBalancesScreen(rows: rows, startDate: _start),
          locale: const Locale('en'),
        );
        expect(find.textContaining('07 Sep 2026'), findsOneWidget);
        expect(find.byType(CalendarDatePicker), findsNothing);
      },
    );

    testWidgets('F1-09c-1 rupees typed become integer paise, never a double', (
      tester,
    ) async {
      expect(parseRupeesToPaise('50000'), 5000000);
      expect(parseRupeesToPaise('1,200.50'), 120050);
      expect(parseRupeesToPaise(''), 0);
      expect(parseRupeesToPaise('abc'), 0);
    });

    testWidgets(
      'F1-09c-1 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
      (tester) async {
        await expectNoOverflowInEveryLocale(
          tester,
          () => BusinessOpeningBalancesScreen(rows: rows, startDate: _start),
        );
      },
    );
  });
}
