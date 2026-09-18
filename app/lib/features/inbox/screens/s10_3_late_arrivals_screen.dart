// S10.3 — the Late Arrivals tray (13 §3.2 row S10.3, parent S6; 07 §13 🔒;
// 02 §8 🔒; ADR 2026-09-05e §3, §10).
//
// An entry made before a month closed but reaching this phone afterwards is
// **valid**, counts in every live balance the moment it lands, and leaves the
// certified month untouched (02 §8 🔒). It waits here for the closer, who
// either re-dates it into the open period — the default, one tap — or
// re-opens the month, which is an admin act, logged, and needs a re-close.
//
// Three rules this screen is built around:
//
//  1. **Nothing here is pending.** The money is already in the balances
//     (02 §3 🔒, 02 §8 🔒); the card says so in words. No "waiting to be
//     counted" anywhere on this surface.
//  2. **Re-date is the default and re-open is the exception** (07 §13 🔒):
//     the one-tap primary, then the scary-styled secondary behind a confirm
//     sheet with a required reason.
//  3. **A closed FY is not re-openable from here** (02 §8.1 🔒, 02 §7.2.1 🔒):
//     the card states the reason and points at the year-close ceremony rather
//     than offering a tap that can only be refused (07 §1 rule 6).
//
// States (13 §4.3): loading (ruled skeleton, 11 §4.5) · populated · empty,
// stating the capability rather than showing a bare tray (13 §2.3 🔒) · its
// viewer variant (13 §2.3.1) · error-with-retry · offline chip, never a
// blocking banner (07 §1 rule 7) · per-card busy, failed write and refusal.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../late_arrivals.dart';
import '../widgets/late_arrival_card.dart';
import '../widgets/reopen_sheet.dart';

/// The full-screen Late Arrivals tray.
class LateArrivalsScreen extends StatefulWidget {
  /// Creates the screen.
  const LateArrivalsScreen({super.key, this.onDone});

  /// Back to the Inbox — the one next action of every end state
  /// (07 §1 rule 6: no dead ends).
  final VoidCallback? onDone;

  @override
  State<LateArrivalsScreen> createState() => _LateArrivalsScreenState();
}

