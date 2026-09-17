// S10 — the month-close wizard (02 §8 🔒, 07 §13 🔒, 13 §3.2 rows S10 and
// S10.5), with S10.5 in place of step 4's action when the book is waiting on
// a phone (07 §28 🔒).
//
// **Four steps, 02 §8's own words, one screen each** (07 §13 🔒):
//
//   1. *Count your cash*      — a door per cash A/C to S5.5, the one screen
//                               that owns counting (02 §8.2 🔒). The row shows
//                               whether that A/C has been counted **inside
//                               this month**; not having been is a *warning*,
//                               never a block.
//   2. *Confirm each bank balance* — per A/C, `Matches ✓` / `Doesn't match ▸
//                               reconcile`. The reconcile door is **disabled
//                               with its reason**: the balance-check screen
//                               (S7.2) lands at M10, and a control that does
//                               nothing is worse than one that says why
//                               (13 §4.3, 07 §1 rule 6).
//   3. *Clear the tray*       — two lists, **never one**: what stops the close
//                               and what merely wants knowing. The split is
//                               not this screen's opinion; it is the type
//                               system's, because a blocker carries
//                               `core_ledger`'s [CloseBlocker] and a warning
//                               cannot (see `close_source.dart`).
//   4. *Confirm & lock*       — the declared balances, then the one lock
//                               action, disabled with its reason while
//                               anything blocks. The lock itself is a signed
//                               envelope recording those balances, the
//                               balance-vector hash and the `projector_version`
//                               (02 §8 step 4 🔒) — minted by the engine
//                               through the seam, never here.
//
// **Resumable 🔒** (07 §13): the step reached is written through the seam at
// every step change and read back on the next load. A shopkeeper will not
// finish this in one sitting, so a close that forgets where it was is a
// broken close, not an untidy one. The bank confirmations ride along for the
// same reason.
//
// The ledger reaches this screen through the feature-local [CloseSource] —
// `shared/ledger/` is another lane's folder this round, and nothing here
// imports `LocalLedger`. The only thing this feature takes from another is
// [CashCountPaths.forAccount], a path constant.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../cash_count/cash_count_paths.dart';
import '../close_source.dart';
import '../widgets/close_blocked_panel.dart';
import '../widgets/close_parts.dart';

/// Keys the wizard's parts answer to, so a test names a thing rather than a
/// string (the strings are asserted separately, in all three languages).
abstract final class CloseKeys {
  /// The step body currently on screen.
  static const step = Key('close.step');

  /// Step 1's list of cash A/Cs.
  static const cashList = Key('close.cash');

  /// Step 2's list of bank A/Cs.
  static const bankList = Key('close.banks');

  /// Step 3's **blocking** list — the things that stop the close.
  static const blocks = Key('close.tray.blocks');

  /// Step 3's **warning** list — the things that do not.
  static const warns = Key('close.tray.warns');

  /// Step 4's declared-balances summary.
  static const declared = Key('close.declared');

  /// The one lock action, enabled.
  static const lock = Key('close.lock');

  /// The S10.5 panel, in place of the lock action.
  static const blocked = Key('close.blocked');

  /// Move to the next step.
  static const next = Key('close.next');

  /// Move to the previous step.
  static const back = Key('close.back');
}

/// How locking is going (13 §4.3: default · loading · error, and the refusal
/// the engine may still raise).
enum _LockPhase { idle, working, done, error, refused }

/// S10 — close one book's month.
class MonthCloseScreen extends StatefulWidget {
  /// Creates the wizard for [bookId]'s [period].
  const MonthCloseScreen({
    super.key,
    required this.bookId,
    required this.period,
    this.source,
    this.onOpenCount,
    this.offline = false,
  });

  /// The book being closed.
  final String bookId;

  /// The month being closed.
  final YearMonth period;

  /// The ledger door; when null it is read from [CloseScope].
  final CloseSource? source;

  /// Opens a location — the S5.5 cash count sheet, at the path this screen
  /// builds from [CashCountPaths]. `closeRoutes` passes `context.push`; a test
  /// passes a recorder, so the *path* is what is asserted, not a callback.
  final void Function(String path)? onOpenCount;

  /// True while this device cannot reach the server. A chip, never a blocking
  /// banner (07 §1 rule 7 🔒) — a close is computed locally and offline does
  /// not stop it.
  final bool offline;

  @override
  State<MonthCloseScreen> createState() => _MonthCloseScreenState();
}

