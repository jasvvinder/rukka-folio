// F1-07-226…228: `LedgerLateArrivals` over the **real** ledger — the tray S6's
// section and S10.3 have been drawn against a fake all phase (02 §8 🔒, 07 §9,
// 07 §13 🔒, ADR 2026-09-05e §3 and §10).
//
// The book question, settled here: **the Inbox is one surface** (07 §9 🔒), so
// the adapter watches every book this device holds and merges the trays, each
// item carrying its own book's name. It is not coupled to Home's selected book.
//
// Everything else is the ledger's: what is in the tray is the projector's
// `entries_p.status`, *re-date* is an amend and *re-open* is one signed
// `period_unlock` — refused outright inside a closed financial year, which the
// card pre-empts rather than offering a tap that can only fail (07 §1 rule 6).
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/late_arrivals.dart';
import 'package:rukka_folio/features/inbox/ledger_late_arrivals.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

/// 5 October 2026 — so September can be locked while *today* stays in an open
/// October.
DateTime _october() => DateTime(2026, 10, 5, 10);

void main() {
  late LocalLedger ledger;
  late String bookId;
  late String cashId;
  late String fuelId;
  late YearMonth september;

  setUp(() async {
    ledger = await openTestLedger(now: _october);
    await ledger.bootstrapSolo(
      firstBookName: 'Me',
      startDate: LocalDate(2026, 4, 1),
    );
    bookId = (await ledger.mirror.bookIds()).single;
    september = YearMonth(2026, 9);
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
  });

  /// An entry dated inside September. Posted **before** the month locks — a
  /// late arrival is a valid entry that landed after the lock, not a write
  /// into a locked month (02 §8 🔒).
  Future<Entry> september30(String book, String cash, String category) =>
      ledger.moneyOut(
        bookId: book,
        from: cash,
        forWhat: category,
        paise: 125_000,
        date: LocalDate(2026, 9, 30),
        note: 'Diesel, month end',
      );

  /// Projects [entryId] into the tray the way sync will once the
  /// arrival-after-lock set reaches Recompute — the projector's own verdict,
  /// which this adapter reads and never decides (ADR 2026-09-05e §10).
  Future<void> putInTray(String entryId) async {
    await ledger.db.customStatement(
      "UPDATE entries_p SET status = 'in_tray' WHERE id = ?",
      [entryId],
    );
    // A raw statement is invisible to drift's update tracking, so a stream
    // already open over `entries_p` would keep serving its cached answer. The
    // real path writes through the projector and notifies; this says the same
    // thing by hand.
    ledger.db.markTablesUpdated({ledger.db.entriesP});
  }

  /// The first tray that holds [count] items — the streams are live, so this
  /// waits for the merge rather than reading one event and hoping.
  Future<LateArrivalsTray> trayOf(LedgerLateArrivals t, int count) async {
    if (t.current != null && t.current!.items.length == count) {
      return t.current!;
    }
    return t.watch().firstWhere((x) => x.items.length == count);
  }

  test('F1-07-226 the Inbox is ONE surface: the tray merges every book this '
      'device holds, oldest first, each item carrying its own book\'s name — '
      'not Home\'s selected book (07 §9 🔒)', () async {
    final second = await ledger.createBook(
      name: 'Kirana',
      type: BookType.business,
      startDate: LocalDate(2026, 4, 1),
    );
    final cash2 = (await ledger.addAccount(
      second,
      name: 'Shop cash',
      accountClass: AccountClass.money,
      subtype: MoneySubtype.cash,
    )).id;
    final fuel2 = (await ledger.addAccount(
      second,
      name: 'Packing',
      accountClass: AccountClass.categoryExpense,
    )).id;

    final a = await september30(bookId, cashId, fuelId);
    final b = await september30(second, cash2, fuel2);
    await ledger.lockMonth(bookId, september, declaredBalances: const {});
    await ledger.lockMonth(second, september, declaredBalances: const {});
    await putInTray(a.id);
    await putInTray(b.id);

    final adapter = LedgerLateArrivals(ledger);
    addTearDown(adapter.dispose);
    final snapshot = await trayOf(adapter, 2);
    expect(snapshot.items.map((i) => i.bookId).toSet(), {bookId, second});
    expect(snapshot.items.map((i) => i.bookName).toSet(), {'Me', 'Kirana'});

    // The mount the shell makes (bootstrap.dart) is one scope above the
    // router; the scope itself is asserted where it can be pumped without a
    // live drift stream inside a fake-async zone (F1-07-225).
    expect(
      LateArrivalsScope(tray: adapter, child: const SizedBox()).tray,
      same(adapter),
    );
  });

  test('F1-07-227 each card carries the money A/C\'s own signed paise, both '
      'sides in the user\'s words, and *why it is here* — the locked month and '
      'the day it locked (07 §13 🔒)', () async {
    final entry = await september30(bookId, cashId, fuelId);
    await ledger.lockMonth(bookId, september, declaredBalances: const {});
    await putInTray(entry.id);

    final adapter = LedgerLateArrivals(ledger);
    addTearDown(adapter.dispose);
    final item = (await trayOf(adapter, 1)).items.single;
    expect(item.entryId, entry.id);
    expect(item.lockedPeriod, september);
    expect(item.date, LocalDate(2026, 9, 30));
    // Money out of the cash A/C: negative from the money side (02 §10 🔒).
    expect(item.paise, -125_000);
    expect(item.magnitudePaise, 125_000);
    expect(item.fromLabel, 'Cash in hand');
    expect(item.toLabel, 'Diesel');
    expect(item.note, 'Diesel, month end');
    expect(item.lockedOn, isNotNull);
    // Nothing is certified yet, so the re-open is offered rather than
    // pre-empted.
    expect(item.closedYear, isNull);
    expect(item.reopenBlocked, isFalse);
  });

  test('F1-07-228 re-date is an amend and re-open is one signed envelope; the '
      'ledger\'s typed refusal arrives as the seam\'s ReopenRefused, and a '
      'closed financial year is pre-empted on the card (02 §8.1 🔒)', () async {
    final entry = await september30(bookId, cashId, fuelId);
    await ledger.lockMonth(bookId, september, declaredBalances: const {});
    await putInTray(entry.id);
    final adapter = LedgerLateArrivals(ledger);
    addTearDown(adapter.dispose);
    await trayOf(adapter, 1);

    // An amend, not a reversal: the head moves into the open period and the
    // item leaves the tray (02 §5, 02 §8 🔒).
    await adapter.redateToToday(entry.id);
    expect(await trayOf(adapter, 0), isNotNull);
    final heads = await ledger.db
        .customSelect(
          'SELECT accounting_date AS d FROM entries_p '
          'WHERE book_id = ?1 AND superseded_by IS NULL '
          "AND note = 'Diesel, month end'",
          variables: [Variable.withString(bookId)],
          readsFrom: {ledger.db.entriesP},
        )
        .get();
    expect(heads.single.read<String>('d'), ledger.today().toIso());

    // Re-open: one `period_unlock`, and the month is open again.
    await adapter.reopenMonth(
      bookId: bookId,
      period: september,
      reason: 'A bill arrived late',
    );
    final unlocks = await (ledger.db.select(
      ledger.db.envelopesLocal,
    )..where((t) => t.objectType.equals('period_unlock'))).get();
    expect(unlocks, hasLength(1));

    // A month that is not locked refuses, typed, without authoring.
    await expectLater(
      adapter.reopenMonth(bookId: bookId, period: september, reason: 'again'),
      throwsA(
        isA<ReopenRefused>().having(
          (e) => e.reason,
          'reason',
          ReopenRefusal.notLocked,
        ),
      ),
    );

    // And once the year is certified, the card says so instead of offering a
    // tap that can only be refused (07 §1 rule 6).
    final fy = FinancialYear(2026, startMonth: 4);
    final second = await september30(bookId, cashId, fuelId);
    for (final m in fy.months) {
      await ledger.lockMonth(bookId, m, declaredBalances: const {});
    }
    await ledger.closeYear(bookId, fy);
    await putInTray(second.id);
    await adapter.refresh();
    final item = adapter.current!.items.single;
    expect(item.closedYear, fy.label);
    expect(item.reopenBlocked, isTrue);
    await expectLater(
      adapter.reopenMonth(
        bookId: bookId,
        period: september,
        reason: 'the year is sealed',
      ),
      throwsA(
        isA<ReopenRefused>()
            .having((e) => e.reason, 'reason', ReopenRefusal.closedYear)
            .having((e) => e.closedYearLabel, 'label', fy.label),
      ),
    );
  });
}
