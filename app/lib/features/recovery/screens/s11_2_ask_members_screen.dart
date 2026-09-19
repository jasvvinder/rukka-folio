// S11.2 — Recovery, ask your trusted members (13 §3.2 row S11.2, design R2.2,
// 04 §7.3 🔒, ADR 2026-09-05d §1, ADR 2026-09-06 §2, ADR 2026-09-13c).
//
// The live waiting screen. Somebody is standing at a shop counter with a new
// phone and nothing on it, calling their brother. It may be open for minutes,
// so the pack's instruction is the design constraint: **it must not feel
// stuck** — every row says where that person stands, by name, and the screen
// never shows a spinner.
//
// **The rows are real.** Migration 0010 stores one append-only row per member
// per decision and derives the tally from them, so "1 of 2 approvals" is
// counted here from named rows, never read off a counter. That is what lets
// the screen say *who*.
//
// **Two gates, in this order.**
//  1. The **recovery ceremony** (ADR 2026-09-13c ruling 1 🔒): this phone
//     scans the user's own key off a member's already-verified phone before
//     any key may be put back together. Ruling 2 🔒 makes it QR only — there
//     is deliberately no *enter code instead* here.
//     ⚠️ SPEC: the ADR fixes the ceremony "before 04 §7.3 step 4" but does not
//     say where on the screen it sits. It is drawn **first**, which is the
//     conservative reading: nothing about the attempt is shown, and nothing
//     can be reconstructed, until this phone has been pinned to a human. It
//     also falls on the same call the person is already making.
//  2. The **24 h wait** (ADR 2026-09-05d §1 🔒) when the account still has an
//     active phone. Stated as protection, with the hours left.
//
// **What this screen may never say.** 03 §2.2's `state` has no `denied`, so a
// request closed by three refusals and one closed by the 72 h clock are the
// same value (migration 0010, the ⚠️ SPEC on `rf.recovery_derive`). The closed
// copy therefore claims neither. The per-member rows *can* say what each
// person did, because those rows exist — and 04 §7.3 step 7 🔒 requires the
// requester be told about a refusal.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/money_format.dart' show groupIndian;
import '../../../shared/seams/recovery_ladder.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../widgets/recovery_parts.dart';

/// The waiting screen for rung 2.
class AskTrustedMembersScreen extends StatefulWidget {
  /// Creates the screen. [recovery] defaults to [GuardianRecoveryScope]'s.
  const AskTrustedMembersScreen({
    super.key,
    this.recovery,
    this.onBack,
    this.onCall,
  });

  /// The seam to ask.
  final GuardianRecovery? recovery;

  /// Back to the fork (S11.6) — the way out of every state that cannot go
  /// forward. 07 §1 rule 6 🔒: no dead ends.
  final VoidCallback? onBack;

  /// Places a call to one member. Null when nothing on this build can dial;
  /// the row then shows the number instead of a control that would do nothing.
  final void Function(TrustedApprover approver)? onCall;

  @override
  State<AskTrustedMembersScreen> createState() =>
      _AskTrustedMembersScreenState();
}

class _AskTrustedMembersScreenState extends State<AskTrustedMembersScreen> {
  RecoveryScanOutcome? _ceremony;
  GuardianRecoveryAttempt? _attempt;
  bool _failed = false;
  bool _started = false;
  bool _scanning = false;
  StreamSubscription<GuardianRecoveryAttempt>? _sub;

