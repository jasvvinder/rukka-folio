// F1-07-220…225: `LedgerYearCloseSource` and `LedgerClosedYearsSource` over the
// **real** ledger — the seam S10.4 has been drawn against a fake all phase, now
// run against a projection (02 §8.1 🔒, ADR 2026-09-05c §3 🔒, ADR 2026-09-05e
// §2, ADR 2026-09-09 §4 🔒).
//
// The point of these tests is that the adapter **decides nothing**: the
// blockers are the engine's, the vector is the projector's, the refusal is the
// facade's carried across unchanged, and the certified years are empty until a
// year actually closes — which is what makes *no FY switcher at all* true by
// construction.
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/close/ledger_year_close_source.dart';
import 'package:rukka_folio/features/close/year_close_source.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/closed_years.dart';

import '../../shared/test_app.dart';

/// 10 May 2027 — FY 2026-27 is wholly past, so every month of it can be locked
/// while *today* stays in the open FY 2027-28.
DateTime _may2027() => DateTime(2027, 5, 10, 10);

void main() {
  late LocalLedger ledger;
  late LedgerYearCloseSource source;
  late String bookId;
  late String cashId;
  late String fuelId;
  late FinancialYear fy;

  setUp(() async {
    ledger = await openTestLedger(now: _may2027);
    await ledger.bootstrapSolo(
      firstBookName: 'Me',
      startDate: LocalDate(2026, 4, 1),
    );
    bookId = (await ledger.mirror.bookIds()).single;
    source = LedgerYearCloseSource(ledger);
    fy = FinancialYear(2026, startMonth: 4);

    cashId = (await ledger.addAccount(
      bookId,
      name: 'Cash in hand',
      accountClass: AccountClass.money,
      subtype: MoneySubtype.cash,
    )).id;
    fuelId = (await ledger.addAccount(
      bookId,
      name: 'Diesel',
      accountClass: AccountClass.categoryExpense,
    )).id;
    await ledger.openingBalances(
      bookId,
      balances: {cashId: 2_500_000},
      date: LocalDate(2026, 4, 1),
    );
    await ledger.moneyOut(
      bookId: bookId,
      from: cashId,
      forWhat: fuelId,
      paise: 240_000,
      date: LocalDate(2026, 6, 15),
      note: 'Diesel',
    );
  });

  Future<void> lockEveryMonth() async {
    for (final m in fy.months) {
      await ledger.lockMonth(bookId, m, declaredBalances: const {});
    }
  }

  test('F1-07-220 the checklist is the ENGINE\'s: every unlocked month of the '
      'year comes back as a monthOpen blocker naming the month, and nothing '
      'can be certified while one stands (02 §8.1 🔒)', () async {
    final view = await source.loadYearClose(bookId, fy);
    expect(view.bookName, 'Me');
    expect(view.financialYear, fy);
    expect(view.status, YearStatus.open);
    expect(view.canCertify, isFalse);
    expect(view.openMonths, hasLength(12));
    expect(view.openMonths.first, YearMonth(2026, 4));
    expect(
      view.blockers.every((b) => b.kind == CloseBlocker.monthOpen),
      isTrue,
    );
  });

  test('F1-07-221 the vector shown before the action is the PROJECTOR\'s — the '
      'same bytes `closingVector` produced, balance-sheet accounts only and '
      'one net-result line (ADR 2026-09-05e §2 🔒, 03 §3.3 rule 2)', () async {
    await lockEveryMonth();
    final view = await source.loadYearClose(bookId, fy);
    expect(view.canCertify, isTrue);
    final shown = view.vector;
    expect(shown, isNotNull);
    expect(shown!.vector, await ledger.yearClosingVector(bookId, fy));
    expect(shown.isBalanced, isTrue);
    expect(shown.vector.nonZero.containsKey(fuelId), isFalse);
    // Names come from the chart, so the table says *Cash in hand*, not an id.
    expect(shown.names[cashId], 'Cash in hand');
    expect(shown.lines.where((l) => l.isNetResult), hasLength(1));
  });

  test('F1-07-222 closeYear publishes the signed close and hands back this '
      'device\'s own verification, read out of the rebuilt projection '
      '(ADR 2026-09-05c §3 🔒)', () async {
    await lockEveryMonth();
    final result = await source.closeYear(bookId, fy);
    expect(result.close.financialYear, fy);
    expect(result.close.projectorVersion, projectorVersion);
    expect(result.verification, CloseVerification.verified);

    final after = await source.loadYearClose(bookId, fy);
    expect(after.status, YearStatus.closed);
    expect(after.certifiedVector?.vector, result.close.vector);
    expect(after.verification, CloseVerification.verified);
    // A sealed year offers no fresh preview to certify again.
    expect(after.vector, isNull);
  });

  test('F1-07-223 the facade\'s typed refusals arrive as the seam\'s '
      'YearCloseRefused, carrying the engine\'s own items — never a message '
      'this layer invented', () async {
    await expectLater(
      source.closeYear(bookId, fy),
      throwsA(
        isA<YearCloseRefused>().having(
          (e) => e.blockers.map((b) => b.kind).toSet(),
          'blockers',
          contains(CloseBlocker.monthOpen),
        ),
      ),
    );
    // And a second close of a sealed year is refused too, with nothing to
    // list: the screen re-reads and finds the certificate (07 §1 rule 6).
    await lockEveryMonth();
    await source.closeYear(bookId, fy);
    await expectLater(
      source.closeYear(bookId, fy),
      throwsA(isA<YearCloseRefused>()),
    );
  });

  test('F1-07-224 certifiedYears is empty until a year actually closes — which '
      'is what makes *no FY switcher at all* true by construction '
      '(ADR 2026-09-09 §4 🔒)', () async {
    expect(await source.certifiedYears(bookId), isEmpty);
    await lockEveryMonth();
    expect(await source.certifiedYears(bookId), isEmpty);
    await source.closeYear(bookId, fy);
    final years = await source.certifiedYears(bookId);
    expect(years, hasLength(1));
    expect(years.single.year, fy);
    expect(years.single.isCertified, isTrue);
    expect(years.single.verification, CloseVerification.verified);
    expect(years.single.carriedForward, Paise(2_500_000));
  });

  testWidgets('F1-07-225 LedgerClosedYearsSource gives the switcher one A/C\'s '
      'b/f out of the certified vector and the book\'s total for a report, and '
      'both scopes hand the real sources down the tree', (tester) async {
    await lockEveryMonth();
    await source.closeYear(bookId, fy);

    final closedYears = LedgerClosedYearsSource(ledger);
    final forAccount = await closedYears(bookId, cashId);
    expect(forAccount, hasLength(1));
    expect(forAccount.single.year, fy);
    // The A/C's own certified closing balance, not a figure recomputed later.
    expect(forAccount.single.carriedForwardPaise, 2_500_000 - 240_000);
    // S8.2 passes an empty account id: a report is a whole book.
    final forBook = await closedYears(bookId, '');
    expect(forBook.single.carriedForwardPaise, 2_500_000);

    // The mount the shell makes (bootstrap.dart): both scopes above the
    // router, each taking only the live ledger.
    late BuildContext inner;
    await tester.pumpWidget(
      YearCloseScope(
        source: source,
        child: ClosedYearsScope(
          source: closedYears.call,
          child: Builder(
            builder: (context) {
              inner = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(YearCloseScope.maybeOf(inner), same(source));
    expect(ClosedYearsScope.maybeOf(inner), isNotNull);
    expect(
      await ClosedYearsScope.maybeOf(inner)!(bookId, cashId),
      hasLength(1),
    );
  });
}
