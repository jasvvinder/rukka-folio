// F1-07-18 + F1-07-105…109: S5.5 the cash count sheet (07 §5.5 🔒, 02 §8.2 🔒,
// 13 §3.2 rows S5.5 and S2.4).
//
// The screen is pumped over the feature-local [FakeCashCountSource], which
// runs the engine's own `validateCount` / `resolveCount` (A-02-83…92) — so a
// green test here is green against 02 §8.2's rule, not against a stub's
// opinion of it. Every amount is synthetic (CLAUDE.md rule 4) and integer
// paise (rule 1).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/cash_count/cash_count_fake.dart';
import 'package:rukka_folio/features/cash_count/cash_count_money.dart';
import 'package:rukka_folio/features/cash_count/cash_count_routes.dart';
import 'package:rukka_folio/features/cash_count/widgets/denomination_grid.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/format/money_format.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

// ---- fixtures ---------------------------------------------------------------

/// The shop galla: a `cash` account, counted in **verify** mode.
Account gallaAccount({String book = 'book-1'}) => Account(
  id: 'galla',
  bookId: book,
  name: 'Galla',
  accountClass: AccountClass.money,
  subtype: MoneySubtype.cash,
  createdOrder: 1,
);

/// The gurudwara gollak: a `cash_collection` account, counted in **collect**
/// mode (02 §8.2 🔒).
Account gollakAccount({String book = 'book-1'}) => Account(
  id: 'gollak',
  bookId: book,
  name: 'Gollak',
  accountClass: AccountClass.money,
  subtype: MoneySubtype.cashCollection,
  createdOrder: 2,
);

Account donationsAccount({String book = 'book-1'}) => Account(
  id: 'donations',
  bookId: book,
  name: 'Donations',
  accountClass: AccountClass.categoryIncome,
  createdOrder: 3,
);

/// Verify mode: the book already says ₹2,500 sits in the galla.
CashCountTarget verifyTarget({
  BookType bookType = BookType.business,
  Paise bookBalance = const Paise(250000),
  LastCashCount? lastCount,
}) => CashCountTarget(
  bookId: 'book-1',
  bookType: bookType,
  account: gallaAccount(),
  bookBalance: bookBalance,
  lastCount: lastCount,
);

/// Collect mode: a trust's gollak, with one income A/C to recognise into.
CashCountTarget collectTarget({List<Account>? income}) => CashCountTarget(
  bookId: 'book-1',
  bookType: BookType.organization,
  account: gollakAccount(),
  bookBalance: Paise.zero,
  incomeAccounts: income ?? [donationsAccount()],
);

Future<void> pumpSheet(
  WidgetTester tester,
  FakeCashCountSource source, {
  String accountId = 'galla',
  bool readOnly = false,
  Locale? locale,
  double textScale = 1,
  Size? viewport,
  FakeSyncClient? sync,
}) => pumpRk(
  tester,
  CashCountScreen(accountId: accountId, source: source, readOnly: readOnly),
  locale: locale,
  sync: sync,
  textScale: textScale,
  viewport: viewport ?? rkTallViewport,
);

AppLocalizations stringsFor(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

/// Scrolls the sheet top to bottom, checking at every step that no word is
/// drawn past the edge of its box. A lazy list only builds what is on screen,
/// so a layout case that never scrolls has only tested the first screenful.
Future<void> sweep(WidgetTester tester, {required String reason}) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 10; i++) {
    expectTextFits(tester, reason: reason);
    await tester.drag(scrollable, const Offset(0, -320));
    await tester.pumpAndSettle();
  }
  expectTextFits(tester, reason: reason);
}

/// Types [rupees] into the single counted-total field (grid off).
Future<void> typeTotal(WidgetTester tester, String rupees) async {
  await tester.enterText(find.byType(TextField).first, rupees);
  await tester.pumpAndSettle();
}

