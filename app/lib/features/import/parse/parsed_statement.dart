// What reading a statement file produces (02 §10 🔒, 07 §11 🔒).
//
// Parsed lines land in an **inbox, never the ledger** (02 §10 🔒) — nothing in
// this file posts anything, and none of it knows what the counterpart account
// is. That is the one question S7.1 asks.
import 'package:core_ledger/core_ledger.dart';

import 'column_mapping.dart';
import 'field_parse.dart';

/// Which way the money went, **in the bank's own vocabulary** (02 §10 🔒).
///
/// A bank credit is money *in* to the user — the mirror of our ledger,
/// because the bank keeps its own book. The engine's Dr/Cr logic never
/// changes; the words the user sees do, and on import they are only ever
/// *Money in* / *Money out*.
enum BankDirection {
  /// The bank credited the account: money came in.
  moneyIn,

  /// The bank debited the account: money went out.
  moneyOut,
}

/// One line of a statement, as parsed.
final class ParsedLine {
  /// Creates a line.
  const ParsedLine({
    required this.date,
    required this.bankText,
    required this.paise,
    required this.direction,
    required this.rowIndex,
    this.balancePaise,
  });

  /// The transaction date (a date only — 03 §1).
  final LocalDate date;

  /// The statement's own line, **verbatim** — never trimmed, re-cased or
  /// re-wrapped (02 §10 🔒). Truncation is a display decision, never a
  /// storage one.
  final String bankText;

  /// The magnitude in **integer paise**, always positive; [direction] carries
  /// the side. No float touches this value (CLAUDE.md rule 1).
  final int paise;

  /// Money in or money out, in bank vocabulary.
  final BankDirection direction;

  /// The bank's running balance after this line, when the file has the
  /// column. Signed as the bank prints it (an overdraft runs negative).
  final int? balancePaise;

  /// The line's row in the file, header row included — what the mapping
  /// screen points at when a row is wrong.
  final int rowIndex;

  /// The amount as [Paise], for handing to the engine unchanged.
  Paise get amount => Paise(paise);

  @override
  String toString() =>
      'ParsedLine($date, ${direction.name}, $paise, "$bankText")';
}

/// A line's stable identity for duplicate defence (02 §10 🔒).
///
/// Date + amount + the **normalised** bank text, within one account, plus the
/// per-file [ordinal] among lines identical in all three. The ordinal is what
/// keeps two genuine identical same-day withdrawals from collapsing into one
/// (02 §10 🔒) while a re-upload of the same file still matches line for line:
/// the ordinal counts occurrences *within the statement*, so it is the same
/// on every upload of that statement.
///
/// The normalisation is derived metadata and never replaces `bank_text`.
final class LineIdentity {
  /// Creates an identity.
  const LineIdentity({
    required this.accountId,
    required this.epochDay,
    required this.paise,
    required this.direction,
    required this.normalisedText,
    required this.ordinal,
  });

  /// The identity of [line] within [accountId], as the [ordinal]th line
  /// identical to it in this file.
  factory LineIdentity.of(
    ParsedLine line, {
    required String accountId,
    int ordinal = 0,
  }) => LineIdentity(
    accountId: accountId,
    epochDay: line.date.toEpochDays(),
    paise: line.paise,
    direction: line.direction,
    normalisedText: normaliseBankText(line.bankText),
    ordinal: ordinal,
  );

  /// The bank A/C the line belongs to.
  final String accountId;

  /// The transaction date, as days since 1970-01-01.
  final int epochDay;

  /// Magnitude in integer paise.
  final int paise;

  /// Money in or money out.
  final BankDirection direction;

  /// Trimmed, whitespace-collapsed, case-folded bank text.
  final String normalisedText;

  /// Which occurrence of an otherwise identical line this is, 0-based.
  final int ordinal;

  @override
  bool operator ==(Object other) =>
      other is LineIdentity &&
      other.accountId == accountId &&
      other.epochDay == epochDay &&
      other.paise == paise &&
      other.direction == direction &&
      other.normalisedText == normalisedText &&
      other.ordinal == ordinal;

  @override
  int get hashCode => Object.hash(
    accountId,
    epochDay,
    paise,
    direction,
    normalisedText,
    ordinal,
  );