  GuardianRecovery? get _seam =>
      widget.recovery ?? GuardianRecoveryScope.maybeOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _listen();
    }
  }

  @override
  void didUpdateWidget(AskTrustedMembersScreen old) {
    super.didUpdateWidget(old);
    if (widget.recovery != old.recovery) _listen();
  }

  /// Subscribes to the attempt and reads it once.
  ///
  /// Like S11.6, the result is held in plain fields rather than handed to a
  /// `FutureBuilder`: a seam that fails synchronously would otherwise complete
  /// before any builder subscribed and surface as an unhandled framework
  /// error over a screen that is behaving correctly.
  Future<void> _listen() async {
    final seam = _seam;
    setState(() {
      _failed = false;
      _attempt = seam?.current;
    });
    if (seam == null) {
      setState(() => _failed = true);
      return;
    }
    await _sub?.cancel();
    _sub = seam.watch().listen((a) {
      if (mounted) setState(() => _attempt = a);
    });
    try {
      await seam.refresh();
      if (!mounted) return;
      setState(() => _attempt = seam.current ?? _attempt);
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _scan() async {
    final seam = _seam;
    if (seam == null || _scanning) return;
    setState(() => _scanning = true);
    try {
      final outcome = await seam.verifyOwnKeyByScan();
      if (!mounted) return;
      setState(() => _ceremony = outcome);
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: switch (_ceremony) {
          _ when _failed => RkErrorState(
            text: l10n.recoveryAskError,
            retryLabel: l10n.recoveryAskRetry,
            onRetry: _listen,
          ),
          null ||
          RecoveryScanOutcome.cancelled ||
          RecoveryScanOutcome.unavailable => _CeremonyStep(
            outcome: _ceremony,
            busy: _scanning,
            onScan: _scan,
            onBack: widget.onBack,
          ),
          RecoveryScanOutcome.mismatch => _Mismatch(onBack: widget.onBack),
          RecoveryScanOutcome.verified =>
            _attempt == null
                ? _Loading(label: l10n.recoveryAskLoading)
                : _Waiting(
                    attempt: _attempt!,
                    onCall: widget.onCall,
                    onBack: widget.onBack,
                  ),
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(RkSpace.gutter),
        child: RkFitText(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
      Expanded(child: RkSkeleton(label: label, rows: 3)),
    ],
  );
}

/// Gate 1 — the recovery ceremony (ADR 2026-09-13c rulings 1 and 2 🔒).
class _CeremonyStep extends StatelessWidget {
  const _CeremonyStep({
    required this.outcome,
    required this.busy,
    required this.onScan,
    required this.onBack,
  });

  final RecoveryScanOutcome? outcome;
  final bool busy;
  final VoidCallback onScan;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final unavailable = outcome == RecoveryScanOutcome.unavailable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s8,
        RkSpace.gutter,
        RkSpace.s8,
      ),
      children: [
        RkFitText(l10n.recoveryAskScanTitle, style: text.headlineSmall),
        const SizedBox(height: RkSpace.s4),
        RkFitText(l10n.recoveryAskScanBody, style: text.bodyMedium),
        const SizedBox(height: RkSpace.s6),
        if (unavailable)
          // Disabled-with-reason (13 §4.3): the control stays, the reason is
          // stated in words beside a lock, and a way that works sits under it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: RkIcon.grid - RkSpace.s2,
                color: status.locked,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: RkFitText(
                  l10n.recoveryAskScanUnavailable,
                  style: text.bodyMedium?.copyWith(color: status.locked),
                ),
              ),
            ],
          )
        else
          Semantics(
            button: true,
            child: FilledButton.icon(
              onPressed: busy ? null : onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: RkFitText(
                l10n.recoveryAskScanAction,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (onBack != null) ...[
          const SizedBox(height: RkSpace.s4),
          TextButton(
            onPressed: onBack,
            child: RkFitText(l10n.recoveryAskBack, textAlign: TextAlign.center),
          ),
        ],
      ],
    );
  }
}

/// The ceremony failed to match.
///
/// ADR 2026-09-13c ruling 1 🔒: **hard fail, no override**. There is therefore
/// no *scan again* here — the one action offered is the honest way out, and a
/// person who scanned the wrong screen reaches it through the fork.
class _Mismatch extends StatelessWidget {
  const _Mismatch({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s8,
        RkSpace.gutter,
        RkSpace.s8,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.report_outlined, color: status.danger),
            const SizedBox(width: RkSpace.s2),
            Expanded(
              child: RkFitText(
                l10n.recoveryAskScanMismatch,
                style: text.bodyLarge?.copyWith(color: status.danger),
              ),
            ),
          ],
        ),
        if (onBack != null) ...[
          const SizedBox(height: RkSpace.s6),
          TextButton(
            onPressed: onBack,
            child: RkFitText(l10n.recoveryAskBack, textAlign: TextAlign.center),
          ),
        ],
      ],
    );
  }
}

