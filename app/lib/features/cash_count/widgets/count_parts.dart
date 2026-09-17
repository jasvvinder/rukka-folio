// The two pieces of chrome S5.5 adds to the design-system atoms. `RkFitText`,
// `RkSkeleton` and `RkErrorState` used to be copied here; they are the 13 §4
// atoms and now come from `shared/widgets/`. Tokens only — a hex literal here
// is review-blocking (CLAUDE.md, design-system).
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';

/// A quiet chip — the offline/saved-on-phone note of 07 §1 rule 7 🔒, which
/// is never a blocking banner. Icon plus words, so the tint is never alone.
class CountQuietChip extends StatelessWidget {
  /// Creates the chip.
  const CountQuietChip({super.key, required this.label, required this.icon});

  /// The words.
  final String label;

  /// The glyph beside them.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s3,
        vertical: RkSpace.s1,
      ),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.md),
        border: Border.all(color: status.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: RkSpace.s4, color: status.muted),
          const SizedBox(width: RkSpace.s2),
          Flexible(
            child: RkFitText(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: status.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A persistent banner (13 §4.2) — read-only here: the state and its reason,
/// with a lock glyph so colour never carries the meaning alone.
class CountBanner extends StatelessWidget {
  /// Creates the banner.
  const CountBanner({super.key, required this.title, required this.reason});

  /// The state in one or two words.
  final String title;

  /// Why, and what the reader may still do (07 §1 rule 6).
  final String reason;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RkSpace.cardPadding),
      decoration: BoxDecoration(
        color: status.sunk,
        border: Border(bottom: BorderSide(color: status.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: RkSpace.s5, color: status.locked),
          const SizedBox(width: RkSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RkFitText(title, style: text.titleSmall),
                const SizedBox(height: RkSpace.s1),
                RkFitText(
                  reason,
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
