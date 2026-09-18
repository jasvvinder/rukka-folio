// The small pieces S10 is built from: the stepper, the two tray lists and the
// disabled-with-reason action. The 13 §4.3 states (fit text, skeleton, error)
// come from `shared/widgets/` since W1 moved them there. Tokens only — a hex
// literal here is review-blocking (CLAUDE.md, design-system).
//
// **Colour is never alone** (07 §1 rule 3): every state here pairs its tint
// with a glyph *and* a word, and the blocking/warning split is carried first
// by two separate headings, then by the glyph, then by the tint.
import 'package:flutter/material.dart';

import '../../../shared/widgets/rk_fit_text.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// The stepper progress atom (13 §4.2): a rule per step, plus the words
/// *Step n of 4* — the count is never left to the tint alone.
class CloseStepper extends StatelessWidget {
  /// Creates the stepper.
  const CloseStepper({
    super.key,
    required this.label,
    required this.index,
    required this.total,
  });

  /// *Step {n} of {total}*, already localised.
  final String label;

  /// Zero-based index of the step being shown.
  final int index;

  /// How many steps there are (four — 02 §8 🔒).
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

/// The heading over one step: the 02 §8 words, then the one help line.
class CloseStepHeader extends StatelessWidget {
  /// Creates the header.
  const CloseStepHeader({super.key, required this.title, required this.help});

  /// The step's own title — 02 §8 🔒 verbatim.
  final String title;

  /// One line saying what the step is for.
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

/// A card with the 3 px left rule (brand §4.1) — the container every list and
/// panel on this screen sits in.
class CloseCard extends StatelessWidget {
  /// Creates the card.
  const CloseCard({super.key, required this.child, this.rule, this.padding});

  /// Contents.
  final Widget child;

  /// The left rule's colour; the theme's outline when null.
  final Color? rule;

  /// Inner padding; [RkSpace.cardPadding] on every side when null.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      padding: padding ?? const EdgeInsets.all(RkSpace.cardPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(RkRadius.lg),
        border: Border.all(color: status.hairline),
        // The rule motif: 3 px on the leading edge, never rounded there.
        boxShadow: null,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: rule ?? status.hairline,
            width: RkRadius.ruleLeftWidth,
          ),
        ),
        borderRadius: BorderRadius.circular(RkRadius.lg),
      ),
      child: child,
    );
  }
}

/// One row of a tray list, or of a state list: glyph · words · optional meta.
///
/// The glyph and the tint always travel together, and the words alone are
/// enough to tell a blocker from a warning.
class CloseStateRow extends StatelessWidget {
  /// Creates the row.
  const CloseStateRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.text,
    this.meta,
  });

  /// The glyph.
  final IconData icon;

  /// Its colour — from tokens, and never the only carrier of the meaning.
  final Color tint;

  /// The line itself.
  final String text;

  /// A second, quieter line: an A/C name, a party, a date.
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme;
    final meta = this.meta;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: RkSpace.s5, color: tint),
          const SizedBox(width: RkSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RkFitText(text, style: style.bodyMedium),
                if (meta != null) ...[
                  const SizedBox(height: RkSpace.s1),
                  RkFitText(
                    meta,
                    style: style.bodySmall?.copyWith(color: status.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An action that is off, with the reason beside it — never a control that
/// simply does nothing (13 §4.3 disabled-with-reason, 07 §1 rule 6: no dead
/// ends, so the reason may carry its own way out).
class CloseDisabledAction extends StatelessWidget {
  /// Creates the pair.
  const CloseDisabledAction({
    super.key,
    required this.label,
    required this.reason,
    this.wayOut,
    this.onWayOut,
    this.icon = Icons.lock_outline,
  });

  /// What the action would have been called.
  final String label;

  /// Why it is off, in the user's words.
  final String reason;

  /// The label of the path out, when there is one.
  final String? wayOut;

  /// Takes the path out.
  final VoidCallback? onWayOut;

  /// The glyph on the dead control.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final wayOut = this.wayOut;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          enabled: false,
          button: true,
          label: '$label. $reason',
          child: ExcludeSemantics(
            child: FilledButton.icon(
              onPressed: null,
              icon: Icon(icon),
              label: RkFitText(label),
            ),
          ),
        ),
        const SizedBox(height: RkSpace.s2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: RkSpace.s4, color: status.muted),
            const SizedBox(width: RkSpace.s2),
            Expanded(
              child: RkFitText(
                reason,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: status.muted),
              ),
            ),
          ],
        ),
        if (wayOut != null && onWayOut != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: onWayOut, child: RkFitText(wayOut)),
          ),
      ],
    );
  }
}

/// A quiet chip — the offline/saved-on-phone note of 07 §1 rule 7 🔒, which is
/// never a blocking banner. Icon plus words, so the tint is never alone.
class CloseQuietChip extends StatelessWidget {
  /// Creates the chip.
  const CloseQuietChip({super.key, required this.label, required this.icon});

  /// The words.
  final String label;

  /// The glyph beside them.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s1,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s3,
        vertical: RkSpace.s1,
      ),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.md),
        border: Border.all(color: status.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: RkSpace.s4, color: status.muted),
          const SizedBox(width: RkSpace.s2),
          Flexible(
            child: RkFitText(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: status.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A persistent banner (13 §4.2) — read-only here: the state and its reason,
/// with a lock glyph so colour never carries the meaning alone.
class CloseBanner extends StatelessWidget {
  /// Creates the banner.
  const CloseBanner({
    super.key,
    required this.reason,
    this.icon = Icons.lock_outline,
  });

  /// Why, and what the reader may still do (07 §1 rule 6).
  final String reason;

  /// The glyph.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RkSpace.cardPadding),
      decoration: BoxDecoration(
        color: status.sunk,
        border: Border(bottom: BorderSide(color: status.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: RkSpace.s5, color: status.locked),
          const SizedBox(width: RkSpace.s3),
          Expanded(
            child: RkFitText(
              reason,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The wizard's bottom bar: *Back* beside *Next* when both labels fit, stacked
/// when they do not.
///
/// The choice is **font-measured, never a text-scale threshold**. A threshold
/// cannot know how wide a word is in a font it has not measured, and the words
/// here are single Gurmukhi and Devanagari compounds with no break opportunity
/// at all — at 200 % *ਪਿੱਛੇ* needs 160 px and half of a 360 px phone leaves it
/// 137 px, so a side-by-side bar draws it straight past the edge with nothing
/// thrown (07 §1 rule 11, and the `expectTextFits` note in the harness).
///
/// Both buttons are full-width in their half or their row: `rkTheme` gives
/// every filled and outlined button `Size.fromHeight`, an infinite minimum
/// width, so a button here must always be handed a bounded box.
class CloseWizardFooter extends StatelessWidget {
  /// Creates the bar. A null label omits that button.
  const CloseWizardFooter({
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

  /// *Next*, or null at the last step.
  final String? nextLabel;

  /// Steps on.
  final VoidCallback? onNext;

  /// Key of the next button.
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
    return LayoutBuilder(
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
            // Stacked, primary lowest: the bar stays in thumb reach (07 §1
            // rule 2).
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  back,
                  const SizedBox(height: RkSpace.s2),
                  next,
                ],
              );
      },
    );
  }
}
