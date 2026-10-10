// F1-200-21…26: S10 declares the balances **at the end of the month being
// closed**, not the live ones (02 §8 step 4 🔒, PLAN desk 200 (e)) — while
// steps 1–2 keep showing the live figure the closer counts and checks against
// (02 §8 steps 1–2 🔒), the same one S5.5 counts against.
//
// 02 §8 🔒: a late arrival "counts in every live balance the moment it lands
// but leaves the certified month untouched", and 02 §8.1 🔒 restricts the
// year's vector to entries whose `accounting_date` ≤ the FY's last day. A
// month close that declared the live balance would certify August with
// September's money in it — which is what the R2B capture of S10 closing
// August on 1 Sep showed. But the cash box and the bank's app hold *today's*
// money, so steps 1–2 must show today's figure, and step 4 says which day its
// figures are for.
//
// F1-200-21…25 run over a **real `LocalLedger`** (in-memory SQLite,
// FakeKeyStore, injected clock 7 Sep 2026): a fake `CloseSource` would hand
// back whatever figure it was given and prove nothing. F1-200-26 is the
// screen half, over the feature fake, because what it asserts is what the
// widget draws from a [CloseView]. Amounts are synthetic (CLAUDE.md rule 4)
// and integer paise end to end (rule 1).
import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/close/close_routes.dart';
import 'package:rukka_folio/features/close/ledger_close_source.dart';
import 'package:rukka_folio/features/close/widgets/close_parts.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/format/date_format.dart';
import 'package:rukka_folio/shared/format/money_format.dart';

import '../../shared/test_app.dart';

