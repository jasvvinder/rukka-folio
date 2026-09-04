/// Books and accounts (02 §1.1, §1.2).
library;

/// Book types (02 §1.1). Organization-tenant books are the same objects with
/// different display names; the type matters here only for cash-count policy
/// (02 §8.2: trust books always require the denomination sheet).
enum BookType {
  /// One person's own book.
  personal,

  /// A family or sub-family book.
  family,

  /// A joint / common-pool book.
  joint,

  /// A business book (single owner or shared, 02 §7.1).
  business,

  /// A trust / society / organization book (02 §8.2).
  organization,
}

/// Account classes (02 §1.2). Placement is by sign — there is no Debtor or
/// Creditor class; one party, one account, both roles.
enum AccountClass {
  /// Cash, bank accounts, cards, wallets. Dr = asset, Cr = liability.
  money,

  /// One account per person/shop/firm. Dr = you will get, Cr = you will give.
  party,

  /// `Advance – {member}`, one per member per book (02 §7).
  advance,

  /// `{Owner} — Partner Current A/c` (02 §7.1). Cr = business owes them.
  partner,

  /// Income categories (P&L).
  categoryIncome,

  /// Expense categories (P&L).
  categoryExpense,

  /// Opening Balance, Adjustments, Suspense, Due to/from {Book}, Profit Distributed…
  equitySystem,
}

/// Subtypes of `money` accounts (02 §1.2, §8.2).
enum MoneySubtype {
  /// Physical cash whose balance is known from entries: household cash, shop galla, vault.
  cash,

  /// A collection box (gollak, hundi, donation box): contents unknown until counted (02 §8.2).
  cashCollection,

  /// Savings bank account.
  saving,

  /// Current account.
  current,

  /// Overdraft account.
  od,

  /// Credit card.
  cc,

  /// Loan account.
  loan,

  /// Prepaid wallet.
  wallet,
}

/// Roles of `equity_system` accounts that the adjustment wizards route to.
enum SystemRole {
  /// Opening Balance / Capital — counterpart of every opening (02 §4).
  openingBalance,

  /// Adjustments — cash-count differences, write-offs (02 §2 verb 6, §7, §8).
  adjustments,

  /// Suspense — unexplained imported money (02 §10).
  suspense,

  /// Due to/from {Book} — inter-book pairs (02 §6).
  dueToFrom,

  /// Profit Distributed — appropriation of surplus to partners (02 §7.1).
  profitDistributed,

  /// Owner drawings in a single-owner business (02 §7.1 *Just me*).
  drawings,
}

/// An account: encrypted content with a stable UUID (02 §1.2). Names are
/// user-facing labels; the engine keys everything on [id] and [accountClass].
final class Account {
  /// Creates an account.
  Account({
    required this.id,
    required this.bookId,
    required this.name,
    required this.accountClass,
    required this.createdOrder,
    this.subtype,
    this.systemRole,
    this.memberId,
    this.counterpartBookId,
  }) {
    if ((subtype != null) != (accountClass == AccountClass.money)) {
      throw ArgumentError(
        'subtype is required for money accounts and only there ($name)',
      );
    }
    if (systemRole != null && accountClass != AccountClass.equitySystem) {
      throw ArgumentError(
        'systemRole belongs to equity_system accounts only ($name)',
      );
    }
  }

  /// Stable id (UUIDv7 in production; any unique string here).
  final String id;

  /// Owning book (02 §1.4 rule 3).
  final String bookId;

  /// Display name (A/C / khata).
  final String name;

  /// Class.
  final AccountClass accountClass;

  /// Money subtype, required iff [accountClass] is `money`.
  final MoneySubtype? subtype;

  /// Role for `equity_system` accounts.
  final SystemRole? systemRole;

  /// For `advance` and `partner`: the member / owner this account belongs to.
  final String? memberId;

  /// For `dueToFrom`: the other book of the pair.
  final String? counterpartBookId;

  /// Creation order within the book — the tiebreak of the 02 §7.1 rounding rule.
  final int createdOrder;

  /// True for money accounts.
  bool get isMoney => accountClass == AccountClass.money;

  /// True for a collection box (02 §8.2).
  bool get isCollection => subtype == MoneySubtype.cashCollection;

  /// True for the two spendable-cash-or-bank kinds a collection may empty into.
  bool get isCashOrBank => isMoney && !isCollection;

  @override
  String toString() => 'Account($name, ${accountClass.name})';
}

/// A book's chart of accounts.
final class Chart {
  /// Creates a chart; every account must belong to [bookId].
  Chart({required this.bookId, required Iterable<Account> accounts})
    : _byId = {for (final a in accounts) a.id: a} {
    for (final a in _byId.values) {
      if (a.bookId != bookId) {
        throw ArgumentError(
          'account ${a.id} belongs to ${a.bookId}, not $bookId',
        );
      }
    }
  }

  /// The book.
  final String bookId;
  final Map<String, Account> _byId;

  /// Looks an account up; throws if absent.
  Account account(String id) {
    final a = _byId[id];
    if (a == null) {
      throw ArgumentError.value(id, 'id', 'not in chart of $bookId');
    }
    return a;
  }

  /// Looks an account up; `null` if absent.
  Account? maybeAccount(String id) => _byId[id];

  /// True when [id] is in this chart.
  bool contains(String id) => _byId.containsKey(id);

  /// All accounts in creation order.
  List<Account> get accounts =>
      _byId.values.toList()
        ..sort((a, b) => a.createdOrder.compareTo(b.createdOrder));

  /// Accounts of one class, in creation order.
  List<Account> byClass(AccountClass c) =>
      accounts.where((a) => a.accountClass == c).toList();
}
