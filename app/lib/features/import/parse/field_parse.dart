// Reading one cell of a bank statement: an amount and a date.
//
// **Rule 1 (CLAUDE.md, 02 §1.4):** money is integer paise and no float ever
// touches it. `1,23,456.78` is read by splitting the string at the decimal
// point and doing integer arithmetic on the two halves — `double.parse` is
// not used here, and cannot be: `0.07` is not representable, and a rounding
// step is exactly the bug the rule forbids.
//
// Pure string work: no clock, no locale, no `dart:io`.
import 'package:core_ledger/core_ledger.dart';

/// The minus sign a statement may use: ASCII, Unicode, or the accountant's
/// parentheses (`(1,234.50)`).
const _minusSigns = ['-', '−', '–', '—'];

/// Reads an amount cell as **signed integer paise**, or null when the cell
/// holds no number at all (blank, `-`, `NIL`, a stray footer word).
///
/// Accepts Indian grouping (`1,23,456.78`), western grouping (`123,456.78`),
/// a `₹`/`Rs`/`INR` prefix, a trailing `Dr`/`Cr` marker, spaces inside the
/// figure, and parentheses for negatives. One or two decimal places; a third
/// would be a different currency's minor unit and is refused rather than
/// rounded.
int? parseAmountPaise(String cell) {
  var s = cell.trim();
  if (s.isEmpty) return null;
  var negative = false;

  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1).trim();
  }

  // A trailing (or leading) Dr/Cr marker inside the amount cell itself.
  final marker = RegExp(
    r'^(dr|cr|db|c|d)\b|\b(dr|cr|db|c|d)\.?$',
    caseSensitive: false,
  ).firstMatch(s);
  if (marker != null) {
    final word = (marker.group(1) ?? marker.group(2)!).toLowerCase();
    if (word == 'dr' || word == 'db' || word == 'd') negative = true;
    s = s.replaceRange(marker.start, marker.end, '').trim();
  }

  // Currency marks and grouping. `,` is a group separator in every Indian
  // statement; a European decimal comma would need the mapping step to say
  // so, and is refused here rather than guessed at.
  s = s
      .replaceAll(RegExp(r'(?:₹|rs\.?|inr)', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s,]'), '')
      .trim();

  for (final sign in _minusSigns) {
    if (s.startsWith(sign)) {
      negative = true;
      s = s.substring(sign.length);
      break;
    }
  }
  if (s.startsWith('+')) s = s.substring(1);
  if (s.isEmpty) return null;

  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final rupees = int.parse(m.group(1)!);
  final frac = m.group(2);
  final paise = frac == null ? 0 : int.parse(frac.padRight(2, '0'));
  final value = rupees * 100 + paise;
  return negative ? -value : value;
}

/// Month names as Indian statements print them, lower-cased.
const _months = {
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

/// Reads a date cell, or null when it is not a date.
///
/// Understands `dd/MM/yyyy`, `dd-MM-yy`, `dd.MM.yyyy`, `dd-MMM-yyyy`
/// (`01-Apr-2026`), `dd MMM yy` and ISO `yyyy-MM-dd`. **Day-first is the
/// default** — every Indian bank prints it that way — and a first component
/// above 12 settles it regardless. A time of day after the date is ignored:
/// `accounting_date` is a date only (03 §1).
///
/// Two-digit years resolve into 2000–2099. A statement from 1998 is not a
/// case this app has; assuming it would mis-date every line of the ones it
/// does have.
LocalDate? parseStatementDate(String cell) {
  final s = cell.trim();
  if (s.isEmpty) return null;

  final iso = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b').firstMatch(s);
  if (iso != null) {
    return _date(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }

  final named = RegExp(r'^(\d{1,2})[-/. ]([A-Za-z]{3,9})[-/. ](\d{2}|\d{4})\b')
      .firstMatch(s);
  if (named != null) {
    final month = _months[named.group(2)!.toLowerCase()];
    if (month == null) return null;
    return _date(_year(named.group(3)!), month, int.parse(named.group(1)!));
  }

  final numeric = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\b')
      .firstMatch(s);
  if (numeric != null) {
    final a = int.parse(numeric.group(1)!);
    final b = int.parse(numeric.group(2)!);
    final year = _year(numeric.group(3)!);
    // Day-first unless the first component cannot be a day.
    return a > 12 || b <= 12 ? _date(year, b, a) : _date(year, a, b);
  }
  return null;
}

int _year(String digits) =>
    digits.length == 4 ? int.parse(digits) : 2000 + int.parse(digits);

LocalDate? _date(int year, int month, int day) {
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > LocalDate.daysInMonth(year, month)) return null;
  return LocalDate(year, month, day);
}

/// Trim, collapse whitespace, case-fold — the normalisation the duplicate
/// identity uses (02 §10 🔒, ADR 2026-09-05e §12). The bank's running balance
/// is a column of its own here, so there is none embedded to strip.
///
/// This is **derived metadata**: it is never written back over `bank_text`,
/// which stays verbatim (02 §10 🔒).
String normaliseBankText(String bankText) =>
    bankText.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
