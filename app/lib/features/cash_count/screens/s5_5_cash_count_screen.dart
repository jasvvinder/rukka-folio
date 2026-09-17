// S5.5 — the cash count sheet (07 §5.5 🔒, 02 §8.2 🔒, 13 §3.2 row S5.5).
//
// One screen, two modes, and the **account's subtype chooses** — never a
// toggle, never a caller's opinion (02 §8.2 *Two kinds of count* 🔒):
//
//   `cash`            → **verify**. The book already knows this balance, so
//                       the sheet shows it, states the difference in words
//                       ("₹230 less than the book — we'll adjust it") and, on
//                       a non-zero difference only, walks the one guided
//                       adjustment of S2.4 (ADR 2026-09-03b §2 🔒: this screen
//                       is that wizard's only door, and the amount is the
//                       engine's, never typed).
//   `cash_collection` → **collect**. Nobody knows what is in the gollak until
//                       it is opened, so the count *is* the record: the
//                       counted total alone, recognised as income in a chosen
//                       income A/C, with the denomination grid and two names
//                       required.
//
// What a count *means* is the engine's to say. `countPolicy`, `validateCount`
// and `resolveCount` (`core_ledger`, pinned by A-02-83…92) decide what the
// count must carry and what — if anything — posts; this screen collects the
// figures, shows their consequence in advance, and hands them over. **A count
// never moves money** (02 §8.2 🔒): saving always records the count, and only
// a non-zero difference or a collection recognition posts an entry.
//
// The ledger reaches this screen through the feature-local [CashCountSource]
// (see `cash_count_source.dart`) — `shared/ledger/` is another lane's folder
// this round, and nothing here imports `LocalLedger`.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../cash_count_money.dart';
import '../cash_count_source.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../widgets/count_parts.dart';
import '../widgets/denomination_grid.dart';

/// S5.5 — count one cash or collection A/C.
class CashCountScreen extends StatefulWidget {
  /// Creates the sheet for [accountId].
  const CashCountScreen({
    super.key,
    required this.accountId,
    this.source,
    this.readOnly = false,
  });

  /// The cash (`cash`) or collection (`cash_collection`) A/C being counted.
  final String accountId;

  /// The ledger door; when null it is read from [CashCountScope].
  final CashCountSource? source;

  /// The read-only variant (13 §2.3.1): a member who may read this book but
  /// not post in it. The sheet is legible, the action says why it is off.
  ///
  /// ⚠️ SPEC: 13 §7 gives posting rights by role, but the app has no
  /// book-role source yet (members are another lane's), so the shell passes
  /// this in. Defaulting to false is right for the solo book, whose only
  /// member is its owner.
  final bool readOnly;

  @override
  State<CashCountScreen> createState() => _CashCountScreenState();
}

class _CashCountScreenState extends State<CashCountScreen> {
  CashCountSource? _source;
  CashCountTarget? _target;
  Object? _loadError;
  bool _started = false;

  /// Note value (rupees) → count on the table.
  final Map<int, int> _notes = {};
  final _coins = TextEditingController();
  final _typedTotal = TextEditingController();
  final _countedBy = TextEditingController();
  final _witness = TextEditingController();

  bool _useGrid = false;
  String? _incomeId;
  bool _saving = false;
  bool _saveFailed = false;
  CashCountResult? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The source is an InheritedWidget, so it may only be read from here on.
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void didUpdateWidget(CashCountScreen old) {
    super.didUpdateWidget(old);
    // A different A/C — or a different door onto the ledger — is a different
    // count: drop what is on the sheet and read the new target.
    if (old.accountId != widget.accountId || old.source != widget.source) {
      _notes.clear();
      _coins.clear();
      _typedTotal.clear();
      _countedBy.clear();
      _witness.clear();
      _incomeId = null;
      _result = null;
      _saveFailed = false;
      _target = null;
      _loadError = null;
      _load();
    }
  }

