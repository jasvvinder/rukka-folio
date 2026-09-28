// S9.2's fail-closed state — *no code to show yet* (ADR 2026-09-25b §3,
// 04 §6.1 as amended, 07 §12).
//
// When it shows. S9.2's QR carries the nonce of the invite that brought this
// user into the tenant. The inviter's device drew it; the server relays it
// (25b §1–§2); this device pairs it to the invite it accepted, by `invite_id`.
// When there is no such nonce — the invite was accepted before this launch
// (⚠️ SPEC, `features/members/invite_nonce_relay.dart`), the relay could not
// be read, or this ceremony was not born of an invite (25b Open) — there is
// nothing honest to put in the square. This device **never draws one** (§3),
// so no session is opened and no QR is drawn: this screen is built from a
// `ShowMyCodeNoInviteNonce`, which carries no repository at all.
//
// What it must be: 25b §3 — *"S9.2 keeps its placeholder and says why"* —
// read with 07 §1 rule 6 (no dead ends). So it is not the route's silent
// *Getting your code.*: it says there is no code yet and why, that nothing has
// been shared, and has two ways on — *Check again* (re-reads the relay; draws
// nothing) and *Close*.
//
// Colour is never alone (07 §1 rule 3): the icon carries a semantics label and
// the title says the state in words.
//
// ⚠️ SPEC — copy: 07 §12 / 13 §3.2 give S9.2 no state for this; the words
// are this lane's draft for the 07/13 design owner (reported, M11-NONCE2).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// S9.2 while this device holds no relayed invite nonce.
class ShowMyCodeNoInviteScreen extends StatelessWidget {
  /// [onCheckAgain] re-opens this side; [onClose] leaves S9.2.
  const ShowMyCodeNoInviteScreen({super.key, this.onCheckAgain, this.onClose});

  /// *Check again*.
  final VoidCallback? onCheckAgain;

  /// *Close*.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ceremonyShowTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: l10n.ceremonyShowNoInviteSemantics,
                child: Icon(
                  Icons.qr_code_2_outlined,
                  size: RkSpace.s12,
                  color: status.warning,
                ),
              ),
              const SizedBox(height: RkSpace.s4),
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(
                  l10n.ceremonyShowNoInviteTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              Text(
                l10n.ceremonyShowNoInviteBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: RkSpace.s3),
              Text(
                l10n.ceremonyShowNoInviteWhy,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: status.muted,
                ),
              ),
              const SizedBox(height: RkSpace.s8),
              FilledButton(
                onPressed: onCheckAgain,
                child: Text(l10n.ceremonyShowNoInviteRetry),
              ),
              const SizedBox(height: RkSpace.s3),
              TextButton(
                onPressed: onClose,
                child: Text(l10n.ceremonyShowNoInviteClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
