import 'accounts.dart';
import 'entry.dart';
import 'money.dart';
import 'ratio.dart';

/// The six verbs and their fixed postings (02 §2), the adjustment wizards
/// (02 §2 verb 6, §4, §7, §8), the advance flow (02 §7) and the partner
/// postings (02 §7.1). Each builder answers the plain questions and returns the
/// lines; the posting rule is fixed here and cannot be gotten wrong — a slot
/// filled with an account of the wrong class throws [ArgumentError].
///
/// The engine's Dr/Cr logic never bends to the display language (02 §10).
abstract final class Verbs {
  /// 1 · Money in / ਪੈਸੇ ਆਏ / पैसे आए — *Into (cash/bank)? From (category or party)?*
  /// `Dr money · Cr income-category` or `Cr party`.
  static List<Line> moneyIn({
    required Account into,
    required Account from,
    required Paise amount,
  }) {
    _positive(amount);
    _spendable(into, 'into');
    _oneOf(from, 'from', const {
      AccountClass.categoryIncome,
      AccountClass.party,
      AccountClass.equitySystem,
    });
    return [
      Line(accountId: into.id, amount: amount),
      Line(accountId: from.id, amount: -amount),
    ];
  }

  /// 2 · Money out / ਪੈਸੇ ਗਏ / पैसे गए — *From (cash/bank)? For (category or party)?*
  /// `Dr expense-category` or `Dr party` · `Cr money`.
  static List<Line> moneyOut({
    required Account from,
    required Account forWhat,
    required Paise amount,
  }) {
    _positive(amount);
    _spendable(from, 'from');
    _oneOf(forWhat, 'forWhat', const {
      AccountClass.categoryExpense,
      AccountClass.party,
      AccountClass.equitySystem,
    });
    return [
      Line(accountId: forWhat.id, amount: amount),
      Line(accountId: from.id, amount: -amount),
    ];
  }

  /// 3 · Gave on credit / ਉਧਾਰ ਦਿੱਤਾ / उधार दिया — *To whom? Gave what — money, or work/goods?*
  /// `Dr party · Cr money` or `Cr income-category`.
  static List<Line> gaveCredit({
    required Account toWhom,
    required Account gave,
    required Paise amount,
  }) {
    _positive(amount);
    _oneOf(toWhom, 'toWhom', const {AccountClass.party});
    if (gave.isMoney) {
      _spendable(gave, 'gave');
    } else {
      _oneOf(gave, 'gave', const {AccountClass.categoryIncome});
    }
    return [
      Line(accountId: toWhom.id, amount: amount),
      Line(accountId: gave.id, amount: -amount),
    ];
  }

  /// 4 · Took on credit / ਉਧਾਰ ਲਿਆ / उधार लिया — *From whom? Took what — money, or goods/expense?*
  /// `Dr money` or `Dr expense-category` · `Cr party`.
  static List<Line> tookCredit({
    required Account fromWhom,
    required Account took,
    required Paise amount,
  }) {
    _positive(amount);
    _oneOf(fromWhom, 'fromWhom', const {AccountClass.party});
    if (took.isMoney) {
      _spendable(took, 'took');
    } else {
      _oneOf(took, 'took', const {AccountClass.categoryExpense});
    }
    return [
      Line(accountId: took.id, amount: amount),
      Line(accountId: fromWhom.id, amount: -amount),
    ];
  }

  /// 5 · Transfer — `Dr to · Cr from`. Within a book: two different money
  /// accounts (cash↔bank, bank↔bank, card/loan payments). One side may be the
  /// `Due to/from {Book}` half of an inter-book move (02 §6). A collection box
  /// (gollak) empties only into the book's Cash A/c or a bank account, and
  /// nothing is paid *into* a box through the books (02 §8.2).
  static List<Line> transfer({
    required Account from,
    required Account to,
    required Paise amount,
  }) {
    _positive(amount);
    if (from.id == to.id) {
      throw ArgumentError('transfer needs two different accounts');
    }
    final fromDue = _isDueToFrom(from);
    final toDue = _isDueToFrom(to);
    if (fromDue && toDue) {
      throw ArgumentError('a transfer cannot join two Due to/from accounts');
    }
    if (!fromDue && !from.isMoney) {
      throw ArgumentError.value(
        from,
        'from',
        'must be a money account or Due to/from',
      );
    }
    if (!toDue && !to.isMoney) {
      throw ArgumentError.value(
        to,
        'to',
        'must be a money account or Due to/from',
      );
    }
    if (to.isCollection) {
      throw ArgumentError.value(
        to,
        'to',
        'nothing is paid into a collection box through the books (02 §8.2)',
      );
    }
    if (from.isCollection && !_isCashOrBank(to)) {
      throw ArgumentError.value(
        to,
        'to',
        'a collection box empties only into the Cash A/c or a bank account (02 §8.2)',
      );
    }
    return [
      Line(accountId: to.id, amount: amount),
      Line(accountId: from.id, amount: -amount),
    ];
  }