  @override
  void dispose() {
    _coins.dispose();
    _typedTotal.dispose();
    _countedBy.dispose();
    _witness.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = widget.source ?? CashCountScope.maybeOf(context);
    _source = source;
    if (source == null) {
      // No ledger behind the route yet. An error with a retry, not a throw:
      // a red screen is a dead end (07 §1 rule 6).
      setState(() => _loadError = StateError('no CashCountSource in scope'));
      return;
    }
    try {
      final target = await source.loadTarget(widget.accountId);
      if (!mounted) return;
      setState(() {
        _target = target;
        _loadError = null;
        // Mandatory where it matters (02 §8.2 🔒): an organization book
        // records the notes for **every** cash account, so the grid opens
        // already on and its switch is locked with its reason beside it.
        _useGrid =
            countPolicy(
              bookType: target.bookType,
              account: target.account,
            ).denominationSheetMandatory ||
            target.isCollection;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _retry() {
    setState(() {
      _loadError = null;
      _target = null;
      _started = true;
    });
    _load();
  }

  // ---- the figures ---------------------------------------------------------

  /// The sheet as the engine's own object, or null when the grid is off.
  DenominationSheet? get _sheet {
    if (!_useGrid) return null;
    final notes = {
      for (final e in _notes.entries)
        if (e.value > 0) e.key: e.value,
    };
    return DenominationSheet(
      notes: notes,
      coinsPaise: Paise(paiseFromRupeeInput(_coins.text) ?? 0),
    );
  }

  /// What has been counted: the grid's total when the grid is open, the typed
  /// figure otherwise. Integer paise throughout.
  Paise get _counted => _useGrid
      ? _sheet!.total
      : Paise(paiseFromRupeeInput(_typedTotal.text) ?? 0);

  /// counted − book (02 §8.2; the same subtraction `resolveCount` makes, and
  /// the only figure the guided adjustment ever shows).
  Paise get _difference => _counted - _target!.bookBalance;

  bool get _hasFigure =>
      _useGrid || paiseFromRupeeInput(_typedTotal.text) != null;

  CashCountDraft _draft(BuildContext context) => CashCountDraft(
    accountId: widget.accountId,
    date: localDateOf(RkScope.of(context).now()),
    counted: _counted,
    sheet: _sheet,
    countedBy: _countedBy.text.trim(),
    witness: _witness.text.trim(),
    incomeAccountId: _incomeId,
  );

  /// Why Save is off, in the user's words — or null when it is on.
  ///
  /// The rules are the engine's: [validateCount] answers for the denomination
  /// sheet and the two names (02 §8.2 🔒), so the screen cannot drift from the
  /// policy it is meant to enforce.
  String? _blockedReason(BuildContext context, AppLocalizations l10n) {
    final target = _target!;
    if (widget.readOnly) return l10n.countBlockedReadonly;
    if (!_hasFigure) return l10n.countBlockedAmount;
    if (target.isCollection && !_counted.isDebit) {
      return l10n.countBlockedAmount;
    }
    final violations = validateCount(
      _draft(context).toEvent(bookId: target.bookId),
      bookType: target.bookType,
      account: target.account,
    );
    for (final v in violations) {
      switch (v.kind) {
        case ViolationKind.countSheetRequired:
          return l10n.countBlockedSheet;
        case ViolationKind.countNamesRequired:
          return l10n.countBlockedNames;
        default:
          return l10n.countError;
      }
    }
    if (target.isCollection && _incomeId == null) {
      return l10n.countIncomeRequired;
    }
    return null;
  }

  // ---- saving --------------------------------------------------------------

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final target = _target!;
    final draft = _draft(context);
    // The one door into the cash-count-difference wizard (S2.4; ADR
    // 2026-09-03b §2 🔒). Guided: the sheet states what will post, the user
    // confirms it, and the amount is never typed.
    if (!target.isCollection && !_difference.isZero) {
      final go = await _confirmDifference(l10n);
      if (go != true) return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      final result = await _source!.saveCount(draft);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _result = result;
      });
    } catch (_) {
      if (!mounted) return;
      // Nothing is cleared: every counted figure survives the failure, so
      // Try again costs one tap and not a recount (07 §1 rule 6).
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
  }

  Future<bool?> _confirmDifference(AppLocalizations l10n) {
    final locale = Localizations.localeOf(context);
    final amount = formatPaise(_difference.abs().raw, locale: locale);
    final body = _difference.isCredit
        ? l10n.countConfirmLess(amount)
        : l10n.countConfirmMore(amount);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Plain [Text] inside the dialog: its title and its action bar ask
        // children for intrinsic dimensions, which a LayoutBuilder — and so
        // [RkFitText] — cannot answer.
        title: Text(l10n.countConfirmTitle),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.countConfirmCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.countConfirmSave),
          ),
        ],
      ),
    );
  }

  void _done() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(_result);
      return;
    }
    // Nowhere to go back to (the sheet was the first route): start a fresh
    // count rather than leave the reader on a screen with one dead button.
    setState(() {
      _result = null;
      _notes.clear();
      _coins.clear();
      _typedTotal.clear();
      _countedBy.clear();
      _witness.clear();
      _incomeId = null;
    });
  }

  // ---- the screen ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = _target;
    final title = target == null
        ? l10n.countTitleVerify
        : target.isCollection
        ? l10n.countTitleCollect
        : l10n.countTitleVerify;
    return Scaffold(
      appBar: AppBar(title: RkFitText(title)),
      body: SafeArea(
        child: _loadError != null
            ? RkErrorState(
                text: l10n.countError,
                retryLabel: l10n.countRetry,
                onRetry: _retry,
              )
            : target == null
            ? RkSkeleton(label: l10n.countSkeleton)
            : _result != null
            ? _ResultPanel(result: _result!, target: target, onDone: _done)
            : _form(context, target, l10n),
      ),
      bottomNavigationBar: target == null || _result != null
          ? null
          : _saveBar(context, l10n),
    );
  }

  Widget _form(
    BuildContext context,
    CashCountTarget target,
    AppLocalizations l10n,
  ) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final policy = countPolicy(
      bookType: target.bookType,
      account: target.account,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s8),
      children: [
        if (widget.readOnly)
          CountBanner(
            title: l10n.countReadonlyBanner,
            reason: l10n.countBlockedReadonly,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The A/C being counted. User-typed, so it may be in any script
              // whatever the UI language (01 §1 rule 9).
              RkFitText(target.account.name, style: text.titleMedium),
              const SizedBox(height: RkSpace.s1),
              RkFitText(
                target.isCollection
                    ? l10n.countModeCollectHelp
                    : l10n.countModeVerifyHelp,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s1),
              RkFitText(
                target.lastCount == null
                    ? l10n.countLastCountedNever
                    : l10n.countLastCounted(
                        formatLedgerDate(target.lastCount!.date, strings: l10n),
                      ),
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s5),
              // The counted total, large at the top (07 §5.5). Plain ink and
              // no sign: it is a quantity of cash, not a direction, so no
              // credit/debit tint belongs on it (07 §1 rule 3).
              RkFitText(
                l10n.countTotalLabel,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              Semantics(
                label: l10n.countTotalSemantics(
                  formatPaise(_counted.raw, locale: locale),
                ),
                excludeSemantics: true,
                child: RkFitText(
                  formatPaise(_counted.raw, locale: locale),
                  style: RkType.amountHero.copyWith(
                    color: text.displayLarge?.color,
                    fontFeatures: RkType.tabular,
                  ),
                ),
              ),
              if (!target.isCollection) ...[
                const SizedBox(height: RkSpace.s3),
                _BookRow(bookBalance: target.bookBalance),
                const SizedBox(height: RkSpace.s2),
                _DifferenceLine(difference: _difference),
              ],
              const SizedBox(height: RkSpace.s4),
            ],
          ),
        ),
        _gridSection(context, target, policy, l10n),
        _namesSection(context, target, policy, l10n),
        if (target.isCollection) _incomeSection(context, target, l10n),
      ],
    );
  }

  Widget _gridSection(
    BuildContext context,
    CashCountTarget target,
    CountPolicy policy,
    AppLocalizations l10n,
  ) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    // Collection counts and organization books both record the notes; every
    // other book may count by grid or by a single figure (02 §8.2 🔒).
    final locked = policy.denominationSheetMandatory || target.isCollection;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: RkFitText(l10n.countGridToggle),
            subtitle: locked
                ? RkFitText(
                    target.isCollection
                        ? l10n.countModeCollectHelp
                        : l10n.countGridRequired,
                    style: text.bodySmall?.copyWith(color: status.muted),
                  )
                : null,
            value: _useGrid,
            onChanged: locked || widget.readOnly
                ? null
                : (on) => setState(() => _useGrid = on),
          ),
          if (_useGrid) ...[
            DenominationGrid(
              counts: _notes,
              showTwoThousand: target.lastCount?.usedTwoThousand ?? false,
              enabled: !widget.readOnly,
              onChanged: (value, count) =>
                  setState(() => _notes[value] = count),
            ),
            const SizedBox(height: RkSpace.s4),
            TextField(
              controller: _coins,
              enabled: !widget.readOnly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.countCoinsLabel,
                helperText: l10n.countCoinsHelp,
                helperMaxLines: 3,
                prefixText: rupeeSign,
              ),
            ),
          ] else
            TextField(
              controller: _typedTotal,
              enabled: !widget.readOnly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.countTotalLabel,
                helperText: l10n.countTotalHelp,
                helperMaxLines: 3,
                prefixText: rupeeSign,
              ),
            ),
          const SizedBox(height: RkSpace.s5),
        ],
      ),
    );
  }

  Widget _namesSection(
    BuildContext context,
    CashCountTarget target,
    CountPolicy policy,
    AppLocalizations l10n,
  ) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _countedBy,
            enabled: !widget.readOnly,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l10n.countNamesCountedBy),
          ),
          const SizedBox(height: RkSpace.s3),
          TextField(
            controller: _witness,
            enabled: !widget.readOnly,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l10n.countNamesWitness),
          ),
          if (policy.twoNamesRequired) ...[
            const SizedBox(height: RkSpace.s2),
            RkFitText(
              l10n.countNamesRequired,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
          ],
          const SizedBox(height: RkSpace.s5),
        ],
      ),
    );
  }

  Widget _incomeSection(
    BuildContext context,
    CashCountTarget target,
    AppLocalizations l10n,
  ) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final chosen = _incomeId == null
        ? null
        : target.incomeAccounts
              .where((a) => a.id == _incomeId)
              .map((a) => a.name)
              .firstOrNull;
    if (target.incomeAccounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RkFitText(l10n.countIncomeLabel, style: text.titleSmall),
            const SizedBox(height: RkSpace.s2),
            // Blocked, with the way out named (07 §1 rule 6 🔒).
            Text(l10n.countIncomeEmpty, style: text.bodyMedium),
          ],
        ),
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
      title: RkFitText(l10n.countIncomeLabel),
      subtitle: RkFitText(
        chosen ?? l10n.countIncomeRequired,
        style: text.bodySmall?.copyWith(
          color: chosen == null ? status.muted : null,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: widget.readOnly ? null : () => _pickIncome(target, l10n),
    );
  }

  Future<void> _pickIncome(
    CashCountTarget target,
    AppLocalizations l10n,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(RkSpace.cardPadding),
              child: RkFitText(
                l10n.countIncomeLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // A plain chosen/not-chosen row rather than a radio group: the
            // sheet closes on the tap, so the selection lives on the screen
            // beneath it, and the tick keeps the state out of colour alone.
            for (final a in target.incomeAccounts)
              ListTile(
                title: RkFitText(a.name),
                trailing: a.id == _incomeId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(a.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _incomeId = picked);
  }

  Widget _saveBar(BuildContext context, AppLocalizations l10n) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final reason = _blockedReason(context, l10n);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Offline is normal, not an error: a quiet chip, never a blocking
            // banner, and Save behaves identically (07 §1 rule 7 🔒).
            _OfflineChip(label: l10n.countOffline),
            if (_saveFailed) ...[
              RkFitText(
                l10n.countSaveError,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: RkSpace.s2),
            ],
            if (reason != null) ...[
              // Disabled, and it says why (13 §4.3; 07 §1 rule 6).
              RkFitText(
                reason,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s2),
            ],
            FilledButton(
              onPressed: reason != null || _saving ? null : _save,
              child: Text(
                _saving
                    ? l10n.countSaving
                    : _saveFailed
                    ? l10n.countRetry
                    : l10n.countSave,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The book's own figure for this cash A/C — verify mode only (02 §8.2).
class _BookRow extends StatelessWidget {
  const _BookRow({required this.bookBalance});

  final Paise bookBalance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    return Wrap(
      spacing: RkSpace.s3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        RkFitText(
          l10n.countBookLabel,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: status.muted),
        ),
        Text(
          formatPaise(bookBalance.raw, locale: locale),
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontFeatures: RkType.tabular),
        ),
      ],
    );
  }
}

