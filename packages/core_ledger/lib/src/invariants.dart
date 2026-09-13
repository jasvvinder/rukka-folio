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

  /// ADR 2026-09-09d §4 (authoring only, never a reader invariant):
  /// accounting_date before the book's start date. The opening balance is a
  /// counted figure, so anything earlier is already inside it.
  beforeBookStart,

  /// 02 §8: accounting_date in a period locked before this HLC.
  periodLocked,

  /// 03 §3.3.5: over the carried limit but not flagged (hostile client).
  reviewFlagMissing,

  /// 02 §1.3: `pending` on something other than an advance request.
  pendingNotAdvance,

  /// 02 §5: amend chains are linear — only the head may be amended.
  amendNotHead,

  /// 02 §5: an amendment must keep the kind.
  amendKindChanged,

  /// 02 §5: amendment in a locked period is forbidden by rule.
  amendInLockedPeriod,

  /// 02 §5: only a counted (posted) head may be reversed.
  reverseTargetNotPosted,

  /// 02 §5: the reversal is not the exact mirror of its target.
  reversalNotMirror,

  /// 02 §5: the target is already reversed (void).
  alreadyReversed,

  /// 02 §7.2 item 1: nobody clears their own flag.
  selfApproval,

  /// 02 §8.2: the denomination sheet is mandatory here.
  countSheetRequired,

  /// 02 §8.2: a collection count needs *counted by* and *witness*.
  countNamesRequired,

  /// 02 §8.2: the sheet does not add up to the counted figure.
  countSheetMismatch,

  /// 02 §1.4 rule 7 / ADR 2026-09-05e §6: the lines do not match the class
  /// shape of the entry's `kind` (a mislabelled kind that still sums to zero).
  shapeViolation,

  /// ADR 2026-09-05b §3: two envelopes from one device carry the same
  /// `author_seq` — a replay or a forgery; the later one is refused.
  authorSeqDuplicate,

  /// ADR 2026-09-05b §4: the target of an amendment, reversal or decision is
  /// provably absent — every author's sequence is contiguous and it never came.
  targetMissing,
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
  if (out.isEmpty) {
    // Shape is checked only on an otherwise well-formed entry: the class of every
    // line must be known before the kind's shape can be judged.
    final shape = checkShape(entry, chart);
    if (shape != null) out.add(shape);
  }
  return out;
}

