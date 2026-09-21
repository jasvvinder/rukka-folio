// S18.2 Privacy policy (13 §3.2 row S18.2) — a document page through the
// shared template (ADR 2026-09-02).
//
// The *designed* privacy surface is the hub's **Privacy, in four lines**
// card, and that card is built and true (S18, this feature). The policy
// itself is counsel's document, so this page carries the same honest
// missing-content state as S18.1 rather than prose nobody signed off, and
// offers S18.3 meanwhile (07 §1 rule 6).
//
// The four lines on the hub and the impossibility table on S18.3 are the
// substance; this page is the legal record of it, and it **blocks a store
// submission** until the owner lands the text.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../widgets/legal_document.dart';

/// S18.2 — Privacy policy.
class PrivacyScreen extends StatelessWidget {
  /// Creates the page.
  const PrivacyScreen({super.key, this.onOpenWhatWeSee});

  /// Takes the reader to S18.3 while the policy is unpublished.
  final VoidCallback? onOpenWhatWeSee;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LegalDocumentPage(
      title: l10n.legalPrivacyTitle,
      blocks: null,
      pendingBadge: l10n.legalDocumentPendingBadge,
      pendingBody: l10n.legalDocumentPendingBody,
      pendingActionLabel: l10n.legalDocumentPendingAction,
      onPendingAction: onOpenWhatWeSee,
    );
  }
}
