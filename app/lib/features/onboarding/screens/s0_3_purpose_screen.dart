// S0.3 Purpose (13 §3.2 row S0.3, 07 §3.1 step 3, 07 §3.1.1 🔒 — the purpose
// card branches the setup). Five illustrated cards, 2x2 with the trust card
// full width beneath (the label is the longest and five does not divide into
// a grid). Selecting a card records the branch and hands it straight to the
// caller — this screen does not itself decide what O6* branch runs next
// (07 §3.1.1's table), it only names which one was chosen.
//
// 🔒 The trust card alone sets `tenant.type = organization` (07 §3.1,
// 07 §3.1.1) — [OnboardingPurpose.setsOrganizationTenant] is the single flag
// a caller reads to act on that; the actual tenant/book seeding is the O6*
// branch wizard, a later lane (out of scope here per the U1b brief).
//
// Cards are distinguishable without colour: icon + label + description
// together, never a fill or border colour alone (07 §1 rule 3).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';

/// The five signup purposes (07 §3.1 step 3). The underlying tenant type
/// stays the generic `organization` for [trust] — this enum is UI-facing
/// branch selection, not the ledger's own type.
enum OnboardingPurpose { myself, shop, businesses, family, trust }

extension OnboardingPurposeCopy on OnboardingPurpose {
  /// 🔒 07 §3.1 / 07 §3.1.1 — the trust card is the only one that sets
  /// `tenant.type = organization` (trustee role labels, mandatory cash
  /// denomination counting, gollak as `cash_collection`). Every other card
  /// stays a personal/business book.
  bool get setsOrganizationTenant => this == OnboardingPurpose.trust;

  String label(AppLocalizations l10n) => switch (this) {
    OnboardingPurpose.myself => l10n.onboardingPurposeCardMyselfLabel,
    OnboardingPurpose.shop => l10n.onboardingPurposeCardShopLabel,
    OnboardingPurpose.businesses => l10n.onboardingPurposeCardBusinessesLabel,
    OnboardingPurpose.family => l10n.onboardingPurposeCardFamilyLabel,
    OnboardingPurpose.trust => l10n.onboardingPurposeCardTrustLabel,
  };

  String description(AppLocalizations l10n) => switch (this) {
    OnboardingPurpose.myself => l10n.onboardingPurposeCardMyselfDescription,
    OnboardingPurpose.shop => l10n.onboardingPurposeCardShopDescription,
    OnboardingPurpose.businesses =>
      l10n.onboardingPurposeCardBusinessesDescription,
    OnboardingPurpose.family => l10n.onboardingPurposeCardFamilyDescription,
    OnboardingPurpose.trust => l10n.onboardingPurposeCardTrustDescription,
  };

  IconData get icon => switch (this) {
    OnboardingPurpose.myself => Icons.person_outline,
    OnboardingPurpose.shop => Icons.storefront_outlined,
    OnboardingPurpose.businesses => Icons.business_center_outlined,
    OnboardingPurpose.family => Icons.family_restroom_outlined,
    OnboardingPurpose.trust => Icons.account_balance_outlined,
  };
}

/// "What will you use this for?" (07 §3.1 step 3). Tapping a card selects it
/// and immediately hands the branch to [onSelected] — the 8-second-entry
/// ethos (07 §1 rule 1) means this screen asks nothing else before moving on.
class PurposeScreen extends StatelessWidget {
  const PurposeScreen({super.key, this.onSelected});

  /// Called with the chosen purpose the instant a card is tapped.
  final void Function(OnboardingPurpose purpose)? onSelected;

  static const _grid = [
    OnboardingPurpose.myself,
    OnboardingPurpose.shop,
    OnboardingPurpose.businesses,
    OnboardingPurpose.family,
  ];