/// The class-shape invariant of each `kind` (02 §1.4 rule 7, §2; ADR
/// 2026-09-05e §6) — reader-enforced, so a mislabelled kind that still sums to
/// zero cannot corrupt day-books, P&L or ageing. Returns the violation, or
/// `null` when the lines fit.
///
/// The ADR's table names the six verbs over the classes 02 §2 mentions. The
/// two classes 02 introduces later — `advance` (§7) and `partner` (§7.1) — and
/// the `Due to/from` half of a §6 pair are fitted in as follows. ⚠️ SPEC (the
/// narrowest reading that admits every posting 02 itself prescribes):
/// - `partner` is party-like (a Partner Current A/c is the business's account
///   *with* an owner: `Dr Expense · Cr Partner`, `Dr Partner · Cr money`);
/// - `advance` movements keep the M1 kinds — request `money_out` (Dr advance ·
///   Cr money), spend `money_out` (Dr expense · Cr advance), return `money_in`
///   (Dr money · Cr advance) — so `advance` is admitted where a party would be
///   on the debit side and beside money on the credit side;
/// - a §6 pair's `Due to/from` account stands in for money on the far side
///   (`transfer` and the payee half of a pocket expense, `Dr Expense · Cr Due to/from`);
/// - a reversal (`refs.reverses` set) is exempt: the projector proves it is the
///   exact mirror of its target, whose shape was already checked.
///
/// Two `equity_system` roles are admitted by name, one on each of the two
/// money verbs, and both are rulings rather than readings: `drawings` on the
/// debit side of `money_out` (ADR 2026-09-09b §3 🔒) and `openingBalance` —
/// which *is* Capital (ADR 2026-09-09b §1 🔒) — on the credit side of
/// `money_in` (ADR 2026-09-13 §4 🔒). Every other system account posts through
/// its own verb, and neither role is admitted on the other's side.
Violation? checkShape(Entry entry, Chart chart) {
  if (entry.refs.reverses != null) return null;
  final debits = <Account>[];
  final credits = <Account>[];
  for (final l in entry.lines) {
    final a = chart.maybeAccount(l.accountId);
    if (a == null) return null; // reported by the unknown-account check
    (l.amount.isDebit ? debits : credits).add(a);
  }
  bool isDue(Account a) =>
      a.accountClass == AccountClass.equitySystem &&
      a.systemRole == SystemRole.dueToFrom;
  // Owner takeout in a *Just me* business is an ordinary Money out whose
  // counterpart is Drawings (02 §7.1, ADR 2026-09-09b §3, 07 §5 "Owner's
  // drawings" 🔒): `Dr Drawings · Cr money`. Only that one equity_system role
  // is admitted here — Opening Balance, Adjustments, Suspense, Profit
  // Distributed, Corpus and Due to/from keep to their own verbs.
  bool isDrawings(Account a) =>
      a.accountClass == AccountClass.equitySystem &&
      a.systemRole == SystemRole.drawings;
  // Capital introduced is an ordinary Money in whose counterpart is the
  // book's Opening Balance / Capital A/c (02 §7.1, ADR 2026-09-13 §4;
  // `financial-accounting-standards.md` §4.1 B01 "Owner adds capital",
  // `Dr HDFC · Cr Capital`). The exact mirror of [isDrawings]: one
  // equity_system role admitted on one side of one verb, and Capital is the
  // Opening Balance account itself (ADR 2026-09-09b §1 🔒 — no separate
  // `capital` role exists, as both worked examples name it
  // `Opening Balance / Capital A/c`).
  bool isCapital(Account a) =>
      a.accountClass == AccountClass.equitySystem &&
      a.systemRole == SystemRole.openingBalance;
  bool all(List<Account> xs, bool Function(Account) ok) => xs.every(ok);
  const partyLike = {AccountClass.party, AccountClass.partner};
  bool party(Account a) => partyLike.contains(a.accountClass);
  bool money(Account a) => a.isMoney;
  bool income(Account a) => a.accountClass == AccountClass.categoryIncome;
  bool expense(Account a) => a.accountClass == AccountClass.categoryExpense;
  bool advance(Account a) => a.accountClass == AccountClass.advance;

  final ok = switch (entry.kind) {
    EntryKind.moneyIn =>
      all(debits, money) &&
          all(
            credits,
            (a) => income(a) || party(a) || advance(a) || isCapital(a),
          ),
    EntryKind.moneyOut =>
      all(
            debits,
            (a) => expense(a) || party(a) || advance(a) || isDrawings(a),
          ) &&
          all(credits, (a) => money(a) || advance(a) || isDue(a)),
    EntryKind.gaveCredit =>
      all(debits, party) && all(credits, (a) => money(a) || income(a)),
    EntryKind.tookCredit =>
      all(debits, (a) => money(a) || expense(a)) && all(credits, party),
    EntryKind.transfer =>
      all(debits, (a) => money(a) || isDue(a)) &&
          all(credits, (a) => money(a) || isDue(a)) &&
          !(debits.any(isDue) && credits.any(isDue)),
    EntryKind.adjustment =>
      {
            for (final l in entry.lines)
              if (chart.account(l.accountId).accountClass ==
                  AccountClass.equitySystem)
                l.accountId,
          }.length ==
          1,
  };
  if (ok) return null;
  return Violation(
    ViolationKind.shapeViolation,
    '${entry.kind.wire}: Dr ${debits.map((a) => a.accountClass.name).join('/')}'
    ' · Cr ${credits.map((a) => a.accountClass.name).join('/')}',
  );
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
