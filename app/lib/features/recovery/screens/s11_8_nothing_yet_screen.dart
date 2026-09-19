// S11.8 — Recovery, nothing worked **yet** (13 §3.2 row S11.8, design R2.5 🔒,
// 04 §7.6 🔒, 06 §5).
//
// The screen a person reaches only when every rung has failed, and the one
// place in the product where the temptation to be either falsely reassuring or
// falsely final is strongest. The pack rules it 🔒 and this file obeys it
// literally:
//
//   * the heading is *"We can't open your private book on this phone yet."* —
//     the word **yet** is the whole design;
//   * three bordered rows, green · amber · grey, each with an icon and a
//     status **word** so the tint is never the only carrier (07 §1 rule 3 🔒);
//   * the family and business books are **restorable now**, and that row
//     carries the screen's single primary button;
//   * the private book is **still sealed on our server, exactly as you left
//     it** — which is true: the ciphertext never left (04 §7.6 🔒) — with the
//     two keys stated as things that will still work *today, next week or
//     next year*;
//   * the readable copy as a way to restart from closing balances.
//
// 🔒 What this screen must never say: that the data is destroyed (it is not),
// or "contact support" (support cannot open it either — 04 §1, 06 §8). There
// is no retry loop, because there is nothing here to retry: the way back in is
// an Apple/Google account or a sheet, and neither is a button.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../widgets/recovery_parts.dart';

/// The honest empty-vault screen.
class NothingWorkedYetScreen extends StatelessWidget {
  /// Creates the screen.
  const NothingWorkedYetScreen({super.key, this.onContinue});

  /// Taken by the one primary button: set this phone up, so the family can
  /// verify the person again and the shared books open (06 §5).
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s8,
                RkSpace.gutter,
                RkSpace.s4,
              ),
              child: RkFitText(
                l10n.recoveryNothingTitle,
                style: text.headlineSmall,
              ),
            ),
            // Green — and the only row with an action, per the pack.
            RecoveryStatusCard(
              tone: status.success,
              icon: Icons.check_circle_outline,
              status: l10n.recoveryNothingFamilyStatus,
              title: l10n.recoveryNothingFamilyTitle,
              body: l10n.recoveryNothingFamilyBody,
              action: l10n.recoveryNothingFamilyAction,
              onAction: onContinue,
            ),
            // Amber — sealed, which is not the same word as lost.
            RecoveryStatusCard(
              tone: status.pending,
              icon: Icons.lock_outline,
              status: l10n.recoveryNothingPrivateStatus,
              title: l10n.recoveryNothingPrivateTitle,
              body: l10n.recoveryNothingPrivateBody,
              extra: [
                const SizedBox(height: RkSpace.s3),
                RkFitText(
                  l10n.recoveryNothingPrivateKeys,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: RkSpace.s2),
                _Bullet(text: l10n.recoveryNothingPrivateKeyPlatform),
                const SizedBox(height: RkSpace.s1),
                _Bullet(text: l10n.recoveryNothingPrivateKeySheet),
              ],
            ),
            // Grey — a record rather than a restore (04 §7.6 table row 2).
            RecoveryStatusCard(
              tone: status.muted,
              icon: Icons.description_outlined,
              status: l10n.recoveryNothingReadableStatus,
              title: l10n.recoveryNothingReadableTitle,
              body: l10n.recoveryNothingReadableBody,
            ),
            const SizedBox(height: RkSpace.s8),
          ],
        ),
      ),
    );
  }
}

/// One of the private book's two keys, as a thing to do.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: RkSpace.s1),
          child: Icon(
            Icons.arrow_forward,
            size: RkIcon.grid - RkSpace.s2,
            color: status.muted,
          ),
        ),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: RkFitText(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
