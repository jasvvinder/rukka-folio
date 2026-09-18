// The on-device statement parser (07 §11 item 1 🔒: *all parsing on-device*;
// 04: nothing readable leaves the phone).
//
// Bytes in, value out. No `dart:io`, no clock, no locale, no network — the
// whole file is a pure function, so the three statement shapes below are
// pinned by tests rather than by a bank's goodwill, and the money path is
// integer paise end to end (CLAUDE.md rule 1).
//
// What it deliberately does **not** do: decide a counterpart account, post
// anything, or edit `bank_text`. Parsed lines land in an inbox, never the
// ledger (02 §10 🔒).
import 'dart:typed_data';

import 'column_mapping.dart';
import 'csv_reader.dart';
import 'field_parse.dart';
import 'parsed_statement.dart';

/// How many rows from the top are searched for the header row. A bank's
/// letterhead block (name, A/C number, period, address) runs long; 30 rows
/// covers every sample shape without letting a data row masquerade as one.
const _headerSearchRows = 30;

/// Reads a statement file.
///
/// [bytes] and [fileName] come from the file port; [accountId] is the bank
/// A/C picked *before* the file (07 §11 item 1 🔒), and is part of every
/// line's identity. [mapping] is the per-bank remembered mapping when there is
/// one — supplying it skips detection and marks the result confirmed.
/// [alreadyImported] are the identities the book already holds: matching lines
/// are removed **before anything is shown** and counted (07 §11 item 1 🔒).
///
/// Never throws for bad input: every refusal is a [StatementParseFailure].
StatementParseResult parseStatement({
  required Uint8List bytes,
  required String fileName,
  required String accountId,
  ColumnMapping? mapping,
  Set<LineIdentity> alreadyImported = const {},
}) {
  if (bytes.length > maxStatementBytes) {
    return StatementParseFailure(
      ParseFailureReason.tooLarge,
      fileName: fileName,
    );
  }
  final format = StatementFormat.ofFileName(fileName);
  if (format == null) {
    return StatementParseFailure(
      ParseFailureReason.unsupportedFormat,
      fileName: fileName,
    );
  }
  if (!format.isSupportedNow) {
    return StatementParseFailure(
      ParseFailureReason.notYetSupported,
      fileName: fileName,
      format: format,
    );
  }
  if (bytes.isEmpty) {
    return StatementParseFailure(
      ParseFailureReason.unreadable,
      fileName: fileName,
    );
  }

  final text = decodeStatementText(bytes);
  if (text.trim().isEmpty) {
    return StatementParseFailure(
      ParseFailureReason.unreadable,
      fileName: fileName,
    );
  }
  final delimiter = mapping?.delimiter ?? sniffDelimiter(text);
  final rows = parseCsv(text, delimiter: delimiter);
  if (rows.isEmpty) {
    return StatementParseFailure(
      ParseFailureReason.unreadable,
      fileName: fileName,
    );
  }

  final resolved = mapping ?? detectMapping(rows, delimiter: delimiter);
  if (resolved == null) {
    return StatementParseFailure(
      ParseFailureReason.noHeaderRow,
      fileName: fileName,
    );
  }
  if (!resolved.hasAmount) {
    return StatementParseFailure(
      ParseFailureReason.noAmountColumn,
      fileName: fileName,
    );
  }

  final read = readLines(rows, resolved);
  if (read.lines.isEmpty) {
    return StatementParseFailure(
      ParseFailureReason.noLines,
      fileName: fileName,
    );
  }

  final kept = <ParsedLine>[];
  var skipped = 0;
  final seen = <LineIdentity, int>{};
  for (final line in read.lines) {
    // The ordinal counts occurrences within *this file*, so a re-upload of
    // the same statement produces the same identities line for line, while
    // two genuinely identical same-day withdrawals stay two lines.
    final base = LineIdentity.of(line, accountId: accountId);
    final ordinal = seen.update(base, (n) => n + 1, ifAbsent: () => 0);
    final identity = LineIdentity.of(
      line,
      accountId: accountId,
      ordinal: ordinal,
    );
    if (alreadyImported.contains(identity)) {
      skipped++;
    } else {
      kept.add(line);
    }
  }

  return ParsedStatement(
    fileName: fileName,
    accountId: accountId,
    mapping: resolved,
    lines: kept,
    headers: read.headers,
    duplicatesSkipped: skipped,
    unreadableRows: read.unreadableRows,
  );
}

