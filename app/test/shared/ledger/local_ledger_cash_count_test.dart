// F1-02-29…35: the app's cash-count surface on `LocalLedger` — 02 §8.2 🔒.
//
// The engine already owns what a count *means* (`countPolicy`,
// `validateCount`, `resolveCount`, A-02-83…92); these tests pin the facade
// over it: the count is recorded as its own envelope, the outcome is posted
// **unchanged** — nothing, one guided adjustment, or one recognition — and a
// count never moves money by itself (02 §8.2 🔒).
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../test_app.dart';

Future<int> envelopeCount(SeededLedger s) async =>
    (await s.ledger.db.select(s.ledger.db.envelopesLocal).get()).length;

Future<Paise> balanceOf(SeededLedger s, String bookId, String accountId) async {
  final rows = await s.ledger.watchAccounts(bookId).first;
  return Paise(rows.firstWhere((r) => r.account.id == accountId).balancePaise);
}

Future<Account> accountNamed(
  SeededLedger s,
  String bookId,
  String name,
) async =>
    (await s.ledger.chartOf(bookId)).accounts.firstWhere((a) => a.name == name);

void main() {
  late SeededLedger s;

  setUp(() async => s = await seedSoloLedger());

  group(
    'verification — a cash account whose balance is known (02 §8.2 🔒)',
    () {
      test('F1-02-29 an equal count posts nothing and is still recorded: '
          '*verified on {date}*', () async {
        final before = await envelopeCount(s);
        final entriesBefore =
            (await s.ledger.watchStatement(s.cashId).first).length;
        final result = await s.ledger.recordCashCount(
          accountId: s.cashId,
          counted: const Paise(21_600_00),
          date: s.ledger.today(),
          sheet: const DenominationSheet(
            notes: {500: 43, 100: 1},
            coinsPaise: Paise(0),
          ),
        );
        expect(result.outcome, isA<CountVerified>());
        expect(result.entry, isNull, reason: 'a count never moves money');
        expect(
          await envelopeCount(s),
          before + 1,
          reason: 'one envelope: the count itself',
        );
        expect(
          (await s.ledger.watchStatement(s.cashId).first).length,
          entriesBefore,
        );
        final last = await s.ledger.lastCashCount(s.cashId);
        expect(last, isNotNull);
        expect(last!.counted, const Paise(21_600_00));
        expect(last.date, s.ledger.today());
        expect(last.sheet?.notes[500], 43, reason: 'the sheet is a snapshot');
      });

      test(
        'F1-02-30 a different count posts exactly one guided adjustment — '
        'Dr/Cr Cash · Cr/Dr Adjustments, the count attached as evidence',
        () async {
          final result = await s.ledger.recordCashCount(
            accountId: s.cashId,
            counted: const Paise(21_100_00),
            date: s.ledger.today(),
          );
          expect(result.outcome, isA<CountAdjustment>());
          expect(
            (result.outcome as CountAdjustment).difference,
            const Paise(-500_00),
          );
          final entry = result.entry!;
          expect(entry.kind, EntryKind.adjustment);
          final adjustments = await accountNamed(s, s.bookId, 'Adjustments');
          expect(adjustments.systemRole, SystemRole.adjustments);
          expect(entry.lines.map((l) => (l.accountId, l.amount.raw)).toSet(), {
            (s.cashId, -500_00),
            (adjustments.id, 500_00),
          });
          expect(
            entry.refs.extra['cash_count'],
            result.count.id,
            reason: 'the count is the evidence for the adjustment (02 §8.2 🔒)',
          );
          // The books now agree with the floor.
          expect(
            await balanceOf(s, s.bookId, s.cashId),
            const Paise(21_100_00),
          );
        },
      );

      test('F1-02-31 a sheet whose total is not the counted figure is refused; '
          'nothing is authored', () async {
        final before = await envelopeCount(s);
        await expectLater(
          s.ledger.recordCashCount(
            accountId: s.cashId,
            counted: const Paise(21_600_00),
            date: s.ledger.today(),
            sheet: const DenominationSheet(notes: {500: 1}),
          ),
          throwsA(
            isA<CountRejected>().having(
              (e) => e.violations.map((v) => v.kind),
              'kinds',
              contains(ViolationKind.countSheetMismatch),
            ),
          ),
        );
        expect(await envelopeCount(s), before);
        expect(await s.ledger.lastCashCount(s.cashId), isNull);
      });
    },
  );

  group('recognition — a collection box nobody knows the inside of', () {
    late String trustId;
    late Account gollak;
    late Account donations;
    late Account trustCash;

    setUp(() async {
      trustId = await s.ledger.createBook(
        name: 'Gurdwara Sahib',
        type: BookType.organization,
      );
      gollak = await accountNamed(s, trustId, 'Gollak Cash');
      donations = await accountNamed(s, trustId, 'Donation Income');
      trustCash = await accountNamed(s, trustId, 'Cash');
    });

    test('F1-02-32 a gollak count recognises income for the full amount and '
        'leaves the money in the box (02 §8.2 🔒)', () async {
      final result = await s.ledger.recordCashCount(
        accountId: gollak.id,
        counted: const Paise(12_450_00),
        date: s.ledger.today(),
        sheet: const DenominationSheet(
          notes: {500: 20, 100: 24, 10: 5},
          coinsPaise: Paise(0),
        ),
        countedBy: 'Gurmeet Singh',
        witness: 'Baljit Kaur',
        incomeAccountId: donations.id,
      );
      expect(result.outcome, isA<CountRecognition>());
      final entry = result.entry!;
      expect(entry.kind, EntryKind.moneyIn);
      expect(entry.lines.map((l) => (l.accountId, l.amount.raw)).toSet(), {
        (gollak.id, 12_450_00),
        (donations.id, -12_450_00),
      });
      // The counted cash is still in the box: depositing it later is an
      // ordinary Transfer (02 §8.2 🔒 *A count never moves money*).
      expect(await balanceOf(s, trustId, gollak.id), const Paise(12_450_00));
      expect(await balanceOf(s, trustId, trustCash.id), Paise.zero);
    });

    test(
      'F1-02-33 a trust count without the denomination sheet, and a '
      'collection count without two names, are both refused (02 §8.2 🔒)',
      () async {
        await expectLater(
          s.ledger.recordCashCount(
            accountId: trustCash.id,
            counted: const Paise(500_00),
            date: s.ledger.today(),
          ),
          throwsA(
            isA<CountRejected>().having(
              (e) => e.violations.map((v) => v.kind),
              'kinds',
              contains(ViolationKind.countSheetRequired),
            ),
          ),
        );
        await expectLater(
          s.ledger.recordCashCount(
            accountId: gollak.id,
            counted: const Paise(500_00),
            date: s.ledger.today(),
            sheet: const DenominationSheet(notes: {500: 1}),
            countedBy: 'Gurmeet Singh',
            incomeAccountId: donations.id,
          ),
          throwsA(
            isA<CountRejected>().having(
              (e) => e.violations.map((v) => v.kind),
              'kinds',
              contains(ViolationKind.countNamesRequired),
            ),
          ),
        );
      },
    );

    test('F1-02-34 the reading S5.5 and the S4 header draw: book, type, '
        'balance, income categories, last count', () async {
      final reading = await s.ledger.cashCountReading(gollak.id);
      expect(reading.bookId, trustId);
      expect(reading.bookType, BookType.organization);
      expect(reading.account.isCollection, isTrue);
      expect(reading.bookBalance, Paise.zero);
      expect(reading.lastCount, isNull);
      expect(
        reading.incomeAccounts.map((a) => a.name),
        contains('Donation Income'),
        reason: 'collect mode needs the *Record it as* picker',
      );

      await s.ledger.recordCashCount(
        accountId: gollak.id,
        counted: const Paise(1_000_00),
        date: s.ledger.today(),
        sheet: const DenominationSheet(notes: {500: 2}),
        countedBy: 'Gurmeet Singh',
        witness: 'Baljit Kaur',
        incomeAccountId: donations.id,
      );
      final after = await s.ledger.cashCountReading(gollak.id);
      expect(after.lastCount?.counted, const Paise(1_000_00));
      expect(after.bookBalance, const Paise(1_000_00));
    });
  });

  test('F1-02-35 an account that is not counted at all is refused before '
      'anything is authored', () async {
    final before = await envelopeCount(s);
    await expectLater(
      s.ledger.recordCashCount(
        accountId: s.salesId,
        counted: const Paise(100),
        date: s.ledger.today(),
      ),
      throwsArgumentError,
    );
    expect(await envelopeCount(s), before);
  });
}
