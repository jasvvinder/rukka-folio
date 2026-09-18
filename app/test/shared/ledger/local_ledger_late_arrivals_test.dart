// F1-02-60…67: the **Late Arrivals** surface on `LocalLedger` — 02 §8 🔒,
// ADR 2026-09-05e §3 and §10, 02 §7.2.1 🔒, 02 §8.1 🔒.
//
// What these tests hold in place:
//
//  · the tray is the **projector's** verdict, never this facade's: an item is
//    in it because `entries_p.status` says `in_tray`, and it carries the *why*
//    07 §13 🔒 asks for — the locked month and the HLC of the lock in force;
//  · *Re-date to today* is an **amend**, and it is the ONLY amendment allowed
//    against a locked month (02 §5, 02 §8): identical lines, only the date
//    moves, into an open period. The projector's own `_isRedate` shape;
//  · the carve-out is exactly that wide — an ordinary posted entry in a locked
//    month is still `amendInLockedPeriod`, and a tray entry whose amount is
//    edited is too;
//  · *Re-open {month}* authors **one** `period_unlock` envelope and nothing
//    else, and refuses — authoring nothing — when the month is not locked or
//    lies inside a closed FY (02 §8.1: that re-open is structural, 02 §7.2.1).
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

/// 5 October 2026 — so the seeded week spans a September the tests can lock
/// while *today* stays in an open October.
DateTime _october() => DateTime(2026, 10, 5, 10);

