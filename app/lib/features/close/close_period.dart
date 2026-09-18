// The one piece of parsing this feature does: the `:period` path parameter.
//
// The wire form is `YearMonth.toString()`'s own — `YYYY-MM` — so the path and
// the engine agree by construction and nothing here invents a second calendar
// (02 §8: periods are calendar months).
//
// It returns **null** rather than throwing or guessing. A route cannot know
// what month the user meant, and *the current month* is not a safe guess: it
// would silently offer to close the wrong period. Null reaches a screen that
// says so and offers the way back (07 §1 rule 6).
import 'package:core_ledger/core_ledger.dart';

/// `YYYY-MM` → [YearMonth], or null when [raw] is missing or malformed.
YearMonth? parseClosePeriod(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12) return null;
  return YearMonth(year, month);
}

/// `YYYY-MM` (the financial year's **first month**) → [FinancialYear], or null
/// when [raw] is missing or malformed.
///
/// A book's FY does not have to start in April — `FinancialYear.startMonth` is
/// 1–12 and a trust may run the calendar year — so the route names the first
/// month and this reads both halves of the answer out of it. Like
/// [parseClosePeriod] it **guesses nothing**: the current financial year is not
/// a safe default, because certifying the wrong year is exactly the mistake
/// 02 §8.1 🔒 makes permanent.
FinancialYear? parseFinancialYear(String? raw) {
  final start = parseClosePeriod(raw);
  if (start == null) return null;
  return FinancialYear(start.year, startMonth: start.month);
}
