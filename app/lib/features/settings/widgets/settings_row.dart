// Row widgets shared by S13 Settings (07 §16, 13 §4.3). Two shapes:
// [SettingsRow] — enabled, navigable, ends in a chevron; and
// [SettingsDisabledRow] — disabled-with-reason (07 §1 rule 6): the row never
// disappears and never sits inert with no explanation, it just cannot be
// entered yet, with a clock icon paired to the reason text so the state
// never rides on colour alone (07 §1 rule 3).
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// A section header ("Your books", …) above a group of rows.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RkSpace.gutter,
      RkSpace.s5,
      RkSpace.gutter,
      RkSpace.s2,
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

/// One tappable settings row: title, optional subtitle, optional trailing
/// widget (defaults to a chevron).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
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
                    Text(title, style: text.bodyLarge),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: RkSpace.s2),
              trailing ??
                  Icon(Icons.chevron_right, color: status.muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings row whose destination has not been built yet. Never a dead
/// end (07 §1 rule 6): dimmed title + a clock icon paired with the reason
/// text explain why, so the state is never carried by colour alone
/// (07 §1 rule 3). `onTap` is always null — the row is genuinely disabled,
/// not a fake link.
class SettingsDisabledRow extends StatelessWidget {
  const SettingsDisabledRow({
    super.key,
    required this.title,
    required this.reason,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(color: status.muted),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.schedule, size: 14, color: status.muted),
                          const SizedBox(width: RkSpace.s1),
                          Expanded(
                            child: Text(
                              reason,
                              style: text.bodySmall?.copyWith(
                                color: status.muted,
                              ),
                            ),
                          ),
                        ],
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
