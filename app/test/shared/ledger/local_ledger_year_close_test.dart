// F1-02-68…79: the **Year Close ceremony** on `LocalLedger` — 02 §8.1 🔒,
// ADR 2026-09-05c §3 🔒, ADR 2026-09-05e §2 and §4, ADR 2026-09-09 §4 🔒.
//
// What these tests hold in place:
//
//  · **what blocks is the engine's** — `yearClosePreconditions(state, chart,
//    fy)` — with the mirror's own facts (an author-sequence hole, a `held`
//    envelope) *unioned in* and never substituted, exactly as the month lock
//    does. A blocker may be added here; none may be dropped;
//  · **the vector is the projector's** — `closingVector`, not a second sum
//    computed in the app layer (03 §3.3 rule 2). What is carried (money,
//    party, advance, partner, equity_system) and what is not (categories, as
//    one net-result line) is the engine's rule, asserted here as *the shape
//    the facade hands on unchanged*;
//  · **a refusal appends nothing** and **a close appends exactly one**
//    envelope, carrying `projectorVersion` so a reader on an older projector
//    reads *update to verify* rather than a false mismatch;
//  · **the verification comes back out of the rebuilt projection**, never from
//    an assumption that the write succeeded;
//  · **`certifiedYears` is empty until the first close** — which is what makes
//    ADR 2026-09-09 §4 🔒's *no FY switcher at all* true by construction.
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

/// 10 May 2027 — FY 2026-27 is wholly in the past, so every one of its months
/// can be locked while *today* stays in the open FY 2027-28.
DateTime _may2027() => DateTime(2027, 5, 10, 10);

