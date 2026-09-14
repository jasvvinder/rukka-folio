// S6.3 — the review surface the structural card opens (13 §3.2; 07 §26 🔒).
//
// The card in the Inbox already carries the 🔒 contract: what will change,
// quorum progress, Approve and Veto with reason. This surface is where an
// owner goes to *decide*: the same statement of the change, plus the rule in
// force for this request, who has signed so far, and when the 14-day window
// closes — all read off the engine's own outcome (02 §7.2.1, ADR 2026-09-14
// ruling 1 🔒), never recounted here.
//
// States (13 §4.3): loading skeleton · the request · gone (decided or cleared
// on another phone — never a blank screen) · error-with-retry · busy and
// failed-write on the card itself · the role variants of 13 §2.3.1, which the
// card states rather than hiding.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../structural_requests.dart';
import '../widgets/structural_card.dart';
import '../widgets/veto_sheet.dart';

/// The full-screen S6.3 review surface for one request.
class StructuralReviewScreen extends StatefulWidget {
  /// Creates the screen.
  const StructuralReviewScreen({
    super.key,
    required this.requestId,
    this.onDone,
  });

  /// Which request (the path parameter).
  final String requestId;

  /// Back to the Inbox — the one next action in every end state.
  final VoidCallback? onDone;

  @override
  State<StructuralReviewScreen> createState() => _StructuralReviewScreenState();
}

class _StructuralReviewScreenState extends State<StructuralReviewScreen> {
  bool _busy = false;
  bool _error = false;
  bool _loadError = false;
  StructuralResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && StructuralRequestsScope.of(context).current == null) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    final seam = StructuralRequestsScope.of(context);
    setState(() => _loadError = false);
    try {
      await seam.refresh();
    } on StructuralRequestFailure {
      if (mounted) setState(() => _loadError = true);
    }
  }

  Future<void> _run(Future<void> Function() act, StructuralResult ok) async {
    setState(() {
      _busy = true;
      _error = false;
      _result = null;
    });
    try {
      await act();
      if (mounted) setState(() => _result = ok);
    } on StructuralRequestFailure {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(StructuralItem item) async {
    if (!await confirmApproval(context) || !mounted) return;
    final seam = StructuralRequestsScope.of(context);
    await _run(() => seam.approve(item.request.id), StructuralResult.approved);
  }

  Future<void> _veto(StructuralItem item) async {
    final reason = await showVetoSheet(context);
    if (reason == null || !mounted) return;
    final seam = StructuralRequestsScope.of(context);
    await _run(
      () => seam.veto(requestId: item.request.id, reason: reason),
      StructuralResult.vetoed,
    );
  }

  /// A fresh request with the same terms (02 §7.2.1: lapsed, logged,
  /// re-initiable). It is a new request, not a revival, so no approval
  /// result is claimed for it — the seam's next snapshot carries it.
  Future<void> _reinitiate(StructuralItem item) async {
    final seam = StructuralRequestsScope.of(context);
    setState(() {
      _busy = true;
      _error = false;
      _result = null;
    });
    try {
      await seam.reinitiate(item.request.id);
    } on StructuralRequestFailure {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seam = StructuralRequestsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inboxStructuralDetailTitle)),
      body: SafeArea(
        child: StreamBuilder<StructuralInbox>(
          stream: seam.watch(),
          initialData: seam.current,
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) {
              return _loadError
                  ? _Failed(onRetry: _refresh)
                  : const _Skeleton();
            }
            StructuralItem? item;
            for (final i in data.visible) {
              if (i.request.id == widget.requestId) item = i;
            }
            if (item == null) return _Gone(onDone: widget.onDone);
            return _body(context, item);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, StructuralItem item) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final required = item.required;
    final approvers = item.outcome.approvedBy;
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        StructuralCard(
          item: item,
          dense: true,
          busy: _busy,
          error: _error,
          result: _result,
          onApprove: () => _approve(item),
          onVeto: () => _veto(item),
          onReinitiate: () => _reinitiate(item),
        ),
        const SizedBox(height: RkSpace.s4),
        Text(
          l10n.inboxStructuralDetailRaised(
            formatLedgerDate(
              localDateOf(
                DateTime.fromMillisecondsSinceEpoch(
                  item.request.hlc.physicalMs,
                ),
              ),
              strings: l10n,
            ),
            item.initiatorName,
          ),
          style: text.bodyMedium?.copyWith(color: status.muted),
        ),
        if (required != null) ...[
          const SizedBox(height: RkSpace.s2),
          Text(
            // Both numbers are the engine's: the threshold it applied, and the
            // owners it applied it to (02 §7.2.1; ⌊n/2⌋+1 for a majority).
            l10n.inboxStructuralQuorumRule(required, item.ownerNames.length),
            style: text.bodyMedium?.copyWith(color: status.muted),
          ),
        ],
        const SizedBox(height: RkSpace.s4),
        Text(l10n.inboxStructuralDetailApprovers, style: text.titleMedium),
        const SizedBox(height: RkSpace.s2),
        if (approvers.isEmpty)
          Text(
            l10n.inboxStructuralDetailApproversNone,
            style: text.bodyLarge?.copyWith(color: status.muted),
          )
        else
          for (final id in approvers)
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: status.success,
                  ),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: Text(
                      id == item.viewerId
                          ? l10n.inboxStructuralDetailYou(
                              item.ownerNames[id] ?? id,
                            )
                          : item.ownerNames[id] ?? id,
                      style: text.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: RkSpace.s6),
        TextButton(
          onPressed: widget.onDone,
          child: Text(l10n.inboxStructuralDetailBack),
        ),
      ],
    );
  }
}

/// The ruled skeleton (11 §4.5): true row pitch, no shimmer, announced.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Semantics(
      liveRegion: true,
      label: l10n.inboxSkeleton,
      child: ListView(
        padding: const EdgeInsets.all(RkSpace.gutter),
        children: [
          Container(
            height: RkSpace.s5,
            width: 200,
            color: status.skeletonLabel,
          ),
          const SizedBox(height: RkSpace.s3),
          Container(
            height: RkSpace.s4,
            width: 140,
            color: status.skeletonAmount,
          ),
          const SizedBox(height: RkSpace.s4),
          Container(height: RkSpace.s12, color: status.skeletonLabel),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error),
            const SizedBox(height: RkSpace.s3),
            Text(
              l10n.inboxError,
              style: text.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RkSpace.s3),
            FilledButton(onPressed: onRetry, child: Text(l10n.inboxRetry)),
          ],
        ),
      ),
    );
  }
}

/// The request has gone — decided, vetoed or lapsed on another phone. Never a
/// blank screen, and never a dead end (07 §1 rules 6 and 12).
class _Gone extends StatelessWidget {
  const _Gone({this.onDone});

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, color: status.muted),
            const SizedBox(height: RkSpace.s3),
            Text(
              l10n.inboxStructuralDetailGoneTitle,
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              l10n.inboxStructuralDetailGoneBody,
              style: text.bodyLarge?.copyWith(color: status.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RkSpace.s4),
            FilledButton(
              onPressed: onDone,
              child: Text(l10n.inboxStructuralDetailBack),
            ),
          ],
        ),
      ),
    );
  }
}
