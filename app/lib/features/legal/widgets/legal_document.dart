// The one document-page template every S18 page renders through (13 §3.2
// rows S18.1/S18.2/S18.4, ADR 2026-09-02: "document pages, rendered in a
// shared template patterned on S18.3"). S18.3 is the page that is fully
// drawn, so the template is its shape: a title, then a column of blocks —
// headings, paragraphs, and the claim/reason pair that 12 §2's impossibility
// table is made of.
//
// Tokens only — a hex literal here is review-blocking (CLAUDE.md,
// design-system). Every string draws through [RkFitText]: at 200 % on a
// 360 px phone a Gurmukhi or Devanagari compound is wider than the column,
// and Flutter draws it past the edge without throwing (07 §1 rules 9, 11).
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';

/// One piece of a legal document page.
sealed class LegalBlock {
  const LegalBlock();
}

/// A section heading.
final class LegalHeading extends LegalBlock {
  /// Creates the heading.
  const LegalHeading(this.text);

  /// The heading itself.
  final String text;
}

/// A paragraph of prose.
final class LegalParagraph extends LegalBlock {
  /// Creates the paragraph.
  const LegalParagraph(this.text);

  /// The prose.
  final String text;
}

/// One row of the impossibility table (12 §2): a thing that cannot be done,
/// and why it cannot — rendered as a card rather than a table, because a
/// two-column table of sentences is unreadable on a 360 px phone and
/// unreadable twice over at 200 % font scale.
final class LegalClaim extends LegalBlock {
  /// Creates the row.
  const LegalClaim({required this.claim, required this.why});

  /// What cannot be done.
  final String claim;

  /// Why it cannot — the structural reason, in the reader's words.
  final String why;
}

/// A quiet closing line.
final class LegalNote extends LegalBlock {
  /// Creates the note.
  const LegalNote(this.text);

  /// The line.
  final String text;
}

/// The shared S18 document page.
///
/// [blocks] null is the **honest missing-content state**: the document has
/// not been published in the app yet, and rather than a placeholder that
/// reads like terms nobody wrote, the page says so and offers the way on
/// (07 §1 rule 6 — no dead ends). The state is carried by an icon and the
/// words, never by the tint alone (07 §1 rule 3).
class LegalDocumentPage extends StatelessWidget {
  /// Creates the page.
  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.blocks,
    required this.pendingBadge,
    required this.pendingBody,
    required this.pendingActionLabel,
    this.onPendingAction,
  });

  /// App-bar title.
  final String title;

  /// The document, or null while it is unpublished.
  final List<LegalBlock>? blocks;

  /// Short label of the missing-content state.
  final String pendingBadge;

  /// What the reader should do instead.
  final String pendingBody;

  /// Label of the way out of the missing-content state.
  final String pendingActionLabel;

  /// Takes the reader to S18.3, which *is* published. Null only in a test
  /// that pumps the page bare; the route always supplies it.
  final VoidCallback? onPendingAction;

  @override
  Widget build(BuildContext context) {
    final blocks = this.blocks;
    return Scaffold(
      appBar: AppBar(title: RkFitText(title)),
      body: SafeArea(
        child: blocks == null
            ? _PendingBody(
                badge: pendingBadge,
                body: pendingBody,
                actionLabel: pendingActionLabel,
                onAction: onPendingAction,
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: RkSpace.s10),
                children: [for (final b in blocks) LegalBlockView(b)],
              ),
      ),
    );
  }
}

/// Draws one [LegalBlock]. Public so S18.4 can mix blocks into its own list.
class LegalBlockView extends StatelessWidget {
  /// Creates the view.
  const LegalBlockView(this.block, {super.key});

  /// What to draw.
  final LegalBlock block;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return switch (block) {
      LegalHeading(text: final heading) => Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s6,
          RkSpace.gutter,
          RkSpace.s2,
        ),
        child: RkFitText(heading, style: text.titleLarge),
      ),
      LegalParagraph(text: final para) => Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s2,
          RkSpace.gutter,
          RkSpace.s2,
        ),
        child: RkFitText(para, style: text.bodyLarge),
      ),
      LegalClaim(:final claim, :final why) => RkRuledCard(
        ruleColor: status.locked,
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The meaning rides on the icon and the words; the muted
                  // tint only reinforces it (07 §1 rule 3).
                  Icon(Icons.block, size: RkIcon.grid, color: status.locked),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: RkFitText(
                      claim,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RkSpace.s2),
              RkFitText(
                why,
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
            ],
          ),
        ),
      ),
      LegalNote(text: final note) => Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s5,
          RkSpace.gutter,
          RkSpace.s2,
        ),
        child: RkFitText(
          note,
          style: text.bodySmall?.copyWith(color: status.muted),
        ),
      ),
    };
  }
}

class _PendingBody extends StatelessWidget {
  const _PendingBody({
    required this.badge,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String badge;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.only(top: RkSpace.s6, bottom: RkSpace.s10),
      children: [
        RkRuledCard(
          ruleColor: status.pending,
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.hourglass_empty,
                      size: RkIcon.grid,
                      color: status.pending,
                    ),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(child: RkFitText(badge, style: text.titleMedium)),
                  ],
                ),
                const SizedBox(height: RkSpace.s3),
                RkFitText(body, style: text.bodyLarge),
                if (onAction != null) ...[
                  const SizedBox(height: RkSpace.s4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton(
                      onPressed: onAction,
                      child: RkFitText(actionLabel),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
