// The two shapes S12.3, S12.4 and S12.6 share: an action that may be shut
// with the reason written under it, and an inline notice.
//
// 🔒 **Disabled always says why** (07 §1 rule 6, 13 §4.3). A shut door with no
// sentence beside it is the dead end the rule forbids, so [SubscriptionAction]
// cannot be built disabled without a [reason] — the constructor takes the two
// together and the widget draws them together.
//
// 🔒 **Colour is never alone** (07 §1 rule 3). Every [SubscriptionNotice]
// carries an icon and words; the tint only reinforces them.
//
// Everything draws through [RkFitText]: at 200 % on a 360 px phone one
// Gurmukhi or Devanagari word is wider than the button, and a paragraph given
// less width than its longest word draws past the edge without throwing.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';

/// A full-width action, optionally shut with its reason underneath.
class SubscriptionAction extends StatelessWidget {
  /// A live action.
  const SubscriptionAction({
    super.key,
    required this.label,
    required VoidCallback this.onPressed,
    this.emphasis = SubscriptionEmphasis.primary,
  }) : reason = null;

  /// A shut action. [reason] is required: a disabled control that does not say
  /// why is a dead end (07 §1 rule 6 🔒).
  const SubscriptionAction.shut({
    super.key,
    required this.label,
    required String this.reason,
    this.emphasis = SubscriptionEmphasis.primary,
  }) : onPressed = null;

  /// The button's words.
  final String label;

  /// What it does. Null when the action is shut.
  final VoidCallback? onPressed;

  /// Why it is shut, or null when it is live.
  final String? reason;

  /// How loudly it is drawn.
  final SubscriptionEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final child = RkFitText(label, textAlign: TextAlign.center);
    final button = switch (emphasis) {
      SubscriptionEmphasis.primary => FilledButton(
        onPressed: onPressed,
        child: child,
      ),
      SubscriptionEmphasis.secondary => OutlinedButton(
        onPressed: onPressed,
        child: child,
      ),
      // The "quiet Cancel" of DESIGN-PACK §11 (S12.3) 🔒 — a text button,
      // never the page's loudest thing.
      SubscriptionEmphasis.quiet => TextButton(
        onPressed: onPressed,
        child: child,
      ),
    };
    final reason = this.reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: double.infinity, child: button),
        if (reason != null) ...[
          const SizedBox(height: RkSpace.s1),
          SubscriptionReason(reason),
        ],
      ],
    );
  }
}

/// How loudly a [SubscriptionAction] is drawn.
enum SubscriptionEmphasis {
  /// Filled — one per screen.
  primary,

  /// Outlined.
  secondary,

  /// Text only.
  quiet,
}

/// Why something is shut: a clock icon paired with the sentence, so the state
/// never rides on dimming alone (07 §1 rule 3 🔒).
class SubscriptionReason extends StatelessWidget {
  /// Creates the line.
  const SubscriptionReason(this.text, {super.key});

  /// The sentence.
  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.schedule, size: 14, color: status.muted),
            const SizedBox(width: RkSpace.s1),
            Expanded(
              child: RkFitText(
                text,
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

/// What a notice is telling the reader.
enum SubscriptionNoticeKind {
  /// Something went wrong and may be tried again.
  problem,

  /// Something was accepted.
  done,

  /// A plain statement of fact.
  info,
}

/// An inline notice: icon, tint and words together.
class SubscriptionNotice extends StatelessWidget {
  /// Creates the notice.
  const SubscriptionNotice({super.key, required this.text, required this.kind});

  /// The sentence.
  final String text;

  /// Which kind it is.
  final SubscriptionNoticeKind kind;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final (icon, tint) = switch (kind) {
      SubscriptionNoticeKind.problem => (Icons.error_outline, status.warning),
      SubscriptionNoticeKind.done => (
        Icons.check_circle_outline,
        status.success,
      ),
      SubscriptionNoticeKind.info => (Icons.info_outline, status.info),
    };
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: RkIcon.grid, color: tint),
            const SizedBox(width: RkSpace.s2),
            Expanded(
              child: RkFitText(
                text,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