  /// 6a · Opening balance wizard (02 §4): one adjustment per account against
  /// Opening Balance. [balance] is signed the way the ledger sees it: money
  /// *balance today* (negative = overdraft); party *you will get* (+) / *you
  /// will give* (−). Opening Balance absorbs the difference — that is correct.
  static List<Line> openingBalance({
    required Account account,
    required Paise balance,
    required Account openingAccount,
  }) {
    _nonZero(balance);
    _oneOf(account, 'account', const {
      AccountClass.money,
      AccountClass.party,
      AccountClass.advance,
      AccountClass.partner,
    });
    _role(openingAccount, 'openingAccount', SystemRole.openingBalance);
    return [
      Line(accountId: account.id, amount: balance),
      Line(accountId: openingAccount.id, amount: -balance),
    ];
  }

  /// 6b · Cash-count difference (02 §8 step 1, §8.2): `Dr/Cr Cash · Cr/Dr Adjustments`.
  /// [difference] = counted − book balance.
  static List<Line> cashCountDifference({
    required Account cash,
    required Paise difference,
    required Account adjustmentsAccount,
  }) {
    _nonZero(difference);
    if (cash.subtype != MoneySubtype.cash) {
      throw ArgumentError.value(
        cash,
        'cash',
        'must be a cash account (a collection count recognises income instead)',
      );
    }
    _role(adjustmentsAccount, 'adjustmentsAccount', SystemRole.adjustments);
    return [
      Line(accountId: cash.id, amount: difference),
      Line(accountId: adjustmentsAccount.id, amount: -difference),
    ];
  }

  /// 6c · Write-off of a party or advance balance (02 §2 verb 6, §7): the
  /// account is brought to zero against Adjustments. [balance] is its current
  /// signed balance.
  static List<Line> writeOff({
    required Account account,
    required Paise balance,
    required Account adjustmentsAccount,
  }) {
    _nonZero(balance);
    _oneOf(account, 'account', const {
      AccountClass.party,
      AccountClass.advance,
    });
    _role(adjustmentsAccount, 'adjustmentsAccount', SystemRole.adjustments);
    return [
      Line(accountId: adjustmentsAccount.id, amount: balance),
      Line(accountId: account.id, amount: -balance),
    ];
  }

  // ── advances (02 §7) ──────────────────────────────────────────────────────
  // ⚠️ SPEC: 02 fixes six kinds and does not name which one an advance movement
  // is stored as. Balances never depend on kind. The builders return lines only;
  // the app stores a request as `money_out` + status `pending`, spending as
  // `money_out`, a return as `money_in` — noted to the owner in CHANGELOG.

  /// Advance request: on approval `Dr Advance – {member} · Cr money` (02 §7).
  /// Stored with status `pending`; the approval itself moves the money.
  static List<Line> advanceRequest({
    required Account advance,
    required Account from,
    required Paise amount,
  }) {
    _positive(amount);
    _oneOf(advance, 'advance', const {AccountClass.advance});
    _spendable(from, 'from');
    return [
      Line(accountId: advance.id, amount: amount),
      Line(accountId: from.id, amount: -amount),
    ];
  }

  /// Spending against an advance: `Dr expense-category · Cr Advance – {member}`.
  static List<Line> advanceSpend({
    required Account advance,
    required Account forWhat,
    required Paise amount,
  }) {
    _positive(amount);
    _oneOf(advance, 'advance', const {AccountClass.advance});
    _oneOf(forWhat, 'forWhat', const {AccountClass.categoryExpense});
    return [
      Line(accountId: forWhat.id, amount: amount),
      Line(accountId: advance.id, amount: -amount),
    ];
  }

  /// Returning the remainder: `Dr money · Cr Advance – {member}`.
  static List<Line> advanceReturn({
    required Account advance,
    required Account into,
    required Paise amount,
  }) {
    _positive(amount);
    _oneOf(advance, 'advance', const {AccountClass.advance});
    _spendable(into, 'into');
    return [
      Line(accountId: into.id, amount: amount),
      Line(accountId: advance.id, amount: -amount),
    ];
  }

  // ── partners (02 §7.1) ────────────────────────────────────────────────────

  /// An owner pays a business cost from their own pocket: `Dr Expense · Cr Partner Current`
  /// — the business now owes them. (In their personal book it is `Dr {Business} · Cr Cash`, never an expense.)
  static List<Line> partnerPaidCost({
    required Account partner,
    required Account expense,
    required Paise amount,
  }) {
    _positive(amount);
    _oneOf(partner, 'partner', const {AccountClass.partner});
    _oneOf(expense, 'expense', const {AccountClass.categoryExpense});
    return [
      Line(accountId: expense.id, amount: amount),
      Line(accountId: partner.id, amount: -amount),
    ];
  }

