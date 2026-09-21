// S17.3 Contact support (13 §3.2 row S17.3: "WhatsApp primary; states what
// support cannot do"; 07 §22 🔒, which names the four limits of 06 §8 🔒).
//
// ⛔ Nothing on this screen launches anything. PLAN-11 is open:
// ADR 2026-09-19 (mobile_scanner + url_launcher) is unratified, so
// `url_launcher` is not in `app/pubspec.yaml` and no `tel:`, `wa.me` or
// `https:` target may be opened from here. [onOpenChannel] is the seam for
// the day it is ratified and production passes **null**, exactly as
// `features/recovery` passes a null `RecoveryScanner` under the same ADR.
//
// That is why the honest shape of this screen is not "a button that opens
// WhatsApp". It is:
//
//   1. the channel, named, with the disabled-with-reason state of 13 §4.3
//      saying in words why it will not open yet;
//   2. **what support cannot do** — the part of S17.3 that 07 §22 🔒 makes
//      normative, and the part that is useful whether or not the door opens:
//      a reader who learns that no endpoint exists to read their book cannot
//      be talked into asking for one (06 §8 🔒);
//   3. the ways on, so the page is never a dead end (07 §1 rule 6 🔒) — the
//      answer that spells support's powers out, and S17.4, which is the one
//      thing a person *can* send today.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../faq_catalog.dart';
import '../widgets/help_widgets.dart';

/// S17.3 — Contact support.
class ContactSupportScreen extends StatelessWidget {
  /// Creates the page.
  const ContactSupportScreen({
    super.key,
    this.onOpenChannel,
    required this.onOpenDiagnostics,
    required this.onOpenArticle,
  });

  /// Opens the WhatsApp conversation. **Null in production** while
  /// ADR 2026-09-19 is unratified; the row then states the reason.
  final VoidCallback? onOpenChannel;

  /// Opens S17.4. Required: S17.4 is built, and it is the one thing a person
  /// *can* send today, so this door never has nowhere to go.
  final VoidCallback onOpenDiagnostics;

  /// Opens S17.2 for an answer id.
  final void Function(String id) onOpenArticle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final powers = faqText(l10n, 'support_powers');
    return Scaffold(
      appBar: AppBar(title: RkFitText(l10n.helpContactTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: RkSpace.s10),
          children: [
            HelpDoorRow(
              icon: Icons.chat_outlined,
              title: l10n.helpContactValue,
              onTap: onOpenChannel,
              reason: l10n.helpContactReason,
            ),
            HelpLimitsCard(
              title: l10n.helpCannotTitle,
              lines: [
                l10n.helpCannotRead,
                l10n.helpCannotKey,
                l10n.helpCannotMember,
                l10n.helpCannotCeremony,
              ],
              footnote: l10n.helpCannotFootnote,
            ),
            HelpSectionHeading(l10n.helpSectionReach),
            if (powers != null)
              HelpDoorRow(
                icon: Icons.verified_user_outlined,
                title: powers.question,
                onTap: () => onOpenArticle('support_powers'),
              ),
            HelpDoorRow(
              icon: Icons.assignment_outlined,
              title: l10n.helpDiagnosticsTitle,
              subtitle: l10n.helpDiagnosticsSubtitle,
              onTap: onOpenDiagnostics,
            ),
          ],
        ),
      ),
    );
  }
}
