// S12.1 Plans — comparison, annual saving, current plan marked, quota rows
// (13 §3.2 row S12.1, 08 §3.1 🔒, DESIGN-PACK §11 S12.1 🔒).
//
// 💰 **Not one number lives in this file.** Every price, quota and band comes
// from `tier_catalogue.dart`, in integer paise, and the annual saving is
// integer arithmetic there (CLAUDE.md rule 1: a float touching money is a
// bug). This screen formats and lays out; it does not compute money.
//
// 🔒 **iOS says less, and says it in Apple's terms** (08 §3.2, ADR
// 2026-09-05g §8): on [RkCheckoutChannel.inAppPurchase] there is no coupon
// field and no external payment link anywhere on the screen — the GST buyer
// is given the one sentence the ADR writes. Off iOS the coupon/GSTIN line
// names the checkout that will carry them.
//
// 🔒 **Above 15 members nobody is refused** (08 §2, ADR 2026-09-05g §14): a
// 40-trustee committee is told that the band is still being set, on this
// screen, instead of meeting a wall.
//
// ⛔ **No checkout and no dependency.** S12.2 needs the IAP package, which is
// an owner decision, so *Choose this plan* and *Extra members* render
// disabled-with-reason (07 §1 rule 6) rather than reaching for a payment
// sheet that does not exist.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../../../shared/widgets/rk_states.dart';
import '../entitlement_source.dart';
import '../subscription_copy.dart';
import '../tier_catalogue.dart';

/// S12.1 — the plan comparison.
class PlansScreen extends StatefulWidget {
  /// Creates the screen over [source] for [channel].
  const PlansScreen({
    super.key,
    required this.source,
    required this.channel,
    this.tiers = rkTiers,
  });

  /// Where the current-plan marking and the member count come from.
  final EntitlementSource source;

  /// iOS or gateway (08 §3.2 🔒).
  final RkCheckoutChannel channel;

