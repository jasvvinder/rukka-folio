// S6.2 — the one-by-one review stepper (07 §9 🔒). Each flagged entry
// full-screen: photo, amount, A/Cs, date/time, author, note, with **Approve /
// Reject (reason required → auto-reversal posts) / Skip (stays flagged)** and
// a quiet *ask for a better photo* link. Every decision advances; progress is
// shown as counts, never a percentage (11 §4.5). Nothing is approved unseen;
// rejecting one never blocks the rest.
//
// The entry under the reviewer's eyes is **already in the book** (02 §3 🔒):
// approving changes no balance, and rejecting posts a reversal beside it
// (02 §5). No screen state here implies the money is waiting.
//
// Consumer vocabulary throughout — *Money in / Money out*, never Dr/Cr
// (02 §10 🔒, CLAUDE.md rule 9).
//
// The list of entries is captured once, when the screen opens: the queue drops
// each entry as it is decided, and the stepper must keep counting to the total
// the reviewer was promised ("3 of 7").
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../review_queue.dart';
import '../widgets/reject_sheet.dart';

/// The S6.2 stepper for one S6.1 card.
class ReviewStepperScreen extends StatefulWidget {
  /// Creates the screen for [groupId].
  const ReviewStepperScreen({super.key, required this.groupId, this.onDone});

  /// The S6.1 card being stepped through.
  final String groupId;

  /// Leaves the stepper; falls back to popping the route.
  final VoidCallback? onDone;

  @override
  State<ReviewStepperScreen> createState() => _ReviewStepperScreenState();
}

