// The quick chips of the money-account slot (07 §5 step 2 🔒): the three
// most-used money accounts plus **+ More** for the full list. The row is
// **absent entirely** when no money account is involved — milk on khata
// (`Dr Milk Expense · Cr Vardhman Dairy`) shows no chips rather than three
// chips that must not be tapped. **No chip is pre-selected** (ADR 2026-09-05f
// §C): a wrong default posts a wrong entry and nobody notices until the month
// will not reconcile.
//
// Selection is never colour alone (07 §1 rule 5) — the chosen chip carries a
// tick as well as its tone.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// One money-account chip.
class EntryAccountChip extends StatelessWidget {
  /// Creates the chip.
  const EntryAccountChip({
    super.key,
    required this.name,
    required this.selected,
    this.onTap,
  });

  /// The account's own name, in whatever script the user typed it.
  final String name;

  /// True when this chip is the slot's answer.
  final bool selected;

  /// Chooses this account.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: RkSpace.s2),
      child: Material(
        color: selected ? scheme.primary : status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RkRadius.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RkSpace.s3,
              vertical: RkSpace.s2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(right: RkSpace.s1),
                    child: Icon(Icons.check, size: 16, color: scheme.onPrimary),
                  ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RkType.body.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chip row: chips, then **+ More**. Pans horizontally — this screen
/// never scrolls *vertically* (07 §5 🔒).
class EntryChipRow extends StatelessWidget {
  /// Creates the row.
  const EntryChipRow({
    super.key,
    required this.names,
    required this.selectedId,
    required this.onPick,
    required this.onMore,
    required this.moreLabel,
  });

  /// Account id → name, in chip order.
  final List<(String, String)> names;

  /// The slot's answer, or null while nothing is chosen.
  final String? selectedId;

  /// Chooses an account.
  final void Function(String id) onPick;

  /// Opens the full list in the lower region (never a sheet, 07 §5 🔒).
  final VoidCallback onMore;

  /// The **+ More** label.
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (id, name) in names)
            EntryAccountChip(
              key: ValueKey('entry.chip.$id'),
              name: name,
              selected: id == selectedId,
              onTap: () => onPick(id),
            ),
          TextButton(onPressed: onMore, child: Text(moreLabel)),
        ],
      ),
    );
  }
}