/// Taps the `+` stepper of one note row [times] times.
Future<void> addNotes(
  WidgetTester tester,
  AppLocalizations l10n,
  int value,
  int times, {
  required Locale locale,
}) async {
  final face = formatPaise(Paise.rupees(value).raw, locale: locale);
  for (var i = 0; i < times; i++) {
    await tester.tap(find.bySemanticsLabel(l10n.countGridAdd(face)).first);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  const en = Locale('en');

  group(
    'S5.5 verify mode — the galla (02 §8.2 🔒 a count is a verification)',
    () {
      testWidgets(
        'F1-07-18 shows the book balance and states the difference in words',
        (tester) async {
          final source = FakeCashCountSource(target: verifyTarget());
          await pumpSheet(tester, source, locale: en);
          final l10n = stringsFor(tester);

          expect(find.text(l10n.countTitleVerify), findsOneWidget);
          expect(find.text(l10n.countBookLabel), findsOneWidget);
          expect(find.text('₹2,500'), findsOneWidget);

          // ₹2,270 counted against ₹2,500 in the book: ₹230 short, said in
          // words exactly as 07 §5.5 🔒 writes it.
          await typeTotal(tester, '2270');
          expect(find.text(l10n.countDifferenceLess('₹230')), findsOneWidget);
          // Colour is never alone (07 §1 rule 3): a direction glyph carries it.
          expect(find.byIcon(Icons.south_east), findsOneWidget);
          // The counted total, large at the top.
          expect(find.text('₹2,270'), findsOneWidget);
        },
      );

      testWidgets(
        'F1-07-18 a non-zero difference posts one guided adjustment in paise',
        (tester) async {
          final source = FakeCashCountSource(target: verifyTarget());
          await pumpSheet(tester, source, locale: en);
          final l10n = stringsFor(tester);
          await typeTotal(tester, '2270');

          await tester.tap(find.text(l10n.countSave));
          await tester.pumpAndSettle();

          // S2.4 is guided and this sheet is its only door (ADR 2026-09-03b §2
          // 🔒): the wizard states the engine's figure and nobody types it.
          expect(find.text(l10n.countConfirmTitle), findsOneWidget);
          expect(find.text(l10n.countConfirmLess('₹230')), findsOneWidget);
          await tester.tap(find.text(l10n.countConfirmSave));
          await tester.pumpAndSettle();

          expect(source.saved.single.counted.raw, 227000);
          final lines = source.posted.single;
          expect(lines.length, 2);
          expect(
            lines.firstWhere((l) => l.accountId == 'galla').amount.raw,
            -23000,
          );
          expect(
            lines.firstWhere((l) => l.accountId == 'adjustments').amount.raw,
            23000,
          );
          expect(find.text(l10n.countResultAdjusted('₹230')), findsOneWidget);
        },
      );

      testWidgets(
        'F1-07-18 an equal count posts nothing and reads verified on the date',
        (tester) async {
          final source = FakeCashCountSource(target: verifyTarget());
          await pumpSheet(tester, source, locale: en);
          final l10n = stringsFor(tester);
          await typeTotal(tester, '2500');

          expect(find.text(l10n.countDifferenceMatch), findsOneWidget);
          await tester.tap(find.text(l10n.countSave));
          await tester.pumpAndSettle();

          // No wizard: there is no difference to adjust (02 §8.2 🔒).
          expect(find.text(l10n.countConfirmTitle), findsNothing);
          expect(source.posted.single, isEmpty);
          expect(source.saved.single.counted.raw, 250000);
          expect(
            find.text(l10n.countResultVerified('07 Sep 2026')),
            findsOneWidget,
          );
        },
      );
    },
  );

  group('S5.5 collect mode — the gollak (02 §8.2 🔒 a count is a recognition)', () {
    testWidgets(
      'F1-07-105 counted total only: no book balance, two names and an income '
      'A/C required before Save',
      (tester) async {
        final source = FakeCashCountSource(target: collectTarget());
        await pumpSheet(tester, source, accountId: 'gollak', locale: en);
        final l10n = stringsFor(tester);

        expect(find.text(l10n.countTitleCollect), findsOneWidget);
        // Nothing to check against, so nothing is shown to check against.
        expect(find.text(l10n.countBookLabel), findsNothing);
        expect(find.text(l10n.countNamesRequired), findsOneWidget);

        await addNotes(tester, l10n, 500, 4, locale: en);
        // Both names still missing — Save is off and says which rule (02 §8.2).
        expect(find.text(l10n.countBlockedNames), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );

        await tester.enterText(
          find.widgetWithText(TextField, l10n.countNamesCountedBy),
          'Harpreet',
        );
        await tester.enterText(
          find.widgetWithText(TextField, l10n.countNamesWitness),
          'Sukhwinder',
        );
        await tester.pumpAndSettle();
        // Names in; now it is the income A/C that holds Save (02 §8.2).
        expect(find.text(l10n.countIncomeRequired), findsWidgets);
      },
    );

    testWidgets(
      'F1-07-105 saving recognises the full counted amount as income',
      (tester) async {
        final source = FakeCashCountSource(target: collectTarget());
        await pumpSheet(tester, source, accountId: 'gollak', locale: en);
        final l10n = stringsFor(tester);

        await addNotes(tester, l10n, 500, 4, locale: en);
        await addNotes(tester, l10n, 100, 3, locale: en);
        await tester.enterText(
          find.widgetWithText(TextField, l10n.countNamesCountedBy),
          'Harpreet',
        );
        await tester.enterText(
          find.widgetWithText(TextField, l10n.countNamesWitness),
          'Sukhwinder',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.countIncomeLabel).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Donations').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text(l10n.countSave));
        await tester.pumpAndSettle();

        // ₹2,300 = 4×₹500 + 3×₹100, in paise, Dr gollak · Cr Donations.
        final lines = source.posted.single;
        expect(
          lines.firstWhere((l) => l.accountId == 'gollak').amount.raw,
          230000,
        );
        expect(
          lines.firstWhere((l) => l.accountId == 'donations').amount.raw,
          -230000,
        );
        expect(source.saved.single.countedBy, 'Harpreet');
        expect(source.saved.single.witness, 'Sukhwinder');
        expect(source.saved.single.sheet!.total.raw, 230000);
        // The money has not moved: it is still in the box (02 §8.2 🔒).
        expect(find.text(l10n.countResultCollectedNote), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-105 a book with no income A/C says so and names the way out',
      (tester) async {
        final source = FakeCashCountSource(
          target: collectTarget(income: const []),
        );
        await pumpSheet(tester, source, accountId: 'gollak', locale: en);
        final l10n = stringsFor(tester);
        expect(find.text(l10n.countIncomeEmpty), findsOneWidget);
      },
    );
  });

  group('S5.5 the denomination grid (02 §8.2 🔒)', () {
    testWidgets(
      'F1-07-106 steppers carry a live line total into the counted total, and '
      'coins are one value',
      (tester) async {
        final source = FakeCashCountSource(target: verifyTarget());
        await pumpSheet(tester, source, locale: en);
        final l10n = stringsFor(tester);

        await tester.tap(find.text(l10n.countGridToggle));
        await tester.pumpAndSettle();
        await addNotes(tester, l10n, 500, 2, locale: en);
        await addNotes(tester, l10n, 20, 3, locale: en);

        // Line totals, live, per row (design-system §3.1 rule 6 🔒).
        expect(find.text('₹1,000'), findsOneWidget);
        expect(find.text('₹60'), findsOneWidget);
        // ₹1,060 counted so far.
        expect(find.text('₹1,060'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, l10n.countCoinsLabel),
          '40',
        );
        await tester.pumpAndSettle();
        expect(find.text('₹1,100'), findsOneWidget);

        await tester.tap(find.text(l10n.countSave));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.countConfirmSave));
        await tester.pumpAndSettle();
        final sheet = source.saved.single.sheet!;
        expect(sheet.notes, {500: 2, 20: 3});
        expect(sheet.coinsPaise.raw, 4000);
        expect(sheet.total.raw, 110000);
      },
    );

    testWidgets(
      'F1-07-106 ₹2000 appears only when the previous count used it',
      (tester) async {
        final source = FakeCashCountSource(target: verifyTarget());
        await pumpSheet(tester, source, locale: en);
        final l10n = stringsFor(tester);
        await tester.tap(find.text(l10n.countGridToggle));
        await tester.pumpAndSettle();
        expect(find.text(l10n.countGridRow('₹2,000')), findsNothing);
        expect(find.text(l10n.countGridRow('₹500')), findsOneWidget);

        final withTwoThousand = FakeCashCountSource(
          target: verifyTarget(
            lastCount: LastCashCount(
              date: LocalDate(2026, 8, 27),
              counted: const Paise(250000),
              sheet: const DenominationSheet(notes: {2000: 1, 500: 1}),
            ),
          ),
        );
        await pumpSheet(tester, withTwoThousand, locale: en);
        await tester.tap(find.text(l10n.countGridToggle));
        await tester.pumpAndSettle();
        expect(find.text(l10n.countGridRow('₹2,000')), findsOneWidget);
        expect(find.text(l10n.countLastCounted('27 Aug 2026')), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-106 an organization book counts note by note for every cash A/C, '
      'and the switch says why it cannot be turned off',
      (tester) async {
        final source = FakeCashCountSource(
          target: verifyTarget(bookType: BookType.organization),
        );
        await pumpSheet(tester, source, locale: en);
        final l10n = stringsFor(tester);

        expect(find.text(l10n.countGridRequired), findsOneWidget);
        expect(find.text(l10n.countGridRow('₹500')), findsOneWidget);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
          isNull,
        );
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );
      },
    );
  });

  group('S5.5 states (13 §4.3)', () {
    testWidgets(
      'F1-07-107 loading skeleton · error with retry · read-only with its '
      'reason · the quiet offline chip',
      (tester) async {
        // Loading: the ruled skeleton, never a spinner (11 §4.5).
        final slow = FakeCashCountSource(
          target: verifyTarget(),
          loadDelay: const Duration(seconds: 5),
        );
        await pumpSheet(tester, slow, locale: en);
        final l10n = stringsFor(tester);
        expect(find.bySemanticsLabel(l10n.countSkeleton), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text(l10n.countTotalLabel), findsWidgets);

        // Error, with a retry that actually reloads.
        final broken = FakeCashCountSource(
          target: verifyTarget(),
          failLoad: true,
        );
        await pumpSheet(tester, broken, locale: en);
        expect(find.text(l10n.countError), findsOneWidget);
        broken.failLoad = false;
        await tester.tap(find.text(l10n.countRetry));
        await tester.pumpAndSettle();
        expect(find.text(l10n.countBookLabel), findsOneWidget);

        // Read-only: legible, and the action says why it is off (S12.5).
        final readOnly = FakeCashCountSource(target: verifyTarget());
        await pumpSheet(tester, readOnly, locale: en, readOnly: true);
        expect(find.text(l10n.countReadonlyBanner), findsOneWidget);
        expect(find.text(l10n.countBlockedReadonly), findsWidgets);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );

        // Offline is normal, not an error (07 §1 rule 7 🔒): a quiet chip, and
        // Save keeps working.
        final offline = FakeCashCountSource(target: verifyTarget());
        await pumpSheet(
          tester,
          offline,
          locale: en,
          sync: FakeSyncClient(initial: const Offline()),
        );
        expect(find.text(l10n.countOffline), findsOneWidget);
        await typeTotal(tester, '2500');
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('F1-07-107 a save that fails keeps every counted figure', (
      tester,
    ) async {
      final source = FakeCashCountSource(
        target: verifyTarget(),
        failSave: true,
      );
      await pumpSheet(tester, source, locale: en);
      final l10n = stringsFor(tester);
      await typeTotal(tester, '2500');
      await tester.tap(find.text(l10n.countSave));
      await tester.pumpAndSettle();

      expect(find.text(l10n.countSaveError), findsOneWidget);
      expect(find.text('₹2,500'), findsWidgets);
      source.failSave = false;
      await tester.tap(find.text(l10n.countRetry));
      await tester.pumpAndSettle();
      expect(source.saved, hasLength(1));
    });
  });

  group('S5.5 three languages, 200 % text, 360×800', () {
    for (final locale in rkLocales) {
      testWidgets(
        'F1-07-108 verify mode reads in ${locale.languageCode} at 200 % '
        'without a word leaving the screen',
        (tester) async {
          final source = FakeCashCountSource(
            target: verifyTarget(
              lastCount: LastCashCount(
                date: LocalDate(2026, 8, 27),
                counted: const Paise(250000),
                sheet: const DenominationSheet(notes: {2000: 1}),
              ),
            ),
          );
          await pumpSheet(
            tester,
            source,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          final l10n = stringsFor(tester);
          expect(find.text(l10n.countTitleVerify), findsWidgets);
          expect(tester.takeException(), isNull);
          await sweep(tester, reason: 'S5.5 verify, ${locale.languageCode}');

          // The grid at the same width and scale — an organization book has
          // it open from the start (02 §8.2 🔒), which is also the tallest,
          // busiest form of this screen.
          final trust = FakeCashCountSource(
            target: verifyTarget(bookType: BookType.organization),
          );
          await pumpSheet(
            tester,
            trust,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          await tester.dragUntilVisible(
            find.byType(DenominationGrid),
            find.byType(Scrollable).first,
            const Offset(0, -320),
          );
          expect(find.byType(DenominationGrid), findsOneWidget);
          expect(tester.takeException(), isNull);
          await sweep(tester, reason: 'S5.5 grid, ${locale.languageCode}');
        },
      );

      testWidgets(
        'F1-07-108 collect mode reads in ${locale.languageCode} at 200 % '
        'without a word leaving the screen',
        (tester) async {
          final source = FakeCashCountSource(target: collectTarget());
          await pumpSheet(
            tester,
            source,
            accountId: 'gollak',
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          final l10n = stringsFor(tester);
          expect(find.text(l10n.countTitleCollect), findsWidgets);
          expect(tester.takeException(), isNull);
          await sweep(tester, reason: 'S5.5 collect, ${locale.languageCode}');
        },
      );
    }
  });

  group('S5.5 the rules that outlive the layout', () {
    testWidgets(
      'F1-07-109 the guided adjustment can be refused, and refusing records '
      'nothing at all',
      (tester) async {
        final source = FakeCashCountSource(target: verifyTarget());
        await pumpSheet(tester, source, locale: en);
        final l10n = stringsFor(tester);
        await typeTotal(tester, '2270');
        await tester.tap(find.text(l10n.countSave));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.countConfirmCancel));
        await tester.pumpAndSettle();

        // Nothing saved, nothing posted, and the sheet is as it was — the
        // count is never half-recorded (02 §8.2 🔒, 07 §1 rule 6).
        expect(source.saved, isEmpty);
        expect(source.posted, isEmpty);
        expect(find.text('₹2,270'), findsWidgets);
        expect(find.text(l10n.countSave), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-109 the counted total announces itself as a total, not a bare '
      'number',
      (tester) async {
        final source = FakeCashCountSource(target: verifyTarget());
        await pumpSheet(tester, source, locale: en);
        final l10n = stringsFor(tester);
        await typeTotal(tester, '2270');
        // Value **plus what it is** (design-system §3.1 rule 5 🔒): the hero
        // figure is announced as a counted total, never as a bare number.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == l10n.countTotalSemantics('₹2,270'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('F1-07-109 typed rupees become integer paise, never a double', (
      tester,
    ) async {
      expect(paiseFromRupeeInput('2,270'), 227000);
      expect(paiseFromRupeeInput('₹12.50'), 1250);
      expect(paiseFromRupeeInput('12.5'), 1250);
      expect(paiseFromRupeeInput(''), isNull);
      expect(paiseFromRupeeInput('12.505'), isNull);
      expect(paiseFromRupeeInput('abc'), isNull);

      final source = FakeCashCountSource(target: verifyTarget());
      await pumpSheet(tester, source, locale: const Locale('en'));
      final l10n = stringsFor(tester);
      await typeTotal(tester, '2,500.50');
      await tester.tap(find.text(l10n.countSave));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.countConfirmSave));
      await tester.pumpAndSettle();
      expect(source.saved.single.counted.raw, 250050);
    });
  });
}
