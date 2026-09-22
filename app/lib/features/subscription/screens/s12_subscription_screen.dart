// S12 Subscription — plan, renewal, entitlement state (13 §3.2 row S12,
// 07 §20 🔒).
//
// The screen renders a **reading**, never a judgement: `EntitlementSource`
// hands it a resolved [Entitlement] and this file decides nothing about
// lapsing, clocks or grace windows. That is deliberate — ADR 2026-09-05g §4's
// clock floor (`max(local, highest server timestamp seen)`) is the server's
// rule, and a screen that worked a lapse out from the phone's clock would be
// the exact defect the ADR forbids.
//
// 🔒 **Two graces, two copies.** Read-only and offline grace both raise the
// shared S12.5 banner, but through [EntitlementStateCopy.restriction], which
// maps only the server-declared lapse to [RkRestrictionKind.readOnly]. An
// off-network phone reads *Connect once to keep entering* and never meets the
// lapse copy.
//
// 🔒 **Read-only hides nothing.** 08 §1 — *lapsed ≠ locked* — so the plan, the
// renewal date and the member count are rendered in every state; the banner
// is added above them, never in place of them.
//
// Doors: S12.1 Plans, S12.3 Manage, S12.4 Payment problem and S12.6 Invoices
// are live. **S12.5 Read-only mode stays a row**: it is the global banner plus
// the blocked-entry sheet (13 §3.2 — scope `global`), which this screen
// already raises through [RkRestrictionBanner], not a page to push. It renders
// disabled-with-reason (07 §1 rule 6) rather than vanishing, so the catalogue
// row is still accounted for on screen.
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
import '../subscription_copy.dart';
import '../widgets/subscription_row.dart';

/// S12 — the subscription hub.
class SubscriptionScreen extends StatefulWidget {
  /// Creates the screen over [source].
  const SubscriptionScreen({
    super.key,
    required this.source,
    this.onOpenPlans,
    this.onOpenManage,
    this.onOpenPayment,
    this.onOpenInvoices,
    this.onExport,
  });

  /// Where the entitlement reading comes from.
  final EntitlementSource source;

  /// → S12.1 Plans. Null leaves the row inert in a test pump; the route
  /// always supplies it.
  final VoidCallback? onOpenPlans;

  /// → S12.3 Manage subscription.
  final VoidCallback? onOpenManage;

  /// → S12.4 Payment problem — the dunning grace (08 §3 🔒).
  final VoidCallback? onOpenPayment;

  /// → S12.6 Invoices.
  final VoidCallback? onOpenInvoices;

  /// Export — offered on the read-only banner and **never** blocked (08 §1 🔒).
  /// Null where the surface has no export wired yet.
  final VoidCallback? onExport;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  Entitlement? _entitlement;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SubscriptionScreen old) {
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
      // A failed **read** is not a lapse: the error copy says the plan could
      // not be read, never that it ended (07 §1 rule 12).
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
      appBar: AppBar(title: Text(l10n.subscriptionTitle)),
      body: SafeArea(child: _body(l10n)),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) return RkSkeleton(label: l10n.subscriptionLoading, rows: 5);
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
      onOpenPlans: widget.onOpenPlans,
      onOpenManage: widget.onOpenManage,
      onOpenPayment: widget.onOpenPayment,
      onOpenInvoices: widget.onOpenInvoices,
      onExport: widget.onExport,
      onRetry: _load,
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.entitlement,
    required this.onOpenPlans,
    required this.onOpenManage,
    required this.onOpenPayment,
    required this.onOpenInvoices,
    required this.onExport,
    required this.onRetry,
  });

  final Entitlement entitlement;
  final VoidCallback? onOpenPlans;
  final VoidCallback? onOpenManage;
  final VoidCallback? onOpenPayment;
  final VoidCallback? onOpenInvoices;
  final VoidCallback? onExport;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = entitlement.state;
    final restriction = state.restriction;
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
              // Read-only's way forward is Renew → S12.1; offline grace's is
              // one more try at the server, never an upgrade prompt (ADR
              // 2026-09-05g §4).
              onAction: restriction == RkRestrictionKind.offlineGrace
                  ? onRetry
                  : onOpenPlans,
              onExport: onExport,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: RkRuledCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RkFitText(
                  l10n.subscriptionPlanLabel,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: RkStatusColors.of(context).muted),
                ),
                const SizedBox(height: RkSpace.s1),
                RkFitText(
                  entitlement.plan.name(l10n),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: RkSpace.s2),
                _StateChip(state: state),
                if (state.body(l10n) != null) ...[
                  const SizedBox(height: RkSpace.s2),
                  RkFitText(
                    state.body(l10n)!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: RkSpace.s4),
                // Figures stay on screen in every state — read-only hides
                // nothing (08 §1 🔒).
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
        SubscriptionRow(
          title: l10n.subscriptionRowPlansTitle,
          subtitle: l10n.subscriptionRowPlansSubtitle,
          onTap: onOpenPlans,
        ),
        SubscriptionRow(
          title: l10n.subscriptionRowManageTitle,
          subtitle: l10n.subscriptionRowManageSubtitle,
          onTap: onOpenManage,
        ),
        SubscriptionRow(
          title: l10n.subscriptionRowPaymentTitle,
          subtitle: l10n.subscriptionRowPaymentSubtitle,
          onTap: onOpenPayment,
        ),
        // S12.5 is the global banner + blocked-entry sheet, not a page: the
        // row stays, disabled-with-reason (13 §3.2, 07 §1 rule 6).
        SubscriptionDisabledRow(
          title: l10n.subscriptionRowReadOnlyTitle,
          reason: l10n.subscriptionRowReadOnlyReason,
        ),
        SubscriptionRow(
          title: l10n.subscriptionRowInvoicesTitle,
          subtitle: l10n.subscriptionRowInvoicesSubtitle,
          onTap: onOpenInvoices,
        ),
      ],
    );
  }
}

/// The entitlement state as icon + word (colour never alone, 07 §1 rule 3).
class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final EntitlementState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Semantics(
      label: state.label(l10n),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(state.icon, size: RkIcon.grid, color: state.tint(status)),
            const SizedBox(width: RkSpace.s1),
            Expanded(
              child: RkFitText(
                state.label(l10n),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
