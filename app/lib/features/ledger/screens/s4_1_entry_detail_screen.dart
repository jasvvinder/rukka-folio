// S4.1 Entry detail (13 §3.2 row S4.1, 07 §6 flow line `tap row → S4.1 entry
// detail → [Amend | Reverse]`). The target of every tap in every list, and a
// *detail viewer*, not a destination — 13 §211 exempts it from the depth rule
// because it opens from a row.
//
// This is a CONSUMER surface (02 §10 🔒, CLAUDE.md rule 9): every amount reads
// *Money in / Money out*. True Dr/Cr belongs to the A/C statement (S4), the
// trial balance and the exports — never here. The figures are the same signed
// integer paise either way; only the words change.
//
// Append-only, visibly (CLAUDE.md rule 2, 02 §5): this screen never edits.
// *Correct this* posts a new entry carrying `refs.amends`; *Reverse this*
// posts the auto-built mirror carrying `refs.reverses`. The version you are
// looking at is left exactly as it was posted, and the trail links both ways
// so a chain is never a dead end (07 §1 rule 2).
//
// Three states behind one id (ADR 2026-09-05b §4): posted · **held** (a
// dangling amend/reverse/decision — *"waiting for the entry this changes"*,
// neither projected nor counted, and deliberately not drawn as an error) ·
// missing. Plus the 13 §4.3 set: loading skeleton, error-with-retry, and
// disabled-with-reason on both actions.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../entry/entry_restriction.dart';
import '../entry_detail.dart';

/// S4.1 — one entry, its audit trail and its two corrections.
class EntryDetailScreen extends StatefulWidget {
  /// Creates the screen.
  const EntryDetailScreen({
    super.key,
    required this.entryId,
    this.onOpenEntry,
    this.onAmendFigures,
    this.onEnterAgain,
    this.memberName,
  });

  /// The entry to show.
  final String entryId;

  /// Opens another version of the chain (the trail's *Open* links). When null
  /// the trail still names what happened; only the link is dropped.
  final void Function(String entryId)? onOpenEntry;

  /// Hands amount/account changes to the entry flow (S2), which owns the
  /// keypad and the account pickers (07 §5). When null the amend sheet still
  /// offers the date and the note — the fields S4.1 owns.
  final void Function(String entryId)? onAmendFigures;

  /// Opens the entry flow (S2) on [EntryKind] for the corrected re-entry that
  /// 02 §5 🔒 pairs with the reversal of a locked-month entry (*Fix an old
  /// entry*). Called right after *Fix this entry* posts the reversal, and
  /// again from *Enter it again* on the reversed entry. When null the sheet
  /// posts the reversal only and says so.
  ///
  /// ⚠️ SPEC: 02 §5 has the app post both halves in one guided flow, and
  /// ADR 2026-09-03b makes that flow an S2.4 wizard whose door is this
  /// screen. S2.4 is not built and S2 takes no prefill, so the re-entry opens
  /// S2 on the entry's own verb with today's date and the user types the
  /// right figures. See the FIX200 lane report.
  final void Function(EntryKind kind)? onEnterAgain;

  /// Resolves a `created_by_user` to a name. Null, or a null answer, falls
  /// back to *you* / *another member* — never a raw uuid.
  final String? Function(String userId)? memberName;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  Future<EntryDetail>? _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // LedgerScope is an InheritedWidget: readable here, never in initState.
    _detail ??= loadEntryDetail(LedgerScope.of(context), widget.entryId);
  }

  void _reload() {
    // A block body, not an arrow: `setState` refuses a callback that returns a
    // Future, and an arrow here would return the assigned Future.
    final next = loadEntryDetail(LedgerScope.of(context), widget.entryId);
    setState(() {
      _detail = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ledgerEntryTitle)),
      body: FutureBuilder<EntryDetail>(
        future: _detail,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ErrorState(text: l10n.ledgerEntryError, onRetry: _reload);
          }
          final detail = snap.data;
          if (detail == null) {
            return _Skeleton(label: l10n.ledgerEntrySkeleton);
          }
          return switch (detail) {
            EntryDetailPosted() => _PostedBody(
              detail: detail,
              onOpenEntry: widget.onOpenEntry,
              onAmendFigures: widget.onAmendFigures,
              onEnterAgain: widget.onEnterAgain,
              memberName: widget.memberName,
              onChanged: _reload,
            ),
            EntryDetailHeld() => _HeldBody(detail: detail),
            EntryDetailMissing() => _MissingBody(onRetry: _reload),
          };
        },
      ),
    );
  }
}

