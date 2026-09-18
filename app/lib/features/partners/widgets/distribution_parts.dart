// The atoms S14.1 is built from (13 §4.2 stepper, §4.3 states; 07 §1 rules).
//
// They are deliberately local to this feature. `features/close` grew the same
// three shapes for the month-close wizard (`close_parts.dart`) and they want
// hoisting into `shared/widgets` — but that folder belongs to another lane
// this round, so copying is the only move that does not cross a boundary.
// Noted in the lane report as the one duplication this screen carries.
//
// Tokens only: a hex literal here is review-blocking (CLAUDE.md, design-system).
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';

/// The stepper progress atom (13 §4.2): a rule per step, and the words *Step n
/// of 3* beneath — the count is never left to the tint alone (07 §1 rule 3).
class DistributeStepper extends StatelessWidget {
  /// Creates the stepper.
  const DistributeStepper({
    super.key,
    required this.label,
    required this.index,
    required this.total,
  });

  /// *Step {n} of {total}*, already localised.
  final String label;

  /// Zero-based index of the step on screen.
  final int index;

  /// How many steps there are.
  final int total;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: RkSpace.s1),
                  Expanded(
                    child: Container(
                      height: RkMotion.loaderTrackHeight,
                      color: i <= index ? scheme.primary : status.loaderTrack,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: RkSpace.s2),
            ExcludeSemantics(
              child: RkFitText(
                label,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: status.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The heading over one step: the title, then one line saying what it is for.
class DistributeStepHeader extends StatelessWidget {
  /// Creates the header.
  const DistributeStepHeader({
    super.key,
    required this.title,
    required this.help,
  });

  /// The step's own title.
  final String title;

  /// One line of help.
  final String help;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        RkSpace.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(title, style: text.titleLarge),
          const SizedBox(height: RkSpace.s1),
          RkFitText(
            help,
            style: text.bodyMedium?.copyWith(color: status.muted),
          ),
        ],
      ),
    );
  }
}

/// One `label · amount` line. The amount is tabular and right-aligned; the
/// label wraps rather than pushing it off a 360 px phone at 200 % (07 §1
/// rule 11).
class DistributeFigureRow extends StatelessWidget {
  /// Creates the row.
  const DistributeFigureRow({
    super.key,
    required this.label,
    required this.amount,
    this.strong = false,
    this.muted = false,
  });

  /// The words.
  final String label;

  /// The figure, already formatted for the locale.
  final String amount;

  /// Draws it as a total.
  final bool strong;

  /// Draws it as a caption-weight line.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final base = strong
        ? theme.textTheme.titleSmall
        : (muted ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium);
    final style = muted ? base?.copyWith(color: status.muted) : base;
    final figure = Text(
      amount,
      textAlign: TextAlign.end,
      // A money figure never wraps and never shrinks: tabular digits are the
      // whole point of the column (07 §1 rule 4). When it will not fit beside
      // its label, the label goes above it instead.
      softWrap: false,
      style: style?.copyWith(fontFeatures: RkType.tabular),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(
              text: amount,
              style: style?.copyWith(fontFeatures: RkType.tabular),
            ),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout();
          final needed = painter.width;
          painter.dispose();
          // Half the row for the figure, the rest for the words. At 200 % on a
          // 360 px phone a five-figure rupee amount takes more than that, and
          // a Row would then print it straight off the edge (07 §1 rule 11).
          final fits = needed <= (constraints.maxWidth - RkSpace.s3) / 2;
          return fits
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(label, style: style)),
                    const SizedBox(width: RkSpace.s3),
                    figure,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label, style: style),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: figure,
                    ),
                  ],
                );
        },
      ),
    );
  }
}

/// The wizard's bottom bar: *Back* beside the primary action when both labels
/// fit, stacked when they do not.
///
/// The choice is **font-measured, never a text-scale threshold** — the words
/// here are single Gurmukhi and Devanagari compounds with no break opportunity
/// at all, so a threshold that has not measured the font draws them straight
/// past the edge (07 §1 rule 11).
class DistributeFooter extends StatelessWidget {
  /// Creates the bar. A null label omits that button.
  const DistributeFooter({
    super.key,
    this.backLabel,
    this.onBack,
    this.backKey,
    this.nextLabel,
    this.onNext,
    this.nextKey,
  });

  /// *Back*, or null at the first step.
  final String? backLabel;

  /// Steps back.
  final VoidCallback? onBack;

  /// Key of the back button.
  final Key? backKey;

  /// The forward action, or null when there is none.
  final String? nextLabel;

  /// Steps on, or commits. Null disables the button (13 §4.3
  /// disabled-with-reason — the reason is printed above it).
  final VoidCallback? onNext;

  /// Key of the forward button.
  final Key? nextKey;

  double _need(BuildContext context, String label, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final width = painter.minIntrinsicWidth;
    painter.dispose();
    // Plus the button's own horizontal chrome.
    return width + RkSpace.s6 * 2;
  }

  @override
  Widget build(BuildContext context) {
    final backLabel = this.backLabel;
    final nextLabel = this.nextLabel;
    if (backLabel == null && nextLabel == null) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final back = backLabel == null
              ? null
              : OutlinedButton(
                  key: backKey,
                  onPressed: onBack,
                  child: Text(backLabel),
                );
          final next = nextLabel == null
              ? null
              : FilledButton(
                  key: nextKey,
                  onPressed: onNext,
                  child: Text(nextLabel),
                );
          if (back == null || next == null) {
            return SizedBox(width: double.infinity, child: back ?? next);
          }
          final half = (constraints.maxWidth - RkSpace.s3) / 2;
          final fits =
              _need(context, backLabel!, style) <= half &&
              _need(context, nextLabel!, style) <= half;
          return fits
              ? Row(
                  children: [
                    Expanded(child: back),
                    const SizedBox(width: RkSpace.s3),
                    Expanded(child: next),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(width: double.infinity, child: next),
                    const SizedBox(height: RkSpace.s3),
                    SizedBox(width: double.infinity, child: back),
                  ],
                );
        },
      ),
    );
  }
}
