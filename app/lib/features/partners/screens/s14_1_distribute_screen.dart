// S14.1 — the profit-distribution wizard (02 §7.1 🔒, 02 §7.2.1 🔒, ADR
// 2026-09-14b, ADR 2026-09-05e §8; 13 §3.2 row S14.1, reached from S14).
//
// **Three steps, 13 §3.2's own words** — *period profit → ratio preview (incl.
// interest lines) → one multi-line entry*:
//
//   1. *Which stretch of the year?* — defaults to the open FY up to today. The
//      dates bound the **interest** period only; the profit figure is the
//      year's whatever window is chosen (ADR 2026-09-05e §8), and the help
//      line says so rather than letting the reader assume otherwise.
//   2. *What each owner gets* — **both lines per owner**, interest and share
//      (02 §7.1 🔒), their totals, and the whole entry's total beneath. The
//      two totals add to the year's figure exactly, so the odd paise the
//      division leaves over are visible inside the owners' own numbers rather
//      than hidden in a rounding note.
//   3. *Ready to record* — *Distribute* for a book with one owner (a quorum of
//      one, where 02 §7.2.1 🔒 keeps the idea invisible), *Propose to the
//      owners* for a shared book, with one sentence saying it waits in their
//      Inbox and that nothing changes before they approve.
//
// **This screen computes nothing.** Every figure arrives through
// [DistributionPort] from `core_ledger` — the split, the remainder, the
// interest and the ceiling — and the screen imports neither `LocalLedger` nor
// `packages/data`. It does not even decide whether it may post: `quorumOfOne`
// and `block` are the port's answers.
//
// Vocabulary: business surface — *share*, *interest*, *put in*. No Dr/Cr here;
// that belongs to the A/C statement and the exports (02 §10 🔒).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_connection_notice.dart';
import '../../../shared/widgets/rk_connection_notice_copy.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../../../shared/widgets/rk_states.dart';
import '../partners_port.dart';
import '../partners_scope.dart';
import '../widgets/distribution_parts.dart';

/// Keys the wizard's parts answer to, so a test names a thing rather than a
/// string — the strings are asserted separately, in all three languages.
abstract final class DistributeKeys {
  /// The step body on screen.
  static const step = Key('distribute.step');

  /// The forward / commit button.
  static const next = Key('distribute.next');

  /// The back button.
  static const back = Key('distribute.back');

  /// The *From* date row.
  static const from = Key('distribute.from');

  /// The *To* date row.
  static const to = Key('distribute.to');

  /// The refusal panel (13 §4.3).
  static const blocked = Key('distribute.blocked');
}

/// S14.1 — the wizard.
class DistributeProfitScreen extends StatefulWidget {
  /// Creates the screen for [bookId].
  const DistributeProfitScreen({super.key, required this.bookId, this.port});

  /// The shared business whose year this is (02 §7.1: partner accounts are
  /// per business book).
  final String bookId;

  /// Overrides the ambient [PartnersScope] — used by tests and by a host that
  /// builds the screen directly.
  final DistributionPort? port;

  @override
  State<DistributeProfitScreen> createState() => _DistributeProfitScreenState();
}

class _DistributeProfitScreenState extends State<DistributeProfitScreen> {
  static const _steps = 3;

