// S18.3 What we can and cannot see (13 §3.2 row S18.3, 07 §23 🔒).
//
// This is 12 §2's impossibility table — "publish this table" is what 12 §2
// says of it — rendered for a reader who is not an engineer, plus the two
// lines 07 §23 🔒 requires: **where the data lives (India** — ADR 2026-09-05c
// §1) and what a rooted phone changes (nothing about the server; everything
// about that phone — 07 §24 S19.5, ADR 2026-09-05 §6).
//
// It also carries the other half honestly: 12 §1's list of what the console
// *can* see — a name, a language, a plan, counts — so the page is a true
// account rather than a one-sided claim. The two halves are what make it a
// trust asset instead of boilerplate (11 §1).
//
// Every row is an eight-row copy of 12 §2's table, in order. Adding, dropping
// or softening one is a 12 §2 change, not a copy change.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../widgets/legal_document.dart';

/// S18.3 — the impossibility table as a page.
class WhatWeSeeScreen extends StatelessWidget {
  /// Creates the page.
  const WhatWeSeeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LegalDocumentPage(
      title: l10n.legalSeeTitle,
      // Never null here: this is the page that is fully drawn, and the three
      // other S18 pages are patterned on it (ADR 2026-09-02).
      blocks: whatWeSeeBlocks(l10n),
      pendingBadge: l10n.legalDocumentPendingBadge,
      pendingBody: l10n.legalDocumentPendingBody,
      pendingActionLabel: l10n.legalDocumentPendingAction,
    );
  }
}

/// The page's content, in order. Exposed so a test can assert the eight rows
/// of 12 §2 are all present without reaching into the widget tree.
List<LegalBlock> whatWeSeeBlocks(AppLocalizations l10n) => [
  LegalParagraph(l10n.legalSeeIntro),
  LegalHeading(l10n.legalSeeCannotHeading),
  LegalParagraph(l10n.legalSeeCannotLead),
  // 12 §2, row for row.
  LegalClaim(
    claim: l10n.legalSeeCannotEntriesClaim,
    why: l10n.legalSeeCannotEntriesWhy,
  ),
  LegalClaim(
    claim: l10n.legalSeeCannotPasswordClaim,
    why: l10n.legalSeeCannotPasswordWhy,
  ),
  LegalClaim(
    claim: l10n.legalSeeCannotRecoverClaim,
    why: l10n.legalSeeCannotRecoverWhy,
  ),
  LegalClaim(
    claim: l10n.legalSeeCannotMemberClaim,
    why: l10n.legalSeeCannotMemberWhy,
  ),
  LegalClaim(
    claim: l10n.legalSeeCannotRefundClaim,
    why: l10n.legalSeeCannotRefundWhy,
  ),
  LegalClaim(
    claim: l10n.legalSeeCannotPhoneClaim,
    why: l10n.legalSeeCannotPhoneWhy,
  ),
  LegalClaim(
    claim: l10n.legalSeeCannotImpersonateClaim,
    why: l10n.legalSeeCannotImpersonateWhy,
  ),
  LegalClaim(
    claim: l10n.legalSeeCannotResetAllClaim,
    why: l10n.legalSeeCannotResetAllWhy,
  ),
  // 12 §1 — the honest other half.
  LegalHeading(l10n.legalSeeCanHeading),
  LegalParagraph(l10n.legalSeeCanBody),
  // ADR 2026-09-05c §1 — the residency line 07 §23 🔒 asks for.
  LegalHeading(l10n.legalSeeIndiaHeading),
  LegalParagraph(l10n.legalSeeIndiaBody),
  // 07 §23 🔒 — what a rooted phone changes.
  LegalHeading(l10n.legalSeeRootedHeading),
  LegalParagraph(l10n.legalSeeRootedBody),
  LegalNote(l10n.legalSeeFooter),
];
