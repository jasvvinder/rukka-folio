// F1-07-200…209 — the on-device statement parser (07 §11 item 1 🔒, 02 §10 🔒).
//
// The parser is pure Dart, so this file pumps no widget: bytes in, value out.
// Every fixture below is synthetic (CLAUDE.md rule 4) — no real narration, no
// real account number, no real amount.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/import/parse/column_mapping.dart';
import 'package:rukka_folio/features/import/parse/field_parse.dart';
import 'package:rukka_folio/features/import/parse/parsed_statement.dart';
import 'package:rukka_folio/features/import/parse/statement_parser.dart';

Uint8List bytesOf(String csv) => Uint8List.fromList(utf8.encode(csv));

/// Shape 1 — separate withdrawal and deposit columns, under a letterhead
/// block, the common Indian bank export.
const splitColumnsCsv = '''
Test Bank Ltd.
Account: XXXXXX1234
Statement period: 01/08/2026 to 31/08/2026

Date,Chq./Ref.No.,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
02/08/2026,,"UPI/DR/425634789012/VERMA DAI/TSTB/vermadairy@oktst/Payment for milk","1,234.50",,"98,765.50"
05/08/2026,000123,SALARY AUG 2026,,"1,23,456.78","2,22,222.28"
09/08/2026,,ATM CASH WDL  DELHI,"2,000.00",,"2,20,222.28"
*** End of statement ***
''';

/// Shape 2 — one signed amount column.
const signedAmountCsv = '''
Txn Date,Description,Amount,Balance
2026-08-02,POS PURCHASE STORE,-1234.50,98765.50
2026-08-05,NEFT INWARD,123456.78,222222.28
''';

/// Shape 3 — one amount column with a Dr/Cr marker column.
const drCrMarkerCsv = '''
Date,Particulars,Amount,Dr/Cr,Balance
02-Aug-2026,CHEQUE PAID,"1,234.50",Dr,"98,765.50"
05-Aug-2026,INTEREST CREDITED,"1,23,456.78",Cr,"2,22,222.28"
''';