/// Gate 2 and the pack's own screen: the live list.
class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.attempt,
    required this.onCall,
    required this.onBack,
  });

  final GuardianRecoveryAttempt attempt;
  final void Function(TrustedApprover approver)? onCall;
  final VoidCallback? onBack;

  String _stateText(AppLocalizations l10n, TrustedApproverState s) =>
      switch (s) {
        TrustedApproverState.approved => l10n.recoveryAskStateApproved,
        TrustedApproverState.waiting => l10n.recoveryAskStateWaiting,
        TrustedApproverState.notAsked => l10n.recoveryAskStateNotAsked,
        TrustedApproverState.declined => l10n.recoveryAskStateDeclined,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final now = RkScope.of(context).now();
    final sync = RkScope.of(context).sync;
    final restore = attempt.restore;
    final done = attempt.state == RecoveryAttemptState.approved;

    return StreamBuilder<SyncStatus>(
      stream: sync.status,
      initialData: sync.current,
      builder: (context, ss) {
        final offline = ss.data is Offline;
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s8,
                RkSpace.gutter,
                RkSpace.s3,
              ),
              child: RkFitText(
                done
                    ? l10n.recoveryAskDoneTitle
                    : l10n.recoveryAskTitle('${attempt.k}', '${attempt.n}'),
                style: text.headlineSmall,
              ),
            ),
            if (!done && !attempt.isClosed)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.gutter,
                  0,
                  RkSpace.gutter,
                  RkSpace.s3,
                ),
                child: RkFitText(
                  l10n.recoveryAskCallAdvice,
                  style: text.bodyMedium?.copyWith(color: status.muted),
                ),
              ),
            if (offline)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.gutter,
                  0,
                  RkSpace.gutter,
                  RkSpace.s3,
                ),
                // A quiet chip, never a blocking banner (07 §1 rule 7). It is
                // also true: the approvals are on the server, not lost.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: RkIcon.grid - RkSpace.s2,
                      color: status.muted,
                    ),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(
                      child: RkFitText(
                        l10n.recoveryAskOffline,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                0,
                RkSpace.gutter,
                RkSpace.s4,
              ),
              // Counted from the rows above, never from a counter column
              // (migration 0010 🔒).
              child: RkFitText(
                l10n.recoveryAskProgress(
                  '${attempt.approvals}',
                  '${attempt.k}',
                ),
                style: text.titleMedium,
              ),
            ),
            for (final a in attempt.approvers)
              TrustedApproverRow(
                approver: a,
                stateText: _stateText(l10n, a.state),
                waitingLabel: l10n.recoveryAskWaitingLabel(a.name),
                callLabel: l10n.recoveryAskCall,
                onCall: onCall,
              ),
            if (attempt.state == RecoveryAttemptState.waiting24h)
              Padding(
                padding: const EdgeInsets.all(RkSpace.gutter),
                child: RecoveryStatusCard(
                  tone: status.pending,
                  icon: Icons.schedule,
                  status: l10n.recoveryAskWait24Remaining(
                    _hoursLeft(attempt.waitUntil, now),
                  ),
                  title: l10n.recoveryAskWait24Title,
                  body: l10n.recoveryAskWait24Body,
                ),
              ),
            if (attempt.state == RecoveryAttemptState.expired)
              Padding(
                padding: const EdgeInsets.all(RkSpace.gutter),
                child: RecoveryStatusCard(
                  tone: status.locked,
                  icon: Icons.history_toggle_off,
                  status: l10n.recoveryAskClosedTitle,
                  title: l10n.recoveryAskClosedTitle,
                  body: l10n.recoveryAskClosedBody,
                  action: onBack == null ? null : l10n.recoveryAskBack,
                  onAction: onBack,
                ),
              ),
            if (attempt.state == RecoveryAttemptState.cancelled)
              Padding(
                padding: const EdgeInsets.all(RkSpace.gutter),
                child: RecoveryStatusCard(
                  tone: status.warning,
                  icon: Icons.phonelink_lock_outlined,
                  status: l10n.recoveryAskCancelledTitle,
                  title: l10n.recoveryAskCancelledTitle,
                  body: l10n.recoveryAskCancelledBody,
                  action: onBack == null ? null : l10n.recoveryAskBack,
                  onAction: onBack,
                ),
              ),
            if (done && restore != null)
              Padding(
                padding: const EdgeInsets.all(RkSpace.gutter),
                // R2.2's completed state: one calm line with a **count** over
                // the determinate rule. Never a percentage (11 §4.5 🔒).
                child: RecoveryLoaderRule(
                  value: restore.fraction,
                  countText: l10n.recoveryAskRestoring(
                    groupIndian('${restore.done}'),
                    groupIndian('${restore.total}'),
                  ),
                  semanticsLabel: l10n.recoveryAskRestoreLoader,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Whole hours between [now] and [until]; 0 when the wait is over or unknown.
///
/// Hours, not minutes: a ticking counter on a day-long wait reads as a
/// deadline the person could miss, and they cannot — the wait completes by
/// itself (ADR 2026-09-05d §1).
int _hoursLeft(DateTime? until, DateTime now) {
  if (until == null) return 0;
  final left = until.difference(now);
  return left.isNegative ? 0 : left.inHours;
}
