// The parts the three activation screens share (13 §4.1–§4.3).
//
// Tokens only — a hex literal here is review-blocking (CLAUDE.md, purity
// check). Colour is never alone (07 §1 rule 3 🔒): every tinted thing on
// these screens is paired with an icon *and* a word, because the person
// reading them may be anxious, at a shop counter, in bright sun.
//
// Nothing in this file can render key material: the widgets take strings the
// screen read out of ARB and integers the seam counted, and the seam carries
// no bytes (04 §7.4, 07 §5.6 🔒).
import 'package:flutter/material.dart';

import '../../../shared/seams/recovery_ladder.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';

/// The determinate loader **rule** (11 §4.5 🔒, DESIGN-PACK loader-rule
/// paragraph): a 2 px `loader-track` with a `loader-segment`, a count beneath
/// it, and never a spinner and never a percentage.
///
/// [value] is always supplied, so this can never render as an indeterminate
/// sweep by accident — [RecoveryProgress.fraction] answers 0 rather than null
/// while the total is unknown.
class RecoveryLoaderRule extends StatelessWidget {
  /// Creates the rule.
  const RecoveryLoaderRule({
    super.key,
    required this.value,
    this.countText,
    required this.semanticsLabel,
  });

  /// 0..1.
  final double value;

  /// *"{done} of {total} books restored"* — a count, never a percentage.
  ///
  /// Null before the first reading arrives: there is no honest count to draw
  /// yet, and a `0 of 0` would be a figure the screen invented. The caller's
  /// heading carries the verb meanwhile (11 §4.5: an indeterminate moment
  /// always carries a verb).
  final String? countText;

  /// What a screen reader announces, so the grey rule is never the only
  /// carrier of the state.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: semanticsLabel,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RkRadius.sm),
            child: LinearProgressIndicator(
              value: value,
              minHeight: RkMotion.loaderTrackHeight,
              backgroundColor: status.loaderTrack,
              color: status.loaderSegment,
            ),
          ),
          if (countText != null) ...[
            const SizedBox(height: RkSpace.s3),
            RkFitText(
              countText!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// One full-width way back in, on S11.6 (design R2.1).
///
/// Two states and no third: live, or **disabled-with-reason** (13 §4.3). A
/// rung is never hidden — a row that vanishes teaches the reader that their
/// books are unreachable, which is false, and 07 §1 rule 6 forbids the dead
/// end that would follow.
class RecoveryRungRow extends StatelessWidget {
  /// Creates the row.
  const RecoveryRungRow({
    super.key,
    required this.rung,
    required this.title,
    required this.body,
    this.subLine,
    this.note,
    this.reason,
    this.onTap,
  });

  /// Which rung this row offers — the screen's order is asserted off this.
  final RecoveryRung rung;

  /// The way in, in the user's words.
  final String title;

  /// Its one-line explanation.
  final String body;

  /// The sheet row's *paper or the file you saved*.
  final String? subLine;

  /// An extra true line, e.g. 06 §5's *link instead*.
  final String? note;

  /// Why this row cannot be taken; null when it can.
  final String? reason;

  /// Taken when the row is live.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final blocked = reason != null;
    final titleColor = blocked ? status.locked : scheme.onSurface;

    return Semantics(
      button: !blocked,
      enabled: !blocked,
      // The reason travels with the control, so a screen reader hears *why*
      // and not merely "dimmed".
      hint: reason,
      child: InkWell(
        // A blocked row is inert rather than absent: no callback, no ripple.
        onTap: blocked ? null : onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s4,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RkFitText(
                      title,
                      style: text.titleMedium?.copyWith(color: titleColor),
                    ),
                    const SizedBox(height: RkSpace.s1),
                    RkFitText(
                      body,
                      style: text.bodyMedium?.copyWith(
                        color: blocked ? status.locked : status.muted,
                      ),
                    ),
                    if (subLine != null) ...[
                      const SizedBox(height: RkSpace.s1),
                      RkFitText(
                        subLine!,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                    ],
                    if (note != null) ...[
                      const SizedBox(height: RkSpace.s2),
                      _IconLine(
                        icon: Icons.phone_iphone,
                        text: note!,
                        color: status.info,
                      ),
                    ],
                    if (blocked) ...[
                      const SizedBox(height: RkSpace.s2),
                      // Icon + word + tint, in that order of load-bearing:
                      // the lock and the sentence say it, the grey only
                      // reinforces it (07 §1 rule 3).
                      _IconLine(
                        icon: Icons.lock_outline,
                        text: reason!,
                        color: status.locked,
                      ),
                    ],
                  ],
                ),
              ),
              if (!blocked) ...[
                const SizedBox(width: RkSpace.s3),
                Icon(Icons.chevron_right, color: status.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One bordered row of S11.8 (design R2.5 🔒): a left rule in its tone, a
/// status **word** beside an icon, the heading, the body, and — on the one
/// row the pack says carries it — the screen's single primary button.
class RecoveryStatusCard extends StatelessWidget {
  /// Creates the card.
  const RecoveryStatusCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.status,
    required this.title,
    required this.body,
    this.extra = const <Widget>[],
    this.action,
    this.onAction,
  });

  /// The rule colour: success · pending · muted, per the pack's green / amber
  /// / grey.
  final Color tone;

  /// The icon that carries the state beside the word.
  final IconData icon;

  /// The state as a **word** — colour is never alone (07 §1 rule 3).
  final String status;

  /// What this row is about.
  final String title;

  /// The honest sentence.
  final String body;

  /// Further lines (the private book's two keys).
  final List<Widget> extra;

  /// The primary button's label, on the one row that carries it.
  final String? action;

  /// Taken when that button is pressed.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RkRuledCard(
      ruleColor: tone,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconLine(icon: icon, text: status, color: tone),
            const SizedBox(height: RkSpace.s2),
            RkFitText(title, style: text.titleMedium),
            const SizedBox(height: RkSpace.s1),
            RkFitText(body, style: text.bodyMedium),
            ...extra,
            if (action != null) ...[
              const SizedBox(height: RkSpace.s4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAction,
                  child: RkFitText(action!, textAlign: TextAlign.center),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An icon and a line of text in one tint — the shape every coloured thing on
/// these screens takes, so no tint is ever the sole carrier of meaning.
class _IconLine extends StatelessWidget {
  const _IconLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: RkIcon.grid - RkSpace.s2, color: color),
      const SizedBox(width: RkSpace.s2),
      Expanded(
        child: RkFitText(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ),
    ],
  );
}

/// The short inline rule a *waiting* row carries on S11.2 (design R2.2:
/// "a short inline **loader rule** — 2 px hairline + ink segment, 11 §4.5;
/// **never a spinner**").
///
/// It is drawn **static**: a 2 px `loader-track` carrying a `loader-segment`
/// at the token's own 30 % of the track. Two reasons, and neither is
/// convenience. 11 §4.5 🔒 makes the static hairline plus the words the
/// reduced-motion form and says "the words do the work" — here the row's own
/// *Waiting…* is that word. And an endlessly sweeping indicator is a widget
/// that never settles, which is the shape of a screen that "feels stuck" —
/// the one thing R2.2 says this screen must not do. The sweep belongs to the
/// motion pass, behind the platform's reduced-motion query.
class RecoveryInlineRule extends StatelessWidget {
  /// Creates the rule.
  const RecoveryInlineRule({super.key, this.width = RkSpace.s12});

  /// How long the hairline is.
  final double width;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return SizedBox(
      width: width,
      height: RkMotion.loaderTrackHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RkRadius.sm),
        child: ColoredBox(
          color: status.loaderTrack,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            // The token's own proportion: `loader-segment` is 30 % of track.
            widthFactor: 0.3,
            child: ColoredBox(color: status.loaderSegment),
          ),
        ),
      ),
    );
  }
}

