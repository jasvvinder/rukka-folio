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
      // A Stack, not an IntrinsicHeight + stretched Row. The rule has to run
      // the full height of a card whose height is unbounded inside a
      // ListView, and a positioned child pinned top-to-bottom does that
      // without anyone asking the contents for an intrinsic height — which
      // matters, because [RkFitText] measures itself against the width it is
      // actually given and a `LayoutBuilder` cannot answer an intrinsic
      // query. The card sizes to `child`; the rule only paints.
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: RkRadius.ruleLeftWidth,
            ),
            child: child,
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: RkRadius.ruleLeftWidth,
            child: ColoredBox(
              color: ruleColor ?? Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A label on the left and a figure on the right that drops the figure to its
/// own line **when the two no longer fit as measured** — not at a text-scale
/// threshold (07 §1 rule 11). Everything Home draws as `label … amount` goes
/// through here.
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
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [label, ?meta],
    );
    // Measured, never thresholded. The old rule stacked past 1.3× text scale,
    // which split the row 50/50 below it: at exactly 1.3× on a 360 px phone
    // `+₹1,14,600` needed 188 px of the 139 px it was given and lost its last
    // digits — silently, because a paragraph too narrow for one unbreakable
    // word draws past its edge instead of throwing. A scale number cannot
    // answer that question; it does not know how wide a word is in the font
    // being drawn, and 1.3× in Gurmukhi is not 1.3× in English.
    //
    // `Wrap` asks the font instead: label and amount sit side by side while
    // both fit the row as measured, and the amount drops to its own line the
    // moment they do not (07 §1 rule 11).
    final body = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: RkSpace.s3,
      runSpacing: RkSpace.s1,
      children: [
        left,
        // Last resort, for a figure wider than the whole row: shrink it to
        // fit rather than lose its final digits. A cut number is a wrong
        // number — the one thing a ledger may never show.
        FittedBox(fit: BoxFit.scaleDown, child: amount),
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

/// Text that never draws a word past the edge of its box.
///
/// Flutter wraps *between* words; a single word wider than the line is laid
/// out at the line width and drawn straight past it — no exception thrown, no
/// ellipsis, just letters over the edge, which is why a test can be green
/// over text the reader cannot finish. Devanagari and Gurmukhi compounds
/// reach that width long before English does: at 200 % on a 360 px phone
/// *प्रविष्टियाँ* alone needs 339 px of the 291 px a card has to give.
///
/// So this measures the widest unbreakable word in the string — in the font
/// and at the scale actually in force, never from a scale threshold — and
/// steps the scale down only as far as that word needs. Anything that already
/// fits is drawn at exactly the size the reader asked for (07 §1 rule 11).
class RkFitText extends StatelessWidget {
  /// Creates the text.
  const RkFitText(this.data, {super.key, this.style});

  /// The string to draw.
  final String data;

  /// Style, merged onto the inherited one exactly as [Text] merges it.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final asked = MediaQuery.textScalerOf(context);
        var scaler = asked;
        final room = constraints.maxWidth;
        if (room.isFinite && room > 1) {
          final painter = TextPainter(
            text: TextSpan(text: data, style: resolved),
            textScaler: asked,
            textDirection: Directionality.of(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout();
          final widest = painter.minIntrinsicWidth;
          painter.dispose();
          // A pixel of slack: glyph advances do not scale perfectly linearly,
          // and landing exactly on the boundary would still clip.
          if (widest > room) {
            scaler = TextScaler.linear(asked.scale(1) * (room - 1) / widest);
          }
        }
        return Text(data, style: style, textScaler: scaler);
      },
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
