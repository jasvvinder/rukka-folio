// F1-07-24 (07 §10 🔒 — the Family Reconciliation screen) and F1-07-100…104
// (13 §3.2 row S8.3, 02 §6 🔒, ADR 2026-09-05e §7 🔒) for S8.3 Family
// reconciliation, reached from S8.1.
//
// What the screen owes the reader, in the docs' own words:
//   • *"normally a single proud green ✓"* (07 §10) — and a tick is a colour, so
//     it is **stated in words** beside the icon (07 §1 rule 3).
//   • a non-zero pair is *"listed with the entries composing it"* (02 §6 🔒).
//   • a side the reader cannot open is **one-sided · unconfirmed**, *"never as
//     a mismatch"* (ADR 2026-09-05e §7 🔒) — the word *mismatch* must not be
//     anywhere near it.
//
// This is a CONSUMER surface (02 §10 🔒, CLAUDE.md rule 9): *Money in / Money
// out*, never Dr/Cr. The figures come from real postings through `LocalLedger`
// — the same derivation `InterBook.reconcile` owns — so nothing here asserts a
// number the engine did not produce.
@Tags(['F1'])
library;

import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/reports/screens/s8_1_reports_list_screen.dart';
import 'package:rukka_folio/features/reports/screens/s8_3_family_reconciliation_screen.dart';
import 'package:rukka_folio/features/reports/widgets/reports_row.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

/// Tears the tree down inside the test and lets drift's zero-duration stream
/// cleanup timers run out (the S8.2 pattern).
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

/// Every [Text] in the tree, plain data or rendered span (MoneyText writes its
/// direction word into a `Text.rich`).
List<String> texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

