// S8.3 Family reconciliation (13 §3.2 row S8.3, design D5; 07 §10 🔒; 02 §6 🔒;
// ADR 2026-09-05e §7 🔒), reached from S8.1 (Menu → Reports).
//
// The whole report in one sentence from 02 §6 🔒: *for every pair,
// balance(A→B) + balance(B→A) must equal 0; any non-zero pair is listed with
// the entries composing it*. 07 §10 adds what that normally looks like —
// *"a single proud green ✓"*. A tick is a colour, so the verdict is written in
// words beside it and never carried by the colour alone (07 §1 rule 3).
//
// The third state is the one that is easy to get wrong and is 🔒: a pair whose
// other side sits in a personal or sub-family book this device holds no key for
// (04 §5.2) is **one-sided · unconfirmed**, *never a mismatch* (ADR
// 2026-09-05e §7). Nothing is wrong with those books; the check simply cannot
// run, and saying "mismatch" would accuse a relative of a discrepancy the app
// has no way to see.
//
// This is a CONSUMER surface (02 §10 🔒, CLAUDE.md rule 9): every figure is
// *Money in / Money out*, never Dr/Cr. The engine's posting does not bend to
// it — the figures are `LocalLedger.watchReconciliation`, which is
// `InterBook.reconcile` (A-02-79, A-02-81, A-ref-6, A-05e-10) with the book
// names and dates a reader needs attached. There is no second derivation here.
import 'package:core_ledger/core_ledger.dart' show PairStatus;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Where the pairs come from. The default is the ledger's own live read; a
/// test injects one to exercise the loading and error states of 13 §4.3.
typedef ReconciliationSource = Stream<List<ReconciliationPair>> Function(
  LocalLedger,
);

/// The shipped source: the projection, live (02 §6 🔒).
Stream<List<ReconciliationPair>> ledgerReconciliation(LocalLedger ledger) =>
    ledger.watchReconciliation();

/// Above this text scale a label and its figure no longer fit one line on a
/// 360 px phone, and the figure drops under the label. A fraction of the
/// screen's own budget, not a design token — the pair only has to agree with
/// itself (the S8.2 precedent).
/// S8.3 — the Family Reconciliation report.
class FamilyReconciliationScreen extends StatefulWidget {
  /// Creates the screen.
  const FamilyReconciliationScreen({
    super.key,
    this.source = ledgerReconciliation,
    this.onOpenEntry,
    this.onMoveMoney,
  });

  /// Where the pairs are read from.
  final ReconciliationSource source;

  /// Opens S4.1 for one composing entry — the audit trail one tap from any
  /// entry (07 §1 rule 8). Null leaves the rows un-tappable; the report is
  /// still a report.
  final void Function(String entryId)? onOpenEntry;

  /// The empty state's one next action (07 §1 rule 12): make an inter-book
  /// movement. Null while S2.3 has no route here — the sentence above it
  /// still explains, so the screen is not a dead end either way.
  final VoidCallback? onMoveMoney;

  @override
  State<FamilyReconciliationScreen> createState() =>
      _FamilyReconciliationScreenState();
}

