// The states every Home surface ships (13 §4.3): loading skeleton, error with
// retry, empty with the one next action. Tokens only — a hex literal here is
// review-blocking (CLAUDE.md, design-system).
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// The ruled skeleton (11 §4.5): never a spinner, always the shape of what is
/// coming. [label] is what a screen reader announces while it shows.
class HomeSkeleton extends StatelessWidget {
  /// Creates the skeleton.
  const HomeSkeleton({super.key, required this.label, this.rows = 6});

  /// Screen-reader announcement.
  final String label;

  /// How many ruled rows to draw.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      child: ListView.builder(
        padding: const EdgeInsets.all(RkSpace.gutter),
        itemCount: rows,
        itemBuilder: (context, i) => Container(
          height: RkSpace.rowMinHeight,
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: i.isEven
                  ? RkMotion.skeletonLabelWidthMax
                  : RkMotion.skeletonLabelWidthMin,
              child: Container(
                height: RkSpace.s3,
                decoration: BoxDecoration(
                  color: status.skeletonLabel,
                  borderRadius: BorderRadius.circular(RkRadius.sm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error with a named cause and the path out (07 §1 rule 12, 13 §4.3).
class HomeErrorState extends StatelessWidget {
  /// Creates the state.
  const HomeErrorState({
    super.key,
    required this.text,
    required this.retryLabel,
    required this.onRetry,
  });

  /// What failed, in the user's words.
  final String text;

  /// Label of the retry control.
  final String retryLabel;

  /// Clears the error and tries again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(RkSpace.s6),
    children: [
      const SizedBox(height: RkSpace.s8),
      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
      const SizedBox(height: RkSpace.s3),
      Text(text, textAlign: TextAlign.center),
      const SizedBox(height: RkSpace.s4),
      Center(
        child: FilledButton(onPressed: onRetry, child: Text(retryLabel)),
      ),
    ],
  );
}

/// A card with the brand's 3px left rule (design-system §2) — the container
/// every Home group sits in.
class RkRuledCard extends StatelessWidget {
  /// Creates the card.
  const RkRuledCard({super.key, required this.child, this.ruleColor});

  /// Card contents.
  final Widget child;

  /// Rule colour; defaults to the theme's primary.
  final Color? ruleColor;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(RkRadius.lg),
        border: Border.all(color: status.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      // IntrinsicHeight, not a bare stretched Row: inside a ListView the
      // card's height is unbounded, and `CrossAxisAlignment.stretch` would
      // hand the 3px rule an infinite height constraint.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: RkRadius.ruleLeftWidth,
              color: ruleColor ?? Theme.of(context).colorScheme.primary,
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// A label on the left and a figure on the right that **stacks** past 1.3×
/// text scale instead of overflowing (07 §1 rule 11; the defect S4 fixed the
/// same way). Everything Home draws as `label … amount` goes through here.
class RkLabelAmountRow extends StatelessWidget {
  /// Creates the row.
  const RkLabelAmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.leading,
    this.meta,
    this.onTap,
    this.semanticHint,
  });

  /// Left-hand label.
  final Widget label;

  /// Right-hand figure.
  final Widget amount;

  /// Optional leading icon (colour is never alone — 07 §1 rule 3).
  final Widget? leading;

  /// Optional second line under the label.
  final Widget? meta;

  /// Drill-down (07 §4: every position line drills into its list).
  final VoidCallback? onTap;

  /// Screen-reader hint for [onTap].
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [label, ?meta],
    );
    final body = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              left,
              const SizedBox(height: RkSpace.s1),
              amount,
            ],
          )
        : Row(
            children: [
              Expanded(child: left),
              const SizedBox(width: RkSpace.s3),
              Flexible(child: amount),
            ],
          );
    final withLeading = leading == null
        ? body
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: RkSpace.s3),
                child: leading,
              ),
              Expanded(child: body),
            ],
          );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.cardPadding,
          vertical: RkSpace.s3,
        ),
        child: Row(
          children: [
            Expanded(child: withLeading),
            if (onTap != null) const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      hint: semanticHint,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

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
                  child: Text(
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
              child: Text(
                progressText,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: RkSpace.s1),
            Text(
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
