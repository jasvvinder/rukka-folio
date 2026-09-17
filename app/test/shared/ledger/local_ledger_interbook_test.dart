// F1-02-19…28: the app's inter-book surface on `LocalLedger` — 02 §6 🔒.
// The engine already owns every posting and the whole reconciliation
// derivation (`InterBook.transfer`, `InterBook.pocketExpense`,
// `InterBook.reconcile`, `InterBook.isInTransit`, `PairStatus`; A-02-78…82,
// A-ref-6, A-05e-10). These tests pin the *app* facade over it: one user
// action that appends two envelopes sharing `refs.transfer_group`, the
// `Due to/from` pair auto-created on first use, the pocket-expense case, and
// a reconciliation read that says *balanced* / lists a non-zero pair with its
// composing entries / says **one-sided · unconfirmed** — never *mismatch* —
// for a side whose book this reader cannot open (ADR 2026-09-05e §7 🔒).
//
// No parallel state: every figure here comes back out of the projection and
// the engine's own `reconcile`. In-memory SQLite, FakeKeyStore, injected
// clock. Amounts are synthetic (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

/// The `Due to/from` accounts of [bookId], newest-created last.
Future<List<Account>> dueAccounts(LocalLedger ledger, String bookId) async =>
    (await ledger.chartOf(bookId))
        .byClass(AccountClass.equitySystem)
        .where((a) => a.systemRole == SystemRole.dueToFrom)
        .toList();

/// The one line of [entry] that touches [accountId].
Line lineOn(Entry entry, String accountId) =>
    entry.lines.singleWhere((l) => l.accountId == accountId);

