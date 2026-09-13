// A-09b-5 — capital introduced posts `Dr money · Cr Opening Balance/Capital`
// through the ordinary Money in verb (02 §7.1, ADR 2026-09-13 §4, the exact
// twin of ADR 2026-09-09b §3's drawings ruling). Synthetic data only; amounts
// are the reference's.
import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('A-09b-5 capital introduced is Money in, never income', () {
    late TestBook book;
    late Account cash; // Business Cash A/c
    late Account bank; // Business Bank — HDFC
    late Account opening; // Opening Balance / Capital A/c
    late Account drawings;
    late Account adjustments;
    late Account suspense;
    late Account profitDistributed;
    late Account due;
    late Account sales;
    late Chart chart;

    setUp(() {
      book = TestBook('b1', bookType: BookType.business);
      cash = book.cash('Business Cash A/c');
      bank = book.money('Business Bank — HDFC', subtype: MoneySubtype.current);
      opening = book.openingBalance();
      drawings = book.acct(
        'Drawings A/c',
        AccountClass.equitySystem,
        systemRole: SystemRole.drawings,
      );
      adjustments = book.adjustments();
      suspense = book.suspense();
      profitDistributed = book.profitDistributed();
      due = book.dueToFrom('b2');
      sales = book.income('Sales');
      chart = book.chart;
    });

    test('A-09b-5 Verbs.moneyIn → Dr money · Cr Opening Balance/Capital for B01', () {
      // standards §4.1 B01 — "Owner adds capital", Dr HDFC · Cr Capital 5,000.
      expect(Verbs.moneyIn(into: bank, from: opening, amount: rs(5000)), [
        dr(bank, rs(5000)),
        cr(opening, rs(5000)),
      ], reason: 'B01');
      // And into cash, which is the same event through the other money a/c.
      expect(Verbs.moneyIn(into: cash, from: opening, amount: rs(5000)), [
        dr(cash, rs(5000)),
        cr(opening, rs(5000)),
      ]);
    });

    test('A-09b-5 the money_in posting passes checkShape and every universal invariant', () {
      final e = book.entry(
        Verbs.moneyIn(into: bank, from: opening, amount: rs(5000)),
        kind: EntryKind.moneyIn,
      );
      expect(checkShape(e, chart), isNull);
      expect(checkUniversalInvariants(e, chart), isEmpty);
    });

    test('A-09b-5 capital sits outside the P&L: net profit unchanged, Capital 5,000 Cr', () {
      final fy = FinancialYear(2026);
      // One real income line so the FY has a result to leave untouched.
      final sale = book.entry(
        Verbs.moneyIn(into: cash, from: sales, amount: rs(8000)),
        kind: EntryKind.moneyIn,
        date: d(2026, 6, 1),
      );
      final before = project([sale], chart);
      final profitBefore = netProfit(before, chart, fy);
      expect(profitBefore, rs(8000));

      final b01 = book.entry(
        Verbs.moneyIn(into: bank, from: opening, amount: rs(5000)),
        kind: EntryKind.moneyIn,
        date: d(2026, 6, 30),
      );
      final after = project([sale, b01], chart);
      expect(after.quarantined, isEmpty);
      // Capital introduced is not income: it must not move the year's result.
      expect(netProfit(after, chart, fy), profitBefore);
      expect(after.balances[opening.id], -rs(5000)); // Cr, as the reference
      expect(after.balances[bank.id], rs(5000));

      // Carried on the balance-sheet side of the closing vector, never folded
      // into net_result — which still holds only the ₹8,000 gain.
      final closing = closingVector(after, chart, fy);
      expect(closing[opening.id], -rs(5000));
      expect(closing[netResultKey(fy)], -rs(8000));
      expect(closing.totalDebits, closing.totalCredits);
    });

    test('A-09b-5 every other equity_system role is refused on both sides — verb and checkShape', () {
      final others = <Account>[
        drawings,
        adjustments,
        suspense,
        profitDistributed,
        due,
      ];
      expect(
        others.map((a) => a.systemRole).toSet(),
        SystemRole.values.toSet().difference({SystemRole.openingBalance}),
        reason: 'the test must name every non-opening-balance role 02 lists',
      );
      for (final a in others) {
        // Constructor side: the verb refuses the slot (02 §2 "cannot be gotten
        // wrong"). Before ADR 2026-09-13 §4 it accepted every one of these —
        // the twin of the drawings defect, and the reason this test exists.
        expect(
          () => Verbs.moneyIn(into: bank, from: a, amount: rs(1)),
          throwsArgumentError,
          reason: 'verb · ${a.systemRole!.name}',
        );
        // Reader side: a hand-built money_in with that credit is a shape
        // violation.
        final e = book.entry([
          dr(bank, rs(1)),
          cr(a, rs(1)),
        ], kind: EntryKind.moneyIn);
        expect(
          checkShape(e, chart)?.kind,
          ViolationKind.shapeViolation,
          reason: 'checkShape · ${a.systemRole!.name}',
        );
      }
      // And the plain-income path is untouched.
      expect(
        checkShape(
          book.entry(
            Verbs.moneyIn(into: cash, from: sales, amount: rs(1)),
            kind: EntryKind.moneyIn,
          ),
          chart,
        ),
        isNull,
      );
    });

    test('A-09b-5 the two verbs stay mirror images: one equity role each, and not each other\'s', () {
      // Money in admits Opening Balance/Capital and refuses Drawings;
      // Money out admits Drawings and refuses Opening Balance/Capital
      // (ADR 2026-09-09b §3, ADR 2026-09-13 §4).
      expect(
        () => Verbs.moneyIn(into: bank, from: drawings, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.moneyOut(from: bank, forWhat: opening, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        checkShape(
          book.entry([
            dr(drawings, rs(1)),
            cr(bank, rs(1)),
          ], kind: EntryKind.moneyOut),
          chart,
        ),
        isNull,
      );
      expect(
        checkShape(
          book.entry([
            dr(bank, rs(1)),
            cr(opening, rs(1)),
          ], kind: EntryKind.moneyIn),
          chart,
        ),
        isNull,
      );
    });
  });
}