// ── posted ───────────────────────────────────────────────────────────────────

class _PostedBody extends StatelessWidget {
  const _PostedBody({
    required this.detail,
    required this.onChanged,
    this.onOpenEntry,
    this.onAmendFigures,
    this.onEnterAgain,
    this.memberName,
  });

  final EntryDetailPosted detail;
  final VoidCallback onChanged;
  final void Function(String entryId)? onOpenEntry;
  final void Function(String entryId)? onAmendFigures;
  final void Function(EntryKind kind)? onEnterAgain;
  final String? Function(String userId)? memberName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = detail.view;
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        RkSpace.s8,
      ),
      children: [
        _Headline(detail: detail),
        // c2 *Locked period · Fix this entry*: the month's state, said once,
        // in words and an icon — never only by a greyed button (07 §1 rule 3).
        if (detail.inLockedPeriod) ...[
          const SizedBox(height: RkSpace.s4),
          _LockLine(detail: detail),
        ],
        const SizedBox(height: RkSpace.s5),
        _SectionHeading(l10n.ledgerEntrySides),
        for (final line in view.lines)
          _SideRow(
            name:
                detail.chart.maybeAccount(line.accountId)?.name ??
                line.accountId,
            paise: line.amount.raw,
          ),
        const SizedBox(height: RkSpace.s5),
        _SectionHeading(l10n.ledgerEntryDetails),
        _FactRow(
          label: l10n.ledgerEntryDate,
          value: formatLedgerDate(view.date, strings: l10n),
        ),
        _FactRow(
          label: l10n.ledgerEntryNote,
          value: view.note ?? l10n.ledgerEntryNoNote,
          muted: view.note == null,
        ),
        if (view.channel != null)
          _FactRow(label: l10n.ledgerEntryChannel, value: view.channel!),
        _FactRow(
          label: l10n.ledgerEntryPhoto,
          // ⚠️ SPEC: 13 §3.2 puts the bill photo on S4.1 and S20 opens from
          // here (07 §25, @M12), but `entries_p` does not project
          // `attachment_ids` and `EntryView` does not carry them, so this
          // build can only ever state the empty case honestly. The section
          // stays so the fact — no photo — is on the screen rather than
          // silently absent. See the lane report's `open` items.
          value: l10n.ledgerEntryNoPhoto,
          muted: true,
        ),
        _FactRow(
          label: l10n.ledgerEntryEnteredBy(_authorName(context, l10n)),
          value: '',
        ),
        const SizedBox(height: RkSpace.s5),
        _SectionHeading(l10n.ledgerEntryTrail),
        _Trail(detail: detail, onOpenEntry: onOpenEntry),
        const SizedBox(height: RkSpace.s5),
        _Actions(
          detail: detail,
          onAmendFigures: onAmendFigures,
          onChanged: onChanged,
        ),
      ],
    );
    final reenter = reentryFor(detail, onEnterAgain);
    if (detail.awaitsReentry && reenter != null) {
      // c2 *Reversed* (the locked-month entry after *Fix this entry*): the
      // reversal is half of 02 §5 🔒 *Fix an old entry*; the other half, the
      // corrected re-entry, stays pinned in the footer where the frame puts
      // its action — the screen after the fix is never a dead end.
      final month = monthName(l10n, view.date.month);
      return Column(
        children: [
          Expanded(child: list),
          _PinnedFooter(
            label: l10n.ledgerEntryLockedReentry,
            hint: l10n.ledgerEntryLockedReentryHint(
              formatLedgerDate(detail.reversedBy!.date, strings: l10n),
              month,
            ),
            onPressed: () => reenter(view.kind),
          ),
        ],
      );
    }
    if (!detail.lockedOnly) return list;
    // c2 *Locked period · Fix this entry*: the one path 02 §5 🔒 leaves is a
    // footer pinned in thumb reach (07 §1 rule 2), above a rule, whatever the
    // scroll — never below the fold under a greyed button.
    return Column(
      children: [
        Expanded(child: list),
        _PinnedFooter(
          label: l10n.ledgerEntryLockedFix,
          hint: l10n.ledgerEntryLockedFixHint(monthName(l10n, view.date.month)),
          onPressed: detail.canReverse
              ? () => openReverseSheet(
                  context,
                  detail,
                  onChanged,
                  onEnterAgain: onEnterAgain,
                )
              : null,
        ),
      ],
    );
  }

  String _authorName(BuildContext context, AppLocalizations l10n) {
    final userId = detail.view.createdByUser;
    final named = memberName?.call(userId);
    if (named != null && named.isNotEmpty) return named;
    final ledger = LedgerScope.of(context);
    return userId == ledger.identity.userId
        ? l10n.ledgerEntryEnteredByYou
        : l10n.ledgerEntryEnteredByOther;
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.detail});

  final EntryDetailPosted detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final paise = detail.headlinePaise;
    final verb = _verbLabel(l10n, detail.view.kind);
    final direction = directionLabel(l10n, Vocabulary.consumer, paise);
    // The struck-through version of a replaced or reversed entry is how 02 §5
    // asks history to read; the chip beside it carries the same fact in words
    // and an icon, so colour and a line are never the only signal (07 §1).
    final struck = detail.isReplaced || detail.isReversed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          verb,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: RkStatusColors.of(context).muted),
        ),
        const SizedBox(height: RkSpace.s2),
        Semantics(
          label: direction == null
              ? null
              : '${formatPaise(paise, locale: Localizations.localeOf(context), signed: false)} $direction',
          // Figure and word as two widgets, exactly as [_SideRow] does it:
          // [MoneyText] draws its run with `softWrap: false`, so
          // `−₹2,400 Money out` at the hero size is one 344.7 px word where a
          // 360 px phone has 328 px of line — cut, silently, at 1.3x. Split,
          // the hero figure keeps the size the reader asked for (07 §1 rule 4
          // — a tabular figure is never shrunk to fit) and the direction word
          // takes the next line when it has to. The announcement above is
          // unchanged, and still carries both.
          child: ExcludeSemantics(
            child: Wrap(
              spacing: RkSpace.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Scale-to-fit, the same answer Home's hero already gives
                // (`features/home/widgets/home_cards.dart`): at the hero size
                // `−₹2,400` is one unbreakable word needing 344.7 px of the
                // 328 px a 360 px phone leaves at 1.3x, and a plain Text drew
                // its last digits off the screen without throwing — which is
                // how a ledger comes to show a wrong number.
                //
                // ⚠️ SPEC: 07 §6 fixes the hero's type and says nothing about
                // a figure that outgrows the phone. Shrinking loses no digit
                // and creates no dead end (07 §1 rules 2 and 6), so it is the
                // conservative reading — but a 200 % reader does get less
                // than the full hero size on a long figure. A shorter format
                // (lakh / crore) or a smaller hero token would be the other
                // answers, and both are design calls: owner to rule. Same
                // open item as Home's.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: MoneyText(
                    paise,
                    style: RkType.amountHero.copyWith(
                      decoration: struck ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                // The word is a word, so it fits itself rather than being
                // scaled with the figure: *Money* at the hero size is 440 px
                // of unbreakable letters at 200 %, where the line is 328 px
                // (13 §4, 07 §1 rule 11). The figure beside it keeps the
                // reader's own size.
                if (direction != null)
                  RkFitText(
                    direction,
                    style: RkType.amountHero.copyWith(
                      decoration: struck ? TextDecoration.lineThrough : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RkSpace.s3),
        Wrap(
          spacing: RkSpace.s2,
          runSpacing: RkSpace.s2,
          children: [
            if (detail.isReplaced)
              _StatusChip(
                icon: Icons.history_edu_outlined,
                label: l10n.ledgerEntryStatusReplaced,
              ),
            if (detail.isReversed)
              _StatusChip(
                icon: Icons.undo,
                label: l10n.ledgerEntryStatusReversed,
              ),
            if (detail.isWaitingReview)
              _StatusChip(
                icon: Icons.hourglass_empty,
                label: l10n.ledgerEntryStatusReview,
              ),
          ],
        ),
      ],
    );
  }
}

String _verbLabel(AppLocalizations l10n, EntryKind kind) => switch (kind) {
  EntryKind.moneyIn => l10n.entryVerbMoneyIn,
  EntryKind.moneyOut => l10n.entryVerbMoneyOut,
  EntryKind.gaveCredit => l10n.entryVerbGaveCredit,
  EntryKind.tookCredit => l10n.entryVerbTookCredit,
  EntryKind.transfer => l10n.entryVerbMoveMoney,
  EntryKind.adjustment => l10n.ledgerEntryKindAdjustment,
};

class _SideRow extends StatelessWidget {
  const _SideRow({required this.name, required this.paise});

  final String name;
  final int paise;

  @override
  Widget build(BuildContext context) {
    final text = Text(name, style: Theme.of(context).textTheme.bodyMedium);
    // The figure and its word are two widgets, not one string, because
    // [MoneyText] never wraps: `−₹2,400 Money out` is one unbreakable run
    // 344.7 px wide at 1.3x, and a 360 px phone has 328 px of line, so drawn
    // as one string it is cut with nothing thrown. Split, the figure keeps
    // its tabular size (07 §1 — never shrunk) and the word moves to the next
    // line on its own. `MoneyText` labels itself for the screen reader and
    // excludes its children, so the word is announced after it.
    final direction = directionLabel(
      AppLocalizations.of(context),
      Vocabulary.consumer,
      paise,
    );
    final amount = Wrap(
      spacing: RkSpace.s1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MoneyText(paise, showPaise: true),
        if (direction != null)
          Text(direction, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s2),
      child: _Fold(start: text, end: amount),
    );
  }
}

/// A label/value pair on one line — label left, value right — that becomes
/// two stacked lines as soon as the two of them no longer fit (07 §1 rule 11).
///
/// The fold is decided by the **layout**, not by a text-scale threshold: a
/// `Wrap` puts the pair in one run while the run holds them and in two runs
/// when it does not, which is the same question asked of the real words in
/// the real font. The threshold this replaced (`scale(1) > 1.3`) was green at
/// 200 % and overflowed by 81 px at exactly 1.3, where the words are still
/// drawn and are widest — U3g's finding on S8.2, over again.
class _Fold extends StatelessWidget {
  const _Fold({required this.start, required this.end});

  final Widget start;
  final Widget end;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.start,
    spacing: RkSpace.s3,
    runSpacing: RkSpace.s1,
    children: [start, end],
  );
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s2),
      child: _Fold(
        start: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
        ),
        end: value.isEmpty
            ? const SizedBox.shrink()
            : Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted ? status.muted : null,
                ),
              ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: RkSpace.s1),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s3,
        vertical: RkSpace.s1,
      ),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.md),
        border: Border.all(color: status.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Colour is never alone (07 §1 rule 3): every chip carries its icon
          // and its word.
          Icon(icon, size: RkSpace.s4, color: status.muted),
          const SizedBox(width: RkSpace.s1),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

// ── audit trail ──────────────────────────────────────────────────────────────

class _Trail extends StatelessWidget {
  const _Trail({required this.detail, this.onOpenEntry});

  final EntryDetailPosted detail;
  final void Function(String entryId)? onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final items = <Widget>[
      _TrailRow(
        icon: Icons.check_circle_outline,
        text:
            '${l10n.ledgerEntryTrailSaved} · '
            '${formatLedgerDate(detail.view.date, strings: l10n)}',
      ),
      if (detail.corrects != null)
        _TrailRow(
          icon: Icons.edit_outlined,
          text: l10n.ledgerEntryTrailAmends,
          onOpen: onOpenEntry == null
              ? null
              : () => onOpenEntry!(detail.corrects!.id),
        ),
      if (detail.reverses != null)
        _TrailRow(
          icon: Icons.undo,
          text: l10n.ledgerEntryTrailReverses,
          onOpen: onOpenEntry == null
              ? null
              : () => onOpenEntry!(detail.reverses!.id),
        ),
      if (detail.correctedBy != null)
        _TrailRow(
          icon: Icons.history_edu_outlined,
          text: l10n.ledgerEntryTrailSuperseded,
          onOpen: onOpenEntry == null
              ? null
              : () => onOpenEntry!(detail.correctedBy!.id),
        ),
      if (detail.reversedBy != null)
        _TrailRow(
          icon: Icons.undo,
          text:
              '${l10n.ledgerEntryTrailReversed} · '
              '${formatLedgerDate(detail.reversedBy!.date, strings: l10n)}',
          onOpen: onOpenEntry == null
              ? null
              : () => onOpenEntry!(detail.reversedBy!.id),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...items,
        const SizedBox(height: RkSpace.s2),
        Text(
          l10n.ledgerEntryTrailAppendOnly,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: status.muted),
        ),
      ],
    );
  }
}

