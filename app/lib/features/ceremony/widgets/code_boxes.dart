// The eight character boxes (07 §12 🔒 owner-approved) and the expiry
// countdown that sits with them.
//
// Presentation only. The digits arrive already derived from the key
// fingerprint and the invite nonce (04 §6.1) — this file never computes one,
// and there is no share or copy affordance anywhere on it (04 §6.4 🔒: the
// code must travel over a channel where the verifier recognises the person).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// How many boxes there are. Eight, per 04 §6.1.
const int ceremonyCodeLength = 8;

/// `4 min 12 s` · `40 s` — Latin digits, tabular figures.
String formatCodeExpiry(AppLocalizations l10n, Duration left) {
  final clamped = left.isNegative ? Duration.zero : left;
  if (clamped.inMinutes >= 1) {
    return l10n.ceremonyShowTimeMinutesSeconds(
      clamped.inMinutes,
      clamped.inSeconds % 60,
    );
  }
  return l10n.ceremonyShowTimeSeconds(clamped.inSeconds);
}

/// Eight boxes, one character each.
///
/// **Layout.** Eight boxes across a 360 px phone stop fitting long before
/// 200 % text scale, so the row is measured rather than assumed: the box is
/// sized from the *font-measured* width of a digit at the live scale (the
/// same reasoning as the harness's `expectTextFits` — a scale threshold
/// cannot know how wide a glyph is), and when eight will not fit the code
/// breaks into two rows of four. Four-and-four is also how a person reads
/// eight digits aloud, so the wrap is not a concession.
class RkCodeBoxes extends StatelessWidget {
  /// Renders [digits] (up to [ceremonyCodeLength]); shorter input leaves the
  /// remaining boxes empty, which is how the entry field on S9.3 fills up.
  const RkCodeBoxes({
    super.key,
    required this.digits,
    this.semanticsLabel,
    this.muted = false,
  });

  /// The characters to show.
  final String digits;

  /// What a screen reader hears instead of eight separate boxes. Null where
  /// something above already names the code — the entry field on S9.3 does.
  final String? semanticsLabel;

  /// Greys the code out — the expired state (04 §6.3).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final style = (theme.textTheme.headlineSmall ?? RkType.section).copyWith(
      fontFeatures: RkType.tabular,
      color: muted ? status.locked : theme.colorScheme.onSurface,
    );

    // Font-measured, not guessed: a Gurmukhi or Devanagari digit is not the
    // width of a Latin one, and at 200 % neither is the width this code was
    // written against.
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final glyph = Size(painter.width, painter.height);
    painter.dispose();

    final boxWidth = (glyph.width + RkSpace.s4).clamp(44.0, double.infinity);
    final boxHeight = (glyph.height + RkSpace.s4).clamp(44.0, double.infinity);

    final boxes = LayoutBuilder(
      builder: (context, constraints) {
        const gap = RkSpace.s2;
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : boxWidth * ceremonyCodeLength;
        final perRow =
            boxWidth * ceremonyCodeLength + gap * (ceremonyCodeLength - 1) <=
                available
            ? ceremonyCodeLength
            : ceremonyCodeLength ~/ 2;
        // Never wider than the share we actually have: one character has no
        // break opportunity, so an over-wide box is a silently cut glyph.
        final width = ((available - gap * (perRow - 1)) / perRow).clamp(
          0.0,
          boxWidth,
        );
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < ceremonyCodeLength; i++)
              _Box(
                width: width,
                height: boxHeight,
                style: style,
                character: i < digits.length ? digits[i] : '',
              ),
          ],
        );
      },
    );
    return semanticsLabel == null
        ? ExcludeSemantics(child: boxes)
        : Semantics(
            label: semanticsLabel,
            excludeSemantics: true,
            child: boxes,
          );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.width,
    required this.height,
    required this.style,
    required this.character,
  });

  final double width;
  final double height;
  final TextStyle style;
  final String character;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: height),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.sm),
        border: Border.all(color: status.hairline),
      ),
      child: Text(character, style: style, textAlign: TextAlign.center),
    );
  }
}

/// The visible expiry countdown (07 §12 🔒) — a clock icon and a word beside
/// the time, never colour alone (07 §1 rule 3).
class RkCodeExpiry extends StatelessWidget {
  /// Shows [left]; at zero it reads as expired.
  const RkCodeExpiry({super.key, required this.left});

  /// Time remaining on the nonce.
  final Duration left;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final expired = left <= Duration.zero;
    final label = expired
        ? l10n.ceremonyShowExpired
        : l10n.ceremonyShowExpiresIn(formatCodeExpiry(l10n, left));
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            expired ? Icons.timer_off_outlined : Icons.schedule,
            size: RkIcon.grid,
            color: expired ? status.warning : status.muted,
          ),
          const SizedBox(width: RkSpace.s2),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: RkType.tabular,
                color: expired ? status.warning : status.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The code-entry field of S9.3: the same eight boxes, filled by the keyboard.
///
/// It is a real text field underneath — a screen reader, a Bluetooth keyboard
/// and voice control all work on it, which eight tap targets would not give.
class RkCodeField extends StatelessWidget {
  /// Wires [controller] to the boxes; [onSubmitted] fires on the keyboard's
  /// done key and [enabled] false is the disabled-with-reason state.
  const RkCodeField({
    super.key,
    required this.controller,
    required this.label,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
  });

  /// Holds the typed digits.
  final TextEditingController controller;

  /// Accessible name of the field.
  final String label;

  /// Called with the digits when the user commits.
  final ValueChanged<String>? onSubmitted;

  /// False greys the boxes and refuses input.
  final bool enabled;

  /// Whether to open the keyboard on arrival.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) =>
              RkCodeBoxes(digits: value.text, muted: !enabled),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              enabled: enabled,
              autofocus: autofocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: ceremonyCodeLength,
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(height: 0.01),
              decoration: InputDecoration(
                counterText: '',
                border: InputBorder.none,
                labelText: label,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(ceremonyCodeLength),
              ],
              onSubmitted: onSubmitted,
            ),
          ),
        ),
      ],
    );
  }
}
