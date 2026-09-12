// F1 widget tests for the family branch of onboarding — S0.6d (F1-07-74),
// S0.6e (F1-07-75) and S0.6f (F1-07-76).
//
// Sources: 13 §3.2 rows S0.6d / S0.6e / S0.6f, 07 §3.1.1 (branch O6d → O6e →
// O6f → O6), ADR 2026-09-09 §1 (S0.6e is the archetype S0.6a1 reuses), ADR
// 2026-09-09c §1–§3 (the seeded chart, one grouped screen), ADR 2026-09-09d
// §1 and §4 (no seeded bank, the book's start date).
@Tags(['F1'])
library;

import 'dart:io';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_flow.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6b_business_opening_balances_screen.dart'
    show OpeningGroup, OpeningRow;
import 'package:rukka_folio/features/onboarding/screens/s0_6d_family_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6e_family_members_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6f_family_accounts_screen.dart';
import 'package:rukka_folio/features/onboarding/widgets/family_opening_host.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

final _start = LocalDate(2026, 9, 7);

const _locales = [Locale('en'), Locale('pa'), Locale('hi')];

/// Pumps [child] on a tall surface so a long scrolling screen is entirely
/// built (same rationale as the business-branch tests: a widget a
/// [ListView] has not reached is not in the tree at all).
Future<void> pumpTall(
  WidgetTester tester,
  Widget child, {
  Locale? locale,
  LocalLedger? ledger,
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpRk(tester, child, locale: locale, ledger: ledger);
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

Future<Map<String, int>> _balances(LocalLedger l) async => {
  for (final r in await l.db.select(l.db.balances).get())
    r.accountId: r.balancePaise,
};

void main() {
  group('S0.6d Name the family (13 §3.2, 07 §3.1.1)', () {
    testWidgets('F1-07-74 Continue is disabled until the family is named '
        '(disabled-with-reason, 13 §4.3)', (tester) async {
      await pumpTall(tester, FamilyNameScreen(startDate: _start));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Sharma Family');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('F1-07-74 Continue hands the trimmed name on; no ownership '
        'or FY question is asked (07 §3.1.1 differs from S0.6a)', (
      tester,
    ) async {
      FamilyDraft? submitted;
      await pumpTall(
        tester,
        FamilyNameScreen(
          startDate: _start,
          onSubmit: (draft) => submitted = draft,
        ),
        locale: const Locale('en'),
      );
      await tester.enterText(find.byType(TextField), '  Sharma Family  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(submitted!.name, 'Sharma Family');
      expect(find.text('Who owns it?'), findsNothing);
      expect(find.text('Financial year starts'), findsNothing);
    });

    testWidgets(
      'F1-07-74 the screen states the book start date and its floor, and '
      'offers no date picker (ADR 2026-09-09d §4)',
      (tester) async {
        await pumpTall(
          tester,
          FamilyNameScreen(startDate: _start),
          locale: const Locale('en'),
        );
        expect(find.textContaining('07 Sep 2026'), findsOneWidget);
        expect(find.textContaining('before that day'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-74 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
      (tester) async {
        await expectNoOverflowInEveryLocale(
          tester,
          () => FamilyNameScreen(startDate: _start),
        );
      },
    );
  });

  group(
    'S0.6e Who else is in the family (13 §3.2, ADR 2026-09-09 §1 archetype)',
    () {
      testWidgets(
        'F1-07-75 the creating user is the first row, tagged you; invited '
        'rows are tagged to invite and stay unverified until the ceremony',
        (tester) async {
          await pumpTall(
            tester,
            const FamilyMembersScreen(yourName: 'Amrit Kaur'),
            locale: const Locale('en'),
          );
          expect(find.text('you'), findsOneWidget);
          expect(find.textContaining('unverified'), findsOneWidget);
        },
      );

      testWidgets(
        'F1-07-75 Skip for now is always visible, whether or not any member '
        'has been added or filled in (🔒 07 §3.1.1, 13 §3.2)',
        (tester) async {
          var skipped = 0;
          await pumpTall(
            tester,
            FamilyMembersScreen(
              yourName: 'Amrit Kaur',
              onSkip: () => skipped++,
            ),
            locale: const Locale('en'),
          );
          expect(find.text('Skip for now'), findsOneWidget);

          // Still visible after adding a half-filled row that blocks Continue.
          await tester.tap(find.text('Add a family member'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          expect(find.text('Skip for now'), findsOneWidget);

          await tester.tap(find.text('Skip for now'));
          await tester.pumpAndSettle();
          expect(skipped, 1);
        },
      );

      testWidgets(
        'F1-07-75 an invited row needs a name and a phone number before '
        'Continue hands the list on; there are no share weights here',
        (tester) async {
          List<FamilyMemberDraft>? submitted;
          await pumpTall(
            tester,
            FamilyMembersScreen(
              yourName: 'Amrit Kaur',
              onSubmit: (members) => submitted = members,
            ),
            locale: const Locale('en'),
          );
          await tester.tap(find.text('Add a family member'));
          await tester.pumpAndSettle();
          expect(find.text('shares'), findsNothing);

          await tester.enterText(
            find.widgetWithText(TextField, 'Name').last,
            'Sukhdev Singh',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Phone number').last,
            '9800000000',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();

          expect(submitted!.first.isYou, isTrue);
          expect(submitted!.first.name, 'Amrit Kaur');
          expect(submitted!.last.name, 'Sukhdev Singh');
          expect(submitted!.last.phone, '9800000000');
        },
      );

      testWidgets(
        'F1-07-75 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
        (tester) async {
          await expectNoOverflowInEveryLocale(
            tester,
            () => const FamilyMembersScreen(yourName: 'Amrit Kaur'),
          );
        },
      );
    },
  );

  group('S0.6f The family shared accounts (ADR 2026-09-09c, 2026-09-09d)', () {
    const rows = [
      OpeningRow(
        accountId: 'cash',
        name: 'Joint Cash A/c',
        group: OpeningGroup.have,
      ),
    ];

    testWidgets(
      'F1-07-76 the seeded pool cash account is shown for review; no bank '
      'is seeded, and the group offers Add a bank account (ADR 09d §1)',
      (tester) async {
        OpeningGroup? asked;
        await pumpTall(
          tester,
          FamilySharedAccountsScreen(
            rows: rows,
            startDate: _start,
            onAddAccount: (g) => asked = g,
          ),
          locale: const Locale('en'),
        );
        expect(find.text('Joint Cash A/c'), findsOneWidget);
        expect(find.text('Bank A/c'), findsNothing);
        await tester.tap(find.text('Add a bank account'));
        await tester.pumpAndSettle();
        expect(asked, OpeningGroup.have);
      },
    );

    testWidgets(
      'F1-07-76 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
      (tester) async {
        await expectNoOverflowInEveryLocale(
          tester,
          () => FamilySharedAccountsScreen(rows: rows, startDate: _start),
        );
      },
    );
  });

  group('S0.6f committing step — FamilyOpeningHost', () {
    OnboardingFlow flow() => OnboardingFlow()
      ..setYourName('Amrit Kaur')
      ..setFamily(const FamilyDraft(name: 'Sharma Family'));

    Future<void> pumpHost(
      WidgetTester tester,
      LocalLedger ledger,
      OnboardingFlow flow, {
      VoidCallback? onDone,
    }) async {
      tester.view.physicalSize = const Size(420, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpRk(
        tester,
        FamilyOpeningHost(flow: flow, startDate: _start, onDone: onDone),
        ledger: ledger,
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'F1-07-76 the pool book is created from the S0.6d answer, seeding '
      'Joint Cash A/c and no bank, no categories (ADR 2026-09-09c §1)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final f = flow();
        await pumpHost(tester, ledger, f);

        expect(f.familyBookId, isNotNull);
        final books = await ledger.db.select(ledger.db.booksP).get();
        final book = books.firstWhere((b) => b.id == f.familyBookId);
        expect(book.name, 'Sharma Family');
        expect(book.startDate, _start.toString());

        expect(find.byType(FamilySharedAccountsScreen), findsOneWidget);
        expect(find.text('Joint Cash A/c'), findsOneWidget);

        final chart = await ledger.chartOf(f.familyBookId!);
        expect(
          chart.byClass(AccountClass.categoryIncome),
          isEmpty,
          reason:
              'the household category tree is drafted and unratified '
              '(docs/reference/seed-category-trees.md) — the family book '
              'seeds no categories unless the caller passes them',
        );
        expect(chart.byClass(AccountClass.categoryExpense), isEmpty);
        // No bank is seeded in any book type (ADR 2026-09-09d §1): the only
        // money account is the seeded Joint Cash A/c.
        expect(chart.byClass(AccountClass.money), hasLength(1));
      },
    );

    testWidgets(
      'F1-07-76 Save posts the typed rupees as integer paise against the '
      'pool book, dated at its start date',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final f = flow();
        var done = 0;
        await pumpHost(tester, ledger, f, onDone: () => done++);

        await tester.enterText(find.byType(TextField).first, '2500');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(done, 1);
        final bookId = f.familyBookId!;
        final chart = await ledger.chartOf(bookId);
        final cash = chart
            .byClass(AccountClass.money)
            .firstWhere((a) => a.name == 'Joint Cash A/c');
        expect((await _balances(ledger))[cash.id], 250000);
      },
    );

    testWidgets(
      'F1-07-76 Skip for now still leaves the pool book and its seeded '
      'chart behind — nothing is posted, never a dead end',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final f = flow();
        var done = 0;
        await pumpHost(tester, ledger, f, onDone: () => done++);

        await tester.tap(find.byType(TextButton).last);
        await tester.pumpAndSettle();

        expect(done, 1);
        final chart = await ledger.chartOf(f.familyBookId!);
        final balances = await _balances(ledger);
        for (final a in chart.accounts) {
          expect(balances[a.id] ?? 0, 0);
        }
      },
    );

    testWidgets(
      'F1-07-76 resuming the step reuses the pool book it already made — '
      'never a second book for the same answers (07 §3.1.1)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final f = flow();
        await pumpHost(tester, ledger, f);
        final first = f.familyBookId;

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpHost(tester, ledger, f);

        expect(f.familyBookId, first);
        expect(await ledger.mirror.bookIds(), hasLength(2));
      },
    );

    testWidgets(
      'F1-07-76 an unanswered S0.6d is an error with a way on, never a '
      'blank screen (07 §1 rule 12)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        await pumpHost(tester, ledger, OnboardingFlow());

        expect(find.byType(FamilySharedAccountsScreen), findsNothing);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
      },
    );
  });

  test('F1-07-74 S0.6d/e/f are in the 13 §3.2 inventory, each carrying its own '
      'test id', () {
    final doc = File('../docs/13-ux-architecture.md').readAsLinesSync();
    final d = doc.indexWhere((l) => l.startsWith('| **S0.6d**'));
    final e = doc.indexWhere((l) => l.startsWith('| **S0.6e**'));
    final f = doc.indexWhere((l) => l.startsWith('| **S0.6f**'));
    expect(d, greaterThan(-1));
    expect(e, greaterThan(d));
    expect(f, greaterThan(e));
    expect(doc[d], contains('F1-07-74'));
    expect(doc[e], contains('F1-07-75'));
    expect(doc[f], contains('F1-07-76'));
  });
}
