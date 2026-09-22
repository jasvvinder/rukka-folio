// S12.4 Payment problem — the **dunning** grace with its countdown, what
// changes when it ends, Retry and Change payment method (13 §3.2 row S12.4,
// 07 §20 🔒, 08 §3 🔒, DESIGN-PACK §11 S12.4 🔒).
//
// 🔒 **Two graces, two copies.** This screen is the *dunning* grace only —
// tenant-wide, server-declared, 7 days from `period_end` (ADR 2026-09-05g §4).
// Reached in any other state it says so plainly and shows **no countdown**.
// Reached in **offline grace** it never uses the lapse words: an off-network
// phone has not lapsed and the server has not said it has, so `payment.none.*`
// is deliberately free of *ended* and *lapsed* and the state chip carries the
// offline-grace words of `subscription_copy.dart`.
//
// 🔒 **The clock is injected.** `now` is a parameter; nothing in this file or
// in `dunning_grace.dart` calls `DateTime.now()`. ADR 2026-09-05g §4's clock
// floor — `max(local, highest server timestamp seen)` — is the server's rule,
// and the countdown here is a rendering of two dates it was handed.
//
// 🔒 **The grace blocks nothing.** Entry carries on while a payment is
// retried; that is what the grace *is* ([EntitlementState.blocksEntry] is
// false for it). So the screen states what changes **when the time is up**,
// in the future tense, and never as something already lost.
//
// ⛔ **No payment channel.** ADR 2026-09-05g §8 rules *which* channel per
// platform, but no gateway SDK and no IAP package is in this app (PLAN desk
// item 11), so *Change payment method* is disabled-with-reason and *Retry*
// goes through [SubscriptionCommands], whose shipped implementation answers
// [RkCommandUnavailable] — shown as a reason, never as a silent no-op.
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
import '../dunning_grace.dart';
import '../entitlement_source.dart';
import '../subscription_commands.dart';
import '../subscription_copy.dart';
import '../widgets/subscription_action.dart';

/// S12.4 — the dunning grace.
class PaymentProblemScreen extends StatefulWidget {
  /// Creates the screen.
  const PaymentProblemScreen({
    super.key,
    required this.source,
    required this.commands,
    required this.now,
    this.onOpenPlans,
  });

  /// Where the entitlement reading comes from.
  final EntitlementSource source;

  /// The retry command's seam.
  final SubscriptionCommands commands;

  /// The injected clock (07 §1; CLAUDE.md rule 3's spirit in the UI layer —
  /// a screen never reads the wall clock itself).
  final DateTime Function() now;

  /// → S12.1 Plans, the way forward from the read-only banner.
  final VoidCallback? onOpenPlans;

  @override
  State<PaymentProblemScreen> createState() => _PaymentProblemScreenState();
}

class _PaymentProblemScreenState extends State<PaymentProblemScreen> {
  Entitlement? _entitlement;
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;
  RkCommandOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PaymentProblemScreen old) {
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _retry() async {
    if (_sending) return;
    setState(() => _sending = true);
    final outcome = await widget.commands.retryPayment();
    if (!mounted) return;
    setState(() {
      _sending = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.paymentTitle)),
      body: SafeArea(child: _body(l10n)),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) return RkSkeleton(label: l10n.subscriptionLoading, rows: 4);
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
      now: widget.now,
      outcome: _outcome,
      onRetryPayment: _retry,
      onOpenPlans: widget.onOpenPlans,
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.entitlement,
    required this.now,
    required this.outcome,
    required this.onRetryPayment,
    required this.onOpenPlans,
  });

  final Entitlement entitlement;
  final DateTime Function() now;
  final RkCommandOutcome? outcome;
  final VoidCallback onRetryPayment;
  final VoidCallback? onOpenPlans;

  @override
  Widget build(BuildContext context) {
    final state = entitlement.state;
    // 🔒 The dunning grace and nothing else. Every other state — including
    // offline grace, which is a *different* grace — takes the quiet branch.
    final dunning = state == EntitlementState.dunningGrace;
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
              onAction: restriction == RkRestrictionKind.offlineGrace
                  ? null
                  : onOpenPlans,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: dunning
              ? _Dunning(
                  entitlement: entitlement,
                  now: now,
                  outcome: outcome,
                  onRetryPayment: onRetryPayment,
                )
              : _NoProblem(state: state),
        ),
      ],
    );
  }
}

