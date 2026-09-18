// Suite E (client half) — the Late Arrivals tray end to end (02 §8; ADR
// 2026-09-05e §3, §10; 03 §3.1, §3.2, §3.3). The engine already knows what a
// late arrival *is* (`isLateArrival`); these tests pin the client-local fact it
// cannot see — the order in which THIS device stored each envelope — and the
// set built from it, so `entries_p.status = 'in_tray'` can exist at all.
@Tags(['E'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// One book, one locked month, one entry created before the lock.
///
/// Returns the envelopes in *creation* (HLC) order; every test appends them in
/// whatever **arrival** order it is about, which is the whole point.
final class _TrayCase {
  _TrayCase({this.lockVector, this.lockProjectorVersion}) {
    early = f.entry(
      'early',
      Verbs.moneyIn(
        into: f.cash,
        from: f.salary,
        amount: const Paise.rupees(50000),
      ),
      date: LocalDate(2026, 4, 5),
      kind: EntryKind.moneyIn,
    );
    late_ = f.entry(
      'late',
      Verbs.moneyOut(
        from: f.cash,
        forWhat: f.kirana,
        amount: const Paise.rupees(1200),
      ),
      date: LocalDate(2026, 4, 20),
    );
    lock = PeriodLock(
      id: 'L-apr',
      bookId: f.bookId,
      period: YearMonth(2026, 4),
      byUser: 'papa',
      hlc: f.nextHlc(),
      vectorCanonical: lockVector,
      projectorVersion: lockProjectorVersion,
    );
  }

  final Fixture f = Fixture();
  final String? lockVector;
  final int? lockProjectorVersion;

  late final Entry early;
  late final Entry late_;
  late final PeriodLock lock;

  /// Envelope records, minted in HLC order so `author_seq` stays contiguous.
  late final List<EnvelopeRecord> setup = f.setupEnvelopes();
  late final EnvelopeRecord earlyEnv = f.eventEnvelope(early);
  late final EnvelopeRecord lateEnv = f.eventEnvelope(late_);
  late final EnvelopeRecord lockEnv = f.eventEnvelope(lock);
}

Future<String?> _statusOf(LedgerDatabase db, String id) async {
  final row = await (db.select(
    db.entriesP,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  return row?.status;
}

void main() {
  group('Late Arrivals tray (02 §8; ADR 2026-09-05e §3, §10)', () {
    test(
      'E-03-47 an entry dated inside a locked month, created before the lock '
      'and stored after it, projects entries_p.status = in_tray',
      () async {
        final c = _TrayCase();
        final db = await openMemory();
        final (m, r) = rig(db);
        // Arrival order: the lock lands first, the entry after it.
        await storeAll(m, [...c.setup, c.earlyEnv, c.lockEnv, c.lateEnv]);
        await r.run();

        expect(await _statusOf(db, 'late'), 'in_tray');
        expect(await _statusOf(db, 'early'), 'posted');
        // `in_tray` is a presentation/certification state, never a projection
        // one: the envelope is not held and not quarantined (ADR 05e §10).
        final row = (await m.envelopesOf(c.f.bookId))
            .singleWhere((e) => e.envelopeId == 'env-late');
        expect(row.held, 0);
        expect(row.quarantined, 0);

        // ⚠️ SPEC (CL6, 18 Sep 2026): ADR 2026-09-05e §3 🔒 says a late arrival
        // "counts in every live figure the moment it lands", but the engine
        // excludes it — `projection.dart:645-652` sets `inTray` without calling
        // `apply()`, and `ProjectedEntry.isCounted` (line 81-82) is
        // `posted || voided`. So the cash balance here is the pre-lock figure
        // only. Recorded, not changed: `core_ledger` behaviour is out of this
        // lane's boundary. E-03-52 carries the ADR's rule and is skipped until
        // that escalation lands.
        expect(
          await storedBalance(db, c.f.cash.id),
          5000000,
          reason: 'engine fact, not the ADR rule — see E-03-52',
        );
        await db.close();
      },
    );

    test(
      'E-03-48 the same envelopes stored in HLC order — the entry before the '
      'lock — project posted: arrival order is the only difference',
      () async {
        final c = _TrayCase();
        final db = await openMemory();
        final (m, r) = rig(db);
        await storeAll(m, [...c.setup, c.earlyEnv, c.lateEnv, c.lockEnv]);
        await r.run();

        expect(await _statusOf(db, 'late'), 'posted');
        expect(await storedBalance(db, c.f.cash.id), 5000000 - 120000);
        await db.close();
      },
    );

    test(
      'E-03-49 an entry whose HLC is after the lock is quarantined '
      'period_locked and is never a tray item (the validity rule, unchanged)',
      () async {
        final f = Fixture();
        final early = f.entry(
          'early',
          Verbs.moneyIn(
            into: f.cash,
            from: f.salary,
            amount: const Paise.rupees(50000),
          ),
          date: LocalDate(2026, 4, 5),
          kind: EntryKind.moneyIn,
        );
        final lock = PeriodLock(
          id: 'L-apr',
          bookId: f.bookId,
          period: YearMonth(2026, 4),
          byUser: 'papa',
          hlc: f.nextHlc(),
        );
        // Created AFTER the lock, dated inside the locked month.
        final backdated = f.entry(
          'backdated',
          Verbs.moneyOut(
            from: f.cash,
            forWhat: f.kirana,
            amount: const Paise.rupees(1200),
          ),
          date: LocalDate(2026, 4, 20),
        );

        final db = await openMemory();
        final (m, r) = rig(db);
        await storeAll(m, [
          ...f.setupEnvelopes(),
          f.eventEnvelope(early),
          f.eventEnvelope(lock),
          f.eventEnvelope(backdated),
        ]);
        final rep = (await r.run()).single;

        expect(rep.quarantined, contains('env-backdated'));
        expect(await _statusOf(db, 'backdated'), isNull);
        final row = (await m.envelopesOf(f.bookId))
            .singleWhere((e) => e.envelopeId == 'env-backdated');
        expect(row.quarantined, 1);
        expect(row.quarantineReason, contains('2026-04'));
        await db.close();
      },
    );

    test(
      'E-03-50 re-dating the tray item into the open period takes the head out '
      'of the tray on the next Recompute (02 §8, the closer\'s one tap)',
      () async {
        final c = _TrayCase();
        final db = await openMemory();
        final (m, r) = rig(db);
        await storeAll(m, [...c.setup, c.earlyEnv, c.lockEnv, c.lateEnv]);
        await r.run();
        expect(await _statusOf(db, 'late'), 'in_tray');

        // The closer re-dates it into May: same lines, only the date moves.
        final redated = c.f.entry(
          'late-2',
          c.late_.lines,
          date: LocalDate(2026, 5, 2),
          refs: const EntryRefs(amends: 'late'),
        );
        await m.append(c.f.eventEnvelope(redated));
        await r.run();

        expect(await _statusOf(db, 'late'), 'superseded');
        expect(
          await _statusOf(db, 'late-2'),
          'posted',
          reason: 'the head is dated in an open month, so it is not late',
        );
        await db.close();
      },
    );

    test(
      'E-03-51 after a period_unlock the month\'s tray is empty: with no lock '
      'in force there is nothing for an entry to be late against',
      () async {
        final c = _TrayCase();
        final db = await openMemory();
        final (m, r) = rig(db);
        await storeAll(m, [...c.setup, c.earlyEnv, c.lockEnv, c.lateEnv]);
        await r.run();
        expect(await _statusOf(db, 'late'), 'in_tray');

        final unlock = PeriodUnlock(
          id: 'U-apr',
          bookId: c.f.bookId,
          period: YearMonth(2026, 4),
          byUser: 'papa',
          reason: 'late bills',
          hlc: c.f.nextHlc(),
        );
        await m.append(c.f.eventEnvelope(unlock));
        await r.run();

        expect(await _statusOf(db, 'late'), 'posted');
        final period = await (db.select(
          db.periodsP,
        )..where((t) => t.month.equals(4))).getSingle();
        expect(period.state, 'open');
        await db.close();
      },
    );

    test(
      'E-03-52 a tray item counts in the live balance the moment it lands '
      '(ADR 2026-09-05e §3 🔒)',
      () async {
        final c = _TrayCase();
        final db = await openMemory();
        final (m, r) = rig(db);
        await storeAll(m, [...c.setup, c.earlyEnv, c.lockEnv, c.lateEnv]);
        await r.run();

        expect(await _statusOf(db, 'late'), 'in_tray');
        expect(
          await storedBalance(db, c.f.cash.id),
          5000000 - 120000,
          reason:
              'ADR 05e §3: no recorded reality is excluded from a live '
              'balance; only the certified month is left untouched',
        );
        await db.close();
      },
      skip:
          'blocked on core_ledger: projection.dart:645-652 sets EffectiveStatus'
          '.inTray without apply(), and ProjectedEntry.isCounted (line 81-82) '
          'is posted||voided, so a tray item is in no live balance — the '
          'opposite of ADR 2026-09-05e §3 🔒. Counting it naively would also '
          'break the lock verification at projection.dart:716-723, which '
          'compares the running balances at the lock\'s HLC (a late arrival '
          'sorts BEFORE the lock) with the published vector — so the fix needs '
          'two accumulators, a core_ledger behaviour change. Escalated to '
          'lane-core; E-03-47 records the current engine fact meanwhile.',
    );

    test(
      'E-03-53 the lock\'s certified vector verifies identically with and '
      'without a tray item: the tray never alters a certified month',
      () async {
        // The vector the closer published: the book as it stood at the lock,
        // with no late arrival in it.
        final probe = _TrayCase();
        final certified = project([
          probe.early,
        ], probe.f.chart).balances.canonical();

        Future<String?> verificationOf(List<EnvelopeRecord> arrival) async {
          final db = await openMemory();
          final (m, r) = rig(db);
          await storeAll(m, arrival);
          await r.run();
          final row = await (db.select(
            db.periodsP,
          )..where((t) => t.month.equals(4))).getSingle();
          final v = row.verification;
          await db.close();
          return v;
        }

        final clean = _TrayCase(
          lockVector: certified,
          lockProjectorVersion: projectorVersion,
        );
        final withTray = _TrayCase(
          lockVector: certified,
          lockProjectorVersion: projectorVersion,
        );

        final noLate = await verificationOf([
          ...clean.setup,
          clean.earlyEnv,
          clean.lockEnv,
        ]);
        final trayed = await verificationOf([
          ...withTray.setup,
          withTray.earlyEnv,
          withTray.lockEnv,
          withTray.lateEnv,
        ]);

        expect(noLate, isNotNull);
        expect(trayed, noLate, reason: 'byte-identical verification');

        // And the contrast that makes the tray load-bearing: the very same
        // envelopes, stored before the lock instead, are counted into the
        // month and the published vector no longer reproduces.
        final counted = _TrayCase(
          lockVector: certified,
          lockProjectorVersion: projectorVersion,
        );
        final early = await verificationOf([
          ...counted.setup,
          counted.earlyEnv,
          counted.lateEnv,
          counted.lockEnv,
        ]);
        expect(early, isNot(noLate));
      },
    );

    test(
      'E-03-54 two Recomputes over the same mirror give the same tray: the '
      'arrival fact is persisted data, never a clock (03 §3.3 rule 2)',
      () async {
        final c = _TrayCase();
        final db = await openMemory();
        final (m, r) = rig(db);
        await storeAll(m, [...c.setup, c.earlyEnv, c.lockEnv, c.lateEnv]);
        await r.run();
        final first = await db.dumpProjections();
        await r.run();
        expect(await db.dumpProjections(), first);
        expect(first, contains('in_tray'));

        // A second device that received the same envelopes in HLC order holds
        // no tray item — two devices may legitimately differ (02 §8).
        final other = _TrayCase();
        final db2 = await openMemory();
        final (m2, r2) = rig(db2);
        await storeAll(m2, [
          ...other.setup,
          other.earlyEnv,
          other.lateEnv,
          other.lockEnv,
        ]);
        await r2.run();
        expect(await db2.dumpProjections(), isNot(contains('in_tray')));
        await db.close();
        await db2.close();
      },
    );

    test(
      'E-03-56 held and in_tray are disjoint: a dangling reference is held and '
      'reaches no entries_p row, a tray item is never held (ADR 05e §10)',
      () async {
        final c = _TrayCase();
        // An amendment whose target never arrives: held, not in the tray.
        final orphan = c.f.entry(
          'orphan',
          c.late_.lines,
          date: LocalDate(2026, 5, 9),
          refs: const EntryRefs(amends: 'never-sent'),
        );

        final db = await openMemory();
        final (m, r) = rig(db);
        // A hole in the author's sequence: without one the set is provably
        // complete and the orphan is quarantined `target_missing` instead of
        // held (ADR 2026-09-05b §4). `held` is the state under test.
        c.f.reserveSeq();
        final orphanEnv = c.f.eventEnvelope(orphan);
        await storeAll(m, [
          ...c.setup,
          c.earlyEnv,
          c.lockEnv,
          c.lateEnv,
          orphanEnv,
        ]);
        final rep = (await r.run()).single;

        expect(rep.held, ['env-orphan']);
        expect(await _statusOf(db, 'orphan'), isNull);
        expect(await _statusOf(db, 'late'), 'in_tray');

        final rows = {
          for (final e in await m.envelopesOf(c.f.bookId)) e.envelopeId: e,
        };
        expect(rows['env-orphan']!.held, 1);
        expect(rows['env-late']!.held, 0);
        await db.close();
      },
    );
  });
}
