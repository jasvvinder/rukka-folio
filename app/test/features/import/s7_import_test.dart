// F1-07-25 + F1-07-210…213, 218: S7 — Import, pick account & file
// (07 §11 🔒, 02 §10 🔒, 13 §3.2 row S7 and design S7.0a).
//
// The screen is pumped over the feature-local [FakeImportSource], which runs
// the real on-device parser — so a green test here is green against the rule,
// not against a stub's opinion of it. Every fixture is synthetic (CLAUDE.md
// rule 4) and every amount integer paise (rule 1).
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

/// A statement in the common Indian shape: separate withdrawal and deposit
/// columns under the bank's letterhead.
const statementCsv = '''
Test Bank Ltd.
Account: XXXXXX1234

Date,Chq./Ref.No.,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
02/08/2026,,"UPI/DR/425634789012/VERMA DAI/TSTB/vermadairy@oktst/Payment for milk","1,234.50",,"98,765.50"
05/08/2026,000123,SALARY AUG 2026,,"1,23,456.78","2,22,222.28"
09/08/2026,,ATM CASH WDL DELHI,"2,000.00",,"2,20,222.28"
''';

PickedStatementFile fileOf(String csv, {String name = 'statement.csv'}) =>
    PickedStatementFile(
      name: name,
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );

/// The handoff S7 makes when a file reads: what the mapping step receives.
final class Handoff {
  Handoff(this.statement, this.account);
  final ParsedStatement statement;
  final ImportAccount account;
}

Future<Handoff?> pumpS7(
  WidgetTester tester, {
  FakeImportSource? source,
  FakeStatementFilePort? port,
  List<Handoff>? handoffs,
  Locale? locale,
  double textScale = 1,
  Size? viewport,
}) async {
  final out = handoffs ?? <Handoff>[];
  await pumpRk(
    tester,
    ImportScope(
      source: source ?? FakeImportSource(),
      filePort: port ?? FakeStatementFilePort(),
      bookId: 'book-1',
      child: ImportScreen(
        onParsed: (statement, account, bytes) =>
            out.add(Handoff(statement, account)),
      ),
    ),
    locale: locale,
    textScale: textScale,
    viewport: viewport ?? rkTallViewport,
  );
  return out.isEmpty ? null : out.last;
}

AppLocalizations stringsFor(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

/// Scrolls the screen top to bottom, checking at every step that no word is
/// drawn past the edge of its box.
Future<void> sweep(WidgetTester tester, {required String reason}) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 8; i++) {
    expectTextFits(tester, reason: reason);
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expectTextFits(tester, reason: reason);
}

/// Every `Text` in the tree, including the ones inside `RichText` runs.
Iterable<String> allText(WidgetTester tester) sync* {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    if (w.data != null) yield w.data!;
  }
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    yield w.text.toPlainText();
  }
}

