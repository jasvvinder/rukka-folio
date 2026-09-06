// Suite A — cash counts and note denominations (02 §8.2).
@Tags(['A'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final shop = TestBook('shop', bookType: BookType.business);
  final galla = shop.cash('Galla');
  final adjustments = shop.adjustments();
  final trust = TestBook('trust', bookType: BookType.organization);
  final gollak = trust.acct(
    'Gollak',
    AccountClass.money,
    subtype: MoneySubtype.cashCollection,
  );
  final trustCash = trust.cash('Cash');
  final donation = trust.income('Gollak Donation');
  final trustAdjustments = trust.adjustments();

  group('denomination sheet', () {
    test('A-02-83 sums notes and coins to the counted value', () {
      const sheet = DenominationSheet(
        notes: {500: 20, 200: 15, 100: 25},
        coinsPaise: Paise(1250),
      );
      expect(
        sheet.total,
        Paise.rupees(10000 + 3000 + 2500) + const Paise(1250),
      );
      expect(sheet.usesTwoThousand, isFalse);
      expect(const DenominationSheet(notes: {2000: 1}).usesTwoThousand, isTrue);
    });

    test('A-02-84 only INR denominations are accepted', () {
      expect(
        () => DenominationSheet(notes: const {300: 1}).total,
        throwsArgumentError,
      );
      expect(
        () => DenominationSheet(notes: const {500: -1}).total,
        throwsArgumentError,
      );
    });
  });

  group('policy (02 §8.2 🔒)', () {
    test('A-02-85 organization books: sheet always mandatory; collection accounts need two names', () {
      final p = countPolicy(bookType: BookType.organization, account: gollak);
      expect(p.denominationSheetMandatory, isTrue);
      expect(p.twoNamesRequired, isTrue);
      final c = countPolicy(
        bookType: BookType.organization,
        account: trustCash,
      );
      expect(c.denominationSheetMandatory, isTrue);
      expect(c.twoNamesRequired, isFalse);
    });

    test('A-02-86 other books: a single counted figure is always accepted', () {
      final p = countPolicy(bookType: BookType.business, account: galla);
      expect(p.denominationSheetMandatory, isFalse);
      expect(p.twoNamesRequired, isFalse);
    });

    test(
      'A-02-87 a collection account requires two names in every book type',
      () {
        final famBox = TestBook('fam').acct(
          'Donation box',
          AccountClass.money,
          subtype: MoneySubtype.cashCollection,
        );
        expect(
          countPolicy(
            bookType: BookType.family,
            account: famBox,
          ).twoNamesRequired,
          isTrue,
        );
      },
    );

    test('A-02-88 count validation enforces the policy and that a sheet matches the counted figure', () {
      final bare = CashCount(
        id: 'c1',
        bookId: 'trust',
        accountId: gollak.id,
        date: d(2026, 8, 27),
        counted: rs(62000),
        hlc: const Hlc(1),
      );
      final v = validateCount(
        bare,
        bookType: BookType.organization,
        account: gollak,
      ).map((x) => x.kind);
      expect(
        v,
        containsAll([
          ViolationKind.countSheetRequired,
          ViolationKind.countNamesRequired,
        ]),
      );
      final bad = CashCount(
        id: 'c2',
        bookId: 'trust',
        accountId: gollak.id,
        date: d(2026, 8, 27),
        counted: rs(62000),
        sheet: const DenominationSheet(notes: {500: 1}),
        countedBy: 'a',
        witness: 'b',
        hlc: const Hlc(2),
      );
      expect(
        validateCount(
          bad,
          bookType: BookType.organization,
          account: gollak,
        ).single.kind,
        ViolationKind.countSheetMismatch,
      );
      expect(
        () => CashCount(
          id: 'c3',
          bookId: 'shop',
          accountId: adjustments.id,
          date: d(2026, 8, 27),
          counted: rs(1),
          hlc: const Hlc(3),
        ).validateAgainst(adjustments),
        throwsArgumentError,
      );
    });
  });

  group('two kinds of count', () {
    test('A-02-89 cash: equal → no entry, account marked verified on date', () {
      final count = CashCount(
        id: 'c',
        bookId: 'shop',
        accountId: galla.id,
        date: d(2026, 8, 27),
        counted: rs(33000),
        hlc: const Hlc(9),
      );
      final outcome = resolveCount(
        count,
        account: galla,
        bookBalance: rs(33000),
        adjustmentsAccount: adjustments,
      );
      expect(outcome, isA<CountVerified>());
      expect(outcome.lines, isEmpty);
    });

    test('A-02-90 cash: different → one guided adjustment with the difference shown plainly', () {
      final count = CashCount(
        id: 'c',
        bookId: 'shop',
        accountId: galla.id,
        date: d(2026, 8, 31),
        counted: rs(32770),
        hlc: const Hlc(9),
      );
      final outcome = resolveCount(
        count,
        account: galla,
        bookBalance: rs(33000),
        adjustmentsAccount: adjustments,
      ) as CountAdjustment;
      expect(outcome.difference, -rs(230));
      expect(outcome.lines, [cr(galla, rs(230)), dr(adjustments, rs(230))]);
      final excess = resolveCount(
        CashCount(
          id: 'c2',
          bookId: 'shop',
          accountId: galla.id,
          date: d(2026, 8, 31),
          counted: rs(33100),
          hlc: const Hlc(10),
        ),
        account: galla,
        bookBalance: rs(33000),
        adjustmentsAccount: adjustments,
      ) as CountAdjustment;
      expect(excess.lines, [dr(galla, rs(100)), cr(adjustments, rs(100))]);
    });

    test('A-02-91 cash_collection: the count recognises income for the full counted amount', () {
      final count = CashCount(
        id: 'c',
        bookId: 'trust',
        accountId: gollak.id,
        date: d(2026, 8, 27),
        counted: rs(62000),
        sheet: const DenominationSheet(notes: {500: 100, 200: 50, 100: 20}),
        countedBy: 'Sewadar A',
        witness: 'Sewadar B',
        hlc: const Hlc(9),
      );
      final outcome = resolveCount(
        count,
        account: gollak,
        bookBalance: Paise.zero,
        adjustmentsAccount: trustAdjustments,
        incomeAccount: donation,
      ) as CountRecognition;
      expect(outcome.lines, [dr(gollak, rs(62000)), cr(donation, rs(62000))]);
      // The counted cash stays in the box: depositing later is an ordinary Transfer.
      expect(Verbs.transfer(from: gollak, to: trustCash, amount: rs(62000)), [
        dr(trustCash, rs(62000)),
        cr(gollak, rs(62000)),
      ]);
    });

    test(
      'A-02-92 cash_collection needs an income account; cash never takes one',
      () {
        final count = CashCount(
          id: 'c',
          bookId: 'trust',
          accountId: gollak.id,
          date: d(2026, 8, 27),
          counted: rs(1),
          hlc: const Hlc(9),
        );
        expect(
          () => resolveCount(
            count,
            account: gollak,
            bookBalance: Paise.zero,
            adjustmentsAccount: trustAdjustments,
          ),
          throwsArgumentError,
        );
        final shopCount = CashCount(
          id: 'c',
          bookId: 'shop',
          accountId: galla.id,
          date: d(2026, 8, 27),
          counted: rs(1),
          hlc: const Hlc(9),
        );
        expect(
          () => resolveCount(
            shopCount,
            account: galla,
            bookBalance: rs(1),
            adjustmentsAccount: adjustments,
            incomeAccount: donation,
          ),
          throwsArgumentError,
        );
      },
    );

    test('A-02-93 a count never moves money: the projector records it as a memo only', () {
      final cash = TestBook('p').cash('Cash');
      final book = TestBook('p');
      final c = book.cash('Cash');
      final count = CashCount(
        id: 'c',
        bookId: 'p',
        accountId: c.id,
        date: d(2026, 8, 27),
        counted: rs(500),
        hlc: const Hlc(9),
      );
      final s = project([count], book.chart);
      expect(s.balances[c.id], Paise.zero);
      expect(s.lastCount[c.id]!.date, d(2026, 8, 27));
      expect(cash.id, c.id);
    });
  });
}