class _TrailRow extends StatelessWidget {
  const _TrailRow({required this.icon, required this.text, this.onOpen});

  final IconData icon;
  final String text;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s2),
      child: _Fold(
        // `min` + `Flexible`, not `Expanded`: inside [_Fold]'s `Wrap` a
        // full-width row would push the button onto its own line even when
        // both fit.
        start: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: RkSpace.s4, color: status.muted),
            const SizedBox(width: RkSpace.s2),
            Flexible(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
        end: onOpen == null
            ? const SizedBox.shrink()
            : TextButton(
                onPressed: onOpen,
                child: Text(l10n.ledgerEntryTrailOpen),
              ),
      ),
    );
  }
}

// ── actions ──────────────────────────────────────────────────────────────────

/// The muted lock line (c2 *Locked period · Fix this entry*): the month is
/// closed, and — when the projection knows it — the day its lock was signed.
class _LockLine extends StatelessWidget {
  const _LockLine({required this.detail});

  final EntryDetailPosted detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final month = monthName(l10n, detail.view.date.month);
    final on = detail.lockedOn;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: RkSpace.s5, color: status.locked),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: Text(
            on == null
                ? l10n.ledgerEntryLockedLineUndated(month)
                : l10n.ledgerEntryLockedLine(
                    month,
                    formatLedgerDate(on, strings: l10n),
                  ),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: status.muted),
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.detail,
    required this.onChanged,
    this.onAmendFigures,
  });

  final EntryDetailPosted detail;
  final VoidCallback onChanged;
  final void Function(String entryId)? onAmendFigures;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final month = monthName(l10n, detail.view.date.month);
    final reason = detail.lockedOnly
        ? l10n.ledgerEntryLockedAmendBlocked(month)
        : !detail.canAmend
        ? (detail.isReversed
              ? l10n.ledgerEntryReverseBlocked
              : l10n.ledgerEntryAmendBlocked)
        : null;
    final amend = FilledButton(
      onPressed: detail.canAmend
          ? () => openAmendSheet(context, detail, onAmendFigures, onChanged)
          : null,
      child: Text(l10n.ledgerEntryAmend),
    );
    // Disabled-with-reason (13 §4.3): a greyed button never stands alone.
    final why = reason == null
        ? null
        : Text(reason, style: text.bodySmall?.copyWith(color: status.muted));
    if (detail.lockedOnly) {
      // 02 §5 🔒 *Locked period*: amendment is forbidden by rule, so
      // *Correct this* stays, greyed, with its reason (13 §4.3); the path —
      // *Fix this entry* — is the pinned footer ([_PinnedFooter]).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          amend,
          const SizedBox(height: RkSpace.s2),
          why!,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: RkSpace.s3,
          runSpacing: RkSpace.s3,
          children: [
            amend,
            OutlinedButton(
              onPressed: detail.canReverse
                  ? () => openReverseSheet(context, detail, onChanged)
                  : null,
              child: Text(l10n.ledgerEntryReverse),
            ),
          ],
        ),
        if (why != null) ...[const SizedBox(height: RkSpace.s2), why],
      ],
    );
  }
}