void main() {
  late SeededLedger s;
  late String familyId;
  late String familyCashId;
  late LocalDate today;

  setUp(() async {
    s = await seedSoloLedger();
    today = s.ledger.today();
    // A second book on the same device — the reader holds both keys, which is
    // the only case 02 §6 calls reconcilable.
    familyId = await s.ledger.createBook(
      name: 'Sharma Family',
      type: BookType.family,
    );
    familyCashId = (await s.ledger.chartOf(familyId))
        .byClass(AccountClass.money)
        .first
        .id;
  });

  group('inter-book movement (02 §6 🔒)', () {
    test(
      'F1-02-19 one action, two envelopes sharing refs.transfer_group — one '
      'posted into each book, the Due to/from pair auto-created on first use',
      () async {
        final before =
            (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length;

        final move = await s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: familyId,
          toAccountId: familyCashId,
          paise: 5_000_000,
          date: today,
        );

        expect(move.from.bookId, s.bookId);
        expect(move.to.bookId, familyId);
        expect(move.transferGroup, isNotEmpty);
        expect(move.from.refs.transferGroup, move.transferGroup);
        expect(move.to.refs.transferGroup, move.transferGroup);
        // Both halves count from the moment of entry (02 §6): the money moved.
        expect(move.from.status, EntryStatus.posted);
        expect(move.to.status, EntryStatus.posted);

        // The paired system accounts, one per book, facing each other.
        final mine = await dueAccounts(s.ledger, s.bookId);
        final theirs = await dueAccounts(s.ledger, familyId);
        expect(mine, hasLength(1));
        expect(theirs, hasLength(1));
        expect(mine.single.counterpartBookId, familyId);
        expect(theirs.single.counterpartBookId, s.bookId);
        expect(mine.single.accountClass, AccountClass.equitySystem);
        expect(mine.single.systemRole, SystemRole.dueToFrom);
        // Two accounts + two entries appended, nothing updated in place.
        final after =
            (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length;
        expect(after - before, 4);
      },
    );

    test(
      'F1-02-20 the postings are 02 §6\'s: Dr Due to/from B · Cr money in the '
      'paying book, Dr money · Cr Due to/from A in the receiving one',
      () async {
        final move = await s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: familyId,
          toAccountId: familyCashId,
          paise: 5_000_000,
          date: today,
        );
        final mine = (await dueAccounts(s.ledger, s.bookId)).single;
        final theirs = (await dueAccounts(s.ledger, familyId)).single;

        expect(move.from.kind, EntryKind.transfer);
        expect(lineOn(move.from, mine.id).amount, Paise(5_000_000));
        expect(lineOn(move.from, s.bankId).amount, Paise(-5_000_000));
        expect(move.to.kind, EntryKind.transfer);
        expect(lineOn(move.to, familyCashId).amount, Paise(5_000_000));
        expect(lineOn(move.to, theirs.id).amount, Paise(-5_000_000));

        // And the balances agree with the entries — nothing derived twice.
        final rows = await s.ledger.reconciliation();
        expect(rows.single.netPaise, 0);
      },
    );

    test(
      'F1-02-21 the Due to/from pair is created on *first* use only — a second '
      'transfer reuses it (02 §6)',
      () async {
        await s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: familyId,
          toAccountId: familyCashId,
          paise: 5_000_000,
          date: today,
        );
        final first = (await dueAccounts(s.ledger, s.bookId)).single.id;

        // The reverse direction, too: the same pair of accounts carries it.
        await s.ledger.transferBetweenBooks(
          fromBookId: familyId,
          fromAccountId: familyCashId,
          toBookId: s.bookId,
          toAccountId: s.cashId,
          paise: 1_000_000,
          date: today,
        );

        expect(await dueAccounts(s.ledger, s.bookId), hasLength(1));
        expect(await dueAccounts(s.ledger, familyId), hasLength(1));
        expect((await dueAccounts(s.ledger, s.bookId)).single.id, first);
        // Nothing is lost: 50,000 out and 10,000 back nets to 40,000 owed.
        final rows = await s.ledger.reconciliation();
        expect(rows.single.status, PairStatus.balanced);
        expect(rows.single.netPaise, 0);
        expect(rows.single.sidePaise.abs(), 4_000_000);
      },
    );

    test(
      'F1-02-22 the pocket-expense case — personal book Dr Due to/from Family '
      '· Cr Cash, family book Dr Expense · Cr Due to/from Personal (02 §6)',
      () async {
        final groceries = await s.ledger.addAccount(
          familyId,
          name: 'Groceries',
          accountClass: AccountClass.categoryExpense,
        );

        final move = await s.ledger.pocketExpense(
          payerBookId: s.bookId,
          payerMoneyId: s.cashId,
          payeeBookId: familyId,
          payeeExpenseId: groceries.id,
          paise: 120_000,
          date: today,
        );

        final mine = (await dueAccounts(s.ledger, s.bookId)).single;
        final theirs = (await dueAccounts(s.ledger, familyId)).single;
        // The payer is owed money — never an expense in his own book.
        expect(lineOn(move.from, mine.id).amount, Paise(120_000));
        expect(lineOn(move.from, s.cashId).amount, Paise(-120_000));
        // The family carries the expense.
        expect(move.to.kind, EntryKind.moneyOut);
        expect(lineOn(move.to, groceries.id).amount, Paise(120_000));
        expect(lineOn(move.to, theirs.id).amount, Paise(-120_000));
        // Nothing is lost in someone's pocket: the pair nets to zero.
        final rows = await s.ledger.reconciliation();
        expect(rows.single.status, PairStatus.balanced);
        expect(rows.single.netPaise, 0);
      },
    );
  });

  group('Family Reconciliation (02 §6 🔒, ADR 2026-09-05e §7 🔒)', () {
    test('F1-02-23 a matched pair reads balanced and nets to zero, both books '
        'named', () async {
      expect(await s.ledger.reconciliation(), isEmpty);

      await s.ledger.transferBetweenBooks(
        fromBookId: s.bookId,
        fromAccountId: s.bankId,
        toBookId: familyId,
        toAccountId: familyCashId,
        paise: 5_000_000,
        date: today,
      );

      final rows = await s.ledger.reconciliation();
      expect(rows, hasLength(1), reason: 'one pair, not one row per side');
      final pair = rows.single;
      expect(pair.status, PairStatus.balanced);
      expect(pair.isBalanced, isTrue);
      expect(pair.isUnconfirmed, isFalse);
      expect(pair.netPaise, 0);
      expect(
        {pair.bookName, pair.counterpartBookName},
        {'Me', 'Sharma Family'},
      );
      expect(pair.counterpartBookId, isNotNull);
      expect(pair.entries, hasLength(2));
    });

    test('F1-02-24 a non-zero pair is listed with the entries composing it '
        '(02 §6 🔒)', () async {
      final move = await s.ledger.transferBetweenBooks(
        fromBookId: s.bookId,
        fromAccountId: s.bankId,
        toBookId: familyId,
        toAccountId: familyCashId,
        paise: 5_000_000,
        date: today,
      );
      // The receiving half is reversed and the pair stops netting to zero.
      final reversal = await s.ledger.reverse(move.to.id, date: today);

      final pair = (await s.ledger.reconciliation()).single;
      expect(pair.status, PairStatus.mismatch);
      expect(pair.netPaise.abs(), 5_000_000);
      final ids = pair.entries.map((e) => e.entryId).toSet();
      expect(ids, contains(move.from.id));
      expect(ids, contains(move.to.id));
      expect(ids, contains(reversal.id));
      // Each composing entry carries what a reader needs to open it.
      final mineRow = pair.entries.firstWhere((e) => e.entryId == move.from.id);
      expect(mineRow.bookId, s.bookId);
      expect(mineRow.bookName, 'Me');
      expect(mineRow.date, today);
      expect(mineRow.amountPaise, 5_000_000);
    });

    test('F1-02-25 a side the reader cannot open is one-sided · unconfirmed, '
        'never a mismatch (ADR 2026-09-05e §7 🔒)', () async {
      // A book this install knows of but holds no key for (04 §5.2): a
      // brother\'s personal book. The Due to/from account names it; the
      // ledger has no state for it at all.
      final due = await s.ledger.dueToFromAccount(
        s.bookId,
        counterpartBookId: 'book-we-hold-no-key-for',
        name: 'Due to/from Bhraji',
      );
      await s.ledger.transfer(
        bookId: s.bookId,
        from: s.cashId,
        to: due.id,
        paise: 300_000,
        date: today,
      );

      final pair = (await s.ledger.reconciliation()).single;
      expect(pair.status, PairStatus.unconfirmed);
      expect(pair.isUnconfirmed, isTrue);
      expect(
        pair.status,
        isNot(PairStatus.mismatch),
        reason: 'a sealed side is never a mismatch (ADR 2026-09-05e §7 🔒)',
      );
      expect(pair.counterpartBookName, isNull);
      expect(pair.counterpartBookId, 'book-we-hold-no-key-for');
      // The readable side\'s own balance is what it can say, and it says so.
      expect(pair.sidePaise.abs(), 300_000);
      expect(pair.entries, hasLength(1));
      expect(pair.entries.single.bookId, s.bookId);
    });

    test(
      'F1-02-26 the read is live — watchReconciliation follows a posting',
      () async {
        final seen = <List<ReconciliationPair>>[];
        final sub = s.ledger.watchReconciliation().listen(seen.add);
        await pumpEventQueue();
        expect(seen.last, isEmpty);

        await s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: familyId,
          toAccountId: familyCashId,
          paise: 5_000_000,
          date: today,
        );
        await pumpEventQueue();

        expect(seen.last, hasLength(1));
        expect(seen.last.single.isBalanced, isTrue);
        await sub.cancel();
      },
    );

    test(
      'F1-02-27 in transit comes only from the engine — both halves post, so '
      'nothing is in transit until a half carries an open review flag (02 §6)',
      () async {
        await s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: familyId,
          toAccountId: familyCashId,
          paise: 5_000_000,
          date: today,
        );
        expect((await s.ledger.reconciliation()).single.inTransit, isFalse);

        // The half the actor lacks posting rights in carries the review flag
        // for that book's approver; the pair reads *in transit* while it is
        // open (02 §6, 07 §10). This app has no book-role source yet, so the
        // flag is only ever set by an explicit caller — see the ⚠️ SPEC note
        // on [LocalLedger.transferBetweenBooks].
        await s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: familyId,
          toAccountId: familyCashId,
          paise: 2_000_000,
          date: today,
          reviewRequiredIn: (from: false, to: true),
        );

        final pair = (await s.ledger.reconciliation()).single;
        expect(pair.inTransit, isTrue);
        // And it is still a balanced pair: a flag does not unbalance anything.
        expect(pair.status, PairStatus.balanced);
      },
    );

    test('F1-02-28 refusals are typed and append nothing', () async {
      Future<void> refused(
        Future<void> Function() action,
        InterBookRefusal expected,
      ) async {
        final before =
            (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length;
        await expectLater(
          action(),
          throwsA(
            isA<InterBookRefused>().having(
              (e) => e.refusal,
              'refusal',
              expected,
            ),
          ),
        );
        final after =
            (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length;
        expect(after, before, reason: 'a refusal authors nothing');
      }

      await refused(
        () => s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: s.bookId,
          toAccountId: s.cashId,
          paise: 1_000_00,
          date: today,
        ),
        InterBookRefusal.sameBook,
      );
      await refused(
        () => s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: familyId,
          toAccountId: familyCashId,
          paise: 0,
          date: today,
        ),
        InterBookRefusal.amountNotPositive,
      );
      await refused(
        () => s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.salesId,
          toBookId: familyId,
          toAccountId: familyCashId,
          paise: 1_000_00,
          date: today,
        ),
        InterBookRefusal.notAMoneyAccount,
      );
      await refused(
        () => s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: 'book-we-hold-no-key-for',
          toAccountId: familyCashId,
          paise: 1_000_00,
          date: today,
        ),
        InterBookRefusal.bookNotHeld,
      );
      await refused(
        () => s.ledger.pocketExpense(
          payerBookId: s.bookId,
          payerMoneyId: s.cashId,
          payeeBookId: familyId,
          payeeExpenseId: familyCashId,
          paise: 1_000_00,
          date: today,
        ),
        InterBookRefusal.notAnExpenseCategory,
      );
    });
  });

  // ── the pair is atomic (02 §6 🔒) ───────────────────────────────────────────
  //
  // 02 §6 🔒 says one action makes **two** envelopes sharing
  // `refs.transfer_group`. The ledger is append-only (CLAUDE.md rule 2), so a
  // half that has landed can never be withdrawn: if the receiving book would
  // refuse its half, the paying half must never have been written. The only
  // correct shape is therefore *validate both halves against both books'
  // states, then append* — never *append, then compensate*.
  //
  // `F1-07-120` covers the **paying** half being refused, which the old
  // sequential code already handled by accident (it refused before appending
  // anything). These drive the case it deliberately leaves out: the receiving
  // half is the one that is refused.
  group('F1-02-47 one action, two envelopes — or neither', () {
    /// Entry envelopes across every book this device holds.
    Future<int> entryEnvelopes() async {
      final db = s.ledger.db;
      final rows = await (db.select(
        db.envelopesLocal,
      )..where((e) => e.objectType.equals('entry'))).get();
      return rows.length;
    }

    /// A book whose books begin **today**, so anything dated earlier is
    /// refused in it by the ADR 2026-09-09d §4 start-date guard — while the
    /// seeded paying book, which began a week ago, accepts the same date.
    Future<({String bookId, String cashId, String expenseId})>
    lateBook() async {
      final id = await s.ledger.createBook(
        name: 'Gurdwara Langar',
        type: BookType.family,
        startDate: today,
      );
      final chart = await s.ledger.chartOf(id);
      final expense = await s.ledger.addAccount(
        id,
        name: 'Langar supplies',
        accountClass: AccountClass.categoryExpense,
      );
      return (
        bookId: id,
        cashId: chart.byClass(AccountClass.money).first.id,
        expenseId: expense.id,
      );
    }

    test(
      'F1-02-47 transferBetweenBooks: when the receiving book refuses its '
      'half, nothing is appended to either book — no orphan paying half',
      () async {
        final late = await lateBook();
        final backDated = today.addDays(-3);
        final before = await entryEnvelopes();

        await expectLater(
          s.ledger.transferBetweenBooks(
            fromBookId: s.bookId,
            fromAccountId: s.bankId,
            toBookId: late.bookId,
            toAccountId: late.cashId,
            paise: 25_000_00,
            date: backDated,
          ),
          throwsA(isA<PostRejected>()),
        );

        // Not one envelope more, in either book: the paying half was never
        // written, so there is nothing to reverse and no broken pair.
        expect(await entryEnvelopes(), before);
      },
    );

    test('F1-02-47 the refusal names the receiving half\'s violation, not a '
        'silent no-op', () async {
      final late = await lateBook();
      try {
        await s.ledger.transferBetweenBooks(
          fromBookId: s.bookId,
          fromAccountId: s.bankId,
          toBookId: late.bookId,
          toAccountId: late.cashId,
          paise: 25_000_00,
          date: today.addDays(-3),
        );
        fail('the receiving book must refuse a date before its start');
      } on PostRejected catch (e) {
        expect(
          e.violations.map((v) => v.kind),
          contains(ViolationKind.beforeBookStart),
        );
      }
    });

    test('F1-02-47 pocketExpense: the same — a refused payee half leaves the '
        "payer's book empty too", () async {
      final late = await lateBook();
      final before = await entryEnvelopes();

      await expectLater(
        s.ledger.pocketExpense(
          payerBookId: s.bookId,
          payerMoneyId: s.cashId,
          payeeBookId: late.bookId,
          payeeExpenseId: late.expenseId,
          paise: 1_200_00,
          date: today.addDays(-3),
        ),
        throwsA(isA<PostRejected>()),
      );

      expect(await entryEnvelopes(), before);
    });

    test('F1-02-47 and when both halves are acceptable the pair still lands '
        'whole — two envelopes, one transfer_group', () async {
      final late = await lateBook();
      final before = await entryEnvelopes();
      final move = await s.ledger.transferBetweenBooks(
        fromBookId: s.bookId,
        fromAccountId: s.bankId,
        toBookId: late.bookId,
        toAccountId: late.cashId,
        paise: 25_000_00,
        date: today,
      );
      expect(await entryEnvelopes(), before + 2);
      expect(move.from.refs.transferGroup, move.transferGroup);
      expect(move.to.refs.transferGroup, move.transferGroup);
    });
  });
}