void main() {
  late LocalLedger ledger;
  late String bookId;
  late String cashId;
  late String fuelId;
  late String salesId;
  late FinancialYear fy;

  setUp(() async {
    ledger = await openTestLedger(now: _may2027);
    await ledger.bootstrapSolo(
      firstBookName: 'Me',
      startDate: LocalDate(2026, 4, 1),
    );
    bookId = (await ledger.mirror.bookIds()).single;
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
    salesId = (await ledger.addAccount(
      bookId,
      name: 'Shop sales',
      accountClass: AccountClass.categoryIncome,
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
    await ledger.moneyIn(
      bookId: bookId,
      into: cashId,
      from: salesId,
      paise: 500_000,
      date: LocalDate(2026, 8, 20),
      note: 'Sales',
    );
  });

  /// Locks every month of [fy] — the one precondition the ceremony cannot
  /// clear for itself (02 §8.1 🔒: every month locked).
  Future<void> lockEveryMonth() async {
    for (final m in fy.months) {
      await ledger.lockMonth(bookId, m, declaredBalances: const {});
    }
  }

  Future<List<EnvelopesLocalData>> envelopes(String objectType) =>
      (ledger.db.select(
        ledger.db.envelopesLocal,
      )..where((t) => t.objectType.equals(objectType))).get();

  group('what blocks (02 §8.1 🔒, ADR 2026-09-05e §4)', () {
    test('F1-02-68 every month of the year that is not locked is a monthOpen '
        'blocker naming that month — the checklist can say where to go, not '
        'just that something is wrong (07 §1 rule 6)', () async {
      final blockers = await ledger.yearClosePreconditions(bookId, fy);
      final months = [
        for (final b in blockers)
          if (b.kind == CloseBlocker.monthOpen) b.ref,
      ];
      expect(months, hasLength(12));
      expect(months, contains(YearMonth(2026, 4).toString()));
      expect(months, contains(YearMonth(2027, 3).toString()));
    });

    test('F1-02-69 with every month locked the list is empty — the only '
        'condition closeYear proceeds under (02 §8.1 🔒)', () async {
      await lockEveryMonth();
      expect(await ledger.yearClosePreconditions(bookId, fy), isEmpty);
    });

    test(
      'F1-02-70 the mirror\'s own facts are unioned in, never substituted, '
      'and deduplicated by (kind, ref): an author-sequence hole the '
      'projection has not got still refuses the year (ADR 2026-09-05b §3)',
      () async {
        await lockEveryMonth();
        for (final seq in [7, 8]) {
          await ledger.db
              .into(ledger.db.authorGaps)
              .insert(
                AuthorGapsCompanion.insert(
                  bookId: bookId,
                  authorDevice: 'device-b',
                  expectedSeq: seq,
                  sinceHlc: 100 + seq,
                ),
              );
        }
        final blockers = await ledger.yearClosePreconditions(bookId, fy);
        final gaps = blockers.where(
          (b) => b.kind == CloseBlocker.authorGapOpen,
        );
        // Two holes in one author's sequence are one blocker: the union
        // deduplicates by (kind, ref) rather than counting rows.
        expect(gaps, hasLength(1));
        expect(gaps.single.ref, 'device-b');
      },
    );
  });

  group('the vector is the projector\'s (ADR 2026-09-05e §2 🔒)', () {
    test(
      'F1-02-71 yearClosingVector carries the balance-sheet accounts and '
      'one net-result line, never a category account, and it balances',
      () async {
        final v = await ledger.yearClosingVector(bookId, fy);
        expect(v[cashId], Paise(2_500_000 - 240_000 + 500_000));
        expect(v.nonZero.containsKey(fuelId), isFalse);
        expect(v.nonZero.containsKey(salesId), isFalse);
        final net = v.nonZero.keys.where(isNetResultKey).toList();
        expect(net, hasLength(1));
        expect(v[net.single], Paise(240_000 - 500_000));
        expect(v.isBalanced, isTrue);
      },
    );
  });

  group('the ceremony (02 §8.1 🔒)', () {
    test('F1-02-72 a refusal appends nothing: while a month is open closeYear '
        'throws YearCertifyRefused carrying the engine\'s own items and no '
        'year_close envelope exists', () async {
      await expectLater(
        ledger.closeYear(bookId, fy),
        throwsA(
          isA<YearCertifyRefused>().having(
            (e) => e.blockers.map((b) => b.kind).toSet(),
            'blockers',
            contains(CloseBlocker.monthOpen),
          ),
        ),
      );
      expect(await envelopes('year_close'), isEmpty);
    });

    test('F1-02-73 closeYear authors exactly ONE year_close envelope, and the '
        'vector it carries is the projector\'s own — the bytes every other '
        'device replays (03 §3.3 rule 2)', () async {
      await lockEveryMonth();
      final expected = await ledger.yearClosingVector(bookId, fy);
      final result = await ledger.closeYear(bookId, fy);
      expect(await envelopes('year_close'), hasLength(1));
      expect(result.close.vector, expected);
      expect(result.close.vector.canonical(), expected.canonical());
      expect(result.close.financialYear, fy);
    });

    test('F1-02-74 the close records core_ledger\'s own projectorVersion, so a '
        'reader on an older projector reads *update to verify* rather than a '
        'false mismatch (ADR 2026-09-05c §3 🔒)', () async {
      await lockEveryMonth();
      final result = await ledger.closeYear(bookId, fy);
      expect(result.close.projectorVersion, projectorVersion);
    });

    test('F1-02-75 the verification comes back out of the REBUILT projection, '
        'not from an assumption that the write succeeded '
        '(ADR 2026-09-05c §3 🔒)', () async {
      await lockEveryMonth();
      final result = await ledger.closeYear(bookId, fy);
      expect(result.verification, CloseVerification.verified);
      final rows = await (ledger.db.select(
        ledger.db.yearCloseP,
      )..where((t) => t.bookId.equals(bookId))).get();
      expect(rows.single.state, YearStatus.closed.name);
      expect(rows.single.verification, 'verified');
    });

    test('F1-02-76 a second close of a sealed year is refused and appends '
        'nothing — 02 §8.1 🔒 gives a certificate exactly one way back, and it '
        'is not a second certificate', () async {
      await lockEveryMonth();
      await ledger.closeYear(bookId, fy);
      await expectLater(
        ledger.closeYear(bookId, fy),
        throwsA(
          isA<YearAlreadyClosed>().having(
            (e) => e.status,
            'status',
            YearStatus.closed,
          ),
        ),
      );
      expect(await envelopes('year_close'), hasLength(1));
    });
  });

  group('certifiedYears (ADR 2026-09-09 §4 🔒)', () {
    test('F1-02-77 empty before the first close — which is what makes *no FY '
        'switcher at all* true by construction, not by a flag a screen has to '
        'remember', () async {
      expect(await ledger.certifiedYears(bookId), isEmpty);
      await lockEveryMonth();
      expect(await ledger.certifiedYears(bookId), isEmpty);
    });

    test(
      'F1-02-78 after a close it lists that year, closed, with this '
      'device\'s verification and the book\'s carried-forward total',
      () async {
        await lockEveryMonth();
        await ledger.closeYear(bookId, fy);
        final years = await ledger.certifiedYears(bookId);
        expect(years, hasLength(1));
        final row = years.single;
        expect(row.year, fy);
        expect(row.status, YearStatus.closed);
        expect(row.verification, CloseVerification.verified);
        expect(row.carriedForward, Paise(2_760_000));
      },
    );

    test('F1-02-79 the row carries the whole certified vector, so one A/C\'s '
        'b/f is read from it rather than recomputed — the figure S4\'s '
        'switcher shows beside the year (ADR 2026-09-09 §4 🔒)', () async {
      await lockEveryMonth();
      await ledger.closeYear(bookId, fy);
      final row = (await ledger.certifiedYears(bookId)).single;
      expect(row.vector, isNotNull);
      expect(row.carriedForwardFor(cashId), Paise(2_760_000));
      // A category account carries nothing forward: it is not in the vector.
      expect(row.carriedForwardFor(fuelId), Paise.zero);
    });
  });
}