void main() {
  group('statement parser', () {
    test(
      'F1-07-200 separate withdrawal and deposit columns: header found under '
      'the letterhead, bank credit = money in (02 §10 🔒)',
      () {
        final r = parseStatement(
          bytes: bytesOf(splitColumnsCsv),
          fileName: 'statement.csv',
          accountId: 'bank-1',
        );
        final s = r as ParsedStatement;

        // The header sits on row 4; the rows above it are the bank's own
        // letterhead and are not lines.
        expect(s.mapping.headerRow, 4);
        expect(s.mapping.date, 0);
        expect(s.mapping.description, 2);
        expect(s.mapping.moneyOut, 3);
        expect(s.mapping.moneyIn, 4);
        expect(s.mapping.balance, 5);
        expect(s.mapping.amount, isNull);
        expect(s.mapping.confidence, MappingConfidence.detected);

        expect(s.lines.length, 3);
        // A deposit is the bank's credit — and the user's Money in.
        expect(s.lines[1].direction, BankDirection.moneyIn);
        expect(s.lines[1].paise, 12345678);
        // A withdrawal is Money out. The magnitude is positive; the side is
        // the direction's to carry, never a sign on the number.
        expect(s.lines[0].direction, BankDirection.moneyOut);
        expect(s.lines[0].paise, 123450);
        expect(s.lines[2].direction, BankDirection.moneyOut);
        expect(s.lines[2].paise, 200000);

        // The running balance is read where the file has the column.
        expect(s.lines[0].balancePaise, 9876550);
        expect(s.lines[1].balancePaise, 22222228);

        // `*** End of statement ***` is counted, not crashed on.
        expect(s.unreadableRows, 1);
        expect(s.headers[3], 'Withdrawal Amt.');
      },
    );

    test('F1-07-201 one signed amount column: the sign decides the direction, '
        'the amount stays a magnitude', () {
      final s = parseStatement(
        bytes: bytesOf(signedAmountCsv),
        fileName: 'txns.csv',
        accountId: 'bank-1',
      ) as ParsedStatement;

      expect(s.mapping.hasSplitColumns, isFalse);
      expect(s.mapping.amount, 2);
      expect(s.mapping.balance, 3);
      expect(s.lines.length, 2);
      expect(s.lines[0].direction, BankDirection.moneyOut);
      expect(s.lines[0].paise, 123450);
      expect(s.lines[1].direction, BankDirection.moneyIn);
      expect(s.lines[1].paise, 12345678);
      expect(s.lines[0].date, LocalDate(2026, 8, 2));
    });

    test(
      'F1-07-202 a Dr/Cr marker column: Cr is money in, Dr is money out — the '
      'bank keeps its own book (02 §10 🔒)',
      () {
        final s = parseStatement(
          bytes: bytesOf(drCrMarkerCsv),
          fileName: 'txns.csv',
          accountId: 'bank-1',
        ) as ParsedStatement;

        expect(s.mapping.direction, 3);
        expect(s.mapping.amount, 2);
        expect(s.lines[0].direction, BankDirection.moneyOut);
        expect(s.lines[1].direction, BankDirection.moneyIn);
        expect(s.lines[1].paise, 12345678);
        expect(s.lines[0].date, LocalDate(2026, 8, 2));
      },
    );

    test('F1-07-203 Indian grouped amounts become integer paise, exactly — no '
        'float ever touches the money path (CLAUDE.md rule 1)', () {
      expect(parseAmountPaise('1,23,456.78'), 12345678);
      expect(parseAmountPaise('₹ 1,23,456.78'), 12345678);
      expect(parseAmountPaise('123,456.78'), 12345678);
      expect(parseAmountPaise('1,23,456'), 12345600);
      expect(parseAmountPaise('0.07'), 7);
      expect(parseAmountPaise('8.20'), 820);
      expect(parseAmountPaise('8.2'), 820);
      expect(parseAmountPaise('99,99,999.99'), 999999999);
      expect(parseAmountPaise('(1,234.50)'), -123450);
      expect(parseAmountPaise('-1,234.50'), -123450);
      expect(parseAmountPaise('−1,234.50'), -123450);
      expect(parseAmountPaise('1,234.50 Cr'), 123450);
      expect(parseAmountPaise('1,234.50 Dr'), -123450);
      // Not numbers at all.
      expect(parseAmountPaise(''), isNull);
      expect(parseAmountPaise('  '), isNull);
      expect(parseAmountPaise('-'), isNull);
      expect(parseAmountPaise('NIL'), isNull);
      // Three decimals are a different currency's minor unit: refused, not
      // rounded.
      expect(parseAmountPaise('1.234'), isNull);

      // The float trap, stated: 0.07 * 100 is 7.000000000000001 in binary
      // floating point, and 8.20 * 100 is 819.9999999999999. The parser
      // never multiplies, so both are exact above.
      expect((0.07 * 100).toInt(), 7);
      expect((8.20 * 100).toInt(), 819);
    });

    test('F1-07-204 bank_text is preserved byte for byte — immutable evidence '
        '(02 §10 🔒)', () {
      final s = parseStatement(
        bytes: bytesOf(splitColumnsCsv),
        fileName: 'statement.csv',
        accountId: 'bank-1',
      ) as ParsedStatement;

      const verbatim =
          'UPI/DR/425634789012/VERMA DAI/TSTB/vermadairy@oktst/'
          'Payment for milk';
      expect(s.lines[0].bankText, verbatim);
      // Not trimmed, not collapsed, not re-cased: the double space inside
      // the ATM line survives exactly as the bank wrote it.
      expect(s.lines[2].bankText, 'ATM CASH WDL  DELHI');
      // Normalisation is derived metadata and never written back.
      expect(normaliseBankText(s.lines[2].bankText), 'atm cash wdl delhi');
      expect(s.lines[2].bankText, 'ATM CASH WDL  DELHI');
    });

    test('F1-07-205 a malformed file is a typed failure, never a crash '
        '(07 §11 item 4 🔒)', () {
      Object reasonOf(String name, List<int> bytes) {
        final r = parseStatement(
          bytes: Uint8List.fromList(bytes),
          fileName: name,
          accountId: 'bank-1',
        );
        return (r as StatementParseFailure).reason;
      }

      // Random bytes with a .csv name: no header row anywhere in them.
      expect(
        reasonOf('junk.csv', [0x00, 0xFF, 0xFE, 0x01, 0x02, 0x03]),
        ParseFailureReason.noHeaderRow,
      );
      // Empty file.
      expect(reasonOf('empty.csv', const []), ParseFailureReason.unreadable);
      expect(
        reasonOf('blank.csv', utf8.encode('\n\n   \n')),
        ParseFailureReason.unreadable,
      );
      // A header the app understands, with nothing under it.
      expect(
        reasonOf(
          'headers-only.csv',
          utf8.encode('Date,Narration,Withdrawal,Deposit,Balance\n'),
        ),
        ParseFailureReason.noLines,
      );
      // A CSV with no money column at all.
      expect(
        reasonOf('no-amount.csv', utf8.encode('Date,Narration\n02/08/2026,X')),
        ParseFailureReason.noHeaderRow,
      );
      // The formats the drop zone names but this round does not read.
      for (final name in ['s.xls', 's.xlsx', 's.ofx', 's.pdf']) {
        expect(
          reasonOf(name, utf8.encode('anything')),
          ParseFailureReason.notYetSupported,
          reason: name,
        );
      }
      expect(
        reasonOf('photo.jpg', utf8.encode('anything')),
        ParseFailureReason.unsupportedFormat,
      );
    });

    test(
      'F1-07-206 duplicates are removed before anything is shown, counted, and '
      'two genuine identical same-day lines are never collapsed (02 §10 🔒)',
      () {
        final first = parseStatement(
          bytes: bytesOf(splitColumnsCsv),
          fileName: 'statement.csv',
          accountId: 'bank-1',
        ) as ParsedStatement;
        final already = {
          for (var i = 0; i < first.lines.length; i++)
            identityOf(first.lines[i], accountId: 'bank-1'),
        };

        // The same file again: every line already imported.
        final again = parseStatement(
          bytes: bytesOf(splitColumnsCsv),
          fileName: 'statement.csv',
          accountId: 'bank-1',
          alreadyImported: already,
        ) as ParsedStatement;
        expect(again.lines, isEmpty);
        expect(again.duplicatesSkipped, 3);
        expect(again.totalRead, 3);

        // The same statement in a different bank A/C is not a duplicate: the
        // identity is scoped to the account.
        final other = parseStatement(
          bytes: bytesOf(splitColumnsCsv),
          fileName: 'statement.csv',
          accountId: 'bank-2',
          alreadyImported: already,
        ) as ParsedStatement;
        expect(other.duplicatesSkipped, 0);
        expect(other.lines.length, 3);

        // Two genuine identical same-day withdrawals: the per-file ordinal
        // keeps them apart, so importing the pair once and re-uploading skips
        // exactly two — never one, never three.
        const twice = '''
Date,Narration,Withdrawal Amt.,Deposit Amt.
02/08/2026,ATM CASH WDL,"2,000.00",
02/08/2026,ATM CASH WDL,"2,000.00",
''';
        final pair = parseStatement(
          bytes: bytesOf(twice),
          fileName: 'a.csv',
          accountId: 'bank-1',
        ) as ParsedStatement;
        expect(pair.lines.length, 2);
        expect(
          identityOf(pair.lines[0], accountId: 'bank-1'),
          isNot(identityOf(pair.lines[1], accountId: 'bank-1', ordinal: 1)),
        );

        final pairAgain = parseStatement(
          bytes: bytesOf(twice),
          fileName: 'a.csv',
          accountId: 'bank-1',
          alreadyImported: {
            identityOf(pair.lines[0], accountId: 'bank-1'),
            identityOf(pair.lines[1], accountId: 'bank-1', ordinal: 1),
          },
        ) as ParsedStatement;
        expect(pairAgain.duplicatesSkipped, 2);
        expect(pairAgain.lines, isEmpty);

        // Only one of the pair imported: the second still comes through.
        final half = parseStatement(
          bytes: bytesOf(twice),
          fileName: 'a.csv',
          accountId: 'bank-1',
          alreadyImported: {identityOf(pair.lines[0], accountId: 'bank-1')},
        ) as ParsedStatement;
        expect(half.duplicatesSkipped, 1);
        expect(half.lines.length, 1);
      },
    );

    test('F1-07-207 over 10 MB is refused before the file is decoded '
        '(07 §11 item 1 🔒)', () {
      expect(maxStatementBytes, 10 * 1024 * 1024);
      final tooBig = Uint8List(maxStatementBytes + 1);
      final r = parseStatement(
        bytes: tooBig,
        fileName: 'huge.csv',
        accountId: 'bank-1',
      );
      expect((r as StatementParseFailure).reason, ParseFailureReason.tooLarge);
      expect(r.fileName, 'huge.csv');

      // Exactly 10 MB is allowed — the limit is stated as "up to 10 MB".
      final atLimit = parseStatement(
        bytes: Uint8List(maxStatementBytes),
        fileName: 'big.csv',
        accountId: 'bank-1',
      );
      expect(
        (atLimit as StatementParseFailure).reason,
        isNot(ParseFailureReason.tooLarge),
      );
    });

    test('F1-07-208 XLS, OFX and PDF are stated as not-yet-supported, with the '
        'format named — never a silent shrug', () {
      for (final (name, format) in [
        ('s.xls', StatementFormat.xls),
        ('s.xlsx', StatementFormat.xls),
        ('s.ofx', StatementFormat.ofx),
        ('s.qfx', StatementFormat.ofx),
        ('s.pdf', StatementFormat.pdf),
      ]) {
        final r = parseStatement(
          bytes: bytesOf('anything'),
          fileName: name,
          accountId: 'bank-1',
        ) as StatementParseFailure;
        expect(r.reason, ParseFailureReason.notYetSupported);
        expect(r.format, format, reason: name);
      }
      expect(StatementFormat.csv.isSupportedNow, isTrue);
      expect(StatementFormat.pdf.isSupportedNow, isFalse);
    });

    test('F1-07-209 a remembered mapping is used as given, and a correction '
        're-reads the same rows (07 §11 item 1 🔒)', () {
      // A file whose headers the detector cannot read at all — exactly the
      // case the per-bank memory exists for.
      const headless = '''
Col1,Col2,Col3,Col4
02/08/2026,SOME BANK LINE,1234.50,98765.50
05/08/2026,ANOTHER LINE,-2000.00,96765.50
''';
      expect(
        parseStatement(
          bytes: bytesOf(headless),
          fileName: 'x.csv',
          accountId: 'bank-1',
        ),
        isA<StatementParseFailure>(),
      );

      const remembered = ColumnMapping(
        date: 0,
        description: 1,
        amount: 2,
        balance: 3,
        confidence: MappingConfidence.confirmed,
      );
      final s = parseStatement(
        bytes: bytesOf(headless),
        fileName: 'x.csv',
        accountId: 'bank-1',
        mapping: remembered,
      ) as ParsedStatement;
      expect(s.mapping.confidence, MappingConfidence.confirmed);
      expect(s.lines.length, 2);
      expect(s.lines[0].direction, BankDirection.moneyIn);
      expect(s.lines[0].bankText, 'SOME BANK LINE');
      expect(s.lines[1].direction, BankDirection.moneyOut);

      // A correction re-points one role and nothing else, and comes back
      // confirmed — the user has just said so.
      final corrected = remembered.withColumn(StatementColumn.balance, null);
      expect(corrected.balance, isNull);
      expect(corrected.amount, 2);
      expect(corrected.confidence, MappingConfidence.confirmed);
      final reread = readLines(statementRows(bytesOf(headless)), corrected);
      expect(reread.lines.length, 2);
      expect(reread.lines[0].balancePaise, isNull);

      // What is remembered round-trips through the shape `rules_p` will
      // hold (03 §3.2).
      expect(ColumnMapping.fromJson(corrected.toJson()), corrected);
    });
  });
}
