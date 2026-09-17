// S14.2 — the drift & settlement card (07 §27 🔒, 02 §7.1 🔒 *Drift
// visibility*, 13 §3.2 row S14.2).
//
// Quiet by construction: it states a fact and says out loud that nothing has
// to be done about it. It is `info`-toned, never `warning` — a partner who has
// more with the business than the others has done nothing wrong, and 07 §1
// rule 3 keeps the status family off amounts anyway, so the tone lives in the
// icon and the rule, with the words carrying the meaning on their own.
//
// The three doors of 07 §27 each lead somewhere real or say why not
// (07 §1 rule 6, 13 §4.3 disabled-with-reason):
//
//   pay out            → the in-feature sheet (02 §7.1 route 1) — disabled
//                        when the business has no money to pay from
//   partner-to-partner → the in-feature sheet (route 2) — disabled when
//                        there is no second owner to settle with
//   carry forward      → always disabled-with-reason: it is the *default* and
//                        the year-close ceremony (§8.1) performs it; there is
//                        nothing to do here and never was
//
// Read-only (13 §5, S12.5) closes the two posting doors with its own reason
// and leaves every figure visible.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../partners_port.dart';
import '../../../shared/widgets/rk_ruled_card.dart';

/// The quiet card for one over-funded owner.
class DriftSettlementCard extends StatelessWidget {
  /// Creates the card.
  const DriftSettlementCard({
    super.key,
    required this.drift,
    required this.view,
    required this.onPayOut,
    required this.onPartnerToPartner,
  });

  /// Who is above the group average, and by how much.
  final PartnerDriftView drift;

  /// The book's position, for what the doors can and cannot do.
  final PartnersView view;

  /// Opens the pay-out sheet.
  final VoidCallback onPayOut;

  /// Opens the partner-to-partner sheet.
  final VoidCallback onPartnerToPartner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);

    final hasCash = view.sources.any((s) => s.balance.raw > 0);
    final hasOtherPartner = view.positions.length > 1;
    final readOnly = view.readOnly;

    return RkRuledCard(
      ruleColor: status.info,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colour never alone (07 §1 rule 3): the icon is the signal
                // that survives grayscale, the words carry the meaning.
                Icon(Icons.info_outline, size: RkIcon.grid, color: status.info),
                const SizedBox(width: RkSpace.s3),
                Expanded(
                  child: Text(
                    l10n.partnersDriftTitle(
                      drift.name,
                      formatPaise(drift.aboveAverage.raw, locale: locale),
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              l10n.partnersDriftBody,
              style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s5),
            Text(
              l10n.partnersDriftDoors,
              style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s2),
            _Door(
              label: l10n.partnersDriftDoorPayout,
              reason: readOnly
                  ? l10n.partnersDoorsReadonly
                  : hasCash
                  ? null
                  : l10n.partnersDriftDoorPayoutDisabled,
              onPressed: onPayOut,
            ),
            _Door(
              label: l10n.partnersDriftDoorP2p,
              reason: readOnly
                  ? l10n.partnersDoorsReadonly
                  : hasOtherPartner
                  ? null
                  : l10n.partnersDriftDoorP2pDisabled,
              onPressed: onPartnerToPartner,
            ),
            _Door(
              label: l10n.partnersDriftDoorCarry,
              reason: l10n.partnersDriftDoorCarryDisabled,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

/// One door: a button, or — when [reason] is non-null — the same button
/// disabled with the reason printed beneath it and folded into its semantics,
/// so a screen reader hears why before it hears the label (13 §4.3,
/// 07 §1 rule 6).
class _Door extends StatelessWidget {
  const _Door({
    required this.label,
    required this.reason,
    required this.onPressed,
  });

  final String label;
  final String? reason;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final reason = this.reason;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: RkSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            enabled: reason == null,
            hint: reason,
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: reason == null ? onPressed : null,
                child: Text(label, textAlign: TextAlign.center),
              ),
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: RkSpace.s1),
            Text(
              reason,
              style: theme.textTheme.bodySmall?.copyWith(
                color: RkStatusColors.of(context).muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
