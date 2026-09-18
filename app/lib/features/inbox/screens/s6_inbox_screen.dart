// S6 Inbox (13 §3.2, 07 §9) — the one tray for everything awaiting a human.
//
// This slice draws three of 13 §4.1 P3's typed cards: the **review** card
// (S6.1), the **structural approval** card (S6.3, 07 §26 🔒 — quorum, Approve
// and Veto with reason) and the **late arrivals** section, which counts what
// is waiting and opens S10.3 (07 §13 🔒, 02 §8 🔒). The rest (imports,
// invites, recoveries, reminders, quota, security) each need a source this
// build does not have yet; a state that cannot be sourced is not drawn.
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
import '../late_arrivals.dart';
import '../review_queue.dart';
import '../structural_requests.dart';
import '../widgets/reject_sheet.dart';
import '../widgets/review_card.dart';
import '../widgets/structural_card.dart';
import '../widgets/veto_sheet.dart';

/// The Inbox tab root.
class InboxScreen extends StatefulWidget {
  /// Creates the screen.
  const InboxScreen({
    super.key,
    this.onOpenLedger,
    this.onReviewGroup,
    this.onOpenStructural,
    this.onOpenLateArrivals,
  });

  /// The empty state's one next action (07 §1 rule 6 — no dead ends).
  final VoidCallback? onOpenLedger;

  /// *One by one* → S6.2 for that card.
  final void Function(String groupId)? onReviewGroup;

  /// *See the full request* → S6.3's review surface for that request.
  final void Function(String requestId)? onOpenStructural;

