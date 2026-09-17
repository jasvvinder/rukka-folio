// The two component states of 13 §4.3 that every screen ships: the loading
// skeleton and error-with-retry. (The third, disabled-with-reason, is
// `RkRestriction` / `RkBanner` in this same folder.) Tokens only — a hex
// literal here is review-blocking (CLAUDE.md, design-system).
//
// One definition for what `features/home`, `features/cash_count` and
// `features/close` had each copied locally.
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import 'rk_fit_text.dart';

/// The ruled skeleton (13 §4.3, 11 §4.5): never a spinner, always the shape
/// of what is coming. [label] is what a screen reader announces while it
/// shows — the wait is stated in words, so the grey rules are never the only
/// carrier of the state (07 §1 rule 3).
class RkSkeleton extends StatelessWidget {
  /// Creates the skeleton.
  const RkSkeleton({super.key, required this.label, this.rows = 6});

  /// Screen-reader announcement.
  final String label;

  /// How many ruled rows to draw.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      child: ListView.builder(
        padding: const EdgeInsets.all(RkSpace.gutter),
        itemCount: rows,
        itemBuilder: (context, i) => Container(
          height: RkSpace.rowMinHeight,
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: i.isEven
                  ? RkMotion.skeletonLabelWidthMax
                  : RkMotion.skeletonLabelWidthMin,
              child: Container(
                height: RkSpace.s3,
                decoration: BoxDecoration(
                  color: status.skeletonLabel,
                  borderRadius: BorderRadius.circular(RkRadius.sm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error with a named cause and the path out — never a dead end (13 §4.3,
/// 07 §1 rule 12). The icon and the words carry the failure; the error tint
/// only reinforces it (07 §1 rule 3).
class RkErrorState extends StatelessWidget {
  /// Creates the state.
  const RkErrorState({
    super.key,
    required this.text,
    required this.retryLabel,
    required this.onRetry,
  });

  /// What failed, in the user's words.
  final String text;

  /// Label of the retry control.
  final String retryLabel;

  /// Clears the error and tries again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(RkSpace.s6),
    children: [
      const SizedBox(height: RkSpace.s8),
      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
      const SizedBox(height: RkSpace.s3),
      // Fit-measured, not plain `Text`: the cash-count copy had already
      // learned that a 200 % Gurmukhi error line leaves the box, and the
      // message is the one string a reader must be able to finish.
      RkFitText(text, textAlign: TextAlign.center),
      const SizedBox(height: RkSpace.s4),
      Center(
        child: FilledButton(onPressed: onRetry, child: Text(retryLabel)),
      ),
    ],
  );
}
