// ADR 2026-10-07b 🔒 — an account created inside an entry asks for its opening
// balance afterwards, on its statement (S4) and with a marker in the Ledger
// index (S3); the answer posts what S3.1 posts.
//
// TEST HONESTY: every screen is built with exactly the arguments its
// production route passes (ledger_routes.dart: S4 with accountId +
// onOpenEntry + onCountCash, nothing else; S3 with onOpenAccount +
// onOpenSearch), over a real in-memory LocalLedger. No test hands a screen a
// flag: whether an account asks is `LocalLedger.watchOpeningUnanswered`,
// derived from the envelopes. The person is created with exactly the call the
// entry picker's inline create makes (`s2_add_entry_screen.dart` `_create`:
// `ledger.addAccount(bookId, name:, accountClass:)`, no opening). Synthetic
// names and sums only (CLAUDE.md rule 4); money is integer paise.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s3_1_quick_add_sheet.dart';
import 'package:rukka_folio/features/ledger/screens/s3_ledger_index_screen.dart';
import 'package:rukka_folio/features/ledger/screens/s4_account_statement_screen.dart';
import 'package:rukka_folio/features/ledger/widgets/opening_prompt.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/format/date_format.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/closed_years.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../../shared/test_app.dart';
import '../entry/restriction_support.dart';

/// The seeded book plus the c7 cast: a person created from the entry picker
/// (Gurdeep Singh, ₹500 lent today, no opening) and an expense category
/// created the same way (Tea Expense).
final class _Book {
  _Book(this.seed, this.personId, this.teaId);
  final SeededLedger seed;
  final String personId;
  final String teaId;
  LocalLedger get ledger => seed.ledger;
  String get bookId => seed.bookId;
}

Future<_Book> _book(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final seed = await seedSoloLedger();
      final l = seed.ledger;
      // The entry picker's inline create, verbatim (s2_add_entry_screen.dart).
      final person = await l.addAccount(
        seed.bookId,
        name: 'Gurdeep Singh',
        accountClass: AccountClass.party,
      );
      final tea = await l.addAccount(
        seed.bookId,
        name: 'Tea Expense',
        accountClass: AccountClass.categoryExpense,
      );
      await l.gaveCredit(
        bookId: seed.bookId,
        toWhom: person.id,
        gave: seed.cashId,
        paise: 500_00,
        date: l.today(),
        note: 'Lent for the tractor repair',
      );
      await l.moneyOut(
        bookId: seed.bookId,
        from: seed.cashId,
        forWhat: tea.id,
        paise: 40_00,
        date: l.today(),
      );
      return _Book(seed, person.id, tea.id);
    }))!;

/// S4 exactly as ledger_routes.dart builds it.
AccountStatementScreen _statement(String accountId) => AccountStatementScreen(
  accountId: accountId,
  onOpenEntry: (_) {},
  onCountCash: (_) {},
);

/// S3 exactly as ledger_routes.dart builds it.
LedgerIndexScreen _index() =>
    LedgerIndexScreen(onOpenAccount: (_) {}, onOpenSearch: () {});

Future<void> _pumpStatement(
  WidgetTester tester,
  LocalLedger ledger,
  String accountId, {
  EntitlementSource? entitlement,
}) => pumpUnderEntitlement(
  tester,
  _statement(accountId),
  ledger: ledger,
  entitlement: entitlement,
  viewport: const Size(400, 1400),
);

/// Opening adjustments posted to [accountId]: (date, line on the A/C, line on
/// Opening Balance), read from the projection.
Future<List<(String, int, int)>> _openings(
  WidgetTester tester,
  LocalLedger ledger,
  String accountId,
) async => (await tester.runAsync(() async {
  final rows = await ledger.db
      .customSelect(
        'SELECT e.accounting_date AS d, l.amount_paise AS mine, '
        'o.amount_paise AS ob FROM entries_p e '
        'JOIN entry_lines_p l ON l.entry_id = e.id AND l.account_id = ? '
        'JOIN entry_lines_p o ON o.entry_id = e.id '
        'JOIN accounts_p a ON a.id = o.account_id '
        "WHERE e.kind = 'adjustment' AND a.system_role = 'opening_balance'",
        variables: [Variable.withString(accountId)],
      )
      .get();
  return [
    for (final r in rows)
      (r.read<String>('d'), r.read<int>('mine'), r.read<int>('ob')),
  ];
}))!;

