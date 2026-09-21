// The pieces the four S17 screens share. Tokens only — a hex literal here is
// review-blocking (CLAUDE.md, design-system). Every string draws through
// [RkFitText]: at 200 % on a 360 px phone a Gurmukhi or Devanagari compound
// is wider than the column and Flutter draws it past the edge without
// throwing (07 §1 rules 9, 11).
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';

/// A section heading inside a Help page.
class HelpSectionHeading extends StatelessWidget {
  /// Creates the heading.
  const HelpSectionHeading(this.text, {super.key});

  /// The heading.
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RkSpace.gutter,
      RkSpace.s6,
      RkSpace.gutter,
      RkSpace.s2,
    ),
    child: RkFitText(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// A paragraph of Help prose.
class HelpParagraph extends StatelessWidget {
  /// Creates the paragraph.
  const HelpParagraph(this.text, {super.key, this.muted = false});

  /// The prose.
  final String text;

  /// Draws it as a quiet closing note.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s2,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: RkFitText(
        text,
        style: muted ? t.bodySmall?.copyWith(color: status.muted) : t.bodyLarge,
      ),
    );
  }
}

/// A door out of a Help page: a row that opens another screen, or states in
/// words why it cannot (13 §4.3 disabled-with-reason). A null [onTap] with no
/// [reason] is a programming error, not a state — every door either goes
/// somewhere or says why it does not (07 §1 rule 6 🔒).
class HelpDoorRow extends StatelessWidget {
  /// Creates the row.
  const HelpDoorRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.reason,
  }) : assert(
         onTap != null || reason != null,
         'a door with nowhere to go must state why (07 §1 rule 6)',
       );

  /// The icon that carries the row's meaning beside its words.
  final IconData icon;

  /// The row's title.
  final String title;

  /// What lies behind it.
  final String? subtitle;

  /// Opens it; null leaves it disabled.
  final VoidCallback? onTap;

  /// Why it is disabled. Drawn instead of [subtitle] when [onTap] is null.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final enabled = onTap != null;
    final under = enabled ? subtitle : (reason ?? subtitle);
    final body = Container(
      constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: RkIcon.grid,
            color: enabled
                ? Theme.of(context).colorScheme.primary
                : status.muted,
          ),
          const SizedBox(width: RkSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RkFitText(
                  title,
                  style: enabled
                      ? t.bodyLarge
                      : t.bodyLarge?.copyWith(color: status.muted),
                ),
                if (under != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The reason is carried by an icon as well as the
                        // words, never by the muted tint alone (07 §1 rule 3).
                        if (!enabled) ...[
                          Icon(
                            Icons.schedule,
                            size: RkSpace.s4 - 2,
                            color: status.muted,
                          ),
                          const SizedBox(width: RkSpace.s1),
                        ],
                        Expanded(
                          child: RkFitText(
                            under,
                            style: t.bodySmall?.copyWith(color: status.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: RkSpace.s2),
          if (enabled) Icon(Icons.chevron_right, color: status.muted),
        ],
      ),
    );
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: under == null ? title : '$title. $under',
      child: ExcludeSemantics(
        child: enabled ? InkWell(onTap: onTap, child: body) : body,
      ),
    );
  }
}

/// One question in the hub's list.
class HelpQuestionRow extends StatelessWidget {
  /// Creates the row.
  const HelpQuestionRow({
    super.key,
    required this.question,
    required this.onOpen,
  });

  /// The question, verbatim — it is the article's heading too.
  final String question;

  /// Opens S17.2 for it.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      button: true,
      label: question,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: RkSpace.gutter,
              vertical: RkSpace.s3,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: status.hairline)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.help_outline,
                  size: RkIcon.grid,
                  color: status.muted,
                ),
                const SizedBox(width: RkSpace.s3),
                Expanded(
                  child: RkFitText(
                    question,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: RkSpace.s2),
                Icon(Icons.chevron_right, color: status.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card listing things that cannot be done, each line carried by a block
/// icon as well as by its words (07 §1 rule 3). S17.3 draws support's limits
/// with it (07 §22 🔒, 06 §8 🔒); S17.4 draws the payload's exclusions.
class HelpLimitsCard extends StatelessWidget {
  /// Creates the card.
  const HelpLimitsCard({
    super.key,
    required this.title,
    required this.lines,
    this.footnote,
    this.icon = Icons.block,
  });

  /// The card's heading.
  final String title;

  /// One line per limit.
  final List<String> lines;

  /// The closing line, when there is one.
  final String? footnote;

  /// The icon each line carries.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final footnote = this.footnote;
    return RkRuledCard(
      ruleColor: status.locked,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RkFitText(title, style: t.titleMedium),
            const SizedBox(height: RkSpace.s3),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: RkSpace.s2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: RkIcon.grid, color: status.locked),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(child: RkFitText(line, style: t.bodyLarge)),
                  ],
                ),
              ),
            if (footnote != null)
              RkFitText(
                footnote,
                style: t.bodySmall?.copyWith(color: status.muted),
              ),
          ],
        ),
      ),
    );
  }
}
