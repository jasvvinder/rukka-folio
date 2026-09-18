// S7.1 — the import inbox (13 §3.2 row S7.1; 07 §11 item 2 🔒, 02 §10 🔒).
//
// **Parsed lines land here, never in the ledger** (02 §10 🔒). Each row shows
// the date, the bank's own words in muted type, the **Money in / Money out**
// amount, and **one question** — *Where did it come from?* / *Where did it
// go?* — with a state chip: `Matched ✓` · `Suggested` · `New` · `Transfer?` ·
// `Suspense`. The user never sees or chooses a side.
//
// Every decision behind a chip belongs to [ImportSource]: the auto-link, the
// learned rules, the opposite-line search. This screen renders them and sends
// the user's answers back. That is what keeps *approving teaches the rule*
// (07 §11 item 3 🔒) true no matter which source is installed.
//
// **Partial submit is always allowed** (07 §11 item 1 🔒): answered lines are
// recorded, the rest stay here and the screen says how many.
//
// **Nothing posts this round.** [ImportSource.posting] is asked before the
// primary action is drawn: over the real book it answers
// [ImportPostingBlocked] because 02 §10 🔒 requires `bank_text` stored
// verbatim on the envelope and the engine has no such field. The action is
// then **disabled with its reason in one plain sentence**, beside *Keep for
// later* — never an error, never a dead end (07 §1 rule 6, 13 §4.3).
//
// States (13 §4.3): ruled skeleton · error-with-retry · empty · populated.
// Offline says nothing: every step here is on-device (04).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../balance_check.dart';
import '../import_lines.dart';
import '../import_source.dart';
import '../parse/parsed_statement.dart';
import '../widgets/inbox_parts.dart';
import 's7_2_balance_check_screen.dart';

/// S7.1 — sort the lines a statement read.
class ImportInboxScreen extends StatefulWidget {
  /// Creates the screen.
  const ImportInboxScreen({
    super.key,
    required this.statement,
    this.source,
    this.bookId,
    this.onKeepForLater,
  });

  /// The statement whose lines are waiting.
  final ParsedStatement statement;

  /// The ledger door; read from [ImportScope] when absent.
  final ImportSource? source;

  /// The book; read from [ImportScope] when absent.
  final String? bookId;

  /// *Keep for later* — leaves everything in the inbox and goes back. Null
  /// pops the route, which is the same promise.
  final VoidCallback? onKeepForLater;

  @override
  State<ImportInboxScreen> createState() => _ImportInboxScreenState();
}

class _ImportInboxScreenState extends State<ImportInboxScreen> {
  ImportSource? _source;
  String? _bookId;
  bool _started = false;

  List<ImportLine>? _lines;
  List<ImportCounterpart> _counterparts = const [];
  ImportBalanceCheck? _check;
  Object? _error;

  String? _picking;
  String? _noting;
  final _expanded = <String>{};