class _FamilyReconciliationScreenState
    extends State<FamilyReconciliationScreen> {
  Stream<List<ReconciliationPair>>? _stream;

  /// Memoised so a rebuild does not resubscribe the drift stream every frame;
  /// [_retry] drops it, which is what makes the error state's *Try again* a
  /// real retry rather than a repaint.
  Stream<List<ReconciliationPair>> _pairs() =>
      _stream ??= widget.source(LedgerScope.of(context));

  void _retry() => setState(() => _stream = null);

  @override
  void didUpdateWidget(FamilyReconciliationScreen old) {
    super.didUpdateWidget(old);
    // A new source is a new read, not a repaint of the old one: without this
    // the memoised stream outlives the widget that named it.
    if (old.source != widget.source) _stream = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.reportsFamilyReconciliationRowTitle,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<ReconciliationPair>>(
          stream: _pairs(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorState(
                text: l10n.reportsReconciliationError,
                onRetry: _retry,
              );
            }
            final pairs = snap.data;
            if (pairs == null) {
              return _Skeleton(label: l10n.reportsReconciliationSkeleton);
            }
            if (pairs.isEmpty) {
              return _EmptyState(onMoveMoney: widget.onMoveMoney);
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: RkSpace.s8),
              children: [
                _Summary(pairs: pairs),
                for (final pair in pairs)
                  _PairCard(pair: pair, onOpenEntry: widget.onOpenEntry),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The one line the report normally is (07 §10): a tick and, beside it, the
/// verdict in words. When something is off it counts what, never louder than
/// it must be — an unconfirmed pair is not a failure (ADR 2026-09-05e §7 🔒).
class _Summary extends StatelessWidget {
  const _Summary({required this.pairs});

  final List<ReconciliationPair> pairs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final off = pairs.where((p) => p.status == PairStatus.mismatch).length;
    final unconfirmed = pairs.where((p) => p.isUnconfirmed).length;

    final (
      IconData icon,
      Color tint,
      String headline,
      String detail,
    ) = switch ((off, unconfirmed)) {
      (0, 0) => (
        Icons.check_circle_outline,
        status.success,
        l10n.reportsReconciliationSummaryOk,
        l10n.reportsReconciliationSummaryOkDetail,
      ),
      (0, _) => (
        Icons.help_outline,
        status.info,
        l10n.reportsReconciliationSummaryUnconfirmed(unconfirmed),
        l10n.reportsReconciliationUnconfirmedDetail,
      ),
      _ => (
        Icons.warning_amber_outlined,
        status.warning,
        l10n.reportsReconciliationSummaryOff(off),
        l10n.reportsReconciliationMismatchDetail,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: RkSpace.s5),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(headline, style: text.titleMedium),
                const SizedBox(height: RkSpace.s1),
                Text(
                  detail,
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One pair of books: who it is between, what it says in words, its figures,
/// and — when it does not net to zero — the entries composing it (02 §6 🔒).
class _PairCard extends StatelessWidget {
  const _PairCard({required this.pair, this.onOpenEntry});

  final ReconciliationPair pair;
  final void Function(String entryId)? onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;

    final other =
        pair.counterpartBookName ?? l10n.reportsReconciliationPairSealed;
    final (
      IconData icon,
      Color tint,
      String word,
      String detail,
    ) = switch (pair.status) {
      PairStatus.balanced => (
        Icons.check_circle_outline,
        status.success,
        l10n.reportsReconciliationStatusBalanced,
        l10n.reportsReconciliationBalancedDetail,
      ),
      PairStatus.mismatch => (
        Icons.warning_amber_outlined,
        status.warning,
        l10n.reportsReconciliationStatusMismatch,
        l10n.reportsReconciliationMismatchDetail,
      ),
      PairStatus.unconfirmed => (
        Icons.help_outline,
        status.info,
        l10n.reportsReconciliationStatusUnconfirmed,
        l10n.reportsReconciliationUnconfirmedDetail,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: RkSpace.s4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.reportsReconciliationPairBooks(pair.bookName, other),
                style: text.titleSmall,
              ),
              const SizedBox(height: RkSpace.s1),
              // The status, in words beside the icon (07 §1 rule 3).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: tint, size: RkSpace.s4),
                  const SizedBox(width: RkSpace.s1),
                  Expanded(
                    child: Text(
                      word,
                      style: text.bodyMedium?.copyWith(color: tint),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RkSpace.s1),
              Text(
                detail,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              if (pair.inTransit) ...[
                const SizedBox(height: RkSpace.s2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.schedule,
                      size: RkSpace.s4,
                      color: status.pending,
                    ),
                    const SizedBox(width: RkSpace.s1),
                    Expanded(
                      child: Text(
                        '${l10n.reportsReconciliationInTransit} — '
                        '${l10n.reportsReconciliationInTransitDetail}',
                        style: text.bodySmall?.copyWith(color: status.pending),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: RkSpace.s2),
              _FigureLine(
                label: l10n.reportsReconciliationSideLabel,
                paise: pair.sidePaise,
              ),
              if (!pair.isBalanced)
                _FigureLine(
                  label: l10n.reportsReconciliationDifferenceLabel,
                  paise: pair.netPaise,
                ),
            ],
          ),
        ),
        // 02 §6 🔒: a pair that does not net to zero is listed *with the
        // entries composing it*. A matched pair needs no list — that is what
        // "matched" means, and the A/C statement is one tap away for anyone
        // who wants the history.
        if (!pair.isBalanced) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              RkSpace.s1,
            ),
            child: Text(
              l10n.reportsReconciliationEntriesTitle,
              style: text.labelLarge?.copyWith(color: status.muted),
            ),
          ),
          for (final entry in pair.entries)
            ReconciliationEntryRow(
              entry: entry,
              onTap: onOpenEntry == null
                  ? null
                  : () => onOpenEntry!(entry.entryId),
            ),
        ],
      ],
    );
  }
}

/// A labelled figure: side by side while both fit on the line, and the amount
/// on a line of its own when they do not — an amount is never allowed to lose
/// room to its own label, and a label never to its amount (07 §1 rule 11).
///
/// The fold is **laid out**, never thresholded. A `Row` with the label in an
/// `Expanded` gives the amount its natural width first and hands the label
/// whatever is left — at 1.3x that was 14.4 px, and *Difference*, one
/// unbreakable word needing 184.5 px, was drawn straight across the card
/// without throwing. A scale threshold cannot fix that: it was set at
/// `> 1.3`, so the one scale that broke was the one it let through. A `Wrap`
/// asks each child what it needs and puts the amount on the next line when
/// the two will not share one, in every script and at every scale
/// (F1-07-104).
class _FigureLine extends StatelessWidget {
  const _FigureLine({required this.label, required this.paise});

  final String label;
  final int paise;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final amount = Semantics(
      label: label,
      child: MoneyText(paise, showDirection: true, style: style),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: RkSpace.s2,
        runSpacing: RkSpace.s1,
        children: [
          Text(label, style: style),
          amount,
        ],
      ),
    );
  }
}

/// One entry composing a pair: when it happened, which book it sits in, what
/// it moved, and its note. Tapping opens it (07 §1 rule 8).
class ReconciliationEntryRow extends StatelessWidget {
  /// Creates the row.
  const ReconciliationEntryRow({super.key, required this.entry, this.onTap});

  /// The entry, as the reconciliation read returned it.
  final ReconciliationEntry entry;

  /// Opens it; null leaves the row un-tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final when = formatLedgerDate(entry.date, strings: l10n);
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1;

    final head = Text(
      '$when · ${entry.bookName}',
      style: text.bodySmall?.copyWith(color: status.muted),
    );
    final amount = MoneyText(
      entry.amountPaise,
      showDirection: true,
      style: text.bodyMedium,
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (stacked) ...[
              head,
              const SizedBox(height: RkSpace.s1),
              amount,
            ] else
              Row(
                children: [
                  Expanded(child: head),
                  amount,
                ],
              ),
            if (entry.note != null && entry.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: RkSpace.s1),
                child: Text(
                  entry.note!,
                  style: text.bodySmall,
                  // The note is the user's own words in their own script; the
                  // row gives them one line and an ellipsis rather than a cut.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// No book has moved money to another yet — a friendly line and, where there
/// is somewhere to go, the one next action (07 §1 rule 12).
class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onMoveMoney});

  final VoidCallback? onMoveMoney;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        Text(
          l10n.reportsReconciliationEmpty,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (onMoveMoney != null) ...[
          const SizedBox(height: RkSpace.s4),
          FilledButton(
            onPressed: onMoveMoney,
            child: Text(l10n.reportsReconciliationEmptyNext),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: RkSpace.s3),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: RkSpace.s4),
            FilledButton(onPressed: onRetry, child: Text(l10n.ledgerListRetry)),
          ],
        ),
      ),
    );
  }
}

/// The ruled skeleton (11 §4.5): true row pitch, no shimmer, no spinner.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      child: ListView.builder(
        padding: const EdgeInsets.all(RkSpace.gutter),
        itemCount: 4,
        itemBuilder: (context, i) => Container(
          height: RkSpace.rowMinHeight,
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: i.isEven
                  ? RkMotion.skeletonLabelWidthMax
                  : RkMotion.skeletonLabelWidthMin,
              child: Container(
                height: RkSpace.s3,
                decoration: BoxDecoration(
                  color: status.skeletonLabel,
                  borderRadius: BorderRadius.circular(RkRadius.sm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
