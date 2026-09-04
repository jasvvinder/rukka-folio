import 'accounts.dart';
import 'entry.dart';
import 'local_date.dart';
import 'money.dart';

/// Why an envelope is quarantined (02 preamble: never silently displayed or summed)
/// or why an authoring attempt is refused.
enum ViolationKind {
  /// 02 §1.4 rule 1: lines do not sum to zero.
  linesUnbalanced,

  /// 02 §1.4 rule 1: fewer than two lines.
  tooFewLines,

  /// 02 §1.4 rule 1: a zero line.
  zeroLine,

  /// 02 §1.4 rule 3: an account of another book.
  accountNotInBook,

  /// An account id the chart does not know.
  unknownAccount,

  /// 02 §1.4 rule 5: not INR.
  currencyUnsupported,

  /// 02 §1.4 rule 6 (authoring only): accounting_date after today.
  futureDate,

  /// 02 §8: accounting_date in a period locked before this HLC.
  periodLocked,

  /// 03 §3.3.5: over the carried limit but not flagged (hostile client).
  reviewFlagMissing,

  /// 02 §1.3: `pending` on something other than an advance request.
  pendingNotAdvance,

  /// 02 §5: amends an entry this reader has not accepted.
  amendTargetMissing,

  /// 02 §5: amend chains are linear — only the head may be amended.
  amendNotHead,

  /// 02 §5: an amendment must keep the kind.
  amendKindChanged,

  /// 02 §5: amendment in a locked period is forbidden by rule.
  amendInLockedPeriod,

  /// 02 §5: reverses an entry this reader has not accepted.
  reverseTargetMissing,

  /// 02 §5: only a counted (posted) head may be reversed.
  reverseTargetNotPosted,

  /// 02 §5: the reversal is not the exact mirror of its target.
  reversalNotMirror,

  /// 02 §5: the target is already reversed (void).
  alreadyReversed,

  /// 02 §7.2 item 1: nobody clears their own flag.
  selfApproval,

  /// A decision on an entry this reader has not accepted.
  decisionTargetMissing,

  /// 02 §8.2: the denomination sheet is mandatory here.
  countSheetRequired,

  /// 02 §8.2: a collection count needs *counted by* and *witness*.
  countNamesRequired,

  /// 02 §8.2: the sheet does not add up to the counted figure.
  countSheetMismatch,
}

/// One violation with a plain explanation (for the security event, never for the user).
final class Violation {
  /// Creates a violation.
  const Violation(this.kind, this.message);

  /// Kind.
  final ViolationKind kind;

  /// Detail.
  final String message;

  @override
  String toString() => '${kind.name}: $message';
}

/// The universal invariants of 02 §1.4 (plus the reader-side re-checks of
/// 02 §1.3 and 03 §3.3.5) that every reading client applies to every entry.
/// Pure: no clock, no settings. Period locks are checked by the projector,
/// which holds the lock timeline.
List<Violation> checkUniversalInvariants(Entry entry, Chart chart) {
  final out = <Violation>[];
  if (entry.lines.length < 2) {
    out.add(
      Violation(ViolationKind.tooFewLines, '${entry.lines.length} line(s)'),
    );
  }
  final sum = Paise.sum(entry.lines.map((l) => l.amount));
  if (!sum.isZero) {
    out.add(
      Violation(ViolationKind.linesUnbalanced, 'lines sum to ${sum.raw}'),
    );
  }
  for (final l in entry.lines) {
    if (l.amount.isZero) {
      out.add(Violation(ViolationKind.zeroLine, 'zero line on ${l.accountId}'));
    }
    final a = chart.maybeAccount(l.accountId);
    if (a == null) {
      out.add(Violation(ViolationKind.unknownAccount, l.accountId));
    } else if (a.bookId != entry.bookId || chart.bookId != entry.bookId) {
      out.add(
        Violation(
          ViolationKind.accountNotInBook,
          '${l.accountId} is in ${a.bookId}, entry is in ${entry.bookId}',
        ),
      );
    }
  }
  if (entry.currency != 'INR') {
    out.add(Violation(ViolationKind.currencyUnsupported, entry.currency));
  }
  final limit = entry.reviewLimitPaise;
  if (!entry.reviewRequired && limit != null && entry.totalDebits > limit) {
    out.add(
      Violation(
        ViolationKind.reviewFlagMissing,
        '${entry.totalDebits.raw} over limit ${limit.raw} without review_required',
      ),
    );
  }
  if (entry.status == EntryStatus.pending &&
      !isAdvanceRequestShape(entry, chart)) {
    out.add(
      const Violation(
        ViolationKind.pendingNotAdvance,
        'pending is only an advance request awaiting approval',
      ),
    );
  }
  return out;
}

/// True when [entry] has the shape of an advance request (02 §7): exactly one
/// debit line, to an `advance` account, and every credit line on a money account.
bool isAdvanceRequestShape(Entry entry, Chart chart) {
  final debits = entry.lines.where((l) => l.amount.isDebit).toList();
  if (debits.length != 1) return false;
  final adv = chart.maybeAccount(debits.single.accountId);
  if (adv == null || adv.accountClass != AccountClass.advance) return false;
  return entry.lines
      .where((l) => l.amount.isCredit)
      .every((l) => chart.maybeAccount(l.accountId)?.isMoney ?? false);
}

/// Rules only the authoring client can check, because they need today's date
/// (02 §1.4 rule 6). The projector never calls this — it may not read a clock.
List<Violation> checkAuthoringRules(Entry entry, {required LocalDate today}) {
  final out = <Violation>[];
  if (entry.accountingDate.isAfter(today)) {
    out.add(
      Violation(
        ViolationKind.futureDate,
        '${entry.accountingDate} is after $today (recurring entries own the future)',
      ),
    );
  }
  return out;
}
