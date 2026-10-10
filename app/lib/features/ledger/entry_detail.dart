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
import 'package:drift/drift.dart';

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
    this.inLockedPeriod = false,
    this.lockedOn,
    this.lockedMonths = const {},
    this.bookStart,
  });

  @override
  String get entryId => view.id;

  /// The entry's month is locked (02 §8 🔒) — read from the projection's own
  /// month states, never assumed. 02 §5 🔒: in a locked period amendment is
  /// forbidden by rule and the only path is the reversal dated in the open
  /// period (*Fix an old entry*).
  final bool inLockedPeriod;

  /// The day the lock in force over the entry's month was signed (the
  /// physical part of its HLC), when the projection recorded it.
  final LocalDate? lockedOn;

  /// Every month of the entry's book that is locked, as the projection held
  /// them when S4.1 loaded. The amend sheet greys these in its calendar
  /// (07 §5 step 4 🔒) so a correction is never moved into a closed month the
  /// engine would then refuse as `periodLocked` (02 §8).
  final Set<YearMonth> lockedMonths;

  /// The day the book begins (ADR 2026-09-09d §4): nothing is dated before
  /// it, so the amend sheet's calendar starts there. Null when not recorded.
  final LocalDate? bookStart;

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
  /// (02 §5); a reversed entry is corrected by re-entering, not by amending;
  /// and nothing in a locked month is amended (02 §5 🔒 *Locked period*).
  bool get canAmend => !isReplaced && !isReversed && !inLockedPeriod;

  /// One reversal per entry (02 §5, `alreadyReversed`). A locked month does
  /// not stop it: the reversal is dated today, in the open period, and is the
  /// one path 02 §5 leaves for an entry in a locked month.
  bool get canReverse => !isReplaced && !isReversed;

  /// *Correct this* is off only because the month is locked — the case whose
  /// reason is the lock and whose path is *Fix this entry* (07 §1 rule 6).
  bool get lockedOnly => inLockedPeriod && !isReplaced && !isReversed;

  /// A locked-month entry already taken out by a reversal dated in a later,
  /// open month — what *Fix this entry* leaves behind. 02 §5 🔒 pairs that
  /// reversal with the corrected re-entry, so S4.1 keeps offering *Enter it
  /// again* here rather than ending on two greyed buttons (07 §1 rule 6).
  ///
  /// ⚠️ SPEC: the re-entry carries no `refs` back to this entry (02 §5 names
  /// none), so S4.1 cannot tell whether the user already entered it again;
  /// the offer is worded as a conditional (*if it still belongs in the
  /// books*) rather than hidden or nagged.
  bool get awaitsReentry {
    final reversal = reversedBy;
    return inLockedPeriod &&
        !isReplaced &&
        reversal != null &&
        reversal.date.yearMonth != view.date.yearMonth;
  }

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
/// Reads only, and only through the facade: `LocalLedger.entry` answers the
/// projected case, `LocalLedger.heldFor` answers *is this envelope held, and
/// what is it waiting for*, and `LocalLedger.reversalOf` answers *what
/// reversed this entry* (both added for this screen — no screen reaches into
/// the Drift tables itself).
Future<EntryDetail> loadEntryDetail(LocalLedger ledger, String id) async {
  final view = await ledger.entry(id);
  if (view == null) {
    final held = await ledger.heldFor(id);
    if (held != null) {
      return EntryDetailHeld(id, waitingForId: held.waitingForId);
    }
    return EntryDetailMissing(id);
  }
  final chart = await ledger.chartOf(view.bookId);
  final reversalId = await ledger.reversalOf(id);
  final lock = await _lockOver(ledger, view.bookId, view.date);
  return EntryDetailPosted(
    inLockedPeriod: lock.locked,
    lockedOn: lock.on,
    lockedMonths: await _lockedMonths(ledger, view.bookId),
    bookStart: await ledger.startDateOf(view.bookId),
    view: view,
    chart: chart,
    corrects: view.amends == null ? null : await ledger.entry(view.amends!),
    correctedBy: view.supersededBy == null
        ? null
        : await ledger.entry(view.supersededBy!),
    reverses: view.reverses == null ? null : await ledger.entry(view.reverses!),
    reversedBy: reversalId == null ? null : await ledger.entry(reversalId),
  );
}

/// Whether [date]'s month is locked in [bookId], and the day its lock was
/// signed.
///
/// Read from `periods_p`, the projection's month states (03; written by the
/// recompute from the same `PeriodLedger` `LocalLedger.amend` consults), so
/// S4.1 offers exactly what the engine will accept. ⚠️ SPEC: `LocalLedger`
/// publishes no period-status read, so this reads the projection table the
/// way `features/close/ledger_close_source.dart` does; a facade method
/// (`LocalLedger.periodStatus`) belongs to `app/lib/shared`, which this lane
/// does not own — see the FIX200 lane report.
Future<({bool locked, LocalDate? on})> _lockOver(
  LocalLedger ledger,
  String bookId,
  LocalDate date,
) async {
  final db = ledger.db;
  final row =
      await (db.select(db.periodsP)..where(
            (t) =>
                t.bookId.equals(bookId) &
                t.year.equals(date.year) &
                t.month.equals(date.month),
          ))
          .getSingleOrNull();
  if (row == null || row.state != 'locked') return (locked: false, on: null);
  final raw = row.lockHlc;
  final ms = raw == null ? 0 : Hlc(raw).physicalMs;
  if (ms <= 0) return (locked: true, on: null);
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  return (locked: true, on: LocalDate(at.year, at.month, at.day));
}

/// Every locked month of [bookId], from the same `periods_p` rows
/// [_lockOver] reads (and with the same ⚠️ SPEC: no facade read exists yet).
Future<Set<YearMonth>> _lockedMonths(LocalLedger ledger, String bookId) async {
  final db = ledger.db;
  final rows = await (db.select(
    db.periodsP,
  )..where((t) => t.bookId.equals(bookId) & t.state.equals('locked'))).get();
  return {for (final r in rows) YearMonth(r.year, r.month)};
}
