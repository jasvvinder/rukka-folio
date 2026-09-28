// What S9.1 shows once an invite exists: the inviter still has to send it
// (ADR 2026-09-25 §2 — the server sends nothing).
//
// The order is fixed by the ruling: the invite is **created first**, and only
// then is the share sheet raised with the link and a prefilled message
// ([offerInvite]). If creation failed there is nothing to share, so no sheet
// is opened — the form's own error stands.
//
// What the panel says depends on what the seam reports (share_sheet.dart):
//   * a raised sheet → **nothing is claimed**; the sheet was its own
//     confirmation and the platform reports neither send nor cancel (07 §1
//     rule 12, the `ReportShared` precedent);
//   * copied → the fact, and where to paste it;
//   * unavailable → why, with the message on screen and *Copy the message*, so
//     the invite is never a dead end (07 §1 rules 2 and 6).
// *Resend* reopens the sheet with the same message; *Done* goes back to S9.
//
// ⚠️ SPEC (M11-INV2): with **no link** ([CreatedInvite.link] null — production
// until the owner rules a link format, [InviteLinkOf]) there is nothing to
// send. No sheet is raised and no message is offered: the panel says the
// invite exists and why nothing can be sent yet (13 §4.3 disabled-with-reason),
// with *Done* as the way out. It never names a join path — the spec has only
// the deep link (13 §3.2 S0.9; 07 §3.1 step 8).
//
// The message carries the link and the product name — **no amount, no book
// name or figure and no phone number** (CLAUDE.md rule 4). The invitee's
// number stays in the contact card on this device (ADR 2026-09-05f §G 🔒);
// the link alone admits nobody (ADR 2026-09-05d §9 🔒).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/seams/share_sheet.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../members_repository.dart';

/// The prefilled message for [invite], in the inviter's language — or null
/// when the invite has no link, because a message without one would have to
/// invent a way to join (⚠️ SPEC M11-INV2).
String? inviteShareMessage(AppLocalizations l10n, CreatedInvite invite) {
  final link = invite.link;
  return link == null
      ? null
      : l10n.inviteShareMessage(l10n.appName, link.toString());
}

/// Offers [invite]'s message through the share sheet, or — with no link —
/// offers nothing and returns null (no sheet is raised).
Future<ShareOutcome?> offerCreatedInvite(
  BuildContext context,
  CreatedInvite invite, {
  ShareSheet? via,
}) async {
  final message = inviteShareMessage(AppLocalizations.of(context), invite);
  if (message == null) return null;
  return offerInvite(context, message, via: via);
}

/// Hands [message] to the installed [ShareSheet]. With none installed, the
/// share is [ShareUnavailable] — the panel then shows the message and *Copy*.
///
/// [via] wins over the scope: a modal sheet is built under the navigator,
/// which may sit above the [ShareSheetScope], so its opener passes the sheet
/// it found.
Future<ShareOutcome> offerInvite(
  BuildContext context,
  String message, {
  ShareSheet? via,
}) {
  final sheet = via ?? ShareSheetScope.maybeOf(context);
  if (sheet == null) return Future.value(const ShareUnavailable());
  return sheet.shareText(message);
}

/// The after-creation panel: the message, *Resend*, *Copy the message* and
/// *Done*, with one line for what the last share did.
class InviteSharePanel extends StatefulWidget {
  /// Creates the panel for an invite already created and already offered
  /// once ([outcome] is what that first offer returned; null when nothing
  /// could be offered because the invite has no link).
  const InviteSharePanel({
    super.key,
    required this.invite,
    required this.outcome,
    required this.onDone,
    this.sheet,
  });

  /// The share sheet *Resend* uses; null → the nearest [ShareSheetScope].
  final ShareSheet? sheet;

  /// The invite that exists on the server.
  final CreatedInvite invite;

  /// What the first share returned; null → nothing was offered (no link).
  final ShareOutcome? outcome;

  /// Back to S9.
  final VoidCallback onDone;

  @override
  State<InviteSharePanel> createState() => _InviteSharePanelState();
}

class _InviteSharePanelState extends State<InviteSharePanel> {
  late ShareOutcome? _outcome = widget.outcome;
  bool _busy = false;

  Future<void> _resend(String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await offerInvite(context, message, via: widget.sheet);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  Future<void> _copy(String message) async {
    // Flutter's own clipboard — the fallback needs no package.
    final outcome = await const ClipboardShareSheet().shareText(message);
    if (!mounted) return;
    setState(() => _outcome = outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final message = inviteShareMessage(l10n, widget.invite);
    if (message == null) return _noLink(context);
    final outcome = _outcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.inviteReadyTitle, style: text.titleLarge),
        const SizedBox(height: RkSpace.s2),
        Text(l10n.inviteReadyBody, style: text.bodyMedium),
        const SizedBox(height: RkSpace.s4),
        // The message itself, selectable, so it can always be taken by hand.
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: status.hairline),
            borderRadius: BorderRadius.circular(RkRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.cardPadding),
            child: SelectableText(message, style: text.bodyMedium),
          ),
        ),
        const SizedBox(height: RkSpace.s2),
        Text(l10n.inviteExpiryNote, style: text.bodySmall),
        if (outcome is! ShareSheetRaised) ...[
          const SizedBox(height: RkSpace.s3),
          Semantics(
            container: true,
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colour never alone: the icon and the sentence carry it.
                Icon(
                  outcome is ShareCopied
                      ? Icons.content_copy
                      : Icons.info_outline,
                  size: RkIcon.grid - RkSpace.s2,
                  color: outcome is ShareCopied ? status.success : status.info,
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: Text(
                    outcome is ShareCopied
                        ? l10n.inviteShareCopied
                        : l10n.inviteShareUnavailable,
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: RkSpace.s4),
        FilledButton.icon(
          onPressed: _busy ? null : () => _resend(message),
          icon: const Icon(Icons.ios_share),
          label: Text(l10n.inviteShareResend),
        ),
        const SizedBox(height: RkSpace.s2),
        OutlinedButton.icon(
          onPressed: () => _copy(message),
          icon: const Icon(Icons.content_copy),
          label: Text(l10n.inviteShareCopy),
        ),
        const SizedBox(height: RkSpace.s2),
        TextButton(onPressed: widget.onDone, child: Text(l10n.inviteShareDone)),
      ],
    );
  }

  /// No link, so nothing to send: the invite exists, the reason is stated,
  /// and *Done* is the way out. No message, no *Resend*, no *Copy*, and no
  /// line about a link's expiry (⚠️ SPEC M11-INV2).
  Widget _noLink(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.inviteNolinkTitle, style: text.titleLarge),
        const SizedBox(height: RkSpace.s3),
        Semantics(
          container: true,
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Colour never alone: the icon and the sentence carry it.
              Icon(
                Icons.info_outline,
                size: RkIcon.grid - RkSpace.s2,
                color: status.info,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: Text(l10n.inviteNolinkBody, style: text.bodyMedium),
              ),
            ],
          ),
        ),
        const SizedBox(height: RkSpace.s4),
        FilledButton(
          onPressed: widget.onDone,
          child: Text(l10n.inviteShareDone),
        ),
      ],
    );
  }
}
