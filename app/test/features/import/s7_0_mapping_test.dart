// F1-07-214…217, 219: S7.0b and S7.0c — confirm the columns, then the
// duplicates summary (07 §11 item 1 🔒, 02 §10 🔒, 13 §3.3 design S7.0b–c).
//
// Pumped over the feature-local [FakeImportSource], which runs the real
// on-device parser. Every fixture is synthetic (CLAUDE.md rule 4); every
// amount is integer paise (rule 1).
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/import/import_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

// ---- fixtures ---------------------------------------------------------------

const statementCsv = '''
Test Bank Ltd.
Account: XXXXXX1234

Date,Chq./Ref.No.,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
02/08/2026,,"UPI/DR/425634789012/VERMA DAI/TSTB/vermadairy@oktst/Payment for milk","1,234.50",,"98,765.50"
05/08/2026,000123,SALARY AUG 2026,,"1,23,456.78","2,22,222.28"
09/08/2026,,ATM CASH WDL DELHI,"2,000.00",,"2,20,222.28"
Totals,,,"3,234.50","1,23,456.78",
''';

const sbi = ImportAccount(
  id: 'bank-1',
  name: 'SBI Saving',
  bankKey: 'sbi',
  subtitle: 'Savings',
);

Uint8List bytesOf(String csv) => Uint8List.fromList(utf8.encode(csv));

ParsedStatement statementOf(
  String csv, {
  Set<LineIdentity> already = const {},
}) => parseStatement(
  bytes: bytesOf(csv),
  fileName: 'statement.csv',
  accountId: sbi.id,
  alreadyImported: already,
) as ParsedStatement;

Future<void> pumpMapping(
  WidgetTester tester, {
  required ParsedStatement statement,
  String csv = statementCsv,
  FakeImportSource? source,
  List<ParsedStatement>? continued,
  VoidCallback? onAnotherFile,
  Locale? locale,
  double textScale = 1,
  Size? viewport,
}) => pumpRk(
  tester,
  ImportScope(
    source: source ?? FakeImportSource(),
    filePort: FakeStatementFilePort(),
    bookId: 'book-1',
    child: ImportMappingScreen(
      // A fresh key per pump: Flutter would otherwise reuse the previous
      // screen's State, and a test that pumps twice would open on the phase
      // the last one ended in.
      key: UniqueKey(),
      statement: statement,
      account: sbi,
      bytes: bytesOf(csv),
      onContinue: (s) => continued?.add(s),
      onAnotherFile: onAnotherFile,
    ),
  ),
  locale: locale,
  textScale: textScale,
  viewport: viewport ?? rkTallViewport,
);

AppLocalizations stringsFor(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

Iterable<String> allText(WidgetTester tester) sync* {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    if (w.data != null) yield w.data!;
  }
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    yield w.text.toPlainText();
  }
}

Future<void> sweep(WidgetTester tester, {required String reason}) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 10; i++) {
    expectTextFits(tester, reason: reason);
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expectTextFits(tester, reason: reason);
}

