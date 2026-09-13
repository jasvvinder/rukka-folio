// S6.1 — the grouped review card (07 §9 🔒, 13 §4.1 P3): one card per author +
// book + day, never one per item. Avatar · who + where + count + total ·
// expandable list with photo thumbnails and a per-row quick reject · two
// actions: **Approve all** and **One by one**.
//
// The entries on this card are **already in the book** (02 §3 🔒). The card
// says so in words; nothing here draws the money as pending or held, because
// post-then-review defines no such state. The amber chip is the *review flag*,
// carried with its icon and its word so colour is never alone (07 §1 rule 3).
//
// Vocabulary: consumer — *Money in / Money out*, never Dr/Cr (02 §10 🔒).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../review_queue.dart';

/// The S6.1 card.
class ReviewCard extends StatefulWidget {
  /// Creates the card.
  const ReviewCard({
    super.key,
    required this.group,
    required this.now,
    required this.onApproveAll,
    required this.onReject,
    this.onOneByOne,
    this.busy = false,
    this.error = false,
    this.approvedCount,
  });

  /// The flagged entries of one author, book and day.
  final ReviewGroup group;

  /// Injected clock (CLAUDE.md rule 3) — relative date labels only.
  final DateTime now;

  /// *Approve all* (07 §9 🔒): clears every flag on the card in one tap.
  final VoidCallback onApproveAll;

  /// Per-row quick reject; the reason sheet is the caller's to show.
  final void Function(ReviewEntry entry) onReject;

  /// *One by one* → S6.2. Null while the stepper route is not mounted.
  final VoidCallback? onOneByOne;

  /// A write is in flight (13 §4.3 loading).
  final bool busy;

  /// The last write failed; the flags are unchanged (13 §4.3 error).
  final bool error;

  /// Shown after *Approve all* landed, before the card leaves the list.
  final int? approvedCount;

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final g = widget.group;
    final locale = Localizations.localeOf(context);
    final day = formatListDate(g.day, strings: l10n, now: widget.now);
    final total = formatPaise(g.totalPaise, locale: locale);

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(RkRadius.lg),
          border: Border(
            left: BorderSide(
              color: status.pending,
              width: RkRadius.ruleLeftWidth,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, g, day: day, total: total),
            const SizedBox(height: RkSpace.s2),
            _meta(context, g, total),
            const SizedBox(height: RkSpace.s2),
            _flagChip(context),
            const SizedBox(height: RkSpace.s2),
            // 02 §3 🔒: the money already moved. Say it plainly.
            Text(
              l10n.inboxCardPosted(g.authorName),
              style: text.bodyMedium?.copyWith(color: status.muted),
            ),
            if (widget.error) ...[
              const SizedBox(height: RkSpace.s2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: scheme.error, size: 20),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: Text(
                      l10n.inboxCardError,
                      style: text.bodyMedium?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.approvedCount != null) ...[
              const SizedBox(height: RkSpace.s2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: status.success,
                    size: 20,
                  ),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: Text(
                      l10n.inboxCardApproved(widget.approvedCount!),
                      style: text.bodyMedium?.copyWith(color: status.success),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: RkSpace.s3),
            // A Wrap, not a TextButton.icon: at 200 % the longest Devanagari
            // word here needs the card's whole width, so the chevron has to be
            // able to fall to its own run instead of stealing 32 px (13 §8).
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
                child: Wrap(
                  spacing: RkSpace.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _expanded ? l10n.inboxCardCollapse : l10n.inboxCardExpand,
                      style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: scheme.onSurface,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              for (final e in g.entries)
                _EntryRow(
                  entry: e,
                  now: widget.now,
                  onReject: widget.busy ? null : () => widget.onReject(e),
                ),
            const SizedBox(height: RkSpace.s3),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    ReviewGroup g, {
    required String day,
    required String total,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          child: Text(
            _initials(g.authorName),
            style: text.bodyMedium?.copyWith(color: scheme.onPrimary),
          ),
        ),
        const SizedBox(width: RkSpace.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(g.authorName, style: text.titleLarge),
              Text(
                l10n.inboxCardSubtitle(g.bookName, day),
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Count and total, at the card's FULL width rather than indented beside the
  /// avatar: at 200 % the Devanagari word for *entries* needs nearly the whole
  /// 360 px card, and the avatar's indent was cutting it (07 §1 rule 9, 13 §8).
  Widget _meta(BuildContext context, ReviewGroup g, String total) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: RkSpace.s3,
      runSpacing: RkSpace.s1,
      children: [
        Text(l10n.inboxCardCount(g.count), style: text.bodyLarge),
        // A card mixes money in and money out, so the total is unsigned and
        // uncoloured (07 §1 rule 3).
        Text(
          l10n.inboxCardTotal(total),
          style: text.bodyLarge?.copyWith(fontFeatures: RkType.tabular),
        ),
      ],
    );
  }

  Widget _flagChip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Row(
      children: [
        Icon(Icons.flag_outlined, size: 20, color: status.pending),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: Text(
            l10n.inboxCardFlag,
            style: text.bodyMedium?.copyWith(color: status.pending),
          ),
        ),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.busy) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: RkSpace.s2),
          Expanded(child: Text(l10n.inboxCardWorking)),
        ],
      );
    }
    return Wrap(
      spacing: RkSpace.s3,
      runSpacing: RkSpace.s2,
      children: [
        FilledButton(
          onPressed: widget.onApproveAll,
          child: Text(l10n.inboxCardApproveAll),
        ),
        OutlinedButton(
          onPressed: widget.onOneByOne,
          child: Text(l10n.inboxCardOneByOne),
        ),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p.characters.first).join();
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.now, this.onReject});

  final ReviewEntry entry;
  final DateTime now;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final note = entry.note;
    return Padding(
      padding: const EdgeInsets.only(top: RkSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: status.hairline),
          const SizedBox(height: RkSpace.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: entry.hasPhoto
                    ? l10n.inboxRowPhoto
                    : l10n.inboxRowPhotoNone,
                child: Icon(
                  entry.hasPhoto
                      ? Icons.photo_outlined
                      : Icons.image_not_supported_outlined,
                  size: 20,
                  color: status.muted,
                ),
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: Text(
                  l10n.inboxRowRoute(entry.fromLabel, entry.toLabel),
                  style: text.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onReject != null)
                IconButton(
                  onPressed: onReject,
                  tooltip: l10n.inboxRowReject,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          Wrap(
            spacing: RkSpace.s3,
            runSpacing: RkSpace.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MoneyText(entry.paise, showDirection: true),
              Text(
                formatListDate(entry.date, strings: l10n, now: now),
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
            ],
          ),
          Text(
            note == null || note.trim().isEmpty ? l10n.inboxRowNoteNone : note,
            style: text.bodyMedium?.copyWith(color: status.muted),
          ),
        ],
      ),
    );
  }
}
