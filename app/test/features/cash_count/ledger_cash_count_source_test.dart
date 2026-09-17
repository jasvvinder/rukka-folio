// F1-02-36…39: [LedgerCashCountSource] over a real `LocalLedger`, held to the
// **same** expectations as `FakeCashCountSource` (02 §8.2 🔒).
//
// The fake is the behaviour contract S5.5 was built against, so every
// expectation here runs twice — once against the fake, once against the
// ledger. A screen that is green on the fake is then green on the ledger for
// the same reason: both defer to the engine's `validateCount` / `resolveCount`
// and neither re-decides what a count means.
//
// In-memory SQLite, injected clock, synthetic amounts (CLAUDE.md rule 4).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/cash_count/cash_count_fake.dart';
import 'package:rukka_folio/features/cash_count/cash_count_source.dart';
import 'package:rukka_folio/features/cash_count/ledger_cash_count_source.dart';

import '../../shared/test_app.dart';

/// One book set up for counting, and the source that reads it.
typedef Counted = ({
  CashCountSource source,
  String cashId,
  String gollakId,
  String incomeId,
  LocalDate today,
  // The fake serves a fixed balance; the ledger re-reads its own. This lets
  // one expectation run against both without the fake pretending to post.
  void Function(Paise) cashBalanceIsNow,
});

Future<Account> _named(SeededLedger s, String bookId, String name) async =>
    (await s.ledger.chartOf(bookId)).accounts.firstWhere((a) => a.name == name);

/// The ledger-backed source over a trust book: a plain Cash A/c with a known
/// balance and a gollak that has never been opened.
Future<Counted> ledgerBacked() async {
  final s = await seedSoloLedger();
  final trustId = await s.ledger.createBook(
    name: 'Gurdwara Sahib',
    type: BookType.organization,
  );
  final cash = await _named(s, trustId, 'Cash');
  final gollak = await _named(s, trustId, 'Gollak Cash');
  final donations = await _named(s, trustId, 'Donation Income');
  final opening = await _named(s, trustId, 'Opening Balance');
  await s.ledger.post(
    Entry(
      id: '',
      bookId: trustId,
      kind: EntryKind.adjustment,
      status: EntryStatus.posted,
      reviewRequired: false,
      accountingDate: s.ledger.today(),
      lines: Verbs.openingBalance(
        account: cash,
        balance: const Paise(5_000_00),
        openingAccount: opening,
      ),
      createdByUser: s.ledger.identity.userId,
      createdByDevice: s.ledger.identity.deviceId,
      hlc: const Hlc(0),
    ),
  );
  return (
    source: LedgerCashCountSource(s.ledger),
    cashId: cash.id,
    gollakId: gollak.id,
    incomeId: donations.id,
    today: s.ledger.today(),
    cashBalanceIsNow: (_) {},
  );
}

/// The same book, in memory: the fake serves one target at a time, so the two
/// accounts are two fakes over one synthetic chart.
Future<Counted> fakeBacked() async {
  Account a(String id, String name, AccountClass c, {MoneySubtype? sub}) =>
      Account(
        id: id,
        bookId: 'trust',
        name: name,
        accountClass: c,
        subtype: sub,
        createdOrder: 0,
      );
  final cash = a('cash', 'Cash', AccountClass.money, sub: MoneySubtype.cash);
  final gollak = a(
    'gollak',
    'Gollak Cash',
    AccountClass.money,
    sub: MoneySubtype.cashCollection,
  );
  final donations = a(
    'donations',
    'Donation Income',
    AccountClass.categoryIncome,
  );
  final today = LocalDate(2026, 9, 7);
  final byAccount = {
    'cash': FakeCashCountSource(
      target: CashCountTarget(
        bookId: 'trust',
        bookType: BookType.organization,
        account: cash,
        bookBalance: const Paise(5_000_00),
        incomeAccounts: [donations],
      ),
    ),
    'gollak': FakeCashCountSource(
      target: CashCountTarget(
        bookId: 'trust',
        bookType: BookType.organization,
        account: gollak,
        bookBalance: Paise.zero,
        incomeAccounts: [donations],
      ),
    ),
  };
  return (
    source: _Routing(byAccount),
    cashId: 'cash',
    gollakId: 'gollak',
    incomeId: 'donations',
    today: today,
    cashBalanceIsNow: (Paise balance) {
      final fake = byAccount['cash']!;
      fake.target = CashCountTarget(
        bookId: 'trust',
        bookType: BookType.organization,
        account: cash,
        bookBalance: balance,
        incomeAccounts: [donations],
      );
    },
  );
}

