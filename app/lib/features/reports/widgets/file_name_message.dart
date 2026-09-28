// A sentence that names a file — S8.2's and S4's fallback confirmation
// (*"Saved: day-book-2026-27.pdf"*, `reports.export.saved`) — laid out so the
// name **wraps and is never cut** (ADR 2026-09-24b §10, desk 28a).
//
// 07 §1 rule 6 (name the file) and rule 11 (fit at 200 % on 360×800) both
// hold, and the ruling reconciles them: a file name may break at any
// character. It breaks **preferring** `-`, `/` and `.`, and only a stretch
// that still cannot fit between those is broken at every character. It is
// never ellipsised and never clipped — the reader must be able to read the
// whole name to find the file.
//
// A file name is one unbreakable word to the line breaker (UAX #14 keeps
// `2026-27` and `27.pdf` together), which at 200 % needs more than a snackbar
// has. The break opportunities are zero-width spaces (U+200B) added only when
// the plain sentence does not fit the width it is given, so at ordinary sizes
// the text is byte-for-byte the ARB sentence. Screen readers are handed the
// plain sentence, without them.
import 'package:flutter/widgets.dart';

/// The break opportunity — a zero-width space, drawn as nothing.
const String _zwsp = '​';

/// The characters a file name prefers to break after (ADR 2026-09-24b §10).
const Set<String> _preferred = {'-', '/', '.'};

/// [name] with a break opportunity after each preferred character — the first
/// of the two wrap levels. Pure, so it can be asserted without a layout.
String fileNameBreaksPreferred(String name) {
  final out = StringBuffer();
  final chars = name.characters.toList();
  for (var i = 0; i < chars.length; i++) {
    out.write(chars[i]);
    if (_preferred.contains(chars[i]) && i < chars.length - 1) out.write(_zwsp);
  }
  return out.toString();
}

/// [segment] with a break opportunity between every grapheme — the second
/// level, for a stretch with no preferred character narrow enough. Graphemes,
/// not code units, so a Gurmukhi or Devanagari cluster is never split.
String fileNameBreaksAnywhere(String segment) => segment.characters.join(_zwsp);

/// The two-level wrap of [name] given a width test: preferred breaks first,
/// then every-character breaks inside any segment [fits] still rejects.
String fileNameBreaks(String name, bool Function(String segment) fits) {
  final preferred = fileNameBreaksPreferred(name);
  return [
    for (final segment in preferred.split(_zwsp))
      fits(segment) ? segment : fileNameBreaksAnywhere(segment),
  ].join(_zwsp);
}

/// The style [Text] will actually draw with under [context] — the ambient
/// [DefaultTextStyle], made bold when the OS Bold Text setting is on, with the
/// MediaQuery line-height, letter- and word-spacing overrides applied on top.
///
/// This mirrors `Text.build` (Flutter 3.47, widgets/text.dart): a fit measured
/// in any other style can pass for a piece that is then drawn wider — Mukta's
/// SemiBold face, which bold resolves to, is ~4 % wider than Regular — and be
/// clipped at the line's edge (RPT2 review, finding 1).
TextStyle _drawnStyle(BuildContext context) {
  var style = DefaultTextStyle.of(context).style;
  if (MediaQuery.boldTextOf(context)) {
    style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  final height = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
  final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
  if (height != null || letterSpacing != null || wordSpacing != null) {
    style = style.merge(
      TextStyle(
        height: height,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
      ),
    );
  }
  return style;
}

/// A one-sentence message naming [fileName], built by [sentence] (the ARB
/// string with the name as its placeholder), which wraps and never cuts the
/// name at any text scale.
class FileNameMessage extends StatelessWidget {
  /// Creates the message.
  const FileNameMessage({
    super.key,
    required this.fileName,
    required this.sentence,
  });

  /// The file name or path, exactly as the sink reported it.
  final String fileName;

  /// The localized sentence around it — e.g. `l10n.reportsExportSaved`.
  final String Function(String fileName) sentence;

  @override
  Widget build(BuildContext context) {
    final plain = sentence(fileName);
    // Measured in the style the Text below is drawn in, not the ambient one.
    final style = _drawnStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        /// Whether [text]'s longest unbreakable run fits the line.
        bool fits(String text) {
          if (!width.isFinite) return true;
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: scaler,
            locale: locale,
          )..layout();
          final longest = painter.minIntrinsicWidth;
          painter.dispose();
          return longest <= width;
        }

        final shown = fits(plain)
            ? plain
            : sentence(fileNameBreaks(fileName, fits));
        return Text(
          shown,
          semanticsLabel: plain,
          // Wrap, never ellipsise (ADR 2026-09-24b §10): no maxLines, and the
          // default clip overflow left in place so a run that did not fit
          // would still be measured as cut by the F1 fit check, not hidden.
          softWrap: true,
        );
      },
    );
  }
}
