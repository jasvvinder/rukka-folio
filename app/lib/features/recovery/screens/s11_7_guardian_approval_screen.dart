// S11.7 — the guardian's side (13 §3.2 row S11.7, design R2.3, 04 §7.3
// steps 2–3 and 7 🔒, ADR 2026-09-13c ruling 3 🔒).
//
// This one does not belong to the person recovering. It arrives on a
// **relative's** phone, out of the blue, from 13 §3.4's loud notification, and
// what it asks for is a security decision: re-seal your share of somebody
// else's master key to a phone you have never seen.
//
// The pack's instruction is therefore the screen's architecture: the caution
// *"Call them first to be sure it is really them"* **must be impossible to
// skip past**. Two things carry that here, and neither is a sentence somebody
// can scroll by:
//
//   1. The caution sits **above** the buttons and carries a tick the person
//      must set — a checkbox, not a dismissible warning, the same shape
//      ADR 2026-09-06 checklist 4 🔒 fixed for the other irreversible choice
//      in this feature.
//   2. **The scan is a condition, not a step.** ADR 2026-09-13c ruling 3 🔒
//      turns 04 §7.3 step 2's advice into a check: this phone scans the new
//      phone's code and the re-seal accepts only what matched. The seam throws
//      [RecoveryCandidateUnverified] if anything calls `approve` without it,
//      so the caution is unskippable in the **contract** and not merely in
//      this layout.
//
// *Not now* needs neither: refusing is always safe, and 04 §7.3 step 7 says a
// denial is simply reported back. Nothing here can be made harder than the
// safe answer.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/seams/recovery_ladder.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../widgets/recovery_parts.dart';

/// The approval that arrives on a trusted member's phone.
class GuardianApprovalScreen extends StatefulWidget {
  /// Creates the screen. [approvals] defaults to [GuardianApprovalsScope]'s.
  const GuardianApprovalScreen({
    super.key,
    required this.requestId,
    this.approvals,
    this.onCall,
    this.onDone,
  });

  /// Which request this is.
  final String requestId;

  /// The seam to ask.
  final GuardianApprovals? approvals;

  /// Places the call to the requester. Null when nothing can dial; the number
  /// is then shown instead of a control that would do nothing.
  final void Function(String phone)? onCall;

  /// Taken once the member has answered, either way.
  final VoidCallback? onDone;

  @override
  State<GuardianApprovalScreen> createState() => _GuardianApprovalScreenState();
}

/// Where the member has got to.
enum _Answer {
  /// Still deciding.
  none,

  /// Share re-sealed and sent.
  approved,

  /// Refused — nothing sent.
  declined,
}

class _GuardianApprovalScreenState extends State<GuardianApprovalScreen> {
  GuardianRecoveryAsk? _ask;
  bool _failed = false;
  bool _started = false;
  bool _busy = false;
  bool _acknowledged = false;
  RecoveryScanOutcome? _scan;
  _Answer _answer = _Answer.none;

  GuardianApprovals? get _seam =>
      widget.approvals ?? GuardianApprovalsScope.maybeOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(GuardianApprovalScreen old) {
    super.didUpdateWidget(old);
    if (widget.approvals != old.approvals ||
        widget.requestId != old.requestId) {
      _load();
    }
  }

