// The verb pill — five positions 🔒 (owner-ruled 3 Sep 2026, ADR
// 2026-09-03b): Money in · Money out · Gave on credit · Took on credit ·
// **Move money**. The transfer (S2.3) is the fifth swipe, not a separate
// door, and switching position never loses the amount (07 §5).
//
// Consumer vocabulary only (02 §10 🔒): plain verbs, never Dr/Cr. Selection
// is never colour alone (07 §1 rule 5) — the chosen position carries a tick.
// The row pans horizontally; this screen never scrolls vertically.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../entry_slots.dart';

/// The five-position pill.
class EntryVerbPill extends StatelessWidget {
  /// Creates the pill.
  const EntryVerbPill({super.key, required this.kind, required this.onKind});

  /// The position showing.
  final EntryKind kind;

  /// Switches position, keeping the amount.
  final void Function(EntryKind kind) onKind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final k in entryVerbs)
            Padding(
              padding: const EdgeInsets.only(right: RkSpace.s2),
              child: Material(
                color: k == kind ? scheme.primary : status.sunk,
                borderRadius: BorderRadius.circular(RkRadius.lg),
                child: InkWell(
                  onTap: () => onKind(k),
                  borderRadius: BorderRadius.circular(RkRadius.lg),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RkSpace.s3,
                      vertical: RkSpace.s2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (k == kind)
                          Padding(
                            padding: const EdgeInsets.only(right: RkSpace.s1),
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: scheme.onPrimary,
                            ),
                          ),
                        Text(
                          verbLabel(l10n, k),
                          maxLines: 1,
                          style: RkType.body.copyWith(
                            fontWeight: k == kind
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: k == kind
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