class _LateArrivalsScreenState extends State<LateArrivalsScreen> {
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && LateArrivalsScope.of(context).current == null) _refresh();
    });
  }

  Future<void> _refresh() async {
    final tray = LateArrivalsScope.of(context);
    setState(() => _loadError = false);
    try {
      await tray.refresh();
    } on LateArrivalsFailure {
      if (mounted) setState(() => _loadError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tray = LateArrivalsScope.of(context);
    final scope = RkScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inboxLateTitle)),
      body: SafeArea(
        child: StreamBuilder<LateArrivalsTray>(
          stream: tray.watch(),
          initialData: tray.current,
          builder: (context, snap) {
            final s = snap.data;
            if (s == null) {
              return _loadError
                  ? _LateError(onRetry: _refresh)
                  : const LateArrivalsSkeleton();
            }
            return StreamBuilder<SyncStatus>(
              stream: scope.sync.status,
              initialData: scope.sync.current,
              builder: (context, ss) => RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(RkSpace.gutter),
                  children: [
                    if (ss.data is Offline) const _OfflineChip(),
                    if (_loadError)
                      _InlineError(onRetry: _refresh)
                    else if (s.isEmpty)
                      LateArrivalsEmpty(
                        readOnly: s.readOnly,
                        onAction: widget.onDone,
                      ),
                    for (final item in s.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: RkSpace.s4),
                        child: LateArrivalTile(item: item),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One card plus the writes it can make. Busy, failure and refusal are held
/// **per card**, so a refused re-open never blanks the tray (13 §4.3), and the
/// ledger being append-only means a failed write changed nothing at all.
class LateArrivalTile extends StatefulWidget {
  /// Creates the tile.
  const LateArrivalTile({super.key, required this.item});

  /// The tray item this tile draws.
  final LateArrivalItem item;

  @override
  State<LateArrivalTile> createState() => _LateArrivalTileState();
}

class _LateArrivalTileState extends State<LateArrivalTile> {
  bool _busy = false;
  bool _error = false;
  bool _moved = false;
  ReopenRefusal? _refusal;

  String get _month {
    final l10n = AppLocalizations.of(context);
    return lateArrivalMonthLabel(
      l10n,
      widget.item.lockedPeriod.year,
      widget.item.lockedPeriod.month,
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// *Re-date to today* — one tap, no confirm (02 §8 🔒 "default, one tap").
  ///
  /// ⚠️ SPEC: 07 §5 gives the *entry save* flow a 10-second Undo. Nothing in
  /// 02 §8 or 07 §13 extends it to a re-date, and the seam offers no reverse
  /// of one, so this surface confirms rather than offering an Undo it cannot
  /// honour. Re-dating is an amend of a posted entry: the entry stays in the
  /// book either way and only its date moved, which the confirmation says.
  Future<void> _redate() async {
    final tray = LateArrivalsScope.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = false;
      _refusal = null;
    });
    try {
      await tray.redateToToday(widget.item.entryId);
      if (mounted) setState(() => _moved = true);
      _say(l10n.inboxLateCardMoved);
    } on LateArrivalsFailure {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// *Re-open {month}* — admin, scary-styled, logged (07 §13 🔒). The sheet
  /// states the consequence and will not confirm without a reason, because
  /// `LocalLedger.unlockMonth` treats a blank one as a programming error.
  Future<void> _reopen() async {
    final month = _month;
    final l10n = AppLocalizations.of(context);
    final reason = await showReopenSheet(context, month: month);
    if (reason == null || !mounted) return;
    final tray = LateArrivalsScope.of(context);
    setState(() {
      _busy = true;
      _error = false;
      _refusal = null;
    });
    try {
      await tray.reopenMonth(
        bookId: widget.item.bookId,
        period: widget.item.lockedPeriod,
        reason: reason,
      );
      _say(l10n.inboxLateReopened(month));
    } on ReopenRefused catch (r) {
      if (mounted) setState(() => _refusal = r.reason);
    } on LateArrivalsFailure {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LateArrivalCard(
    item: widget.item,
    busy: _busy,
    error: _error,
    moved: _moved,
    refusal: _refusal,
    onRedate: _redate,
    onReopen: widget.item.reopenBlocked ? null : _reopen,
  );
}

/// The ruled skeleton (11 §4.5): true row pitch, no shimmer, announced.
class LateArrivalsSkeleton extends StatelessWidget {
  /// Creates the skeleton.
  const LateArrivalsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Semantics(
      liveRegion: true,
      label: l10n.inboxLateSkeleton,
      child: ListView(
        padding: const EdgeInsets.all(RkSpace.gutter),
        children: [
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: RkSpace.s5,
                    width: 160,
                    color: status.skeletonAmount,
                  ),
                  const SizedBox(height: RkSpace.s2),
                  Container(
                    height: RkSpace.s4,
                    width: 220,
                    color: status.skeletonLabel,
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

/// Empty, and its viewer variant — the capability is stated, never a bare
/// tray (13 §2.3 🔒, 13 §2.3.1), with the one next action beneath it.
class LateArrivalsEmpty extends StatelessWidget {
  /// Creates the empty state.
  const LateArrivalsEmpty({super.key, required this.readOnly, this.onAction});

  /// The reader may view the book but not close it.
  final bool readOnly;

  /// The one next action (07 §1 rule 6).
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s8),
      child: Column(
        children: [
          Icon(
            readOnly ? Icons.visibility_outlined : Icons.schedule_outlined,
            color: status.muted,
          ),
          const SizedBox(height: RkSpace.s3),
          Text(
            readOnly
                ? l10n.inboxLateEmptyViewerTitle
                : l10n.inboxLateEmptyTitle,
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RkSpace.s2),
          Text(
            readOnly ? l10n.inboxLateEmptyViewerBody : l10n.inboxLateEmptyBody,
            style: text.bodyLarge?.copyWith(color: status.muted),
            textAlign: TextAlign.center,
          ),
          if (onAction != null) ...[
            const SizedBox(height: RkSpace.s4),
            FilledButton(
              onPressed: onAction,
              child: Text(l10n.inboxLateEmptyAction),
            ),
          ],
        ],
      ),
    );
  }
}

class _LateError extends StatelessWidget {
  const _LateError({required this.onRetry});

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
              l10n.inboxLateError,
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

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.error, size: 20),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(
              l10n.inboxLateError,
              style: text.bodyMedium?.copyWith(color: scheme.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.inboxRetry)),
        ],
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