/// Confirms the mapping, scrolling the button into the viewport first.
///
/// `ensureVisible` alone is not enough at 200 %: it brings the button to the
/// edge of the viewport, where its centre can still sit outside the screen and
/// the tap lands on nothing. This drags until the button is genuinely on
/// screen, which is also what a user has to do.
Future<void> confirm(WidgetTester tester, AppLocalizations l) async {
  final scrollable = find.byType(Scrollable).first;
  final button = find.text(l.importMapConfirm);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var i = 0; i < 20; i++) {
    if (tester.any(button)) {
      final centre = tester.getRect(button).center;
      if (centre.dy > 0 && centre.dy < screen.height - 8) break;
    }
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('S7.0b — check the columns', () {
    testWidgets(
      'F1-07-214 the auto-detected columns are shown for confirmation with a '
      'sample row in bank words — Money in / Money out, never Dr/Cr '
      '(07 §11 item 1 🔒, 02 §10 🔒)',
      (tester) async {
        await pumpMapping(tester, statement: statementOf(statementCsv));
        final l = stringsFor(tester);

        // Every role is named in the user's words…
        // The file's own header for the date column is the word *Date* too,
        // so the label and the quoted header both match.
        expect(find.text(l.importMapColDate), findsWidgets);
        expect(find.text(l.importMapColText), findsOneWidget);
        expect(find.text(l.importMapColMoneyOut), findsOneWidget);
        expect(find.text(l.importMapColMoneyIn), findsOneWidget);
        expect(find.text(l.importMapColBalance), findsOneWidget);

        // …and the bank's own headers are quoted as data, in the controls.
        expect(find.text('Withdrawal Amt.'), findsWidgets);
        expect(find.text('Deposit Amt.'), findsWidgets);

        // The sample row: the bank's line verbatim, the amount with its
        // direction in consumer words.
        expect(find.text(l.importMapSample), findsOneWidget);
        expect(
          find.text(
            'UPI/DR/425634789012/VERMA DAI/TSTB/vermadairy@oktst/'
            'Payment for milk',
          ),
          findsOneWidget,
        );
        expect(
          find.text('−₹1,234 Money out', findRichText: true),
          findsOneWidget,
        );

        // 02 §10 🔒 / CLAUDE.md rule 9: a consumer surface. The bank's own
        // column header is data and may say anything; nothing the *app*
        // writes may say Dr or Cr.
        for (final w in tester.widgetList<Text>(find.byType(Text))) {
          final text = w.data ?? '';
          if (statementCsv.contains(text)) continue; // the file's own words
          expect(
            RegExp(r'\b(Dr|Cr)\b').hasMatch(text),
            isFalse,
            reason: 'professional vocabulary leaked onto S7.0b: "$text"',
          );
        }
      },
    );

    testWidgets(
      'F1-07-215 a correction re-reads the file on this phone, and confirming '
      'remembers the mapping per bank (07 §11 item 1 🔒)',
      (tester) async {
        final source = FakeImportSource();
        await pumpMapping(
          tester,
          statement: statementOf(statementCsv),
          source: source,
        );
        final l = stringsFor(tester);

        // A correction: the *bank's own words* column is pointed at the
        // reference column instead. The sample row re-reads at once — from
        // the bytes already in memory, never by asking for the file again.
        await tester.tap(find.byKey(const ValueKey('description:2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chq./Ref.No.').last);
        await tester.pumpAndSettle();
        // The sample re-reads from the bytes already in memory: the bank's
        // narration is gone from it, and the amount is unchanged.
        expect(
          find.text(
            'UPI/DR/425634789012/VERMA DAI/TSTB/vermadairy@oktst/'
            'Payment for milk',
          ),
          findsNothing,
        );
        expect(
          find.text('−₹1,234 Money out', findRichText: true),
          findsOneWidget,
        );

        await confirm(tester, l);

        // Remembered against the **bank**, not the A/C, and marked confirmed
        // so the next statement needs no checking.
        expect(source.rememberedCalls, hasLength(1));
        final (bankKey, mapping) = source.rememberedCalls.single;
        expect(bankKey, 'sbi');
        expect(mapping.confidence, MappingConfidence.confirmed);
        expect(mapping.description, 1);
        expect(await source.rememberedMapping('sbi'), mapping);
        expect(await source.rememberedMapping('hdfc'), isNull);
      },
    );
  });

  group('S7.0c — duplicates skipped', () {
    testWidgets(
      'F1-07-216 duplicates are removed before anything is shown and the '
      'count is stated up front (07 §11 item 1 🔒)',
      (tester) async {
        // Two of the three lines are already in the book.
        final first = statementOf(statementCsv);
        final already = {
          identityOf(first.lines[0], accountId: sbi.id),
          identityOf(first.lines[1], accountId: sbi.id),
        };
        final source = FakeImportSource(alreadyImported: already);
        await pumpMapping(
          tester,
          statement: statementOf(statementCsv, already: already),
          source: source,
        );
        final l = stringsFor(tester);
        await confirm(tester, l);

        expect(find.text('2 lines already imported — skipped'), findsOneWidget);
        expect(find.text(l.importDupesSkipped(2)), findsOneWidget);
        expect(find.text(l.importDupesReady(1)), findsOneWidget);
        // The bank's own `Totals` row is stated, not silently dropped.
        expect(find.text(l.importDupesIgnored(1)), findsOneWidget);
        // Nothing has posted; the lines are waiting (02 §10 🔒).
        expect(find.text(l.importDupesNotposted), findsOneWidget);

        // The zero-duplicate case says so rather than leaving a blank.
        await pumpMapping(tester, statement: statementOf(statementCsv));
        await confirm(tester, l);
        expect(find.text(l.importDupesNone), findsOneWidget);
        expect(find.text(l.importDupesReady(3)), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-217 the door onward to the import inbox, and no dead end when '
      'every line is a duplicate (07 §1 rule 6)',
      (tester) async {
        final continued = <ParsedStatement>[];
        await pumpMapping(
          tester,
          statement: statementOf(statementCsv),
          continued: continued,
        );
        final l = stringsFor(tester);
        await confirm(tester, l);

        // Back returns to the columns — the step is never one-way.
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.text(l.importMapTitle), findsOneWidget);
        await confirm(tester, l);

        await tester.tap(find.text(l.importDupesContinue));
        await tester.pumpAndSettle();
        expect(continued, hasLength(1));
        expect(continued.single.lines, hasLength(3));

        // Every line already imported: not a failure, and still a way on.
        final first = statementOf(statementCsv);
        final already = {
          for (final line in first.lines) identityOf(line, accountId: sbi.id),
        };
        var another = 0;
        await pumpMapping(
          tester,
          statement: statementOf(statementCsv, already: already),
          source: FakeImportSource(alreadyImported: already),
          onAnotherFile: () => another++,
        );
        await confirm(tester, l);
        expect(find.text(l.importDupesNothing), findsOneWidget);
        expect(find.text(l.importDupesContinue), findsNothing);
        await tester.tap(find.text(l.importFailAnother));
        await tester.pumpAndSettle();
        expect(another, 1);
      },
    );

    testWidgets(
      'F1-07-219 S7.0b and S7.0c hold at 360×800 and 375×667, 130 % and '
      '200 %, in EN · ਪੰਜਾਬੀ · हिन्दी',
      (tester) async {
        for (final size in rkPhones) {
          for (final scale in rkTextScales) {
            for (final locale in rkLocales) {
              final where =
                  '${size.width.toInt()} @$scale ${locale.languageCode}';
              await pumpMapping(
                tester,
                statement: statementOf(statementCsv),
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              await sweep(tester, reason: 'S7.0b $where');

              final l = stringsFor(tester);
              await confirm(tester, l);
              expect(
                find.text(l.importDupesNone),
                findsOneWidget,
                reason: where,
              );
              await sweep(tester, reason: 'S7.0c $where');
            }
          }
        }
      },
    );
  });
}