/// One trusted member on S11.2 (design R2.2): initials, name, a state that is
/// always an **icon plus a word** (07 §1 rule 3 🔒 — colour is never alone),
/// and, where the book holds a number, the pack's small *Call* link.
class TrustedApproverRow extends StatelessWidget {
  /// Creates the row.
  const TrustedApproverRow({
    super.key,
    required this.approver,
    required this.stateText,
    required this.waitingLabel,
    required this.callLabel,
    this.onCall,
  });

  /// The member and where they stand.
  final TrustedApprover approver;

  /// Their state, as the word the screen read out of ARB.
  final String stateText;

  /// What a screen reader hears for a waiting row's rule.
  final String waitingLabel;

  /// The *Call* link's label.
  final String callLabel;

  /// Taken with the member's number. Null when nothing on this build can
  /// dial — the number is then simply shown, so the advice still works.
  final void Function(TrustedApprover approver)? onCall;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, tone) = switch (approver.state) {
      TrustedApproverState.approved => (
        Icons.check_circle_outline,
        status.success,
      ),
      TrustedApproverState.waiting => (Icons.hourglass_empty, status.muted),
      TrustedApproverState.notAsked => (
        Icons.radio_button_unchecked,
        status.muted,
      ),
      TrustedApproverState.declined => (
        Icons.do_not_disturb_on_outlined,
        status.locked,
      ),
    };
    final waiting = approver.state == TrustedApproverState.waiting;
    final phone = approver.phone;

    return Semantics(
      container: true,
      label: waiting ? waitingLabel : '${approver.name}, $stateText',
      child: Container(
        constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s3,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: status.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No photograph pipeline exists in the app, so the avatar is the
            // member's initial over the sunk surface — a placeholder that is
            // honest rather than a broken image.
            Container(
              width: RkIcon.grid + RkSpace.s2,
              height: RkIcon.grid + RkSpace.s2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: status.sunk,
                shape: BoxShape.circle,
              ),
              child: Text(
                approver.name.isEmpty ? '' : approver.name.characters.first,
                style: text.titleSmall?.copyWith(color: scheme.onSurface),
              ),
            ),
            const SizedBox(width: RkSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RkFitText(approver.name, style: text.titleMedium),
                  const SizedBox(height: RkSpace.s1),
                  Row(
                    children: [
                      Icon(icon, size: RkIcon.grid - RkSpace.s2, color: tone),
                      const SizedBox(width: RkSpace.s2),
                      Flexible(
                        child: RkFitText(
                          stateText,
                          style: text.bodySmall?.copyWith(color: tone),
                        ),
                      ),
                      if (waiting) ...[
                        const SizedBox(width: RkSpace.s3),
                        const RecoveryInlineRule(),
                      ],
                    ],
                  ),
                  if (waiting && phone != null) ...[
                    const SizedBox(height: RkSpace.s1),
                    if (onCall == null)
                      // Nothing here can place a call, so the number itself is
                      // shown — the advice ("phone them") still works, and no
                      // control is drawn that would do nothing (07 §1 rule 6).
                      Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: RkIcon.grid - RkSpace.s2,
                            color: status.muted,
                          ),
                          const SizedBox(width: RkSpace.s2),
                          Flexible(
                            child: RkFitText(
                              phone,
                              style: text.bodySmall?.copyWith(
                                color: status.muted,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      TextButton(
                        onPressed: () => onCall!(approver),
                        child: RkFitText('$callLabel · $phone'),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The caution S11.7 cannot be used around (design R2.3 🔒).
///
/// A bordered field in the `warning` tone carrying an icon, the caution, its
/// body, and the acknowledgement that has to be ticked before Approve comes
/// alive. It is drawn **above** the buttons and is never collapsible: this is
/// a security decision taken by a relative, and the pack's instruction is
/// that the caution must be impossible to skip past.
class RecoveryCautionCard extends StatelessWidget {
  /// Creates the caution.
  const RecoveryCautionCard({
    super.key,
    required this.title,
    required this.body,
    required this.ackLabel,
    required this.acknowledged,
    required this.onAcknowledged,
    this.callLabel,
    this.onCall,
  });

  /// The caution itself (design R2.3, verbatim).
  final String title;

  /// Why it matters, in one plain line.
  final String body;

  /// The acknowledgement's label.
  final String ackLabel;

  /// Whether it has been ticked.
  final bool acknowledged;

  /// Takes the new value.
  final ValueChanged<bool> onAcknowledged;

  /// The *Call {name}* label, when a number exists.
  final String? callLabel;

  /// Places the call.
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return RkRuledCard(
      ruleColor: status.warning,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconLine(
              icon: Icons.warning_amber_outlined,
              text: title,
              color: status.warning,
            ),
            const SizedBox(height: RkSpace.s2),
            RkFitText(body, style: text.bodyMedium),
            if (callLabel != null && onCall != null) ...[
              const SizedBox(height: RkSpace.s2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.phone_outlined),
                  label: RkFitText(callLabel!),
                ),
              ),
            ],
            const SizedBox(height: RkSpace.s2),
            // A checkbox, not a dismissible warning: ADR 2026-09-06
            // checklist 4 🔒 sets that precedent for the other irreversible
            // choice in this feature, and the same reasoning holds here.
            InkWell(
              onTap: () => onAcknowledged(!acknowledged),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: acknowledged,
                      onChanged: (v) => onAcknowledged(v ?? false),
                    ),
                    const SizedBox(width: RkSpace.s1),
                    Expanded(
                      child: RkFitText(ackLabel, style: text.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The new device's fingerprint on S11.7 (04 §7.3 step 2 🔒).
///
/// Small, wide-tracked and in **tabular figures** so the two people can read
/// it to each other character by character without losing their place. Mukta
/// carries `tnum` (11 §4.4), so no second font family is needed — and none is
/// added, because a font is a bundle decision, not a screen's.
class RecoveryFingerprint extends StatelessWidget {
  /// Creates the block.
  const RecoveryFingerprint({
    super.key,
    required this.label,
    required this.value,
  });

  /// What sits above it.
  final String label;

  /// The fingerprint, already grouped by whoever produced it.
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RkFitText(label, style: text.bodySmall?.copyWith(color: status.muted)),
        const SizedBox(height: RkSpace.s1),
        // Read aloud character by character, so it is announced as it looks.
        Semantics(
          label: value.split('').join(' '),
          excludeSemantics: true,
          child: RkFitText(
            value,
            style: text.bodyMedium?.copyWith(
              fontFeatures: RkType.tabular,
              letterSpacing: RkSpace.s1 / 2,
            ),
          ),
        ),
      ],
    );
  }
}