/// Routes to the fake that holds the account asked for, so one [Counted] can
/// answer for both accounts exactly as the ledger does.
final class _Routing implements CashCountSource {
  _Routing(this.byAccount);

  final Map<String, FakeCashCountSource> byAccount;

  FakeCashCountSource _of(String id) =>
      byAccount[id] ?? (throw StateError('no such account: $id'));

  @override
  Future<CashCountTarget> loadTarget(String accountId) =>
      _of(accountId).loadTarget(accountId);

  @override
  Future<CashCountResult> saveCount(CashCountDraft draft) =>
      _of(draft.accountId).saveCount(draft);
}

void main() {
  for (final MapEntry(key: label, value: build)
      in <String, Future<Counted> Function()>{
        'fake (the contract)': fakeBacked,
        'LedgerCashCountSource': ledgerBacked,
      }.entries) {
    group(label, () {
      late Counted c;
      setUp(() async => c = await build());

      test('F1-02-36 loads the target, and the subtype chooses the mode '
          '(02 §8.2 🔒 *Two kinds of count*)', () async {
        final cash = await c.source.loadTarget(c.cashId);
        expect(cash.isCollection, isFalse);
        expect(cash.bookBalance, const Paise(5_000_00));
        expect(cash.bookType, BookType.organization);
        final gollak = await c.source.loadTarget(c.gollakId);
        expect(gollak.isCollection, isTrue);
        expect(gollak.lastCount, isNull);
        expect(gollak.incomeAccounts.map((a) => a.name), ['Donation Income']);
      });

      test('F1-02-37 a verification that differs comes back as one '
          'adjustment; an equal one posts nothing', () async {
        final adjusted = await c.source.saveCount(
          CashCountDraft(
            accountId: c.cashId,
            date: c.today,
            counted: const Paise(4_500_00),
            sheet: const DenominationSheet(notes: {500: 9}),
          ),
        );
        expect(adjusted.outcome, isA<CountAdjustment>());
        expect(
          (adjusted.outcome as CountAdjustment).difference,
          const Paise(-500_00),
        );
        expect(adjusted.postedEntryId, isNotNull);

        c.cashBalanceIsNow(const Paise(4_500_00));
        final verified = await c.source.saveCount(
          CashCountDraft(
            accountId: c.cashId,
            date: c.today,
            counted: const Paise(4_500_00),
            sheet: const DenominationSheet(notes: {500: 9}),
          ),
        );
        expect(
          verified.outcome,
          isA<CountVerified>(),
          reason: 'the books now agree with the floor',
        );
        expect(verified.postedEntryId, isNull);
        expect(verified.date, c.today);
      });

      test('F1-02-38 a gollak count is a recognition of income for the full '
          'counted amount (02 §8.2 🔒)', () async {
        final result = await c.source.saveCount(
          CashCountDraft(
            accountId: c.gollakId,
            date: c.today,
            counted: const Paise(12_450_00),
            sheet: const DenominationSheet(notes: {500: 24, 100: 4, 50: 1}),
            countedBy: 'Gurmeet Singh',
            witness: 'Baljit Kaur',
            incomeAccountId: c.incomeId,
          ),
        );
        expect(result.outcome, isA<CountRecognition>());
        expect(result.postedEntryId, isNotNull);
        expect(result.incomeAccountName, 'Donation Income');
      });

      test('F1-02-39 the engine\'s refusals arrive as CashCountRefused, '
          'carrying its own violations', () async {
        await expectLater(
          c.source.saveCount(
            CashCountDraft(
              accountId: c.gollakId,
              date: c.today,
              counted: const Paise(500_00),
              sheet: const DenominationSheet(notes: {500: 1}),
              countedBy: 'Gurmeet Singh',
              incomeAccountId: c.incomeId,
            ),
          ),
          throwsA(
            isA<CashCountRefused>().having(
              (e) => e.violations.map((v) => v.kind),
              'kinds',
              contains(ViolationKind.countNamesRequired),
            ),
          ),
        );
        await expectLater(
          c.source.saveCount(
            CashCountDraft(
              accountId: c.cashId,
              date: c.today,
              counted: const Paise(4_500_00),
              sheet: const DenominationSheet(notes: {500: 1}),
            ),
          ),
          throwsA(
            isA<CashCountRefused>().having(
              (e) => e.violations.map((v) => v.kind),
              'kinds',
              contains(ViolationKind.countSheetMismatch),
            ),
          ),
        );
      });
    });
  }
}
