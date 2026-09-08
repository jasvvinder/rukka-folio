// Dates on screen (07 §1 rule 5 🔒): English abbreviates the month
// (`07 Aug 2026`); ਪੰਜਾਬੀ and हिन्दी use full month names — the ARB carries the
// right form per locale, so this file never branches on language. Relative
// labels *Today / Yesterday* in lists, decided against an injected `now` —
// never `DateTime.now()` (CLAUDE.md rule 3; RkScope.now).
import 'package:core_ledger/core_ledger.dart';

import '../../l10n/gen/app_localizations.dart';

/// The calendar day of an injected [DateTime] in the device's local zone —
/// the ledger's `accounting_date` is a [LocalDate], not an instant (03 §1).
LocalDate localDateOf(DateTime moment) =>
    LocalDate(moment.year, moment.month, moment.day);

/// The month word for [month] (1–12) from the locale's strings: abbreviated
/// in EN, full in PA/HI (07 §1 rule 5).
String monthName(AppLocalizations strings, int month) => switch (month) {
  1 => strings.dateMonthJan,
  2 => strings.dateMonthFeb,
  3 => strings.dateMonthMar,
  4 => strings.dateMonthApr,
  5 => strings.dateMonthMay,
  6 => strings.dateMonthJun,
  7 => strings.dateMonthJul,
  8 => strings.dateMonthAug,
  9 => strings.dateMonthSep,
  10 => strings.dateMonthOct,
  11 => strings.dateMonthNov,
  12 => strings.dateMonthDec,
  _ => throw ArgumentError.value(month, 'month', 'must be 1–12'),
};

/// `DD <month> YYYY` — `07 Aug 2026` in EN, `07 ਅਗਸਤ 2026` in PA, `07 अगस्त
/// 2026` in HI. Digits are Latin in every locale (11 §4.4).
String formatLedgerDate(LocalDate date, {required AppLocalizations strings}) =>
    '${date.day.toString().padLeft(2, '0')} '
    '${monthName(strings, date.month)} ${date.year}';

/// [formatLedgerDate], but *Today* / *Yesterday* when [date] is the day of
/// [now] or the one before (07 §1 rule 5, lists). Any other day — including
/// tomorrow, which the ledger does not allow — falls back to the full form.
String formatListDate(
  LocalDate date, {
  required AppLocalizations strings,
  required DateTime now,
}) {
  final today = localDateOf(now);
  final delta = date.daysUntil(today);
  if (delta == 0) return strings.dateToday;
  if (delta == 1) return strings.dateYesterday;
  return formatLedgerDate(date, strings: strings);
}
