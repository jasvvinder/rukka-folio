// A-09b-4 — owner takeout in a *Just me* business posts `Dr Drawings · Cr money`
// through the ordinary Money out verb (02 §7.1, ADR 2026-09-09b §3, 07 §5
// "Owner's drawings" 🔒). Synthetic data only; amounts are the reference's.
import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('A-09b-4 owner takeout is a drawing, never an expense', () {
    late TestBook book;
    late Account cash; // Business Cash A/c
    late Account bank; // Indian Bank Current A/c
    late Account drawings;
    late Account opening;
    late Account adjustments;
    late Account suspense;
    late Account profitDistributed;
    late Account due;
    late Account rent;
    late Chart chart;

    setUp(() {
      book = TestBook('b1', bookType: BookType.business);
      cash = book.cash('Business Cash A/c');
      bank = book.money(
        'Indian Bank Current A/c',
        subtype: MoneySubtype.current,
      );
      drawings = book.acct(
        'Drawings A/c',
        AccountClass.equitySystem,
        systemRole: SystemRole.drawings,
      );
      opening = book.openingBalance();
      adjustments = book.adjustments();
      suspense = book.suspense();
      profitDistributed = book.profitDistributed();
      due = book.dueToFrom('b2');
      rent = book.expense('Shop rent');
      chart = book.chart;
    });

    /// The three reference drawings: sharma B-022 (₹25,000, Cr Business Cash),
    /// sharma B-031 (₹30,000, Cr Indian Bank) and standards §4.2 B11 (₹5,000,
    /// Cr Business Cash).
    List<(String, Account, int)> reference() => [
      ('B-022', cash, 25000),
      ('B-031', bank, 30000),
      ('B11', cash, 5000),
    ];

    test('A-09b-4 Verbs.moneyOut → Dr Drawings · Cr money for B-022, B-031 and B11', () {
      for (final (voucher, money, rupees) in reference()) {
        expect(
          Verbs.moneyOut(from: money, forWhat: drawings, amount: rs(rupees)),
          [dr(drawings, rs(rupees)), cr(money, rs(rupees))],
          reason: voucher,
        );
      }
    });

    test('A-09b-4 the money_out posting passes checkShape and every universal invariant', () {
      for (final (voucher, money, rupees) in reference()) {
        final e = book.entry(
          Verbs.moneyOut(from: money, forWhat: drawings, amount: rs(rupees)),
          kind: EntryKind.moneyOut,
        );
        expect(checkShape(e, chart), isNull, reason: voucher);
        expect(checkUniversalInvariants(e, chart), isEmpty, reason: voucher);
      }
    });

    test('A-09b-4 drawings sit outside the P&L: net profit unchanged, Drawings 55,000 Dr as sharma row 286', () {
      final fy = FinancialYear(2026);
      // One real expense so the FY has a result to leave untouched.
      final expense = book.entry(
        Verbs.moneyOut(from: cash, forWhat: rent, amount: rs(1000)),
        kind: EntryKind.moneyOut,
        date: d(2026, 6, 1),
      );
      final before = project([expense], chart);
      final profitBefore = netProfit(before, chart, fy);
      expect(profitBefore, -rs(1000));

      final b022 = book.entry(
        Verbs.moneyOut(from: cash, forWhat: drawings, amount: rs(25000)),
        kind: EntryKind.moneyOut,
        date: d(2026, 6, 30),
      );
      final b031 = book.entry(
        Verbs.moneyOut(from: bank, forWhat: drawings, amount: rs(30000)),
        kind: EntryKind.moneyOut,
        date: d(2026, 8, 26),
      );
      final after = project([expense, b022, b031], chart);
      expect(after.quarantined, isEmpty);
      expect(netProfit(after, chart, fy), profitBefore);
      expect(after.balances[drawings.id], rs(55000)); // Dr, as the reference
      expect(after.balances[cash.id], -rs(26000));
      expect(after.balances[bank.id], -rs(30000));
      // Drawings is carried on the balance-sheet side of the closing vector,
      // never folded into the year's net_result line — which holds only the
      // ₹1,000 loss, ledger-signed (Dr), so the vector still sums to zero.
      final closing = closingVector(after, chart, fy);
      expect(closing[drawings.id], rs(55000));
      expect(closing[netResultKey(fy)], rs(1000));
      expect(closing.totalDebits, closing.totalCredits);
    });

    test('A-09b-4 every other equity_system role is refused on both sides — verb and checkShape', () {
      final others = <Account>[
        opening,
        adjustments,
        suspense,
        profitDistributed,
        due,
      ];
      expect(
        others.map((a) => a.systemRole).toSet(),
        SystemRole.values.toSet().difference({SystemRole.drawings}),
        reason: 'the test must name every non-drawings role 02 line 29 lists',
      );
      for (final a in others) {
        // Constructor side: the verb refuses the slot (02 §2 "cannot be gotten wrong").
        expect(
          () => Verbs.moneyOut(from: cash, forWhat: a, amount: rs(1)),
          throwsArgumentError,
          reason: 'verb · ${a.systemRole!.name}',
        );
        // Reader side: a hand-built money_out with that debit is a shape violation.
        final e = book.entry([
          dr(a, rs(1)),
          cr(cash, rs(1)),
        ], kind: EntryKind.moneyOut);
        expect(
          checkShape(e, chart)?.kind,
          ViolationKind.shapeViolation,
          reason: 'checkShape · ${a.systemRole!.name}',
        );
      }
      // And the plain-expense path is untouched.
      expect(
        checkShape(
          book.entry(
            Verbs.moneyOut(from: cash, forWhat: rent, amount: rs(1)),
            kind: EntryKind.moneyOut,
          ),
          chart,
        ),
        isNull,
      );
    });
  });
}