/// The pinned footer of the locked-month states — c2 *Locked period · Fix
/// this entry* (*Fix this entry*, the reversal 02 §5 🔒 leaves open, whose
/// door on S4.1 is ADR 2026-09-03b's) and c2 *Reversed* (*Enter it again*,
/// the corrected re-entry that completes it): one full-width outlined action
/// over its promise, above a hairline.
class _PinnedFooter extends StatelessWidget {
  const _PinnedFooter({
    required this.label,
    required this.hint,
    required this.onPressed,
  });

  final String label;
  final String hint;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: status.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s3,
            RkSpace.gutter,
            RkSpace.s3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(onPressed: onPressed, child: Text(label)),
              const SizedBox(height: RkSpace.s2),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: status.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The re-entry door for [detail], or null when there is none to offer.
///
/// ⚠️ SPEC: an adjustment is guided-only (02 §2 verb 6) and has no position
/// on S2 (`entryVerbOf` maps it to *Money in*), so its re-entry belongs to the
/// S2.4 wizards, which are not built; no S2 door is offered for one rather
/// than one that would re-enter it as the wrong verb.
void Function(EntryKind kind)? reentryFor(
  EntryDetailPosted detail,
  void Function(EntryKind kind)? onEnterAgain,
) => detail.view.kind == EntryKind.adjustment ? null : onEnterAgain;

/// Opens the guided reversal sheet (02 §5): an auto-built mirror entry dated
/// today, with an optional reason. Nothing here is freeform — the user never
/// picks accounts or sides.
///
/// For an entry in a locked month this is *Fix this entry* (02 §5 🔒 *Fix an
/// old entry*: the reversal plus the corrected re-entry). When [onEnterAgain]
/// is given, posting the reversal goes straight on to the re-entry.
Future<void> openReverseSheet(
  BuildContext context,
  EntryDetailPosted detail,
  VoidCallback onChanged, {
  void Function(EntryKind kind)? onEnterAgain,
}) async {
  final ledger = LedgerScope.of(context);
  final reenter = detail.inLockedPeriod
      ? reentryFor(detail, onEnterAgain)
      : null;
  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ReverseSheet(
      detail: detail,
      ledger: ledger,
      reenters: reenter != null,
    ),
  );
  if (!(posted ?? false)) return;
  onChanged();
  // The footer that opened this sheet is gone once S4.1 reloads (the entry is
  // now reversed), so the callback — which carries the route's own context —
  // is called without asking whether this one is still mounted.
  reenter?.call(detail.view.kind);
}