  int _recorded = 0;
  bool _kept = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ImportScope.maybeOf(context);
    final source = widget.source ?? scope?.source;
    final bookId = widget.bookId ?? scope?.bookId;
    if (source == null || bookId == null) {
      // No scope, no door: the error state, not a thrown red screen
      // (07 §1 rule 6).
      if (_error == null && !_started) {
        setState(() => _error = StateError('no ImportScope'));
      }
      return;
    }
    if (identical(source, _source) && _started) return;
    _source = source;
    _bookId = bookId;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final source = _source;
    final bookId = _bookId;
    if (source == null || bookId == null) return;
    setState(() {
      _error = null;
      _lines = null;
    });
    try {
      final lines = await source.classify(
        bookId: bookId,
        statement: widget.statement,
      );
      final counterparts = await source.counterparts(bookId);
      final check = await _balanceCheck(source);
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _counterparts = counterparts;
        _check = check;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// S7.2's input: the statement's own opening and closing against the book's
  /// balance on those dates (07 §11 item 1 🔒).
  Future<ImportBalanceCheck> _balanceCheck(ImportSource source) async {
    final lines = widget.statement.lines;
    if (lines.isEmpty) {
      return ImportBalanceCheck.of(
        widget.statement,
        ledgerOpeningPaise: null,
        ledgerClosingPaise: null,
      );
    }
    final accountId = widget.statement.accountId;
    // The opening is the book on the day *before* the statement starts.
    final opening = await source.ledgerBalanceOn(
      accountId,
      lines.first.date.addDays(-1),
    );
    final closing = await source.ledgerBalanceOn(accountId, lines.last.date);
    return ImportBalanceCheck.of(
      widget.statement,
      ledgerOpeningPaise: opening,
      ledgerClosingPaise: closing,
    );
  }

  List<ImportLine> get _all => _lines ?? const [];

  int get _answered => _all.where((l) => l.isClassified).length;

  int get _waiting => _all.length - _answered;

  void _replace(ImportLine line, {List<String> remove = const []}) {
    final next = <ImportLine>[
      for (final l in _all)
        if (!remove.contains(l.id)) (l.id == line.id ? line : l),
    ];
    setState(() => _lines = next);
  }

  Future<void> _run(Future<ImportLine> Function(ImportSource s) verb) async {
    final source = _source;
    if (source == null) return;
    final line = await verb(source);
    if (!mounted) return;
    _replace(line);
  }

  Future<void> _answer(ImportLine line, ImportCounterpart counterpart) async {
    final source = _source;
    if (source == null) return;
    final next = await source.answer(line, counterpart);
    if (!mounted) return;
    setState(() => _picking = null);
    _replace(next);
    // Rules learn from corrections (07 §11 item 3 🔒): the *Always? Yes/No*
    // toast, and only where something was actually corrected.
    if (next.correctedFrom != null) _askAlways(next);
  }

  void _askAlways(ImportLine line) {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RkFitText(l.importInboxAlwaysQ(line.counterpartName ?? '')),
            const SizedBox(height: RkSpace.s1),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    _source?.teachRule(line);
                  },
                  child: RkFitText(l.importInboxAlwaysYes),
                ),
                const SizedBox(width: RkSpace.s2),
                TextButton(
                  onPressed: messenger.hideCurrentSnackBar,
                  child: RkFitText(l.importInboxAlwaysNo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTransfer(ImportLine line) async {
    final source = _source;
    if (source == null) return;
    final pair = await source.confirmTransfer(line);
    if (!mounted) return;
    _replace(pair.line, remove: pair.collapsedIds);
  }

  /// The pair is **not** a transfer: both halves go back to their one
  /// question rather than staying stuck on it (07 §1 rule 6).
  void _rejectTransfer(ImportLine line) {
    final otherId = line.pairedLineId;
    setState(() {
      _lines = [
        for (final l in _all)
          if (l.id == line.id || l.id == otherId)
            l.copyWith(state: ImportLineState.needsAnswer, clearPair: true)
          else
            l,
      ];
    });
  }

  Future<void> _submit() async {
    final source = _source;
    if (source == null) return;
    final outcomes = await source.submit(_all);
    if (!mounted) return;
    final done = <String>{
      for (final o in outcomes)
        if (o is ImportPosted || o is ImportLinked) o.lineId,
    };
    setState(() {
      _recorded = done.length;
      _lines = [
        for (final l in _all)
          if (!done.contains(l.id)) l,
      ];
    });
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: RkFitText(
            '${l.importInboxRecorded(done.length)} · '
            '${l.importInboxLeft(_all.length)}',
          ),
        ),
      );
  }

