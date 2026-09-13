// S6 Inbox (13 §3.2, 07 §9) — the one tray for everything awaiting a human.
//
// This slice draws the **review** cards (S6.1) only. 13 §4.1 P3's other typed
// cards (imports, invites, recoveries, reminders, late arrivals, structural
// approval S6.3, quota, security) each need a source this build does not have
// yet; a state that cannot be sourced is not drawn. They arrive with their own
// slices — S6.3's is planned at A-02-94 @M7.
//
// States (13 §4.3): loading (ruled skeleton) · populated · empty with its one
// next action · error-with-retry · offline chip (never a blocking banner,
// 07 §1 rule 7) · the viewer role variant of 13 §2.3.1, which states the
// capability instead of showing a bare empty tray (13 §2.3 🔒).
//
// Post-then-review (02 §3 🔒): every entry listed here is already posted and
// already counted. Nothing on this screen may suggest the money is waiting.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../review_queue.dart';
import '../widgets/reject_sheet.dart';
import '../widgets/review_card.dart';

/// The Inbox tab root.
class InboxScreen extends StatefulWidget {
  /// Creates the screen.
  const InboxScreen({super.key, this.onOpenLedger, this.onReviewGroup});

  /// The empty state's one next action (07 §1 rule 6 — no dead ends).
  final VoidCallback? onOpenLedger;

  /// *One by one* → S6.2 for that card.
  final void Function(String groupId)? onReviewGroup;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  bool _loading = false;
  bool _error = false;
  String? _busyGroup;
  String? _errorGroup;
  ({String groupId, int count})? _approved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ReviewQueueScope.of(context).current == null) _refresh();
    });
  }

  Future<void> _refresh() async {
    final queue = ReviewQueueScope.of(context);
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      await queue.refresh();
    } on ReviewQueueFailure {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approveAll(ReviewGroup g) async {
    final queue = ReviewQueueScope.of(context);
    setState(() {
      _busyGroup = g.id;
      _errorGroup = null;
      _approved = null;
    });
    try {
      await queue.approveAll(g.id);
      if (mounted) {
        setState(() => _approved = (groupId: g.id, count: g.count));
      }
    } on ReviewQueueFailure {
      if (mounted) setState(() => _errorGroup = g.id);
    } finally {
      if (mounted) setState(() => _busyGroup = null);
    }
  }

  Future<void> _reject(ReviewGroup g, ReviewEntry e) async {
    final reason = await showRejectSheet(context, authorName: g.authorName);
    if (reason == null || !mounted) return;
    final queue = ReviewQueueScope.of(context);
    setState(() {
      _busyGroup = g.id;
      _errorGroup = null;
    });
    try {
      await queue.decide(
        groupId: g.id,
        entryId: e.id,
        decision: ReviewDecision.reject,
        reason: reason,
      );
    } on ReviewQueueFailure {
      if (mounted) setState(() => _errorGroup = g.id);
    } finally {
      if (mounted) setState(() => _busyGroup = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final queue = ReviewQueueScope.of(context);
    final scope = RkScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inboxTitle)),
      body: SafeArea(
        child: StreamBuilder<InboxSnapshot>(
          stream: queue.watch(),
          initialData: queue.current,
          builder: (context, snap) {
            final s = snap.data;
            if (s == null) {
              if (_error && !_loading) {
                return _ErrorState(onRetry: _refresh);
              }
              return const _Skeleton();
            }
            return StreamBuilder<SyncStatus>(
              stream: scope.sync.status,
              initialData: scope.sync.current,
              builder: (context, ss) => _body(
                context,
                s,
                offline: ss.data is Offline,
                now: scope.now(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    InboxSnapshot s, {
    required bool offline,
    required DateTime now,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final approved = _approved;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(RkSpace.gutter),
        children: [
          if (offline) const _OfflineChip(),
          if (_error)
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: scheme.error, size: 20),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: Text(
                      l10n.inboxError,
                      style: text.bodyMedium?.copyWith(color: scheme.error),
                    ),
                  ),
                  TextButton(onPressed: _refresh, child: Text(l10n.inboxRetry)),
                ],
              ),
            ),
          if (s.isEmpty)
            _EmptyState(readOnly: s.readOnly, onAction: widget.onOpenLedger)
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s3),
              child: Text(l10n.inboxSectionReview, style: text.titleLarge),
            ),
            for (final g in s.reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: RkSpace.s4),
                child: ReviewCard(
                  group: g,
                  now: now,
                  busy: _busyGroup == g.id,
                  error: _errorGroup == g.id,
                  approvedCount: approved != null && approved.groupId == g.id
                      ? approved.count
                      : null,
                  onApproveAll: () => _approveAll(g),
                  onReject: (e) => _reject(g, e),
                  onOneByOne: widget.onReviewGroup == null
                      ? null
                      : () => widget.onReviewGroup!(g.id),
                ),
              ),
          ],
        ],
      ),
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
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: RkSpace.s5,
                    width: 180,
                    color: status.skeletonLabel,
                  ),
                  const SizedBox(height: RkSpace.s2),
                  Container(
                    height: RkSpace.s4,
                    width: 120,
                    color: status.skeletonAmount,
                  ),
                  const SizedBox(height: RkSpace.s2),
                  Container(height: RkSpace.s10, color: status.skeletonLabel),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

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

class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_off, size: 20, color: status.muted),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(
              l10n.inboxOffline,
              style: text.bodyMedium?.copyWith(color: status.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty (13 §4.3: friendly line + the one next action) and its viewer
/// variant (13 §2.3.1) — the reason is stated, never silently hidden.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.readOnly, this.onAction});

  final bool readOnly;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s10),
      child: Column(
        children: [
          Icon(
            readOnly ? Icons.visibility_outlined : Icons.inbox_outlined,
            color: status.muted,
          ),
          const SizedBox(height: RkSpace.s3),
          Text(
            readOnly ? l10n.inboxEmptyViewerTitle : l10n.inboxEmptyTitle,
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RkSpace.s2),
          Text(
            readOnly ? l10n.inboxEmptyViewerBody : l10n.inboxEmptyBody,
            style: text.bodyLarge?.copyWith(color: status.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RkSpace.s4),
          FilledButton(onPressed: onAction, child: Text(l10n.inboxEmptyAction)),
        ],
      ),
    );
  }
}
