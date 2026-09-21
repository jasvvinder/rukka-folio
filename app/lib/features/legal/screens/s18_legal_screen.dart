// S18 Legal & trust (13 §3.2 row S18; 07 §2 — the **last** Menu row under
// *This app*, ADR 2026-09-03 ruling 3). The hub is the designed surface of
// the family (ADR 2026-09-02): each document gets a summary card here that
// makes its claim in plain words, so a reader who never opens a document
// still learns the thing that matters.
//
// Card order is deliberate. *What we can and cannot see* (S18.3) comes
// first: it is the one page with content of its own and the brand's
// directional-trust claim (12 §2, 11 §1). *Privacy, in four lines* (S18.2)
// follows, because those four lines are the whole privacy answer for most
// readers. Terms (S18.1) and licences (S18.4) close.
//
// This screen owns no navigation: each card is handed a callback, the route
// supplies it (the EntryDetailScreen nullable-callback convention). A null
// callback leaves the door visible but disabled rather than removing it —
// a card with nowhere to go would be a dead end of a quieter kind
// (07 §1 rule 6).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../widgets/legal_summary_card.dart';

/// S18 — the Legal & trust hub.
class LegalScreen extends StatelessWidget {
  /// Creates the hub.
  const LegalScreen({
    super.key,
    this.onOpenWhatWeSee,
    this.onOpenPrivacy,
    this.onOpenTerms,
    this.onOpenLicences,
  });

  /// Opens S18.3.
  final VoidCallback? onOpenWhatWeSee;

  /// Opens S18.2.
  final VoidCallback? onOpenPrivacy;

  /// Opens S18.1.
  final VoidCallback? onOpenTerms;

  /// Opens S18.4.
  final VoidCallback? onOpenLicences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: RkFitText(l10n.legalTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: RkSpace.s10),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s4,
                RkSpace.gutter,
                RkSpace.s2,
              ),
              child: RkFitText(l10n.legalHubIntro, style: text.bodyLarge),
            ),
            LegalSummaryCard(
              leading: Icons.visibility_off_outlined,
              title: l10n.legalSeeCardTitle,
              lines: [l10n.legalSeeCardSummary],
              actionLabel: l10n.legalSeeCardAction,
              onOpen: onOpenWhatWeSee,
            ),
            LegalSummaryCard(
              leading: Icons.lock_outline,
              title: l10n.legalPrivacyCardTitle,
              numbered: true,
              lines: [
                l10n.legalPrivacyCardLine1,
                l10n.legalPrivacyCardLine2,
                l10n.legalPrivacyCardLine3,
                l10n.legalPrivacyCardLine4,
              ],
              actionLabel: l10n.legalPrivacyCardAction,
              onOpen: onOpenPrivacy,
            ),
            LegalSummaryCard(
              leading: Icons.description_outlined,
              title: l10n.legalTermsCardTitle,
              lines: [l10n.legalTermsCardSummary],
              actionLabel: l10n.legalTermsCardAction,
              onOpen: onOpenTerms,
            ),
            LegalSummaryCard(
              leading: Icons.code_outlined,
              title: l10n.legalLicencesCardTitle,
              lines: [l10n.legalLicencesCardSummary],
              actionLabel: l10n.legalLicencesCardAction,
              onOpen: onOpenLicences,
            ),
          ],
        ),
      ),
    );
  }
}
