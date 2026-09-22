// S12.3 Manage subscription — plan, renewal date, what is included, change,
// cancel (13 §3.2 row S12.3, 07 §20 🔒, DESIGN-PACK §11 S12.3 🔒).
//
// 🔒 **Cancel says what continues to work, before it is issued.** 08 §1
// principle 4 — *lapsed ≠ locked* — and 08 §3: *entry of new data is the only
// thing a lapse ever blocks*. The sentence sits beside the Cancel button, not
// behind a confirmation, so nobody has to commit to find out what they keep.
//
// 🔒 **On an Apple platform this screen does not cancel anything.** Apple is
// merchant of record on IAP (08 §3.2, ADR 2026-09-05g §8), so cancellation
// lives in the device's subscription settings; DESIGN-PACK §11 (S12.3) calls
// that a deep link, and there is **no URL launcher in this app** (PLAN desk
// item 11 — no dialer, no launcher package). The conservative reading is
// taken: the confirm renders **disabled-with-reason naming the exact place**
// (07 §1 rule 6), and [SubscriptionCommands.cancelAtPeriodEnd] is never
// called on iOS or macOS. The lane report carries the deep link as an owner
// item.
//
// 🔒 **Nothing is hidden once a cancellation is scheduled.** The plan, the
// renewal date and the member count stay exactly where they were; the
// scheduled date is added above them (08 §1 🔒 — read-only hides no figure,
// and neither does a pending cancel).
//
// ⚠️ SPEC — `cancel_at_period_end` is **not** a field of the entitlement token
// (ADR 2026-09-05g §1 lists `{tenant_id, plan, limits, period_end,
// grace_kind, iat, exp}`), so a cancellation scheduled on one run is not
// readable on the next until the subscription record arrives on the meta
// channel (05 §5). This screen therefore shows what it has just been told by
// [RkCommandDone.effectiveOn]; it never *infers* a pending cancel. Flagged in
// the lane report rather than invented here.
//
// No clock: the renewal date is a token field, and the cancellation date is
// one the channel states. Nothing here reads `DateTime.now()`.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_restriction.dart';
import '../../../shared/widgets/rk_restriction_copy.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../../../shared/widgets/rk_states.dart';
import '../entitlement_source.dart';
import '../subscription_commands.dart';
import '../subscription_copy.dart';
import '../tier_catalogue.dart';
import '../widgets/subscription_action.dart';
import '../widgets/subscription_row.dart';

/// S12.3 — manage the current subscription.
class ManageSubscriptionScreen extends StatefulWidget {
  /// Creates the screen.
  const ManageSubscriptionScreen({
    super.key,
    required this.source,
    required this.commands,
    required this.channel,
    this.onOpenPlans,
  });

  /// Where the plan, renewal date and member count come from.
  final EntitlementSource source;

  /// The cancel command's seam.
  final SubscriptionCommands commands;

  /// Which channel this platform buys through (08 §3.2 🔒). On
  /// [RkCheckoutChannel.inAppPurchase] cancellation is Apple's, not ours.
  final RkCheckoutChannel channel;

  /// → S12.1 Plans.
  final VoidCallback? onOpenPlans;

  @override
  State<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  Entitlement? _entitlement;
  bool _loading = true;
  bool _failed = false;

  /// Whether the confirmation block is open.
  bool _confirming = false;

  /// In flight — the confirm button is held while the channel is asked, so a
  /// double tap cannot send two cancellations.
  bool _sending = false;