  Future<void> _load() async {
    final seam = _seam;
    // Every check is reset with the request. An acknowledgement or a scan
    // belongs to **one** ask: carrying either across a reload — a new request
    // id, or a live seam installed over the fake — would let a tick made for
    // one person authorise another, which is exactly what
    // ADR 2026-09-13c ruling 3 🔒 exists to prevent.
    setState(() {
      _ask = null;
      _failed = false;
      _acknowledged = false;
      _scan = null;
      _busy = false;
      _answer = _Answer.none;
    });
    if (seam == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final ask = await seam.load(widget.requestId);
      if (mounted) setState(() => _ask = ask);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _scanCandidate() async {
    final seam = _seam;
    if (seam == null || _busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await seam.verifyCandidateByScan(widget.requestId);
      if (mounted) setState(() => _scan = outcome);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final seam = _seam;
    if (seam == null || _busy) return;
    setState(() => _busy = true);
    try {
      await seam.approve(widget.requestId);
      if (mounted) setState(() => _answer = _Answer.approved);
    } on RecoveryCandidateUnverified {
      // The contract refused what the layout should never have offered. The
      // honest result is the screen back in its unverified state, not a
      // silent success (ADR 2026-09-13c ruling 3 🔒).
      if (mounted) setState(() => _scan = null);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final seam = _seam;
    if (seam == null || _busy) return;
    setState(() => _busy = true);
    try {
      await seam.decline(widget.requestId);
      if (mounted) setState(() => _answer = _Answer.declined);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ask = _ask;
    return Scaffold(
      // Unlike the other recovery screens this one is reached from a
      // notification on a phone that already has books (13 §3.4), so there is
      // somewhere to go back to — and the close control uses the framework's
      // own localised label rather than a key this feature would have to
      // invent.
      appBar: widget.onDone == null
          ? null
          : AppBar(leading: CloseButton(onPressed: widget.onDone)),
      body: SafeArea(
        child: switch ((_failed, ask, _answer)) {
          (true, _, _) => RkErrorState(
            text: l10n.recoveryApproveError,
            retryLabel: l10n.recoveryApproveRetry,
            onRetry: _load,
          ),
          (false, null, _) => RkSkeleton(
            label: l10n.recoveryApproveLoading,
            rows: 4,
          ),
          (false, final a?, _Answer.approved) => _Answered(
            tone: RkStatusColors.of(context).success,
            icon: Icons.check_circle_outline,
            title: l10n.recoveryApproveApprovedTitle,
            body: l10n.recoveryApproveApprovedBody(a.requesterName),
          ),
          (false, final a?, _Answer.declined) => _Answered(
            tone: RkStatusColors.of(context).locked,
            icon: Icons.do_not_disturb_on_outlined,
            title: l10n.recoveryApproveDeclinedTitle,
            body: l10n.recoveryApproveDeclinedBody(a.requesterName),
          ),
          (false, final a?, _Answer.none) => _Review(
            ask: a,
            busy: _busy,
            acknowledged: _acknowledged,
            scan: _scan,
            onAcknowledged: (v) => setState(() => _acknowledged = v),
            onScan: _scanCandidate,
            onApprove: _approve,
            onDecline: _decline,
            onCall: widget.onCall,
          ),
        },
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({
    required this.ask,
    required this.busy,
    required this.acknowledged,
    required this.scan,
    required this.onAcknowledged,
    required this.onScan,
    required this.onApprove,
    required this.onDecline,
    required this.onCall,
  });

  final GuardianRecoveryAsk ask;
  final bool busy;
  final bool acknowledged;
  final RecoveryScanOutcome? scan;
  final ValueChanged<bool> onAcknowledged;
  final VoidCallback onScan;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  final void Function(String phone)? onCall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final verified = scan == RecoveryScanOutcome.verified;
    final unavailable = scan == RecoveryScanOutcome.unavailable;
    final mismatch = scan == RecoveryScanOutcome.mismatch;
    final phone = ask.requesterPhone;
    // Both checks, or no approval. The reason is picked for what is actually
    // missing, so a screen reader never hears a generic "dimmed".
    final blockedReason = unavailable
        ? l10n.recoveryApproveScanUnavailable
        : (verified && acknowledged ? null : l10n.recoveryApproveBlocked);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s8,
        RkSpace.gutter,
        RkSpace.s8,
      ),
      children: [
        RkFitText(
          l10n.recoveryApproveTitle(ask.requesterName),
          style: text.headlineSmall,
        ),
        const SizedBox(height: RkSpace.s4),
        RkFitText(
          l10n.recoveryApproveDevice(ask.newDeviceName),
          style: text.bodyMedium,
        ),
        const SizedBox(height: RkSpace.s3),
        RecoveryFingerprint(
          label: l10n.recoveryApproveFingerprint,
          value: ask.newDeviceFingerprint,
        ),
        const SizedBox(height: RkSpace.s6),
        // 🔒 The caution, above the buttons and never collapsible.
        RecoveryCautionCard(
          title: l10n.recoveryApproveCautionTitle,
          body: l10n.recoveryApproveCautionBody,
          ackLabel: l10n.recoveryApproveCautionAck(ask.requesterName),
          acknowledged: acknowledged,
          onAcknowledged: onAcknowledged,
          callLabel: phone == null
              ? null
              : l10n.recoveryApproveCall(ask.requesterName),
          onCall: phone == null || onCall == null ? null : () => onCall!(phone),
        ),
        if (phone != null && onCall == null) ...[
          const SizedBox(height: RkSpace.s2),
          // Nothing here can dial, so the number itself is on the screen and
          // the caution still works (07 §1 rule 6).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.phone_outlined,
                size: RkIcon.grid - RkSpace.s2,
                color: status.muted,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: RkFitText(
                  phone,
                  style: text.bodyMedium?.copyWith(color: status.muted),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: RkSpace.s6),
        // The second check (ADR 2026-09-13c ruling 3 🔒).
        RkFitText(l10n.recoveryApproveScanWhy, style: text.bodyMedium),
        const SizedBox(height: RkSpace.s3),
        if (unavailable)
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
                  l10n.recoveryApproveScanUnavailable,
                  style: text.bodyMedium?.copyWith(color: status.locked),
                ),
              ),
            ],
          )
        else if (verified)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline, color: status.success),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: RkFitText(
                  l10n.recoveryApproveScanDone,
                  style: text.bodyMedium?.copyWith(color: status.success),
                ),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: busy ? null : onScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: RkFitText(
              l10n.recoveryApproveScanAction,
              textAlign: TextAlign.center,
            ),
          ),
        if (mismatch) ...[
          const SizedBox(height: RkSpace.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.report_outlined, color: status.danger),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: RkFitText(
                  l10n.recoveryApproveScanMismatch,
                  style: text.bodyMedium?.copyWith(color: status.danger),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: RkSpace.s8),
        Semantics(
          button: true,
          enabled: blockedReason == null && !busy,
          hint: blockedReason,
          child: FilledButton(
            onPressed: blockedReason != null || busy ? null : onApprove,
            child: RkFitText(
              l10n.recoveryApproveApprove,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (blockedReason != null) ...[
          const SizedBox(height: RkSpace.s2),
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
                  blockedReason,
                  style: text.bodySmall?.copyWith(color: status.locked),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: RkSpace.s4),
        // *Not now* is never gated: refusing is always the safe answer.
        TextButton(
          onPressed: busy ? null : onDecline,
          child: RkFitText(
            l10n.recoveryApproveDecline,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _Answered extends StatelessWidget {
  const _Answered({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String body;

  /// No action: R2.3 draws none, and the member's part really is over. The
  /// close control in the bar is the whole way out.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(RkSpace.gutter),
    child: RecoveryStatusCard(
      tone: tone,
      icon: icon,
      status: title,
      title: title,
      body: body,
    ),
  );
}
