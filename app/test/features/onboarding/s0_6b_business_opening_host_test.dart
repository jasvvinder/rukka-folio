// F1 widget tests for the committing step of the business branch — the piece
// between S0.6a/S0.6a1 and S0.6b that actually creates the book, so that S0.6b
// can be the review-and-fill screen ADR 2026-09-09c §3 requires rather than a
// creation flow.
//
// Sources: 07 §3.1.1 (branch O6a → O6b, every step resumable), ADR
// 2026-09-09c §1 (the seeded chart) and §3 (one grouped screen), ADR
// 2026-09-09 §1 (the owners), ADR 2026-09-09d §4 (the start date).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_flow.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a1_business_owners_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a_business_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6b_business_opening_balances_screen.dart';
import 'package:rukka_folio/features/onboarding/widgets/business_opening_host.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

final _start = LocalDate(2026, 9, 7);

// The projections are read with plain Futures, never `stream.first`: cancelling
// a Drift subscription inside `flutter_test`'s fake-async zone never completes,
// and the test hangs at teardown rather than failing.
Future<Map<String, int>> _balances(LocalLedger l) async => {
  for (final r in await l.db.select(l.db.balances).get())
    r.accountId: r.balancePaise,
};

OnboardingFlow _flow({
  BusinessOwnershipChoice ownership = BusinessOwnershipChoice.justMe,
  List<OwnerDraft> owners = const [],
}) => OnboardingFlow()
  ..setYourName('Amrit Kaur')
  ..setBusiness(
    BusinessDraft(
      name: 'Amrit Kaur Agri',
      ownership: ownership,
      fyStartMonth: 4,
    ),
  )
  ..setOwners(owners);

Future<void> _pumpHost(
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
    BusinessOpeningHost(flow: flow, startDate: _start, onDone: onDone),
    ledger: ledger,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('S0.6b committing step (07 §3.1.1, ADR 2026-09-09c §1, §3)', () {
    testWidgets(
      'F1-09c-1 the book is created from the S0.6a answers, and its seeded '
      'chart becomes the rows — never an empty screen',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = _flow();
        await _pumpHost(tester, ledger, flow);

        expect(flow.businessBookId, isNotNull);
        final books = await ledger.db.select(ledger.db.booksP).get();
        final book = books.firstWhere((b) => b.id == flow.businessBookId);
        expect(book.name, 'Amrit Kaur Agri');
        expect(book.startDate, _start.toString());

        // The seeded cash account of ADR 2026-09-09c §1 is on screen, under
        // *What you have* — the review-and-fill S0.6b of §3.
        expect(find.byType(BusinessOpeningBalancesScreen), findsOneWidget);
        expect(find.text('Business Cash A/c'), findsOneWidget);
        // No bank is seeded (ADR 2026-09-09d §1): the group offers to add one.
        expect(find.textContaining('bank'), findsWidgets);
      },
    );

    testWidgets(
      'F1-09c-1 a shared business shows one Partner Current row per owner, '
      'in the order S0.6a1 gave them',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = _flow(
          ownership: BusinessOwnershipChoice.shared,
          owners: const [
            OwnerDraft(name: 'Amrit Kaur', isYou: true),
            OwnerDraft(name: 'Sukhdev Singh'),
          ],
        );
        await _pumpHost(tester, ledger, flow);

        expect(find.text('Amrit Kaur — Partner Current A/c'), findsOneWidget);
        expect(
          find.text('Sukhdev Singh — Partner Current A/c'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-09c-1 an unnamed first owner row falls back to the S0.4 name — the '
      'answer is carried forward, not dropped',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = _flow(
          ownership: BusinessOwnershipChoice.shared,
          owners: const [OwnerDraft(name: '', isYou: true)],
        );
        await _pumpHost(tester, ledger, flow);

        expect(find.text('Amrit Kaur — Partner Current A/c'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-09c-1 Save posts the typed rupees as integer paise against the new '
      'book, dated at its start date',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = _flow();
        var done = 0;
        await _pumpHost(tester, ledger, flow, onDone: () => done++);

        await tester.enterText(find.byType(TextField).first, '1500');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(done, 1);
        final bookId = flow.businessBookId!;
        final chart = await ledger.chartOf(bookId);
        final cash = chart
            .byClass(AccountClass.money)
            .firstWhere((a) => a.name == 'Business Cash A/c');
        expect((await _balances(ledger))[cash.id], 150000);
        final entries =
            await (ledger.db.select(ledger.db.entriesP)
                  ..where((e) => e.bookId.equals(bookId))
                  ..orderBy([(e) => OrderingTerm.asc(e.accountingDate)]))
                .get();
        expect(entries.single.accountingDate, _start.toString());
      },
    );

    testWidgets(
      'F1-09c-1 Skip for now still leaves the book and its seeded chart '
      'behind — nothing is posted, and the step is not a dead end',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = _flow();
        var done = 0;
        await _pumpHost(tester, ledger, flow, onDone: () => done++);

        await tester.tap(find.byType(TextButton).last);
        await tester.pumpAndSettle();

        expect(done, 1);
        final bookId = flow.businessBookId!;
        final chart = await ledger.chartOf(bookId);
        expect(chart.accounts, isNotEmpty);
        final balances = await _balances(ledger);
        for (final a in chart.accounts) {
          expect(balances[a.id] ?? 0, 0);
        }
      },
    );

    testWidgets(
      'F1-09c-1 resuming the step reuses the book it already made — never a '
      'second book for the same answers (07 §3.1.1)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = _flow();
        await _pumpHost(tester, ledger, flow);
        final first = flow.businessBookId;

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpHost(tester, ledger, flow);

        expect(flow.businessBookId, first);
        expect(await ledger.mirror.bookIds(), hasLength(2));
      },
    );

    testWidgets(
      'F1-09c-1 an unanswered S0.6a is an error with a way on, never a blank '
      'screen (07 §1 rule 12)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        await _pumpHost(tester, ledger, OnboardingFlow());

        expect(find.byType(BusinessOpeningBalancesScreen), findsNothing);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
      },
    );
  });
}