class _ReverseSheet extends StatefulWidget {
  const _ReverseSheet({
    required this.detail,
    required this.ledger,
    required this.reenters,
  });

  final EntryDetailPosted detail;
  final LocalLedger ledger;

  /// Posting goes on to the corrected re-entry (02 §5 🔒 *Fix an old entry*).
  final bool reenters;

  @override
  State<_ReverseSheet> createState() => _ReverseSheetState();
}

class _ReverseSheetState extends State<_ReverseSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_busy) return;
    // S12.5 (ADR 2026-09-24b §13): a reversal is a new envelope, so read-only
    // blocks it with the same sheet; the typed reason stays under the sheet.
    // Both seams are read before the first await. (The 10-second Undo on S2
    // is the one exception and never comes through here.)
    final sources = entryRestrictionSourcesOf(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    final refused = await refuseIfEntryRestricted(context, sources, [
      widget.detail.view.bookId,
    ], onBlocked: () => setState(() => _busy = false));
    if (refused) return;
    try {
      await widget.ledger.reverse(
        widget.detail.view.id,
        date: widget.ledger.today(),
        note: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.ledgerEntryReverseError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // An entry in a locked month is reversed as *Fix this entry* (02 §5 🔒,
    // ADR 2026-09-03b): the same mirror dated today, said as what it is for.
    final locked = widget.detail.inLockedPeriod;
    final month = monthName(l10n, widget.detail.view.date.month);
    return _SheetFrame(
      title: locked ? l10n.ledgerEntryLockedFix : l10n.ledgerEntryReverseTitle,
      children: [
        Text(
          locked
              ? l10n.ledgerEntryLockedFixExplain(month)
              : l10n.ledgerEntryReverseExplain,
        ),
        const SizedBox(height: RkSpace.s4),
        TextField(
          controller: _reason,
          decoration: InputDecoration(labelText: l10n.ledgerEntryReverseReason),
        ),
        if (_error != null) ...[
          const SizedBox(height: RkSpace.s3),
          _InlineError(_error!),
        ],
        const SizedBox(height: RkSpace.s5),
        _SheetButtons(
          cancel: l10n.ledgerEntryReverseCancel,
          confirm: widget.reenters
              ? l10n.ledgerEntryLockedFixConfirm
              : l10n.ledgerEntryReverseConfirm,
          busy: _busy,
          onConfirm: _post,
        ),
      ],
    );
  }
}

/// Opens the guided correction sheet (02 §5 open-period amendment). Amount and
/// accounts are handed to the entry flow, which owns the keypad and the
/// pickers; the date and the note are corrected here. A locked period is not a
/// dead end: it offers *Fix an old entry*, the reversal path 02 §5 names.
Future<void> openAmendSheet(
  BuildContext context,
  EntryDetailPosted detail,
  void Function(String entryId)? onAmendFigures,
  VoidCallback onChanged,
) async {
  final ledger = LedgerScope.of(context);
  final outcome = await showModalBottomSheet<_AmendOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AmendSheet(
      detail: detail,
      ledger: ledger,
      onAmendFigures: onAmendFigures,
    ),
  );
  if (!context.mounted) return;
  switch (outcome) {
    case _AmendOutcome.posted:
      onChanged();
    case _AmendOutcome.reverseInstead:
      await openReverseSheet(context, detail, onChanged);
    case _AmendOutcome.figures:
      onAmendFigures?.call(detail.view.id);
    case null:
      break;
  }
}

