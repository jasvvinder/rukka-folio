// The component system's container atom and its one row (13 §4): the brand's
// 3px left-rule card (design-system §3) and the measured label/amount row
// every surface draws a figure in. Tokens only — a hex literal here is
// review-blocking (CLAUDE.md, design-system).
//
// `features/home` had these as originals and `features/partners` as a copy
// (`PartnersCard`); this is the one definition.
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// A card with the brand's 3px left rule (design-system §3) — the container
/// every group of figures sits in (13 §4).
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
/// threshold (13 §4, 07 §1 rule 11). Everything drawn as `label … amount`
/// goes through here.
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