  @override
  String toString() =>
      'LineIdentity($accountId, $epochDay, $paise, ${direction.name}, '
      '"$normalisedText", #$ordinal)';
}

/// The result of reading a file: either a statement or a stated failure.
/// Never an exception the screen has to interpret, and never a crash.
sealed class StatementParseResult {
  const StatementParseResult();
}

/// A statement the app could read.
final class ParsedStatement extends StatementParseResult {
  /// Creates a statement.
  const ParsedStatement({
    required this.fileName,
    required this.accountId,
    required this.mapping,
    required this.lines,
    required this.headers,
    this.duplicatesSkipped = 0,
    this.unreadableRows = 0,
  });

  /// The file the user picked, for the confirmation copy. The file itself
  /// never leaves the device (07 §11 item 4 🔒).
  final String fileName;

  /// The bank A/C the user picked before the file (07 §11 item 1 🔒).
  final String accountId;

  /// How the columns were read.
  final ColumnMapping mapping;

  /// The lines to show, duplicates already removed (07 §11 item 1 🔒:
  /// *duplicates removed before anything is shown*).
  final List<ParsedLine> lines;

  /// The file's own header cells, verbatim — shown as **data** on the mapping
  /// step, which is why they never live in ARB.
  final List<String> headers;

  /// How many lines were dropped as already imported; the count is stated up
  /// front (07 §11 item 1 🔒).
  final int duplicatesSkipped;

  /// Rows after the header that held no readable date or amount (the bank's
  /// own totals and footers). Stated on the duplicates step rather than
  /// silently dropped.
  final int unreadableRows;

  /// Every line that was read, duplicates included.
  int get totalRead => lines.length + duplicatesSkipped;
}

/// Why a file could not be read (07 §11 item 4 🔒: *Couldn't read this file* +
/// the supported-format list).
enum ParseFailureReason {
  /// Over [maxStatementBytes].
  tooLarge,

  /// A format the app will read, but not yet in this version (XLS, OFX, PDF).
  notYetSupported,

  /// A format the app does not read at all.
  unsupportedFormat,

  /// No header row could be found, so no column means anything.
  noHeaderRow,

  /// A header row, but no date column or no amount column in it.
  noAmountColumn,

  /// A readable shape with no transaction rows in it.
  noLines,

  /// The file is empty, or is not text at all.
  unreadable,
}

/// A stated, typed failure. The file is still on the device; nothing readable
/// left the phone to produce this (07 §11 item 1 🔒, 04).
final class StatementParseFailure extends StatementParseResult {
  /// Creates a failure.
  const StatementParseFailure(
    this.reason, {
    required this.fileName,
    this.format,
  });

  /// Which failure this is; the screen maps it to copy.
  final ParseFailureReason reason;

  /// The file the user picked.
  final String fileName;

  /// The format that was recognised but not read, for
  /// [ParseFailureReason.notYetSupported].
  final StatementFormat? format;

  @override
  String toString() => 'StatementParseFailure(${reason.name}, $fileName)';
}

/// The formats the drop zone names: *CSV, XLS, OFX or PDF · up to 10 MB*
/// (07 §11 item 1 🔒). Only [csv] is read this round; the rest are typed
/// *not yet supported* results, said plainly rather than hidden.
enum StatementFormat {
  /// Comma (or `;`/tab/`|`) separated text — read on-device today.
  csv,

  /// Excel workbook.
  xls,

  /// Open Financial Exchange.
  ofx,

  /// A PDF statement; per-pilot-bank work is owner-held.
  pdf;

  /// The format [fileName]'s extension names, or null when unrecognised.
  static StatementFormat? ofFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'csv' || 'txt' || 'tsv' => StatementFormat.csv,
      'xls' || 'xlsx' => StatementFormat.xls,
      'ofx' || 'qfx' => StatementFormat.ofx,
      'pdf' => StatementFormat.pdf,
      _ => null,
    };
  }

  /// Whether this round's parser can read it.
  bool get isSupportedNow => this == StatementFormat.csv;
}

/// The size the drop zone states: 10 MB (07 §11 item 1 🔒). A bigger file is
/// refused before it is decoded, so a wrong pick costs nothing.
const maxStatementBytes = 10 * 1024 * 1024;