  /// The late-arrivals section's one action → S10.3 (13 §3.2: its parent is
  /// this screen). Null leaves the section a statement of what is waiting,
  /// never a tap that goes nowhere (07 §1 rule 6).
  final VoidCallback? onOpenLateArrivals;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  bool _loading = false;
  bool _error = false;
  String? _busyGroup;
  String? _errorGroup;
  ({String groupId, int count})? _approved;
  String? _busyRequest;
  String? _errorRequest;
  ({String requestId, StructuralResult result})? _decided;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cold =
          ReviewQueueScope.of(context).current == null ||
          LateArrivalsScope.of(context).current == null;
      if (cold) _refresh();
    });
  }

  Future<void> _refresh() async {
    final queue = ReviewQueueScope.of(context);
    final structural = StructuralRequestsScope.of(context);
    final lateTray = LateArrivalsScope.of(context);
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      await queue.refresh();
      await structural.refresh();
      await lateTray.refresh();
    } on ReviewQueueFailure {
      if (mounted) setState(() => _error = true);
    } on StructuralRequestFailure {
      if (mounted) setState(() => _error = true);
    } on LateArrivalsFailure {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// One structural write (02 §7.2.1): one signed envelope, nothing applied
  /// here. Busy and failure are per-card, so a failed veto never blanks the
  /// tray (13 §4.3).
  Future<void> _structuralWrite(
    StructuralItem item,
    Future<void> Function(StructuralRequests seam) act,
    StructuralResult? result,
  ) async {
    final seam = StructuralRequestsScope.of(context);
    final id = item.request.id;
    setState(() {
      _busyRequest = id;
      _errorRequest = null;
      _decided = null;
    });
    try {
      await act(seam);
      if (mounted && result != null) {
        setState(() => _decided = (requestId: id, result: result));
      }
    } on StructuralRequestFailure {
      if (mounted) setState(() => _errorRequest = id);
    } finally {
      if (mounted) setState(() => _busyRequest = null);
    }
  }

  Future<void> _approveStructural(StructuralItem item) async {
    if (!await confirmApproval(context) || !mounted) return;
    await _structuralWrite(
      item,
      (seam) => seam.approve(item.request.id),
      StructuralResult.approved,
    );
  }

  Future<void> _vetoStructural(StructuralItem item) async {
    final reason = await showVetoSheet(context);
    if (reason == null || !mounted) return;
    await _structuralWrite(
      item,
      (seam) => seam.veto(requestId: item.request.id, reason: reason),
      StructuralResult.vetoed,
    );
  }

  Future<void> _reinitiateStructural(StructuralItem item) =>
      _structuralWrite(item, (seam) => seam.reinitiate(item.request.id), null);

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
            final structural = StructuralRequestsScope.of(context);
            final lateTray = LateArrivalsScope.of(context);
            return StreamBuilder<StructuralInbox>(
              stream: structural.watch(),
              initialData: structural.current,
              builder: (context, st) => StreamBuilder<LateArrivalsTray>(
                stream: lateTray.watch(),
                initialData: lateTray.current,
                builder: (context, lt) => StreamBuilder<SyncStatus>(
                  stream: scope.sync.status,
                  initialData: scope.sync.current,
                  builder: (context, ss) => _body(
                    context,
                    s,
                    structural: st.data ?? const StructuralInbox(),
                    lateTray: lt.data ?? const LateArrivalsTray(),
                    offline: ss.data is Offline,
                    now: scope.now(),
                  ),
                ),
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
    required StructuralInbox structural,
    required LateArrivalsTray lateTray,
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
          if (s.isEmpty && structural.isEmpty && lateTray.isEmpty)
            _EmptyState(readOnly: s.readOnly, onAction: widget.onOpenLedger),
          // S6.3 first: a structural change is the only card that can alter
          // who may do what (02 §7.2.1), so it outranks a review flag.
          if (!structural.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s3),
              child: Text(l10n.inboxSectionStructural, style: text.titleLarge),
            ),
            for (final item in structural.visible)
              Padding(
                padding: const EdgeInsets.only(bottom: RkSpace.s4),
                child: StructuralCard(
                  item: item,
                  busy: _busyRequest == item.request.id,
                  error: _errorRequest == item.request.id,
                  result: _decided?.requestId == item.request.id
                      ? _decided?.result
                      : null,
                  onApprove: () => _approveStructural(item),
                  onVeto: () => _vetoStructural(item),
                  onReinitiate: () => _reinitiateStructural(item),
                  onOpen: widget.onOpenStructural == null
                      ? null
                      : () => widget.onOpenStructural!(item.request.id),
                ),
              ),
          ],
          // Then the tray: a late arrival is the only card here holding a
          // *month close* open (02 §8 🔒), which is time-bound in a way a
          // review flag is not, and 13 §4.1 P3 lists it ahead of the
          // structural card.
          //
          // ⚠️ SPEC: nothing in 07 §9, 07 §13 or 13 §4.1 ranks the P3 card
          // types against each other. The conservative reading is the one
          // this screen already took for S6.3 — the card that can change what
          // a person may do comes first — with the time-bound tray next and
          // the everyday review work last. If the owner wants a different
          // order, it is three blocks moving in this list.
          if (!lateTray.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s4),
              child: _LateArrivalsSection(
                count: lateTray.items.length,
                onOpen: widget.onOpenLateArrivals,
              ),
            ),
          if (!s.isEmpty) ...[
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

/// The S6 **late arrivals** section (07 §13 🔒, 02 §8 🔒): how many entries
/// arrived after their month had closed, and the one tap into S10.3.
///
/// It is drawn only when something is waiting. That is not a hidden
/// capability (13 §2.3 🔒): the *capability* — deciding where a late arrival
/// sits — lives on S10.3 and on the close tray, and S6's own empty state
/// already states what this reader may do here, including the viewer variant.
/// A section that said "nothing arrived late" on every quiet day would be the
/// bare tray 13 §2.3 warns against.
///
/// Post-then-review (02 §3 🔒, 02 §8 🔒): the line under the count says the
/// money is already in the balances. Nothing here may read as a hold.
class _LateArrivalsSection extends StatelessWidget {
  const _LateArrivalsSection({required this.count, this.onOpen});

  /// How many entries are in the tray.
  final int count;

  /// Opens S10.3. Null leaves the section a statement (07 §1 rule 6).
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: RkSpace.s3),
          child: Text(l10n.inboxSectionLate, style: text.titleLarge),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colour is never alone (07 §1 rule 3): the lock icon and the
                // sentence carry it, the token colour only reinforces.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_clock, size: 20, color: status.locked),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(
                      child: Text(
                        l10n.inboxSectionLateCount(count),
                        style: text.bodyLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RkSpace.s2),
                Text(
                  l10n.inboxSectionLateCounted,
                  style: text.bodyMedium?.copyWith(color: status.muted),
                ),
                if (onOpen != null) ...[
                  const SizedBox(height: RkSpace.s4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onOpen,
                      child: Text(l10n.inboxSectionLateAction),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
