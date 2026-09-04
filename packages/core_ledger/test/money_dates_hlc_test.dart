// Suite A — foundations: integer paise (02 §1.4 rule 2), dates (02 §1.4 rule 6, §8), HLC (03 §1).
import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

void main() {
  group('Paise', () {
    test('is integer arithmetic only', () {
      const a = Paise(150);
      const b = Paise(-50);
      expect((a + b).raw, 100);
      expect((a - b).raw, 200);
      expect((-a).raw, -150);
      expect((a * 3).raw, 450);
      expect(Paise.rupees(12).raw, 1200);
      expect(a.abs().raw, 150);
      expect(b.abs().raw, 50);
    });

    test('side follows sign: + is Dr, − is Cr, zero has no side', () {
      expect(const Paise(1).side, Side.dr);
      expect(const Paise(-1).side, Side.cr);
      expect(const Paise(0).side, isNull);
      expect(Paise.zero.isZero, isTrue);
    });

    test('compares and sums', () {
      expect(const Paise(5) < const Paise(7), isTrue);
      expect(const Paise(7) >= const Paise(7), isTrue);
      expect(
        Paise.sum([const Paise(1), const Paise(2), const Paise(-3)]),
        Paise.zero,
      );
    });
  });

  group('LocalDate', () {
    test('parses and prints ISO dates', () {
      final date = LocalDate.parse('2026-04-01');
      expect(date, LocalDate(2026, 4, 1));
      expect(date.toIso(), '2026-04-01');
    });

    test('rejects impossible dates', () {
      expect(() => LocalDate(2026, 2, 30), throwsArgumentError);
      expect(() => LocalDate(2026, 13, 1), throwsArgumentError);
      expect(LocalDate(2028, 2, 29).day, 29); // leap year
    });

    test('day arithmetic', () {
      final a = LocalDate(2026, 4, 8);
      final b = LocalDate(2026, 7, 31);
      expect(a.daysUntil(b), 114);
      expect(a.addDays(114), b);
      expect(LocalDate(2026, 4, 30).addDays(1), LocalDate(2026, 5, 1));
      expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
      expect(a.compareTo(b) < 0, isTrue);
    });

    test('inclusive day count as used by interest on capital', () {
      // 01 Apr – 31 Jul 2026 is the 122-day season of 02 §7.1.
      expect(LocalDate(2026, 4, 1).daysUntil(LocalDate(2026, 7, 31)) + 1, 122);
    });
  });

  group('YearMonth / FinancialYear', () {
    test('period of a date and its bounds', () {
      final ym = LocalDate(2026, 5, 10).yearMonth;
      expect(ym, YearMonth(2026, 5));
      expect(ym.firstDay, LocalDate(2026, 5, 1));
      expect(ym.lastDay, LocalDate(2026, 5, 31));
      expect(ym.next, YearMonth(2026, 6));
      expect(YearMonth(2026, 12).next, YearMonth(2027, 1));
      expect(ym.contains(LocalDate(2026, 5, 31)), isTrue);
      expect(ym.contains(LocalDate(2026, 6, 1)), isFalse);
    });

    test('financial year defaults to 1 April – 31 March (02 §1.1)', () {
      final fy = FinancialYear.of(LocalDate(2026, 4, 1));
      expect(fy.startYear, 2026);
      expect(fy.firstDay, LocalDate(2026, 4, 1));
      expect(fy.lastDay, LocalDate(2027, 3, 31));
      expect(fy.label, '2026-27');
      expect(FinancialYear.of(LocalDate(2027, 3, 31)).startYear, 2026);
      expect(FinancialYear.of(LocalDate(2027, 4, 1)).startYear, 2027);
      expect(fy.months.length, 12);
      expect(fy.months.first, YearMonth(2026, 4));
      expect(fy.months.last, YearMonth(2027, 3));
    });

    test('financial year start month is per book', () {
      final fy = FinancialYear.of(LocalDate(2026, 2, 1), startMonth: 1);
      expect(fy.startYear, 2026);
      expect(fy.label, '2026');
      expect(fy.lastDay, LocalDate(2026, 12, 31));
    });
  });

  group('Hlc', () {
    test('composes 48-bit physical ms and 16-bit counter (03 §1)', () {
      final h = Hlc.compose(physicalMs: 1725000000000, counter: 7);
      expect(h.physicalMs, 1725000000000);
      expect(h.counter, 7);
      expect(
        () => Hlc.compose(physicalMs: 1, counter: 1 << 16),
        throwsArgumentError,
      );
    });

    test('tick is monotonic with an injected physical clock', () {
      final h0 = Hlc.compose(physicalMs: 1000, counter: 0);
      final h1 = h0.tick(physicalMs: 1000); // same ms → counter bumps
      expect(h1.physicalMs, 1000);
      expect(h1.counter, 1);
      final h2 = h1.tick(physicalMs: 900); // clock went backwards → stays ahead
      expect(h2 > h1, isTrue);
      expect(h2.physicalMs, 1000);
      final h3 = h2.tick(physicalMs: 2000);
      expect(h3.physicalMs, 2000);
      expect(h3.counter, 0);
    });

    test('event order is (hlc, id) — deterministic tiebreak', () {
      expect(
        compareEventOrder(const Hlc(1), 'b', const Hlc(2), 'a') < 0,
        isTrue,
      );
      expect(
        compareEventOrder(const Hlc(2), 'a', const Hlc(2), 'b') < 0,
        isTrue,
      );
      expect(compareEventOrder(const Hlc(2), 'a', const Hlc(2), 'a'), 0);
    });
  });
}
