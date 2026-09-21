// S16.3 Delete account — 15-day cooling, what is erased vs retained, cancel
// anytime (07 §21 🔒, 06 §9.3 🔒; a support request lands as a card to accept,
// never as a started clock — ADR 2026-09-05h §2).
//
// Two things make this screen what it is.
//
// **The cooling period is a state, not a dialog.** A modal asks a question and
// vanishes; a 15-day window is something the account *is in*, on every device,
// until it ends or the user stops it. So the screen has four states and the
// data decides which one is drawn: `idle` (the explanation and the two lists),
// `requested` (support has asked — nothing is running), `running` (the
// countdown, with Cancel to the last second) and `over` (the window closed;
// the Cancel is gone because it no longer exists). Nothing here is a
// `showDialog`.
//
// **The screen is honest about what deletion cannot do.** 06 §9.3 🔒 erases the
// profile, every wrapped key and the personal book, and ends every session —
// and it *keeps* two things: the entries the user authored in shared books
// (they are the tenant's records, with authorship pseudonymised) and the
// verification material (public key + device certificates, flagged `erased`)
// without which other devices could not verify the signature chain (04 §3.4),
// would quarantine those entries, compute different balances and fail the
// close hash (02 §8). Both lists are on the one screen, given equal weight.
// Nothing here may claim an erasure the architecture does not perform.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_banner.dart';
import '../../../shared/widgets/rk_states.dart';
import '../account_repository.dart';
import '../deletion_window.dart';
import '../widgets/account_parts.dart';

/// S16.3 — the deletion screen.
class DeleteAccountScreen extends StatefulWidget {
  /// Creates the screen.
  const DeleteAccountScreen({super.key, this.onOpenExport});

