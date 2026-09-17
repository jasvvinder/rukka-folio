// S5 *Advance out* row (07 §8): the book's view of 02 §7's *money out with
// people*, aged. One row per open `advance` account, oldest unsettled first.
//
// The approver's two actions ride under the row. Neither can act yet — the
// *Advance reminder* notification of 07 §17 has no source on the device, and
// a write-off is the approver-only guided adjustment of 02 §7 (S2.4). So both
// render in 13 §4.3's **disabled-with-reason** state, which says why, rather
// than as a tap that does nothing (07 §1 rule 6: no dead ends).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// 02 §7: reminders default to 15 days to the holder, then 30 to the approver.
/// Past the approver's mark the row reads as a problem, not a wait — and it
/// says so in a word and an icon, never in the tint alone (07 §1 rule 3).
const int advanceOverdueDays = 30;

/// One open advance the book has out with somebody.
class AdvanceAgedRow extends StatelessWidget {
  /// Creates the row.
  const AdvanceAgedRow({
    super.key,
    required this.advance,
    this.canApprove = false,
  });

  /// The advance, as the ledger derives it.
  final AdvanceView advance;

  /// Whether this member may approve advances in this book (13 §7: owner and
  /// admin). Drives only whether the two approver actions are drawn at all.
  final bool canApprove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final overdue = advance.ageDays >= advanceOverdueDays;
    final tint = overdue ? status.warning : status.pending;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: status.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // At 200 % the name and the figure cannot share a line on a 360 pt
          // phone, so they wrap instead of squeezing the amount (U3g).
          Wrap(
            spacing: RkSpace.s3,
            runSpacing: RkSpace.s1,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: RkSpace.s12),
                child: Text(
                  l10n.advancesRowAgeing(
                    advance.accountName.isEmpty
                        ? l10n.advancesRowUnnamed
                        : advance.accountName,
                    advance.ageDays,
                  ),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              MoneyText(
                advance.remainingPaise,
                vocabulary: Vocabulary.professional,
                favour: Favour.unfavourable,
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                overdue ? Icons.error_outline : Icons.schedule,
                size: RkIcon.grid * 0.75,
                color: tint,
              ),
              const SizedBox(width: RkSpace.s1),
              Flexible(
                child: Text(
                  l10n.advancesStatusNotSettled,
                  style: theme.textTheme.bodySmall?.copyWith(color: tint),
                ),
              ),
            ],
          ),
          if (canApprove) ...[
            const SizedBox(height: RkSpace.s2),
            Wrap(
              spacing: RkSpace.s2,
              runSpacing: RkSpace.s2,
              children: [
                _DisabledAction(
                  label: l10n.advancesActionRemind,
                  reason: l10n.advancesActionRemindDisabled,
                ),
                _DisabledAction(
                  label: l10n.advancesActionWriteoff,
                  reason: l10n.advancesActionWriteoffDisabled,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 13 §4.3's disabled-with-reason: the control is visibly off, the reason is
/// on screen beside it (not hidden in a tooltip a touch user never sees), and
/// `onPressed: null` means the tap cannot go anywhere silently.
class _DisabledAction extends StatelessWidget {
  const _DisabledAction({required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Semantics(
      label: '$label — $reason',
      button: true,
      enabled: false,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(onPressed: null, child: Text(label)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              reason,
              style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
            ),
          ),
        ],
      ),
    );
  }
}
