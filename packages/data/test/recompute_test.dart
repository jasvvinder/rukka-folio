// Suite E (client half) — Recompute, determinism, integrity gating and the
// corruption path (03 §3.3; ADR 2026-09-05b §4; ADR 2026-09-05c §3, §6).
@Tags(['E'])
library;

import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Recompute (03 §3.3)', () {
    test('E-03-9 the same envelope set inserted in two different orders into '
        'two databases yields byte-identical projection tables', () async {
      final f = Fixture();
      final envelopes = [
        ...f.setupEnvelopes(),
        for (final e in f.ordinaryMonth()) f.eventEnvelope(e),
      ];
      final a = await openMemory();
      final b = await openMemory();
      final (ma, ra) = rig(a);
      final (mb, rb) = rig(b);
      await storeAll(ma, envelopes);
      await storeAll(mb, envelopes.reversed);
      // Interleave a second shuffle: middle-out.
      final mid = envelopes.length ~/ 2;
      final c = await openMemory();
      final (mc, rc) = rig(c);
      await storeAll(mc, [
        ...envelopes.sublist(mid),
        ...envelopes.sublist(0, mid).reversed,
      ]);

      final reports = await Future.wait([ra.run(), rb.run(), rc.run()]);
      for (final r in reports) {
        expect(r.single.integrityOk, isTrue);
        expect(r.single.quarantined, isEmpty);
      }
      final dumpA = await a.dumpProjections();
      expect(await b.dumpProjections(), dumpA);
      expect(await c.dumpProjections(), dumpA);
      expect(dumpA, contains('# balances'));
      // Spot-check the projection is right, not just identical.
      expect(await storedBalance(a, f.cash.id), (50000 - 1200 - 7000) * 100);
      expect(await storedBalance(a, f.verma.id), -80000);
      final e4 = await (a.select(
        a.entriesP,
      )..where((t) => t.id.equals('e4'))).getSingle();
      expect(
        (e4.status, e4.reviewState, e4.reviewApprover),
        ('posted', 'approved', 'papa'),
      );
      expect(e4.reviewDecidedHlc, isNotNull);
      final snaps = await (a.select(
        a.dailySnapshots,
      )..where((t) => t.accountId.equals(f.cash.id))).get();
      expect(snaps.map((s) => (s.date, s.balancePaise)).toList(), [
        ('2026-04-05', 5000000),
        ('2026-04-06', 4880000),
        ('2026-05-03', 4180000),
      ]);
      final book = await bookRow(a, f.bookId);
      expect(
        (book.name, book.type, book.fyStartMonth, book.integrityOk),
        ('Sharma family', 'family', 4, 1),
      );
      await Future.wait([a.close(), b.close(), c.close()]);
    });

    test('E-03-10 a rebuild seeds from the latest certified vector when that '
        "FY's entries are not present locally, and lands on the same balances "
        'and year_close_p as a full replay', () async {
      final f = Fixture();
      // FY 2025-26: one salary, one kirana. Close it. FY 2026-27: the ordinary month.
      final fy1 = [
        f.entry(
          'p1',
          Verbs.moneyIn(
            into: f.cash,
            from: f.salary,
            amount: const Paise.rupees(30000),
          ),
          date: LocalDate(2025, 6, 1),
          kind: EntryKind.moneyIn,
        ),
        f.entry(
          'p2',
          Verbs.moneyOut(
            from: f.cash,
            forWhat: f.kirana,
            amount: const Paise.rupees(4000),
          ),
          date: LocalDate(2025, 7, 1),
        ),
      ];
      // The closer publishes the as-of vector: balance-sheet accounts plus one
      // net-result line, no categories (ADR 05e §2).
      final closeVector = closingVector(
        project(fy1, f.chart),
        f.chart,
        FinancialYear(2025),
      );
      final close = YearClose(
        id: 'yc2025',
        bookId: f.bookId,
        financialYear: FinancialYear(2025),
        vector: closeVector,
        byUser: 'papa',
        hlc: f.nextHlc(),
      );
      final fy2 = f.ordinaryMonth();
      final setup = f.setupEnvelopes();

      final full = await openMemory();
      final (mf, rf) = rig(full);
      await storeAll(mf, [
        ...setup,
        ...fy1.map(f.eventEnvelope),
        f.eventEnvelope(close),
        ...fy2.map(f.eventEnvelope),
      ]);
      final archived = await openMemory();
      final (ma, ra) = rig(archived);
      await storeAll(ma, [
        ...setup,
        f.eventEnvelope(close),
        ...fy2.map(f.eventEnvelope),
      ]);

      final rFull = (await rf.run()).single;
      final rArch = (await ra.run()).single;
      expect(rFull.seededFromVector, isFalse);
      expect(rArch.seededFromVector, isTrue);
      expect(
        rArch.eventsApplied,
        fy2.length + 1,
        reason: 'FY2 events + the seed close',
      );
      // Balance-sheet accounts agree exactly; the seeded book's P&L is
      // FY-scoped by construction (ADR 05e §2) while the full replay's category
      // balances are all-time — so categories legitimately differ.
      for (final a in [f.cash, f.bank, f.verma, f.opening]) {
        expect(
          await storedBalance(archived, a.id),
          await storedBalance(full, a.id),
          reason: a.name,
        );
      }
      expect(await storedBalance(archived, f.salary.id), -50000 * 100);
      expect(await storedBalance(full, f.salary.id), -80000 * 100);
      expect(
        await archived.dumpTable('year_close_p'),
        await full.dumpTable('year_close_p'),
      );
      expect(
        await storedBalance(archived, f.cash.id),
        (30000 - 4000 + 50000 - 1200 - 7000) * 100,
      );
      expect(
        (await archived.select(archived.yearCloseP).get()).single.verification,
        'verified',
        reason: 'both readers reproduce the published vector',
      );
      final yc = await archived.select(archived.yearCloseP).get();
      expect(yc.single.state, 'closed');
      expect(yc.single.vector, isNotNull);
      // The cross-check knows about the seed.
      expect(await ra.verifyBalances(f.bookId), isEmpty);
      expect(await rf.verifyBalances(f.bookId), isEmpty);
      await Future.wait([full.close(), archived.close()]);
    });

    test('E-03-11 integrity_ok is 0 while any envelope is unverified, held for '
        'a missing target or has an author gap, and 1 once all are resolved', () async {
      final f = Fixture();
      final db = await openMemory();
      final (m, r) = rig(db);
      await storeAll(m, f.setupEnvelopes());
      final month = f.ordinaryMonth();
      await storeAll(m, month.map(f.eventEnvelope));
      expect((await r.run()).single.integrityOk, isTrue);

      // A reversal of an entry that has not arrived → held, not counted, not quarantined.
      // The target is built first only so the reversal mirrors it exactly;
      // it is stored *later*, out of order.
      final ghost = f.entry(
        'ghost',
        Verbs.moneyOut(
          from: f.cash,
          forWhat: f.kirana,
          amount: const Paise.rupees(300),
        ),
        date: LocalDate(2026, 5, 8),
      );
      final ghostReversal = ghost.reversal(
        newId: 'rv1',
        hlc: f.nextHlc(),
        accountingDate: LocalDate(2026, 5, 9),
        createdByUser: 'ramesh',
        createdByDevice: f.device,
      );
      // The original's author_seq is reserved but not stored: the author has a
      // gap, so the target may still be in flight → held (ADR 05b §3–4).
      final ghostSeq = f.reserveSeq();
      await m.append(f.eventEnvelope(ghostReversal));
      var rep = (await r.run()).single;
      expect(rep.held, ['env-rv1']);
      expect(rep.quarantined, isEmpty);
      expect(rep.integrityOk, isFalse);
      var row = (await m.envelopesOf(f.bookId))
          .firstWhere((e) => e.envelopeId == 'env-rv1');
      expect((row.held, row.heldFor), (1, 'ghost'));
      expect(
        await storedBalance(db, f.cash.id),
        (50000 - 1200 - 7000) * 100,
        reason: 'held is not counted',
      );
      expect((await bookRow(db, f.bookId)).integrityOk, 0);

      // The target arrives (out of order — its HLC is earlier): released and counted.
      await m.append(f.eventEnvelope(ghost, authorSeq: ghostSeq));
      rep = (await r.run()).single;
      expect(rep.held, isEmpty);
      expect(rep.integrityOk, isTrue);
      row = (await m.envelopesOf(f.bookId))
          .firstWhere((e) => e.envelopeId == 'env-rv1');
      expect((row.held, row.heldFor), (0, null));
      expect(
        await storedBalance(db, f.cash.id),
        (50000 - 1200 - 7000) * 100,
        reason: 'reversal + target net to zero',
      );
      final statuses = await (db.select(
        db.entriesP,
      )..where((t) => t.id.isIn(['ghost', 'rv1']))).get();
      expect(
        {for (final s in statuses) s.id: s.status},
        {'ghost': 'void', 'rv1': 'posted'},
      );

      // An unverified envelope gates the book too.
      final late = f.entry(
        'u1',
        Verbs.moneyOut(
          from: f.cash,
          forWhat: f.kirana,
          amount: const Paise.rupees(1),
        ),
        date: LocalDate(2026, 5, 10),
      );
      await m.append(f.eventEnvelope(late, verified: false));
      rep = (await r.run()).single;
      expect((rep.unverified, rep.integrityOk), (1, false));
      await m.markVerified('env-u1');
      expect((await r.run()).single.integrityOk, isTrue);

      // An author gap (seq 50 with nothing between) gates it as well.
      await m.append(
        f.envelope('gap', 'rule', {'id': 'gap'}, hlc: 5000, authorSeq: 50),
      );
      rep = (await r.run()).single;
      expect(rep.authorGaps, greaterThan(0));
      expect(rep.integrityOk, isFalse);
      await db.close();
    });

    test('E-05c-2 a tampered balances row is detected by the cross-check and '
        'repaired by Recompute; a clean book reports no mismatch', () async {
      final f = Fixture();
      final db = await openMemory();
      final (m, r) = rig(db);
      await storeAll(m, [
        ...f.setupEnvelopes(),
        ...f.ordinaryMonth().map(f.eventEnvelope),
      ]);
      await r.run();
      expect(await r.verifyBalances(f.bookId), isEmpty);
      await db.customStatement(
        "UPDATE balances SET balance_paise = balance_paise + 1 WHERE account_id = '${f.cash.id}'",
      );
      await db.customStatement(
        "DELETE FROM balances WHERE account_id = '${f.verma.id}'",
      );
      final bad = await r.verifyBalances(f.bookId);
      expect(bad.map((b) => b.accountId).toList(), [f.cash.id, f.verma.id]);
      expect(bad.first.stored, bad.first.recomputed + 1);
      expect(await r.checkAndRepair(f.bookId), hasLength(2));
      expect(await r.verifyBalances(f.bookId), isEmpty);
      expect(await storedBalance(db, f.verma.id), -80000);
      await db.close();
    });

    test(
      'E-05c-3 a mirror row failing blob_hash flags the book '
      'needs_rebootstrap with integrity_ok 0, the envelope is skipped not '
      'quarantined, and outbox rows survive both Recompute and re-bootstrap',
      () async {
        final f = Fixture();
        final db = await openMemory();
        final (m, r) = rig(db);
        final month = f.ordinaryMonth();
        await storeAll(m, [
          ...f.setupEnvelopes(),
          ...[month[0], month[1], month[3], month[4]].map(f.eventEnvelope),
        ]);
        // e3 arrives with a hash that does not match its bytes: on-disk corruption.
        await m.append(
          f.eventEnvelope(month[2], blobHash: Uint8List.fromList([9, 9, 9, 9])),
        );
        await m.enqueue(
          envelopeId: 'mine',
          bookId: f.bookId,
          blob: Uint8List.fromList([7]),
          createdAt: 1,
        );

        final rep = (await r.run()).single;
        expect(rep.corrupt, ['env-e3']);
        expect(rep.needsRebootstrap, isTrue);
        expect(rep.integrityOk, isFalse);
        expect(
          rep.quarantined,
          isEmpty,
          reason: 'corruption is not tampering (ADR 05c §2)',
        );
        final book = await bookRow(db, f.bookId);
        expect((book.integrityOk, book.needsRebootstrap), (0, 1));
        expect(
          await storedBalance(db, f.verma.id),
          isNull,
          reason: 'the corrupt envelope is not projected',
        );
        expect((await m.outboxRows()).single.envelopeId, 'mine');

        final dropped = await m.rebootstrapBook(f.bookId);
        expect(dropped, greaterThan(0));
        expect(await m.envelopesOf(f.bookId), isEmpty);
        expect(
          (await m.outboxRows()).single.envelopeId,
          'mine',
          reason: 'never dropped without the user seeing it',
        );
        // The guard is back after re-bootstrap.
        await m.append(f.setupEnvelopes().first);
        expect(
          () => db.customStatement('DELETE FROM envelopes_local'),
          throwsA(anything),
        );
        await db.close();
      },
    );

    test('E-03-14 payloads the opener cannot read are quarantined with the '
        'reason; object types the projector does not consume are stored, '
        'counted for integrity, and otherwise ignored', () async {
      final f = Fixture();
      final db = await openMemory();
      final (m, r) = rig(db);
      await storeAll(m, f.setupEnvelopes());
      await m.append(
        f.envelope('rule1', 'rule', {
          'id': 'rule1',
          'pattern': 'VERMA',
        }, hlc: 500),
      );
      await m.append(
        EnvelopeRecord(
          envelopeId: 'env-junk',
          bookId: f.bookId,
          objectId: 'junk',
          objectType: 'entry',
          keyVersion: 1,
          hlc: 600,
          authorDevice: f.device,
          authorSeq: 99,
          blob: Uint8List.fromList([0xff, 0xfe]),
          blobHash: toyHash(Uint8List.fromList([0xff, 0xfe])),
          verified: true,
        ),
      );
      final rep = (await r.run()).single;
      expect(rep.quarantined, ['env-junk']);
      final junk = (await m.envelopesOf(f.bookId))
          .firstWhere((e) => e.envelopeId == 'env-junk');
      expect(junk.quarantined, 1);
      expect(junk.quarantineReason, startsWith('payload:'));
      expect(rep.eventsApplied, 0);
      expect((await db.select(db.accountsP).get()).length, f.accounts.length);
      await db.close();
    });
  });

  group('projector output mirrored into rows (ADR 05b §3–4, 05c §3)', () {
    test(
      'E-05b-2 held comes from the projector: an amendment or a decision whose '
      'target has not arrived is held (flag columns, absent from entries_p, '
      'integrity_ok 0) while its author has a gap; when the original arrives '
      'both fold and the amount counts once; with the author complete the '
      'target is proven missing and quarantined instead',
      () async {
        final f = Fixture();
        final db = await openMemory();
        final (m, r) = rig(db);
        await storeAll(m, f.setupEnvelopes());
        await storeAll(m, f.ordinaryMonth().map(f.eventEnvelope));
        await r.run();
        final base = (await storedBalance(db, f.cash.id))!;

        // Original built but not stored; its seq is reserved → a real gap.
        final original = f.entry(
          'o1',
          Verbs.moneyOut(
            from: f.cash,
            forWhat: f.kirana,
            amount: const Paise.rupees(900),
          ),
          date: LocalDate(2026, 5, 12),
        );
        final originalSeq = f.reserveSeq();
        final amendment = original.amendWith(
          newId: 'a1',
          hlc: f.nextHlc(),
          lines: Verbs.moneyOut(
            from: f.cash,
            forWhat: f.kirana,
            amount: const Paise.rupees(950),
          ),
        );
        await m.append(f.eventEnvelope(amendment));
        // A decision on an entry nobody has seen.
        final stray = ApprovalDecision(
          id: 'dx',
          bookId: f.bookId,
          entryId: 'never-seen',
          decision: Decision.approve,
          byUser: 'papa',
          hlc: f.nextHlc(),
        );
        await m.append(f.eventEnvelope(stray));

        var rep = (await r.run()).single;
        expect(rep.held, unorderedEquals(['env-a1', 'env-dx']));
        expect(rep.quarantined, isEmpty);
        expect(rep.integrityOk, isFalse);
        final rows = {
          for (final e in await m.envelopesOf(f.bookId)) e.envelopeId: e,
        };
        expect((rows['env-a1']!.held, rows['env-a1']!.heldFor), (1, 'o1'));
        expect(
          (rows['env-dx']!.held, rows['env-dx']!.heldFor),
          (1, 'never-seen'),
        );
        expect(
          await (db.select(
            db.entriesP,
          )..where((t) => t.id.isIn(['a1', 'o1']))).get(),
          isEmpty,
          reason: 'held events are not projected',
        );
        expect(await storedBalance(db, f.cash.id), base);

        // The original lands: amend chain folds, only the head counts.
        await m.append(f.eventEnvelope(original, authorSeq: originalSeq));
        rep = (await r.run()).single;
        expect(await storedBalance(db, f.cash.id), base - 950 * 100);
        final statuses = await (db.select(
          db.entriesP,
        )..where((t) => t.id.isIn(['a1', 'o1']))).get();
        expect(
          {for (final e in statuses) e.id: (e.status, e.supersededBy)},
          {'o1': ('superseded', 'a1'), 'a1': ('posted', null)},
        );
        final a1 = (await m.envelopesOf(f.bookId))
            .firstWhere((e) => e.envelopeId == 'env-a1');
        expect((a1.held, a1.heldFor), (0, null));

        // The author is now complete and 'never-seen' is still absent: the
        // target provably never existed → quarantined target_missing, no
        // longer held (ADR 05b §4). The book is whole again apart from that.
        expect(rep.held, isEmpty);
        expect(rep.quarantined, ['env-dx']);
        final dx = (await m.envelopesOf(f.bookId))
            .firstWhere((e) => e.envelopeId == 'env-dx');
        expect((dx.held, dx.quarantined), (0, 1));
        expect(dx.quarantineReason, contains('targetMissing'));
        expect(rep.integrityOk, isTrue);
        await db.close();
      },
    );

    test('E-05b-3 an author gap seen by the projector gates the book: entries '
        'from one device with author_seq 1 and 3 → integrity_ok 0 and an '
        'author_gaps row expecting 2; seq 2 arriving clears both', () async {
      final f = Fixture();
      final db = await openMemory();
      final (m, r) = rig(db);
      await storeAll(m, f.setupEnvelopes());
      Entry x(String id, int rupees, LocalDate d) => f.entry(
        id,
        Verbs.moneyIn(
          into: f.cash,
          from: f.salary,
          amount: Paise.rupees(rupees),
        ),
        date: d,
        kind: EntryKind.moneyIn,
        device: 'dev-x',
      );
      final x1 = x('x1', 100, LocalDate(2026, 4, 1));
      final x2 = x('x2', 200, LocalDate(2026, 4, 2));
      final x3 = x('x3', 300, LocalDate(2026, 4, 3));
      await m.append(f.eventEnvelope(x1, authorSeq: 1));
      await m.append(f.eventEnvelope(x3, authorSeq: 3));
      var rep = (await r.run()).single;
      expect(rep.integrityOk, isFalse);
      expect(rep.authorGaps, 1);
      final gaps = await db.select(db.authorGaps).get();
      expect(gaps.single.authorDevice, 'dev-x');
      expect(gaps.single.expectedSeq, 2);
      expect(gaps.single.sinceHlc, x3.hlc.raw);
      expect((await bookRow(db, f.bookId)).integrityOk, 0);
      // Present entries still count in the live balance (02 §3).
      expect(await storedBalance(db, f.cash.id), 400 * 100);

      await m.append(f.eventEnvelope(x2, authorSeq: 2));
      rep = (await r.run()).single;
      expect(rep.integrityOk, isTrue);
      expect(rep.authorGaps, 0);
      expect(await db.select(db.authorGaps).get(), isEmpty);
      expect(await storedBalance(db, f.cash.id), 600 * 100);
      await db.close();
    });

    test('E-05c-6 projector_version round-trips through the codec and lands in '
        'year_close_p; a close certified by a newer projector whose vector this '
        'reader cannot reproduce is reader_outdated, never mismatch', () async {
      // Codec.
      final lock = PeriodLock(
        id: 'L1',
        bookId: 'b1',
        period: YearMonth(2026, 4),
        byUser: 'papa',
        hlc: Hlc(77),
        vectorCanonical: 'x',
        projectorVersion: projectorVersion,
      );
      final lockJson = encodeEvent(lock);
      expect(lockJson['projector_version'], projectorVersion);
      final lock2 = decodeEvent('period_lock', lockJson)! as PeriodLock;
      expect(lock2.projectorVersion, projectorVersion);
      expect(encodeEvent(lock2), lockJson);

      final f = Fixture();
      final fy1 = [
        f.entry(
          'p1',
          Verbs.moneyIn(
            into: f.cash,
            from: f.salary,
            amount: const Paise.rupees(30000),
          ),
          date: LocalDate(2025, 6, 1),
          kind: EntryKind.moneyIn,
        ),
      ];
      final good = closingVector(
        project(fy1, f.chart),
        f.chart,
        FinancialYear(2025),
      );
      YearClose close(String id, BalanceVector v, int? version) => YearClose(
        id: id,
        bookId: f.bookId,
        financialYear: FinancialYear(2025),
        vector: v,
        byUser: 'papa',
        hlc: f.nextHlc(),
        projectorVersion: version,
      );
      final ycJson = encodeEvent(close('yc', good, 99));
      expect(ycJson['projector_version'], 99);
      expect(
        (decodeEvent('year_close', ycJson)! as YearClose).projectorVersion,
        99,
      );

      // Verified: current version, reproducible vector.
      final dbA = await openMemory();
      final (ma, ra) = rig(dbA);
      await storeAll(ma, [
        ...f.setupEnvelopes(),
        ...fy1.map(f.eventEnvelope),
        f.eventEnvelope(close('ycA', good, projectorVersion)),
      ]);
      await ra.run();
      final rowA = (await dbA.select(dbA.yearCloseP).get()).single;
      expect(
        (rowA.projectorVersion, rowA.verification),
        (projectorVersion, 'verified'),
      );

      // Newer certifier, vector this reader does not reproduce → reader_outdated.
      final g = Fixture();
      final wrong = BalanceVector({g.cash.id: const Paise.rupees(1)});
      final dbB = await openMemory();
      final (mb, rb) = rig(dbB);
      await storeAll(mb, [
        ...g.setupEnvelopes(),
        ...fy1.map(g.eventEnvelope),
        g.eventEnvelope(
          YearClose(
            id: 'ycB',
            bookId: g.bookId,
            financialYear: FinancialYear(2025),
            vector: wrong,
            byUser: 'papa',
            hlc: g.nextHlc(),
            projectorVersion: 99,
          ),
        ),
      ]);
      await rb.run();
      final rowB = (await dbB.select(dbB.yearCloseP).get()).single;
      expect(
        (rowB.projectorVersion, rowB.verification),
        (99, 'reader_outdated'),
      );
      expect(rowB.verification, isNot('mismatch'));
      await Future.wait([dbA.close(), dbB.close()]);
    });
  });
}