void main() {
  late SeededLedger s;
  late String familyId;
  late String familyCashId;

  Future<void> seedSecondBook() async {
    familyId = await s.ledger.createBook(
      name: 'Sharma Family',
      type: BookType.family,
    );
    familyCashId = (await s.ledger.chartOf(familyId))
        .byClass(AccountClass.money)
        .first
        .id;
  }

  Future<InterBookMovement> move({int paise = 5_000_000}) =>
      s.ledger.transferBetweenBooks(
        fromBookId: s.bookId,
        fromAccountId: s.bankId,
        toBookId: familyId,
        toAccountId: familyCashId,
        paise: paise,
        date: s.ledger.today(),
      );

  setUp(() async {
    s = await seedSoloLedger();
  });

  group('S8.3 Family reconciliation (07 §10 🔒, 02 §6 🔒)', () {
    testWidgets(
      'F1-07-24 S8.1 opens S8.3 — the Family Reconciliation row is enterable '
      'once the destination is wired (07 §10 🔒, 07 §1 rule 6)',
      (tester) async {
        var opened = 0;
        await pumpRk(
          tester,
          ReportsListScreen(onOpenReconciliation: () => opened++),
          viewport: rkTallViewport,
        );

        // Still one row per report, in 07 §14's 🔒 order — this one is no
        // longer disabled-with-reason.
        expect(find.byType(ReportsActionRow), findsOneWidget);
        await tester.tap(find.text('Family Reconciliation'));
        await tester.pumpAndSettle();
        expect(opened, 1);
      },
    );

    testWidgets(
      'F1-07-100 the normal state is one green ✓ stated in words — colour '
      'never alone (07 §10, 07 §1 rule 3)',
      (tester) async {
        await seedSecondBook();
        await move();

        await pumpRk(
          tester,
          const FamilyReconciliationScreen(),
          ledger: s.ledger,
          viewport: rkTallViewport,
        );

        expect(find.text('Everything matches'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
        // The pair itself says so in words too, and names both books.
        expect(find.text('Matched'), findsOneWidget);
        expect(texts(tester).join(' '), contains('Sharma Family'));
        // Nothing claims a problem.
        expect(find.text('Does not match'), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-101 a non-zero pair is listed with the entries composing it '
      '(02 §6 🔒)',
      (tester) async {
        await seedSecondBook();
        final m = await move();
        // The receiving half is reversed: the pair stops netting to zero.
        await s.ledger.reverse(m.to.id, date: s.ledger.today());

        final opened = <String>[];
        await pumpRk(
          tester,
          FamilyReconciliationScreen(onOpenEntry: opened.add),
          ledger: s.ledger,
          viewport: rkTallViewport,
        );

        expect(find.text('Does not match'), findsOneWidget);
        expect(find.text('1 pair does not match'), findsOneWidget);
        expect(find.text('Everything matches'), findsNothing);
        // The composing entries are on screen — three of them: the two halves
        // and the reversal.
        expect(find.text('Entries behind this'), findsOneWidget);
        expect(find.byType(ReconciliationEntryRow), findsNWidgets(3));
        // And each one opens (07 §1 rule 8: the audit trail is one tap away).
        await tester.tap(find.byType(ReconciliationEntryRow).first);
        await tester.pumpAndSettle();
        expect(opened, hasLength(1));
        await unmount(tester);
      },
    );

    testWidgets('F1-07-102 a one-sided pair reads unconfirmed, never mismatch '
        '(ADR 2026-09-05e §7 🔒)', (tester) async {
      final due = await s.ledger.dueToFromAccount(
        s.bookId,
        counterpartBookId: 'book-we-hold-no-key-for',
        name: 'Due to/from Bhraji',
      );
      await s.ledger.transfer(
        bookId: s.bookId,
        from: s.cashId,
        to: due.id,
        paise: 300_000,
        date: s.ledger.today(),
      );

      await pumpRk(
        tester,
        const FamilyReconciliationScreen(),
        ledger: s.ledger,
        viewport: rkTallViewport,
      );

      expect(find.text('One side only · not confirmed'), findsOneWidget);
      expect(find.text('1 pair could not be checked'), findsOneWidget);
      final rendered = texts(tester).join(' ').toLowerCase();
      expect(
        rendered,
        isNot(contains('does not match')),
        reason: 'a sealed side is never a mismatch (ADR 2026-09-05e §7 🔒)',
      );
      expect(rendered, contains('not a mismatch'));
      await unmount(tester);
    });

    testWidgets(
      'F1-07-103 every 13 §4.3 state: loading skeleton, empty with its one '
      'next action, error with retry',
      (tester) async {
        // Loading — a stream that has not emitted yet (11 §4.5 ruled skeleton).
        await pumpRk(
          tester,
          FamilyReconciliationScreen(
            // A stream that has not emitted and has not closed: the real
            // shape of a first frame, with no timer to outlive the test.
            source: (_) => StreamController<List<ReconciliationPair>>().stream,
          ),
          ledger: s.ledger,
          viewport: rkTallViewport,
        );
        expect(find.bySemanticsLabel('Checking your books'), findsOneWidget);

        // Empty — no book has moved money to another yet.
        await pumpRk(
          tester,
          const FamilyReconciliationScreen(),
          ledger: s.ledger,
          viewport: rkTallViewport,
        );
        expect(
          find.text('No money has moved between your books yet.'),
          findsOneWidget,
        );
        // …and the one next action is offered when there is somewhere to go.
        await pumpRk(
          tester,
          FamilyReconciliationScreen(onMoveMoney: () {}),
          ledger: s.ledger,
          viewport: rkTallViewport,
        );
        expect(find.text('Move money between books'), findsOneWidget);

        // Error — with the retry, never a raw code (07 §1 rule 12).
        var calls = 0;
        await pumpRk(
          tester,
          FamilyReconciliationScreen(
            source: (_) {
              calls++;
              return Stream<List<ReconciliationPair>>.error(
                StateError('no read'),
              );
            },
          ),
          ledger: s.ledger,
          viewport: rkTallViewport,
        );
        expect(find.text('The check could not be run.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(calls, 2);
        await unmount(tester);
      },
    );

    for (final locale in rkLocales) {
      testWidgets(
        'F1-07-104 S8.3 resolves in ${locale.languageCode} at 200% on '
        '360x800 with no overflow, in consumer words (02 §10 🔒)',
        (tester) async {
          await seedSecondBook();
          final m = await move();
          await s.ledger.reverse(m.to.id, date: s.ledger.today());

          await pumpRk(
            tester,
            const FamilyReconciliationScreen(),
            ledger: s.ledger,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );

          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: 'S8.3 at 200% on $rkPhone360');
          // Consumer vocabulary only — the ledger's Dr/Cr stays on the
          // professional surfaces (02 §10 🔒, CLAUDE.md rule 9).
          final rendered = texts(tester).join(' ');
          expect(rendered, isNot(matches(RegExp(r'\bDr\b'))));
          expect(rendered, isNot(matches(RegExp(r'\bCr\b'))));
          await unmount(tester);
        },
      );
    }
  });
}
