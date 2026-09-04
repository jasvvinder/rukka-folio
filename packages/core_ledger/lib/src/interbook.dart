import 'accounts.dart';
import 'entry.dart';
import 'hlc.dart';
import 'local_date.dart';
import 'money.dart';
import 'projection.dart';
import 'verbs.dart';

/// A money account and the `Due to/from {other book}` account beside it.
typedef MoneyAndDue = ({Account money, Account dueToFrom});

/// An expense category and the `Due to/from {payer's book}` account beside it.
typedef ExpenseAndDue = ({Account expense, Account dueToFrom});

/// The two envelopes of one inter-book action, one per book (02 §6).
final class TransferPair {
  const TransferPair._(this.from, this.to);

  /// The half in the paying / source book.
  final Entry from;

  /// The half in the receiving / spending book.
  final Entry to;
}

/// One pair of `Due to/from` accounts to reconcile: `balance(A→B) + balance(B→A)` must be 0.
final class InterBookPair {
  /// Creates a pair.
  const InterBookPair({
    required this.a,
    required this.accountA,
    required this.b,
    required this.accountB,
  });

  /// Book A's state.
  final LedgerState a;

  /// Book A's `Due to/from B`.
  final String accountA;

  /// Book B's state.
  final LedgerState b;

  /// Book B's `Due to/from A`.
  final String accountB;
}

/// One row of the Family Reconciliation report (02 §6 🔒).
final class PairReconciliation {
  const PairReconciliation._(
    this.pair,
    this.net,
    this.entryIdsA,
    this.entryIdsB,
  );

  /// The pair.
  final InterBookPair pair;

  /// `balance(A→B) + balance(B→A)`; zero when the books agree.
  final Paise net;

  /// Entries in A composing the balance (listed when the pair is off).
  final List<String> entryIdsA;

  /// Entries in B composing the balance.
  final List<String> entryIdsB;

  /// True when the pair nets to zero.
  bool get isBalanced => net.isZero;
}

/// Inter-book movement (02 §6): books connect only through paired
/// `Due to/from` system accounts; one user action creates two envelopes
/// sharing `refs.transfer_group`, both posting immediately.
abstract final class InterBook {
  /// "Move ₹X from {book A} to {book B}":
  /// `A: Dr Due to/from B · Cr money` · `B: Dr money · Cr Due to/from A`.
  /// The half where the actor lacks posting rights carries the review flag for
  /// that book's approver; the pair shows *in transit* while it is open.
  static TransferPair transfer({
    required Paise amount,
    required LocalDate accountingDate,
    required MoneyAndDue from,
    required MoneyAndDue to,
    required String transferGroup,
    required ({String from, String to}) ids,
    required ({Hlc from, Hlc to}) hlcs,
    required String createdByUser,
    required String createdByDevice,
    required ({bool from, bool to}) reviewRequiredIn,
    required ({Paise? from, Paise? to}) reviewLimitPaise,
    String? note,
  }) {
    _due(from.dueToFrom, 'from.dueToFrom');
    _due(to.dueToFrom, 'to.dueToFrom');
    if (from.money.bookId == to.money.bookId) {
      throw ArgumentError('inter-book transfer needs two different books');
    }
    final fromLines = Verbs.transfer(
      from: from.money,
      to: from.dueToFrom,
      amount: amount,
    );
    final toLines = Verbs.transfer(
      from: to.dueToFrom,
      to: to.money,
      amount: amount,
    );
    return TransferPair._(
      _entry(
        from.money.bookId,
        ids.from,
        hlcs.from,
        EntryKind.transfer,
        accountingDate,
        fromLines,
        transferGroup,
        createdByUser,
        createdByDevice,
        reviewRequiredIn.from,
        reviewLimitPaise.from,
        note,
      ),
      _entry(
        to.money.bookId,
        ids.to,
        hlcs.to,
        EntryKind.transfer,
        accountingDate,
        toLines,
        transferGroup,
        createdByUser,
        createdByDevice,
        reviewRequiredIn.to,
        reviewLimitPaise.to,
        note,
      ),
    );
  }

