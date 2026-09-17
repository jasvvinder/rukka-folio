// The denomination grid of 02 §8.2 🔒 and 07 §5.5: one row per note — ₹500 ·
// ₹200 · ₹100 · ₹50 · ₹20 · ₹10, with ₹2000 offered **only when a previous
// count used it** — each with a stepper and a live line total.
//
// The grid is a *memo*, never a sub-ledger: it is captured at count time and
// nothing here ever touches an entry. Every figure is integer paise; the row
// arithmetic is `Paise.rupees(value) * count`, engine types end to end.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';

/// The note values, largest first. ₹2000 leads the list but is drawn only
/// when [DenominationGrid.showTwoThousand] (02 §8.2).
const noteValuesInRupees = [2000, 500, 200, 100, 50, 20, 10];

/// One row per note value, each a stepper with its running line total.
class DenominationGrid extends StatelessWidget {
  /// Creates the grid.
  const DenominationGrid({
    super.key,
    required this.counts,
    required this.onChanged,
    this.showTwoThousand = false,
    this.enabled = true,
  });

  /// Note value (rupees) → how many are on the table.
  final Map<int, int> counts;

  /// Called with the new count for one note value.
  final void Function(int value, int count) onChanged;

  /// Whether the ₹2000 row is offered — true only when the previous count
  /// held ₹2000 notes (02 §8.2: still legal tender, rarely held).
  final bool showTwoThousand;

  /// False in the read-only variant: the steppers disable, the figures stay.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final values = noteValuesInRupees
        .where((v) => v != 2000 || showTwoThousand)
        .toList();
    return Column(
      children: [
        for (final value in values)
          _DenominationRow(
            value: value,
            count: counts[value] ?? 0,
            enabled: enabled,
            onChanged: (n) => onChanged(value, n),
          ),
      ],
    );
  }
}

class _DenominationRow extends StatelessWidget {
  const _DenominationRow({
    required this.value,
    required this.count,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final int count;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final face = formatPaise(Paise.rupees(value).raw, locale: locale);
    final line = formatPaise(Paise.rupees(value * count).raw, locale: locale);
    final label = l10n.countGridRow(face);
    return Semantics(
      container: true,
      label: l10n.countGridLine(count, face, line),
      explicitChildNodes: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
        padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: status.hairline)),
        ),
        // Measured, not thresholded: the line total drops under the stepper
        // the moment the three no longer fit the row (07 §1 rule 11).
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: RkSpace.s3,
          runSpacing: RkSpace.s1,
          children: [
            RkFitText(label, style: Theme.of(context).textTheme.bodyLarge),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepButton(
                  icon: Icons.remove,
                  tooltip: l10n.countGridRemove(face),
                  onPressed: enabled && count > 0
                      ? () => onChanged(count - 1)
                      : null,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: RkSpace.s8),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontFeatures: RkType.tabular),
                  ),
                ),
                _StepButton(
                  icon: Icons.add,
                  tooltip: l10n.countGridAdd(face),
                  onPressed: enabled ? () => onChanged(count + 1) : null,
                ),
                const SizedBox(width: RkSpace.s2),
                // The running line total the stepper rule requires
                // (design-system §3.1 rule 6 🔒). Plain ink: it is a total,
                // not a direction, so no credit/debit tint belongs on it.
                Text(
                  line,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontFeatures: RkType.tabular,
                    color: count == 0 ? status.muted : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    enabled: onPressed != null,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: RkIcon.grid),
      // ≥ 44pt targets (design-system §3.1 rule 9).
      constraints: const BoxConstraints(
        minWidth: RkSpace.s12,
        minHeight: RkSpace.s12,
      ),
      tooltip: tooltip,
    ),
  );
}