  /// → export (06 §9.2 🔒, always available). Null leaves the line as a
  /// statement rather than a link; it is never removed, because leaving with
  /// your books is the point.
  final VoidCallback? onOpenExport;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _loading = false;
  bool _error = false;
  bool _acknowledged = false;
  bool _busy = false;
  bool _startError = false;
  bool _cancelError = false;
  bool _justCancelled = false;
  bool _justDeclined = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final repo = AccountRepositoryScope.of(context);
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      await repo.refresh();
    } on Exception {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    required bool cancel,
  }) async {
    setState(() {
      _busy = true;
      _startError = false;
      _cancelError = false;
      _justCancelled = false;
      _justDeclined = false;
    });
    try {
      await action();
    } on Exception {
      if (mounted) {
        setState(() {
          if (cancel) {
            _cancelError = true;
          } else {
            _startError = true;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = AccountRepositoryScope.of(context);
    final now = RkScope.of(context).now;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountDeleteTitle)),
      body: SafeArea(
        child: StreamBuilder<AccountSnapshot>(
          stream: repo.watch(),
          initialData: repo.current,
          builder: (context, snap) {
            final s = snap.data;
            if (s == null) {
              if (_error && !_loading) {
                return RkErrorState(
                  text: l10n.accountError,
                  retryLabel: l10n.accountRetry,
                  onRetry: _refresh,
                );
              }
              return RkSkeleton(label: l10n.accountSkeletonLabel, rows: 4);
            }
            final w = s.window;
            final open = w != null && !w.cancelled;
            if (open) {
              return w.isComplete(now())
                  ? _over(context)
                  : _running(context, w, repo, now());
            }
            return _explain(context, s, repo, now());
          },
        ),
      ),
    );
  }

  // ---- state: running -----------------------------------------------------

  Widget _running(
    BuildContext context,
    DeletionWindow w,
    AccountRepository repo,
    DateTime now,
  ) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        RkBannerSurface(
          tone: RkBannerTone.danger,
          icon: Icons.timer_outlined,
          title: l10n.accountDeleteRunningHeading,
          body: l10n.accountDeleteRunningBody(
            formatLedgerDate(localDateOf(w.completesAt), strings: l10n),
          ),
          actions: [
            Text(
              l10n.accountDeletionDaysLeft(w.daysLeft(now)),
              style: text.bodyMedium?.copyWith(
                fontFeatures: RkType.tabular,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.campaign_outlined,
                size: 18,
                color: status.muted,
              ),
            ),
            const SizedBox(width: RkSpace.s2),
            Expanded(
              child: Text(
                l10n.accountDeleteRunningNotified,
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s6),
        _exportLine(context),
        const SizedBox(height: RkSpace.s6),
        if (_cancelError) _ProblemLine(text: l10n.accountDeleteCancelError),
        // Cancel-anytime (06 §9.3 🔒): available up to the last second, which
        // is why this is `canCancel(now)` and not a day count.
        OutlinedButton(
          key: const Key('account.delete.cancel'),
          onPressed: _busy || !w.canCancel(now) ? null : () => _cancel(repo),
          child: Text(
            _busy ? l10n.accountDeleteCancelling : l10n.accountDeleteCancel,
          ),
        ),
      ],
    );
  }

  // ---- state: over --------------------------------------------------------

  Widget _over(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        RkBannerSurface(
          tone: RkBannerTone.danger,
          icon: Icons.lock_clock,
          title: l10n.accountDeleteCompleteHeading,
          body: l10n.accountDeleteCompleteBody,
        ),
      ],
    );
  }

  // ---- states: idle and requested ----------------------------------------

  Widget _explain(
    BuildContext context,
    AccountSnapshot s,
    AccountRepository repo,
    DateTime now,
  ) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final request = s.request;
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        if (_justCancelled) _GoodLine(text: l10n.accountDeleteCancelled),
        if (_justDeclined) _GoodLine(text: l10n.accountDeleteDeclined),
        if (request != null) ...[
          // A request is not a clock (ADR 2026-09-05h §2). Nothing counts
          // down here, and the card says so in as many words.
          RkBannerSurface(
            tone: RkBannerTone.warning,
            icon: Icons.support_agent,
            title: l10n.accountRequestCardTitle,
            body: l10n.accountRequestCardBody,
            actions: [
              Text(
                l10n.accountRequestCardAskedOn(
                  formatLedgerDate(
                    localDateOf(request.requestedAt),
                    strings: l10n,
                  ),
                ),
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s4),
        ],
        Text(l10n.accountDeleteLede, style: text.bodyLarge),
        const SizedBox(height: RkSpace.s6),
        AccountFactList(
          heading: l10n.accountDeleteErasedHeading,
          icon: Icons.remove_circle_outline,
          tint: status.danger,
          items: [
            l10n.accountDeleteErasedProfile,
            l10n.accountDeleteErasedKeys,
            l10n.accountDeleteErasedPersonal,
            l10n.accountDeleteErasedSessions,
          ],
        ),
        const SizedBox(height: RkSpace.s6),
        AccountFactList(
          heading: l10n.accountDeleteKeptHeading,
          icon: Icons.push_pin_outlined,
          tint: status.info,
          items: [l10n.accountDeleteKeptShared, l10n.accountDeleteKeptProof],
          footnote: l10n.accountDeleteKeptNote,
        ),
        const SizedBox(height: RkSpace.s6),
        _exportLine(context),
        const SizedBox(height: RkSpace.s6),
        // Two deliberate acts, never one tap: the acknowledgement, then the
        // action that names what it starts (a clock, not an erasure).
        CheckboxListTile(
          key: const Key('account.delete.ack'),
          value: _acknowledged,
          onChanged: _busy
              ? null
              : (v) => setState(() => _acknowledged = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.accountDeleteAck, style: text.bodyMedium),
        ),
        const SizedBox(height: RkSpace.s3),
        if (_startError) _ProblemLine(text: l10n.accountDeleteError),
        if (request == null)
          FilledButton(
            key: const Key('account.delete.start'),
            onPressed: !_acknowledged || _busy
                ? null
                : () => _run(repo.startDeletion, cancel: false),
            child: Text(
              _busy ? l10n.accountDeleteStarting : l10n.accountDeleteStart,
            ),
          )
        else ...[
          FilledButton(
            key: const Key('account.delete.accept'),
            onPressed: !_acknowledged || _busy
                ? null
                : () => _run(
                    () => repo.acceptDeletionRequest(request.id),
                    cancel: false,
                  ),
            child: Text(
              _busy ? l10n.accountDeleteStarting : l10n.accountDeleteAccept,
            ),
          ),
          const SizedBox(height: RkSpace.s2),
          TextButton(
            key: const Key('account.delete.decline'),
            onPressed: _busy ? null : () => _decline(repo, request.id),
            child: Text(l10n.accountDeleteDecline),
          ),
        ],
        if (!_acknowledged && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: RkSpace.s2),
            child: Text(
              l10n.accountDeleteStartReason,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
          ),
      ],
    );
  }

  Future<void> _cancel(AccountRepository repo) async {
    await _run(repo.cancelDeletion, cancel: true);
    if (mounted && !_cancelError) setState(() => _justCancelled = true);
  }

  Future<void> _decline(AccountRepository repo, String id) async {
    await _run(() => repo.declineDeletionRequest(id), cancel: false);
    if (mounted && !_startError) setState(() => _justDeclined = true);
  }

  Widget _exportLine(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.download_outlined, size: 18, color: status.info),
        ),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.accountDeleteExportTitle,
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.accountDeleteExportBody,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              if (widget.onOpenExport != null)
                TextButton(
                  onPressed: widget.onOpenExport,
                  child: Text(l10n.accountDeleteExportTitle),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProblemLine extends StatelessWidget {
  const _ProblemLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline, size: 16, color: status.danger),
          ),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(text, style: style?.copyWith(color: status.danger)),
          ),
        ],
      ),
    );
  }
}

class _GoodLine extends StatelessWidget {
  const _GoodLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle, size: 16, color: status.success),
          ),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(text, style: style?.copyWith(color: status.success)),
          ),
        ],
      ),
    );
  }
}
