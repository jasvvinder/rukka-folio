// S10.1 — *The family's state, not just yours* 🔒 (07 §13, 13 §3.2 row S10.1).
//
// 07 §13 🔒 writes the line out: *"Kirana closed ✓ · Agriculture waiting on
// Pankaj · Joint pool not started"* — "because closing is a joint act (§8) and
// the karta needs to know who he is waiting for". This draws exactly that, one
// row per book, and nothing else:
//
//   * **multi-book only.** A single-book tenant never sees this section — the
//     caller decides by the length of the list, so a solo shopkeeper is not
//     shown a heading about a family he does not have.
//   * **colour is never alone** (07 §1 rule 3): every row carries a glyph *and*
//     the state in words; the tint is third.
//   * **never a device id.** A gap's phone has no label source yet, so an
//     unnamed phone is *another phone* (07 §28 🔒; see `close_source.dart`).
//   * **the month rides along.** Months lock in order (02 §8.1 🔒), so two
//     books of one family are routinely on different months; a row whose month
//     differs from the one being closed here says so rather than reading as a
//     status of *this* month.
//
// Tokens only — a hex literal here is review-blocking (CLAUDE.md,
// design-system).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../close_source.dart';
import 'close_parts.dart';

/// Keys S10.1's parts answer to.
abstract final class FamilyCloseKeys {
  /// The whole section.
  static const section = Key('close.family');

  /// One book's row, by book id.
  static Key row(String bookId) => Key('close.family.row.$bookId');
}

/// S10.1 — where every book of the family stands in this month's close.
class FamilyCloseStatus extends StatelessWidget {
  /// Creates the section.
  const FamilyCloseStatus({
    super.key,
    required this.statuses,
    required this.period,
  });

  /// One entry per book the user closes, in the order they should read.
  final List<BookCloseStatus> statuses;

  /// The month the wizard around this section is closing — the reference the
  /// per-row month is compared against.
  ///
  /// The rows are a **statement**, not a set of doors: the closer is already
  /// inside one book's close, and sending him into another mid-wizard would
  /// abandon the step he is on.
  final YearMonth period;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return CloseCard(
      key: FamilyCloseKeys.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(l.closeFamilyTitle, style: text.titleMedium),
          const SizedBox(height: RkSpace.s1),
          RkFitText(
            l.closeFamilyHelp,
            style: text.bodySmall?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s2),
          for (final s in statuses) _FamilyRow(status: s, period: period),
        ],
      ),
    );
  }
}

class _FamilyRow extends StatelessWidget {
  const _FamilyRow({required this.status, required this.period});

  final BookCloseStatus status;
  final YearMonth period;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tints = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final (icon, tint) = switch (status.state) {
      BookCloseState.closed => (Icons.check_circle_outline, tints.success),
      BookCloseState.waiting => (Icons.phonelink_off, tints.warning),
      BookCloseState.inProgress => (Icons.pending_outlined, tints.info),
      BookCloseState.notStarted => (Icons.circle_outlined, tints.muted),
    };
    final state = switch (status.state) {
      BookCloseState.closed => l.closeFamilyStateClosed,
      BookCloseState.waiting => l.closeFamilyStateWaiting(
        status.waitingOn ?? l.closeBlockedUnknownDevice,
      ),
      BookCloseState.inProgress => l.closeFamilyStateInProgress,
      BookCloseState.notStarted => l.closeFamilyStateNotStarted,
    };
    // Months lock in order (02 §8.1 🔒): a book still on July must not read as
    // a July verdict on the August the closer is in.
    final elsewhere = status.period != period;
    final month = l.closeFamilyMonth(
      '${monthName(l, status.period.month)} ${status.period.year}',
    );

    // A Column, not a Row: at 200 % on a 360 px phone a book name and
    // *Waiting on another phone* do not share a line (07 §1 rule 11).
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RkFitText(status.bookName, style: text.bodyLarge),
        RkFitText(state, style: text.bodySmall?.copyWith(color: tints.muted)),
        if (elsewhere)
          RkFitText(month, style: text.bodySmall?.copyWith(color: tints.muted)),
      ],
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: RkSpace.s4, color: tint),
          const SizedBox(width: RkSpace.s2),
          Expanded(child: body),
        ],
      ),
    );

    return Semantics(
      key: FamilyCloseKeys.row(status.bookId),
      label: l.closeFamilyRow(status.bookName, state),
      child: row,
    );
  }
}
