// F1-02 / F1-03: the app's ledger facade over the real packages — engine-
// facing behaviour (02 §1.4, §2, §4, §5, §9, §10) and storage-facing
// behaviour (03 §3.1–§3.3). In-memory SQLite, FakeKeyStore, injected clock,
// libsodium via the sodium build hook. Synthetic amounts only.
import 'package:core_crypto/core_crypto.dart' show Uuid16;
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/format/money_format.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../test_app.dart';

Future<int> envelopeCount(LocalLedger l) async =>
    (await l.db.select(l.db.envelopesLocal).get()).length;

Future<int> outboxCount(LocalLedger l) async =>
    (await l.db.select(l.db.outbox).get()).length;

int sum(Iterable<Line> lines) =>
    lines.fold(0, (acc, line) => acc + line.amount.raw);

/// A stable text dump of every Layer-2 table a screen reads (03 §3.2).
Future<List<String>> projectionDump(LocalLedger l) async {
  final db = l.db;
  final out = <String>[
    ...(await db.select(db.booksP).get()).map((r) => r.toString()),
    ...(await (db.select(
      db.accountsP,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get()).map(
      (r) => r.toString(),
    ),
    ...(await (db.select(
      db.entriesP,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get()).map(
      (r) => r.toString(),
    ),
    ...(await (db.select(db.entryLinesP)..orderBy([
              (t) => OrderingTerm.asc(t.entryId),
              (t) => OrderingTerm.asc(t.lineIndex),
            ]))
            .get())
        .map((r) => r.toString()),
    ...(await (db.select(
      db.balances,
    )..orderBy([(t) => OrderingTerm.asc(t.accountId)])).get()).map(
      (r) => r.toString(),
    ),
  ];
  return out;
}

void main() {
  _adr2026_09_09b();
  group('bootstrap', () {
    test('F1-02-1 LedgerNotOpen before bootstrapSolo', () async {
      final l = await openTestLedger();
      expect(l.isOpen, isFalse);
      expect(() => l.identity, throwsA(isA<LedgerNotOpen>()));
      await expectLater(
        l.createBook(name: 'Me', type: BookType.personal),
        throwsA(isA<LedgerNotOpen>()),
      );
      await expectLater(
        l.addAccount('b', name: 'x', accountClass: AccountClass.money),
        throwsA(isA<LedgerNotOpen>()),
      );
      expect(await envelopeCount(l), 0);
    });

    test('F1-03-1 bootstrapSolo mints identity + keys through the KeyStore '
        'and is idempotent', () async {
      final keys = FakeKeyStore();
      final l = await openTestLedger(keys: keys);
      final id = await l.bootstrapSolo(firstBookName: 'Me');
      expect(l.isOpen, isTrue);
      expect(Uuid16.isCanonical(id.deviceId), isTrue);
      expect(Uuid16.isCanonical(id.userId), isTrue);
      expect(Uuid16.isCanonical(id.tenantId), isTrue);
      for (final k in [
        KeyIds.deviceSigningKey,
        KeyIds.deviceAgreementKey,
        KeyIds.wrappedUmk,
        LocalLedgerKeys.identity,
      ]) {
        expect(await keys.contains(k), isTrue, reason: k);
      }
      final books = await l.mirror.bookIds();
      expect(books, hasLength(1));

      // Second call: same ids, no second book, no new envelopes.
      final before = await envelopeCount(l);
      final again = await l.bootstrapSolo(firstBookName: 'Another');
      expect(again.deviceId, id.deviceId);
      expect(again.userId, id.userId);
      expect(again.tenantId, id.tenantId);
      expect(await l.mirror.bookIds(), books);
      expect(await envelopeCount(l), before);
    });

    test(
      'F1-03-2 a new LocalLedger over the same store reopens the same '
      'device (seed replay) and keeps posting; projections identical',
      () async {
        final keys = FakeKeyStore();
        final db = await openTestDb();
        final a = await openTestLedger(keys: keys, db: db);
        final id = await a.bootstrapSolo(firstBookName: 'Me');
        final bookId = (await a.mirror.bookIds()).single;
        final cash = await a.addAccount(
          bookId,
          name: 'Cash',
          accountClass: AccountClass.money,
          subtype: MoneySubtype.cash,
        );
        final sales = await a.addAccount(
          bookId,
          name: 'Sales',
          accountClass: AccountClass.categoryIncome,
        );
        await a.moneyIn(
          bookId: bookId,
          into: cash.id,
          from: sales.id,
          paise: 100_00,
          date: a.today(),
        );
        final dumpA = await projectionDump(a);
        final envelopesA = await envelopeCount(a);
        a.dispose();

        final b = await openTestLedger(keys: keys, db: db);
        final reopened = await b.bootstrapSolo();
        expect(reopened.deviceId, id.deviceId);
        expect(reopened.userId, id.userId);
        expect(
          await envelopeCount(b),
          envelopesA,
          reason: 'reopen appends nothing',
        );
        expect(await projectionDump(b), dumpA);
        // The reopened device seals with the same key: the next envelope is
        // authored, appended and projected without complaint.
        final e = await b.moneyOut(
          bookId: bookId,
          from: cash.id,
          forWhat: (await b.addAccount(
            bookId,
            name: 'Tea',
            accountClass: AccountClass.categoryExpense,
          )).id,
          paise: 20_00,
          date: b.today(),
        );
        expect(e.createdByDevice, id.deviceId);
        final health = await b.watchHealth(bookId).first;
        expect(health.integrityOk, isTrue);
        expect(health.quarantinedCount, 0);
        expect(health.isProvisional, isFalse);
      },
    );
  });

  group('books and accounts', () {
    test('F1-02-2 createBook + addAccount + chartOf: Opening Balance system '
        'account first, then the user chart, in creation order', () async {
      final l = await openTestLedger();
      await l.bootstrapSolo();
      final bookId = await l.createBook(name: 'Shop', type: BookType.business);
      final books = await l.watchBooks().first;
      expect(books.single.id, bookId);
      expect(books.single.name, 'Shop');
      expect(books.single.type, BookType.business.name);

      final cash = await l.addAccount(
        bookId,
        name: 'Cash',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cash,
      );
      final party = await l.addAccount(
        bookId,
        name: 'Ramesh',
        accountClass: AccountClass.party,
      );
      final chart = await l.chartOf(bookId);
      // Since ADR 2026-09-09b §2 a *Just me* business book is seeded with two
      // system accounts, not one: Opening Balance / Capital, then Drawings.
      final system = chart.byClass(AccountClass.equitySystem);
      expect(chart.accounts.map((a) => a.id), [
        ...system.map((a) => a.id),
        cash.id,
        party.id,
      ]);
      expect(system.map((a) => a.systemRole), [
        SystemRole.openingBalance,
        SystemRole.drawings,
      ]);
      final opening = system.first;
      expect(opening.systemRole, SystemRole.openingBalance);
      expect(opening.name, 'Opening Balance');
      expect(chart.account(cash.id).subtype, MoneySubtype.cash);
      expect(chart.account(party.id).accountClass, AccountClass.party);
      // key_cache holds exactly one wrapped key for the book (03 §3.1).
      final cache = await l.db.select(l.db.keyCache).get();
      expect(cache.where((k) => k.bookId == bookId).map((k) => k.keyVersion), [
        1,
      ]);
    });
  });

  group('verbs (02 §2)', () {
    late SeededLedger s;
    setUp(() async => s = await seedSoloLedger());

    test('F1-02-3 every verb posts a balanced two-line entry, + Dr / − Cr, '
        'integer paise, party stamped on party verbs', () async {
      final l = s.ledger;
      final d = l.today();
      final cases = <(Future<Entry>, String, String, EntryKind, String?)>[
        (
          l.moneyIn(
            bookId: s.bookId,
            into: s.bankId,
            from: s.salesId,
            paise: 700_00,
            date: d,
          ),
          s.bankId,
          s.salesId,
          EntryKind.moneyIn,
          null,
        ),
        (
          l.moneyOut(
            bookId: s.bookId,
            from: s.cashId,
            forWhat: s.fuelId,
            paise: 700_00,
            date: d,
          ),
          s.fuelId,
          s.cashId,
          EntryKind.moneyOut,
          null,
        ),
        (
          l.gaveCredit(
            bookId: s.bookId,
            toWhom: s.partyId,
            gave: s.cashId,
            paise: 700_00,
            date: d,
          ),
          s.partyId,
          s.cashId,
          EntryKind.gaveCredit,
          s.partyId,
        ),
        (
          l.tookCredit(
            bookId: s.bookId,
            fromWhom: s.partyId,
            took: s.fuelId,
            paise: 700_00,
            date: d,
          ),
          s.fuelId,
          s.partyId,
          EntryKind.tookCredit,
          s.partyId,
        ),
        (
          l.transfer(
            bookId: s.bookId,
            from: s.bankId,
            to: s.cashId,
            paise: 700_00,
            date: d,
          ),
          s.cashId,
          s.bankId,
          EntryKind.transfer,
          null,
        ),
      ];
      for (final (future, dr, cr, kind, party) in cases) {
        final e = await future;
        expect(e.kind, kind);
        expect(e.status, EntryStatus.posted);
        expect(e.lines, hasLength(2), reason: kind.wire);
        expect(sum(e.lines), 0, reason: '${kind.wire} balances');
        expect(e.lines.every((line) => line.amount.raw != 0), isTrue);
        // Paise is an extension type over int — the type system already forbids
        // a float here (02 §1.4 rule 2); the assertion is the integer sum above.
        expect(
          e.lines.singleWhere((line) => line.accountId == dr).amount.raw,
          700_00,
        );
        expect(
          e.lines.singleWhere((line) => line.accountId == cr).amount.raw,
          -700_00,
        );
        expect(e.partyId, party, reason: kind.wire);
        expect(e.createdByDevice, l.identity.deviceId);
        expect(e.createdByUser, l.identity.userId);
        expect(
          e.authorSeq,
          isNotNull,
          reason: 'author_seq stamped (ADR 05b §3)',
        );
        expect(Uuid16.isCanonical(e.id), isTrue);
        // Projected as authored (02 §3: counts the moment it is saved).
        final view = await l.entry(e.id);
        expect(view, isNotNull);
        expect(view!.status, 'posted');
        expect(
          view.lines.map((x) => (x.accountId, x.amount.raw)),
          e.lines.map((x) => (x.accountId, x.amount.raw)),
        );
      }
      // A party paying back money in: Cr party (their udhaar shrinks) — row 1.
      final repay = s.entries[5];
      expect(repay.kind, EntryKind.moneyIn);
      expect(
        repay.lines.singleWhere((x) => x.accountId == s.partyId).amount.raw,
        -500_000,
      );
      expect(repay.partyId, s.partyId);
      // channel rides in `extra` (02 §2 "online/offline paid") and projects.
      expect((await l.entry(s.entries[2].id))!.channel, 'upi');
    });

    test('F1-02-4 PostRejected on an invariant breach appends nothing '
        '(02 §1.4 rules 1, 3, 6)', () async {
      final l = s.ledger;
      final before = await envelopeCount(l);
      final outboxBefore = await outboxCount(l);

      // Rule 6: future date.
      await expectLater(
        l.moneyIn(
          bookId: s.bookId,
          into: s.cashId,
          from: s.salesId,
          paise: 100_00,
          date: l.today().addDays(1),
        ),
        throwsA(
          isA<PostRejected>().having(
            (r) => r.has(ViolationKind.futureDate),
            'futureDate',
            isTrue,
          ),
        ),
      );
      // Rule 1: unbalanced lines through the raw post door.
      Entry raw(List<Line> lines) => Entry(
        id: l.newId(),
        bookId: s.bookId,
        kind: EntryKind.moneyIn,
        status: EntryStatus.posted,
        reviewRequired: false,
        accountingDate: l.today(),
        lines: lines,
        createdByUser: l.identity.userId,
        createdByDevice: l.identity.deviceId,
        hlc: const Hlc(0),
      );
      await expectLater(
        l.post(
          raw([
            Line(accountId: s.cashId, amount: const Paise(100_00)),
            Line(accountId: s.salesId, amount: const Paise(-90_00)),
          ]),
        ),
        throwsA(
          isA<PostRejected>().having(
            (r) => r.has(ViolationKind.linesUnbalanced),
            'linesUnbalanced',
            isTrue,
          ),
        ),
      );
      // Rule 3: an account the chart does not know.
      await expectLater(
        l.post(
          raw([
            Line(accountId: s.cashId, amount: const Paise(100_00)),
            Line(accountId: l.newId(), amount: const Paise(-100_00)),
          ]),
        ),
        throwsA(
          isA<PostRejected>().having(
            (r) => r.violations.map((v) => v.kind),
            'kinds',
            anyOf(
              contains(ViolationKind.unknownAccount),
              contains(ViolationKind.accountNotInBook),
            ),
          ),
        ),
      );
      // Rule 7 shape: money_in with expense category as the source.
      await expectLater(
        l.post(
          raw([
            Line(accountId: s.cashId, amount: const Paise(100_00)),
            Line(accountId: s.fuelId, amount: const Paise(-100_00)),
          ]),
        ),
        throwsA(isA<PostRejected>()),
      );
      expect(await envelopeCount(l), before, reason: 'nothing appended');
      expect(await outboxCount(l), outboxBefore, reason: 'nothing queued');
    });
  });

  group('corrections (02 §5) — append only', () {
    late SeededLedger s;
    setUp(() async => s = await seedSoloLedger());

    test('F1-02-5 amend appends a new envelope; the original row is unchanged '
        'and marked superseded; views show the head', () async {
      final l = s.ledger;
      final original = s.entries[4]; // gave 10,000 to Ramesh from cash
      final before = await envelopeCount(l);
      final originalView = (await l.entry(original.id))!;

      final head = await l.amend(
        original.id,
        lines: [
          Line(accountId: s.partyId, amount: const Paise(1_200_000)),
          Line(accountId: s.cashId, amount: const Paise(-1_200_000)),
        ],
        note: 'was 12,000',
      );
      expect(await envelopeCount(l), before + 1);
      expect(head.id, isNot(original.id));
      expect(head.kind, original.kind);
      expect(head.refs.amends, original.id);
      expect(head.partyId, s.partyId, reason: 'unpassed fields copied');

      final o = (await l.entry(original.id))!;
      expect(
        o.lines.map((x) => x.amount.raw),
        originalView.lines.map((x) => x.amount.raw),
      );
      expect(o.note, originalView.note);
      expect(o.supersededBy, head.id);
      expect(o.isHead, isFalse);
      final h = (await l.entry(head.id))!;
      expect(h.isHead, isTrue);
      expect(h.amends, original.id);
      expect(h.note, 'was 12,000');

      // Balances follow the head only (02 §5 "views show the latest").
      final party = (await l.watchAccounts(s.bookId).first).singleWhere(
        (a) => a.account.id == s.partyId,
      );
      expect(party.balancePaise, 1_200_000 - 500_000);

      // Statement lists the head, never the superseded body.
      final rows = await l.watchStatement(s.partyId).first;
      expect(rows.map((r) => r.entryId), isNot(contains(original.id)));
      expect(rows.map((r) => r.entryId), contains(head.id));

      // Amending the superseded body again is refused: not the head.
      await expectLater(
        l.amend(original.id, note: 'again'),
        throwsA(
          isA<PostRejected>().having(
            (r) => r.has(ViolationKind.amendNotHead),
            'amendNotHead',
            isTrue,
          ),
        ),
      );
      expect(await envelopeCount(l), before + 1);
    });

    test('F1-02-6 reverse appends the negated mirror; original shows void; '
        'a second reversal is refused', () async {
      final l = s.ledger;
      final original = s.entries[3]; // diesel 2,400 from cash
      final before = await envelopeCount(l);
      final cashBefore = (await l.watchAccounts(s.bookId).first)
          .singleWhere((a) => a.account.id == s.cashId)
          .balancePaise;

      final mirror = await l.reverse(
        original.id,
        date: l.today(),
        note: 'wrong A/C',
      );
      expect(await envelopeCount(l), before + 1);
      expect(mirror.refs.reverses, original.id);
      expect(
        mirror.kind,
        original.kind,
        reason: "mirror keeps the kind (A-05e-8)",
      );
      expect(mirror.accountingDate, l.today());
      for (final line in original.lines) {
        expect(
          mirror.lines
              .singleWhere((x) => x.accountId == line.accountId)
              .amount
              .raw,
          -line.amount.raw,
        );
      }
      final o = (await l.entry(original.id))!;
      expect(o.status, 'void');
      expect(
        o.lines.map((x) => x.amount.raw),
        original.lines.map((x) => x.amount.raw),
        reason: 'original lines untouched',
      );
      final m = (await l.entry(mirror.id))!;
      expect(m.status, 'posted');
      expect(m.reverses, original.id);

      // Both stay in history (02 §9): the statement carries both rows.
      final rows = await l.watchStatement(s.cashId).first;
      expect(rows.map((r) => r.entryId), containsAll([original.id, mirror.id]));
      final cashAfter = (await l.watchAccounts(s.bookId).first)
          .singleWhere((a) => a.account.id == s.cashId)
          .balancePaise;
      expect(cashAfter, cashBefore + 240_000);

      await expectLater(
        l.reverse(original.id, date: l.today()),
        throwsA(
          isA<PostRejected>().having(
            (r) => r.has(ViolationKind.alreadyReversed),
            'alreadyReversed',
            isTrue,
          ),
        ),
      );
      expect(await envelopeCount(l), before + 1);
    });

    test('F1-02-7 openingBalances: one adjustment per non-zero account against '
        'Opening Balance, which absorbs the difference (02 §4)', () async {
      final l = await openTestLedger();
      await l.bootstrapSolo(firstBookName: 'Me');
      final bookId = (await l.mirror.bookIds()).single;
      final cash = await l.addAccount(
        bookId,
        name: 'Cash',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cash,
      );
      final cc = await l.addAccount(
        bookId,
        name: 'HDFC CC',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cc,
      );
      final party = await l.addAccount(
        bookId,
        name: 'Sunita',
        accountClass: AccountClass.party,
      );
      final idle = await l.addAccount(
        bookId,
        name: 'Wallet',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.saving,
      );
      final opening = (await l.chartOf(bookId))
          .byClass(AccountClass.equitySystem)
          .single;

      final posted = await l.openingBalances(
        bookId,
        balances: {
          cash.id: 1_245_000,
          cc.id: -2_291_500,
          party.id: -820_000,
          idle.id: 0,
        },
        date: l.today(),
      );
      expect(posted, hasLength(3), reason: 'zero posts nothing');
      for (final e in posted) {
        expect(e.kind, EntryKind.adjustment);
        expect(e.lines, hasLength(2));
        expect(sum(e.lines), 0);
        expect(e.lines.any((x) => x.accountId == opening.id), isTrue);
      }
      final byId = {
        for (final a in await l.watchAccounts(bookId).first)
          a.account.id: a.balancePaise,
      };
      expect(byId[cash.id], 1_245_000);
      expect(byId[cc.id], -2_291_500);
      expect(byId[party.id], -820_000);
      expect(byId[idle.id], 0);
      expect(byId[opening.id], -(1_245_000 - 2_291_500 - 820_000));
    });
  });

  group('read side (07 §4, §6)', () {
    late SeededLedger s;
    setUp(() async => s = await seedSoloLedger());

    test('F1-02-8 watchPosition sums money, splits get/give, lists banks in '
        'creation order', () async {
      final p = await s.ledger.watchPosition(s.bookId).first;
      expect(p.cashPaise, 2_160_000);
      expect(p.banks.map((b) => b.account.id), [s.bankId]);
      expect(p.banks.single.balancePaise, 11_460_000);
      expect(p.totalMoneyPaise, 2_160_000 + 11_460_000);
      expect(p.youWillGetPaise, 500_000);
      expect(p.youWillGivePaise, 0);
      expect(p.advancesOutPaise, 0);
      expect(p.inTransitPaise, 0);

      // A payable flips to "you will give" as a positive figure.
      await s.ledger.tookCredit(
        bookId: s.bookId,
        fromWhom: s.partyId,
        took: s.fuelId,
        paise: 900_000,
        date: s.ledger.today(),
      );
      final q = await s.ledger.watchPosition(s.bookId).first;
      expect(q.youWillGetPaise, 0);
      expect(q.youWillGivePaise, 400_000);
      expect(
        q.totalMoneyPaise,
        p.totalMoneyPaise,
        reason: 'credit moves no money',
      );
    });

    test(
      'F1-02-9 watchAccounts: A–Z by name with live signed balances',
      () async {
        final rows = await s.ledger.watchAccounts(s.bookId).first;
        expect(rows.map((r) => r.account.name), [
          'Cash in hand',
          'Diesel',
          'Opening Balance',
          'Ramesh',
          'SBI Saving',
          'Shop sales',
        ]);
        final byName = {for (final r in rows) r.account.name: r.balancePaise};
        expect(byName['Cash in hand'], 2_160_000);
        expect(byName['SBI Saving'], 11_460_000);
        expect(byName['Ramesh'], 500_000);
        expect(byName['Shop sales'], -1_860_000);
        expect(byName['Diesel'], 240_000);
        expect(byName['Opening Balance'], -12_500_000);
        expect(rows.every((r) => !r.archived), isTrue);
        // Every balance is the sum of its projected lines — no float anywhere.
        final lines = await s.ledger.db.select(s.ledger.db.entryLinesP).get();
        for (final r in rows) {
          final fromLines = lines
              .where((x) => x.accountId == r.account.id)
              .fold(0, (acc, x) => acc + x.amountPaise);
          expect(r.balancePaise, fromLines, reason: r.account.name);
        }
      },
    );

    test(
      'F1-02-10 watchStatement: ordered by date then hlc, running balance, '
      'Dr/Cr columns from one signed figure, particulars = other side',
      () async {
        final rows = await s.ledger.watchStatement(s.cashId).first;
        expect(rows.map((r) => r.kind), [
          EntryKind.adjustment, // opening 25,000
          EntryKind.moneyOut, // diesel −2,400
          EntryKind.gaveCredit, // Ramesh −10,000
          EntryKind.moneyIn, // Ramesh +5,000
          EntryKind.transfer, // from bank +4,000
        ]);
        expect(rows.map((r) => r.amountPaise), [
          2_500_000,
          -240_000,
          -1_000_000,
          500_000,
          400_000,
        ]);
        expect(rows.map((r) => r.runningBalancePaise), [
          2_500_000,
          2_260_000,
          1_260_000,
          1_760_000,
          2_160_000,
        ]);
        expect(rows.last.runningBalancePaise, 2_160_000, reason: 'sanity');
        expect(rows.map((r) => r.side), [
          Side.dr,
          Side.cr,
          Side.cr,
          Side.dr,
          Side.dr,
        ]);
        expect(rows[1].debitPaise, 0);
        expect(rows[1].creditPaise, 240_000);
        expect(rows[3].debitPaise, 500_000);
        expect(rows[3].creditPaise, 0);
        expect(rows[1].counterAccountIds, [s.fuelId]);
        expect(rows[4].counterAccountIds, [s.bankId]);
        expect(rows[1].note, 'Diesel A/C');
        expect(rows[4].channel, 'netbanking');
        expect(rows.every((r) => r.accountId == s.cashId), isTrue);
        expect(rows.every((r) => r.status == 'posted'), isTrue);
        expect(rows.every((r) => r.reviewState == 'none'), isTrue);
        for (var i = 1; i < rows.length; i++) {
          expect(rows[i - 1].date.compareTo(rows[i].date) <= 0, isTrue);
        }
      },
    );

    test(
      'F1-02-11 entry(): the projected view with lines, refs and author',
      () async {
        final posted = s.entries[2]; // sales → bank
        final v = (await s.ledger.entry(posted.id))!;
        expect(v.bookId, s.bookId);
        expect(v.kind, EntryKind.moneyIn);
        expect(v.status, 'posted');
        expect(v.date, posted.accountingDate);
        expect(v.note, 'Saturday sales');
        expect(v.channel, 'upi');
        expect(v.createdByUser, s.ledger.identity.userId);
        expect(v.hlc, posted.hlc.raw);
        expect(v.amends, isNull);
        expect(v.reverses, isNull);
        expect(v.supersededBy, isNull);
        expect(v.isHead, isTrue);
        expect(v.lines.map((x) => (x.accountId, x.amount.raw)), [
          (s.bankId, 1_860_000),
          (s.salesId, -1_860_000),
        ]);
        expect(await s.ledger.entry(s.ledger.newId()), isNull);
      },
    );

    testWidgets(
      'F1-02-12 rule 9 (02 §10, A-02-10 in spirit): one statement row, '
      'Money in / Money out on the consumer surface, Dr / Cr on the professional',
      (tester) async {
        final rows = await s.ledger.watchStatement(s.cashId).first;
        final moneyIn = rows[3]; // Ramesh repaid 5,000 into cash (+, Dr cash)
        final moneyOut = rows[1]; // diesel 2,400 from cash (−, Cr cash)
        await pumpRk(
          tester,
          Scaffold(
            body: Column(
              children: [
                MoneyText(moneyIn.amountPaise, showDirection: true),
                MoneyText(moneyOut.amountPaise, showDirection: true),
                MoneyText(
                  moneyIn.amountPaise,
                  vocabulary: Vocabulary.professional,
                  showDirection: true,
                ),
                MoneyText(
                  moneyOut.amountPaise,
                  vocabulary: Vocabulary.professional,
                  showDirection: true,
                ),
                Builder(
                  builder: (context) => Text(
                    'scope:${identical(LedgerScope.of(context), s.ledger)}',
                  ),
                ),
              ],
            ),
          ),
          ledger: s.ledger,
        );
        expect(
          find.text('+₹5,000 Money in', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.text('−₹2,400 Money out', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('₹5,000 Dr', findRichText: true), findsOneWidget);
        expect(find.text('₹2,400 Cr', findRichText: true), findsOneWidget);
        expect(find.textContaining('Dr'), findsNWidgets(1));
        expect(find.textContaining('Money'), findsNWidgets(2));
        expect(
          find.text('scope:true'),
          findsOneWidget,
          reason: 'pumpRk(ledger:) wires LedgerScope',
        );
      },
    );
  });

  group('storage (03 §3.1–§3.3)', () {
    late SeededLedger s;
    setUp(() async => s = await seedSoloLedger());

    test('F1-03-3 every authored envelope adds exactly one outbox row; '
        'watchPendingPushes counts them until observed', () async {
      final l = s.ledger;
      final envelopes = await envelopeCount(l);
      final pending = await l.watchPendingPushes().first;
      expect(await outboxCount(l), envelopes);
      expect(pending, envelopes, reason: 'nothing has been pushed yet');
      // book_config + 6 accounts (incl. Opening Balance) + 2 opening + 5 verbs.
      expect(envelopes, 1 + 6 + 2 + 5);

      await l.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 100_00,
        date: l.today(),
      );
      expect(await envelopeCount(l), envelopes + 1);
      expect(await outboxCount(l), envelopes + 1);
      expect(await l.watchPendingPushes().first, pending + 1);

      final outbox = await l.db.select(l.db.outbox).get();
      final mirror = await l.db.select(l.db.envelopesLocal).get();
      expect(
        outbox.map((o) => o.envelopeId).toSet(),
        mirror.map((e) => e.envelopeId).toSet(),
      );
      expect(outbox.every((o) => o.pushState == PushState.queued.name), isTrue);
      // Mirror rows carry this device, contiguous author_seq from 1, verified.
      final seqs = mirror.map((e) => e.authorSeq).toList()..sort();
      expect(seqs, List.generate(mirror.length, (i) => i + 1));
      expect(
        mirror.every((e) => e.authorDevice == l.identity.deviceId),
        isTrue,
      );
      expect(
        mirror.every(
          (e) => e.verified == 1 && e.quarantined == 0 && e.held == 0,
        ),
        isTrue,
      );
      expect(mirror.every((e) => e.keyVersion == 1), isTrue);
    });

    test('F1-03-4 rebuild() reproduces identical projections — the projector '
        'is a pure function of the envelope stream', () async {
      final l = s.ledger;
      final before = await projectionDump(l);
      final envelopes = await envelopeCount(l);
      final r1 = await l.rebuild(s.bookId);
      final r2 = await l.rebuild(s.bookId);
      expect(await projectionDump(l), before);
      expect(
        await envelopeCount(l),
        envelopes,
        reason: 'rebuild authors nothing',
      );
      expect(r1.eventsApplied, r2.eventsApplied);
      expect(r1.integrityOk, isTrue);
      expect(r1.quarantined, isEmpty);
      expect(r1.held, isEmpty);
      expect(r1.corrupt, isEmpty);
      expect(r1.authorGaps, 0);
      expect(l.lastRecompute(s.bookId), same(r2));
    });

    test(
      'F1-03-5 no plaintext financial data outside the ciphertext: the '
      'mirror blob and outbox blob do not carry notes or account names',
      () async {
        final l = s.ledger;
        for (final e in await l.db.select(l.db.envelopesLocal).get()) {
          final text = String.fromCharCodes(e.envelopeBlob);
          expect(text, isNot(contains('Saturday sales')));
          expect(text, isNot(contains('Cash in hand')));
          expect(text, isNot(contains('amount_paise')));
        }
        for (final o in await l.db.select(l.db.outbox).get()) {
          expect(
            String.fromCharCodes(o.envelopeBlob),
            isNot(contains('Saturday sales')),
          );
        }
        final cache = await l.db.select(l.db.keyCache).get();
        expect(
          cache.single.wrappedBlob.length,
          greaterThan(33),
          reason: 'suite ‖ fingerprint ‖ box',
        );
      },
    );

    test('F1-03-6 watchHealth of a whole solo book', () async {
      final h = await s.ledger.watchHealth(s.bookId).first;
      expect(h.bookId, s.bookId);
      expect(h.integrityOk, isTrue);
      expect(h.needsRebootstrap, isFalse);
      expect(h.heldCount, 0);
      expect(h.authorGapCount, 0);
      expect(h.quarantinedCount, 0);
      expect(h.isProvisional, isFalse);
    });
  });
}

void _adr2026_09_09b() {
  group('ADR 2026-09-09b — Capital is Opening Balance; Drawings is seeded', () {
    testWidgets(
      'A-09b-1 Capital is the Opening Balance account, not a second one',
      (tester) async {
        final l = await openTestLedger();
        await l.bootstrapSolo(firstBookName: 'Me');
        final bookId = await l.createBook(
          name: 'Shop',
          type: BookType.business,
        );
        final chart = await l.chartOf(bookId);
        final equity = chart.accounts
            .where((a) => a.accountClass == AccountClass.equitySystem)
            .toList();
        // Exactly one account carries the opening-balance role: both worked
        // examples name it `Opening Balance / Capital A/c`, so splitting Capital
        // off would break their trial balances.
        expect(
          equity.where((a) => a.systemRole == SystemRole.openingBalance),
          hasLength(1),
        );
        expect(
          SystemRole.values.where((r) => r.name == 'capital'),
          isEmpty,
          reason: 'ADR 2026-09-09b §1: no separate capital role exists',
        );
      },
    );

    testWidgets('A-09b-2 a Just me business book is seeded with Drawings A/c', (
      tester,
    ) async {
      final l = await openTestLedger();
      await l.bootstrapSolo(firstBookName: 'Me');
      final bookId = await l.createBook(
        name: 'Sharma Super Store',
        type: BookType.business,
      );
      final chart = await l.chartOf(bookId);
      final drawings = chart.accounts
          .where((a) => a.systemRole == SystemRole.drawings)
          .toList();
      expect(drawings, hasLength(1));
      expect(drawings.single.accountClass, AccountClass.equitySystem);
      expect(drawings.single.name, 'Drawings');
    });

    testWidgets(
      'A-09b-3 no Drawings A/c for a shared business, or any non-business book',
      (tester) async {
        final l = await openTestLedger();
        await l.bootstrapSolo(firstBookName: 'Me');

        Future<int> drawingsCount(String bookId) async {
          final chart = await l.chartOf(bookId);
          return chart.accounts
              .where((a) => a.systemRole == SystemRole.drawings)
              .length;
        }

        // 02 §7.1: a shared business gets one Partner Current A/c per owner,
        // "the single place that relationship lives" — never a Drawings A/c
        // as well.
        final shared = await l.createBook(
          name: 'Amrit Kaur Agri',
          type: BookType.business,
          ownership: BookOwnership.shared,
        );
        expect(await drawingsCount(shared), 0);

        for (final t in [
          BookType.personal,
          BookType.family,
          BookType.joint,
          BookType.organization,
        ]) {
          final id = await l.createBook(name: 'B-${t.name}', type: t);
          expect(
            await drawingsCount(id),
            0,
            reason: '${t.name} books have no owner/business boundary',
          );
        }
      },
    );

    testWidgets('A-09b-3 ownership round-trips, and defaults to justMe', (
      tester,
    ) async {
      // Rule 6 / ADR 2026-09-09b §2: a book written before this ADR carries no
      // `ownership` on the wire and must read back as a single-owner book.
      final legacy = BookConfig.fromJson({
        'id': 'b1',
        'tenant_id': 't1',
        'type': 'business',
        'name': 'Old Shop',
        'fy_start_month': 4,
        'something_new': 42,
      });
      expect(legacy.ownership, BookOwnership.justMe);
      expect(legacy.extra['something_new'], 42);

      final shared = BookConfig.fromJson(
        BookConfig(
          id: 'b2',
          tenantId: 't1',
          type: BookType.business,
          name: 'Agri',
          ownership: BookOwnership.shared,
        ).toJson(),
      );
      expect(shared.ownership, BookOwnership.shared);
    });
  });
}