/// The dunning grace itself: headline, countdown, what changes, the two
/// actions.
class _Dunning extends StatelessWidget {
  const _Dunning({
    required this.entitlement,
    required this.now,
    required this.outcome,
    required this.onRetryPayment,
  });

  final Entitlement entitlement;
  final DateTime Function() now;
  final RkCommandOutcome? outcome;
  final VoidCallback onRetryPayment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final periodEnd = entitlement.periodEnd;
    final outcome = this.outcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RkRuledCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SubscriptionNotice(
                text: l10n.paymentHeadline,
                kind: SubscriptionNoticeKind.problem,
              ),
              // The countdown. A reading with no `period_end` has no window
              // to count, so the screen simply omits the line rather than
              // invent a date (07 §1 rule 12 — never a made-up figure).
              if (periodEnd != null) ...[
                const SizedBox(height: RkSpace.s3),
                Semantics(
                  label: l10n.paymentDaysLeft(
                    rkDunningDaysLeft(periodEnd: periodEnd, now: now()),
                  ),
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: RkIcon.grid,
                          color: status.warning,
                        ),
                        const SizedBox(width: RkSpace.s2),
                        Expanded(
                          child: RkFitText(
                            l10n.paymentDaysLeft(
                              rkDunningDaysLeft(
                                periodEnd: periodEnd,
                                now: now(),
                              ),
                            ),
                            style: text.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: RkSpace.s1),
                RkFitText(
                  formatLedgerDate(
                    localDateOf(rkDunningEndsAt(periodEnd)),
                    strings: l10n,
                  ),
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: RkSpace.s4),
        RkRuledCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RkFitText(l10n.paymentEndsLabel, style: text.titleMedium),
              const SizedBox(height: RkSpace.s2),
              // 🔒 Entry stops; reading, exporting and closing carry on
              // (08 §1 principle 4, 08 §3).
              RkFitText(l10n.paymentEndsBody, style: text.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: RkSpace.s4),
        if (outcome is RkCommandDone) ...[
          SubscriptionNotice(
            text: l10n.paymentRetryDone,
            kind: SubscriptionNoticeKind.done,
          ),
          const SizedBox(height: RkSpace.s3),
        ],
        if (outcome is RkCommandFailed) ...[
          SubscriptionNotice(
            text: l10n.paymentRetryFailed,
            kind: SubscriptionNoticeKind.problem,
          ),
          const SizedBox(height: RkSpace.s3),
        ],
        // 🔒 Unavailable shuts the button *and says why*; failure leaves it
        // live so the same button is the retry (08 §3.1).
        if (outcome is RkCommandUnavailable)
          SubscriptionAction.shut(
            label: l10n.paymentRetry,
            reason: l10n.paymentRetryUnavailable,
          )
        else
          SubscriptionAction(
            label: l10n.paymentRetry,
            onPressed: onRetryPayment,
          ),
        const SizedBox(height: RkSpace.s3),
        // ⛔ No channel is chosen, so there is no other method to offer.
        SubscriptionAction.shut(
          label: l10n.paymentChangeMethod,
          reason: l10n.paymentChangeMethodReason,
          emphasis: SubscriptionEmphasis.secondary,
        ),
      ],
    );
  }
}

/// Every state that is not the dunning grace — including offline grace, whose
/// words are never the lapse words.
class _NoProblem extends StatelessWidget {
  const _NoProblem({required this.state});

  final EntitlementState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return RkRuledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(l10n.paymentNoneTitle, style: text.titleMedium),
          const SizedBox(height: RkSpace.s2),
          RkFitText(l10n.paymentNoneBody, style: text.bodyMedium),
          const SizedBox(height: RkSpace.s3),
          // The state in its own words and icon, so the reader still learns
          // where they stand (colour never alone, 07 §1 rule 3).
          Semantics(
            label: state.label(l10n),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    state.icon,
                    size: RkIcon.grid,
                    color: state.tint(status),
                  ),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: RkFitText(state.label(l10n), style: text.bodyLarge),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