/// The difference, stated in words (07 §5.5 🔒). The icon and the sentence
/// carry the meaning; no colour is asked to do it alone (07 §1 rule 3).
class _DifferenceLine extends StatelessWidget {
  const _DifferenceLine({required this.difference});

  final Paise difference;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final amount = formatPaise(difference.abs().raw, locale: locale);
    final (IconData icon, String words, Color tint) = switch (difference) {
      final d when d.isZero => (
        Icons.check_circle_outline,
        l10n.countDifferenceMatch,
        status.success,
      ),
      final d when d.isCredit => (
        Icons.south_east,
        l10n.countDifferenceLess(amount),
        status.debit,
      ),
      _ => (Icons.north_east, l10n.countDifferenceMore(amount), status.credit),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: RkSpace.s5, color: tint),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: RkFitText(
            words,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// The quiet sync chip, shown only while sync is not caught up.
class _OfflineChip extends StatelessWidget {
  const _OfflineChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final sync = RkScope.of(context).sync;
    return StreamBuilder<SyncStatus>(
      stream: sync.status,
      initialData: sync.current,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status is! Offline && status is! SavedWillSync) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: RkSpace.s2),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: CountQuietChip(label: label, icon: Icons.cloud_off),
          ),
        );
      },
    );
  }
}

