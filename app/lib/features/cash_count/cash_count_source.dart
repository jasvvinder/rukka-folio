// What S5.5 needs from the ledger, and nothing more.
//
// `app/lib/shared/ledger/` belongs to another lane this round, so the sheet
// talks to this **feature-local interface** instead of to `LocalLedger`. The
// next lane implements [CashCountSource] over `LocalLedger` and installs it
// above the route with [CashCountScope]; nothing in this folder imports the
// facade (07 §5.5 is a screen, not a repository).
//
// The meaning of a count is **not** decided here. `core_ledger`'s
// `countPolicy`, `validateCount` and `resolveCount` (02 §8.2 🔒, pinned by
// A-02-83…92) already say what a count requires and what it posts; this file
// only carries their inputs to the widget and their outcome back. Money is
// `Paise` end to end — integer paise, never a double (CLAUDE.md rule 1).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/widgets.dart';

/// The account being counted, with everything the sheet has to know about it.
///
/// One load, one object: the widget never asks the ledger a second question
/// while the user is counting, so the figures on screen cannot drift apart
/// mid-count.
final class CashCountTarget {
  /// Creates the target.
  const CashCountTarget({
    required this.bookId,
    required this.bookType,
    required this.account,
    required this.bookBalance,
    this.lastCount,
    this.incomeAccounts = const [],
  });

  /// The book this account belongs to.
  final String bookId;

  /// Book type — `organization` makes the denomination sheet mandatory for
  /// every cash account (02 §8.2 🔒). Read by `countPolicy`, not by the widget.
  final BookType bookType;

  /// The account itself: its name, and the subtype that chooses the mode —
  /// `cash` → verify, `cashCollection` → collect (02 §8.2 *Two kinds of
  /// count* 🔒).
  final Account account;

  /// The balance the entries already give for this account (engine sign, 02
  /// §9). Meaningful in verify mode; a collection account's balance is *what
  /// is still in the box* and is never shown as something to check against.
  final Paise bookBalance;

  /// The previous count, if any: its date and breakdown drive the header line
  /// and the ₹2000 rule (02 §8.2 — ₹2000 is offered only if a previous count
  /// used it).
  final LastCashCount? lastCount;

  /// The book's income categories, for collect mode's *Record it as* picker.
  /// Empty is a real state: the picker says so and names the way out.
  final List<Account> incomeAccounts;

  /// True when this account is counted in **collect** mode (02 §8.2).
  bool get isCollection => account.isCollection;
}

/// The previous count of this account.
final class LastCashCount {
  /// Creates the summary.
  const LastCashCount({required this.date, required this.counted, this.sheet});

  /// When it was counted.
  final LocalDate date;

  /// What it came to.
  final Paise counted;

  /// Its breakdown, when one was recorded.
  final DenominationSheet? sheet;

  /// Whether that count held ₹2000 notes — the only reason the ₹2000 row is
  /// offered at all (02 §8.2).
  bool get usedTwoThousand => sheet?.usesTwoThousand ?? false;
}

/// One count as the sheet has it when Save is pressed.
///
/// The id and the HLC are the ledger's to mint, exactly as an [Entry] posted
/// through `LocalLedger.post` is; everything else is what the user counted.
final class CashCountDraft {
  /// Creates the draft.
  const CashCountDraft({
    required this.accountId,
    required this.date,
    required this.counted,
    this.sheet,
    this.countedBy,
    this.witness,
    this.incomeAccountId,
  });

  /// The account counted.
  final String accountId;

  /// The day counted (the injected clock's date — never `DateTime.now()`).
  final LocalDate date;

  /// The counted figure, integer paise.
  final Paise counted;

  /// The denomination breakdown, when the grid was used. Its total always
  /// equals [counted] — `validateCount` rejects a sheet that does not.
  final DenominationSheet? sheet;

  /// *Counted by* — required for a collection account (02 §8.2 🔒).
  final String? countedBy;

  /// The second name — required for a collection account (02 §8.2 🔒).
  final String? witness;

  /// Collect mode only: the income A/C the counted amount is recognised in.
  final String? incomeAccountId;

  /// The draft as the engine's own event, for `validateCount` and
  /// `resolveCount`. `id` and `hlc` are placeholders the implementation
  /// replaces when it actually saves.
  CashCount toEvent({required String bookId}) => CashCount(
    id: '',
    bookId: bookId,
    accountId: accountId,
    date: date,
    counted: counted,
    hlc: const Hlc(0),
    sheet: sheet,
    countedBy: (countedBy ?? '').isEmpty ? null : countedBy,
    witness: (witness ?? '').isEmpty ? null : witness,
  );
}

/// What saving a count came to — the engine's own [CountOutcome], carried back
/// unchanged, plus the entry it led to (null when nothing posted).
final class CashCountResult {
  /// Creates the result.
  const CashCountResult({
    required this.outcome,
    required this.date,
    this.postedEntryId,
    this.incomeAccountName,
  });

  /// `CountVerified` · `CountAdjustment` · `CountRecognition` (02 §8.2 🔒).
  final CountOutcome outcome;

  /// The date recorded on the count — the *verified on {date}* line.
  final LocalDate date;

  /// The adjustment or recognition entry, when one was posted. Null for a
  /// verification: an equal count posts nothing (02 §8.2 🔒).
  final String? postedEntryId;

  /// The income A/C the collection was recognised in, for the outcome line.
  final String? incomeAccountName;
}

/// A count the engine refused (`validateCount` returned violations).
///
/// The sheet keeps Save disabled for every rule it can see, so this is the
/// backstop — it carries the engine's own violations rather than a message
/// the widget invented.
final class CashCountRefused implements Exception {
  /// Creates the refusal.
  const CashCountRefused(this.violations);

  /// What the engine objected to (02 §8.2 🔒).
  final List<Violation> violations;

  @override
  String toString() => 'CashCountRefused($violations)';
}

/// The ledger, as S5.5 needs it.
///
/// Two methods: read the account being counted, and save one count. Saving
/// **records the count either way**; whether an entry posts is the engine's
/// decision (`resolveCount`), never the widget's.
abstract interface class CashCountSource {
  /// Everything about [accountId] the sheet draws from.
  ///
  /// Throws when the account is missing, not a money account, or not of a
  /// countable subtype — the screen shows its error state with a retry.
  Future<CashCountTarget> loadTarget(String accountId);

  /// Records [draft] and returns what it meant for the books.
  ///
  /// Implementations validate with `validateCount` first (a refusal is an
  /// exception, not a silent no-op), write the count, then post whatever
  /// `resolveCount` returns — one guided adjustment, one recognition, or
  /// nothing at all.
  Future<CashCountResult> saveCount(CashCountDraft draft);
}

/// The [CashCountSource] for the tree below — installed by the shell above the
/// router, so `cashCountRoutes` can build the screen from a path alone.
class CashCountScope extends InheritedWidget {
  /// Creates the scope.
  const CashCountScope({super.key, required this.source, required super.child});

  /// The implementation in force.
  final CashCountSource source;

  /// The nearest scope, or null when the shell has not installed one yet —
  /// the screen then shows its error state rather than throwing (07 §1 rule
  /// 6: no dead ends, and no red screen either).
  static CashCountSource? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CashCountScope>()?.source;

  @override
  bool updateShouldNotify(CashCountScope old) => source != old.source;
}