/// The identity of [line] in [accountId] — what an importer records so the
/// next upload can skip it. Exposed so the ledger implementation of
/// `ImportSource.alreadyImported` builds identities exactly as the parser
/// does, rather than a second, drifting copy of the rule.
LineIdentity identityOf(
  ParsedLine line, {
  required String accountId,
  int ordinal = 0,
}) => LineIdentity.of(line, accountId: accountId, ordinal: ordinal);

/// What [readLines] found.
final class ReadLines {
  /// Creates the result.
  const ReadLines({
    required this.lines,
    required this.headers,
    required this.unreadableRows,
  });

  /// The transaction lines, in file order.
  final List<ParsedLine> lines;

  /// The header row's cells, verbatim.
  final List<String> headers;

  /// Rows after the header that held no date or no amount.
  final int unreadableRows;
}

/// Reads [rows] under [mapping]. Pure; used by the mapping screen to re-read
/// the sample row the instant a correction is made.
ReadLines readLines(List<List<String>> rows, ColumnMapping mapping) {
  final headers = mapping.headerRow < rows.length
      ? rows[mapping.headerRow]
      : const <String>[];
  final lines = <ParsedLine>[];
  var unreadable = 0;
  for (var i = mapping.headerRow + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((c) => c.trim().isEmpty)) continue;
    final line = _readRow(row, mapping, i);
    if (line == null) {
      unreadable++;
    } else {
      lines.add(line);
    }
  }
  return ReadLines(lines: lines, headers: headers, unreadableRows: unreadable);
}

String _cell(List<String> row, int? index) =>
    index == null || index < 0 || index >= row.length ? '' : row[index];

ParsedLine? _readRow(List<String> row, ColumnMapping m, int rowIndex) {
  final date = parseStatementDate(_cell(row, m.date));
  if (date == null) return null;

  // `bank_text` verbatim — the cell exactly as the file holds it (02 §10 🔒).
  final bankText = _cell(row, m.description);

  int? paise;
  BankDirection? direction;

  if (m.hasSplitColumns) {
    final out = parseAmountPaise(_cell(row, m.moneyOut));
    final into = parseAmountPaise(_cell(row, m.moneyIn));
    if (into != null && into != 0) {
      paise = into.abs();
      direction = BankDirection.moneyIn;
    } else if (out != null && out != 0) {
      paise = out.abs();
      direction = BankDirection.moneyOut;
    }
  } else if (m.amount != null) {
    final value = parseAmountPaise(_cell(row, m.amount));
    if (value != null && value != 0) {
      paise = value.abs();
      direction =
          _markerDirection(_cell(row, m.direction)) ??
          (value < 0 ? BankDirection.moneyOut : BankDirection.moneyIn);
    }
  }
  if (paise == null || direction == null) return null;

  return ParsedLine(
    date: date,
    bankText: bankText,
    paise: paise,
    direction: direction,
    balancePaise: parseAmountPaise(_cell(row, m.balance)),
    rowIndex: rowIndex,
  );
}

/// Reads a `Dr`/`Cr` marker cell. **The bank's credit is the user's money in**
/// (02 §10 🔒): the bank keeps its own book, so its credit to your account is
/// its liability and your deposit.
BankDirection? _markerDirection(String cell) {
  final s = cell.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s.startsWith('cr') || s == 'c' || s == '+' || s.startsWith('credit')) {
    return BankDirection.moneyIn;
  }
  if (s.startsWith('dr') ||
      s.startsWith('db') ||
      s == 'd' ||
      s == '-' ||
      s.startsWith('debit')) {
    return BankDirection.moneyOut;
  }
  return null;
}

