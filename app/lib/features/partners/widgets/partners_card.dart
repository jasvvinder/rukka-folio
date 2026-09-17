// The two pieces S14 and S14.2 add to the design-system atoms: a
// label-over-figure block and a section heading. The 3px-left-rule card used
// to be copied here as `PartnersCard`; it is the 13 §4 container atom
// `RkRuledCard` and now comes from `shared/widgets/`.
//
// Layout rule (07 §1 rule 9 and 11, 13 §4.3): a figure is drawn **under** its
// label, never beside it. At 200 % font scale on a 360×800 phone a
// `label … ₹12,34,567` row has nowhere left to go; stacked, it simply grows
// downward, so the screen has no text-scale threshold to get wrong.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// A caption with its figure underneath — tabular, never coloured.
///
/// 07 §1 rule 3 puts colour in the numerals *and never alone*: it is always
/// paired with a sign, a column and a word. These figures are magnitudes in
/// labelled blocks with no sign of their own (*Put in*, *Took out*), so they
/// stay in ink; the one figure whose direction matters — the net — carries
/// its direction in words (*The business owes {name}*), which is stronger
/// than a hue and survives grayscale.
class PartnersFigure extends StatelessWidget {
  /// Creates the block.
  const PartnersFigure({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  /// The caption.
  final String label;

  /// The pre-formatted figure (₹, Indian grouping — 07 §1 rule 4).
  final String value;

  /// Draws the figure in the larger amount style.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = emphasis
        ? theme.textTheme.titleMedium ?? RkType.amountHero
        : theme.textTheme.labelLarge ?? RkType.amountRow;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: RkStatusColors.of(context).muted,
            ),
          ),
          const SizedBox(height: RkSpace.s1),
          Text(value, style: base.copyWith(fontFeatures: RkType.tabular)),
        ],
      ),
    );
  }
}

/// A section heading.
class PartnersSectionHeader extends StatelessWidget {
  /// Creates the header.
  const PartnersSectionHeader(this.text, {super.key});

  /// The words.
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RkSpace.gutter,
      RkSpace.s5,
      RkSpace.gutter,
      RkSpace.s3,
    ),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}
