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
                Text(l10n.onboardingPurposeTitle, style: text.headlineMedium),
                const SizedBox(height: RkSpace.s6),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _PurposeCard(
                          purpose: _grid[0],
                          onTap: onSelected,
                        ),
                      ),
                      const SizedBox(width: RkSpace.s3),
                      Expanded(
                        child: _PurposeCard(
                          purpose: _grid[1],
                          onTap: onSelected,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: RkSpace.s3),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _PurposeCard(
                          purpose: _grid[2],
                          onTap: onSelected,
                        ),
                      ),
                      const SizedBox(width: RkSpace.s3),
                      Expanded(
                        child: _PurposeCard(
                          purpose: _grid[3],
                          onTap: onSelected,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: RkSpace.s3),
                // Full width beneath (07 §3.1 step 3): five does not divide
                // into a grid, and the trust label is the longest of the five.
                _PurposeCard(
                  purpose: OnboardingPurpose.trust,
                  onTap: onSelected,
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PurposeCard extends StatelessWidget {
  const _PurposeCard({
    required this.purpose,
    required this.onTap,
    this.fullWidth = false,
  });

  final OnboardingPurpose purpose;
  final void Function(OnboardingPurpose purpose)? onTap;
  final bool fullWidth;

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
              Text(label, style: text.titleMedium),
              const SizedBox(height: RkSpace.s1),
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
