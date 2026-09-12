// What S4.1 needs to draw one entry (13 §3.2 row S4.1): the projected entry,
// the chart that names its two sides, and the neighbours of its correction
// chain (02 §5) — the version it corrects, the version that corrected it, the
// entry it reverses, the entry that reversed it.
//
// Three outcomes, because an id can mean three things (ADR 2026-09-05b §4):
//   • [EntryDetailPosted] — projected, so it has lines and a balance effect;
//   • [EntryDetailHeld]   — a dangling amend/reverse/decision whose target has
//     not arrived. Held is NOT an error and NOT a quarantine: the envelope is
//     in the mirror, verified, simply not projected and not counted. S4.1 says
//     *"waiting for the entry this changes"* and nothing more alarming;
//   • [EntryDetailMissing] — nothing on this phone knows the id.
//
// Nothing here mutates: the chain is read, never rewritten (CLAUDE.md rule 2 —
// an amendment is a *new* entry; the version it replaces stays exactly as it
// was posted).
import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;

import '../../shared/ledger/local_ledger.dart';

/// One entry as S4.1 resolved it.
sealed class EntryDetail {
  /// Creates the state.
  const EntryDetail();

  /// The id S4.1 was opened on.
  String get entryId;
}

/// A projected entry: amount, both sides, date, note, author, audit trail.
final class EntryDetailPosted extends EntryDetail {
  /// Creates the state.
  const EntryDetailPosted({
    required this.view,
    required this.chart,
    this.corrects,
    this.correctedBy,
    this.reverses,
    this.reversedBy,
  });

  @override
  String get entryId => view.id;

  /// The projected entry with its lines.
  final EntryView view;

  /// Names the accounts on both sides.
  final Chart chart;

  /// The earlier version this one replaced (`refs.amends`), if any.
  final EntryView? corrects;

  /// The later version that replaced this one (`superseded_by`), if any.
  final EntryView? correctedBy;

  /// The entry this one reverses (`refs.reverses`), if any.
  final EntryView? reverses;

  /// The entry that reverses this one, if any.
  final EntryView? reversedBy;

  /// Amended away — history keeps it, views show the head (02 §5).
  bool get isReplaced => view.supersededBy != null;

  /// Fully reversed: `void` is the derived state of a reversed entry (02 §5).
  bool get isReversed => reversedBy != null || view.status == 'void';

  /// Waiting on an approver (02 §3).
  bool get isWaitingReview => view.reviewState == 'open';

  /// Amend chains are linear and the head is the only amendable version
  /// (02 §5); a reversed entry is corrected by re-entering, not by amending.
  bool get canAmend => !isReplaced && !isReversed;

  /// One reversal per entry (02 §5, `alreadyReversed`).
  bool get canReverse => !isReplaced && !isReversed;

  /// The line that speaks for the entry on a consumer surface: the money
  /// account's own line, whose engine sign already reads *money came in* /
  /// *money went out* (02 §2 row 1, 02 §10). Falls back to the largest line
  /// for an entry that touches no money account (an adjustment, an opening
  /// balance).
  int get headlinePaise {
    var best = 0;
    for (final line in view.lines) {
      if (chart.maybeAccount(line.accountId)?.accountClass ==
          AccountClass.money) {
        return line.amount.raw;
      }
      if (line.amount.raw.abs() > best.abs()) best = line.amount.raw;
    }
    return best;
  }
}

/// A dangling amend/reverse/decision: held, not projected, not counted
/// (ADR 2026-09-05b §4, 02 §5). Never rendered as an error.
final class EntryDetailHeld extends EntryDetail {
  /// Creates the state.
  const EntryDetailHeld(this.entryId, {this.waitingForId});

  @override
  final String entryId;

  /// The target that has not arrived (`envelopes_local.held_for`), when the
  /// mirror recorded one.
  final String? waitingForId;
}

/// The id resolves to nothing on this phone.
final class EntryDetailMissing extends EntryDetail {
  /// Creates the state.
  const EntryDetailMissing(this.entryId);

  @override
  final String entryId;
}

/// Resolves [id] against the local ledger.
///
/// Reads only. `LocalLedger.entry` answers the projected case; the two lookups
/// it has no method for — *is this envelope held?* and *what reverses this
/// entry?* — are plain Drift reads of the mirror and of `entries_p`
/// (see the lane report's `open` items for the facade signatures wanted).
Future<EntryDetail> loadEntryDetail(LocalLedger ledger, String id) async {
  final view = await ledger.entry(id);
  if (view == null) {
    final db = ledger.db;
    final held =
        await (db.select(db.envelopesLocal)
              ..where((t) => t.objectId.equals(id) & t.held.equals(1))
              ..orderBy([(t) => OrderingTerm.asc(t.hlc)])
              ..limit(1))
            .getSingleOrNull();
    if (held != null) {
      return EntryDetailHeld(id, waitingForId: held.heldFor);
    }
    return EntryDetailMissing(id);
  }
  final chart = await ledger.chartOf(view.bookId);
  final db = ledger.db;
  final reversalRow =
      await (db.select(db.entriesP)
            ..where((t) => t.reverses.equals(id))
            ..limit(1))
          .getSingleOrNull();
  return EntryDetailPosted(
    view: view,
    chart: chart,
    corrects: view.amends == null ? null : await ledger.entry(view.amends!),
    correctedBy: view.supersededBy == null
        ? null
        : await ledger.entry(view.supersededBy!),
    reverses: view.reverses == null ? null : await ledger.entry(view.reverses!),
    reversedBy: reversalRow == null ? null : await ledger.entry(reversalRow.id),
  );
}
