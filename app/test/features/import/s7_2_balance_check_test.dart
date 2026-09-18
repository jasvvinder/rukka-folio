// F1-07-255 … F1-07-258: S7.2 — the import balance check (13 §3.2 row S7.2,
// ADR 2026-09-01 §2 🔒, 07 §11 item 1 🔒 *Balance check*).
//
// Three outcomes, each **stated in words with the numbers**: passing ·
// matched · failing. The figures come from the real parser's own opening and
// closing balances against the seam's ledger balance for those dates — never
// from a stub's opinion of them.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/import/import_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';
import 's7_1_inbox_test.dart' show inboxCsv, sweep;

/// The statement, read by the real parser: opening ₹1,00,000.00, closing
/// ₹2,20,222.28, three lines moving +₹1,20,222.28 net.
ParsedStatement readStatement() => parseStatement(
  bytes: Uint8List.fromList(utf8.encode(inboxCsv)),
  fileName: 'statement.csv',
  accountId: 'bank-1',
) as ParsedStatement;

const openingPaise = 1_00_000_00;
const closingPaise = 2_20_222_28;

AppLocalizations stringsFor(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

Iterable<String> allText(WidgetTester tester) sync* {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final data = w.data;
    if (data != null) yield data;
  }
}

/// The check as S7.1 computes it: the book's balance the day before the
/// statement opens, and on the day it closes.
ImportBalanceCheck checkWith({
  required int? ledgerOpening,
  required int? ledgerClosing,
}) => ImportBalanceCheck.of(
  readStatement(),
  ledgerOpeningPaise: ledgerOpening,
  ledgerClosingPaise: ledgerClosing,
);

Future<void> pumpCheck(
  WidgetTester tester,
  ImportBalanceCheck check, {
  Locale? locale,
  double textScale = 1,
  Size? viewport,
}) async => pumpRk(
  tester,
  ImportBalanceCheckScreen(check: check),
  locale: locale,
  textScale: textScale,
  viewport: viewport ?? rkTallViewport,
);

void main() {
  group('S7.2 balance check', () {
    testWidgets(
      'F1-07-255 passing — “Opening matches your book ✓” and “Closing will '
      'match once these 3 lines are recorded”, with both figures, taken off '
      'the parser’s own running balances in integer paise '
      '(07 §11 item 1 🔒, CLAUDE.md rule 1)',
      (tester) async {
        final check = checkWith(
          ledgerOpening: openingPaise,
          ledgerClosing: openingPaise,
        );
        expect(check.statementOpeningPaise, openingPaise);
        expect(check.statementClosingPaise, closingPaise);
        expect(check.movementPaise, closingPaise - openingPaise);
        expect(check.lineCount, 3);
        expect(check.outcome, ImportBalanceOutcome.passing);
        expect(check.closingWillMatch, isTrue);
        // No float ever touched the arithmetic.
        expect(check.projectedClosingPaise, isA<int>());
        await pumpCheck(tester, check);
        final l = stringsFor(tester);
        expect(find.text(l.importBalanceOpeningMatch), findsOneWidget);
        expect(find.text(l.importBalanceClosingWill(3)), findsOneWidget);
        expect(
          find.text(l.importBalanceOpeningFigures('₹1,00,000', '₹1,00,000')),
          findsOneWidget,
        );
        expect(
          find.text(
            l.importBalanceClosingFigures('₹2,20,222.28', '₹2,20,222.28'),
          ),
          findsOneWidget,
        );
        expect(find.text(l.importBalanceFailing), findsNothing);
      },
    );

    testWidgets(
      'F1-07-256 matched — the book already agrees at both ends, said in '
      'words with the closing figures (ADR 2026-09-01 §2)',
      (tester) async {
        final check = checkWith(
          ledgerOpening: openingPaise,
          ledgerClosing: closingPaise,
        );
        expect(check.outcome, ImportBalanceOutcome.matched);
        await pumpCheck(tester, check);
        final l = stringsFor(tester);
        expect(find.text(l.importBalanceOpeningMatch), findsOneWidget);
        expect(find.text(l.importBalanceMatched), findsOneWidget);
        expect(find.text(l.importBalanceClosingWill(3)), findsNothing);
      },
    );

    testWidgets(
      'F1-07-257 failing — a mismatched opening says an earlier statement is '
      'missing, with the gap, the date and the way on (07 §11 item 1 🔒, '
      '07 §1 rule 6)',
      (tester) async {
        final check = checkWith(
          ledgerOpening: openingPaise - 10_000_00,
          ledgerClosing: openingPaise - 10_000_00,
        );
        expect(check.outcome, ImportBalanceOutcome.failing);
        expect(check.openingGapPaise, 10_000_00);
        await pumpCheck(tester, check);
        final l = stringsFor(tester);
        expect(find.text(l.importBalanceOpeningMismatch), findsOneWidget);
        expect(find.text(l.importBalanceFailing), findsOneWidget);
        expect(
          find.text(l.importBalanceFailingGap('₹10,000', '02 Aug 2026')),
          findsOneWidget,
        );
        // Never a dead end: the way back, and the check never blocks sorting.
        expect(find.text(l.importBalanceFailingNext), findsOneWidget);
        expect(find.byKey(ImportBalanceKeys.back), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-258 S7.2 opens from S7.1’s header, says no Dr and no Cr, and '
      'fits at 130 % and 200 % on 360×800 and 375×667 in EN, ਪੰਜਾਬੀ and '
      'हिन्दी (02 §10 🔒, 07 §1 rules 9 and 11)',
      (tester) async {
        // Reached from the inbox header (13 §3.2: S7.2’s parent is S7).
        final statement = readStatement();
        final source = FakeImportSource()
          ..setBalance(
            'bank-1',
            statement.lines.first.date.addDays(-1),
            openingPaise,
          )
          ..setBalance('bank-1', statement.lines.last.date, openingPaise);
        await pumpRk(
          tester,
          ImportScope(
            source: source,
            filePort: FakeStatementFilePort(),
            bookId: 'book-1',
            child: ImportInboxScreen(statement: statement),
          ),
          viewport: rkTallViewport,
        );
        var l = stringsFor(tester);
        await tester.tap(find.byKey(ImportInboxKeys.balance));
        await tester.pumpAndSettle();
        expect(find.text(l.importBalanceOpeningMatch), findsOneWidget);
        expect(find.text(l.importBalanceClosingWill(3)), findsOneWidget);

        for (final outcome in [
          checkWith(ledgerOpening: openingPaise, ledgerClosing: openingPaise),
          checkWith(ledgerOpening: openingPaise, ledgerClosing: closingPaise),
          checkWith(ledgerOpening: 0, ledgerClosing: 0),
          checkWith(ledgerOpening: null, ledgerClosing: null),
        ]) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              for (final locale in rkLocales) {
                await pumpCheck(
                  tester,
                  outcome,
                  locale: locale,
                  textScale: scale,
                  viewport: size,
                );
                l = stringsFor(tester);
                for (final text in allText(tester)) {
                  expect(
                    RegExp(r'\b(Dr|Cr|debit|credit)\b').hasMatch(text),
                    isFalse,
                    reason: 'professional vocabulary leaked onto S7.2: "$text"',
                  );
                }
                await sweep(
                  tester,
                  reason:
                      'S7.2 ${outcome.outcome.name} '
                      '${size.width.toInt()}×${size.height.toInt()} @$scale '
                      '${locale.languageCode}',
                );
              }
            }
          }
        }
      },
    );
  });
}