/// Header keywords, longest-specific first. These are **file data**, not UI
/// labels: they match what a bank prints, so they never go through ARB (and
/// `check_strings`' rule-4 carve-out says exactly that of the S7.0b headers).
const _directionWords = [
  'dr/cr',
  'cr/dr',
  'dr / cr',
  'debit/credit',
  'credit/debit',
  'indicator',
  'txn type',
  'type',
];
const _balanceWords = ['balance', 'bal'];
const _outWords = [
  'withdrawal',
  'withdrawl',
  'withdraw',
  'debit',
  'paid out',
  'payments',
];
const _inWords = ['deposit', 'credit', 'paid in', 'receipts'];
const _dateWords = ['date'];
const _descWords = [
  'description',
  'particulars',
  'details',
  'remarks',
  'narration',
  'transaction',
];
const _amountWords = ['amount', 'amt'];

String _normaliseHeader(String cell) => cell
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)'), ' ')
    .replaceAll(RegExp(r'[^a-z/ ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The longest a header cell can plausibly be. A binary file read as text
/// arrives as one enormous "cell", and running the header regexes over ten
/// megabytes of it is how the 10 MB case overflowed the stack.
const _maxHeaderCell = 80;

StatementColumn? _roleOf(String header) {
  if (header.length > _maxHeaderCell) return null;
  final h = _normaliseHeader(header);
  if (h.isEmpty) return null;
  bool has(List<String> words) => words.any(h.contains);
  // Order matters: a `Dr/Cr` marker column contains both money words, and a
  // `Withdrawal Amt` column contains the amount word.
  if (_directionWords.any((w) => h == w || h.contains(w))) {
    return StatementColumn.direction;
  }
  if (has(_balanceWords)) return StatementColumn.balance;
  if (has(_outWords) || h == 'dr') return StatementColumn.moneyOut;
  if (has(_inWords) || h == 'cr') return StatementColumn.moneyIn;
  if (has(_dateWords)) return StatementColumn.date;
  if (has(_descWords)) return StatementColumn.description;
  if (has(_amountWords)) return StatementColumn.amount;
  return null;
}

/// Auto-detects the column mapping (07 §11 item 1 🔒).
///
/// Returns null when no row in the file reads as a header — the screen then
/// shows the parse-failure state rather than guessing at a shape.
ColumnMapping? detectMapping(
  List<List<String>> rows, {
  String delimiter = ',',
}) {
  var bestRow = -1;
  var bestScore = 0;
  Map<StatementColumn, int> bestRoles = const {};
  final limit = rows.length < _headerSearchRows
      ? rows.length
      : _headerSearchRows;
  for (var i = 0; i < limit; i++) {
    final roles = <StatementColumn, int>{};
    for (var c = 0; c < rows[i].length; c++) {
      final role = _roleOf(rows[i][c]);
      // First column wins a role: `Date` then `Value Date` means the first is
      // the transaction date.
      if (role != null && !roles.containsKey(role)) roles[role] = c;
    }
    final hasDate = roles.containsKey(StatementColumn.date);
    final hasMoney =
        roles.containsKey(StatementColumn.moneyOut) ||
        roles.containsKey(StatementColumn.moneyIn) ||
        roles.containsKey(StatementColumn.amount);
    if (!hasDate || !hasMoney) continue;
    if (roles.length > bestScore) {
      bestScore = roles.length;
      bestRow = i;
      bestRoles = roles;
    }
  }
  if (bestRow < 0) return null;

  final split =
      bestRoles.containsKey(StatementColumn.moneyOut) ||
      bestRoles.containsKey(StatementColumn.moneyIn);
  final everyRoleNamed =
      bestRoles.containsKey(StatementColumn.description) &&
      (split || bestRoles.containsKey(StatementColumn.amount));
  return ColumnMapping(
    date: bestRoles[StatementColumn.date]!,
    description: bestRoles[StatementColumn.description],
    moneyOut: bestRoles[StatementColumn.moneyOut],
    moneyIn: bestRoles[StatementColumn.moneyIn],
    amount: split ? null : bestRoles[StatementColumn.amount],
    direction: split ? null : bestRoles[StatementColumn.direction],
    balance: bestRoles[StatementColumn.balance],
    headerRow: bestRow,
    delimiter: delimiter,
    confidence: everyRoleNamed
        ? MappingConfidence.detected
        : MappingConfidence.guessed,
  );
}

/// Splits [bytes] into rows without reading any of them — what the mapping
/// screen needs to re-read the file under a correction.
List<List<String>> statementRows(Uint8List bytes, {String? delimiter}) =>
    parseCsv(decodeStatementText(bytes), delimiter: delimiter);
