// The component system's text atom (13 §4: one component, one definition).
// Tokens only — a hex literal here is review-blocking (CLAUDE.md,
// design-system).
//
// Three lanes each shipped a copy of this widget (`RkFitText` in
// `features/home`, `CountFitText` in `features/cash_count`, `CloseFitText` in
// `features/close`) because no lane owned a shared folder. This is the one
// definition; the copies import it.
import 'package:flutter/material.dart';

/// Text that never draws a word past the edge of its box (13 §4, 07 §1
/// rule 11).
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
/// fits is drawn at exactly the size the reader asked for.
class RkFitText extends StatelessWidget {
  /// Creates the text.
  const RkFitText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  /// The string to draw.
  final String data;

  /// Style, merged onto the inherited one exactly as [Text] merges it.
  final TextStyle? style;

  /// Alignment for the text run.
  final TextAlign? textAlign;

  /// Line cap, when the caller wants one.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final asked = MediaQuery.textScalerOf(context);
        var scaler = asked;
        final room = constraints.maxWidth;
        if (room.isFinite && room > 1) {
          final direction = Directionality.of(context);
          final locale = Localizations.maybeLocaleOf(context);
          double widestAt(TextScaler at) {
            final painter = TextPainter(
              text: TextSpan(text: data, style: resolved),
              textScaler: at,
              textDirection: direction,
              locale: locale,
            )..layout();
            final w = painter.minIntrinsicWidth;
            painter.dispose();
            return w;
          }

          // Measure, step down, then **measure again**. One division is not
          // enough: a glyph advance is rounded per glyph, so a word of a
          // dozen letters can still need a few pixels more than the linear
          // arithmetic predicted, and a box tight enough to matter is exactly
          // where the last digits go over the edge. The loop only ever
          // shrinks further — text that already fits is never touched, and it
          // is bounded, so a font that refuses to get smaller cannot hang a
          // frame.
          var widest = widestAt(asked);
          for (var pass = 0; pass < 4 && widest > room; pass++) {
            // A pixel of slack: landing exactly on the boundary still clips.
            scaler = TextScaler.linear(scaler.scale(1) * (room - 1) / widest);
            widest = widestAt(scaler);
          }
        }
        return Text(
          data,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          textScaler: scaler,
        );
      },
    );
  }
}
