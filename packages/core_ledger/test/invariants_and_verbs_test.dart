// Suite A — universal invariants (02 §1.4) and the six verbs' fixed postings (02 §2, §11).
import 'dart:math';

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final book = TestBook('b1');
  final cash = book.cash('Cash');
  final bank = book.money('SBI');
  final od = book.money('OD', subtype: MoneySubtype.od);
  final cc = book.money('Card', subtype: MoneySubtype.cc);
  final verma = book.party('Verma Dairy');
  final dairy = book.expense('Dairy Expense');
  final salary = book.income('Salary');
  final opening = book.openingBalance();
  final adjustments = book.adjustments();
  final gollak = book.acct(
    'Gollak',
    AccountClass.money,
    subtype: MoneySubtype.cashCollection,
  );
  final chart = book.chart;

  final other = TestBook('b2');
  final foreignCash = other.cash('Cash');

  group('universal invariants', () {
    test('a balanced two-line entry has no violations', () {
      final e = book.entry([dr(dairy, rs(100)), cr(cash, rs(100))]);
      expect(checkUniversalInvariants(e, chart), isEmpty);
    });

    test('lines must sum to zero', () {
      final e = book.entry([dr(dairy, rs(100)), cr(cash, rs(99))]);
      expect(
        checkUniversalInvariants(e, chart).map((v) => v.kind),
        contains(ViolationKind.linesUnbalanced),
      );
    });

    test('at least two lines, every line non-zero', () {
      final one = book.entry([dr(dairy, Paise.zero)]);
      final kinds = checkUniversalInvariants(
        one,
        chart,
      ).map((v) => v.kind).toSet();
      expect(
        kinds,
        containsAll([ViolationKind.tooFewLines, ViolationKind.zeroLine]),
      );
    });

    test('every account belongs to the entry book (rule 3)', () {
      // An entry claiming to belong to b2 while posting to b1's accounts.
      final e = Entry(
        id: 'x',
        bookId: 'b2',
        kind: EntryKind.moneyOut,
        status: EntryStatus.posted,
        reviewRequired: false,
        accountingDate: d(2026, 5, 1),
        lines: [dr(dairy, rs(5)), cr(cash, rs(5))],
        createdByUser: 'u',
        createdByDevice: 'd',
        hlc: const Hlc(1),
      );
      expect(
        checkUniversalInvariants(e, chart).map((v) => v.kind),
        contains(ViolationKind.accountNotInBook),
      );
      expect(
        checkUniversalInvariants(
          book.entry([dr(foreignCash, rs(5)), cr(cash, rs(5))]),
          chart,
        ).map((v) => v.kind),
        contains(ViolationKind.unknownAccount),
        reason: 'another book\'s account is simply unknown to this chart',
      );
      final unknown = book.entry([
        Line(accountId: 'nope', amount: rs(5)),
        cr(cash, rs(5)),
      ]);
      expect(
        checkUniversalInvariants(unknown, chart).map((v) => v.kind),
        contains(ViolationKind.unknownAccount),
      );
    });

    test('INR only in Phase 1 (rule 5)', () {
      final e = book
          .entry([dr(dairy, rs(1)), cr(cash, rs(1))])
          .copyWith(currency: 'USD');
      expect(
        checkUniversalInvariants(e, chart).map((v) => v.kind),
        contains(ViolationKind.currencyUnsupported),
      );
    });

    test('pending is only for advance requests (02 §1.3)', () {
      final e = book.entry([
        dr(dairy, rs(1)),
        cr(cash, rs(1)),
      ], status: EntryStatus.pending);
      expect(
        checkUniversalInvariants(e, chart).map((v) => v.kind),
        contains(ViolationKind.pendingNotAdvance),
      );
    });

    test(
      'readers re-check review_required against the carried limit (03 §3.3.5)',
      () {
        final e = book.entry([
          dr(dairy, rs(7000)),
          cr(cash, rs(7000)),
        ], reviewLimit: rs(5000));
        expect(
          checkUniversalInvariants(e, chart).map((v) => v.kind),
          contains(ViolationKind.reviewFlagMissing),
        );
        final ok = book.entry(
          [dr(dairy, rs(7000)), cr(cash, rs(7000))],
          reviewLimit: rs(5000),
          reviewRequired: true,
        );
        expect(checkUniversalInvariants(ok, chart), isEmpty);
        final noLimit = book.entry([dr(dairy, rs(7000)), cr(cash, rs(7000))]);
        expect(
          checkUniversalInvariants(noLimit, chart),
          isEmpty,
          reason: 'no limit in force → never flagged',
        );
      },
    );

    test('authoring: accounting_date may be backdated but never in the future (rule 6)', () {
      final today = d(2026, 5, 10);
      final back = book.entry([
        dr(dairy, rs(1)),
        cr(cash, rs(1)),
      ], date: d(2026, 4, 2));
      expect(checkAuthoringRules(back, today: today), isEmpty);
      final future = book.entry([
        dr(dairy, rs(1)),
        cr(cash, rs(1)),
      ], date: d(2026, 5, 11));
      expect(
        checkAuthoringRules(future, today: today).map((v) => v.kind),
        contains(ViolationKind.futureDate),
      );
    });
  });

  group('verbs → postings (02 §2)', () {
    test('1 Money in from an income category: Dr money · Cr income', () {
      final lines = Verbs.moneyIn(into: bank, from: salary, amount: rs(95000));
      expect(lines, [dr(bank, rs(95000)), cr(salary, rs(95000))]);
    });

    test('1 Money in from a party: Cr party (their udhaar shrinks / your payable grows)', () {
      expect(Verbs.moneyIn(into: cash, from: verma, amount: rs(500)), [
        dr(cash, rs(500)),
        cr(verma, rs(500)),
      ]);
    });

    test('2 Money out for an expense: Dr expense · Cr money', () {
      expect(Verbs.moneyOut(from: cash, forWhat: dairy, amount: rs(250)), [
        dr(dairy, rs(250)),
        cr(cash, rs(250)),
      ]);
    });

    test('2 Money out to a party: Dr party · Cr money', () {
      expect(Verbs.moneyOut(from: bank, forWhat: verma, amount: rs(500)), [
        dr(verma, rs(500)),
        cr(bank, rs(500)),
      ]);
    });

    test('3 Gave on credit: Dr party · Cr money or income', () {
      expect(Verbs.gaveCredit(toWhom: verma, gave: cash, amount: rs(20000)), [
        dr(verma, rs(20000)),
        cr(cash, rs(20000)),
      ]);
      expect(Verbs.gaveCredit(toWhom: verma, gave: salary, amount: rs(1)), [
        dr(verma, rs(1)),
        cr(salary, rs(1)),
      ]);
    });

    test('4 Took on credit: Dr money or expense · Cr party', () {
      expect(Verbs.tookCredit(fromWhom: verma, took: dairy, amount: rs(3500)), [
        dr(dairy, rs(3500)),
        cr(verma, rs(3500)),
      ]);
      expect(Verbs.tookCredit(fromWhom: verma, took: cash, amount: rs(40000)), [
        dr(cash, rs(40000)),
        cr(verma, rs(40000)),
      ]);
    });

    test('verbs 3/4 with the money answer equal verbs 1/2 with a party — both doors kept', () {
      expect(
        Verbs.gaveCredit(toWhom: verma, gave: cash, amount: rs(9)),
        Verbs.moneyOut(from: cash, forWhat: verma, amount: rs(9)),
      );
      expect(
        Verbs.tookCredit(fromWhom: verma, took: cash, amount: rs(9)),
        Verbs.moneyIn(into: cash, from: verma, amount: rs(9)),
      );
    });

    test('5 Transfer within a book: Dr to · Cr from; a card payment is Dr CC · Cr bank', () {
      expect(Verbs.transfer(from: bank, to: cash, amount: rs(40000)), [
        dr(cash, rs(40000)),
        cr(bank, rs(40000)),
      ]);
      expect(Verbs.transfer(from: bank, to: cc, amount: rs(12400)), [
        dr(cc, rs(12400)),
        cr(bank, rs(12400)),
      ]);
    });

    test('6 Adjustment wizards only: opening balance, cash-count difference, write-off', () {
      // Money account opening +4,000 → Dr Cash · Cr Opening Balance.
      expect(
        Verbs.openingBalance(
          account: cash,
          balance: rs(4000),
          openingAccount: opening,
        ),
        [dr(cash, rs(4000)), cr(opening, rs(4000))],
      );
      // Party you owe 2,800 (you will give) → Cr party · Dr Opening Balance.
      expect(
        Verbs.openingBalance(
          account: verma,
          balance: -rs(2800),
          openingAccount: opening,
        ),
        [cr(verma, rs(2800)), dr(opening, rs(2800))],
      );
      // Overdraft opening: negative money balance allowed.
      expect(
        Verbs.openingBalance(
          account: od,
          balance: -rs(10000),
          openingAccount: opening,
        ),
        [cr(od, rs(10000)), dr(opening, rs(10000))],
      );
      // Cash count found 230 less than the book: Cr Cash · Dr Adjustments.
      expect(
        Verbs.cashCountDifference(
          cash: cash,
          difference: -rs(230),
          adjustmentsAccount: adjustments,
        ),
        [cr(cash, rs(230)), dr(adjustments, rs(230))],
      );
      // Write off a party balance of 500 owed to you: Dr Adjustments · Cr party.
      expect(
        Verbs.writeOff(
          account: verma,
          balance: rs(500),
          adjustmentsAccount: adjustments,
        ),
        [dr(adjustments, rs(500)), cr(verma, rs(500))],
      );
    });

    test('class checks: the posting rule cannot be gotten wrong', () {
      expect(
        () => Verbs.moneyIn(into: dairy, from: salary, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.moneyIn(into: bank, from: cash, amount: rs(1)),
        throwsArgumentError,
        reason: 'money→money is a transfer',
      );
      expect(
        () => Verbs.moneyOut(from: verma, forWhat: dairy, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.gaveCredit(toWhom: dairy, gave: cash, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.tookCredit(fromWhom: verma, took: salary, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.transfer(from: bank, to: dairy, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.transfer(from: bank, to: bank, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.moneyIn(into: bank, from: salary, amount: Paise.zero),
        throwsArgumentError,
      );
      expect(
        () => Verbs.moneyIn(into: bank, from: salary, amount: -rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.openingBalance(
          account: cash,
          balance: rs(1),
          openingAccount: adjustments,
        ),
        throwsArgumentError,
      );
    });

    test('a collection account (gollak) is not a spending source; it empties only into cash/bank (02 §8.2)', () {
      expect(
        () => Verbs.moneyOut(from: gollak, forWhat: dairy, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.gaveCredit(toWhom: verma, gave: gollak, amount: rs(1)),
        throwsArgumentError,
      );
      expect(Verbs.transfer(from: gollak, to: cash, amount: rs(500)), [
        dr(cash, rs(500)),
        cr(gollak, rs(500)),
      ]);
      expect(Verbs.transfer(from: gollak, to: bank, amount: rs(500)), [
        dr(bank, rs(500)),
        cr(gollak, rs(500)),
      ]);
      expect(
        () => Verbs.transfer(from: gollak, to: cc, amount: rs(1)),
        throwsArgumentError,
      );
      expect(
        () => Verbs.transfer(from: cash, to: gollak, amount: rs(1)),
        throwsArgumentError,
        reason: 'nothing is paid into a box through the books',
      );
    });
  });

  group('02 §11 worked assertions', () {
    test('₹500 money out to a party you owe ₹2,000 → ₹1,500 you will give; no debtor asset', () {
      final e1 = book.entry(
        Verbs.tookCredit(fromWhom: verma, took: dairy, amount: rs(2000)),
        kind: EntryKind.tookCredit,
      );
      final e2 = book.entry(
        Verbs.moneyOut(from: cash, forWhat: verma, amount: rs(500)),
        kind: EntryKind.moneyOut,
      );
      final state = project([e1, e2], chart);
      expect(state.balances[verma.id], -rs(1500));
      expect(
        placementOf(chart.account(verma.id), state.balances[verma.id]),
        Placement.liability,
      );
    });

    test('OD at +₹10,000 then a ₹25,000 payment → −₹15,000, liabilities side, no error', () {
      final e1 = book.entry(
        Verbs.openingBalance(
          account: od,
          balance: rs(10000),
          openingAccount: opening,
        ),
        kind: EntryKind.adjustment,
      );
      final e2 = book.entry(
        Verbs.moneyOut(from: od, forWhat: dairy, amount: rs(25000)),
        kind: EntryKind.moneyOut,
      );
      final state = project([e1, e2], chart);
      expect(state.balances[od.id], -rs(15000));
      expect(
        placementOf(chart.account(od.id), state.balances[od.id]),
        Placement.liability,
      );
      expect(state.quarantined, isEmpty);
    });
  });

  group(
    'property: every verb × every input shape ⇒ invariants hold (09 §1)',
    () {
      final rng = Random(20260904);
      final moneyAccounts = [cash, bank, od, cc];
      final categoriesIn = [salary];
      final categoriesOut = [dairy];
      final parties = [verma];
      T pick<T>(List<T> xs) => xs[rng.nextInt(xs.length)];
      Paise amt() => Paise(1 + rng.nextInt(1 << 31));

      test(
        '1,000 generated postings all sum to zero, are integer paise, in-book',
        () {
          for (var i = 0; i < 1000; i++) {
            final List<Line> lines;
            switch (rng.nextInt(6)) {
              case 0:
                lines = Verbs.moneyIn(
                  into: pick(moneyAccounts),
                  from: pick([...categoriesIn, ...parties]),
                  amount: amt(),
                );
              case 1:
                lines = Verbs.moneyOut(
                  from: pick(moneyAccounts),
                  forWhat: pick([...categoriesOut, ...parties]),
                  amount: amt(),
                );
              case 2:
                lines = Verbs.gaveCredit(
                  toWhom: pick(parties),
                  gave: pick([...moneyAccounts, ...categoriesIn]),
                  amount: amt(),
                );
              case 3:
                lines = Verbs.tookCredit(
                  fromWhom: pick(parties),
                  took: pick([...moneyAccounts, ...categoriesOut]),
                  amount: amt(),
                );
              case 4:
                final from = pick(moneyAccounts);
                final to = pick(moneyAccounts.where((a) => a != from).toList());
                lines = Verbs.transfer(from: from, to: to, amount: amt());
              default:
                final signed = rng.nextBool() ? amt() : -amt();
                lines = Verbs.openingBalance(
                  account: pick([...moneyAccounts, ...parties]),
                  balance: signed,
                  openingAccount: opening,
                );
            }
            final e = book.entry(lines);
            expect(
              checkUniversalInvariants(e, chart),
              isEmpty,
              reason: 'iteration $i: $lines',
            );
            expect(Paise.sum(lines.map((l) => l.amount)), Paise.zero);
            expect(lines.length, greaterThanOrEqualTo(2));
          }
        },
      );
    },
  );
}
