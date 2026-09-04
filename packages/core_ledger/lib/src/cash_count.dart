import 'accounts.dart';
import 'entry.dart';
import 'events.dart';
import 'hlc.dart';
import 'invariants.dart';
import 'local_date.dart';
import 'money.dart';
import 'verbs.dart';

/// Note denominations (02 §8.2): ₹500 · ₹200 · ₹100 · ₹50 · ₹20 · ₹10, coins as a
/// value. ₹2000 is legal but rarely held; it is shown only if a previous count
/// used it ([usesTwoThousand]).
final class DenominationSheet {
  /// Creates a sheet: note value → count, plus coins as paise.
  const DenominationSheet({
    this.notes = const {},
    this.coinsPaise = Paise.zero,
  });

  /// Legal note values.
  static const allowedNotes = {2000, 500, 200, 100, 50, 20, 10};

  /// Note value (rupees) → number of notes.
  final Map<int, int> notes;

  /// Coins, entered as a value.
  final Paise coinsPaise;

  /// The sheet's total.
  Paise get total {
    var t = coinsPaise;
    for (final MapEntry(key: value, value: count) in notes.entries) {
      if (!allowedNotes.contains(value)) {
        throw ArgumentError.value(value, 'notes', 'not an INR note');
      }
      if (count < 0) {
        throw ArgumentError.value(count, 'notes', 'negative count');
      }
      t += Paise.rupees(value) * count;
    }
    return t;
  }

  /// True when the sheet has ₹2000 notes.
  bool get usesTwoThousand => (notes[2000] ?? 0) > 0;
}

/// A dated record of how much cash was physically there (02 §8.2). A count is a
/// memo envelope: **it never moves money**; any posting it leads to is a separate
/// entry built by [resolveCount].
final class CashCount implements LedgerEvent {
  /// Creates a count.
  const CashCount({
    required this.id,
    required this.bookId,
    required this.accountId,
    required this.date,
    required this.counted,
    required this.hlc,
    this.sheet,
    this.countedBy,
    this.witness,
  });

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;

  /// The cash or collection account.
  final String accountId;

  /// When.
  final LocalDate date;

  /// The counted figure.
  final Paise counted;

  /// Optional denomination sheet.
  final DenominationSheet? sheet;

  /// Who counted (required for collection accounts).
  final String? countedBy;

  /// Second name (required for collection accounts).
  final String? witness;

  /// Throws unless [account] is a money account of subtype cash or collection.
  void validateAgainst(Account account) {
    if (account.id != accountId) {
      throw ArgumentError('count is for $accountId, not ${account.id}');
    }
    if (account.subtype != MoneySubtype.cash &&
        account.subtype != MoneySubtype.cashCollection) {
      throw ArgumentError.value(
        account,
        'account',
        'only cash and collection accounts are counted',
      );
    }
  }
}

/// What a count must carry here (02 §8.2 🔒).
final class CountPolicy {
  const CountPolicy._({
    required this.denominationSheetMandatory,
    required this.twoNamesRequired,
  });

  /// Organization (trust) books: always, for every cash account.
  final bool denominationSheetMandatory;

  /// Collection accounts: *counted by* and *witness*.
  final bool twoNamesRequired;
}

/// The policy for counting [account] in a book of [bookType].
CountPolicy countPolicy({
  required BookType bookType,
  required Account account,
}) => CountPolicy._(
  denominationSheetMandatory: bookType == BookType.organization,
  twoNamesRequired: account.isCollection,
);

/// Checks a count against the policy and its own arithmetic.
List<Violation> validateCount(
  CashCount count, {
  required BookType bookType,
  required Account account,
}) {
  count.validateAgainst(account);
  final policy = countPolicy(bookType: bookType, account: account);
  final out = <Violation>[];
  if (policy.denominationSheetMandatory && count.sheet == null) {
    out.add(
      const Violation(
        ViolationKind.countSheetRequired,
        'organization books require the denomination sheet for every cash account',
      ),
    );
  }
  if (policy.twoNamesRequired &&
      ((count.countedBy ?? '').isEmpty || (count.witness ?? '').isEmpty)) {
    out.add(
      const Violation(
        ViolationKind.countNamesRequired,
        'a collection count needs counted-by and witness',
      ),
    );
  }
  final sheet = count.sheet;
  if (sheet != null && sheet.total != count.counted) {
    out.add(
      Violation(
        ViolationKind.countSheetMismatch,
        'sheet ${sheet.total.raw} ≠ counted ${count.counted.raw}',
      ),
    );
  }
  return out;
}

/// What a count means for the books (02 §8.2 *Two kinds of count*).
sealed class CountOutcome {
  const CountOutcome();

  /// Lines of the entry to post; empty when nothing posts.
  List<Line> get lines;
}

/// `cash`, counted figure equals the book: no entry; account marked *verified on {date}*.
final class CountVerified extends CountOutcome {
  const CountVerified._();

  @override
  List<Line> get lines => const [];
}

/// `cash`, counted figure differs: one guided adjustment with the difference shown plainly.
final class CountAdjustment extends CountOutcome {
  const CountAdjustment._(this.difference, this.lines);

  /// counted − book.
  final Paise difference;

  @override
  final List<Line> lines;
}

/// `cash_collection`: the count *is* the record — recognition of income for the full amount.
final class CountRecognition extends CountOutcome {
  const CountRecognition._(this.lines);

  @override
  final List<Line> lines;
}

/// Resolves a count: a galla's balance is known from entries, so counting
/// checks it; a gollak's contents are unknown until opened, so counting creates
/// the record. Counted collection cash stays on the collection account until an
/// ordinary Transfer deposits it (02 §8.2).
CountOutcome resolveCount(
  CashCount count, {
  required Account account,
  required Paise bookBalance,
  required Account adjustmentsAccount,
  Account? incomeAccount,
}) {
  count.validateAgainst(account);
  if (account.isCollection) {
    if (incomeAccount == null) {
      throw ArgumentError(
        'a collection count recognises income: incomeAccount is required',
      );
    }
    if (incomeAccount.accountClass != AccountClass.categoryIncome) {
      throw ArgumentError.value(
        incomeAccount,
        'incomeAccount',
        'must be an income category',
      );
    }
    if (!count.counted.isDebit) {
      throw ArgumentError.value(
        count.counted.raw,
        'counted',
        'must be positive',
      );
    }
    return CountRecognition._([
      Line(accountId: account.id, amount: count.counted),
      Line(accountId: incomeAccount.id, amount: -count.counted),
    ]);
  }
  if (incomeAccount != null) {
    throw ArgumentError(
      'a cash count is a verification; it never recognises income',
    );
  }
  final difference = count.counted - bookBalance;
  if (difference.isZero) return const CountVerified._();
  return CountAdjustment._(
    difference,
    Verbs.cashCountDifference(
      cash: account,
      difference: difference,
      adjustmentsAccount: adjustmentsAccount,
    ),
  );
}
