// S9.4 Verification mismatch (13 §3.2, 07 §12 🔒, 04 §6.3 🔒).
//
// 🔒 A full red screen with **no override**. No *Try again*, no *Are you
// sure*, no way to mark the person verified from here — that absence is the
// whole screen. The `verification_mismatch` security event is written by the
// repository at the moment the comparison failed (04 §6.3), before this screen
// is ever pushed, so nothing a user does or does not do here can lose it.
//
// Colour is never alone (07 §1 rule 3): the red ground carries an icon and the
// words *Do not proceed*, and reads the same in greyscale.
//
// ⚠️ SPEC: Canvas 4 (S9.4 "Mismatch · no way past") words the title *"Do not
// continue."* and the action *"Call Rukka support"*; 04 §6.3 🔒 quotes *"Do not
// proceed. Contact support."*. `design/` and the numbered specs rank together
// (CLAUDE.md § Precedence item 2), so this is a same-level conflict and is not
// ours to settle: the 04 §6.3 wording is kept because 04 owns the ceremony and
// quotes the sentence literally, and the canvas's three *additional* lines —
// the two causes, "Nothing has been shared", and the face-to-face next step —
// are taken as written, since they conflict with nothing. Raised for the owner
// in the M7-U4b lane report.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// S9.4.
class VerificationMismatchScreen extends StatelessWidget {
  /// [onContactSupport] is the one action of 04 §6.3. [onClose] leaves the
  /// screen with the person still unverified.
  const VerificationMismatchScreen({
    super.key,
    this.onContactSupport,
    this.onClose,
  });

  /// *Contact support*.
  final VoidCallback? onContactSupport;

  /// Way off the screen — back to Members, nothing verified.
  //
  // ⚠️ SPEC: 07 §12 and 04 §6.3 name the red screen, the absence of an
  // override and *Contact support*, and say nothing about leaving. Trapping a
  // user in the app is not the conservative reading of "no override", so a
  // muted *Close* pops back with the member still unverified: it grants
  // nothing, retries nothing and re-runs no comparison. Raised for the owner
  // in the M7-U4b lane report.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Scaffold(
      backgroundColor: status.danger,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: RkSpace.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: l10n.ceremonyMismatchSemantics,
                  child: Icon(
                    Icons.gpp_bad_outlined,
                    size: RkSpace.s12,
                    color: status.onDanger,
                  ),
                ),
                const SizedBox(height: RkSpace.s4),
                Text(
                  l10n.ceremonyMismatchTitle,
                  // `section` (titleLarge), not `page`: at 200 % on a 360 px
                  // phone the longest word of this title needs more than the
                  // 328 px the gutter leaves at either larger step, and it
                  // draws past the edge without throwing anything
                  // (test_app's expectTextFits). It is still the loudest type
                  // on the screen — the red ground and the icon carry the
                  // rest.
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: status.onDanger,
                  ),
                ),
                const SizedBox(height: RkSpace.s3),
                Text(
                  l10n.ceremonyMismatchBody,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: status.onDanger,
                  ),
                ),
                const SizedBox(height: RkSpace.s3),
                Text(
                  l10n.ceremonyMismatchCauses,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: status.onDanger,
                  ),
                ),
                const SizedBox(height: RkSpace.s3),
                Text(
                  // The one reassurance that is true, and the reason it is
                  // true: the ceremony fails *before* any book key is wrapped
                  // (04 §8.2 🔒).
                  l10n.ceremonyMismatchNothingShared,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: status.onDanger,
                  ),
                ),
                const SizedBox(height: RkSpace.s3),
                Text(
                  // Says that retrying is not the path — without giving a
                  // retry control to say it with (04 §6.3 🔒).
                  l10n.ceremonyMismatchNextStep,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: status.onDanger,
                  ),
                ),
                const SizedBox(height: RkSpace.s4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      size: RkIcon.grid,
                      color: status.onDanger,
                    ),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(
                      child: Text(
                        l10n.ceremonyMismatchLogged,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: status.onDanger,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RkSpace.s8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: status.onDanger,
                    foregroundColor: status.danger,
                  ),
                  onPressed: onContactSupport,
                  child: Text(l10n.ceremonyMismatchSupport),
                ),
                const SizedBox(height: RkSpace.s3),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: status.onDanger),
                  onPressed: onClose ?? () => Navigator.maybePop(context),
                  child: Text(l10n.ceremonyMismatchClose),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