  /// The catalogue. Injected so a test can pump one tier; production always
  /// takes 08 §2's whole table.
  final List<RkTier> tiers;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  /// Annual is the default — 08 §2 principle 2: monthly is the fallback.
  RkBillingCycle _cycle = RkBillingCycle.annual;
  Entitlement? _entitlement;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlansScreen old) {
    super.didUpdateWidget(old);
    // A new source is a new reading. Without this the State outlives the
    // widget (Flutter reuses it whenever type and position match) and the
    // screen would keep showing the last source's answer — which for a
    // subscription surface means showing one tenant's plan under another's
    // seam.
    if (old.source != widget.source) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final read = await widget.source.read();
      if (!mounted) return;
      setState(() {
        _entitlement = read;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.plansTitle)),
      body: SafeArea(child: _body(l10n)),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) return RkSkeleton(label: l10n.subscriptionLoading, rows: 6);
    final entitlement = _entitlement;
    if (_failed || entitlement == null) {
      return RkErrorState(
        text: l10n.subscriptionError,
        retryLabel: l10n.subscriptionActionRetry,
        onRetry: _load,
      );
    }
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        RkSpace.s8,
      ),
      children: [
        RkFitText(
          l10n.plansCycleLabel,
          style: text.bodySmall?.copyWith(color: status.muted),
        ),
        const SizedBox(height: RkSpace.s2),
        // A Wrap, not a Row: at 200 % the two labels need more than a
        // 360 px phone gives them side by side.
        Wrap(
          spacing: RkSpace.s2,
          runSpacing: RkSpace.s2,
          children: [
            for (final cycle in RkBillingCycle.values)
              ChoiceChip(
                selected: _cycle == cycle,
                onSelected: (_) => setState(() => _cycle = cycle),
                // A plain [Text], not [RkFitText]: a chip measures its label
                // with a dry layout and [RkFitText]'s LayoutBuilder cannot be
                // measured that way. Both labels are one short word, and
                // `expectTextFits` holds them to the same standard as the
                // rest of the screen.
                label: Text(switch (cycle) {
                  RkBillingCycle.monthly => l10n.plansCycleMonthly,
                  RkBillingCycle.annual => l10n.plansCycleAnnual,
                }),
              ),
          ],
        ),
        const SizedBox(height: RkSpace.s2),
        // 08 §3.1 🔒 — the toggle *shows the saving*. Shown on both sides of
        // the toggle: on Annual it names what is being saved, on Monthly it
        // names what is being given up, and it is the same true number.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.savings_outlined,
              size: RkIcon.grid,
              color: status.muted,
            ),
            const SizedBox(width: RkSpace.s1),
            Expanded(
              child: RkFitText(
                l10n.plansCycleSaving(rkAnnualSavingPercent),
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s4),
        for (final tier in widget.tiers) ...[
          _PlanCard(
            tier: tier,
            cycle: _cycle,
            current: tier.plan == entitlement.plan,
          ),
          const SizedBox(height: RkSpace.s3),
        ],
        // 08 §3.1 🔒 "optional add-on seats" — named, and honestly shut.
        RkRuledCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RkFitText(l10n.plansAddonSeatsTitle, style: text.bodyLarge),
              const SizedBox(height: RkSpace.s1),
              _Reason(l10n.plansAddonSeatsReason),
            ],
          ),
        ),
        if (entitlement.aboveLargestBand) ...[
          const SizedBox(height: RkSpace.s3),
          RkRuledCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: RkIcon.grid,
                  color: status.info,
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: RkFitText(l10n.plansLargeOrg, style: text.bodyMedium),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: RkSpace.s4),
        RkFitText(switch (widget.channel) {
          RkCheckoutChannel.inAppPurchase => l10n.plansGstIos,
          RkCheckoutChannel.gateway => l10n.plansGstGateway,
        }, style: text.bodySmall?.copyWith(color: status.muted)),
        const SizedBox(height: RkSpace.s4),
        // DESIGN-PACK §11 (S12.1) 🔒 closes the screen with this sentence.
        RkFitText(l10n.plansNeverLocked, style: text.bodyMedium),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.tier,
    required this.cycle,
    required this.current,
  });

  final RkTier tier;
  final RkBillingCycle cycle;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final storage = rkStorageOf(tier.limits.tenantBytes ?? 0);
    final price = tier.isFree
        ? l10n.plansPriceFree
        : switch (cycle) {
            RkBillingCycle.monthly => l10n.plansPriceMonth(
              formatPaise(tier.monthlyPaise, locale: locale),
            ),
            RkBillingCycle.annual => l10n.plansPriceYear(
              formatPaise(tier.annualPaise, locale: locale),
            ),
          };
    return RkRuledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(tier.plan.name(l10n), style: text.titleLarge),
          if (current || tier.popular) ...[
            const SizedBox(height: RkSpace.s1),
            Wrap(
              spacing: RkSpace.s2,
              runSpacing: RkSpace.s1,
              children: [
                // Badges are icon + word, never a tint alone (07 §1 rule 3).
                if (current)
                  _Badge(
                    icon: Icons.check_circle_outline,
                    label: l10n.plansCurrent,
                    tint: status.success,
                  ),
                if (tier.popular)
                  _Badge(
                    icon: Icons.star_outline,
                    label: l10n.plansPopular,
                    tint: status.info,
                  ),
              ],
            ),
          ],
          const SizedBox(height: RkSpace.s2),
          RkFitText(price, style: text.titleMedium),
          const SizedBox(height: RkSpace.s3),
          _Included(l10n.plansLimitMembers(tier.limits.members ?? 0)),
          _Included(
            tier.limits.businessBooks == null
                ? l10n.plansLimitBooksUnlimited
                : l10n.plansLimitBooks(tier.limits.businessBooks!),
          ),
          _Included(l10n.plansLimitDevices(tier.limits.devices ?? 0)),
          _Included(
            storage.gigabytes
                ? l10n.plansLimitStorageGb(storage.amount)
                : l10n.plansLimitStorageMb(storage.amount),
          ),
          _Included(
            tier.isFree
                ? l10n.plansLimitExportsWatermarked
                : l10n.plansLimitExportsClean,
          ),
          const SizedBox(height: RkSpace.s3),
          SizedBox(
            width: double.infinity,
            // Disabled, and the reason is written under it (13 §4.3):
            // S12.2 Checkout needs the IAP package, an owner decision.
            child: FilledButton(
              onPressed: null,
              child: RkFitText(l10n.plansChoose),
            ),
          ),
          const SizedBox(height: RkSpace.s1),
          _Reason(l10n.plansChooseReason),
        ],
      ),
    );
  }
}

/// One quota line, in plain words (DESIGN-PACK §11 S12.1 🔒: "not a spec
/// table").
class _Included extends StatelessWidget {
  const _Included(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: RkSpace.s1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check,
          size: RkIcon.grid,
          color: RkStatusColors.of(context).muted,
        ),
        const SizedBox(width: RkSpace.s1),
        Expanded(
          child: RkFitText(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

/// A badge: icon + word, so grayscale loses nothing.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.tint});

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: RkIcon.grid, color: tint),
      const SizedBox(width: RkSpace.s1),
      // Flexible, not bare: a badge sits in a [Wrap] whose run width is the
      // card, and at 200 % *ਪ੍ਰਚਲਿਤ* beside its icon asks for more than the
      // run has. Without this the Row overflows its own line by a few pixels
      // — silently in release, loudly in a test.
      Flexible(
        child: RkFitText(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

/// Why something is shut — a clock icon paired with the sentence.
class _Reason extends StatelessWidget {
  const _Reason(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.schedule, size: 14, color: status.muted),
        const SizedBox(width: RkSpace.s1),
        Expanded(
          child: RkFitText(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: status.muted),
          ),
        ),
      ],
    );
  }
}
