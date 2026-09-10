// One slot of the entry, labelled by verb (07 §5 step 2 🔒). The value reads
// *Choose an account* until something is chosen — nothing is pre-selected —
// and the slot itself carries the highlight while its list holds the lower
// region, "so the eye knows where the list belongs" (design canvas 2 row 1,
// S2 state 2).
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// A labelled slot with its chosen account, or the placeholder.
class EntrySlotField extends StatelessWidget {
  /// Creates the field.
  const EntrySlotField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.open,
    this.onTap,
  });

  /// The verb's label for this slot.
  final String label;

  /// The chosen account's name, or null.
  final String? value;

  /// *Choose an account*.
  final String placeholder;

  /// True while this slot's list holds the lower region.
  final bool open;

  /// Opens this slot's list in place.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final chosen = value != null;
    return Semantics(
      button: true,
      label: '$label: ${value ?? placeholder}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // At 200 % the two slots and their chip rows own most of a 667 pt
          // screen, and 07 §5 🔒 forbids scrolling — the gap between rows is
          // the first thing to give, never the type.
          padding: EdgeInsets.symmetric(
            vertical: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                ? 0
                : RkSpace.s1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RkType.caption.copyWith(color: status.muted),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: RkSpace.s3,
                  vertical: RkSpace.s2,
                ),
                decoration: BoxDecoration(
                  color: open ? status.sunk : null,
                  border: Border(
                    bottom: BorderSide(
                      color: open ? scheme.primary : status.hairline,
                      width: open ? RkRadius.ruleLeftWidth : 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value ?? placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RkType.body.copyWith(
                          color: chosen ? scheme.onSurface : status.muted,
                        ),
                      ),
                    ),
                    Icon(
                      chosen ? Icons.check_circle_outline : Icons.search,
                      size: 18,
                      color: status.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
