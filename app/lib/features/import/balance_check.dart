// S7.2 — the import balance check (07 §11 item 1 🔒 *Balance check*, ADR
// 2026-09-01 §2: S7.2 **is** the balance check — passing · matched · failing;
// 13 §3.2 row S7.2).
//
// The statement's own opening and closing balances are compared with the
// ledger for those dates. Three outcomes, each stated **in words with the
// numbers** — never a bare tick, never a colour alone (07 §1 rule 3):
//
//   matched  — the book already agrees on both ends; these lines are already
//              recorded, or there are none left to record.
//   passing  — *Opening matches your book ✓ · Closing will match once these
//              23 lines are recorded.* The ordinary happy case.
//   failing  — the opening does **not** match, which means an earlier
//              statement is missing, and the screen says so with the gap.
//
// Pure: no clock, no locale, no I/O. Integer paise throughout — a float here
// would be a bug (CLAUDE.md rule 1).
import 'package:core_ledger/core_ledger.dart';

import 'parse/parsed_statement.dart';

/// Which of the three the check came out as.
enum ImportBalanceOutcome {
  /// Opening and closing both already agree with the book.
  matched,

  /// Opening agrees; closing will agree once the remaining lines are
  /// recorded.
  passing,

  /// The opening does not agree — an earlier statement is missing.
  failing,

  /// The file has no balance column, so there is nothing to check against.
  /// Stated plainly rather than shown as a pass (07 §1 rule 12).
  unavailable,
}

/// The balance check, computed.
final class ImportBalanceCheck {
  /// Creates the value.
  const ImportBalanceCheck({
    required this.outcome,
    required this.lineCount,
    this.statementOpeningPaise,
    this.statementClosingPaise,
    this.ledgerOpeningPaise,
    this.ledgerClosingPaise,
    this.movementPaise = 0,
    this.firstDate,
    this.lastDate,
  });

  /// Which of the three.
  final ImportBalanceOutcome outcome;

  /// How many lines are waiting to be recorded — the *23* of the spec line.
  final int lineCount;

  /// The balance the statement opens on: the balance before its first line.
  final int? statementOpeningPaise;

  /// The balance the statement closes at: after its last line.
  final int? statementClosingPaise;

  /// The book's balance for this A/C the day before the statement starts.
  final int? ledgerOpeningPaise;

  /// The book's balance for this A/C on the statement's last day.
  final int? ledgerClosingPaise;

  /// The signed sum of the lines waiting to be recorded, engine sign
  /// (+ = money into a bank A/C = Dr).
  final int movementPaise;

  /// The statement's first and last transaction dates.
  final LocalDate? firstDate;

  /// Its last.
  final LocalDate? lastDate;

  /// How far the book is from the statement at the opening — what an earlier
  /// missing statement is worth. Positive means the statement has *more*
  /// money than the book knows about.
  int? get openingGapPaise =>
      statementOpeningPaise == null || ledgerOpeningPaise == null
      ? null
      : statementOpeningPaise! - ledgerOpeningPaise!;

  /// The closing the book will reach once these lines post.
  int? get projectedClosingPaise =>
      ledgerClosingPaise == null ? null : ledgerClosingPaise! + movementPaise;

  /// Whether the opening agrees.
  bool get openingMatches => openingGapPaise == 0;

  /// Runs the check.
  ///
  /// [ledgerOpeningPaise] is the book's balance for the A/C on the day
  /// **before** [ParsedStatement]'s first line; [ledgerClosingPaise] is its
  /// balance on the last line's day — both read from the seam, both signed
  /// engine-side (+ = Dr), which for a bank A/C is exactly how the bank
  /// prints it. Either may be null when the seam cannot answer; the check is
  /// then [ImportBalanceOutcome.unavailable] rather than a guess.
  static ImportBalanceCheck of(
    ParsedStatement statement, {
    required int? ledgerOpeningPaise,
    required int? ledgerClosingPaise,
  }) {
    final lines = statement.lines;
    if (lines.isEmpty) {
      return const ImportBalanceCheck(
        outcome: ImportBalanceOutcome.unavailable,
        lineCount: 0,
      );
    }
    final first = lines.first;
    final last = lines.last;
    final movement = lines.fold(0, (sum, l) => sum + signedPaise(l));
    // The statement's own opening is the balance *before* its first line, so
    // the line's own effect comes back off its running balance.
    final statementOpening = first.balancePaise == null
        ? null
        : first.balancePaise! - signedPaise(first);
    final statementClosing = last.balancePaise;
    if (statementOpening == null ||
        statementClosing == null ||
        ledgerOpeningPaise == null ||
        ledgerClosingPaise == null) {
      return ImportBalanceCheck(
        outcome: ImportBalanceOutcome.unavailable,
        lineCount: lines.length,
        statementOpeningPaise: statementOpening,
        statementClosingPaise: statementClosing,
        ledgerOpeningPaise: ledgerOpeningPaise,
        ledgerClosingPaise: ledgerClosingPaise,
        movementPaise: movement,
        firstDate: first.date,
        lastDate: last.date,
      );
    }
    final opensSame = statementOpening == ledgerOpeningPaise;
    final closesSame = statementClosing == ledgerClosingPaise;
    // A mismatched opening is failing whatever the closing does: an earlier
    // statement is missing, and every figure after it is built on sand
    // (07 §11 item 1 🔒). Otherwise, a book already standing at the
    // statement's closing has nothing left to record — matched; anything else
    // is the ordinary case, passing.
    final outcome = !opensSame
        ? ImportBalanceOutcome.failing
        : closesSame
        ? ImportBalanceOutcome.matched
        : ImportBalanceOutcome.passing;
    return ImportBalanceCheck(
      outcome: outcome,
      lineCount: lines.length,
      statementOpeningPaise: statementOpening,
      statementClosingPaise: statementClosing,
      ledgerOpeningPaise: ledgerOpeningPaise,
      ledgerClosingPaise: ledgerClosingPaise,
      movementPaise: movement,
      firstDate: first.date,
      lastDate: last.date,
    );
  }

  /// Whether the projected closing really lands on the statement's — the
  /// half of *passing* that is arithmetic rather than copy.
  bool get closingWillMatch => projectedClosingPaise == statementClosingPaise;
}

/// A line's effect on the A/C in **engine sign**: money in is a debit to a
/// bank A/C (+), money out a credit (−). The bank's own words stay *Money in*
/// / *Money out* on every surface (02 §10 🔒); only the arithmetic is signed.
int signedPaise(ParsedLine line) =>
    line.direction == BankDirection.moneyIn ? line.paise : -line.paise;
