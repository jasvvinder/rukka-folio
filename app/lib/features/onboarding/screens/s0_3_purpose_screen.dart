// S0.3 Purpose (13 §3.2 row S0.3, 07 §3.1 step 3, 07 §3.1.1 🔒 — the purpose
// card branches the setup), as amended by ADR 2026-10-04c: **four** illustrated
// cards — Myself · My business · My family · Our trust — one per entity type
// (Individual · Business · Family · Trust, ADR 2026-09-25 §5). *My business*
// covers any trade, one or more: it is the former *My businesses* branch, and
// S0.6c *Add another business?* asks the count. Selecting a card records the
// branch and hands it straight to the caller — this screen does not itself
// decide what O6* branch runs next (07 §3.1.1's table), it only names which
// one was chosen.
//
// Layout (ADR 2026-10-04c §2, owner 4 Oct 2026): below the `medium` breakpoint
// (`layout.breakpoint.medium`, 600 logical px — every phone) a single column of
// four full-width cards; at `medium` and wider (an iPad, either way up) a
// two-column grid, Myself · My business / My family · Our trust.
//
// 🔒 The trust card alone sets `tenant.type = organization` (07 §3.1,
// 07 §3.1.1). This screen only names the card; the seam that acts on it is
// `afterSetPin` (onboarding_routes.dart), which sends each card to its O6*
// branch, and that branch's opening host commits the book type — business
// (BusinessOpeningHost), family (FamilyOpeningHost), organization
// (TrustOpeningHost); *Myself* makes no further book. F1-04c-3 and F1-07-16
// drive that whole path through the router and read the committed type back.
//
// Cards are distinguishable without colour: icon + label + description
// together, never a fill or border colour alone (07 §1 rule 3).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/layout.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';

/// The four signup purposes (07 §3.1 step 3, ADR 2026-10-04c §1), in reading
/// order. The underlying tenant type stays the generic `organization` for
/// [trust] — this enum is UI-facing branch selection, not the ledger's own
/// type.
///
/// [businesses] is the one **My business** card (any trade, one or more);
/// the name is kept from the former *My businesses* card whose branch it
/// takes. The *shop* purpose is retired (ADR 2026-10-04c §1).
enum OnboardingPurpose { myself, businesses, family, trust }

/// The key each card carries, so a test can find a card by purpose.
Key purposeCardKey(OnboardingPurpose purpose) =>
    ValueKey('onboarding.purpose.card.${purpose.name}');

extension OnboardingPurposeCopy on OnboardingPurpose {
  String label(AppLocalizations l10n) => switch (this) {
    OnboardingPurpose.myself => l10n.onboardingPurposeCardMyselfLabel,
    OnboardingPurpose.businesses => l10n.onboardingPurposeCardBusinessesLabel,
    OnboardingPurpose.family => l10n.onboardingPurposeCardFamilyLabel,
    OnboardingPurpose.trust => l10n.onboardingPurposeCardTrustLabel,
  };

  String description(AppLocalizations l10n) => switch (this) {
    OnboardingPurpose.myself => l10n.onboardingPurposeCardMyselfDescription,
    OnboardingPurpose.businesses =>
      l10n.onboardingPurposeCardBusinessesDescription,
    OnboardingPurpose.family => l10n.onboardingPurposeCardFamilyDescription,
    OnboardingPurpose.trust => l10n.onboardingPurposeCardTrustDescription,
  };

  IconData get icon => switch (this) {
    OnboardingPurpose.myself => Icons.person_outline,
    OnboardingPurpose.businesses => Icons.business_center_outlined,
    OnboardingPurpose.family => Icons.family_restroom_outlined,
    OnboardingPurpose.trust => Icons.account_balance_outlined,
  };
}

/// "What will you use this for?" (07 §3.1 step 3). Tapping a card selects it
/// and immediately hands the branch to [onSelected] — the 8-second-entry
/// ethos (07 §1 rule 1) means this screen asks nothing else before moving on.
class PurposeScreen extends StatelessWidget {
  const PurposeScreen({super.key, this.onSelected, this.debugDemoCard});

  /// Called with the chosen purpose the instant a card is tapped.
  final void Function(OnboardingPurpose purpose)? onSelected;

  /// DEBUG ONLY (owner-directed, 4 Oct 2026): the demo builder's card, drawn
  /// above the four. The route passes `demoPurposeCard(...)` from
  /// features/demo, which is null in a release build, with the demo switch
  /// off, or for a phone not on the demo roster — so in every real build
  /// this is null and the screen is exactly the four cards.
  final Widget? debugDemoCard;

  /// Whether the grid's two cards each fit their longest word at the scale
  /// actually in force.
  ///
  /// ADR 2026-10-04c §2 makes the grid the layout from `medium` up, and on
  /// every iPad viewport (744 px and wider) at 1.0, 1.3x and 200 % in
  /// EN/PA/HI it is (F1-04c-4). This is the floor under that rule, not a
  /// second rule: a word wider than half the window is something Flutter
  /// draws straight past the card edge without throwing, so where it would
  /// do that the cards stack instead of cutting a word (07 §1, 13 §4).
  /// Measured in this font at this scale, never taken from a text-scale
  /// threshold.
  ///
  /// ⚠️ SPEC: the one place this engages inside the tested range is the
  /// breakpoint's own edge — a 600 px window (a foldable or split-screen
  /// pane, not an iPad) at 200 %, where a card has 238 px and *My business*
  /// needs 257. The ADR did not consider that width at that scale; the
  /// conservative reading keeps every word whole. Raised to the owner.
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

    for (final purpose in OnboardingPurpose.values) {
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
    // ADR 2026-10-04c §2 rules this screen's columns by the window's
    // breakpoint (layout.dart's header keeps breakpoints for the shell; this
    // is the one ruled exception — S0.3 sits outside the shell, before any
    // book exists, so no shell decides it).
    final wide =
        RkLayout.forWidth(MediaQuery.sizeOf(context).width) !=
        RkBreakpoint.compact;
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
                if (debugDemoCard case final demo?) ...[
                  demo,
                  const SizedBox(height: RkSpace.s4),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    const cards = OnboardingPurpose.values;
                    if (wide && _gridFits(context, constraints.maxWidth)) {
                      // Myself · My business / My family · Our trust. Cards
                      // inside an [IntrinsicHeight] cannot use [RkFitText]
                      // (a [LayoutBuilder] refuses to report intrinsic
                      // dimensions); they do not need it — the words were
                      // measured to fit.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _gridRow(cards[0], cards[1]),
                          const SizedBox(height: RkSpace.s3),
                          _gridRow(cards[2], cards[3]),
                        ],
                      );
                    }
                    // A phone: four full-width cards, one under another.
                    // [RkFitText] closes whatever a compound word overruns.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, purpose) in cards.indexed) ...[
                          if (i > 0) const SizedBox(height: RkSpace.s3),
                          _PurposeCard(
                            purpose: purpose,
                            onTap: onSelected,
                            fit: true,
                          ),
                        ],
                      ],
                    );
                  },
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
    this.fit = false,
  });

  final OnboardingPurpose purpose;
  final void Function(OnboardingPurpose purpose)? onTap;

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
      key: purposeCardKey(purpose),
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
