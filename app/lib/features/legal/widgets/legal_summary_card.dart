// The S18 hub's summary card — the *designed* surface of the legal family
// (ADR 2026-09-02: "the designed surface is each one's summary card on the
// S18 hub"). The documents behind it are plain pages; this card is where the
// claim is actually made, in the reader's language, before they decide
// whether to open anything.
//
// Tokens only; every string draws through [RkFitText] (07 §1 rules 9, 11).
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';

/// One summary card on S18: a title, one or more lines of plain summary,
/// and the door to the document itself.
class LegalSummaryCard extends StatelessWidget {
  /// Creates the card.
  const LegalSummaryCard({
    super.key,
    required this.title,
    required this.lines,
    required this.actionLabel,
    this.onOpen,
    this.numbered = false,
    this.leading,
  });

  /// Card heading.
  final String title;

  /// The summary — one paragraph, or the four lines of *Privacy, in four
  /// lines* (13 §3.2 row S18.2).
  final List<String> lines;

  /// Label of the door to the document.
  final String actionLabel;

  /// Opens the document. Null renders the door disabled rather than absent —
  /// a card with no way on would be a dead end (07 §1 rule 6).
  final VoidCallback? onOpen;

  /// Draws the lines as a numbered list. *Privacy, in four lines* takes it;
  /// a one-paragraph summary does not.
  final bool numbered;

  /// Icon beside the title. Paired with the words, never carrying meaning on
  /// its own (07 §1 rule 3).
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return RkRuledCard(
      child: Semantics(
        container: true,
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[
                    Icon(leading, size: RkIcon.grid, color: scheme.primary),
                    const SizedBox(width: RkSpace.s2),
                  ],
                  Expanded(child: RkFitText(title, style: text.titleLarge)),
                ],
              ),
              const SizedBox(height: RkSpace.s2),
              for (var i = 0; i < lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: RkSpace.s2),
                  child: numbered
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: RkSpace.s6,
                              child: RkFitText(
                                '${i + 1}.',
                                style: text.bodyLarge?.copyWith(
                                  color: status.muted,
                                  fontFeatures: RkType.tabular,
                                ),
                              ),
                            ),
                            Expanded(
                              child: RkFitText(lines[i], style: text.bodyLarge),
                            ),
                          ],
                        )
                      : RkFitText(lines[i], style: text.bodyLarge),
                ),
              const SizedBox(height: RkSpace.s2),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onOpen,
                  child: RkFitText(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
