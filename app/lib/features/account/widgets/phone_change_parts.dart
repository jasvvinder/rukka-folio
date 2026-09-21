// The parts S16.2 is drawn from (13 §4.1–§4.3, 07 §1 🔒).
//
// Tokens only — a hex literal here is review-blocking. Colour is never alone
// (07 §1 rule 3 🔒): every tinted thing carries an icon *and* a word, because
// the person reading this screen has usually just lost a phone number and is
// on a call to a relative.
//
// Nothing here can render key material. A phone-number change touches no key
// (06 §9.4 🔒), and the seam carries none, so these widgets take a name, a
// number, a count and an enum and nothing else.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../phone_change.dart';

/// The determinate loader **rule** (11 §4.5 🔒; ADR 2026-09-05f §6 names S16.2
/// among the surfaces that draw it with `loader-track` / `loader-segment`):
/// a 2 px track with a segment, a **count** beneath it, never a spinner and
/// never a percentage.
///
/// [value] is always supplied, so this can never degrade into an
/// indeterminate sweep by accident.
class PhoneChangeRule extends StatelessWidget {
  /// Creates the rule.
  const PhoneChangeRule({
    super.key,
    required this.value,
    required this.countText,
    required this.semanticsLabel,
  });

  /// 0..1.
  final double value;

  /// *"1 of 2 said yes"* — a count, never a percentage.
  final String countText;

  /// What a screen reader announces, so the grey rule is never the only
  /// carrier of the state.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: semanticsLabel,
      liveRegion: true,
      child: ExcludeSemantics(
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
            const SizedBox(height: RkSpace.s3),
            RkFitText(
              countText,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two ways of proving the old number (06 §9.4 🔒).
///
/// Two states and no third: live, or **disabled-with-reason** (13 §4.3). The
/// lost-number route is never hidden for want of trusted members — a row that
/// vanishes teaches the reader that a lost number cannot be changed, which is
/// exactly the false lesson 07 §1 rule 6 forbids. The reason travels with a
/// way to fix it.
class PhoneChangeRouteCard extends StatelessWidget {
  /// Creates the card.
  const PhoneChangeRouteCard({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.reason,
    this.fixLabel,
    this.onFix,
    this.onTap,
  });

  /// The glyph beside the title — meaning never rides on tint alone.
  final IconData icon;

  /// The route, in the user's words.
  final String title;

  /// Its one-line explanation.
  final String? body;

  /// Why this route cannot be taken; null when it can.
  final String? reason;

  /// Label of the control that makes [reason] go away.
  final String? fixLabel;

  /// Taken to fix the reason (→ S11.1 Trusted members).
  final VoidCallback? onFix;

  /// Taken when the route is live.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final live = reason == null && onTap != null;
    final ink = live ? scheme.onSurface : status.muted;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.cardPadding,
        vertical: RkSpace.s4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 22, color: ink),
          ),
          const SizedBox(width: RkSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RkFitText(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (body != null)
                  Padding(
                    padding: const EdgeInsets.only(top: RkSpace.s1),
                    child: Text(
                      body!,
                      style: text.bodyMedium?.copyWith(color: status.muted),
                    ),
                  ),
                if (reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: RkSpace.s2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 14, color: status.muted),
                        const SizedBox(width: RkSpace.s1),
                        Expanded(
                          child: Text(
                            reason!,
                            style: text.bodySmall?.copyWith(
                              color: status.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (reason != null && fixLabel != null && onFix != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(onPressed: onFix, child: Text(fixLabel!)),
                  ),
              ],
            ),
          ),
          if (live) Icon(Icons.chevron_right, size: 22, color: status.muted),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      decoration: BoxDecoration(
        color: live ? scheme.surface : status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.lg),
        border: Border.all(color: status.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: live
          ? InkWell(onTap: onTap, child: content)
          : Semantics(enabled: false, child: content),
    );
  }
}

/// One trusted member on the waiting surface.
///
/// The row says **where that person stands, by name**, because an ask that may
/// be open for days must never feel stuck — the same reason S11.2 draws its
/// rows this way. The state is a word *and* a glyph; the tint is the third
/// carrier, never the first (07 §1 rule 3 🔒).
class TrustedMemberRow extends StatelessWidget {
  /// Creates the row.
  const TrustedMemberRow({
    super.key,
    required this.approver,
    required this.stateLabel,
    this.callLabel,
    this.onCall,
  });

  /// Who, and where they stand.
  final TrustedApprover approver;

  /// [TrustedApproverState] in the user's words.
  final String stateLabel;

  /// *Call {name}* — drawn only where the book holds a number **and** this
  /// build can dial. Where it cannot, the row shows nothing rather than a
  /// control that would do nothing.
  final String? callLabel;

  /// Places the call.
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    // The same four glyphs S11.2 draws (`recovery_parts.TrustedApproverRow`).
    // One act, one vocabulary — down to the icon, because a reader who has
    // seen the recovery screen should recognise this one.
    final (icon, tint) = switch (approver.state) {
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
    // `container`, not `ExcludeSemantics`: the row's label carries the name
    // and the state, and the *Call* button stays reachable underneath it —
    // the bare word "Call" is the pack's, and the container is what stops it
    // being ambiguous.
    return Semantics(
      container: true,
      label: '${approver.name}, $stateLabel',
      child: Container(
        constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: RkSpace.s3),
            // Name, state and *Call* all stack in one column rather than
            // competing for one row's width. At 200 % on a 360 px phone a
            // trailing button squeezes the state label to a few pixels and
            // Flutter draws the overflow past the edge without throwing —
            // a green test over a row nobody can read (07 §1 rule 11 🔒).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RkFitText(approver.name, style: text.bodyLarge),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      stateLabel,
                      style: text.bodySmall?.copyWith(color: status.muted),
                    ),
                  ),
                  if (callLabel != null && onCall != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: onCall,
                        child: Text(callLabel!),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quiet one-line chip S16.2 uses for offline and for a refresh that
/// failed over a screen that is still perfectly readable — never a blocking
/// banner (07 §1 rule 7 🔒).
class PhoneChangeChip extends StatelessWidget {
  /// Creates the chip.
  const PhoneChangeChip({
    super.key,
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  /// The glyph — the meaning's first carrier.
  final IconData icon;

  /// The fact, in one line.
  final String text;

  /// An optional way forward.
  final String? action;

  /// Takes it.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s3,
        RkSpace.gutter,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: status.muted),
          ),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(text, style: style?.copyWith(color: status.muted)),
          ),
          if (action != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}
