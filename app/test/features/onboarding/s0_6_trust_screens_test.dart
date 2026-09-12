// F1 widget tests for the trust branch of onboarding — S0.6g (F1-07-80),
// S0.6h (F1-07-81) and S0.6i (F1-07-82). Before this lane, a user who picked
// the trust card on S0.3 reached a dead end (afterSetPin fell through to
// Home) — this is the last unbuilt purpose-card branch.
//
// Sources: 13 §3.2 rows S0.6g / S0.6h / S0.6i, 07 §3.1.1 (branch O6g → O6h →
// O6i → O6), ADR 2026-09-09c §2–§3 (a trust is not a partnership, no
// owner-contributions group — same reading U1d took for the family pool),
// ADR 2026-09-09d §1/§2 (no seeded bank, the trust's seed lost its bank), 02
// §8.2 (the gollak as cash_collection, denomination counting), 06 §1.0
// (Chairman/President/Trustee/Sevadar).
@Tags(['F1'])
library;

import 'dart:io';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_flow.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6b_business_opening_balances_screen.dart'
    show OpeningGroup, OpeningRow;
import 'package:rukka_folio/features/onboarding/screens/s0_6g_trust_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6h_trust_members_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6i_trust_accounts_screen.dart';
import 'package:rukka_folio/features/onboarding/widgets/trust_opening_host.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

final _start = LocalDate(2026, 9, 7);

const _locales = [Locale('en'), Locale('pa'), Locale('hi')];