  /// An owner takes money out: `Dr Partner Current · Cr business money a/c`.
  static List<Line> partnerDrawing({
    required Account partner,
    required Account from,
    required Paise amount,
  }) {
    _positive(amount);
    _oneOf(partner, 'partner', const {AccountClass.partner});
    _spendable(from, 'from');
    return [
      Line(accountId: partner.id, amount: amount),
      Line(accountId: from.id, amount: -amount),
    ];
  }

  /// Profit distribution — **one multi-line entry**: `Dr Profit Distributed · Cr each
  /// Partner Current` (02 §7.1). Interest on capital, when enabled, is credited
  /// first (tagged `interest`, negative = charged on a debit balance), then the
  /// **remaining** profit splits by the agreed ratio under the rounding rule
  /// (tagged `share`). Moves no cash. [partners] must be in creation order.
  static List<Line> profitDistribution({
    required Account profitDistributed,
    required List<PartnerShare> partners,
    required Paise netProfit,
    Map<String, Paise> interest = const {},
  }) {
    _positive(netProfit);
    _role(profitDistributed, 'profitDistributed', SystemRole.profitDistributed);
    if (partners.isEmpty) throw ArgumentError('at least one partner');
    for (final p in partners) {
      _oneOf(p.account, 'partners', const {AccountClass.partner});
    }
    final interestLines = <Line>[];
    var interestTotal = Paise.zero;
    for (final p in partners) {
      final i = interest[p.account.id] ?? Paise.zero;
      if (i.isZero) continue;
      interestTotal += i;
      interestLines.add(
        Line(accountId: p.account.id, amount: -i, tag: 'interest'),
      );
    }
    final remaining = netProfit - interestTotal;
    if (remaining.isCredit) {
      throw ArgumentError(
        'interest ${interestTotal.raw} exceeds net profit ${netProfit.raw}',
      );
    }
    final shares = remaining.isZero
        ? List.filled(partners.length, Paise.zero)
        : splitByRatio(remaining, [for (final p in partners) p.ratio]);
    return [
      Line(accountId: profitDistributed.id, amount: netProfit),
      ...interestLines,
      for (var k = 0; k < partners.length; k++)
        if (!shares[k].isZero)
          Line(
            accountId: partners[k].account.id,
            amount: -shares[k],
            tag: 'share',
          ),
    ];
  }

  // ── checks ────────────────────────────────────────────────────────────────

  static void _positive(Paise amount) {
    if (!amount.isDebit) {
      throw ArgumentError.value(
        amount.raw,
        'amount',
        'must be a positive number of paise',
      );
    }
  }

  static void _nonZero(Paise amount) {
    if (amount.isZero) {
      throw ArgumentError.value(0, 'amount', 'must not be zero');
    }
  }

  static void _oneOf(Account a, String slot, Set<AccountClass> allowed) {
    if (!allowed.contains(a.accountClass)) {
      throw ArgumentError.value(
        a,
        slot,
        'must be one of ${allowed.map((c) => c.name).join('/')}',
      );
    }
  }

  static void _role(Account a, String slot, SystemRole role) {
    if (a.accountClass != AccountClass.equitySystem || a.systemRole != role) {
      throw ArgumentError.value(
        a,
        slot,
        'must be the ${role.name} system account',
      );
    }
  }

  /// A money account that can be paid from or into — any money account except a collection box.
  static void _spendable(Account a, String slot) {
    if (!a.isMoney) {
      throw ArgumentError.value(a, slot, 'must be a money account');
    }
    if (a.isCollection) {
      throw ArgumentError.value(
        a,
        slot,
        'a collection box is not a spending source and is never paid into through the books (02 §8.2)',
      );
    }
  }

  static bool _isDueToFrom(Account a) =>
      a.accountClass == AccountClass.equitySystem &&
      a.systemRole == SystemRole.dueToFrom;

  static bool _isCashOrBank(Account a) =>
      a.isMoney &&
      const {
        MoneySubtype.cash,
        MoneySubtype.saving,
        MoneySubtype.current,
        MoneySubtype.od,
      }.contains(a.subtype);
}

/// An owner and their agreed sharing ratio (fixed at business creation, 02 §7.1).
final class PartnerShare {
  /// Creates a share.
  PartnerShare({required this.account, required this.ratio}) {
    if (account.accountClass != AccountClass.partner) {
      throw ArgumentError.value(
        account,
        'account',
        'must be a partner account',
      );
    }
    if (ratio <= 0) {
      throw ArgumentError.value(ratio, 'ratio', 'must be positive');
    }
  }

  /// The Partner Current A/c.
  final Account account;

  /// Ratio weight (any positive integers; 1/1/1 is equal thirds).
  final int ratio;
}