  void _keepForLater() {
    setState(() => _kept = true);
    final keep = widget.onKeepForLater;
    if (keep != null) {
      keep();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _openBalanceCheck() {
    final check = _check;
    if (check == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportBalanceCheckScreen(check: check),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lines = _lines;
    return Scaffold(
      appBar: AppBar(
        title: RkFitText(l.importInboxTitle, maxLines: 1),
        actions: [
          // An icon, not a word: at 200 % a worded action beside the title
          // overflows a 360 px bar by 71 px (07 §1 rule 11). The label lives
          // in the tooltip and in Semantics, so it is long-pressed and read
          // aloud rather than lost.
          if (_check != null)
            IconButton(
              key: ImportInboxKeys.balance,
              icon: const Icon(Icons.rule),
              tooltip: l.importInboxBalanceAction,
              onPressed: _openBalanceCheck,
            ),
        ],
      ),
      body: SafeArea(
        child: switch ((lines, _error)) {
          (_, final Object _) => RkErrorState(
            text: l.importInboxError,
            retryLabel: l.importInboxRetry,
            onRetry: _load,
          ),
          (null, _) => RkSkeleton(label: l.importInboxSkeleton, rows: 4),
          (final List<ImportLine> list, _) => _body(l, list),
        },
      ),
    );
  }

  Widget _body(AppLocalizations l, List<ImportLine> lines) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return ListView(
      key: const PageStorageKey<String>('import.inbox'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            RkSpace.s1,
          ),
          child: RkFitText(
            l.importInboxNotposted,
            style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
          ),
        ),
        if (lines.isEmpty)
          _Empty(recorded: _recorded, kept: _kept)
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
            child: RkFitText(
              l.importInboxWaiting(_waiting),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          for (final line in lines)
            ImportLineCard(
              line: line,
              paired: _pairedOf(line),
              counterparts: _counterparts,
              picking: _picking == line.id,
              noting: _noting == line.id,
              expanded: _expanded.contains(line.id),
              onToggleBankText: () => setState(
                () => _expanded.contains(line.id)
                    ? _expanded.remove(line.id)
                    : _expanded.add(line.id),
              ),
              onUnlink: () => _run((s) => s.unlink(line)),
              onApprove: () => _run((s) => s.approveSuggestion(line)),
              onOpenPicker: () => setState(
                () => _picking = _picking == line.id ? null : line.id,
              ),
              onPick: (c) => _answer(line, c),
              onCreate: (name) async {
                final source = _source;
                final bookId = _bookId;
                if (source == null || bookId == null) return;
                final created = await source.createCounterpart(
                  bookId,
                  name: name,
                );
                if (!mounted) return;
                _counterparts = await source.counterparts(bookId);
                if (!mounted) return;
                await _answer(line, created);
              },
              onSuspense: () => _run((s) => s.toSuspense(line)),
              onConfirmTransfer: () => _confirmTransfer(line),
              onRejectTransfer: () => _rejectTransfer(line),
              onToggleNote: () =>
                  setState(() => _noting = _noting == line.id ? null : line.id),
              onNote: (text) async {
                await _run((s) => s.addNote(line, text));
                if (!mounted) return;
                setState(() => _noting = null);
              },
            ),
          _SubmitBlock(
            answered: _answered,
            posting: _source?.posting ?? const ImportPostingReady(),
            onSubmit: _submit,
            onKeep: _keepForLater,
          ),
        ],
        const SizedBox(height: RkSpace.s8),
      ],
    );
  }

  ImportLine? _pairedOf(ImportLine line) {
    final id = line.pairedLineId;
    if (id == null) return null;
    for (final l in _all) {
      if (l.id == id) return l;
    }
    return null;
  }
}

/// The empty state — and, after a submit, what became of the lines
/// (07 §1 rule 12).
class _Empty extends StatelessWidget {
  const _Empty({required this.recorded, required this.kept});

  final int recorded;
  final bool kept;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(
            recorded > 0 ? l.importInboxRecorded(recorded) : l.importInboxEmpty,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: RkSpace.s2),
          RkFitText(
            kept ? l.importInboxBlockedKept : l.importInboxEmptyNext,
            style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
          ),
        ],
      ),
    );
  }
}

/// The primary action, and the reason when it cannot be taken.
///
/// 13 §4.3's **disabled-with-reason**: the sentence sits above the button, in
/// plain words, with *Keep for later* beside it — the path out that 07 §1
/// rule 6 requires of every blocked action.
class _SubmitBlock extends StatelessWidget {
  const _SubmitBlock({
    required this.answered,
    required this.posting,
    required this.onSubmit,
    required this.onKeep,
  });

  final int answered;
  final ImportPostingAvailability posting;
  final VoidCallback onSubmit;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final blocked = posting is ImportPostingBlocked
        ? (posting as ImportPostingBlocked).reason
        : null;
    final reason = blocked == null
        ? (answered == 0 ? l.importInboxSubmitNone : null)
        : switch (blocked) {
            ImportUnavailableReason.bankTextHasNowhereToLand =>
              l.importInboxBlockedBanktext,
            ImportUnavailableReason.periodLocked => l.importInboxBlockedLocked,
            ImportUnavailableReason.noLedger => l.importInboxBlockedNoledger,
          };
    final enabled = blocked == null && answered > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reason != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: RkIcon.grid, color: status.info),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: RkFitText(reason, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s2),
          ],
          FilledButton(
            key: ImportInboxKeys.submit,
            onPressed: enabled ? onSubmit : null,
            child: RkFitText(l.importInboxSubmit(answered)),
          ),
          const SizedBox(height: RkSpace.s1),
          TextButton(
            key: ImportInboxKeys.keep,
            onPressed: onKeep,
            child: RkFitText(l.importInboxBlockedKeep),
          ),
        ],
      ),
    );
  }
}