enum _AmendOutcome { posted, reverseInstead, figures }

class _AmendSheet extends StatefulWidget {
  const _AmendSheet({
    required this.detail,
    required this.ledger,
    this.onAmendFigures,
  });

  final EntryDetailPosted detail;
  final LocalLedger ledger;
  final void Function(String entryId)? onAmendFigures;

  @override
  State<_AmendSheet> createState() => _AmendSheetState();
}

class _AmendSheetState extends State<_AmendSheet> {
  late final TextEditingController _note = TextEditingController(
    text: widget.detail.view.note ?? '',
  );
  late LocalDate _date = widget.detail.view.date;
  bool _busy = false;
  String? _error;
  bool _locked = false;
  bool _dateLocked = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    // 07 §5 step 4 🔒: any date in an open month; future dates disabled;
    // closed months greyed. The engine refuses all three (`checkAuthoringRules`
    // no-future-date, `periodLocked`, `beforeBookStart`), so the calendar
    // offers exactly what it will accept. The entry's own date is always in
    // range — it was accepted when posted.
    final detail = widget.detail;
    final today = widget.ledger.today();
    final start = detail.bookStart;
    DateTime day(LocalDate d) => DateTime(d.year, d.month, d.day);
    final first = start == null || _date.compareTo(start) < 0 ? _date : start;
    final last = _date.compareTo(today) > 0 ? _date : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: day(_date),
      firstDate: start == null ? DateTime(_date.year - 5) : day(first),
      lastDate: day(last),
      selectableDayPredicate: (d) =>
          d == day(_date) ||
          !detail.lockedMonths.contains(YearMonth(d.year, d.month)),
    );
    if (picked != null) {
      setState(() => _date = LocalDate(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    // S12.5 (ADR 2026-09-24b §13): an amendment is a new envelope, so
    // read-only blocks it with the same sheet; the edited note and date stay
    // under the sheet. Both seams are read before the first await.
    final sources = entryRestrictionSourcesOf(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    final note = _note.text.trim();
    final refused = await refuseIfEntryRestricted(context, sources, [
      widget.detail.view.bookId,
    ], onBlocked: () => setState(() => _busy = false));
    if (refused) return;
    try {
      await widget.ledger.amend(
        widget.detail.view.id,
        accountingDate: _date,
        note: note.isEmpty ? null : note,
      );
      if (mounted) Navigator.of(context).pop(_AmendOutcome.posted);
    } on PostRejected catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _locked = e.has(ViolationKind.amendInLockedPeriod);
        // The entry's month is open but the new date's month is closed —
        // closed after the sheet opened, since the calendar greys the ones
        // it knew. Named cause + path (13 §8 Errors): pick another date.
        _dateLocked = !_locked && e.has(ViolationKind.periodLocked);
        _error = _locked
            ? l10n.ledgerEntryAmendLocked
            : _dateLocked
            ? l10n.ledgerEntryAmendDateLocked(monthName(l10n, _date.month))
            : l10n.ledgerEntryAmendError;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.ledgerEntryAmendError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SheetFrame(
      title: l10n.ledgerEntryAmendTitle,
      children: [
        Text(l10n.ledgerEntryAmendExplain),
        const SizedBox(height: RkSpace.s4),
        if (widget.onAmendFigures != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: RkSpace.rowMinHeight,
            leading: const Icon(Icons.calculate_outlined),
            title: Text(l10n.ledgerEntryAmendFigures),
            subtitle: Text(l10n.ledgerEntryAmendFiguresHint),
            onTap: () => Navigator.of(context).pop(_AmendOutcome.figures),
          ),
        _SectionHeading(l10n.ledgerEntryAmendDateNote),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: RkSpace.rowMinHeight,
          leading: const Icon(Icons.event_outlined),
          title: Text(l10n.ledgerEntryDate),
          subtitle: Text(formatLedgerDate(_date, strings: l10n)),
          onTap: _pickDate,
        ),
        Text(
          l10n.ledgerEntryAmendDateRule,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: RkStatusColors.of(context).muted),
        ),
        const SizedBox(height: RkSpace.s3),
        TextField(
          controller: _note,
          decoration: InputDecoration(labelText: l10n.ledgerEntryNote),
        ),
        if (_error != null) ...[
          const SizedBox(height: RkSpace.s3),
          _InlineError(_error!),
          if (_locked) ...[
            const SizedBox(height: RkSpace.s2),
            // 07 §1 rule 6: explain, then offer the path 02 §5 allows.
            FilledButton.tonal(
              onPressed: () =>
                  Navigator.of(context).pop(_AmendOutcome.reverseInstead),
              child: Text(l10n.ledgerEntryAmendLockedAction),
            ),
          ],
        ],
        const SizedBox(height: RkSpace.s5),
        _SheetButtons(
          cancel: l10n.ledgerEntryAmendCancel,
          confirm: l10n.ledgerEntryAmendSave,
          busy: _busy,
          onConfirm: _save,
        ),
      ],
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: RkSpace.gutter,
      right: RkSpace.gutter,
      top: RkSpace.s5,
      bottom: RkSpace.s5 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: RkSpace.s4),
          ...children,
        ],
      ),
    ),
  );
}

