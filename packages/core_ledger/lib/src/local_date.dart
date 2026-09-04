import 'money.dart';

/// Calendar dates without time or zone. `accounting_date` is a date only (03 §1);
/// nothing here reads a clock.
final class LocalDate implements Comparable<LocalDate> {
  /// Creates a validated calendar date.
  LocalDate(this.year, this.month, this.day) {
    if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
    if (day < 1 || day > daysInMonth(year, month)) {
      throw ArgumentError.value(day, 'day');
    }
  }

  /// Parses `YYYY-MM-DD`.
  factory LocalDate.parse(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) throw FormatException('not an ISO date', iso);
    return LocalDate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// Inverse of [toEpochDays].
  factory LocalDate.fromEpochDays(int days) {
    // Howard Hinnant's civil_from_days.
    final z = days + 719468;
    final era = floorDiv(z, 146097);
    final doe = z - era * 146097;
    final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
    final y = yoe + era * 400;
    final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
    final mp = (5 * doy + 2) ~/ 153;
    final d = doy - (153 * mp + 2) ~/ 5 + 1;
    final m = mp < 10 ? mp + 3 : mp - 9;
    return LocalDate(m <= 2 ? y + 1 : y, m, d);
  }

  /// Year.
  final int year;

  /// Month, 1–12.
  final int month;

  /// Day of month.
  final int day;

  /// True for leap years.
  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  /// Days in a month.
  static int daysInMonth(int year, int month) => switch (month) {
    2 => isLeapYear(year) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };

  /// Days since 1970-01-01 (may be negative).
  int toEpochDays() {
    // Howard Hinnant's days_from_civil.
    final y = month <= 2 ? year - 1 : year;
    final era = floorDiv(y, 400);
    final yoe = y - era * 400;
    final mp = month > 2 ? month - 3 : month + 9;
    final doy = (153 * mp + 2) ~/ 5 + day - 1;
    final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
    return era * 146097 + doe - 719468;
  }

  /// Days from this date to [other] (positive when [other] is later).
  int daysUntil(LocalDate other) => other.toEpochDays() - toEpochDays();

  /// This date plus [days].
  LocalDate addDays(int days) => LocalDate.fromEpochDays(toEpochDays() + days);

  /// The calendar month this date falls in.
  YearMonth get yearMonth => YearMonth(year, month);

  /// True when strictly before [other].
  bool isBefore(LocalDate other) => compareTo(other) < 0;

  /// True when strictly after [other].
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  /// `YYYY-MM-DD`.
  String toIso() => '$year-${_two(month)}-${_two(day)}';

  @override
  int compareTo(LocalDate other) =>
      toEpochDays().compareTo(other.toEpochDays());

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// A calendar month — the unit of period locking (02 §8).
final class YearMonth implements Comparable<YearMonth> {
  /// Creates a month.
  YearMonth(this.year, this.month) {
    if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
  }

  /// Year.
  final int year;

  /// Month, 1–12.
  final int month;

  /// First day.
  LocalDate get firstDay => LocalDate(year, month, 1);

  /// Last day.
  LocalDate get lastDay =>
      LocalDate(year, month, LocalDate.daysInMonth(year, month));

  /// Number of days.
  int get daysInMonth => LocalDate.daysInMonth(year, month);

  /// The following month.
  YearMonth get next =>
      month == 12 ? YearMonth(year + 1, 1) : YearMonth(year, month + 1);

  /// True when [date] falls in this month.
  bool contains(LocalDate date) => date.year == year && date.month == month;

  @override
  int compareTo(YearMonth other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${_two(month)}';
}

/// A book's financial year (02 §1.1: default 1 April – 31 March, per book).
final class FinancialYear {
  /// Creates the financial year beginning in [startYear] at [startMonth].
  FinancialYear(this.startYear, {this.startMonth = 4}) {
    if (startMonth < 1 || startMonth > 12) {
      throw ArgumentError.value(startMonth, 'startMonth');
    }
  }

  /// The financial year containing [date].
  factory FinancialYear.of(LocalDate date, {int startMonth = 4}) =>
      FinancialYear(
        date.month >= startMonth ? date.year : date.year - 1,
        startMonth: startMonth,
      );

  /// Calendar year the FY starts in.
  final int startYear;

  /// Month the FY starts in (1–12).
  final int startMonth;

  /// First day.
  LocalDate get firstDay => LocalDate(startYear, startMonth, 1);

  /// Last day.
  LocalDate get lastDay => next.firstDay.addDays(-1);

  /// The twelve months in order.
  List<YearMonth> get months {
    final out = <YearMonth>[];
    var m = YearMonth(startYear, startMonth);
    for (var i = 0; i < 12; i++) {
      out.add(m);
      m = m.next;
    }
    return out;
  }

  /// True when [date] falls in this FY.
  bool contains(LocalDate date) =>
      !date.isBefore(firstDay) && !date.isAfter(lastDay);

  /// The following FY.
  FinancialYear get next =>
      FinancialYear(startYear + 1, startMonth: startMonth);

  /// `2026-27` for April-start years, `2026` for calendar years.
  String get label => startMonth == 1
      ? '$startYear'
      : '$startYear-${_two((startYear + 1) % 100)}';

  @override
  bool operator ==(Object other) =>
      other is FinancialYear &&
      other.startYear == startYear &&
      other.startMonth == startMonth;

  @override
  int get hashCode => Object.hash(startYear, startMonth);

  @override
  String toString() => 'FY $label';
}

String _two(int n) => n < 10 ? '0$n' : '$n';