  /// The outcome of the last cancel attempt, or null before any.
  RkCommandOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ManageSubscriptionScreen old) {
    super.didUpdateWidget(old);
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
      // A failed read is not a lapse: the copy says the plan could not be
      // read, never that it ended (07 §1 rule 12).
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _cancel() async {
    // One cancellation per tap: a second press while the first is in flight
    // would be a second command to the channel.
    if (_sending) return;
    setState(() => _sending = true);
    final outcome = await widget.commands.cancelAtPeriodEnd();
    if (!mounted) return;
    setState(() {
      _sending = false;
      _outcome = outcome;
      // Done closes the confirmation; a failure leaves it open so the same
      // button is there to press again (08 §3.1 🔒 — error + retry).
      if (outcome is RkCommandDone) _confirming = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageTitle)),
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
    return _Loaded(
      entitlement: entitlement,
      channel: widget.channel,
      confirming: _confirming,
      outcome: _outcome,
      onOpenPlans: widget.onOpenPlans,
      onStartCancel: () => setState(() => _confirming = true),
      onKeepPlan: () => setState(() => _confirming = false),
      onConfirmCancel: _cancel,
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.entitlement,
    required this.channel,
    required this.confirming,
    required this.outcome,
    required this.onOpenPlans,
    required this.onStartCancel,
    required this.onKeepPlan,
    required this.onConfirmCancel,
  });

  final Entitlement entitlement;
  final RkCheckoutChannel channel;
  final bool confirming;
  final RkCommandOutcome? outcome;
  final VoidCallback? onOpenPlans;
  final VoidCallback onStartCancel;
  final VoidCallback onKeepPlan;
  final VoidCallback onConfirmCancel;

  /// 🔒 On an Apple platform cancelling is Apple's (ADR 2026-09-05g §8).
  bool get _appleCancels => channel == RkCheckoutChannel.inAppPurchase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final restriction = entitlement.state.restriction;
    final done = outcome;
    final tier = rkTierFor(entitlement.plan);
    final storage = rkStorageOf(tier.limits.tenantBytes ?? 0);
    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s8),
      children: [
        if (restriction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              0,
            ),
            child: RkRestrictionBanner(
              kind: restriction,
              copy: restriction.copy(context),
              onAction: onOpenPlans,
            ),
          ),
        // The scheduled cancellation, added ABOVE the figures and never in
        // place of them (08 §1 🔒).
        if (done is RkCommandDone && done.effectiveOn != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              0,
            ),
            child: RkRuledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SubscriptionNotice(
                    text: l10n.manageCancelledTitle(
                      formatLedgerDate(
                        localDateOf(done.effectiveOn!),
                        strings: l10n,
                      ),
                    ),
                    kind: SubscriptionNoticeKind.info,
                  ),
                  const SizedBox(height: RkSpace.s2),
                  RkFitText(l10n.manageCancelledBody, style: text.bodyMedium),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: RkRuledCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Fact(
                  label: l10n.subscriptionPlanLabel,
                  value: entitlement.plan.name(l10n),
                ),
                const SizedBox(height: RkSpace.s3),
                _Fact(
                  label: l10n.subscriptionRenewalLabel,
                  value: entitlement.periodEnd == null
                      ? l10n.subscriptionRenewalNone
                      : formatLedgerDate(
                          localDateOf(entitlement.periodEnd!),
                          strings: l10n,
                        ),
                ),
                const SizedBox(height: RkSpace.s3),
                _Fact(
                  label: l10n.subscriptionMembersLabel,
                  value: entitlement.limits.members == null
                      ? l10n.subscriptionMembersValueUnlimited(
                          entitlement.activeMembers,
                        )
                      : l10n.subscriptionMembersValue(
                          entitlement.activeMembers,
                          entitlement.limits.members!,
                        ),
                ),
              ],
            ),
          ),
        ),
        // What is included — the tier catalogue's own quota lines, in plain
        // words. Not one number is written in this file.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
          child: RkRuledCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RkFitText(l10n.manageIncludedLabel, style: text.titleMedium),
                const SizedBox(height: RkSpace.s2),
                _Included(l10n.plansLimitMembers(tier.limits.members ?? 1)),
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
              ],
            ),
          ),
        ),
        const SizedBox(height: RkSpace.s2),
        SubscriptionRow(
          title: l10n.manageChangePlan,
          subtitle: l10n.manageChangePlanSubtitle,
          onTap: onOpenPlans,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s2,
            RkSpace.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔒 What continues to work — said before the decision, not
              // after it (08 §1 principle 4, DESIGN-PACK §11 S12.3).
              RkFitText(l10n.manageCancelWhatContinues, style: text.bodyMedium),
              const SizedBox(height: RkSpace.s2),
              if (!confirming)
                SubscriptionAction(
                  label: l10n.manageCancel,
                  emphasis: SubscriptionEmphasis.quiet,
                  onPressed: onStartCancel,
                )
              else
                _Confirm(
                  appleCancels: _appleCancels,
                  outcome: outcome,
                  onConfirmCancel: onConfirmCancel,
                  onKeepPlan: onKeepPlan,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The confirmation block — inline rather than a dialog, so it has the whole
/// page width at 200 % on a 360 px phone.
class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.appleCancels,
    required this.outcome,
    required this.onConfirmCancel,
    required this.onKeepPlan,
  });

  final bool appleCancels;
  final RkCommandOutcome? outcome;
  final VoidCallback onConfirmCancel;
  final VoidCallback onKeepPlan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final outcome = this.outcome;
    // 🔒 The confirm is shut on Apple platforms, and shut again once the
    // channel has said there is none — both with the reason written under it.
    final String? reason = appleCancels
        ? l10n.manageCancelIosReason
        : outcome is RkCommandUnavailable
        ? l10n.manageCancelUnavailable
        : null;
    return RkRuledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(l10n.manageCancelConfirmTitle, style: text.titleMedium),
          const SizedBox(height: RkSpace.s2),
          RkFitText(l10n.manageCancelConfirmBody, style: text.bodyMedium),
          if (outcome is RkCommandFailed) ...[
            const SizedBox(height: RkSpace.s3),
            SubscriptionNotice(
              text: l10n.manageCancelFailed,
              kind: SubscriptionNoticeKind.problem,
            ),
          ],
          const SizedBox(height: RkSpace.s3),
          if (reason != null)
            SubscriptionAction.shut(
              label: l10n.manageCancelConfirmAction,
              reason: reason,
            )
          else
            SubscriptionAction(
              label: l10n.manageCancelConfirmAction,
              onPressed: onConfirmCancel,
            ),
          const SizedBox(height: RkSpace.s1),
          // Always a way back out (07 §1 rule 6).
          SubscriptionAction(
            label: l10n.manageCancelConfirmKeep,
            emphasis: SubscriptionEmphasis.quiet,
            onPressed: onKeepPlan,
          ),
        ],
      ),
    );
  }
}

/// One quota line, in plain words.
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

/// A labelled figure, stacked so 200 % on a 360 px phone has room.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      label: '$label. $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            RkFitText(
              label,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
            const SizedBox(height: 2),
            RkFitText(value, style: text.bodyLarge),
          ],
        ),
      ),
    );
  }
}