void main() {
  group('S7 import — pick account & file', () {
    testWidgets(
      'F1-07-25 pick account → pick file → the read statement goes on to the '
      'mapping step, all on this phone (07 §11 item 1 🔒)',
      (tester) async {
        final source = FakeImportSource();
        final port = FakeStatementFilePort(file: fileOf(statementCsv));
        final handoffs = <Handoff>[];
        await pumpS7(tester, source: source, port: port, handoffs: handoffs);
        final l = stringsFor(tester);

        // Step 1 is the A/C, step 2 the file — the order 07 §11 item 1 🔒
        // states, visible on the screen.
        expect(find.text(l.importStepAccount), findsOneWidget);
        expect(find.text(l.importStepFile), findsOneWidget);
        expect(find.text('SBI Saving'), findsOneWidget);
        expect(find.text('HDFC Current'), findsOneWidget);

        // The second A/C is chosen, then the file.
        await tester.tap(find.text('HDFC Current'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.importFileChoose));
        await tester.pumpAndSettle();

        expect(port.picks, 1);
        expect(handoffs, hasLength(1));
        final handoff = handoffs.single;
        expect(handoff.account.id, 'bank-2');
        // Parsed against the A/C the user picked, into integer paise.
        expect(handoff.statement.accountId, 'bank-2');
        expect(handoff.statement.lines, hasLength(3));
        expect(handoff.statement.lines[1].paise, 12345678);
        expect(handoff.statement.lines[1].direction, BankDirection.moneyIn);
        // `bank_text` came through verbatim (02 §10 🔒).
        expect(
          handoff.statement.lines[0].bankText,
          startsWith('UPI/DR/425634789012/'),
        );
      },
    );

    testWidgets(
      'F1-07-210 the drop zone states exactly what it accepts and where the '
      'file is read (07 §11 item 1 🔒, 04)',
      (tester) async {
        await pumpS7(tester);
        final l = stringsFor(tester);

        expect(find.text('CSV, XLS, OFX or PDF · up to 10 MB'), findsOneWidget);
        expect(find.text(l.importFileAccepts), findsOneWidget);
        expect(find.text(l.importFileOndevice), findsOneWidget);
        expect(find.text(l.importFileToday), findsOneWidget);
        expect(find.text(l.importFileChoose), findsOneWidget);

        // Nothing on this screen speaks about the network: import is
        // on-device, so there is no sync state to report here.
        for (final text in allText(tester)) {
          expect(
            RegExp(
              r'offline|sync|internet|network',
              caseSensitive: false,
            ).hasMatch(text),
            isFalse,
            reason:
                'S7 is on-device; it must say nothing about the '
                'network: "$text"',
          );
        }
      },
    );

    testWidgets(
      'F1-07-211 the 13 §4.3 states: skeleton, error-with-retry, and the '
      'empty book with its one next action',
      (tester) async {
        // Loading — the ruled skeleton, never a spinner (11 §4.5).
        final slow = FakeImportSource(loadDelay: const Duration(seconds: 5));
        await pumpS7(tester, source: slow);
        final l = stringsFor(tester);
        expect(find.bySemanticsLabel(l.importSkeleton), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text('SBI Saving'), findsOneWidget);

        // Error — named, with a retry that works.
        final failing = FakeImportSource(failAccounts: true);
        await pumpS7(tester, source: failing);
        expect(find.text(l.importError), findsOneWidget);
        expect(find.text(l.importRetry), findsOneWidget);
        failing.failAccounts = false;
        await tester.tap(find.text(l.importRetry));
        await tester.pumpAndSettle();
        expect(find.text('SBI Saving'), findsOneWidget);

        // Empty — the friendly line plus the single next action (07 §1
        // rule 12), and no drop zone to press into nothing.
        await pumpS7(tester, source: FakeImportSource(accounts: const []));
        expect(find.text(l.importAccountEmpty), findsOneWidget);
        expect(find.text(l.importAccountEmptyNext), findsOneWidget);
        expect(find.text(l.importFileChoose), findsNothing);
      },
    );

    testWidgets(
      'F1-07-212 the parse-failure state names the cause, lists the formats, '
      'keeps the file on the phone and offers the way on (07 §11 item 4 🔒)',
      (tester) async {
        final port = FakeStatementFilePort(
          file: fileOf('not a statement at all', name: 'notes.csv'),
        );
        await pumpS7(tester, port: port);
        final l = stringsFor(tester);

        await tester.tap(find.text(l.importFileChoose));
        await tester.pumpAndSettle();

        // 07 §11 item 4 🔒 words it exactly this way.
        expect(find.text('Couldn\u2019t read this file'), findsOneWidget);
        expect(find.text(l.importFailTitle), findsOneWidget);
        expect(find.text(l.importFailUnreadable), findsOneWidget);
        expect(find.text(l.importFailFormats), findsOneWidget);
        expect(find.text(l.importFailSupportHelp), findsOneWidget);
        // Never a dead end (07 §1 rule 6).
        expect(find.text(l.importFailAnother), findsOneWidget);

        // A PDF is refused by name, not by silence.
        final pdf = FakeStatementFilePort(
          file: fileOf('%PDF-1.7', name: 'aug.pdf'),
        );
        await pumpS7(tester, port: pdf);
        await tester.tap(find.text(l.importFileChoose));
        await tester.pumpAndSettle();
        expect(find.text(l.importFailNotyet('PDF')), findsOneWidget);

        // Over 10 MB is refused with the limit named back.
        final huge = FakeStatementFilePort(
          file: PickedStatementFile(
            name: 'huge.csv',
            bytes: Uint8List(maxStatementBytes + 1),
          ),
        );
        await pumpS7(tester, port: huge);
        await tester.tap(find.text(l.importFileChoose));
        await tester.pumpAndSettle();
        expect(find.text(l.importFailToobig), findsOneWidget);

        // A cancelled pick is not an error and shows none.
        final cancelled = FakeStatementFilePort();
        await pumpS7(tester, port: cancelled);
        await tester.tap(find.text(l.importFileChoose));
        await tester.pumpAndSettle();
        expect(cancelled.picks, 1);
        expect(find.text(l.importFailTitle), findsNothing);
      },
    );

    testWidgets(
      'F1-07-213 S7 holds at 360×800 and 375×667, 130 % and 200 %, in '
      'EN · ਪੰਜਾਬੀ · हिन्दी — including the failure state',
      (tester) async {
        for (final size in rkPhones) {
          for (final scale in rkTextScales) {
            for (final locale in rkLocales) {
              final where =
                  '${size.width.toInt()} @$scale ${locale.languageCode}';
              await pumpS7(
                tester,
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              await sweep(tester, reason: 'S7 $where');

              final port = FakeStatementFilePort(
                file: fileOf('junk', name: 'junk.csv'),
              );
              await pumpS7(
                tester,
                port: port,
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              final l = stringsFor(tester);
              // At 200 % the drop zone sits below the fold, and a lazy list
              // has not built what is below it — scroll to the action before
              // pressing it.
              await tester.scrollUntilVisible(
                find.text(l.importFileChoose),
                300,
              );
              await tester.ensureVisible(find.text(l.importFileChoose));
              await tester.pumpAndSettle();
              await tester.tap(find.text(l.importFileChoose));
              await tester.pumpAndSettle();
              // The failure state really is the one being swept.
              expect(
                find.text(l.importFailTitle),
                findsOneWidget,
                reason: where,
              );
              await sweep(tester, reason: 'S7 failure $where');
            }
          }
        }
      },
    );

    testWidgets(
      'F1-07-218 bank language throughout: no Dr, no Cr anywhere on S7 '
      '(02 §10 🔒, CLAUDE.md rule 9)',
      (tester) async {
        final port = FakeStatementFilePort(file: fileOf(statementCsv));
        await pumpS7(tester, port: port);
        final l = stringsFor(tester);
        for (final text in allText(tester)) {
          expect(
            RegExp(r'\b(Dr|Cr|debit|credit)\b').hasMatch(text),
            isFalse,
            reason: 'professional vocabulary leaked onto S7: "$text"',
          );
        }
        // And on the failure state, which quotes formats back at the user.
        await tester.tap(find.text(l.importFileChoose));
        await tester.pumpAndSettle();
        for (final text in allText(tester)) {
          expect(
            RegExp(r'\b(Dr|Cr)\b').hasMatch(text),
            isFalse,
            reason: 'professional vocabulary leaked onto S7: "$text"',
          );
        }
      },
    );
  });
}
