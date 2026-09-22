// Row shapes for S12 (13 §4.3: every component ships *disabled-with-reason*).
// The same pair `features/settings` and `features/menu` already carry, kept
// local because no feature owns another's widgets.
//
// Both draw through [RkFitText]: at 200 % on a 360 px phone one row word —
// *Subscription*, *ਸਬਸਕ੍ਰਿਪਸ਼ਨ*, *सब्सक्रिप्शन* — is wider than the row, and a
// paragraph given less width than its longest word draws it past the edge
// without throwing.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';

/// One tappable row: title, optional subtitle, chevron.
class SubscriptionRow extends StatelessWidget {
  /// Creates the row.
  const SubscriptionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  /// Row title.
  final String title;

  /// Optional description.
  final String? subtitle;

  /// Where it goes. Null renders an inert row — prefer
  /// [SubscriptionDisabledRow], which says why.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      button: onTap != null,
      label: subtitle == null ? title : '$title. $subtitle',
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RkFitText(title, style: text.bodyLarge),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: RkFitText(
                          subtitle!,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: RkSpace.s2),
              Icon(Icons.chevron_right, color: status.muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row whose destination has not been built yet — never a dead end
/// (07 §1 rule 6): dimmed title plus a clock icon paired with the reason, so
/// the state never rides on colour alone (07 §1 rule 3). `onTap` is always
/// null; the row is genuinely disabled, not a fake link.
class SubscriptionDisabledRow extends StatelessWidget {
  /// Creates the row.
  const SubscriptionDisabledRow({
    super.key,
    required this.title,
    required this.reason,
  });

  /// Row title.
  final String title;

  /// Why it cannot be opened yet.
  final String reason;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      enabled: false,
      label: '$title. $reason',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RkFitText(
                title,
                style: text.bodyLarge?.copyWith(color: status.muted),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 14, color: status.muted),
                    const SizedBox(width: RkSpace.s1),
                    Expanded(
                      child: RkFitText(
                        reason,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
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
