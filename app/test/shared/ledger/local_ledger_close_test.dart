// F1-02-48…51: the **month lock** on `LocalLedger` — 02 §8 🔒, and the
// resumable wizard progress 07 §13 🔒 asks for.
//
// The engine owns every judgement here and this facade owns none:
// `monthLockPreconditions` says what blocks (A-02-48…52), the projector
// computes the balance vector and `core_ledger.projectorVersion` names the
// version that computed it (ADR 2026-09-05c §3). These tests pin that the
// facade **carries** those answers rather than restating them — the hash it
// publishes is the projector's own bytes, and a refusal is the engine's own
// `CloseBlockerItem`s with nothing appended.
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

void main() {
  late SeededLedger s;
  late YearMonth period;

  setUp(() async {
    s = await seedSoloLedger();
    period = s.ledger.today().yearMonth;
  });

  /// Every `period_lock` envelope in the mirror.
  Future<List<EnvelopesLocalData>> lockEnvelopes() async =>
      (await (s.ledger.db.select(
        s.ledger.db.envelopesLocal,
      )..where((t) => t.objectType.equals('period_lock'))).get());

  group('preconditions are the engine\'s (02 §8 step 3 🔒)', () {
    test('F1-02-48 a clean book blocks on nothing — the facade adds no rule of '
        'its own', () async {
      expect(await s.ledger.monthClosePreconditions(s.bookId, period), isEmpty);
    });

    test(
      'F1-02-48 an open review flag blocks, in the engine\'s own terms — '
      'CloseBlocker.reviewFlagOpen pointing at the entry (A-02-48…52)',
      () async {
        final flagged = await s.ledger.post(
          Entry(
            id: s.ledger.newId(),
            bookId: s.bookId,
            kind: EntryKind.moneyOut,
            status: EntryStatus.posted,
            reviewRequired: true,
            reviewApprover: s.ledger.identity.userId,
            accountingDate: s.ledger.today(),
            lines: [
              Line(accountId: s.fuelId, amount: const Paise(2_000_00)),
              Line(accountId: s.cashId, amount: const Paise(-2_000_00)),
            ],
            createdByUser: s.ledger.identity.userId,
            createdByDevice: s.ledger.identity.deviceId,
            hlc: const Hlc(0),
          ),
        );

        final blockers = await s.ledger.monthClosePreconditions(
          s.bookId,
          period,
        );
        expect(
          blockers.map((b) => b.kind),
          contains(CloseBlocker.reviewFlagOpen),
        );
        expect(blockers.map((b) => b.ref), contains(flagged.id));
      },
    );

    test('F1-02-48 a held envelope in the mirror blocks even though the '
        'projection cannot see it — the union never drops a blocker '
        '(ADR 2026-09-05b §4)', () async {
      // A held row is what sync writes for an envelope whose target has not
      // arrived. Held is never an error — but nobody certifies a balance
      // with entries known to be missing.
      final db = s.ledger.db;
      final any = (await db.select(db.envelopesLocal).get()).first;
      await db.customStatement(
        'UPDATE envelopes_local SET held = 1 WHERE envelope_id = ?',
        [any.envelopeId],
      );

      final blockers = await s.ledger.monthClosePreconditions(s.bookId, period);
      expect(blockers.map((b) => b.kind), contains(CloseBlocker.heldEnvelope));
      expect(blockers.map((b) => b.ref), contains(any.objectId));
      // And the same blocker is not counted twice when the projection has
      // it too.
      final held = blockers
          .where((b) => b.kind == CloseBlocker.heldEnvelope)
          .map((b) => b.ref)
          .toList();
      expect(held.toSet(), hasLength(held.length));
    });
  });

  group('the lock envelope is the projector\'s word (02 §8 step 4 🔒)', () {
    test('F1-02-49 lockMonth authors ONE signed period_lock carrying the '
        'declared balances, the projector\'s canonical vector and its '
        'projectorVersion — the hash is never recomputed here', () async {
      final state = (await s.ledger.rebuild(s.bookId)).state;
      final expectedVector = state.balances.canonical();
      final declared = {
        s.cashId: state.balances[s.cashId],
        s.bankId: state.balances[s.bankId],
      };

      final locked = await s.ledger.lockMonth(
        s.bookId,
        period,
        declaredBalances: declared,
      );

      expect(await lockEnvelopes(), hasLength(1));
      expect(locked.lock.period, period);
      expect(locked.lock.declaredBalances, declared);
      // The bytes the projector computed, not a figure this facade assembled.
      expect(locked.lock.vectorCanonical, expectedVector);
      expect(locked.lock.projectorVersion, projectorVersion);
      // Integer paise end to end (CLAUDE.md rule 1).
      for (final p in locked.lock.declaredBalances!.values) {
        expect(p.raw, isA<int>());
      }
    });

    test('F1-02-49 this device verifies the vector it just published — the '
        'projection answers `verified`, not an assumption of success '
        '(ADR 2026-09-05c §3)', () async {
      final locked = await s.ledger.lockMonth(
        s.bookId,
        period,
        declaredBalances: const {},
      );
      expect(locked.verification, CloseVerification.verified);
    });

    test('F1-02-49 the month reads locked afterwards, and an entry dated in it '
        'is refused (02 §8)', () async {
      await s.ledger.lockMonth(s.bookId, period, declaredBalances: const {});
      final state = (await s.ledger.rebuild(s.bookId)).state;
      expect(state.periods.currentStatus(period), PeriodStatus.locked);

      await expectLater(
        s.ledger.moneyOut(
          bookId: s.bookId,
          from: s.cashId,
          forWhat: s.fuelId,
          paise: 100_00,
          date: s.ledger.today(),
        ),
        throwsA(
          isA<PostRejected>().having(
            (r) => r.has(ViolationKind.periodLocked),
            'periodLocked',
            isTrue,
          ),
        ),
      );
    });

    test(
      'F1-02-50 a refused lock throws the engine\'s own blockers and appends '
      'nothing — a refusal is never a silent no-op',
      () async {
        await s.ledger.post(
          Entry(
            id: s.ledger.newId(),
            bookId: s.bookId,
            kind: EntryKind.moneyOut,
            status: EntryStatus.posted,
            reviewRequired: true,
            reviewApprover: s.ledger.identity.userId,
            accountingDate: s.ledger.today(),
            lines: [
              Line(accountId: s.fuelId, amount: const Paise(2_000_00)),
              Line(accountId: s.cashId, amount: const Paise(-2_000_00)),
            ],
            createdByUser: s.ledger.identity.userId,
            createdByDevice: s.ledger.identity.deviceId,
            hlc: const Hlc(0),
          ),
        );
        final before =
            (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length;

        await expectLater(
          s.ledger.lockMonth(s.bookId, period, declaredBalances: const {}),
          throwsA(
            isA<MonthLockRefused>().having(
              (r) => r.blockers.map((b) => b.kind),
              'blockers',
              contains(CloseBlocker.reviewFlagOpen),
            ),
          ),
        );

        expect(await lockEnvelopes(), isEmpty);
        expect(
          (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length,
          before,
        );
        final state = (await s.ledger.rebuild(s.bookId)).state;
        expect(state.periods.currentStatus(period), PeriodStatus.open);
      },
    );
  });

  group('resumable (07 §13 🔒)', () {
    test('F1-02-51 progress saved at a step is what the next read hands back, '
        'per book and per month', () async {
      expect(await s.ledger.closeProgress(s.bookId, period), isNull);

      await s.ledger.saveCloseProgress(
        s.bookId,
        period,
        SavedCloseProgress(
          step: 'confirmBanks',
          confirmedAccountIds: {s.bankId},
        ),
      );
      expect(
        await s.ledger.closeProgress(s.bookId, period),
        SavedCloseProgress(
          step: 'confirmBanks',
          confirmedAccountIds: {s.bankId},
        ),
      );

      // A different month is a different close.
      expect(
        await s.ledger.closeProgress(
          s.bookId,
          YearMonth(period.year - 1, period.month),
        ),
        isNull,
      );

      // Saving again replaces, never duplicates: one row per (book, month).
      await s.ledger.saveCloseProgress(
        s.bookId,
        period,
        const SavedCloseProgress(step: 'clearTray'),
      );
      expect(
        (await s.ledger.closeProgress(s.bookId, period))!.step,
        'clearTray',
      );
    });

    test('F1-02-51 a Recompute does not drop it — nothing in the envelope '
        'stream could put it back', () async {
      await s.ledger.saveCloseProgress(
        s.bookId,
        period,
        SavedCloseProgress(
          step: 'confirmBanks',
          confirmedAccountIds: {s.bankId},
        ),
      );
      await s.ledger.rebuild(s.bookId);
      expect(
        await s.ledger.closeProgress(s.bookId, period),
        SavedCloseProgress(
          step: 'confirmBanks',
          confirmedAccountIds: {s.bankId},
        ),
      );
    });

    test('F1-02-51 it never leaves this phone: no envelope, and nothing queued '
        'to push', () async {
      final db = s.ledger.db;
      final outboxBefore = (await db.select(db.outbox).get()).length;
      final envelopesBefore = (await db.select(db.envelopesLocal).get()).length;

      await s.ledger.saveCloseProgress(
        s.bookId,
        period,
        const SavedCloseProgress(step: 'clearTray'),
      );

      expect((await db.select(db.outbox).get()).length, outboxBefore);
      expect(
        (await db.select(db.envelopesLocal).get()).length,
        envelopesBefore,
      );
    });

    test('F1-02-51 clearing it forgets the wizard: a closed month does not '
        'resume one', () async {
      await s.ledger.saveCloseProgress(
        s.bookId,
        period,
        const SavedCloseProgress(step: 'confirmAndLock'),
      );
      await s.ledger.clearCloseProgress(s.bookId, period);
      expect(await s.ledger.closeProgress(s.bookId, period), isNull);
    });
  });

  // The companion is exercised above through the facade; this pins the row
  // shape the facade writes, so a schema change that silently drops the
  // confirmed set fails here rather than in a shopkeeper's kitchen.
  test(
    'F1-02-51 the stored row is (book, year, month) → step + banks',
    () async {
      final db = s.ledger.db;
      await db
          .into(db.closeProgressLocal)
          .insertOnConflictUpdate(
            CloseProgressLocalCompanion.insert(
              bookId: s.bookId,
              year: period.year,
              month: period.month,
              step: 'countCash',
              confirmedBanksJson: const Value('["a","b"]'),
            ),
          );
      final row = (await db.select(db.closeProgressLocal).get()).single;
      expect(row.bookId, s.bookId);
      expect(row.step, 'countCash');
      expect(row.confirmedBanksJson, '["a","b"]');
    },
  );
}
