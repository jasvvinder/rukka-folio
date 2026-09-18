// F1-07-149: [LedgerCloseSource.closeStatuses] and
// [LedgerCloseSource.monthSummary] — S10.1's and S10.2's inputs, over a **real
// `LocalLedger`** (07 §13 🔒 bullets 4 and 6, 02 §8 🔒, 02 §8.1 🔒).
//
// The widget tests for S10.1, S10.2 and the Home close card run over the fake,
// which is the right seam for a screen. But the two rules these reads have to
// keep are ledger rules, not widget rules, and a fake cannot prove either:
//
//   * **months lock in order** (02 §8.1 🔒) — so the month a card offers is the
//     earliest *open* one, never simply the month that has just ended. Offering
//     a month the engine would refuse is the dead end 07 §1 rule 6 forbids.
//   * **money is integer paise** (CLAUDE.md rule 1) and the figures are the
//     projection's own (02 §9) — the summary re-reads `entries_p` /
//     `entry_lines_p`, it never re-derives a balance.
//
// In-memory SQLite, FakeKeyStore, injected clock (7 Sep 2026). Amounts are
// synthetic (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show AuthorGapsCompanion;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/close/close_source.dart';
import 'package:rukka_folio/features/close/ledger_close_source.dart';

import '../../shared/test_app.dart';

void main() {
  late SeededLedger s;
  late LedgerCloseSource real;

  // The clock reads 7 Sep 2026 and `seedSoloLedger` opens the book seven days
  // back, on 31 Aug — so **August** is the book's first month (it holds the
  // opening balances and nothing else) and September holds every entry.
  final july = YearMonth(2026, 7);
  final august = YearMonth(2026, 8);
  final september = YearMonth(2026, 9);
  final november = YearMonth(2026, 11);

  setUp(() async {
    s = await seedSoloLedger();
    real = LedgerCloseSource(s.ledger);
  });

  group('closeStatuses — S10.1 and the Home close card (07 §13 🔒)', () {
    test('F1-07-149 a book carries one status, on its earliest open month, and '
        'none at all for a month that predates the book', () async {
      // Asked about September, the card still offers **August**: that is the
      // first month the book existed in and it is still open (02 §8.1 🔒).
      final now = await real.closeStatuses(september);
      expect(now, hasLength(1));
      expect(now.single.bookId, s.bookId);
      expect(now.single.period, august);
      expect(now.single.state, BookCloseState.notStarted);
      expect(now.single.step, isNull);

      // ADR 2026-09-09d §4: the books begin on 31 Aug. A July card would
      // offer to close a month the book did not exist in.
      expect(await real.closeStatuses(july), isEmpty);
    });

    test('F1-07-149 months lock in order (02 §8.1 🔒): asking about November '
        'still offers August, the earliest month that is open', () async {
      final later = await real.closeStatuses(november);
      expect(later.single.period, august);
      expect(later.single.state, BookCloseState.notStarted);

      // Lock August and the offer moves on by itself — the card never has to
      // be told which month is next.
      final view = await real.loadClose(s.bookId, august);
      await real.lock(
        bookId: s.bookId,
        period: august,
        declaredBalances: view.declaredBalances,
      );
      final next = await real.closeStatuses(november);
      expect(next.single.period, september);
      expect(next.single.state, BookCloseState.notStarted);
    });

    test(
      'F1-07-149 saved progress makes the card resume at the step it reached '
      '(07 §13 *Resumable* 🔒)',
      () async {
        await real.saveProgress(
          s.bookId,
          august,
          const CloseProgress(
            step: CloseStep.clearTray,
            confirmedBankIds: {'sbi'},
          ),
        );
        final resumed = await real.closeStatuses(september);
        expect(resumed.single.state, BookCloseState.inProgress);
        expect(resumed.single.step, CloseStep.clearTray);
        expect(resumed.single.resumable, isTrue);
      },
    );

    test(
      'F1-07-149 an open author gap makes the book *waiting*, with no device '
      'name to print (ADR 2026-09-05b §3)',
      () async {
        final db = s.ledger.db;
        await db
            .into(db.authorGaps)
            .insert(
              AuthorGapsCompanion.insert(
                bookId: s.bookId,
                // An id, which is exactly the point: nothing labels it, so
                // the screen says *another phone* (04 §3.4).
                authorDevice: 'device-9f2c',
                expectedSeq: 7,
                sinceHlc: 12,
              ),
            );
        final waiting = await real.closeStatuses(september);
        expect(waiting.single.state, BookCloseState.waiting);
        expect(waiting.single.waitingOn, isNull);
      },
    );

    test(
      'F1-07-149 once the month is locked the status is closed, which is what '
      'turns the Home card into the S10.2 door (07 §13 🔒)',
      () async {
        // Both open months, in order — the engine refuses any other order.
        for (final month in [august, september]) {
          final view = await real.loadClose(s.bookId, month);
          expect(view.tray.canLock, isTrue);
          await real.lock(
            bookId: s.bookId,
            period: month,
            declaredBalances: view.declaredBalances,
          );
        }
        final after = await real.closeStatuses(september);
        expect(after.single.state, BookCloseState.closed);
        expect(after.single.period, september);
        // The wizard must not resume a month that has nothing left to do.
        expect(after.single.step, isNull);
      },
    );
  });

  group('monthSummary — S10.2 (07 §13 🔒)', () {
    test(
      'F1-07-149 the three figures are the projection’s own, positive integer '
      'paise, with saved = in − out',
      () async {
        final summary = await real.monthSummary(s.bookId, september);
        expect(summary.bookId, s.bookId);
        expect(summary.period, september);
        // The seed posts one income (Shop sales 18,600) and one expense
        // (Diesel 2,400) inside September; transfers, credit and repayment
        // touch no category and so belong to neither figure (02 §9).
        expect(summary.moneyIn, const Paise(1860000));
        expect(summary.moneyOut, const Paise(240000));
        expect(summary.saved, const Paise(1620000));
        expect(summary.moneyIn.raw, isA<int>());
        expect(summary.moneyOut.raw, isA<int>());
      },
    );

    test(
      'F1-07-149 the largest expenses are named and ordered, at most three',
      () async {
        final summary = await real.monthSummary(s.bookId, september);
        expect(summary.topExpenses, hasLength(1));
        expect(summary.topExpenses.single.accountId, s.fuelId);
        expect(summary.topExpenses.single.name, 'Diesel');
        expect(summary.topExpenses.single.amount, const Paise(240000));
        expect(summary.topExpenses.length, lessThanOrEqualTo(3));
      },
    );

    test(
      'F1-07-149 a solo tenant has no sub-families, and a month with nothing '
      'in it answers zero rather than failing',
      () async {
        final summary = await real.monthSummary(s.bookId, september);
        expect(summary.subFamilies, isEmpty);

        // August holds only the opening balances, which post to money and
        // equity — never to a category (02 §4 🔒), so the month is nil.
        final empty = await real.monthSummary(s.bookId, august);
        expect(empty.moneyIn, Paise.zero);
        expect(empty.moneyOut, Paise.zero);
        expect(empty.topExpenses, isEmpty);
      },
    );
  });
}