class _ReviewStepperScreenState extends State<ReviewStepperScreen> {
  ReviewGroup? _group;
  List<ReviewEntry>? _entries;
  bool _resolved = false;
  bool _loading = false;
  int _index = 0;
  int _skipped = 0;
  bool _busy = false;
  bool _error = false;
  String? _photoAskedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    if (!mounted || _resolved) return;
    final queue = ReviewQueueScope.of(context);
    if (queue.current == null) {
      setState(() => _loading = true);
      try {
        await queue.refresh();
      } on ReviewQueueFailure {
        // The gone state below is the honest answer: nothing to step through.
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    if (!mounted) return;
    final snapshot = queue.current;
    final group = snapshot?.reviews
        .where((g) => g.id == widget.groupId)
        .firstOrNull;
    setState(() {
      _resolved = true;
      _group = group;
      _entries = group == null ? null : List.of(group.entries);
    });
  }

  void _leave() {
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _decide(ReviewDecision decision, {String? reason}) async {
    final group = _group;
    final entries = _entries;
    if (group == null || entries == null) return;
    final entry = entries[_index];
    final queue = ReviewQueueScope.of(context);
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await queue.decide(
        groupId: group.id,
        entryId: entry.id,
        decision: decision,
        reason: reason,
      );
      if (mounted) setState(() => _index++);
    } on ReviewQueueFailure {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final group = _group;
    if (group == null) return;
    final reason = await showRejectSheet(context, authorName: group.authorName);
    if (reason == null || !mounted) return;
    await _decide(ReviewDecision.reject, reason: reason);
  }

  // 07 §9: Skip leaves the flag exactly as it was — nothing is written.
  void _skip() => setState(() {
    _skipped++;
    _index++;
    _error = false;
  });

  Future<void> _askForPhoto() async {
    final group = _group;
    final entries = _entries;
    if (group == null || entries == null) return;
    final entry = entries[_index];
    final queue = ReviewQueueScope.of(context);
    try {
      await queue.askForPhoto(groupId: group.id, entryId: entry.id);
      if (mounted) setState(() => _photoAskedFor = entry.id);
    } on ReviewQueueFailure {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = _entries;
    final total = entries?.length ?? 0;
    final done = _index >= total;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inboxStepTitle),
        actions: [
          if (entries != null && !done)
            Padding(
              padding: const EdgeInsets.only(right: RkSpace.gutter),
              child: Center(
                child: Text(
                  l10n.inboxStepProgress(_index + 1, total),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (!_resolved || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = _entries;
    final group = _group;
    if (group == null || entries == null || entries.isEmpty) return _gone();
    if (_index >= entries.length) return _done(entries.length);
    return _entry(context, group, entries[_index]);
  }

  /// No dead end: the card is gone, and the way back is on screen.
  Widget _gone() {
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
              l10n.inboxStepGoneTitle,
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              l10n.inboxStepGoneBody,
              style: text.bodyLarge?.copyWith(color: status.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RkSpace.s4),
            FilledButton(
              onPressed: _leave,
              child: Text(l10n.inboxStepDoneAction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _done(int total) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: status.success),
            const SizedBox(height: RkSpace.s3),
            Text(
              l10n.inboxStepDoneTitle(total),
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              _skipped == 0
                  ? l10n.inboxStepDoneClear
                  : l10n.inboxStepDoneSkipped(_skipped),
              style: text.bodyLarge?.copyWith(color: status.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RkSpace.s4),
            FilledButton(
              onPressed: _leave,
              child: Text(l10n.inboxStepDoneAction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, ReviewGroup group, ReviewEntry e) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final now = RkScope.of(context).now();
    final note = e.note;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(RkSpace.gutter),
            children: [
              Text(
                l10n.inboxStepAuthor(group.authorName),
                style: text.bodyLarge,
              ),
              Text(
                l10n.inboxStepBook(group.bookName),
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s4),
              // The hero figure and its word stack rather than sit on one
              // line: MoneyText draws with `softWrap: false`, so at 200 %
              // "+₹23,400 Money in" is one unbreakable 392 px run on a 360 px
              // phone. Colour still never travels alone — the sign rides the
              // numerals and the word sits right under them (07 §1 rule 3) —
              // and the pair is announced as one label (13 §8).
              Semantics(
                container: true,
                excludeSemantics: true,
                label: _amountLabel(context, e.paise),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MoneyText(
                      e.paise,
                      // Tabular Mukta digits are wide: "+₹23,400" at the page
                      // size needs 392 px once the user is at 200 %, and the
                      // phone has 328. Above that the figure steps down one
                      // rung — still the loudest thing on the screen, still
                      // fully scaled, never clipped and never shrunk below
                      // body size (07 §1 rule 9, 13 §8).
                      style: MediaQuery.textScalerOf(context).scale(28) > 44
                          ? text.titleLarge
                          : text.headlineMedium,
                    ),
                    Text(
                      directionLabel(l10n, Vocabulary.consumer, e.paise) ?? '',
                      style: text.bodyLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              // 02 §3 🔒 — already posted, already counted.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.menu_book_outlined, size: 20, color: status.info),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: Text(
                      l10n.inboxStepPosted,
                      style: text.bodyMedium?.copyWith(color: status.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RkSpace.s4),
              _photo(context, e),
              const SizedBox(height: RkSpace.s4),
              _field(
                l10n.inboxStepFieldDate,
                formatLedgerDate(e.date, strings: l10n),
              ),
              _field(l10n.inboxStepFieldFrom, e.fromLabel),
              _field(l10n.inboxStepFieldTo, e.toLabel),
              _field(
                l10n.inboxStepFieldNote,
                note == null || note.trim().isEmpty
                    ? l10n.inboxRowNoteNone
                    : note,
              ),
              _field(
                l10n.inboxStepFieldSaved,
                l10n.inboxStepSavedAt(
                  formatListDate(
                    localDateOf(e.postedAt),
                    strings: l10n,
                    now: now,
                  ),
                  _clock(e.postedAt),
                ),
              ),
              if (_error) ...[
                const SizedBox(height: RkSpace.s3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: scheme.error, size: 20),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(
                      child: Text(
                        l10n.inboxStepError,
                        style: text.bodyMedium?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _actions(context),
      ],
    );
  }

  Widget _photo(BuildContext context, ReviewEntry e) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final asked = _photoAskedFor == e.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: status.sunk,
            borderRadius: BorderRadius.circular(RkRadius.md),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                e.hasPhoto
                    ? Icons.photo_outlined
                    : Icons.image_not_supported_outlined,
                color: status.muted,
              ),
              const SizedBox(width: RkSpace.s2),
              Flexible(
                child: Text(
                  e.hasPhoto ? l10n.inboxRowPhoto : l10n.inboxStepPhotoNone,
                  style: text.bodyMedium?.copyWith(color: status.muted),
                ),
              ),
            ],
          ),
        ),
        if (asked)
          Padding(
            padding: const EdgeInsets.only(top: RkSpace.s2),
            child: Text(
              l10n.inboxStepPhotoAsked(_group?.authorName ?? ''),
              style: text.bodyMedium?.copyWith(color: status.success),
            ),
          )
        else
          TextButton(
            onPressed: _busy ? null : _askForPhoto,
            child: Text(l10n.inboxStepPhotoAsk),
          ),
      ],
    );
  }

  Widget _field(String label, String value) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: status.muted)),
          Text(value, style: text.bodyLarge),
        ],
      ),
    );
  }

  /// Bottom-heavy: the three decisions sit in thumb reach (07 §1 rule 2).
  Widget _actions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: _busy
          ? Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(child: Text(l10n.inboxStepWorking)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => _decide(ReviewDecision.approve),
                  child: Text(l10n.inboxStepApprove),
                ),
                const SizedBox(height: RkSpace.s2),
                OutlinedButton(
                  onPressed: _reject,
                  child: Text(l10n.inboxStepReject),
                ),
                const SizedBox(height: RkSpace.s2),
                TextButton(onPressed: _skip, child: Text(l10n.inboxStepSkip)),
                Text(
                  l10n.inboxStepSkipHint,
                  style: text.bodySmall?.copyWith(color: status.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}

/// *"+₹23,400 Money in"* for the screen reader — amount and direction in one
/// announcement (13 §8 accessibility).
String _amountLabel(BuildContext context, int paise) {
  final l10n = AppLocalizations.of(context);
  final numerals = formatPaise(
    paise,
    locale: Localizations.localeOf(context),
    signed: true,
  );
  final word = directionLabel(l10n, Vocabulary.consumer, paise);
  return word == null ? numerals : '$numerals $word';
}

/// `HH:MM` in 24-hour form — Latin digits in every locale (11 §4.4).
String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