class _SheetButtons extends StatelessWidget {
  const _SheetButtons({
    required this.cancel,
    required this.confirm,
    required this.busy,
    required this.onConfirm,
  });

  final String cancel;
  final String confirm;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: RkSpace.s3,
    runSpacing: RkSpace.s3,
    alignment: WrapAlignment.end,
    children: [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: Text(cancel),
      ),
      FilledButton(onPressed: busy ? null : onConfirm, child: Text(confirm)),
    ],
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.error_outline,
        size: RkSpace.s4,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(width: RkSpace.s2),
      Expanded(child: Text(text)),
    ],
  );
}

// ── held / missing / loading / error ─────────────────────────────────────────

/// The held state (ADR 2026-09-05b §4): a correction that arrived before the
/// entry it corrects. It is *waiting*, not broken — the icon is an hourglass,
/// the ink is muted, and nothing on this screen says error.
class _HeldBody extends StatelessWidget {
  const _HeldBody({required this.detail});

  final EntryDetailHeld detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        _StatusChip(
          icon: Icons.hourglass_empty,
          label: l10n.ledgerEntryHeldBadge,
        ),
        const SizedBox(height: RkSpace.s4),
        Text(
          l10n.ledgerEntryHeld,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: RkSpace.s3),
        Text(l10n.ledgerEntryHeldHint),
        if (detail.waitingForId != null) ...[
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.ledgerEntryHeldWaitingFor(detail.waitingForId!),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: status.muted),
          ),
        ],
      ],
    );
  }
}

class _MissingBody extends StatelessWidget {
  const _MissingBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        Text(
          l10n.ledgerEntryMissing,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: RkSpace.s3),
        Text(l10n.ledgerEntryMissingHint),
        const SizedBox(height: RkSpace.s4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: onRetry,
            child: Text(l10n.ledgerListRetry),
          ),
        ),
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
        itemCount: 5,
        itemBuilder: (context, i) => Container(
          height: RkSpace.rowMinHeight,
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
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
