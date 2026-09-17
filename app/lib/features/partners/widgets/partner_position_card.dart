// S14's per-owner card (13 §3.2 row S14; 02 §7.1 🔒): put in · took out ·
// share · net, plus the agreed share as whole-number weights.
//
// This is a **consumer surface**, so the words are *Put in / Took out* and
// never Dr/Cr (02 §10 🔒, CLAUDE.md rule 9). The engine's posting is unchanged
// underneath: a credit balance on the Partner Current A/c is *the business
// owes them*, a debit balance is *they owe the business*, and 02 §7.1 🔒
// insists the debit case is displayed as plainly as the credit one.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../partners_port.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import 'partners_card.dart';

/// One owner's position.
class PartnerPositionCard extends StatelessWidget {
  /// Creates the card.
  const PartnerPositionCard({
    super.key,
    required this.position,
    required this.ratioTotal,
  });

  /// The owner's figures.
  final PartnerPosition position;

  /// Σ of the recorded weights, for *{weight} of {total}*; zero when the map
  /// records nothing (02 §7.1 🔒 — an absent map is *not recorded*).
  final int ratioTotal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final muted = RkStatusColors.of(context).muted;
    final weight = position.ratioWeight;

    String money(int paise) => formatPaise(paise, locale: locale);

    final net = position.net.raw;
    final netLabel = net > 0
        ? l10n.partnersPositionNetOwed(position.name)
        : net < 0
        ? l10n.partnersPositionNetOwes(position.name)
        : l10n.partnersPositionNetSettled;

    return RkRuledCard(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The owner's own name is user-typed content, so it carries its
            // own language marker for the screen reader (01 §1.9 🔒).
            Semantics(
              header: true,
              child: Text(position.name, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: RkSpace.s1),
            Text(
              weight == null || ratioTotal <= 0
                  ? '${l10n.partnersRatioLabel} · '
                        '${l10n.partnersRatioUnrecorded}'
                  : '${l10n.partnersRatioLabel} · '
                        '${l10n.partnersRatioWeight(weight, ratioTotal)}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            if (weight == null || ratioTotal <= 0) ...[
              const SizedBox(height: RkSpace.s1),
              Text(
                l10n.partnersRatioUnrecordedHelp,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: RkSpace.s4),
            // Wrap, not Row: at 200 % on a 360 px phone the three blocks
            // stack instead of fighting for width (07 §1 rule 11).
            Wrap(
              spacing: RkSpace.s6,
              runSpacing: RkSpace.s4,
              children: [
                PartnersFigure(
                  label: l10n.partnersPositionPutin,
                  value: money(position.putIn.raw),
                ),
                PartnersFigure(
                  label: l10n.partnersPositionTookout,
                  value: money(position.tookOut.raw),
                ),
                PartnersFigure(
                  label: l10n.partnersPositionShare,
                  value: money(position.share.raw),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s4),
            Divider(color: RkStatusColors.of(context).hairline, height: 1),
            const SizedBox(height: RkSpace.s4),
            PartnersFigure(
              label: netLabel,
              value: money(net.abs()),
              emphasis: true,
            ),
          ],
        ),
      ),
    );
  }
}