  /// A member pays another book's expense from their own pocket (02 §6, §7.1):
  /// payer's book `Dr Due to/from {payee} · Cr Cash` — money owed to them, never an
  /// expense; payee's book `Dr Expense · Cr Due to/from {payer}`.
  static TransferPair pocketExpense({
    required Paise amount,
    required LocalDate accountingDate,
    required MoneyAndDue payer,
    required ExpenseAndDue payee,
    required String transferGroup,
    required ({String from, String to}) ids,
    required ({Hlc from, Hlc to}) hlcs,
    required String createdByUser,
    required String createdByDevice,
    required ({bool from, bool to}) reviewRequiredIn,
    required ({Paise? from, Paise? to}) reviewLimitPaise,
    String? note,
  }) {
    _due(payer.dueToFrom, 'payer.dueToFrom');
    _due(payee.dueToFrom, 'payee.dueToFrom');
    if (payer.money.bookId == payee.expense.bookId) {
      throw ArgumentError('pocket expense spans two books');
    }
    if (payee.expense.accountClass != AccountClass.categoryExpense) {
      throw ArgumentError.value(
        payee.expense,
        'payee.expense',
        'must be an expense category',
      );
    }
    final fromLines = Verbs.transfer(
      from: payer.money,
      to: payer.dueToFrom,
      amount: amount,
    );
    final toLines = [
      Line(accountId: payee.expense.id, amount: amount),
      Line(accountId: payee.dueToFrom.id, amount: -amount),
    ];
    return TransferPair._(
      _entry(
        payer.money.bookId,
        ids.from,
        hlcs.from,
        EntryKind.transfer,
        accountingDate,
        fromLines,
        transferGroup,
        createdByUser,
        createdByDevice,
        reviewRequiredIn.from,
        reviewLimitPaise.from,
        note,
      ),
      _entry(
        payee.expense.bookId,
        ids.to,
        hlcs.to,
        EntryKind.moneyOut,
        accountingDate,
        toLines,
        transferGroup,
        createdByUser,
        createdByDevice,
        reviewRequiredIn.to,
        reviewLimitPaise.to,
        note,
      ),
    );
  }

  /// A pair is *in transit* while either half's review flag is open (02 §6).
  static bool isInTransit(ProjectedEntry a, ProjectedEntry b) =>
      a.reviewState == ReviewState.open || b.reviewState == ReviewState.open;

  /// The Family Reconciliation report: every pair with its net and, for any
  /// non-zero pair, the entries composing both sides.
  static List<PairReconciliation> reconcile(List<InterBookPair> pairs) => [
    for (final p in pairs)
      PairReconciliation._(
        p,
        p.a.balances[p.accountA] + p.b.balances[p.accountB],
        [
          for (final e in p.a.counted)
            if (e.entry.lines.any((l) => l.accountId == p.accountA)) e.entry.id,
        ],
        [
          for (final e in p.b.counted)
            if (e.entry.lines.any((l) => l.accountId == p.accountB)) e.entry.id,
        ],
      ),
  ];

  static void _due(Account a, String slot) {
    if (a.accountClass != AccountClass.equitySystem ||
        a.systemRole != SystemRole.dueToFrom) {
      throw ArgumentError.value(
        a,
        slot,
        'must be a Due to/from system account',
      );
    }
  }

  static Entry _entry(
    String bookId,
    String id,
    Hlc hlc,
    EntryKind kind,
    LocalDate date,
    List<Line> lines,
    String group,
    String user,
    String device,
    bool reviewRequired,
    Paise? limit,
    String? note,
  ) => Entry(
    id: id,
    bookId: bookId,
    kind: kind,
    status: EntryStatus.posted,
    reviewRequired: reviewRequired,
    reviewLimitPaise: limit,
    accountingDate: date,
    lines: lines,
    refs: EntryRefs(transferGroup: group),
    note: note,
    createdByUser: user,
    createdByDevice: device,
    hlc: hlc,
  );
}