/// Device B: a fresh database with A's keys (the book key as key sync leaves
/// it, `key_cache`) holding exactly A's envelopes, rebuilt from them.
Future<LocalLedger> _secondDevice(WidgetTester tester, _Book a) async =>
    (await tester.runAsync(() async {
      final b = await openTestLedger(keys: a.ledger.keys as FakeKeyStore);
      for (final k in await a.ledger.db.select(a.ledger.db.keyCache).get()) {
        await b.db.into(b.db.keyCache).insert(k.toCompanion(false));
      }
      await b.openIdentity();
      for (final r
          in await a.ledger.db.select(a.ledger.db.envelopesLocal).get()) {
        await b.db.into(b.db.envelopesLocal).insert(r.toCompanion(false));
      }
      await b.rebuild(a.bookId);
      return b;
    }))!;

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  group('ruling 1 — the question waits on the account', () {
    testWidgets('F1-1007b-1 S4 of a person created from the entry picker '
        'opens with *Opening balance not set*, *Add opening balance* and '
        '*Not needed*, above the year', (tester) async {
      final b = await _book(tester);
      await _pumpStatement(tester, b.ledger, b.personId);

      expect(find.byKey(OpeningPromptKeys.card), findsOneWidget);
      expect(find.text('Opening balance not set'), findsOneWidget);
      expect(
        find.text(
          'Did Gurdeep Singh owe you anything before today? Add it so this '
          'khata shows the right balance.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Add opening balance'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Not needed'), findsOneWidget);
      // At the top: above the statement's own first row.
      expect(
        tester.getTopLeft(find.byKey(OpeningPromptKeys.card)).dy,
        lessThan(
          tester.getTopLeft(find.textContaining('Opening balance b/f')).dy,
        ),
      );
      await unmountTree(tester);
    });

    testWidgets('F1-1007b-1 an expense A/C created the same way never asks '
        '(02 §4: categories start at zero)', (tester) async {
      final b = await _book(tester);
      await _pumpStatement(tester, b.ledger, b.teaId);
      expect(find.text('Tea Expense'), findsWidgets);
      expect(find.byKey(OpeningPromptKeys.card), findsNothing);
      expect(find.text('Opening balance not set'), findsNothing);
      await unmountTree(tester);
    });

    testWidgets('F1-1007b-1 S3 marks the unanswered person with a quiet line '
        '— icon and words in ink, not amber — and no other row', (
      tester,
    ) async {
      final b = await _book(tester);
      // Answer the seed's own person first, so the only unanswered A/C left is
      // the one the entry picker made.
      await tester.runAsync(
        () => b.ledger.openingBalances(
          b.bookId,
          balances: {b.seed.partyId: 100_00},
        ),
      );
      await pumpRk(
        tester,
        _index(),
        ledger: b.ledger,
        viewport: rkTallViewport,
      );
      await settleIo(tester);

      final marker = find.byKey(OpeningPromptKeys.marker);
      expect(marker, findsOneWidget);
      final row = find.ancestor(of: marker, matching: find.byType(ListTile));
      expect(
        find.descendant(of: row, matching: find.text('Gurdeep Singh')),
        findsOneWidget,
      );
      // Colour never alone (07 §1 rule 3): an icon and the words.
      expect(
        find.descendant(of: marker, matching: find.byIcon(Icons.info_outline)),
        findsOneWidget,
      );
      final words = tester.widget<Text>(
        find.descendant(
          of: marker,
          matching: find.text('Opening balance not set'),
        ),
      );
      final scheme = Theme.of(tester.element(marker)).colorScheme;
      expect(words.style?.color, scheme.primary);
      await unmountTree(tester);
    });
  });

  group('ruling 1 — answered stays answered, on every device', () {
    testWidgets('F1-1007b-2 an A/C answered in S3.1 (the production sheet) '
        'with a non-zero opening carries no marker and no prompt', (
      tester,
    ) async {
      final b = await _book(tester);
      await pumpRk(
        tester,
        _index(),
        ledger: b.ledger,
        viewport: rkTallViewport,
      );
      await settleIo(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Someone who owes me'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Jaspal');
      await tester.enterText(
        find.widgetWithText(TextField, 'How much, and who owes whom'),
        '750',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settleIo(tester);
      expect(find.byType(QuickAddSheet), findsNothing);

      final jaspal = find.ancestor(
        of: find.text('Jaspal'),
        matching: find.byType(ListTile),
      );
      expect(jaspal, findsOneWidget);
      expect(
        find.descendant(
          of: jaspal,
          matching: find.byKey(OpeningPromptKeys.marker),
        ),
        findsNothing,
      );
      // The entry-picker person beside it still asks — the check is per A/C.
      final gurdeep = find.ancestor(
        of: find.text('Gurdeep Singh'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: gurdeep,
          matching: find.byKey(OpeningPromptKeys.marker),
        ),
        findsOneWidget,
      );
      await unmountTree(tester);
    });

    // ⚠️ SPEC (ADR 2026-10-07b Open ⚠️, PLAN desk 177) — the case the interim
    // derivation gets WRONG, kept here rather than hidden: S3.1 (and setup,
    // S0.6/S0.6b) posts nothing for a blank or zero answer (02 §4), so no
    // synced data says the question was answered, and
    // `watchOpeningUnanswered` marks the person. Ruling 1 says S3.1 is
    // unchanged and sets the *answered* flag. It goes green once the account
    // object carries that flag — an envelope field, which the ADR reserves
    // for 03 and the owner.
    testWidgets(
      'F1-1007b-2 an A/C answered in S3.1 with a ZERO (blank) opening carries '
      'no marker',
      skip: true, // blocked: owner ruling on the synced *answered* field.
      (tester) async {
        final b = await _book(tester);
        await pumpRk(
          tester,
          _index(),
          ledger: b.ledger,
          viewport: rkTallViewport,
        );
        await settleIo(tester);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Someone who owes me'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Name'),
          'Jaspal',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await settleIo(tester);
        final jaspal = find.ancestor(
          of: find.text('Jaspal'),
          matching: find.byType(ListTile),
        );
        expect(
          find.descendant(
            of: jaspal,
            matching: find.byKey(OpeningPromptKeys.marker),
          ),
          findsNothing,
        );
        await unmountTree(tester);
      },
    );

    testWidgets('F1-1007b-2 device B, holding the same envelopes, does not ask '
        'again for what A answered — and still asks for what A did not', (
      tester,
    ) async {
      final a = await _book(tester);
      // A answers the seed's person; Gurdeep stays unanswered.
      await tester.runAsync(
        () => a.ledger.openingBalances(
          a.bookId,
          balances: {a.seed.partyId: -2_000_00},
        ),
      );
      final deviceB = await _secondDevice(tester, a);

      await _pumpStatement(tester, deviceB, a.seed.partyId);
      expect(find.text('Ramesh'), findsWidgets);
      expect(find.byKey(OpeningPromptKeys.card), findsNothing);
      await unmountTree(tester);

      await _pumpStatement(tester, deviceB, a.personId);
      expect(find.byKey(OpeningPromptKeys.card), findsOneWidget);
      await unmountTree(tester);
    });

    testWidgets('F1-1007b-2 *Not needed* is disabled with its reason in words '
        'until the answer has a synced home (⚠️ SPEC, ADR 2026-10-07b Open)', (
      tester,
    ) async {
      final b = await _book(tester);
      await _pumpStatement(tester, b.ledger, b.personId);
      final notNeeded = tester.widget<TextButton>(
        find.byKey(OpeningPromptKeys.notNeeded),
      );
      expect(notNeeded.onPressed, isNull);
      expect(find.byKey(OpeningPromptKeys.notNeededReason), findsOneWidget);
      expect(
        find.textContaining("Not needed can't be saved yet"),
        findsOneWidget,
      );
      await unmountTree(tester);
    });
  });

  group('ruling 2 — the answer posts what S3.1 posts', () {
    testWidgets('F1-1007b-3 *You owe them* ₹1,250.50 posts ONE adjustment '
        'against Opening Balance, dated at the book start, in integer paise; '
        'the prompt goes', (tester) async {
      final b = await _book(tester);
      final start = (await tester.runAsync(
        () => b.ledger.startDateOf(b.bookId),
      ))!;
      await _pumpStatement(tester, b.ledger, b.personId);
      final before = await envelopeCount(tester, b.ledger);

      await tester.tap(find.byKey(OpeningPromptKeys.add));
      await settleIo(tester);
      expect(find.byKey(OpeningPromptKeys.sheet), findsOneWidget);
      expect(find.text('Gurdeep Singh, before today'), findsOneWidget);
      expect(
        find.text(
          'Recorded as the opening balance on '
          '${formatLedgerDate(start, strings: lookupAppLocalizations(const Locale('en')))}, '
          'the day this book starts.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(OpeningPromptKeys.youOwe));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(OpeningPromptKeys.amount), '1250.50');
      await tester.pumpAndSettle();
      // ₹500 lent today, ₹1,250.50 owed to him before: you will give ₹750.
      expect(find.text('You will give ₹750 in all.'), findsOneWidget);
      await tester.tap(find.byKey(OpeningPromptKeys.save));
      await settleIo(tester);

      expect(find.byKey(OpeningPromptKeys.sheet), findsNothing);
      expect(await envelopeCount(tester, b.ledger), before + 1);
      expect(await _openings(tester, b.ledger, b.personId), [
        (start.toString(), -1_250_50, 1_250_50),
      ]);
      expect(find.byKey(OpeningPromptKeys.card), findsNothing);
      await unmountTree(tester);
    });

    testWidgets('F1-1007b-3 *They owe you* is the side the sheet opens on and '
        'posts a Dr (you will get)', (tester) async {
      final b = await _book(tester);
      await _pumpStatement(tester, b.ledger, b.personId);
      await tester.tap(find.byKey(OpeningPromptKeys.add));
      await settleIo(tester);
      await tester.enterText(find.byKey(OpeningPromptKeys.amount), '2000');
      await tester.pumpAndSettle();
      expect(find.text('You will get ₹2,500 in all.'), findsOneWidget);
      await tester.tap(find.byKey(OpeningPromptKeys.save));
      await settleIo(tester);
      final posted = await _openings(tester, b.ledger, b.personId);
      expect(posted.single.$2, 2_000_00);
      expect(posted.single.$3, -2_000_00);
      await unmountTree(tester);
    });

    testWidgets('F1-1007b-3 an empty or zero amount posts nothing and says '
        'why; Cancel posts nothing and the prompt stays', (tester) async {
      final b = await _book(tester);
      await _pumpStatement(tester, b.ledger, b.personId);
      final before = await envelopeCount(tester, b.ledger);
      await tester.tap(find.byKey(OpeningPromptKeys.add));
      await settleIo(tester);
      await tester.enterText(find.byKey(OpeningPromptKeys.amount), '0');
      await tester.tap(find.byKey(OpeningPromptKeys.save));
      await settleIo(tester);
      expect(find.text("Enter the amount. It can't be zero."), findsOneWidget);
      expect(await envelopeCount(tester, b.ledger), before);
      await tester.tap(find.byKey(OpeningPromptKeys.cancel));
      await settleIo(tester);
      expect(find.byKey(OpeningPromptKeys.sheet), findsNothing);
      expect(find.byKey(OpeningPromptKeys.card), findsOneWidget);
      expect(await envelopeCount(tester, b.ledger), before);
      await unmountTree(tester);
    });

    testWidgets("F1-1007b-3 the book's first month is locked: the sheet says "
        'so and the opening lands on the first day of the earliest open month '
        '(ADR 2026-09-09d §4, A-09d-5); the prompt goes', (tester) async {
      final b = await _book(tester);
      final start = (await tester.runAsync(
        () => b.ledger.startDateOf(b.bookId),
      ))!;
      await tester.runAsync(
        () => b.ledger.lockMonth(
          b.bookId,
          start.yearMonth,
          declaredBalances: const {},
        ),
      );
      final firstOpen = start.yearMonth.next.firstDay;
      await _pumpStatement(tester, b.ledger, b.personId);
      expect(find.byKey(OpeningPromptKeys.card), findsOneWidget);
      await tester.tap(find.byKey(OpeningPromptKeys.add));
      await settleIo(tester);
      expect(
        find.text(
          'Recorded as the opening balance on '
          '${formatLedgerDate(firstOpen, strings: lookupAppLocalizations(const Locale('en')))}, '
          'the first open month — the month this book starts in is closed.',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(OpeningPromptKeys.amount), '600');
      await tester.tap(find.byKey(OpeningPromptKeys.save));
      await settleIo(tester);

      expect(find.byKey(OpeningPromptKeys.sheet), findsNothing);
      expect(
        find.text(
          "Couldn't save the opening balance. Try again — or correct it later "
          'in Your books → Opening balances.',
        ),
        findsNothing,
      );
      expect(await _openings(tester, b.ledger, b.personId), [
        (firstOpen.toString(), 600_00, -600_00),
      ]);
      expect(find.byKey(OpeningPromptKeys.card), findsNothing);
      await unmountTree(tester);
    });

    testWidgets("F1-1007b-3 the *in all* figure is the A/C's balance across "
        'all time, never the closing of the year S4 is showing — here a past '
        'year with nothing in it', (tester) async {
      final b = await _book(tester);
      final past = FinancialYear.of(LocalDate(2025, 6, 1), startMonth: 4);
      // The one seam S4 takes besides its route's arguments: which years are
      // closed (production reads it from the shell's ClosedYearsScope).
      await pumpUnderEntitlement(
        tester,
        AccountStatementScreen(
          accountId: b.personId,
          onOpenEntry: (_) {},
          onCountCash: (_) {},
          closedYears: (_, _) async => [
            ClosedYear(year: past, carriedForwardPaise: 0),
          ],
        ),
        ledger: b.ledger,
        viewport: const Size(400, 1400),
      );
      await settleIo(tester);
      await tester.tap(find.byType(ActionChip));
      await settleIo(tester);
      await tester.tap(find.textContaining('2025').last);
      await settleIo(tester);
      // The past year is what S4 now shows — else this proves nothing.
      expect(
        find.descendant(
          of: find.byType(ActionChip),
          matching: find.textContaining('2025'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(OpeningPromptKeys.card), findsOneWidget);
      await tester.tap(find.byKey(OpeningPromptKeys.add));
      await settleIo(tester);
      await tester.enterText(find.byKey(OpeningPromptKeys.amount), '2000');
      await tester.pumpAndSettle();
      // ₹500 lent today (in the running year) + ₹2,000 before: ₹2,500 — not
      // the ₹2,000 the empty past year's closing would give.
      expect(find.text('You will get ₹2,500 in all.'), findsOneWidget);
      await unmountTree(tester);
    });

    testWidgets('F1-1007b-3 the *in all* figure is emphasised as c7 draws it: '
        'semibold, money-in for *get*, money-out for *give*; the words carry '
        'the side', (tester) async {
      final b = await _book(tester);
      await _pumpStatement(tester, b.ledger, b.personId);
      await tester.tap(find.byKey(OpeningPromptKeys.add));
      await settleIo(tester);
      final status = RkStatusColors.of(
        tester.element(find.byKey(OpeningPromptKeys.sheet)),
      );
      TextSpan figureOf(String text) {
        final rich = tester.widget<Text>(find.byKey(OpeningPromptKeys.total));
        return (rich.textSpan! as TextSpan).children!
            .whereType<TextSpan>()
            .singleWhere((t) => t.text == text);
      }

      await tester.enterText(find.byKey(OpeningPromptKeys.amount), '2000');
      await tester.pumpAndSettle();
      final get = figureOf('₹2,500');
      expect(get.style?.color, status.credit);
      expect(get.style?.fontWeight, FontWeight.w600);

      await tester.tap(find.byKey(OpeningPromptKeys.youOwe));
      await tester.pumpAndSettle();
      expect(find.text('You will give ₹1,500 in all.'), findsOneWidget);
      final give = figureOf('₹1,500');
      expect(give.style?.color, status.debit);
      expect(give.style?.fontWeight, FontWeight.w600);
      await unmountTree(tester);
    });

    testWidgets('F1-1007b-3 read-only refuses the opening (ADR 2026-09-24b '
        '§13): the S12.5 sheet rises, nothing is appended, the figure stays', (
      tester,
    ) async {
      final b = await _book(tester);
      await _pumpStatement(
        tester,
        b.ledger,
        b.personId,
        entitlement: lapsedSource(),
      );
      final before = await envelopeCount(tester, b.ledger);
      await tester.tap(find.byKey(OpeningPromptKeys.add));
      await settleIo(tester);
      await tester.enterText(find.byKey(OpeningPromptKeys.amount), '300');
      await tester.tap(find.byKey(OpeningPromptKeys.save));
      await settleIo(tester);

      expectReadOnlySheet(tester);
      expect(await envelopeCount(tester, b.ledger), before);
      await dismissRestrictionSheet(tester);
      expect(find.byKey(OpeningPromptKeys.sheet), findsOneWidget);
      expect(find.widgetWithText(TextField, '300'), findsOneWidget);
      expect(await _openings(tester, b.ledger, b.personId), isEmpty);
      await unmountTree(tester);
    });
  });

  group('the prompt, the marker and the sheet in every language', () {
    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets(
        'F1-1007b-1 fit at 200 % on 360×800 (${locale.languageCode})',
        (tester) async {
          final b = await _book(tester);
          await pumpRk(
            tester,
            _statement(b.personId),
            ledger: b.ledger,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          await settleIo(tester);
          expect(find.byKey(OpeningPromptKeys.card), findsOneWidget);
          expectTextFits(tester, reason: 'S4 prompt, ${locale.languageCode}');
          await tester.ensureVisible(find.byKey(OpeningPromptKeys.add));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(OpeningPromptKeys.add));
          await settleIo(tester);
          expect(find.byKey(OpeningPromptKeys.sheet), findsOneWidget);
          expectTextFits(tester, reason: 'sheet, ${locale.languageCode}');
          await unmountTree(tester);

          await pumpRk(
            tester,
            _index(),
            ledger: b.ledger,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          await settleIo(tester);
          expectTextFits(tester, reason: 'S3 marker, ${locale.languageCode}');
          await unmountTree(tester);
        },
      );
    }
  });
}
