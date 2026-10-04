// S17.3 Contact support (13 §3.2 row S17.3: "email primary for the pilot …
// states what support cannot do"; 07 §22 🔒, which names the four limits of
// 06 §8 🔒; ADR 2026-09-25 §4, which makes *Email support* the primary
// action).
//
// The page, top to bottom:
//
//   1. **Email support** — the primary action, through [SupportMailer], which
//      can open `mailto:support@rukkafolio.com` and nothing else (ADR
//      2026-09-19 ruling 2 as amended by ADR 2026-09-25 §4). The address is
//      always on the page, selectable, beside *Copy the address*, so a phone
//      with no email app still has a way on. A failed launch names the
//      address in words beside an icon (07 §1 rules 3, 6 🔒). Above the
//      action, the card warns not to send amounts or account numbers (ADR
//      2026-10-03c §7).
//   2. **What support cannot do** — the 🔒 statement of 06 §8, word for word
//      (ADR 2026-09-25 §4 keeps it). A reader who learns that no endpoint
//      exists to read their book cannot be talked into asking for one.
//   3. the other ways on: the answer that spells support's powers out, and
//      S17.4.
//
// There is no chat door: the in-app AI chat of ADR 2026-09-25 §4 needs its
// own ADR before it is built.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../faq_catalog.dart';
import '../support_mailer.dart';
import '../widgets/help_widgets.dart';

/// S17.3 — Contact support.
class ContactSupportScreen extends StatefulWidget {
  /// Creates the page.
  const ContactSupportScreen({
    super.key,
    required this.mailer,
    required this.onOpenDiagnostics,
    required this.onOpenArticle,
  });

  /// Opens the email app addressed to support. Required: email is the
  /// primary channel (ADR 2026-09-25 §4), so production always supplies
  /// [UrlLauncherSupportMailer].
  final SupportMailer mailer;

  /// Opens S17.4.
  final VoidCallback onOpenDiagnostics;

  /// Opens S17.2 for an answer id.
  final void Function(String id) onOpenArticle;

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _email() async {
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await widget.mailer.openSupportEmail();
    } on Object {
      // The seam promises not to throw; a fake or a future one that does is
      // still a failed launch, never a crash.
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
  }

  Future<void> _copy(String confirmation) async {
    await Clipboard.setData(const ClipboardData(text: supportEmailAddress));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: RkFitText(confirmation)));
  }

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
            _EmailCard(
              opening: _opening,
              failed: _failed,
              onEmail: _email,
              onCopy: () => _copy(l10n.helpContactEmailCopied),
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
                onTap: () => widget.onOpenArticle('support_powers'),
              ),
            HelpDoorRow(
              icon: Icons.assignment_outlined,
              title: l10n.helpDiagnosticsTitle,
              subtitle: l10n.helpDiagnosticsSubtitle,
              onTap: widget.onOpenDiagnostics,
            ),
          ],
        ),
      ),
    );
  }
}

/// The email channel: the primary action, the address, and — after a failed
/// launch — the line that says what to do instead.
class _EmailCard extends StatelessWidget {
  const _EmailCard({
    required this.opening,
    required this.failed,
    required this.onEmail,
    required this.onCopy,
  });

  final bool opening;
  final bool failed;
  final VoidCallback onEmail;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return RkRuledCard(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RkFitText(l10n.helpContactEmailBody, style: t.bodyLarge),
            const SizedBox(height: RkSpace.s3),
            // ADR 2026-10-03c §7: the person writes this text themselves, so
            // the card carries the AI chat's warning (ADR 2026-09-25 §4) —
            // CLAUDE.md rule 4 reaching the one channel the app does not
            // write. It sits above the action, so it is read before the
            // email app opens. Page copy only: the `mailto:` stays bare
            // (§6). An icon and words carry it; the tint is never the only
            // signal (07 §1 rule 3 🔒).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  size: RkIcon.grid,
                  color: status.warning,
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: RkFitText(
                    l10n.helpContactEmailWarning,
                    style: t.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s3),
            FilledButton.icon(
              // Disabled only for the instant a launch is in flight, so one
              // tap is one launch.
              onPressed: opening ? null : onEmail,
              icon: const Icon(Icons.mail_outline),
              label: RkFitText(l10n.helpContactEmailAction),
            ),
            if (failed) ...[
              const SizedBox(height: RkSpace.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The failure is an icon and words; no meaning rests on the
                  // tint (07 §1 rule 3 🔒).
                  Icon(
                    Icons.error_outline,
                    size: RkIcon.grid,
                    color: status.muted,
                  ),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: RkFitText(
                        l10n.helpContactEmailFailed(supportEmailAddress),
                        style: t.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: RkSpace.s4),
            RkFitText(
              l10n.helpContactEmailLabel,
              style: t.labelLarge?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s1),
            // Selectable, so the address can be long-pressed and copied by
            // hand as well as by the button below.
            SelectionArea(
              child: RkFitText(supportEmailAddress, style: t.titleMedium),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy),
                label: RkFitText(l10n.helpContactEmailCopy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
