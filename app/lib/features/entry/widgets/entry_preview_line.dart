// The live entry preview (07 §5 step 5.5 🔒, 01 §2.1 🔒). One line above Save
// that **builds in real time** as the entry is filled:
//
//   `{amt} · {credited_account} → {debited_account} · {note}`
//
// One template, all languages — the arrow carries the flow, so there is no
// postposition and no per-language word order (01 §2.1 🔒).
//
// Three 🔒 rules shape the widget:
//   • it reserves its full height from the first frame, so nothing below it
//     shifts as slots fill (this screen must not scroll);
//   • empty slots are dotted placeholders, never blank space — the line reads
//     as a sentence with gaps, which says what is missing without an error;
//   • completion is the validation: the line moves muted → full ink at the
//     same moment Save turns solid. No "please choose an account" ever shows.
//
// Read-only: nothing inside it is tappable (design canvas 2 row 2).
import 'package:flutter/material.dart';

import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// The dotted placeholder that stands in for an empty slot (07 §5.5 🔒).
const String previewGap = '⋯';

/// The arrow between the credited and the debited account (01 §2.1).
const String previewArrow = '→';

/// Lines the preview reserves from the first frame — two, because a pair of
/// long Gurmukhi names wraps rather than truncating (design canvas 2 row 2,
/// *Two-line wrap · long Gurmukhi names*).
const int previewLines = 2;

/// The preview line (07 §5.5).
class EntryPreviewLine extends StatelessWidget {
  /// Creates the line.
  const EntryPreviewLine({
    super.key,
    required this.amountPaise,
    required this.complete,
    this.creditName,
    this.debitName,
    this.note,
    this.textKey,
  });

  /// The running total, integer paise (CLAUDE.md rule 1). Zero renders `₹0`.
  final int amountPaise;

  /// True when both sides are chosen and the amount is more than nil — full
  /// ink, and the moment Save turns solid.
  final bool complete;

  /// The account the engine credits, or null while the slot is empty.
  final String? creditName;

  /// The account the engine debits, or null while the slot is empty.
  final String? debitName;

  /// The user's own words, appended in lighter type; absent entirely when
  /// there is no note — no trailing separator, no "no note" placeholder.
  final String? note;

  /// Key for the rendered text (tests read its ink).
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final base = RkType.caption.copyWith(
      color: complete ? Theme.of(context).colorScheme.onSurface : status.muted,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final lineHeight =
        scaler.scale(base.fontSize ?? 13) * RkType.lineHeightNormal;

    return SizedBox(
      // 🔒 Full height from the first frame.
      height: lineHeight * previewLines,
      width: double.infinity,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ExcludeSemantics(
          child: Text.rich(
            key: textKey,
            TextSpan(
              children: [
                TextSpan(
                  text: formatPaise(amountPaise, locale: locale),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: RkType.tabular,
                  ),
                ),
                const TextSpan(text: ' · '),
                TextSpan(text: creditName ?? previewGap),
                const TextSpan(text: ' $previewArrow '),
                TextSpan(text: debitName ?? previewGap),
                if (note != null && note!.isNotEmpty)
                  TextSpan(
                    text: ' · $note',
                    style: TextStyle(color: status.muted),
                  ),
              ],
            ),
            style: base,
            maxLines: previewLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