void main() {
  late SeededLedger s;
  late YearMonth september;

  setUp(() async {
    s = await seedSoloLedger(clock: _october);
    september = YearMonth(2026, 9);
  });

  Future<List<EnvelopesLocalData>> envelopes([String? objectType]) async {
    final q = s.ledger.db.select(s.ledger.db.envelopesLocal);
    if (objectType != null) q.where((t) => t.objectType.equals(objectType));
    return q.get();
  }

  /// An entry dated inside September, posted before the month is locked.
  Future<Entry> septemberEntry() => s.ledger.moneyOut(
    bookId: s.bookId,
    from: s.cashId,
    forWhat: s.fuelId,
    paise: 1_250_00,
    date: LocalDate(2026, 9, 30),
    note: 'Diesel, month end',
  );

  /// Locks September. Returns the lock.
  Future<PeriodLock> lockSeptember() async => (await s.ledger.lockMonth(
    s.bookId,
    september,
    declaredBalances: const {},
  )).lock;

  /// What the projector cannot see on its own: this entry arrived **after**
  /// the lock, so the closer's tray holds it (ADR 2026-09-05e §10). The data
  /// layer does not feed `heldInTray` yet, so the test writes the projected
  /// status the same way the sync path will once it does.
  Future<void> putInTray(String entryId) => s.ledger.db.customStatement(
    "UPDATE entries_p SET status = 'in_tray' WHERE id = ?",
    [entryId],
  );

  group('the tray (02 §8 🔒, ADR 2026-09-05e §3, §10)', () {
    test('F1-02-60 a book with nothing in the tray yields an empty list — an '
        'empty tray is a state, never an absent stream', () async {
      await lockSeptember();
      expect(await s.ledger.watchLateArrivals(s.bookId).first, isEmpty);
    });

    test('F1-02-61 a head projected in_tray is in the tray with its lines, its '
        'amount and the *why*: the locked month and when it locked '
        '(07 §13 🔒)', () async {
      final late = await septemberEntry();
      final lock = await lockSeptember();
      await putInTray(late.id);

      final tray = await s.ledger.watchLateArrivals(s.bookId).first;
      expect(tray, hasLength(1));
      final item = tray.single;
      expect(item.entryId, late.id);
      expect(item.bookId, s.bookId);
      expect(item.kind, EntryKind.moneyOut);
      expect(item.accountingDate, LocalDate(2026, 9, 30));
      // The why: the month it is dated into, and the lock already in force.
      expect(item.lockedPeriod, september);
      expect(item.lockedAtHlc, lock.hlc.raw);
      // Integer paise throughout (CLAUDE.md rule 1).
      expect(item.amount, const Paise(1_250_00));
      expect(item.lines.map((l) => l.accountId), contains(s.cashId));
      expect(item.lines.map((l) => l.accountName), contains('Cash in hand'));
      expect(item.from.single.accountId, s.cashId);
      expect(item.to.single.accountId, s.fuelId);
    });

    test('F1-02-62 a tray item still counts in the live balance — 02 §3 🔒 has '
        'no state in which recorded reality is left out', () async {
      final before = (await s.ledger.watchAccounts(s.bookId).first)
          .firstWhere((a) => a.account.id == s.cashId)
          .balancePaise;
      final late = await septemberEntry();
      await lockSeptember();
      await putInTray(late.id);

      final after = (await s.ledger.watchAccounts(s.bookId).first)
          .firstWhere((a) => a.account.id == s.cashId)
          .balancePaise;
      expect(
        after,
        before - 1_250_00,
        reason: 'a late arrival counts the moment it lands (02 §8 🔒)',
      );
      expect(await s.ledger.watchLateArrivals(s.bookId).first, hasLength(1));
    });
  });

  group('re-date to today (02 §8 🔒 default, one tap)', () {
    test('F1-02-63 a tray entry re-dates into the open period: one amend, '
        'lines untouched, and the projector keeps it', () async {
      final late = await septemberEntry();
      await lockSeptember();
      await putInTray(late.id);

      final moved = await s.ledger.redateLateArrival(late.id);

      expect(moved.accountingDate, s.ledger.today());
      expect(moved.refs.amends, late.id);
      expect(moved.kind, EntryKind.moneyOut);
      // Only the date moved (the projector's `_isRedate` shape).
      expect(
        moved.lines.map((l) => (l.accountId, l.amount.raw)).toSet(),
        late.lines.map((l) => (l.accountId, l.amount.raw)).toSet(),
      );
      // Not quarantined: the head is the amendment, the original superseded.
      final head = await s.ledger.entry(moved.id);
      expect(head, isNotNull);
      expect(head!.status, 'posted');
      expect((await s.ledger.entry(late.id))!.supersededBy, moved.id);
    });

    test('F1-02-64 re-dating into a **locked** period is refused — the '
        'carve-out is the open period and nothing else', () async {
      final late = await septemberEntry();
      await lockSeptember();
      await putInTray(late.id);
      final before = (await envelopes()).length;

      await expectLater(
        s.ledger.redateLateArrival(late.id, to: LocalDate(2026, 9, 28)),
        throwsA(
          isA<PostRejected>().having(
            (e) => e.violations.map((v) => v.kind),
            'violations',
            contains(ViolationKind.amendInLockedPeriod),
          ),
        ),
      );
      expect((await envelopes()).length, before, reason: 'nothing authored');
    });

    test('F1-02-65 an ORDINARY posted entry in a locked month is still '
        'refused — a correction there is a reversal (02 §5)', () async {
      final ordinary = await septemberEntry();
      await lockSeptember();
      final before = (await envelopes()).length;

      await expectLater(
        s.ledger.amend(ordinary.id, accountingDate: s.ledger.today()),
        throwsA(
          isA<PostRejected>().having(
            (e) => e.violations.map((v) => v.kind),
            'violations',
            contains(ViolationKind.amendInLockedPeriod),
          ),
        ),
      );
      expect((await envelopes()).length, before, reason: 'nothing authored');

      // And a tray entry whose **amount** is edited is refused too: a re-date
      // changes when, never what.
      await putInTray(ordinary.id);
      await expectLater(
        s.ledger.amend(
          ordinary.id,
          accountingDate: s.ledger.today(),
          lines: [
            Line(accountId: s.fuelId, amount: const Paise(9_999_00)),
            Line(accountId: s.cashId, amount: const Paise(-9_999_00)),
          ],
        ),
        throwsA(isA<PostRejected>()),
      );
      expect((await envelopes()).length, before, reason: 'nothing authored');
    });
  });

  group('re-open the month (02 §8 🔒 admin, logged)', () {
    test('F1-02-66 authors exactly ONE period_unlock envelope and re-opens '
        'the month — the envelope is the log (02 §7.2 item 3)', () async {
      await lockSeptember();
      final before = (await envelopes()).length;

      final unlock = await s.ledger.unlockMonth(
        s.bookId,
        september,
        reason: 'Diesel bill arrived from the pump after we closed',
      );

      expect(unlock.period, september);
      expect(unlock.byUser, s.ledger.identity.userId);
      expect(unlock.reason, startsWith('Diesel bill arrived'));
      expect(
        (await envelopes()).length,
        before + 1,
        reason: 'one envelope, and nothing else appended',
      );
      final unlocks = await envelopes('period_unlock');
      expect(unlocks, hasLength(1));
      expect(unlocks.single.objectId, unlock.id);

      // The month is open again, so an entry dated into it posts normally.
      final row =
          await (s.ledger.db.select(s.ledger.db.periodsP)
                ..where((t) => t.bookId.equals(s.bookId))
                ..where((t) => t.year.equals(2026))
                ..where((t) => t.month.equals(9)))
              .getSingleOrNull();
      expect(row?.state, 'open');
      await septemberEntry();
    });

    test('F1-02-67 refuses — authoring nothing — a month that is not locked, '
        'a month inside a closed FY (02 §8.1 🔒: structural, 02 §7.2.1), and '
        'a blank reason (a programming error, never a user state)', () async {
      final before = (await envelopes()).length;

      // (a) not locked.
      await expectLater(
        s.ledger.unlockMonth(s.bookId, september, reason: 'nothing to reopen'),
        throwsA(
          isA<MonthUnlockRefused>().having(
            (e) => e.reason,
            'reason',
            MonthUnlockRefusal.notLocked,
          ),
        ),
      );
      expect((await envelopes()).length, before);

      // (b) a blank reason never reaches an envelope.
      await lockSeptember();
      final afterLock = (await envelopes()).length;
      await expectLater(
        s.ledger.unlockMonth(s.bookId, september, reason: '   '),
        throwsA(isA<ArgumentError>()),
      );
      expect((await envelopes()).length, afterLock);

      // (c) the FY is closed: that re-open voids the certificate and every
      // later one, which is the structural `year_reopen` of 02 §7.2.1 🔒.
      // The app has no year-close authoring path yet, so the projected row
      // the ceremony will write is written here directly.
      await s.ledger.db
          .into(s.ledger.db.yearCloseP)
          .insert(
            YearClosePCompanion.insert(
              bookId: s.bookId,
              fyLabel: '2026-27',
              state: 'closed',
              vector: const Value('{}'),
            ),
          );
      await expectLater(
        s.ledger.unlockMonth(s.bookId, september, reason: 'the mill invoice'),
        throwsA(
          isA<MonthUnlockRefused>().having(
            (e) => e.reason,
            'reason',
            MonthUnlockRefusal.closedYear,
          ),
        ),
      );
      expect(
        (await envelopes()).length,
        afterLock,
        reason: 'a structural re-open authors nothing here',
      );
    });
  });
}
