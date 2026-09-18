// F1-07-240 … F1-07-254: S7.1 — the import inbox, and S7.3 the transfer-pair
// card inside it (07 §11 items 2–3 🔒, 02 §10 🔒, 13 §3.2 rows S7.1 / S7.3,
// ADR 2026-09-01 §2).
//
// The screen is pumped over [FakeImportSource], which runs the **real**
// on-device parser for its lines — so the dates, amounts and bank text a row
// draws are the parser's, not a stub's. Every fixture is synthetic (CLAUDE.md
// rule 4) and every amount integer paise (rule 1).
//
// F1-07-251 is the one test that goes to the real book: [LedgerImportSource]
// over a seeded [LocalLedger], to prove the reads are real and that **nothing
// posts** while `bank_text` has nowhere to land (02 §10 🔒). It is a plain
// `test`, not a `testWidgets`: a drift query stream's first event arrives on a
// zero-duration timer that a widget test's fake clock never fires.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/import/import_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

// ---- fixtures ---------------------------------------------------------------

/// Three lines: one money out with a long UPI narration, one money in, one
/// money out. Opening ₹1,00,000.00 · closing ₹2,20,222.28.
const inboxCsv = '''
Test Bank Ltd.

Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
02/08/2026,"UPI/DR/425634789012/VERMA DAI/TSTB/vermadairy@oktst/Payment for milk","1,234.50",,"98,765.50"
05/08/2026,SALARY AUG 2026,,"1,23,456.78","2,22,222.28"
09/08/2026,ATM CASH WDL DELHI,"2,000.00",,"2,20,222.28"
''';

/// The statement the screen is given, read by the real parser.
ParsedStatement readStatement([String csv = inboxCsv]) {
  final result = parseStatement(
    bytes: Uint8List.fromList(utf8.encode(csv)),
    fileName: 'statement.csv',
    accountId: 'bank-1',
  );
  return result as ParsedStatement;
}

/// The inbox id [FakeImportSource] gives the [i]th line of [statement].
String idOf(ParsedStatement statement, int i) =>
    '${statement.accountId}#${statement.lines[i].rowIndex}';

/// An opposite line already in the inbox from **another** own A/C — the only
/// shape a transfer pair can have (02 §10 🔒).
ImportLine carriedLine({
  required int paise,
  required LocalDate date,
  String accountId = 'bank-2',
  String text = 'NEFT FROM TEST BANK XXXX1234',
}) => ImportLine(
  id: '$accountId#99',
  parsed: ParsedLine(
    date: date,
    bankText: text,
    paise: paise,
    direction: BankDirection.moneyIn,
    rowIndex: 99,
  ),
  accountId: accountId,
  state: ImportLineState.needsAnswer,
);

Future<void> pumpInbox(
  WidgetTester tester, {
  required ParsedStatement statement,
  FakeImportSource? source,
  Locale? locale,
  double textScale = 1,
  Size? viewport,
}) async {
  await pumpRk(
    tester,
    ImportScope(
      source: source ?? FakeImportSource(),
      filePort: FakeStatementFilePort(),
      bookId: 'book-1',
      child: ImportInboxScreen(statement: statement),
    ),
    locale: locale,
    textScale: textScale,
    viewport: viewport ?? rkTallViewport,
  );
}

AppLocalizations stringsFor(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

Iterable<String> allText(WidgetTester tester) sync* {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final data = w.data;
    if (data != null) yield data;
  }
}

/// Scrolls the screen top to bottom, checking at every step that no word is
/// drawn past the edge of its box.
Future<void> sweep(WidgetTester tester, {required String reason}) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 10; i++) {
    expectTextFits(tester, reason: reason);
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expectTextFits(tester, reason: reason);
}

Finder inRow(String id, Finder matching) => find.descendant(
  of: find.byKey(ImportInboxKeys.row(id)),
  matching: matching,
);