  /// True when two cards fit side by side at the scale actually in force.
  ///
  /// The grid is 2x2 by design, but a card is barely a third of a phone
  /// wide, and at 130 % *businesses* alone needs 209 px of the 116 px a card
  /// has to give — Flutter draws such a word straight past the card edge
  /// without throwing (F1-07-16). So the choice between the grid and a
  /// single stacked column is **measured**, in this font at this scale,
  /// never taken from a text-scale threshold: a threshold cannot know how
  /// wide a word is in a font it has not measured (13 §4, U3g).
  static bool _gridFits(BuildContext context, double width) {
    if (!width.isFinite) return true;
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    // Two cards and the gap between them, less each card's own padding.
    final room = (width - RkSpace.s3) / 2 - RkSpace.s4 * 2;
    if (room <= 1) return false;
    double widest(String value, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textScaler: scaler,
        textDirection: direction,
        locale: locale,
      )..layout();
      final w = painter.minIntrinsicWidth;
      painter.dispose();
      return w;
    }

    for (final purpose in _grid) {
      if (widest(purpose.label(l10n), text.titleMedium) > room) return false;
      if (widest(purpose.description(l10n), text.bodySmall) > room) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.s6),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RkFitText(
                  l10n.onboardingPurposeTitle,
                  style: text.headlineMedium,
                ),
                const SizedBox(height: RkSpace.s6),
                LayoutBuilder(
                  builder: (context, constraints) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_gridFits(context, constraints.maxWidth)) ...[
                        // Cards inside an [IntrinsicHeight] cannot use
                        // [RkFitText]: a [LayoutBuilder] refuses to report
                        // intrinsic dimensions. They do not need it — this
                        // branch runs only where the words were measured to
                        // fit.
                        _gridRow(_grid[0], _grid[1]),
                        const SizedBox(height: RkSpace.s3),
                        _gridRow(_grid[2], _grid[3]),
                      ] else
                        // One per row: a card now has the whole width, and
                        // [RkFitText] closes whatever a compound word still
                        // overruns.
                        for (final purpose in _grid) ...[
                          _PurposeCard(
                            purpose: purpose,
                            onTap: onSelected,
                            fit: true,
                          ),
                          const SizedBox(height: RkSpace.s3),
                        ],
                      const SizedBox(height: RkSpace.s3),
                      // Full width beneath (07 §3.1 step 3): five does not
                      // divide into a grid, and the trust label is the
                      // longest of the five.
                      _PurposeCard(
                        purpose: OnboardingPurpose.trust,
                        onTap: onSelected,
                        fullWidth: true,
                        fit: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gridRow(OnboardingPurpose left, OnboardingPurpose right) =>
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _PurposeCard(purpose: left, onTap: onSelected),
            ),
            const SizedBox(width: RkSpace.s3),
            Expanded(
              child: _PurposeCard(purpose: right, onTap: onSelected),
            ),
          ],
        ),
      );
}

class _PurposeCard extends StatelessWidget {
  const _PurposeCard({
    required this.purpose,
    required this.onTap,
    this.fullWidth = false,
    this.fit = false,
  });

  final OnboardingPurpose purpose;
  final void Function(OnboardingPurpose purpose)? onTap;
  final bool fullWidth;

  /// Draw the words through [RkFitText]. Off inside an [IntrinsicHeight],
  /// which cannot ask a [LayoutBuilder] for an intrinsic dimension.
  final bool fit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final label = purpose.label(l10n);
    final description = purpose.description(l10n);
    return Semantics(
      button: true,
      label: '$label. $description',
      child: InkWell(
        onTap: () => onTap?.call(purpose),
        borderRadius: BorderRadius.circular(RkRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.all(RkSpace.s4),
          decoration: BoxDecoration(
            border: Border.all(color: status.hairline),
            borderRadius: BorderRadius.circular(RkRadius.md),
          ),
          child: Column(
            crossAxisAlignment: fullWidth
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(purpose.icon, size: RkIcon.grid),
              const SizedBox(height: RkSpace.s2),
              if (fit)
                RkFitText(label, style: text.titleMedium)
              else
                Text(label, style: text.titleMedium),
              const SizedBox(height: RkSpace.s1),
              if (fit)
                RkFitText(
                  description,
                  style: text.bodySmall?.copyWith(color: status.muted),
                )
              else
                Text(
                  description,
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
