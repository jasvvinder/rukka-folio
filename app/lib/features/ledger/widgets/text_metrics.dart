// Measuring, not guessing: how much room a string actually needs on *this*
// screen, at *this* reader's text scale, in *this* script.
//
// A layout that picks its columns from a text-scale threshold is a layout
// that has never measured the word it is about to cut (U3g, S8.2: green at
// 200 %, 88 px of overflow at 1.3). A tabular figure may never be shrunk to
// fit (07 §1), and a person's account name may not be shortened at all, so
// the only honest way to decide between a grid and a folded row is to measure
// both and take the one that holds.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';

/// The width one line of [text] needs, unwrapped, in [style].
double textRunWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The width of the longest *unbreakable* word in [text].
///
/// Wrapping text needs this much or it is cut: given less room than one word,
/// a paragraph lays that word out at the box width and draws the rest past
/// the edge, throwing nothing (see `expectTextFits`).
double longestWordWidth(BuildContext context, String text, TextStyle? style) {
  var widest = 0.0;
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final w = textRunWidth(context, word, style);
    if (w > widest) widest = w;
  }
  return widest;
}

/// The exact string [MoneyText] draws for [paise] under
/// [Vocabulary.professional] — the figure, and the Dr/Cr word when
/// [withSide]. Measuring anything else would measure the wrong thing.
String professionalFigure(
  BuildContext context,
  int paise, {
  bool withSide = true,
  bool showPaise = false,
}) {
  final locale = Localizations.localeOf(context);
  final numerals = formatPaise(
    paise.abs(),
    locale: locale,
    showPaise: showPaise,
  );
  final side = withSide
      ? directionLabel(
          AppLocalizations.of(context),
          Vocabulary.professional,
          paise,
        )
      : null;
  return side == null ? numerals : '$numerals $side';
}
