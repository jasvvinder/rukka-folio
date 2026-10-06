// S0.2b Found you · is your old phone with you? (13 §3.2 row S0.2b, ADR
// 2026-10-05c §3 🔒; canvas 1b L5). Reached after a correct code for a number
// that has books: from S0.2a on the *I'm new* door, straight from the code on
// the sign-in door (13 §5 F1b). Two ways on:
//
// * *Yes, it's with me* → S0.2c, where the old phone scans this phone's code
//   (04 §9.1 🔒). ⚠️ SPEC: own-device linking — S0.2c, S0.2d and the old
//   phone's *Add a phone* — is not built and not yet ruled for build (PLAN
//   desk SIGNIN2; `features/ceremony/ceremony_sessions.dart` fails closed on
//   it). The choice is therefore **disabled with its reason** (13 §4.3
//   disabled-with-reason), and the reason names the way that works today, so
//   it is never a dead end (07 §1 rule 6). The reason copy is a draft.
// * *No, it's lost or reset* → the S11.6 recovery fork (R2.1), whose own rules
//   stand (*Linking is instant — recovery takes 24 hours*, ADR 2026-09-05d §1).
//
// Nothing about any book or family is named here — the phone is not certified
// (ADR 2026-09-05d §2). ⚠️ SPEC: canvas 1b L5 greets by name; `otp/verify`
// does not carry it (see S0.2a), so the line is *Welcome back* and the avatar
// a glyph.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../widgets/sign_in_parts.dart';

/// At large text (07 §1 rule 9: up to 200 %) the avatar and the icon discs
/// step aside so the words keep the width — they repeat what the words say.
bool _large(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(RkSpace.s4) > RkSpace.s4 * 1.5;

/// The canvas's avatar on L5 (56 px).
const double _avatar = RkSpace.s12 + RkSpace.s2;

/// The canvas's icon disc in a choice card (40 px).
const double _disc = RkSpace.s10;

class FoundYouScreen extends StatelessWidget {
  const FoundYouScreen({
    super.key,
    required this.phone,
    required this.onNoOldPhone,
    this.onOldPhone,
    this.onBack,
  });

  /// E.164 number the code went to.
  final String phone;

  /// *No, it's lost or reset* → S11.6.
  final VoidCallback onNoOldPhone;

  /// *Yes, it's with me* → S0.2c. Null while own-device linking is not built
  /// (PLAN SIGNIN2): the choice then draws disabled with its reason.
  final VoidCallback? onOldPhone;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return AuthPage(
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (!_large(context)) ...[
                const AuthAvatar(size: _avatar),
                const SizedBox(width: RkSpace.s4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.authFoundYouWelcome,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      displayPhone(phone),
                      style: text.bodyLarge?.copyWith(
                        color: status.muted,
                        fontFeatures: RkType.tabular,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s5),
          Semantics(
            header: true,
            child: RkFitText(
              l10n.authFoundYouTitle,
              style: text.headlineMedium,
            ),
          ),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.authFoundYouBody,
            style: text.bodyLarge?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s6),
          _Choice(
            icon: Icons.smartphone_outlined,
            title: l10n.authFoundYouYes,
            subtitle: l10n.authFoundYouYesSub,
            onTap: onOldPhone,
          ),
          if (onOldPhone == null) ...[
            const SizedBox(height: RkSpace.s2),
            _Reason(text: l10n.authFoundYouYesUnavailable),
          ],
          const SizedBox(height: RkSpace.s3),
          _Choice(
            icon: Icons.smartphone_outlined,
            crossed: true,
            title: l10n.authFoundYouNo,
            subtitle: l10n.authFoundYouNoSub,
            onTap: onNoOldPhone,
          ),
        ],
      ),
    );
  }
}

/// A full-width choice card (canvas 1b L5): an icon disc, a title, a muted
/// second line and a chevron, on `surface` with a hairline edge. With no
/// [onTap] it draws in `locked` and reads as disabled to a screen reader.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.crossed = false,
  });

  final IconData icon;

  /// An x inside the phone (canvas 1b L5 *No, it's lost or reset*).
  final bool crossed;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final ink = enabled ? scheme.onSurface : status.locked;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RkRadius.lg),
      side: BorderSide(color: status.hairline),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: scheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RkSpace.s4,
              vertical: RkSpace.s6,
            ),
            child: Row(
              children: [
                if (!_large(context)) ...[
                  Container(
                    width: _disc,
                    height: _disc,
                    decoration: BoxDecoration(
                      color: status.sunk,
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          icon,
                          size: RkIcon.grid,
                          color: enabled ? scheme.primary : status.locked,
                        ),
                        if (crossed)
                          Icon(
                            Icons.close,
                            size: RkIcon.grid / 2,
                            color: enabled ? scheme.primary : status.locked,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: RkSpace.s4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: text.bodyMedium?.copyWith(
                          color: enabled ? status.muted : status.locked,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: RkSpace.s2),
                Icon(
                  enabled ? Icons.chevron_right : Icons.lock_outline,
                  size: RkIcon.grid - RkSpace.s1,
                  color: enabled ? status.muted : status.locked,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Why a choice is disabled (13 §4.3): an info glyph and the words, in
/// `muted` — never colour alone (07 §1 rule 3).
class _Reason extends StatelessWidget {
  const _Reason({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: RkSpace.s1 / 2),
          child: Icon(
            Icons.info_outline,
            size: RkIcon.grid - RkSpace.s1 * 2,
            color: status.muted,
          ),
        ),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: status.muted),
          ),
        ),
      ],
    );
  }
}