  DistributionPort? _port;
  Future<DistributionView>? _pending;
  DistributionView? _view;
  bool _failed = false;
  bool _busy = false;
  bool _postFailed = false;
  int _step = 0;
  LocalDate? _from;
  LocalDate? _to;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // PartnersScope is an InheritedWidget, so it may only be read from here on.
    final port = widget.port ?? _distributionPort(context);
    if (_port != port) {
      _port = port;
      _load();
    }
  }

  @override
  void didUpdateWidget(DistributeProfitScreen old) {
    super.didUpdateWidget(old);
    // A different book (or a different port) must never keep showing the last
    // book's figures — the one way this screen could lie.
    if (widget.bookId != old.bookId || widget.port != old.port) {
      _port = widget.port ?? _distributionPort(context);
      _from = null;
      _to = null;
      _step = 0;
      _load();
    }
  }

  static DistributionPort _distributionPort(BuildContext context) {
    final port = PartnersScope.of(context);
    if (port is! DistributionPort) {
      throw FlutterError(
        'The mounted PartnersPort does not implement DistributionPort. S14.1 '
        'reads the ledger through it; mount a port that implements both.',
      );
    }
    return port as DistributionPort;
  }

  /// Re-reads the preview. [keepFailure] keeps the *nothing was posted* line
  /// on screen while the figures behind it are refreshed — a refused commit
  /// must not clear its own explanation (02 §5, 07 §1 rule 6).
  void _load({bool keepFailure = false}) {
    final future = _port!.distributionPreview(
      widget.bookId,
      from: _from,
      to: _to,
    );
    setState(() {
      _pending = future;
      _failed = false;
      if (!keepFailure) _postFailed = false;
    });
    future.then(
      (view) {
        if (!mounted || _pending != future) return;
        setState(() {
          _view = view;
          _from ??= view.from;
          _to ??= view.to;
        });
      },
      onError: (Object _) {
        if (!mounted || _pending != future) return;
        setState(() {
          _view = null;
          _failed = true;
        });
      },
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final view = _view;
    if (view == null) return;
    final current = (isFrom ? _from : _to) ?? (isFrom ? view.from : view.to);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      // The period must lie inside the year it distributes: the facade refuses
      // anything else, so the picker never offers it (07 §1 rule 6 — a control
      // that leads to a refusal is a dead end with extra steps).
      firstDate: DateTime(view.from.year, view.from.month, view.from.day),
      lastDate: DateTime(view.to.year, view.to.month, view.to.day),
    );
    if (picked == null) return;
    final value = LocalDate(picked.year, picked.month, picked.day);
    setState(() {
      if (isFrom) {
        _from = value;
      } else {
        _to = value;
      }
    });
    _load();
  }

  Future<void> _commit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _postFailed = false;
    });
    try {
      final result = await _port!.distribute(
        widget.bookId,
        from: _from,
        to: _to,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == DistributionResult.posted
                ? l10n.distributePosted
                : l10n.distributeProposed,
          ),
        ),
      );
      if (navigator.canPop()) navigator.pop(result);
    } on Object {
      // Including [DistributionBlocked]: nothing was authored either way, and
      // the reload below replaces the figures with whatever the ledger now
      // says — so the refusal shows as a state rather than as a lost screen.
      if (!mounted) return;
      setState(() => _postFailed = true);
      _load(keepFailure: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = _view;
    // ADR 2026-09-09b 🔒 governs the app bar too: the words *profit* and
    // *distribute* are only spoken once the book is known to be shared.
    final silent = view?.block == DistributionBlock.notShared;
    return Scaffold(
      appBar: AppBar(title: silent ? null : Text(l10n.distributeTitle)),
      body: SafeArea(
        child: switch ((_failed, view)) {
          (true, _) => RkErrorState(
            text: l10n.distributeError,
            retryLabel: l10n.distributeRetry,
            onRetry: _load,
          ),
          (false, null) => RkSkeleton(label: l10n.distributeSkeleton, rows: 4),
          (false, final v!) => _Body(
            view: v,
            step: _step,
            busy: _busy,
            postFailed: _postFailed,
            onBack: () => setState(() => _step--),
            onNext: () => setState(() => _step++),
            onCommit: _commit,
            onPickFrom: () => _pickDate(isFrom: true),
            onPickTo: () => _pickDate(isFrom: false),
            steps: _steps,
          ),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.view,
    required this.step,
    required this.steps,
    required this.busy,
    required this.postFailed,
    required this.onBack,
    required this.onNext,
    required this.onCommit,
    required this.onPickFrom,
    required this.onPickTo,
  });

  final DistributionView view;
  final int step;
  final int steps;
  final bool busy;
  final bool postFailed;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onCommit;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocked = view.block != null;
    // A blocked book keeps step 1 — the dates are the one thing the reader can
    // still change — and shows the reason in place of the preview. Every other
    // way on is closed, and the app bar's back is the way out (07 §1 rule 6).
    final showStepper = !blocked;
    return Column(
      children: [
        if (view.offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              0,
            ),
            child: RkConnectionNotice(copy: rkConnectionNoticeCopy(context)),
          ),
        if (showStepper)
          DistributeStepper(
            label: l10n.distributeStep(step + 1, steps),
            index: step,
            total: steps,
          ),
        Expanded(
          child: ListView(
            key: DistributeKeys.step,
            padding: const EdgeInsets.only(bottom: RkSpace.s6),
            children: [
              if (blocked)
                _Blocked(view: view)
              else
                switch (step) {
                  0 => _Period(
                    view: view,
                    onPickFrom: onPickFrom,
                    onPickTo: onPickTo,
                  ),
                  1 => _Preview(view: view),
                  _ => _Confirm(view: view, postFailed: postFailed),
                },
            ],
          ),
        ),
        DistributeFooter(
          backLabel: step == 0 ? null : l10n.distributeBack,
          onBack: busy ? null : onBack,
          backKey: DistributeKeys.back,
          nextLabel: switch ((blocked, step)) {
            (true, _) => null,
            (false, final s) when s < steps - 1 => l10n.distributeNext,
            _ =>
              view.quorumOfOne
                  ? l10n.distributeConfirmSolo
                  : l10n.distributeConfirmShared,
          },
          // Read-only disables the commit and nothing else: the figures still
          // show and the reason is printed above the button (13 §4.3, 13 §5).
          onNext: busy
              ? null
              : (step < steps - 1
                    ? onNext
                    : (view.canDistribute ? onCommit : null)),
          nextKey: DistributeKeys.next,
        ),
      ],
    );
  }
}

