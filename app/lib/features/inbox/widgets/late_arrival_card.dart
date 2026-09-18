// One Late Arrivals card — S10.3 (13 §3.2, parent S6), 07 §13 🔒: *each item:
// entry + why it's here; actions `Re-date to today` (default) / `Re-open
// August` (admin, scary-styled, logged)*.
//
// Two rules the card is built around:
//
//  · **It is already in the book** (02 §3 🔒, 02 §8 🔒). The card says so in
//    words. Nothing here draws the money as pending, held or waiting.
//  · **Colour is never alone** (07 §1 rule 3): the direction is an icon, the
//    words *Money in / Money out* (02 §10 🔒 — a consumer surface, never
//    Dr/Cr) and a token colour, in that order of reliance.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../late_arrivals.dart';

/// `September 2026` — the month as the actions and sentences name it.
String lateArrivalMonthLabel(AppLocalizations l10n, int year, int month) =>
    '${monthName(l10n, month)} $year';

/// The card for one tray item.
class LateArrivalCard extends StatelessWidget {
  /// Creates the card.
  const LateArrivalCard({
    super.key,
    required this.item,
    required this.onRedate,
    this.onReopen,
    this.busy = false,
    this.error = false,
    this.refusal,
    this.moved = false,
  });

  /// The tray item.
  final LateArrivalItem item;

  /// *Re-date to today* — the one-tap default (02 §8 🔒).
  final VoidCallback onRedate;

  /// *Re-open {month}* — admin, logged. Null hides the action entirely
  /// (a viewer, or a book this reader does not close).
  final VoidCallback? onReopen;

  /// A write is in flight for this card.
  final bool busy;

  /// The last write on this card failed. The ledger is append-only, so a
  /// failure changed nothing.
  final bool error;

  /// The book's own refusal of a re-open, stated as one plain sentence.
  final ReopenRefusal? refusal;

  /// The entry has just been re-dated (the confirmation line, 07 §5).
  final bool moved;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final month = lateArrivalMonthLabel(
      l10n,
      item.lockedPeriod.year,
      item.lockedPeriod.month,
    );
    final amount = formatPaise(item.magnitudePaise, locale: locale);
    final moneyIn = item.paise >= 0;
    final amountLine = moneyIn
        ? l10n.inboxLateCardIn(amount)
        : l10n.inboxLateCardOut(amount);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Direction: icon + words + token colour, never colour alone.
            Semantics(
              label: amountLine,
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      moneyIn ? Icons.south_west : Icons.north_east,
                      size: 20,
                      color: moneyIn ? status.credit : status.debit,
                    ),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(
                      child: Text(
                        amountLine,
                        style: text.titleLarge?.copyWith(
                          color: moneyIn ? status.credit : status.debit,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              l10n.inboxLateCardRoute(item.fromLabel, item.toLabel),
              style: text.bodyLarge,
            ),
            if (item.note case final note? when note.isNotEmpty) ...[
              const SizedBox(height: RkSpace.s1),
              Text(note, style: text.bodyMedium?.copyWith(color: status.muted)),
            ],
            const SizedBox(height: RkSpace.s3),
            // Why it is here (07 §13 🔒).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_clock, size: 20, color: status.locked),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: Text(
                    item.lockedOn == null
                        ? l10n.inboxLateCardWhyNodate(
                            formatLedgerDate(item.date, strings: l10n),
                            item.bookName,
                            month,
                          )
                        : l10n.inboxLateCardWhy(
                            formatLedgerDate(item.date, strings: l10n),
                            item.bookName,
                            month,
                            formatLedgerDate(item.lockedOn!, strings: l10n),
                          ),
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s2),
            // 02 §3 🔒 / 02 §8 🔒 — it already counts. Said, never implied.
            Text(
              l10n.inboxLateCardCounted(month),
              style: text.bodyMedium?.copyWith(color: status.muted),
            ),
            if (moved) ...[
              const SizedBox(height: RkSpace.s3),
              _Line(
                icon: Icons.check_circle_outline,
                color: status.credit,
                text: l10n.inboxLateCardMoved,
              ),
            ],
            if (error) ...[
              const SizedBox(height: RkSpace.s3),
              _Line(
                icon: Icons.error_outline,
                color: scheme.error,
                text: l10n.inboxLateCardError,
              ),
            ],
            if (refusal != null) ...[
              const SizedBox(height: RkSpace.s3),
              _Line(
                icon: Icons.info_outline,
                color: status.muted,
                text: refusal == ReopenRefusal.notLocked
                    ? l10n.inboxLateCardNotlocked(month)
                    : l10n.inboxLateCardClosedYear(
                        item.closedYear ?? month,
                        month,
                      ),
              ),
            ],
            const SizedBox(height: RkSpace.s4),
            if (busy)
              Text(l10n.inboxLateCardWorking, style: text.bodyLarge)
            else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onRedate,
                  child: Text(l10n.inboxLateCardRedate),
                ),
              ),
              // A closed FY cannot be re-opened from here (02 §8.1 🔒): the
              // card states why and keeps the one-tap default, rather than
              // offering a tap that can only be refused (07 §1 rule 6).
              if (item.reopenBlocked)
                Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s3),
                  child: _Line(
                    icon: Icons.verified_outlined,
                    color: status.muted,
                    text: l10n.inboxLateCardClosedYear(item.closedYear!, month),
                  ),
                )
              else if (onReopen != null)
                Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s2),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: status.danger,
                        side: BorderSide(color: status.danger),
                      ),
                      onPressed: onReopen,
                      child: Text(l10n.inboxLateCardReopen(month)),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: RkSpace.s2),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