/// What the count came to — the engine's outcome, said plainly, with the one
/// way onward (07 §1 rule 6: no dead ends).
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.result,
    required this.target,
    required this.onDone,
  });

  final CashCountResult result;
  final CashCountTarget target;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);
    final date = formatLedgerDate(result.date, strings: l10n);
    final (String headline, String note) = switch (result.outcome) {
      CountVerified() => (
        l10n.countResultVerified(date),
        l10n.countResultVerifiedNote,
      ),
      final CountAdjustment a => (
        l10n.countResultAdjusted(
          formatPaise(a.difference.abs().raw, locale: locale),
        ),
        l10n.countResultAdjustedNote,
      ),
      CountRecognition() => (
        l10n.countResultCollected(
          formatPaise(
            Paise.sum(
              result.outcome.lines
                  .where((l) => l.accountId == target.account.id)
                  .map((l) => l.amount),
            ).abs().raw,
            locale: locale,
          ),
          result.incomeAccountName ?? target.account.name,
        ),
        l10n.countResultCollectedNote,
      ),
    };
    return ListView(
      padding: const EdgeInsets.all(RkSpace.s6),
      children: [
        const SizedBox(height: RkSpace.s6),
        // Success is quiet (01 §3): a tick, a sentence, and the way on.
        Icon(Icons.check_circle_outline, color: status.success),
        const SizedBox(height: RkSpace.s3),
        RkFitText(headline, style: text.titleMedium),
        const SizedBox(height: RkSpace.s2),
        Text(note, style: text.bodyMedium?.copyWith(color: status.muted)),
        const SizedBox(height: RkSpace.s6),
        FilledButton(
          onPressed: onDone,
          child: RkFitText(l10n.countResultDone, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
