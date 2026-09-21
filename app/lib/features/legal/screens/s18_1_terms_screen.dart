// S18.1 Terms of service (13 §3.2 row S18.1) — a document page through the
// shared template (ADR 2026-09-02).
//
// **The prose is not the app's to write.** Terms are the owner's and
// counsel's words, and a placeholder that reads like terms would be worse
// than an empty page: a reader would take it for the agreement. So the
// surface is built and the content state is honest — the page says the
// document is not published yet, and offers S18.3, which is (07 §1 rule 6,
// no dead ends).
//
// Landing the real text is a one-line change here: pass `blocks:` instead of
// null. Until then this **blocks a store submission** — both app stores
// require a reachable privacy policy and terms.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../widgets/legal_document.dart';

/// S18.1 — Terms of service.
class TermsScreen extends StatelessWidget {
  /// Creates the page.
  const TermsScreen({super.key, this.onOpenWhatWeSee});

  /// Takes the reader to S18.3 while the terms are unpublished.
  final VoidCallback? onOpenWhatWeSee;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LegalDocumentPage(
      title: l10n.legalTermsTitle,
      blocks: null,
      pendingBadge: l10n.legalDocumentPendingBadge,
      pendingBody: l10n.legalDocumentPendingBody,
      pendingActionLabel: l10n.legalDocumentPendingAction,
      onPendingAction: onOpenWhatWeSee,
    );
  }
}
