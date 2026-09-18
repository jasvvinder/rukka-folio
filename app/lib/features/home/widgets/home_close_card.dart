// The Home **Close card** 🔒 (07 §13 bullet 1; 13 §3.2 rows S10 and S10.2).
//
// 07 §13 🔒: *"Close card appears on Home from the 1st for each book the user
// closes: `Close August ▸ 4 steps`."* Three states, and the third is a door
// rather than a card:
//
//   * **not started** — `Close Aug 2026 · 4 steps`, straight into S10.
//   * **in progress** — it *resumes*: progress lives in `close_progress_local`
//     and the card says which step it picks up at (07 §13 *Resumable* 🔒).
//   * **closed ✓** — the card gives way to the **S10.2** door for that month,
//     because the month summary is the reward and the reward has to be
//     reachable (07 §13 🔒).
//
// A fourth state rides on top of the first two: a book **waiting on a phone**
// (an open author gap or a `held` envelope) says so on the card rather than
// letting the closer walk into S10.5 to find out (ADR 2026-09-05b §3–4). The
// card still opens — the wizard's first three steps are useful work, and a
// door that refuses to open is the dead end 07 §1 rule 6 forbids.
//
// **The month label** is S10's, exactly. ⚠️ SPEC (CL1's, left standing — it is
// the owner's to settle): 07 §13 🔒 writes `Close August`, a full English
// month, while 07 §1 rule 5 🔒 says English abbreviates and `shared_*.arb`
// carries only the abbreviated set. The global rule is taken, so this says
// *Close Aug 2026* and mints no month vocabulary. The card and the wizard read
// the same way because they format the month the same way.
//
// Tokens only — a hex literal here is review-blocking (CLAUDE.md,
// design-system).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../../close/close_source.dart';

/// Keys the close card answers to.
abstract final class HomeCloseKeys {
  /// One book's card, by book id.
  static Key card(String bookId) => Key('home.close.$bookId');

  /// The action inside one book's card.
  static Key action(String bookId) => Key('home.close.action.$bookId');
}

/// One Home *Close card* per book the user closes (07 §13 🔒).
///
/// The list is the caller's: S1 in a book scope passes that book alone, and a
/// tenant with nothing to close passes an empty list and nothing is drawn.
class HomeCloseCards extends StatelessWidget {
  /// Creates the section.
  const HomeCloseCards({
    super.key,
    required this.statuses,
    this.showBookName = false,
    this.onOpenClose,
    this.onOpenSummary,
  });

  /// One entry per book to draw.
  final List<BookCloseStatus> statuses;

  /// Names the book on each card — worth it when more than one is on screen,
  /// noise when the user has a single book.
  final bool showBookName;

  /// Opens S10 for a book's month. Null disables the action rather than
  /// dropping it, so the card never becomes an unexplained decoration.
  final void Function(BookCloseStatus status)? onOpenClose;

  /// Opens S10.2 for a month that has closed (07 §13 🔒).
  final void Function(BookCloseStatus status)? onOpenSummary;

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in statuses)
          _CloseCard(
            status: s,
            showBookName: showBookName,
            onOpenClose: onOpenClose,
            onOpenSummary: onOpenSummary,
          ),
      ],
    );
  }
}

class _CloseCard extends StatelessWidget {
  const _CloseCard({
    required this.status,
    required this.showBookName,
    this.onOpenClose,
    this.onOpenSummary,
  });

  final BookCloseStatus status;
  final bool showBookName;
  final void Function(BookCloseStatus status)? onOpenClose;
  final void Function(BookCloseStatus status)? onOpenSummary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tints = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final month = '${monthName(l, status.period.month)} ${status.period.year}';
    final closed = status.state == BookCloseState.closed;

    final title = closed
        ? l.homeCloseDoneTitle(month)
        : l.homeCloseTitle(month);

    // The second line, in order of what the closer most needs to know.
    final meta = switch (status.state) {
      BookCloseState.closed => null,
      BookCloseState.waiting => l.homeCloseWaiting(
        status.waitingOn ?? l.closeBlockedUnknownDevice,
      ),
      _ when status.step != null => l.homeCloseResume(
        status.step!.index + 1,
        CloseStep.values.length,
      ),
      _ => l.homeCloseSteps(CloseStep.values.length),
    };

    final (icon, tint) = switch (status.state) {
      BookCloseState.closed => (Icons.lock_outline, tints.success),
      BookCloseState.waiting => (Icons.phonelink_off, tints.warning),
      BookCloseState.inProgress => (Icons.pending_outlined, tints.info),
      BookCloseState.notStarted => (Icons.event_available_outlined, tints.info),
    };

    final open = closed ? onOpenSummary : onOpenClose;
    final actionLabel = closed
        ? l.homeCloseDoneAction
        : l.homeCloseTitle(month);

    return RkRuledCard(
      key: HomeCloseKeys.card(status.bookId),
      ruleColor: tint,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon beside the words, never instead of them (07 §1 rule 3).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: RkSpace.s4, color: tint),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RkFitText(title, style: text.titleMedium),
                      if (showBookName && status.bookName.isNotEmpty)
                        RkFitText(
                          l.homeCloseBook(status.bookName),
                          style: text.bodySmall?.copyWith(color: tints.muted),
                        ),
                      if (meta != null)
                        RkFitText(
                          meta,
                          style: text.bodySmall?.copyWith(color: tints.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                key: HomeCloseKeys.action(status.bookId),
                onPressed: open == null ? null : () => open(status),
                child: RkFitText(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
