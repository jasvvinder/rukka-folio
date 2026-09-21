// S17.2 FAQ article (13 §3.2 row S17.2: "one answer, plain language";
// 07 §22 🔒). One question, its answer in paragraphs, and — because 07 §1
// rule 6 🔒 forbids a dead end — the ways on under *Did this not answer it?*.
//
// Two states (13 §4.3): the answer, and the missing answer. The second is
// reached when the route carries an id the catalogue does not know, which is
// what an old link or a renamed id looks like; it says so and offers the hub
// rather than drawing an empty page.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../faq_catalog.dart';
import '../widgets/help_widgets.dart';

/// S17.2 — one answer.
class FaqArticleScreen extends StatelessWidget {
  /// Creates the page for the answer [id].
  const FaqArticleScreen({
    super.key,
    required this.id,
    required this.onBackToHub,
    required this.onOpenContact,
  });

  /// The answer's id, from the route.
  final String id;

  /// Returns to S17 — the hub holds every question.
  final VoidCallback onBackToHub;

  /// Opens S17.3. Required: S17.3 is built, so this door always goes
  /// somewhere (07 §1 rule 6 🔒).
  final VoidCallback onOpenContact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final article = faqText(l10n, id);
    return Scaffold(
      appBar: AppBar(title: RkFitText(l10n.helpArticleAppbar)),
      body: SafeArea(
        child: article == null
            ? _Missing(onBackToHub: onBackToHub)
            : ListView(
                padding: const EdgeInsets.only(bottom: RkSpace.s10),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RkSpace.gutter,
                      RkSpace.s5,
                      RkSpace.gutter,
                      RkSpace.s2,
                    ),
                    child: RkFitText(article.question, style: text.titleLarge),
                  ),
                  for (final p in article.paragraphs) HelpParagraph(p),
                  HelpSectionHeading(l10n.helpArticleStuck),
                  HelpDoorRow(
                    icon: Icons.list_alt_outlined,
                    title: l10n.helpArticleMore,
                    onTap: onBackToHub,
                  ),
                  HelpDoorRow(
                    icon: Icons.chat_outlined,
                    title: l10n.helpContactTitle,
                    subtitle: l10n.helpContactValue,
                    onTap: onOpenContact,
                  ),
                ],
              ),
      ),
    );
  }
}

/// The unknown-id state (13 §4.3): what happened, and the way back.
class _Missing extends StatelessWidget {
  const _Missing({required this.onBackToHub});

  final VoidCallback onBackToHub;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s8,
        RkSpace.gutter,
        RkSpace.s10,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon and words carry the state; the muted tint only
            // reinforces it (07 §1 rule 3).
            Icon(
              Icons.help_center_outlined,
              size: RkIcon.grid,
              color: status.muted,
            ),
            const SizedBox(width: RkSpace.s2),
            Expanded(
              child: RkFitText(
                l10n.helpArticleMissingTitle,
                style: text.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s2),
        RkFitText(l10n.helpArticleMissingBody, style: text.bodyLarge),
        const SizedBox(height: RkSpace.s4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: onBackToHub,
            child: RkFitText(l10n.helpArticleMissingAction),
          ),
        ),
      ],
    );
  }
}