void main() {
  // `seedSoloLedger` opens the book on 31 Aug with Cash 25,000 and SBI
  // 1,00,000, then posts five entries dated 2–7 Sep that move both.
  final august = YearMonth(2026, 8);
  final september = YearMonth(2026, 9);
  const cashAtAugEnd = 2500000;
  const bankAtAugEnd = 10000000;

  group('over the real ledger', () {
    late SeededLedger s;
    late LedgerCloseSource real;

    setUp(() async {
      s = await seedSoloLedger();
      real = LedgerCloseSource(s.ledger);
    });

    CloseCashAccount cashOf(CloseView v) =>
        v.cashAccounts.firstWhere((a) => a.accountId == s.cashId);
    CloseBankAccount bankOf(CloseView v) =>
        v.bankAccounts.firstWhere((a) => a.accountId == s.bankId);

    Future<Map<String, int>> live() async => {
      for (final r in await s.ledger.watchAccounts(s.bookId).first)
        r.account.id: r.balancePaise,
    };

    test('F1-200-21 entries dated in the next month do not change the figures '
        'S10 declares for the month being closed — on step 4 or on the lock '
        '(02 §8 step 4 🔒)', () async {
      // The precondition the test rests on: the live balances have moved.
      final now = await live();
      expect(now[s.cashId], isNot(cashAtAugEnd));
      expect(now[s.bankId], isNot(bankAtAugEnd));

      final view = await real.loadClose(s.bookId, august);
      expect(cashOf(view).monthEndBalance, const Paise(cashAtAugEnd));
      expect(bankOf(view).monthEndBalance, const Paise(bankAtAugEnd));
      expect(view.declaredBalances[s.cashId], const Paise(cashAtAugEnd));
      expect(view.declaredBalances[s.bankId], const Paise(bankAtAugEnd));

      // One more September entry — still not August's money.
      await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.bankId,
        forWhat: s.fuelId,
        paise: 123400,
        date: LocalDate(2026, 9, 1),
      );
      final again = await real.loadClose(s.bookId, august);
      expect(again.declaredBalances, view.declaredBalances);

      // And what the signed lock records is the same as-of figure.
      final locked = await real.lock(
        bookId: s.bookId,
        period: august,
        declaredBalances: again.declaredBalances,
      );
      expect(
        locked.lock.declaredBalances![s.cashId],
        const Paise(cashAtAugEnd),
      );
      expect(
        locked.lock.declaredBalances![s.bankId],
        const Paise(bankAtAugEnd),
      );
    });

    test('F1-200-22 the boundary: an entry on the period\'s last day is in '
        'the declared figure, one on the next day is not', () async {
      await s.ledger.moneyIn(
        bookId: s.bookId,
        into: s.cashId,
        from: s.salesId,
        paise: 70000,
        date: august.lastDay,
        note: 'last-day takings',
      );
      await s.ledger.moneyIn(
        bookId: s.bookId,
        into: s.cashId,
        from: s.salesId,
        paise: 9900,
        date: september.firstDay,
        note: 'first-day takings',
      );
      final view = await real.loadClose(s.bookId, august);
      expect(cashOf(view).monthEndBalance, const Paise(cashAtAugEnd + 70000));
      expect(bankOf(view).monthEndBalance, const Paise(bankAtAugEnd));
    });

    test('F1-200-23 with nothing dated after the period the month-end figure '
        'is the live balance', () async {
      final view = await real.loadClose(s.bookId, september);
      final now = await live();
      expect(cashOf(view).monthEndBalance.raw, now[s.cashId]);
      expect(bankOf(view).monthEndBalance.raw, now[s.bankId]);
      expect(cashOf(view).bookBalance, cashOf(view).monthEndBalance);
    });

    test('F1-200-24 steps 1–2 show the live figure — the one S5.5 counts '
        'against and the bank\'s app shows — not the month-end one '
        '(02 §8 steps 1–2 🔒)', () async {
      final view = await real.loadClose(s.bookId, august);
      final now = await live();
      final sheet = await s.ledger.cashCountReading(s.cashId);

      // Step 1's door and the sheet it opens show the same book.
      expect(cashOf(view).bookBalance, sheet.bookBalance);
      expect(cashOf(view).bookBalance.raw, now[s.cashId]);
      // Step 2 checks today's balance against today's bank.
      expect(bankOf(view).bookBalance.raw, now[s.bankId]);
      // The two figures genuinely differ here, so the line is not vacuous.
      expect(cashOf(view).bookBalance, isNot(cashOf(view).monthEndBalance));
      expect(bankOf(view).bookBalance, isNot(bankOf(view).monthEndBalance));
    });

    test('F1-200-25 the month-end figure keeps what `balances` holds and '
        '`entry_lines_p` does not — the shape a seeded rebuild leaves '
        '(03 §3.3 rule 3) — so it subtracts, never sums from zero', () async {
      // A seeded rebuild carries a certified vector in `balances` with the
      // archived year's lines absent from Layer 2 (Recompute.verifyBalances:
      // balances = seed + Σ lines). Building one through the facade needs a
      // closed financial year, so this stands in for it the way the data
      // layer's own invariant describes: drop the opening entries' Layer 2
      // rows and leave `balances` as it was.
      final db = s.ledger.db;
      final upTo = Variable.withString(august.lastDay.toIso());
      final book = Variable.withString(s.bookId);
      final before = await live();
      await db.customStatement(
        'DELETE FROM entry_lines_p WHERE book_id = ? AND accounting_date <= ?',
        [s.bookId, august.lastDay.toIso()],
      );
      await db.customStatement(
        'DELETE FROM entries_p WHERE book_id = ? AND accounting_date <= ?',
        [s.bookId, august.lastDay.toIso()],
      );
      expect(await live(), before, reason: '`balances` keeps the seed');

      final view = await real.loadClose(s.bookId, august);
      expect(cashOf(view).monthEndBalance, const Paise(cashAtAugEnd));
      expect(bankOf(view).monthEndBalance, const Paise(bankAtAugEnd));

      // The test can tell the two implementations apart: summing the lines
      // dated ≤ 31 Aug from zero now gives a different answer.
      final summed = {
        for (final r
            in await db
                .customSelect(
                  'SELECT l.account_id AS a, SUM(l.amount_paise) AS s '
                  'FROM entry_lines_p l JOIN entries_p e ON e.id = l.entry_id '
                  'WHERE l.book_id = ? AND e.accounting_date <= ? '
                  "AND e.status IN ('posted','void') GROUP BY l.account_id",
                  variables: [book, upTo],
                )
                .get())
          r.read<String>('a'): r.read<int>('s'),
      };
      expect(summed[s.cashId] ?? 0, isNot(cashAtAugEnd));
      expect(summed[s.bankId] ?? 0, isNot(bankAtAugEnd));
    });
  });

  // ── the screen half ────────────────────────────────────────────────────────

  testWidgets('F1-200-26 S10 shows the live figure with the month-end one '
      'beside it at steps 1–2, dates step 4, and locks at the month-end '
      'figures', (tester) async {
    const cash = CloseCashAccount(
      accountId: 'cash',
      name: 'Cash in hand',
      bookBalance: Paise(2160000),
      monthEndBalance: Paise(1760000),
    );
    const sbi = CloseBankAccount(
      accountId: 'sbi',
      name: 'SBI Saving',
      bookBalance: Paise(11460000),
      monthEndBalance: Paise(11860000),
    );
    const pnb = CloseBankAccount(
      accountId: 'pnb',
      name: 'PNB Current',
      bookBalance: Paise(3200000),
    );
    final source = FakeCloseSource(
      view: CloseView(
        bookId: 'book-1',
        bookName: 'Kirana',
        period: august,
        cashAccounts: const [cash],
        bankAccounts: const [sbi, pnb],
        tray: const CloseTray(),
      ),
    );
    await pumpRk(
      tester,
      MonthCloseScreen(bookId: 'book-1', period: august, source: source),
      viewport: rkTallViewport,
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(MonthCloseScreen)),
    );
    const en = Locale('en');
    String rs(int p) => formatPaise(p, locale: en);
    final lastDay = formatLedgerDate(august.lastDay, strings: l);

    // Step 1: today's figure, and the month's under it.
    expect(find.text(l.closeCashBookBalance(rs(2160000))), findsOneWidget);
    expect(
      find.text(l.closeBalanceMonthEnd(rs(1760000), lastDay)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(CloseKeys.next));
    await tester.pumpAndSettle();
    // Step 2: likewise — and no month-end line where the two agree.
    expect(find.text(l.closeBankBookBalance(rs(11460000))), findsOneWidget);
    expect(
      find.text(l.closeBalanceMonthEnd(rs(11860000), lastDay)),
      findsOneWidget,
    );
    expect(find.text(l.closeBankBookBalance(rs(3200000))), findsOneWidget);
    expect(
      find.text(l.closeBalanceMonthEnd(rs(3200000), lastDay)),
      findsNothing,
    );

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(CloseKeys.next));
      await tester.pumpAndSettle();
    }
    // Step 4: dated, and the month-end figures only.
    expect(find.text(l.closeStep4Help(lastDay)), findsOneWidget);
    final declared = find.byKey(CloseKeys.declared);
    expect(
      find.descendant(of: declared, matching: find.text(rs(1760000))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: declared, matching: find.text(rs(2160000))),
      findsNothing,
    );
    // What the screen hands the lock is the month-end set, not today's.
    await tester.ensureVisible(find.byKey(CloseKeys.lock));
    await tester.tap(find.byKey(CloseKeys.lock));
    await tester.pumpAndSettle();
    expect(source.lockedWith, [
      {
        'cash': const Paise(1760000),
        'sbi': const Paise(11860000),
        'pnb': const Paise(3200000),
      },
    ]);
  });
}
