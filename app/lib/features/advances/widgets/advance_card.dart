// S5 *Advance with you* card (07 §8): purpose, taken date, spent-vs-remaining
// bar, `Add spend` and `Return remaining`. One card per open advance, one per
// book — the holder's own view of 02 §7's *money you are holding*, derived
// from the `advance` balance and nothing else.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// One open advance the signed-in user is holding.
class AdvanceCard extends StatelessWidget {
  /// Creates the card.
  const AdvanceCard({
    super.key,
    required this.advance,
    this.onAddSpend,
    this.onReturn,
  });

  /// The advance, as the ledger derives it.
  final AdvanceView advance;

  /// Opens the spend sheet (`Dr expense-category · Cr Advance`, 02 §7).
  final VoidCallback? onAddSpend;

  /// Opens the return sheet (`Dr money · Cr Advance`, 02 §7).
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    // At 200 % on a 360 pt phone `Return remaining` needs more width than the
    // gutter + card padding leave it, and a button label is not something to
    // truncate (07 §1 rule 9: 200 % without breakage). So the card gives its
    // padding back to the text at large scale rather than cutting the word.
    final tight = MediaQuery.textScalerOf(context).scale(100) > 150;
    final spent = formatPaise(advance.spentPaise, locale: locale);
    final left = formatPaise(advance.remainingPaise, locale: locale);
    final given = formatPaise(advance.givenPaise, locale: locale);

    return Card(
      margin: EdgeInsets.fromLTRB(
        tight ? RkSpace.s2 : RkSpace.gutter,
        0,
        tight ? RkSpace.s2 : RkSpace.gutter,
        RkSpace.s3,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RkRadius.lg),
        side: BorderSide(color: status.hairline),
      ),
      child: Padding(
        padding: EdgeInsets.all(tight ? RkSpace.s2 : RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              advance.purpose ?? l10n.advancesCardPurposeNone,
              style: text.titleMedium,
            ),
            const SizedBox(height: RkSpace.s1),
            Text(
              l10n.advancesCardTaken(
                formatLedgerDate(advance.takenDate, strings: l10n),
              ),
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s3),
            _SpentBar(
              spentPaise: advance.spentPaise,
              givenPaise: advance.givenPaise,
              label: l10n.advancesCardProgress(spent, given),
            ),
            const SizedBox(height: RkSpace.s2),
            // The words carry the split; the bar only repeats it, so colour is
            // never the only signal (07 §1 rule 3).
            Text(l10n.advancesCardSplit(spent, left), style: text.bodyMedium),
            const SizedBox(height: RkSpace.s3),
            // Wrap, not Row: at 200 % text scale on a 360 pt phone the two
            // labels do not fit side by side and must stack.
            Wrap(
              spacing: RkSpace.s2,
              runSpacing: RkSpace.s2,
              children: [
                FilledButton.tonal(
                  onPressed: onAddSpend,
                  style: tight ? _tightButton : null,
                  child: Text(l10n.advancesActionSpend),
                ),
                OutlinedButton(
                  onPressed: onReturn,
                  style: tight ? _tightButton : null,
                  child: Text(l10n.advancesActionReturn),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Button padding at large text scale: the label keeps the room, not the
/// chrome. Minimum tap target is unaffected — the taller text sets it.
final ButtonStyle _tightButton = ButtonStyle(
  padding: WidgetStateProperty.all(
    const EdgeInsets.symmetric(horizontal: RkSpace.s2, vertical: RkSpace.s2),
  ),
);

/// The spent-vs-remaining rule. Decorative: the figures beside it say the same
/// thing in words, and the whole bar carries one accessible [label].
class _SpentBar extends StatelessWidget {
  const _SpentBar({
    required this.spentPaise,
    required this.givenPaise,
    required this.label,
  });

  final int spentPaise;
  final int givenPaise;
  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    // Integer ratio, clamped: an advance can be over-spent only if the ledger
    // let the balance go credit, which 02 §7 does not contemplate.
    final fraction = givenPaise <= 0
        ? 0.0
        : (spentPaise / givenPaise).clamp(0.0, 1.0);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RkRadius.sm),
        child: SizedBox(
          height: RkSpace.s2,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: status.sunk)),
              FractionallySizedBox(
                widthFactor: fraction,
                child: ColoredBox(color: status.locked),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