/// Pumps [child] on a tall surface so a long scrolling screen is entirely
/// built (same rationale as the family/business branch tests: a widget a
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
  group('S0.6g Name the trust and its type (13 §3.2, 07 §3.1.1)', () {
    testWidgets('F1-07-80 Continue is disabled until the trust is named '
        '(disabled-with-reason, 13 §4.3)', (tester) async {
      await pumpTall(tester, TrustNameScreen(startDate: _start));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Guru Nanak Gurudwara');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'F1-07-80 Continue hands the trimmed name and chosen type on; no '
      'ownership or FY question is asked (a trust is not a partnership, '
      'ADR 2026-09-09c §2)',
      (tester) async {
        TrustDraft? submitted;
        await pumpTall(
          tester,
          TrustNameScreen(
            startDate: _start,
            onSubmit: (draft) => submitted = draft,
          ),
          locale: const Locale('en'),
        );
        await tester.enterText(
          find.byType(TextField),
          '  Guru Nanak Gurudwara  ',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Temple'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(submitted!.name, 'Guru Nanak Gurudwara');
        expect(submitted!.type, TrustType.temple);
        expect(find.text('Who owns it?'), findsNothing);
        expect(find.text('Financial year starts'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-80 all four illustrative types are offered (07 §3.1 step 3 🔒): '
      'gurudwara, temple, society, registered trust',
      (tester) async {
        await pumpTall(
          tester,
          TrustNameScreen(startDate: _start),
          locale: const Locale('en'),
        );
        expect(find.text('Gurudwara'), findsOneWidget);
        expect(find.text('Temple'), findsOneWidget);
        expect(find.text('Society'), findsOneWidget);
        expect(find.text('Registered trust'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-80 the screen states the book start date and its floor, and '
      'offers no date picker (ADR 2026-09-09d §4)',
      (tester) async {
        await pumpTall(
          tester,
          TrustNameScreen(startDate: _start),
          locale: const Locale('en'),
        );
        expect(find.textContaining('07 Sep 2026'), findsOneWidget);
        expect(find.textContaining('before that day'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-80 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
      (tester) async {
        await expectNoOverflowInEveryLocale(
          tester,
          () => TrustNameScreen(startDate: _start),
        );
      },
    );
  });

  group('S0.6h Who runs the trust (13 §3.2, 06 §1.0 role labels)', () {
    testWidgets('F1-07-81 the creating user is the first row, tagged you and '
        'Chairman by default; invited rows are tagged to invite and stay '
        'unverified until the ceremony', (tester) async {
      await pumpTall(
        tester,
        const TrustMembersScreen(yourName: 'Amrit Kaur'),
        locale: const Locale('en'),
      );
      expect(find.text('you'), findsOneWidget);
      expect(find.textContaining('unverified'), findsOneWidget);
      expect(find.text('Chairman'), findsOneWidget);
    });

    testWidgets(
      'F1-07-81 Skip for now is always visible, whether or not any member '
      'has been added or filled in (🔒 07 §3.1.1, 13 §3.2)',
      (tester) async {
        var skipped = 0;
        await pumpTall(
          tester,
          TrustMembersScreen(yourName: 'Amrit Kaur', onSkip: () => skipped++),
          locale: const Locale('en'),
        );
        expect(find.text('Skip for now'), findsOneWidget);

        // Still visible after adding a half-filled row that blocks Continue.
        await tester.tap(find.text('Add a committee member'));
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
      'F1-07-81 an invited row needs a name and a phone number before '
      'Continue hands the roled list on; each row carries a Chairman / '
      'President / Trustee / Sevadar role and there are no share weights',
      (tester) async {
        List<TrustMemberDraft>? submitted;
        await pumpTall(
          tester,
          TrustMembersScreen(
            yourName: 'Amrit Kaur',
            onSubmit: (members) => submitted = members,
          ),
          locale: const Locale('en'),
        );
        await tester.tap(find.text('Add a committee member'));
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
        // The new row defaults to Trustee; change it to Sevadar.
        await tester.tap(find.text('Trustee').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sevadar').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(submitted!.first.isYou, isTrue);
        expect(submitted!.first.name, 'Amrit Kaur');
        expect(submitted!.first.role, TrustRole.chairman);
        expect(submitted!.last.name, 'Sukhdev Singh');
        expect(submitted!.last.phone, '9800000000');
        expect(submitted!.last.role, TrustRole.sevadar);
      },
    );

    testWidgets(
      'F1-07-81 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
      (tester) async {
        await expectNoOverflowInEveryLocale(
          tester,
          () => const TrustMembersScreen(yourName: 'Amrit Kaur'),
        );
      },
    );
  });

  group(
    'S0.6i The trust accounts (ADR 2026-09-09c/09d, 02 §8.2 the gollak)',
    () {
      const rows = [
        OpeningRow(accountId: 'cash', name: 'Cash', group: OpeningGroup.have),
        OpeningRow(
          accountId: 'gollak',
          name: 'Gollak Cash',
          group: OpeningGroup.have,
          isCollection: true,
        ),
      ];

      testWidgets(
        'F1-07-82 both the seeded Cash A/c and the gollak are shown for '
        'review; the gollak carries its cash_collection note and the '
        'group offers Add a bank account, never seeded (ADR 09d §1/§2)',
        (tester) async {
          OpeningGroup? asked;
          await pumpTall(
            tester,
            TrustAccountsScreen(
              rows: rows,
              startDate: _start,
              onAddAccount: (g) => asked = g,
            ),
            locale: const Locale('en'),
          );
          expect(find.text('Cash'), findsOneWidget);
          expect(find.text('Gollak Cash'), findsOneWidget);
          expect(find.textContaining('gollak'), findsOneWidget);
          expect(find.text('Bank A/c'), findsNothing);
          await tester.tap(find.text('Add a bank account'));
          await tester.pumpAndSettle();
          expect(asked, OpeningGroup.have);
        },
      );

      testWidgets(
        'F1-07-82 strings resolve in EN/PA/HI with no overflow at 200% on 360x800',
        (tester) async {
          await expectNoOverflowInEveryLocale(
            tester,
            () => TrustAccountsScreen(rows: rows, startDate: _start),
          );
        },
      );
    },
  );

  group('S0.6i committing step — TrustOpeningHost', () {
    OnboardingFlow flow() => OnboardingFlow()
      ..setYourName('Amrit Kaur')
      ..setTrust(
        const TrustDraft(
          name: 'Guru Nanak Gurudwara',
          type: TrustType.gurudwara,
        ),
      );

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
        TrustOpeningHost(flow: flow, startDate: _start, onDone: onDone),
        ledger: ledger,
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'F1-07-82 the trust book is created from the S0.6g answer, seeding '
      'Cash and the gollak as cash_collection, plus the four 🔒 category '
      'accounts, and no bank (07 §3.1 step 3 🔒, ADR 2026-09-09d §2)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final f = flow();
        await pumpHost(tester, ledger, f);

        expect(f.trustBookId, isNotNull);
        final books = await ledger.db.select(ledger.db.booksP).get();
        final book = books.firstWhere((b) => b.id == f.trustBookId);
        expect(book.name, 'Guru Nanak Gurudwara');
        expect(book.startDate, _start.toString());

        expect(find.byType(TrustAccountsScreen), findsOneWidget);
        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('Gollak Cash'), findsOneWidget);

        final chart = await ledger.chartOf(f.trustBookId!);
        // Cash + Gollak, no bank (ADR 2026-09-09d §1/§2).
        expect(chart.byClass(AccountClass.money), hasLength(2));
        final gollak = chart
            .byClass(AccountClass.money)
            .firstWhere((a) => a.name == 'Gollak Cash');
        expect(gollak.subtype, MoneySubtype.cashCollection);
        expect(
          chart.byClass(AccountClass.categoryIncome).map((a) => a.name),
          contains('Donation Income'),
        );
        expect(
          chart.byClass(AccountClass.categoryExpense).map((a) => a.name),
          containsAll(['Langar Expense', 'Building Repair', 'Honorarium']),
        );
      },
    );

    testWidgets(
      'F1-07-82 Save posts the typed rupees as integer paise against the '
      'trust book, dated at its start date — the gollak included',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final f = flow();
        var done = 0;
        await pumpHost(tester, ledger, f, onDone: () => done++);

        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '5000');
        await tester.enterText(fields.at(1), '750');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(done, 1);
        final bookId = f.trustBookId!;
        final chart = await ledger.chartOf(bookId);
        final cash = chart
            .byClass(AccountClass.money)
            .firstWhere((a) => a.name == 'Cash');
        final gollak = chart
            .byClass(AccountClass.money)
            .firstWhere((a) => a.name == 'Gollak Cash');
        final balances = await _balances(ledger);
        expect(balances[cash.id], 500000);
        expect(balances[gollak.id], 75000);
      },
    );

    testWidgets(
      'F1-07-82 Skip for now still leaves the trust book and its seeded '
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
        final chart = await ledger.chartOf(f.trustBookId!);
        final balances = await _balances(ledger);
        for (final a in chart.accounts) {
          expect(balances[a.id] ?? 0, 0);
        }
      },
    );

    testWidgets(
      'F1-07-82 resuming the step reuses the trust book it already made — '
      'never a second book for the same answers (07 §3.1.1)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final f = flow();
        await pumpHost(tester, ledger, f);
        final first = f.trustBookId;

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpHost(tester, ledger, f);

        expect(f.trustBookId, first);
        expect(await ledger.mirror.bookIds(), hasLength(2));
      },
    );

    testWidgets(
      'F1-07-82 an unanswered S0.6g is an error with a way on, never a '
      'blank screen (07 §1 rule 12)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        await pumpHost(tester, ledger, OnboardingFlow());

        expect(find.byType(TrustAccountsScreen), findsNothing);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
      },
    );
  });

  test('F1-07-80 S0.6g/h/i are in the 13 §3.2 inventory, each carrying its '
      'own test id', () {
    final doc = File('../docs/13-ux-architecture.md').readAsLinesSync();
    final g = doc.indexWhere((l) => l.startsWith('| **S0.6g**'));
    final h = doc.indexWhere((l) => l.startsWith('| **S0.6h**'));
    final i = doc.indexWhere((l) => l.startsWith('| **S0.6i**'));
    expect(g, greaterThan(-1));
    expect(h, greaterThan(g));
    expect(i, greaterThan(h));
    expect(doc[g], contains('F1-07-80'));
    expect(doc[h], contains('F1-07-81'));
    expect(doc[i], contains('F1-07-82'));
  });
}