class _MonthCloseScreenState extends State<MonthCloseScreen> {
  CloseSource? _source;
  CloseView? _view;
  Object? _loadError;
  bool _started = false;

  CloseStep _step = CloseStep.countCash;
  bool _resumed = false;
  Set<String> _confirmed = {};
  final Set<String> _mismatched = {};

  _LockPhase _phase = _LockPhase.idle;
  List<CloseBlockerItem> _refusedBy = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = widget.source ?? CloseScope.maybeOf(context);
    if (source == null) {
      // No scope, no door: the error state, not a thrown red screen.
      if (_loadError == null && !_started) {
        setState(() => _loadError = StateError('no CloseSource in scope'));
      }
      return;
    }
    if (identical(source, _source) && _started) return;
    _source = source;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _loadError = null;
      _view = null;
    });
    try {
      final view = await source.loadClose(widget.bookId, widget.period);
      if (!mounted) return;
      setState(() {
        _view = view;
        // Resumable 🔒 — the saved step is where the closer starts.
        _step = view.progress.step;
        _resumed = view.progress.step != CloseStep.countCash;
        _confirmed = {...view.progress.confirmedBankIds};
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  /// Saves progress and moves to [step]. Progress is written at **every** step
  /// change (07 §13 *Resumable* 🔒); the screen does not wait on the write
  /// before drawing, so a slow disk never costs the closer a frame.
  void _goTo(CloseStep step) {
    setState(() {
      _step = step;
      _resumed = false;
    });
    _save(step);
  }

  void _save(CloseStep step) {
    final source = _source;
    if (source == null) return;
    unawaited(
      source
          .saveProgress(
            widget.bookId,
            widget.period,
            CloseProgress(step: step, confirmedBankIds: _confirmed),
          )
          // A close that cannot write its progress is still a close: the
          // closer keeps going and loses only the resume point.
          .catchError((Object _) {}),
    );
  }

  void _setBank(String accountId, {required bool matches}) {
    setState(() {
      if (matches) {
        _confirmed.add(accountId);
        _mismatched.remove(accountId);
      } else {
        _confirmed.remove(accountId);
        _mismatched.add(accountId);
      }
    });
    _save(_step);
  }

  Future<void> _lock() async {
    final source = _source;
    final view = _view;
    if (source == null || view == null) return;
    setState(() {
      _phase = _LockPhase.working;
      _refusedBy = const [];
    });
    try {
      await source.lock(
        bookId: view.bookId,
        period: view.period,
        declaredBalances: view.declaredBalances,
      );
      if (!mounted) return;
      setState(() => _phase = _LockPhase.done);
    } on CloseRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LockPhase.refused;
        _refusedBy = e.blockers;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _phase = _LockPhase.error);
    }
  }

  /// The month in words — *Aug 2026* in EN, *ਅਗਸਤ 2026* / *अगस्त 2026* in
  /// PA/HI, from the locale's own month strings (07 §1 rule 5 🔒).
  ///
  /// ⚠️ SPEC: 07 §13 🔒 writes the Home close card as `Close August ▸ 4 steps`
  /// — a **full** English month — while 07 §1 rule 5 🔒 says English
  /// abbreviates, and `shared_*.arb` carries abbreviated EN months only. The
  /// conservative reading is the global rule, so this says *Close Aug 2026*
  /// and mints no new month vocabulary (`shared_*.arb` is another lane's file
  /// besides). If the owner wants the card's wording, 07 §1 rule 5 needs an
  /// exception for month-scale labels and a full-name EN set in shared.
  String _month(AppLocalizations l) =>
      '${monthName(l, widget.period.month)} ${widget.period.year}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final view = _view;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RkFitText(l.closeTitle(_month(l)), maxLines: 1),
            if (view != null)
              RkFitText(
                l.closeBook(view.bookName),
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: RkStatusColors.of(context).muted),
              ),
          ],
        ),
      ),
      body: SafeArea(child: _body(l)),
    );
  }

  Widget _body(AppLocalizations l) {
    if (_loadError != null) {
      return RkErrorState(
        text: l.closeError,
        retryLabel: l.closeRetry,
        onRetry: _load,
      );
    }
    final view = _view;
    if (view == null) return RkSkeleton(label: l.closeSkeleton, rows: 5);
    return Column(
      children: [
        if (widget.offline)
          CloseQuietChip(
            label: l.connectionNoticeTitle,
            icon: Icons.cloud_off_outlined,
          ),
        if (view.readOnly) CloseBanner(reason: l.closeReadonly),
        CloseStepper(
          label: l.closeStepOf(_step.index + 1, CloseStep.values.length),
          index: _step.index,
          total: CloseStep.values.length,
        ),
        if (_resumed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: RkFitText(
                l.closeResumed,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: RkStatusColors.of(context).muted),
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            key: CloseKeys.step,
            padding: const EdgeInsets.only(bottom: RkSpace.s8),
            child: switch (_step) {
              CloseStep.countCash => _stepCash(l, view),
              CloseStep.confirmBanks => _stepBanks(l, view),
              CloseStep.clearTray => _stepTray(l, view),
              CloseStep.confirmAndLock => _stepLock(l, view),
            },
          ),
        ),
        _footer(l),
      ],
    );
  }

  // ── step 1 · Count your cash ───────────────────────────────────────────────

  Widget _stepCash(AppLocalizations l, CloseView view) {
    final locale = Localizations.localeOf(context);
    final status = RkStatusColors.of(context);
    return Column(
      key: CloseKeys.cashList,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CloseStepHeader(title: l.closeStep1Title, help: l.closeStep1Help),
        if (view.cashAccounts.isEmpty)
          CloseCard(
            child: CloseStateRow(
              icon: Icons.info_outline,
              tint: status.info,
              text: l.closeCashEmpty,
            ),
          )
        else
          for (final a in view.cashAccounts)
            CloseCard(
              padding: EdgeInsets.zero,
              rule: a.countedInPeriod ? status.success : status.warning,
              child: Semantics(
                button: true,
                label: l.closeCashOpen(a.name),
                child: InkWell(
                  onTap: () => widget.onOpenCount?.call(
                    CashCountPaths.forAccount(a.accountId),
                  ),
                  borderRadius: BorderRadius.circular(RkRadius.lg),
                  child: Padding(
                    padding: const EdgeInsets.all(RkSpace.cardPadding),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RkFitText(
                                a.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: RkSpace.s1),
                              RkFitText(
                                l.closeCashBookBalance(
                                  formatPaise(
                                    a.bookBalance.raw,
                                    locale: locale,
                                  ),
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: status.muted),
                              ),
                              const SizedBox(height: RkSpace.s2),
                              // Colour never alone: glyph + word + tint.
                              CloseStateRow(
                                icon: a.countedInPeriod
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                tint: a.countedInPeriod
                                    ? status.success
                                    : status.warning,
                                text: a.countedInPeriod
                                    ? l.closeCashCounted
                                    : l.closeCashNotCounted,
                                meta: a.lastCountDate == null
                                    ? l.closeCashNeverCounted
                                    : l.closeCashLastCounted(
                                        formatLedgerDate(
                                          a.lastCountDate!,
                                          strings: l,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: status.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  // ── step 2 · Confirm each bank balance ─────────────────────────────────────

  Widget _stepBanks(AppLocalizations l, CloseView view) {
    final locale = Localizations.localeOf(context);
    final status = RkStatusColors.of(context);
    return Column(
      key: CloseKeys.bankList,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CloseStepHeader(title: l.closeStep2Title, help: l.closeStep2Help),
        if (view.bankAccounts.isEmpty)
          CloseCard(
            child: CloseStateRow(
              icon: Icons.info_outline,
              tint: status.info,
              text: l.closeBankEmpty,
            ),
          )
        else ...[
          for (final a in view.bankAccounts)
            CloseCard(
              rule: _confirmed.contains(a.accountId)
                  ? status.success
                  : (_mismatched.contains(a.accountId)
                        ? status.warning
                        : status.hairline),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RkFitText(
                    a.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: RkSpace.s1),
                  RkFitText(
                    l.closeBankBookBalance(
                      formatPaise(a.bookBalance.raw, locale: locale),
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: status.muted),
                  ),
                  const SizedBox(height: RkSpace.s3),
                  Wrap(
                    spacing: RkSpace.s2,
                    runSpacing: RkSpace.s2,
                    children: [
                      ChoiceChip(
                        selected: _confirmed.contains(a.accountId),
                        onSelected: view.readOnly
                            ? null
                            : (_) => _setBank(a.accountId, matches: true),
                        avatar: const Icon(Icons.check, size: RkSpace.s4),
                        // Plain [Text] for the same reason as the footer: a
                        // chip in a [Wrap] is measured intrinsically.
                        label: Text(l.closeBankMatches),
                      ),
                      ChoiceChip(
                        selected: _mismatched.contains(a.accountId),
                        onSelected: view.readOnly
                            ? null
                            : (_) => _setBank(a.accountId, matches: false),
                        avatar: const Icon(
                          Icons.report_problem_outlined,
                          size: RkSpace.s4,
                        ),
                        label: Text(l.closeBankMismatch),
                      ),
                    ],
                  ),
                  // A difference wants the balance-check screen — which is
                  // M10 (13 §3.2 row S7.2). Disabled, with the reason and the
                  // fact that the close still goes on.
                  if (_mismatched.contains(a.accountId)) ...[
                    const SizedBox(height: RkSpace.s3),
                    CloseDisabledAction(
                      label: l.closeBankReconcile,
                      reason: l.closeBankReconcileUnavailable,
                      icon: Icons.rule,
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RkSpace.gutter,
              vertical: RkSpace.s2,
            ),
            child: RkFitText(
              l.closeBankConfirmed(_confirmed.length, view.bankAccounts.length),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: status.muted),
            ),
          ),
        ],
      ],
    );
  }

  // ── step 3 · Clear the tray ────────────────────────────────────────────────

  String _blockerText(AppLocalizations l, CloseBlockingItem b) {
    final who = b.deviceName ?? l.closeBlockedUnknownDevice;
    return switch (b.kind) {
      CloseBlocker.reviewFlagOpen => l.closeBlockerReviewFlag,
      CloseBlocker.suspenseNonZero => l.closeBlockerSuspense,
      CloseBlocker.advancePending => l.closeBlockerAdvancePending,
      CloseBlocker.monthOpen => l.closeBlockerMonthOpen,
      CloseBlocker.authorGapOpen => l.closeBlockerAuthorGap(who),
      CloseBlocker.heldEnvelope => l.closeBlockerHeld(who),
    };
  }

  String _warningText(AppLocalizations l, CloseWarningItem w) =>
      switch (w.kind) {
        CloseWarning.agedAdvance => l.closeWarningAgedAdvance,
        CloseWarning.unverifiedCount => l.closeWarningUnverifiedCount,
      };

  Widget _stepTray(AppLocalizations l, CloseView view) {
    final status = RkStatusColors.of(context);
    final tray = view.tray;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CloseStepHeader(title: l.closeStep3Title, help: l.closeStep3Help),
        if (tray.isEmpty)
          CloseCard(
            child: CloseStateRow(
              icon: Icons.check_circle_outline,
              tint: status.success,
              text: l.closeTrayEmpty,
            ),
          ),
        // Two lists, never one (07 §13 🔒). Each is its own card under its own
        // heading, and a list that is empty is simply absent — the closer is
        // never shown an empty *These stop the close* heading and left to
        // wonder.
        if (tray.blocks.isNotEmpty)
          CloseCard(
            key: CloseKeys.blocks,
            rule: status.danger,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RkFitText(
                  l.closeTrayBlocksTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                RkFitText(
                  l.closeTrayBlocksHelp,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: status.muted),
                ),
                const SizedBox(height: RkSpace.s2),
                for (final b in tray.blocks)
                  CloseStateRow(
                    icon: Icons.block,
                    tint: status.danger,
                    text: _blockerText(l, b),
                    meta: b.label,
                  ),
              ],
            ),
          ),
        if (tray.warns.isNotEmpty)
          CloseCard(
            key: CloseKeys.warns,
            rule: status.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RkFitText(
                  l.closeTrayWarnsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                RkFitText(
                  l.closeTrayWarnsHelp,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: status.muted),
                ),
                const SizedBox(height: RkSpace.s2),
                for (final w in tray.warns)
                  CloseStateRow(
                    icon: Icons.error_outline,
                    tint: status.warning,
                    text: _warningText(l, w),
                    meta: w.label,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ── step 4 · Confirm & lock, and S10.5 ─────────────────────────────────────

  Widget _stepLock(AppLocalizations l, CloseView view) {
    final locale = Localizations.localeOf(context);
    final status = RkStatusColors.of(context);
    final tray = view.tray;
    final declared = view.declaredBalances;
    final names = {
      for (final a in view.cashAccounts) a.accountId: a.name,
      for (final a in view.bankAccounts) a.accountId: a.name,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CloseStepHeader(title: l.closeStep4Title, help: l.closeStep4Help),
        CloseCard(
          key: CloseKeys.declared,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RkFitText(
                l.closeLockDeclared,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: RkSpace.s2),
              for (final e in declared.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
                  // Both sides flex: at 200 % a name and a grouped amount do
                  // not both fit 360 px, and an amount drawn past the edge is
                  // the silent failure 07 §1 rule 11 exists to prevent.
                  child: Row(
                    children: [
                      Expanded(child: RkFitText(names[e.key] ?? e.key)),
                      const SizedBox(width: RkSpace.s3),
                      Flexible(
                        child: RkFitText(
                          formatPaise(e.value.raw, locale: locale),
                          style: RkType.amountRow,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _lockAction(l, view, tray, status),
      ],
    );
  }

  Widget _lockAction(
    AppLocalizations l,
    CloseView view,
    CloseTray tray,
    RkStatusColors status,
  ) {
    // S10.5 takes the place of the action while entries are known to be
    // missing (07 §28 🔒, ADR 2026-09-05b §3–4).
    final gaps = tray.gaps;
    if (gaps.isNotEmpty) {
      final who = gaps.first.deviceName ?? l.closeBlockedUnknownDevice;
      return KeyedSubtree(
        key: CloseKeys.blocked,
        child: CloseBlockedPanel(
          title: l.closeBlockedTitle,
          body: l.closeBlockedBody(who),
          remindLabel: l.closeBlockedRemind(who),
          remindReason: l.closeBlockedRemindUnavailable,
          lockOffText: l.closeBlockedLockOff,
        ),
      );
    }
    final month = _month(l);
    if (tray.blocks.isNotEmpty) {
      return CloseCard(
        rule: status.danger,
        child: CloseDisabledAction(
          label: l.closeLockAction(month),
          reason: l.closeLockBlocked(tray.blocks.length),
          wayOut: l.closeLockBlockedAction,
          onWayOut: () => _goTo(CloseStep.clearTray),
        ),
      );
    }
    if (view.readOnly) {
      return CloseCard(
        child: CloseDisabledAction(
          label: l.closeLockAction(month),
          reason: l.closeReadonly,
        ),
      );
    }
    return CloseCard(
      child: switch (_phase) {
        _LockPhase.working => CloseStateRow(
          icon: Icons.hourglass_empty,
          tint: status.muted,
          text: l.closeLockWorking,
        ),
        _LockPhase.done => CloseStateRow(
          icon: Icons.lock_outline,
          tint: status.success,
          text: l.closeLockDone(month),
        ),
        _LockPhase.refused => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CloseStateRow(
              icon: Icons.block,
              tint: status.danger,
              text: l.closeLockRefused(_refusedBy.length),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => _goTo(CloseStep.clearTray),
                child: Text(l.closeLockBlockedAction),
              ),
            ),
          ],
        ),
        _LockPhase.error => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CloseStateRow(
              icon: Icons.error_outline,
              tint: status.danger,
              text: l.closeLockError,
            ),
            const SizedBox(height: RkSpace.s2),
            FilledButton(onPressed: _lock, child: Text(l.closeRetry)),
          ],
        ),
        _LockPhase.idle => FilledButton.icon(
          key: CloseKeys.lock,
          onPressed: _lock,
          icon: const Icon(Icons.lock_outline),
          label: RkFitText(l.closeLockAction(month)),
        ),
      },
    );
  }

  // ── chrome ─────────────────────────────────────────────────────────────────

  Widget _footer(AppLocalizations l) {
    final previous = _step.previous;
    final next = _step.next;
    if (previous == null && next == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s2,
        RkSpace.gutter,
        RkSpace.s4,
      ),
      child: CloseWizardFooter(
        backLabel: previous == null ? null : l.closeBack,
        onBack: previous == null ? null : () => _goTo(previous),
        backKey: CloseKeys.back,
        nextLabel: next == null ? null : l.closeNext,
        onNext: next == null ? null : () => _goTo(next),
        nextKey: CloseKeys.next,
      ),
    );
  }
}

/// What the route shows when the `:period` path parameter is not a month.
///
/// A malformed link is another screen's bug, but it still reaches a user, and
/// a red screen is the worst dead end there is (07 §1 rule 6). This says what
/// happened in the user's words and offers the only move that helps: back.
class CloseUnavailableScreen extends StatelessWidget {
  /// Creates the screen. [onBack] pops; the route passes `context.pop`.
  const CloseUnavailableScreen({super.key, required this.onBack});

  /// Leaves the wizard.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: RkErrorState(
          text: l.closeError,
          retryLabel: l.closeBack,
          onRetry: onBack,
        ),
      ),
    );
  }
}
