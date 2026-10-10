// A line of copy whose ✓ is drawn as an icon (PLAN desk 193 (e)).
//
// `entry.saved` reads `Saved ✓ (on phone)` — 07 §5 step 6 🔒 quotes that
// exact string, so the ARB copy keeps its ✓ in every language. U+2713 is in
// none of Mukta / Mukta Mahee / Noto Sans (11 §4.4 owns the font set), so as
// text it draws in a system face on a phone and as a box in the capture.
// This widget keeps the copy as written and swaps each ✓ for the design
// system's check icon at the text's own size and ink.
import 'package:flutter/material.dart';

/// The tick as the copy spells it.
const String entryTick = '✓';

/// The icon drawn in its place.
const IconData entryTickIcon = Icons.check;

/// [text] with every [entryTick] drawn as [entryTickIcon].
class EntryTickText extends StatelessWidget {
  /// Creates the line.
  const EntryTickText(this.text, {super.key, this.style});

  /// The copy, ✓ and all.
  final String text;

  /// Style over the ambient one (a SnackBar's content style, by default).
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final size = MediaQuery.textScalerOf(context)
        .scale(effective.fontSize ?? 14);
    final parts = text.split(entryTick);
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(entryTickIcon, size: size, color: effective.color),
              ),
            if (parts[i].isNotEmpty) TextSpan(text: parts[i]),
          ],
        ],
      ),
      style: style,
      // Read aloud without the glyph; the icon says nothing a word does not.
      semanticsLabel: text
          .replaceAll(entryTick, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }
}