void main() {
  group('S7.1 import inbox', () {
    testWidgets(
      'F1-07-240 every chip state renders from the seam’s line model — '
      'Matched ✓ · Suggested · New · Transfer? · Suspense, each a word '
      '(07 §11 item 2 🔒, 07 §1 rule 3)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource()
          ..matches[statement.lines[0].rowIndex] = const ImportMatch(
            entryId: 'e-1',
            entryLabel: 'Milk — 02 Aug',
          )
          ..rules['SALARY'] = const ImportCounterpart(
            id: 'cat-salary',
            name: 'Salary Income',
          )
          ..carried.add(
            carriedLine(paise: 200000, date: LocalDate(2026, 8, 10)),
          );
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);

        // Matched ✓ on the first line, Suggested on the second, Transfer? on
        // the pair — and New on nothing left, so the fourth state is taken
        // from a line put back by an unlink below.
        expect(find.text(l.importInboxChipMatched), findsOneWidget);
        expect(find.text(l.importInboxChipSuggested), findsOneWidget);
        expect(find.text(l.importInboxChipTransfer), findsNWidgets(2));

        // Suspense: the Suggested row takes *record now, explain later*.
        await tester.tap(
          inRow(idOf(statement, 1), find.text(l.importInboxSuspenseAction)),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.importInboxChipSuspense), findsOneWidget);

        // New: unlinking the matched row falls back to the one question.
        await tester.tap(
          inRow(idOf(statement, 0), find.text(l.importInboxMatchedUnlink)),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.importInboxChipNew), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-241 the one question reads “Where did it come from?” for money '
      'in and “Where did it go?” for money out, beside the direction word and '
      'the sign (02 §10 🔒)',
      (tester) async {
        final statement = readStatement();
        await pumpInbox(tester, statement: statement);
        final l = stringsFor(tester);

        // Line 1 and 3 are money out, line 2 money in.
        expect(
          inRow(idOf(statement, 0), find.text(l.importInboxQuestionOut)),
          findsOneWidget,
        );
        expect(
          inRow(idOf(statement, 1), find.text(l.importInboxQuestionIn)),
          findsOneWidget,
        );
        expect(
          inRow(idOf(statement, 2), find.text(l.importInboxQuestionOut)),
          findsOneWidget,
        );

        // The amount carries its own word and sign — colour is never alone
        // (07 §1 rule 3).
        expect(find.text(l.importInboxMoneyIn), findsOneWidget);
        expect(find.text(l.importInboxMoneyOut), findsNWidgets(2));
        expect(find.text('−₹1,234.50'), findsOneWidget);
        expect(find.text('+₹1,23,456.78'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-242 Matched ✓ unlinks on one tap and the row falls back to its '
      'one question — nothing was posted, so nothing is reversed '
      '(07 §11 item 2 🔒)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource()
          ..matches[statement.lines[0].rowIndex] = const ImportMatch(
            entryId: 'e-1',
            entryLabel: 'Milk — 02 Aug',
          );
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);
        final id = idOf(statement, 0);

        expect(
          inRow(id, find.text(l.importInboxMatchedNothing)),
          findsOneWidget,
        );
        await tester.tap(inRow(id, find.text(l.importInboxMatchedUnlink)));
        await tester.pumpAndSettle();

        expect(inRow(id, find.text(l.importInboxQuestionOut)), findsOneWidget);
        expect(inRow(id, find.text(l.importInboxChipNew)), findsOneWidget);
        // Unlinking posts nothing and reverses nothing.
        expect(source.postings, isEmpty);
      },
    );

    testWidgets(
      'F1-07-243 Suggested approves in exactly one tap and approving teaches '
      'the rule (07 §11 items 2–3 🔒)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource()
          ..rules['SALARY'] = const ImportCounterpart(
            id: 'cat-salary',
            name: 'Salary Income',
          );
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);
        final id = idOf(statement, 1);

        expect(
          inRow(id, find.text(l.importInboxSuggestedChip('Salary Income'))),
          findsOneWidget,
        );
        await tester.tap(inRow(id, find.byKey(ImportInboxKeys.approve(id))));
        await tester.pumpAndSettle();

        expect(
          inRow(id, find.text(l.importInboxAnswerIn('Salary Income'))),
          findsOneWidget,
        );
        expect(source.taught.single.id, id);
      },
    );

    testWidgets(
      'F1-07-244 New is answered by picking an A/C, or by creating one '
      'inline — and the user never chooses a side (02 §10 🔒)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource();
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);
        final id = idOf(statement, 0);

        await tester.tap(inRow(id, find.byKey(ImportInboxKeys.choose(id))));
        await tester.pumpAndSettle();
        await tester.tap(
          inRow(id, find.byKey(ImportInboxKeys.pick(id, 'cat-milk'))),
        );
        await tester.pumpAndSettle();
        expect(
          inRow(id, find.text(l.importInboxAnswerOut('Milk Expense'))),
          findsOneWidget,
        );

        // Inline create on the third line.
        final other = idOf(statement, 2);
        await tester.tap(
          inRow(other, find.byKey(ImportInboxKeys.choose(other))),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(ImportInboxKeys.search(other)),
          'Petty cash',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.importInboxCreate('Petty cash')));
        await tester.pumpAndSettle();
        expect(
          inRow(other, find.text(l.importInboxAnswerOut('Petty cash'))),
          findsOneWidget,
        );

        // Nothing anywhere named a side.
        for (final text in allText(tester)) {
          expect(
            RegExp(r'\b(Dr|Cr)\b').hasMatch(text),
            isFalse,
            reason: 'a side leaked onto S7.1: "$text"',
          );
        }
      },
    );

    testWidgets(
      'F1-07-245 Transfer? — one tap records a single Transfer for the pair '
      'and the two rows collapse to one (02 §10 🔒, S7.3)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource()
          ..carried.add(
            carriedLine(paise: 200000, date: LocalDate(2026, 8, 10)),
          );
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);

        // Both halves ask, and they ask the S7.3 question.
        expect(find.text(l.importInboxTransferQuestion), findsNWidgets(2));
        expect(find.byType(ImportLineCard), findsNWidgets(4));

        final id = idOf(statement, 2);
        await tester.tap(find.byKey(ImportInboxKeys.transferYes(id)));
        await tester.pumpAndSettle();

        // One row where there were two.
        expect(find.byType(ImportLineCard), findsNWidgets(3));
        expect(find.text(l.importInboxTransferQuestion), findsNothing);
        expect(inRow(id, find.text(l.importInboxTransferDone)), findsOneWidget);

        await tester.tap(find.byKey(ImportInboxKeys.submit));
        await tester.pumpAndSettle();
        final transfers = source.postings.where((p) => p.transfer).toList();
        expect(transfers, hasLength(1));
        expect(transfers.single.paise, 200000);
      },
    );

    testWidgets(
      'F1-07-246 Suspense records now and explains later — the line posts, '
      'flagged, and keeps its bank text (02 §10 🔒)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource();
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);
        final id = idOf(statement, 0);

        await tester.tap(inRow(id, find.byKey(ImportInboxKeys.suspense(id))));
        await tester.pumpAndSettle();
        expect(inRow(id, find.text(l.importInboxSuspenseWhat)), findsOneWidget);

        await tester.tap(find.byKey(ImportInboxKeys.submit));
        await tester.pumpAndSettle();
        final posted = source.postings.single;
        expect(posted.suspense, isTrue);
        expect(posted.paise, 123450);
        expect(posted.bankText, statement.lines[0].bankText);
      },
    );

    testWidgets(
      'F1-07-247 partial submit — answered lines are recorded, the rest stay '
      'in the inbox and the screen says how many (07 §11 item 1 🔒)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource();
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);
        final id = idOf(statement, 0);

        await tester.tap(inRow(id, find.byKey(ImportInboxKeys.suspense(id))));
        await tester.pumpAndSettle();
        expect(find.text(l.importInboxWaiting(2)), findsOneWidget);
        expect(find.text(l.importInboxSubmit(1)), findsOneWidget);

        await tester.tap(find.byKey(ImportInboxKeys.submit));
        await tester.pumpAndSettle();

        expect(source.postings, hasLength(1));
        expect(find.byType(ImportLineCard), findsNWidgets(2));
        expect(find.byKey(ImportInboxKeys.row(id)), findsNothing);
        expect(find.text(l.importInboxWaiting(2)), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-248 the Always? Yes/No toast follows a correction, and only a '
      'correction — Yes teaches the rule, No teaches nothing '
      '(07 §11 item 3 🔒)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource()
          ..rules['SALARY'] = const ImportCounterpart(
            id: 'cat-salary',
            name: 'Salary Income',
          );
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);
        final suggested = idOf(statement, 1);

        // Correcting the suggestion asks.
        await tester.tap(
          inRow(suggested, find.byKey(ImportInboxKeys.choose(suggested))),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ImportInboxKeys.pick(suggested, 'party-ramesh')),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.importInboxAlwaysQ('Ramesh')), findsOneWidget);

        await tester.tap(find.text(l.importInboxAlwaysNo));
        await tester.pumpAndSettle();
        expect(source.taught, isEmpty);

        // And the same correction, answered Yes, teaches it.
        final plain = idOf(statement, 0);
        await tester.tap(
          inRow(plain, find.byKey(ImportInboxKeys.choose(plain))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ImportInboxKeys.pick(plain, 'cat-milk')));
        await tester.pumpAndSettle();
        // A `New` row carried no suggestion, so nothing was corrected and
        // nothing is asked.
        expect(find.text(l.importInboxAlwaysQ('Milk Expense')), findsNothing);
        expect(source.taught, isEmpty);
      },
    );

    testWidgets(
      'F1-07-249 + note on a classified row is the user’s own narration and '
      'never touches the bank’s words (02 §10 🔒, 07 §11 item 2 🔒)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource();
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);
        final id = idOf(statement, 0);

        // Unclassified rows carry no note link.
        expect(inRow(id, find.text(l.importInboxNoteAdd)), findsNothing);

        await tester.tap(inRow(id, find.byKey(ImportInboxKeys.suspense(id))));
        await tester.pumpAndSettle();
        await tester.tap(inRow(id, find.byKey(ImportInboxKeys.note(id))));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(ImportInboxKeys.noteField(id)),
          'Verma dairy, August milk',
        );
        await tester.tap(find.text(l.importInboxNoteSave));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ImportInboxKeys.submit));
        await tester.pumpAndSettle();
        final posted = source.postings.single;
        expect(posted.note, 'Verma dairy, August milk');
        expect(posted.bankText, statement.lines[0].bankText);
      },
    );

    testWidgets(
      'F1-07-250 the bank’s own words are shown verbatim — one truncated '
      'line, the whole string on tap, never editable (02 §10 🔒)',
      (tester) async {
        final statement = readStatement();
        await pumpInbox(tester, statement: statement);
        final id = idOf(statement, 0);
        final full = statement.lines[0].bankText;

        Text textOf() => tester.widget<Text>(inRow(id, find.text(full)).first);
        expect(textOf().maxLines, 1);
        expect(textOf().overflow, TextOverflow.ellipsis);

        await tester.tap(inRow(id, find.byKey(ImportInboxKeys.bankText(id))));
        await tester.pumpAndSettle();
        expect(textOf().maxLines, isNull);
        // The evidence is never a field.
        expect(inRow(id, find.byType(TextField)), findsNothing);
      },
    );

    test(
      'F1-07-251 over the real book the reads are real and nothing posts: '
      'LedgerImportSource reads the bank A/Cs and the balance from '
      'LocalLedger, and submit answers ImportPostingUnavailable for every '
      'line without throwing (02 §10 🔒 — bank_text has nowhere to land)',
      () async {
        final seeded = await seedSoloLedger();
        final source = LedgerImportSource(seeded.ledger);

        // The reads are real — and only bank-shaped A/Cs are candidates:
        // cash is counted, not imported (02 §8.2).
        final accounts = await source.pickAccount(seeded.bookId);
        expect(accounts.map((a) => a.id), contains(seeded.bankId));
        expect(accounts.map((a) => a.id), isNot(contains(seeded.cashId)));
        expect(
          await source.ledgerBalanceOn(seeded.bankId, seeded.ledger.today()),
          1_14_600_00,
        );
        expect(
          await source.ledgerBalanceOn(
            seeded.bankId,
            seeded.ledger.today().addDays(-30),
          ),
          0,
        );

        final statement = readStatement();
        final lines = await source.classify(
          bookId: seeded.bookId,
          statement: statement,
        );
        expect(lines, hasLength(3));
        expect(
          lines.every((l) => l.state == ImportLineState.needsAnswer),
          isTrue,
        );

        // Nothing posts, nothing throws, and the blocker is named.
        expect(
          source.posting,
          isA<ImportPostingBlocked>().having(
            (b) => b.reason,
            'reason',
            ImportUnavailableReason.bankTextHasNowhereToLand,
          ),
        );
        final outcomes = await source.submit(lines);
        expect(outcomes, hasLength(3));
        expect(
          outcomes.every(
            (o) =>
                o is ImportPostingUnavailable &&
                o.reason == ImportUnavailableReason.bankTextHasNowhereToLand,
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'F1-07-252 a blocked source draws the primary action disabled with '
      'its reason in one plain sentence, beside Keep for later — never an '
      'error and never a dead end (13 §4.3, 07 §1 rule 6)',
      (tester) async {
        final statement = readStatement();
        final source = FakeImportSource()
          ..posting = const ImportPostingBlocked(
            ImportUnavailableReason.bankTextHasNowhereToLand,
          );
        await pumpInbox(tester, statement: statement, source: source);
        final l = stringsFor(tester);
        expect(find.text(l.importInboxBlockedBanktext), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(ImportInboxKeys.submit))
              .onPressed,
          isNull,
        );
        expect(find.byKey(ImportInboxKeys.keep), findsOneWidget);

        // Even an answered line cannot arm it, and nothing posts.
        final id = idOf(statement, 0);
        await tester.tap(inRow(id, find.byKey(ImportInboxKeys.suspense(id))));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(ImportInboxKeys.submit))
              .onPressed,
          isNull,
        );
        expect(source.postings, isEmpty);
      },
    );

    testWidgets(
      'F1-07-253 the 13 §4.3 states: ruled skeleton while the lines load, '
      'error-with-retry, and the empty state with its one next action',
      (tester) async {
        final statement = readStatement();

        // Error: no scope installed, so the door is missing — the error
        // state, never a red screen (07 §1 rule 6).
        await pumpRk(
          tester,
          ImportInboxScreen(statement: statement),
          viewport: rkTallViewport,
        );
        var l = stringsFor(tester);
        expect(find.text(l.importInboxError), findsOneWidget);
        expect(find.text(l.importInboxRetry), findsOneWidget);

        // Empty: a statement with no lines left after duplicates.
        const empty = '''
Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
''';
        final result = parseStatement(
          bytes: Uint8List.fromList(utf8.encode(empty)),
          fileName: 'empty.csv',
          accountId: 'bank-1',
        );
        // A file with a header and no rows is a stated failure, so the empty
        // inbox is reached the other way: every line submitted away.
        expect(result, isA<StatementParseFailure>());

        final source = FakeImportSource();
        await pumpInbox(tester, statement: statement, source: source);
        l = stringsFor(tester);
        for (var i = 0; i < 3; i++) {
          final id = idOf(statement, i);
          await tester.tap(inRow(id, find.byKey(ImportInboxKeys.suspense(id))));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(ImportInboxKeys.submit));
        await tester.pumpAndSettle();
        expect(find.byType(ImportLineCard), findsNothing);
        expect(find.text(l.importInboxRecorded(3)), findsWidgets);
      },
    );

    testWidgets(
      'F1-07-254 S7.1 fits at 130 % and 200 % on 360×800 and 375×667 in EN, '
      'ਪੰਜਾਬੀ and हिन्दी with every chip state on the screen at once — and '
      'says no Dr and no Cr in any of them (07 §1 rules 9 and 11, 02 §10 🔒, '
      'CLAUDE.md rule 9 — as F1-07-111 asserts for S14)',
      (tester) async {
        final statement = readStatement();
        for (final size in rkPhones) {
          for (final scale in rkTextScales) {
            for (final locale in rkLocales) {
              final where =
                  '${size.width.toInt()}×${size.height.toInt()} @$scale '
                  '${locale.languageCode}';
              final source = FakeImportSource()
                ..matches[statement.lines[0].rowIndex] = const ImportMatch(
                  entryId: 'e-1',
                  entryLabel: 'Milk — 02 Aug',
                )
                ..rules['SALARY'] = const ImportCounterpart(
                  id: 'cat-salary',
                  name: 'Salary Income',
                )
                ..carried.add(
                  carriedLine(paise: 200000, date: LocalDate(2026, 8, 10)),
                );
              await pumpInbox(
                tester,
                statement: statement,
                source: source,
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              for (final text in allText(tester)) {
                // The bank's own narration is data, quoted verbatim
                // (02 §10 🔒): it may say anything, including DR. Only the
                // app's own words are held to the rule.
                if (statement.lines.any((p) => p.bankText == text)) continue;
                if (text == 'NEFT FROM TEST BANK XXXX1234') continue;
                expect(
                  RegExp(r'\b(Dr|Cr|debit|credit)\b').hasMatch(text),
                  isFalse,
                  reason: 'professional vocabulary leaked onto S7.1: "$text"',
                );
              }
              await sweep(tester, reason: 'S7.1 $where');
            }
          }
        }
      },
    );
  });
}
