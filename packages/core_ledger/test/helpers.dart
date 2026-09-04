// Shared builders for suite A (09 §2 A). Synthetic data only — never real entries.
import 'package:core_ledger/core_ledger.dart';

/// A book under test: a chart of accounts plus a monotonically increasing HLC
/// so entries are created in causal order without touching any clock.
class TestBook {
  TestBook(this.bookId, {this.bookType = BookType.family});

  final String bookId;
  final BookType bookType;
  final Map<String, Account> _accounts = {};
  int _order = 0;
  int _hlc = 1000;

  Chart get chart => Chart(bookId: bookId, accounts: _accounts.values.toList());

  Hlc nextHlc() => Hlc(_hlc++);

  Account acct(
    String name,
    AccountClass accountClass, {
    MoneySubtype? subtype,
    SystemRole? systemRole,
    String? memberId,
    String? counterpartBookId,
  }) {
    final id =
        '$bookId:${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
    final a = Account(
      id: id,
      bookId: bookId,
      name: name,
      accountClass: accountClass,
      subtype: subtype,
      systemRole: systemRole,
      memberId: memberId,
      counterpartBookId: counterpartBookId,
      createdOrder: _order++,
    );
    _accounts[id] = a;
    return a;
  }

  Account money(String name, {MoneySubtype subtype = MoneySubtype.saving}) =>
      acct(name, AccountClass.money, subtype: subtype);
  Account cash(String name) =>
      acct(name, AccountClass.money, subtype: MoneySubtype.cash);
  Account party(String name) => acct(name, AccountClass.party);
  Account income(String name) => acct(name, AccountClass.categoryIncome);
  Account expense(String name) => acct(name, AccountClass.categoryExpense);
  Account advance(String member) =>
      acct('Advance – $member', AccountClass.advance, memberId: member);
  Account partner(String owner) => acct(
    '$owner — Partner Current A/c',
    AccountClass.partner,
    memberId: owner,
  );
  Account openingBalance() => acct(
    'Opening Balance',
    AccountClass.equitySystem,
    systemRole: SystemRole.openingBalance,
  );
  Account adjustments() => acct(
    'Adjustments',
    AccountClass.equitySystem,
    systemRole: SystemRole.adjustments,
  );
  Account suspense() => acct(
    'Suspense',
    AccountClass.equitySystem,
    systemRole: SystemRole.suspense,
  );
  Account profitDistributed() => acct(
    'Profit Distributed',
    AccountClass.equitySystem,
    systemRole: SystemRole.profitDistributed,
  );
  Account dueToFrom(String otherBook) => acct(
    'Due to/from $otherBook',
    AccountClass.equitySystem,
    systemRole: SystemRole.dueToFrom,
    counterpartBookId: otherBook,
  );

  /// A posted entry with the given lines. Defaults are the common case: not
  /// flagged, authored by `u1` on `d1`, dated [date] (default 2026-05-10).
  Entry entry(
    List<Line> lines, {
    String? id,
    EntryKind kind = EntryKind.moneyOut,
    EntryStatus status = EntryStatus.posted,
    LocalDate? date,
    bool reviewRequired = false,
    Paise? reviewLimit,
    String? reviewApprover,
    EntryRefs refs = const EntryRefs(),
    String createdByUser = 'u1',
    String createdByDevice = 'd1',
    String? note,
    Hlc? hlc,
    String? partyId,
    String? advanceId,
  }) {
    final h = hlc ?? nextHlc();
    return Entry(
      id: id ?? 'e${h.raw}',
      bookId: bookId,
      kind: kind,
      status: status,
      reviewRequired: reviewRequired,
      reviewLimitPaise: reviewLimit,
      reviewApprover: reviewApprover,
      accountingDate: date ?? LocalDate(2026, 5, 10),
      lines: lines,
      refs: refs,
      note: note,
      createdByUser: createdByUser,
      createdByDevice: createdByDevice,
      hlc: h,
      partyId: partyId,
      advanceId: advanceId,
    );
  }
}

Paise rs(int rupees) => Paise.rupees(rupees);
Line dr(Account a, Paise p) => Line(accountId: a.id, amount: p);
Line cr(Account a, Paise p) => Line(accountId: a.id, amount: -p);
LocalDate d(int y, int m, int day) => LocalDate(y, m, day);
