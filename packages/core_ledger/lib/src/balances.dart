import 'accounts.dart';
import 'money.dart';

/// Balances of every account in a book (02 §9): derived, never stored
/// authoritatively. Signed: Dr +, Cr −. Zero balances are not stored, so two
/// vectors are equal iff every account carries the same non-zero balance, and
/// [canonical] is byte-identical on every device for the same envelope set
/// (02 §8 step 4, 03 §7 *Determinism*). Hashing belongs to `core_crypto`.
final class BalanceVector {
  /// Creates a vector; zero entries are dropped.
  BalanceVector(Map<String, Paise> balances)
    : _map = Map.unmodifiable({
        for (final e in balances.entries)
          if (!e.value.isZero) e.key: e.value,
      });

  final Map<String, Paise> _map;

  /// Balance of [accountId]; zero when absent.
  Paise operator [](String accountId) => _map[accountId] ?? Paise.zero;

  /// Non-zero balances by account id.
  Map<String, Paise> get nonZero => _map;

  /// Sum of debit balances.
  Paise get totalDebits => Paise.sum(_map.values.where((p) => p.isDebit));

  /// Sum of credit balances, as a positive magnitude.
  Paise get totalCredits => -Paise.sum(_map.values.where((p) => p.isCredit));

  /// The books-balanced check (02 §8: the always-visible integrity card).
  bool get isBalanced => totalDebits == totalCredits;

  /// Canonical text form: one `account_id<TAB>paise` line per non-zero balance,
  /// sorted by account id. The input to the close-hash.
  String canonical() {
    final ids = _map.keys.toList()..sort();
    final b = StringBuffer();
    for (final id in ids) {
      b
        ..write(id)
        ..write('\t')
        ..write(_map[id]!.raw)
        ..write('\n');
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) {
    if (other is! BalanceVector || other._map.length != _map.length) {
      return false;
    }
    for (final e in _map.entries) {
      if (other._map[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => canonical().hashCode;

  @override
  String toString() =>
      'BalanceVector(${_map.length} accounts, Dr ${totalDebits.raw} / Cr ${totalCredits.raw})';
}

/// Where a balance sits on the balance sheet or P&L (02 §1.2: placement by
/// sign — the user never classifies anything).
enum Placement {
  /// Money Dr, party Dr (*you will get*), advance, partner Dr (*they owe the business*).
  asset,

  /// Money Cr (overdraft), party Cr (*you will give*), partner Cr (*business owes them*).
  liability,

  /// Income categories (P&L).
  income,

  /// Expense categories (P&L).
  expense,

  /// Opening Balance, Adjustments, Suspense, Profit Distributed…
  equity,

  /// Due to/from {Book} pairs (02 §6).
  interBook,
}

/// Report placement of [account] carrying [balance].
Placement placementOf(Account account, Paise balance) =>
    switch (account.accountClass) {
      AccountClass.money || AccountClass.party || AccountClass.advance =>
        balance.isCredit ? Placement.liability : Placement.asset,
      AccountClass.partner =>
        balance.isDebit ? Placement.asset : Placement.liability,
      AccountClass.categoryIncome => Placement.income,
      AccountClass.categoryExpense => Placement.expense,
      AccountClass.equitySystem =>
        account.systemRole == SystemRole.dueToFrom
            ? Placement.interBook
            : Placement.equity,
    };
