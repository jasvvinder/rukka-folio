// The export pair every report surface wears in its app bar (ADR 2026-09-12e
// §2 🔒: the trio *View · Download/Share · Export (PDF/CSV/XLSX)* is binding on
// S4 as well as S8.2 — owner-confirmed 13 Sep). **View** is the screen itself;
// these two are the other two thirds.
//
// Extracted from S8.2 when the statement gained the same bar: two surfaces with
// two copies of a layout this delicate is two chances for one of them to spill
// at 200 % in Punjabi, which is exactly the defect the second rule below was
// written for.
//
//  1. **Only the primary action is ever labelled.** Above 1.3x the pair is two
//     [IconButton]s, 48 logical px each and independent of text scale, and the
//     [AppBar] title ellipsises rather than fighting them for the line. Giving
//     the chooser a label too would break that, which is why it has none.
//  2. **The labelled form is capped and clips.** A scale threshold alone was
//     never enough: at 1.3x the Punjabi label alone overflowed a 360 px bar,
//     and no test caught it because only 200 % — where the label is already
//     gone — was being asserted. A threshold cannot know how wide a word is in
//     a font it has not measured, so the words are held to
//     [reportActionLabelShare] of the bar and clipped past it. The cap never
//     bites at the real label widths; it is the guarantee that a longer
//     translation, or a wider fallback font, cannot spill the bar.
//
// Both carry their words as a tooltip and a screen-reader label, so neither
// affordance is ever carried by a glyph alone (07 §1 rule 3).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/tokens.dart';

/// Share of the bar the labelled primary action may occupy before its words
/// are clipped. The pair is this plus one 48 px icon button, so the title
/// keeps a little over a third of the line at every width and in every
/// language. A fraction, not a token: this is the report bar's own budget, and
/// the two actions only have to agree with each other.
const double reportActionLabelShare = 0.5;

/// Text scale past which the labelled form gives way to an icon.
const double reportActionLabelMaxScale = 1.3;

/// **Download / Share** — the primary action (ADR 2026-09-12 §1 🔒, default
/// restored by 12d §2 🔒). It writes the PDF and hands it to the platform share
/// sheet; it does not open a sheet of formats.
class ReportExportAction extends StatelessWidget {
  /// Creates the action.
  const ReportExportAction({super.key, required this.onPressed});

  /// Runs the default export.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (MediaQuery.textScalerOf(context).scale(1) > reportActionLabelMaxScale) {
      return IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.ios_share),
        tooltip: l10n.reportsViewerExport,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: RkSpace.s2),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * reportActionLabelShare,
        ),
        // Hand-built rather than `TextButton.icon`, so the label is the piece
        // that gives when the cap bites — and it keeps the tooltip, so the
        // full words reach a screen reader and a long-press even clipped.
        child: Tooltip(
          message: l10n.reportsViewerExport,
          child: TextButton(
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.ios_share),
                const SizedBox(width: RkSpace.s1),
                Flexible(
                  child: Text(
                    l10n.reportsViewerExport,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// **Export** — the door to the three-format sheet (ADR 2026-09-12c §1 🔒:
/// *"the format sheet stays reachable from the viewer so a person can still
/// choose a format rather than accept the default"*). Without it the default
/// would be the only path and the other two formats would vanish from the
/// product — the enumeration is 🔒, and a format you cannot even see named is a
/// dead end (07 §1 rules 2 and 6).
class ReportChooseFormatAction extends StatelessWidget {
  /// Creates the action.
  const ReportChooseFormatAction({super.key, required this.onPressed});

  /// Opens the format sheet.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.more_horiz),
      tooltip: l10n.reportsViewerExportFormats,
    );
  }
}
