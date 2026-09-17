// F1-07-136…139: the [CloseSource] contract, run against **both**
// implementations — `FakeCloseSource`, which S10's widget tests drive, and
// `LedgerCloseSource`, which the app ships.
//
// The fake is the behaviour contract (07 §13 🔒, 02 §8 🔒). A screen proved
// green against a fake that refuses differently from the ledger is a screen
// proved against nothing, so every expectation below runs twice: once on each.
// Where the two cannot be made identical the difference is stated, not hidden
// — the fake answers from a drawn `CloseView`, the real one from a projection.
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/close/close_fake.dart';
import 'package:rukka_folio/features/close/close_source.dart';
import 'package:rukka_folio/features/close/ledger_close_source.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

/// One case of the contract: a name, a source, and the book/period to ask it
/// about.
typedef Subject = ({
  String name,
  CloseSource source,
  String bookId,
  YearMonth period,
});

void main() {
  late SeededLedger s;
  late YearMonth period;
  late LedgerCloseSource real;

  setUp(() async {
    s = await seedSoloLedger();
    period = s.ledger.today().yearMonth;
    real = LedgerCloseSource(s.ledger);
  });

  /// The fake, drawn from whatever the real source currently says — so the two
  /// start from the same picture and any divergence below is behavioural.
  Future<FakeCloseSource> mirrorOfReal() async =>
      FakeCloseSource(view: await real.loadClose(s.bookId, period));

  Future<List<Subject>> bothSources() async => [
    (name: 'LedgerCloseSource', source: real, bookId: s.bookId, period: period),
    (
      name: 'FakeCloseSource',
      source: await mirrorOfReal(),
      bookId: s.bookId,
      period: period,
    ),
  ];

  group('loadClose (02 §8 steps 1–2)', () {
    test(
      'F1-07-136 both sources draw the same book, month and money A/Cs, cash '
      'apart from bank, every figure integer paise',
      () async {
        for (final it in await bothSources()) {
          final view = await it.source.loadClose(it.bookId, it.period);
          expect(view.bookId, s.bookId, reason: it.name);
          expect(view.period, period, reason: it.name);
          // The seeded book has one cash A/C and one saving A/C (07 §6).
          expect(
            view.cashAccounts.map((a) => a.accountId),
            contains(s.cashId),
            reason: it.name,
          );
          expect(
            view.bankAccounts.map((a) => a.accountId),
            contains(s.bankId),
            reason: it.name,
          );
          expect(
            view.cashAccounts.map((a) => a.accountId),
            isNot(contains(s.bankId)),
            reason: it.name,
          );
          for (final p in view.declaredBalances.values) {
            expect(p.raw, isA<int>(), reason: it.name);
          }
        }
      },
    );

    test(
      'F1-07-136 the balances are the ledger\'s own, not a second derivation '
      '(02 §9)',
      () async {
        final state = (await s.ledger.rebuild(s.bookId)).state;
        final view = await real.loadClose(s.bookId, period);
        expect(view.declaredBalances[s.cashId], state.balances[s.cashId]);
        expect(view.declaredBalances[s.bankId], state.balances[s.bankId]);
      },
    );

    test('F1-07-137 an uncounted cash A/C warns and never blocks (02 §8 step 1 '
        '🔒) — the seeded book has never been counted', () async {
      for (final it in await bothSources()) {
        final view = await it.source.loadClose(it.bookId, it.period);
        expect(
          view.cashAccounts.every((a) => !a.countedInPeriod),
          isTrue,
          reason: it.name,
        );
        expect(
          view.tray.warns.map((w) => w.kind),
          contains(CloseWarning.unverifiedCount),
          reason: it.name,
        );
        // Warn-only: the lock is still offered.
        expect(view.tray.canLock, isTrue, reason: it.name);
      }
    });
  });

  group('blocks and warns stay different types (07 §13 🔒)', () {
    setUp(() async {
      // One over-limit entry awaiting its approver — 02 §3's open review flag,
      // which 02 §8 step 3 makes a **blocker**.
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
    });

    test('F1-07-137 an open review flag arrives as the engine\'s own '
        'CloseBlocker, in blocks — never folded into warns', () async {
      for (final it in await bothSources()) {
        final view = await it.source.loadClose(it.bookId, it.period);
        expect(
          view.tray.blocks.map((b) => b.kind),
          contains(CloseBlocker.reviewFlagOpen),
          reason: it.name,
        );
        expect(view.tray.canLock, isFalse, reason: it.name);
        // Warnings are a different type and cannot carry a blocker.
        expect(view.tray.warns, isA<List<CloseWarningItem>>(), reason: it.name);
      }
    });

    test(
      'F1-07-138 lock() throws CloseRefused carrying the engine\'s items, and '
      'the month stays open — identical on both sources',
      () async {
        for (final it in await bothSources()) {
          await expectLater(
            it.source.lock(
              bookId: it.bookId,
              period: it.period,
              declaredBalances: const {},
            ),
            throwsA(
              isA<CloseRefused>().having(
                (r) => r.blockers.map((b) => b.kind),
                'blockers',
                contains(CloseBlocker.reviewFlagOpen),
              ),
            ),
            reason: it.name,
          );
        }
        final state = (await s.ledger.rebuild(s.bookId)).state;
        expect(state.periods.currentStatus(period), PeriodStatus.open);
      },
    );
  });

  group('lock (02 §8 step 4 🔒)', () {
    test(
      'F1-07-138 a clean month locks on both, and the real one publishes the '
      'projector\'s vector and projectorVersion',
      () async {
        final fake = await mirrorOfReal();
        final view = await real.loadClose(s.bookId, period);

        final fakeResult = await fake.lock(
          bookId: s.bookId,
          period: period,
          declaredBalances: view.declaredBalances,
        );
        expect(fakeResult.lock.declaredBalances, view.declaredBalances);
        expect(fakeResult.lock.vectorCanonical, isNotNull);
        expect(fakeResult.lock.projectorVersion, isNotNull);

        final expectedVector = (await s.ledger.rebuild(s.bookId)).state.balances
            .canonical();
        final realResult = await real.lock(
          bookId: s.bookId,
          period: period,
          declaredBalances: view.declaredBalances,
        );
        expect(realResult.lock.declaredBalances, view.declaredBalances);
        expect(realResult.lock.vectorCanonical, expectedVector);
        expect(realResult.lock.projectorVersion, projectorVersion);
        expect(realResult.verification, CloseVerification.verified);
      },
    );

    test(
      'F1-07-138 locking clears the saved progress — a closed month does not '
      'resume a wizard',
      () async {
        await real.saveProgress(
          s.bookId,
          period,
          const CloseProgress(step: CloseStep.confirmAndLock),
        );
        await real.lock(
          bookId: s.bookId,
          period: period,
          declaredBalances: const {},
        );
        expect(await s.ledger.closeProgress(s.bookId, period), isNull);
      },
    );
  });

  group('resumable (07 §13 🔒)', () {
    test('F1-07-139 progress saved at a step is what the next loadClose hands '
        'back — on both sources', () async {
      for (final it in await bothSources()) {
        const progress = CloseProgress(step: CloseStep.clearTray);
        await it.source.saveProgress(it.bookId, it.period, progress);
        final view = await it.source.loadClose(it.bookId, it.period);
        expect(view.progress.step, CloseStep.clearTray, reason: it.name);
      }
    });

    test(
      'F1-07-139 the confirmed banks resume too — re-confirming eight A/Cs is '
      'the loss of work the rule exists to prevent',
      () async {
        for (final it in await bothSources()) {
          final progress = CloseProgress(
            step: CloseStep.confirmBanks,
            confirmedBankIds: {s.bankId},
          );
          await it.source.saveProgress(it.bookId, it.period, progress);
          final view = await it.source.loadClose(it.bookId, it.period);
          expect(view.progress.confirmedBankIds, {s.bankId}, reason: it.name);
        }
      },
    );

    test(
      'F1-07-139 a fresh close starts at step 1 with nothing confirmed',
      () async {
        for (final it in await bothSources()) {
          final view = await it.source.loadClose(it.bookId, it.period);
          expect(view.progress.step, CloseStep.countCash, reason: it.name);
          expect(view.progress.confirmedBankIds, isEmpty, reason: it.name);
        }
      },
    );

    test(
      'F1-07-139 progress written by a build that named its steps differently '
      'restarts the wizard rather than crashing it',
      () async {
        await s.ledger.saveCloseProgress(
          s.bookId,
          period,
          const SavedCloseProgress(step: 'a-step-this-build-does-not-have'),
        );
        final view = await real.loadClose(s.bookId, period);
        expect(view.progress.step, CloseStep.countCash);
      },
    );
  });
}
