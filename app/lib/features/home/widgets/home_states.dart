// S1.4's rebuilding card. The states and containers this file used to hold —
// `RkFitText`, the ruled skeleton, the error-with-retry and the ruled card
// with its measured label/amount row — are the design-system atoms of 13 §4
// and now live once in `shared/widgets/`, where `features/cash_count`,
// `features/partners` and `features/close` import them instead of copying
// them. Tokens only — a hex literal here is review-blocking.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';

/// S1.4 **Book incomplete — rebuilding** (07 §28 🔒, ADR 2026-09-05f §B): the
/// determinate loader rule with a count — *"{done} of {total} entries
/// restored"* (11 §4.5 🔒: 2px rule, never a spinner, counts and never
/// percentages) — replacing the Home card while the book's projections are
/// dropped and recomputed (local corruption, Recompute on upgrade,
/// `store_epoch` re-pull; ADR 2026-09-05c §3/§6).
///
/// The card says in words that the book is not whole yet: while this shows,
/// no figure of the book may be read as final (13 §3.2 row S1.4).
class HomeRebuildingCard extends StatelessWidget {
  /// Creates the card.
  const HomeRebuildingCard({
    super.key,
    required this.title,
    required this.progressText,
    required this.note,
    required this.fraction,
  });

  /// What is happening, in the user's words.
  final String title;

  /// *"{done} of {total} entries restored"* — a count, never a percentage.
  final String progressText;

  /// Why the figures are not final yet.
  final String note;

  /// 0..1 for the determinate rule.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return RkRuledCard(
      ruleColor: status.pending,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colour never alone (07 §1 rule 3): the icon and the words carry
            // the state, the amber rule only reinforces it.
            Row(
              children: [
                Icon(Icons.autorenew, size: RkSpace.s4, color: status.pending),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: RkFitText(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s3),
            // The loader is a RULE, and it is determinate: `value` is always
            // supplied, so this can never render as a sweep (11 §4.5 🔒).
            ClipRRect(
              borderRadius: BorderRadius.circular(RkRadius.sm),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: RkMotion.loaderTrackHeight,
                backgroundColor: status.loaderTrack,
                color: status.loaderSegment,
              ),
            ),
            const SizedBox(height: RkSpace.s2),
            // A live region: the count is announced as it moves (11 §4.5).
            Semantics(
              liveRegion: true,
              child: RkFitText(
                progressText,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: RkSpace.s1),
            RkFitText(
              note,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: status.muted),
            ),
          ],
        ),
      ),
    );
  }
}