/// Step 1 — the period. Defaults to the open FY up to today (13 §3.2).
class _Period extends StatelessWidget {
  const _Period({
    required this.view,
    required this.onPickFrom,
    required this.onPickTo,
  });

  final DistributionView view;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DistributeStepHeader(
          title: l10n.distributeStep1Title,
          help: l10n.distributeStep1Help,
        ),
        RkRuledCard(
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.distributePeriodYear(view.financialYearLabel),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: status.muted,
                  ),
                ),
                const SizedBox(height: RkSpace.s2),
                _DateRow(
                  key: DistributeKeys.from,
                  label: l10n.distributePeriodFrom,
                  date: view.from,
                  onTap: onPickFrom,
                ),
                _DateRow(
                  key: DistributeKeys.to,
                  label: l10n.distributePeriodTo,
                  date: view.to,
                  onTap: onPickTo,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    super.key,
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final LocalDate date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = formatLedgerDate(date, strings: l10n);
    return Semantics(
      button: true,
      label: '$label $text',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                const SizedBox(width: RkSpace.s3),
                // Flexible, not fixed: `07 ਸਤੰਬਰ 2026` at 200 % is wider than
                // half a 360 px phone, so the date wraps rather than pushing
                // the icon off the edge (07 §1 rule 11).
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: RkType.tabular,
                    ),
                  ),
                ),
                const SizedBox(width: RkSpace.s2),
                const Icon(Icons.edit_calendar_outlined, size: RkSpace.s5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Step 2 — the ratio preview: **both lines per owner** (02 §7.1 🔒).
class _Preview extends StatelessWidget {
  const _Preview({required this.view});

  final DistributionView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    String money(Paise p) =>
        formatPaise(p.raw, locale: locale, showPaise: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DistributeStepHeader(
          title: l10n.distributeStep2Title,
          help: l10n.distributeStep2Help,
        ),
        RkRuledCard(
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DistributeFigureRow(
                  label: view.isLoss
                      ? l10n.distributeLoss(view.financialYearLabel)
                      : l10n.distributeProfit(view.financialYearLabel),
                  // The figure is stated as a magnitude beside a word that
                  // says which it is, so the sign is never the only carrier
                  // (07 §1 rule 3).
                  amount: money(view.isLoss ? -view.netProfit : view.netProfit),
                  strong: true,
                ),
                if (view.isLoss) ...[
                  const SizedBox(height: RkSpace.s2),
                  Text(
                    l10n.distributeLossNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.muted,
                    ),
                  ),
                ],
                if (view.interestExceedsProfit) ...[
                  const SizedBox(height: RkSpace.s2),
                  Text(
                    l10n.distributeInterestAbove,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.muted,
                    ),
                  ),
                ],
                if (!view.interestEnabled) ...[
                  const SizedBox(height: RkSpace.s2),
                  Text(
                    l10n.distributeInterestOff,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        for (final owner in view.owners)
          RkRuledCard(
            child: Padding(
              padding: const EdgeInsets.all(RkSpace.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(owner.name, style: theme.textTheme.titleSmall),
                  Text(
                    l10n.distributeRatio(owner.ratioWeight, view.ratioTotal),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.muted,
                      fontFeatures: RkType.tabular,
                    ),
                  ),
                  const SizedBox(height: RkSpace.s2),
                  // 02 §7.1 🔒 — *both lines per partner*. The interest line
                  // shows even at zero when the setting is on, so the reader
                  // sees the effect of the setting rather than a missing row.
                  if (view.interestEnabled)
                    DistributeFigureRow(
                      label: l10n.distributeOwnerInterest,
                      amount: money(owner.interest),
                    ),
                  DistributeFigureRow(
                    label: l10n.distributeOwnerShare,
                    amount: money(owner.share),
                  ),
                  DistributeFigureRow(
                    label: l10n.distributeOwnerTotal(owner.name),
                    amount: money(owner.total),
                    strong: true,
                  ),
                ],
              ),
            ),
          ),
        RkRuledCard(
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (view.interestEnabled)
                  DistributeFigureRow(
                    label: l10n.distributeTotalsInterest,
                    amount: money(view.interestTotal),
                    muted: true,
                  ),
                DistributeFigureRow(
                  label: l10n.distributeTotalsShare,
                  amount: money(view.shareTotal),
                  muted: true,
                ),
                // The two totals add to the year's figure exactly: the paise
                // the division could not split evenly are inside one owner's
                // own number, where the reader can see them (02 §7.1 🔒).
                DistributeFigureRow(
                  label: l10n.distributeTotalsEntry,
                  amount: money(view.interestTotal + view.shareTotal),
                  strong: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Step 3 — the one sentence that says what the button will do.
class _Confirm extends StatelessWidget {
  const _Confirm({required this.view, required this.postFailed});

  final DistributionView view;
  final bool postFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DistributeStepHeader(
          title: l10n.distributeStep3Title,
          help: view.quorumOfOne
              ? l10n.distributeConfirmSoloNote
              : l10n.distributeConfirmSharedNote,
        ),
        RkRuledCard(
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final owner in view.owners)
                  DistributeFigureRow(
                    label: owner.name,
                    amount: formatPaise(
                      owner.total.raw,
                      locale: locale,
                      showPaise: true,
                    ),
                  ),
                DistributeFigureRow(
                  label: l10n.distributeTotalsEntry,
                  amount: formatPaise(
                    (view.interestTotal + view.shareTotal).raw,
                    locale: locale,
                    showPaise: true,
                  ),
                  strong: true,
                ),
              ],
            ),
          ),
        ),
        if (view.readOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: RkSpace.s5, color: status.muted),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: Text(
                    l10n.distributeReadonly,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (postFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              0,
            ),
            child: Text(
              l10n.distributeFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// Every refusal of 13 §4.3, in words. The icon and the sentence carry it;
/// no colour is ever alone (07 §1 rule 3), and the app bar's back button is
/// the way out (07 §1 rule 6).
class _Blocked extends StatelessWidget {
  const _Blocked({required this.view});

  final DistributionView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final (String text, String? help) = switch (view.block!) {
      DistributionBlock.ceiling => (
        l10n.distributeBlockCeiling(
          formatPaise(view.excess.raw, locale: locale, showPaise: true),
        ),
        l10n.distributeBlockCeilingHelp,
      ),
      DistributionBlock.ratioNotRecorded => (
        l10n.distributeBlockRatioUnrecorded,
        null,
      ),
      DistributionBlock.ratioIncomplete => (
        l10n.distributeBlockRatioIncomplete,
        null,
      ),
      DistributionBlock.termsUnverified => (l10n.distributeBlockTerms, null),
      DistributionBlock.nothingToDistribute => (
        l10n.distributeBlockNothing(view.financialYearLabel),
        null,
      ),
      DistributionBlock.noPartners => (l10n.distributeBlockPartners, null),
      DistributionBlock.noProfitDistributed => (
        l10n.distributeBlockAccount,
        null,
      ),
      // ADR 2026-09-09b 🔒: not one of the three words.
      DistributionBlock.notShared => (l10n.distributeBlockNotshared, null),
    };
    return Padding(
      key: DistributeKeys.blocked,
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: RkSpace.s6),
          Icon(Icons.info_outline, color: status.muted),
          const SizedBox(height: RkSpace.s3),
          Text(text, style: theme.textTheme.titleMedium),
          if (help != null) ...[
            const SizedBox(height: RkSpace.s3),
            Text(
              help,
              style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
            ),
          ],
        ],
      ),
    );
  }
}
