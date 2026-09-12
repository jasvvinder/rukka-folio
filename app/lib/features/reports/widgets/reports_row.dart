// The two rows this feature draws, on S8.1 (the report list) and inside
// S8.2's export sheet:
//
//   • [ReportsDisabledRow] — disabled-with-reason (13 §4.3, 07 §1 rule 6): the
//     name is present so the screen is never a dead end, and a clock icon sits
//     beside the reason text so the state never rides on colour alone (07 §1
//     rule 3). Mirrors `features/settings`' `SettingsDisabledRow` (the 13 §4.3
//     precedent), kept local to this feature rather than shared since neither
//     feature owns the other. Ten of S8.1's eleven reports wear it — only the
//     Day Book has a destination at M5. **S8.2's export sheet no longer does:**
//     its PDF row was unblocked by ADR 2026-09-12d §3 🔒 and its XLSX row by
//     ADR 2026-09-12e §1 🔒, so all three formats run.
//   • [ReportsActionRow] — the enterable twin: same rhythm, full-strength ink,
//     a leading icon and a chevron, with a real tap target.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

class ReportsDisabledRow extends StatelessWidget {
  /// Creates the row.
  const ReportsDisabledRow({
    super.key,
    required this.title,
    required this.reason,
    this.description,
  });

  /// The report's (or format's) name.
  final String title;

  /// Why it cannot be opened yet — always words, never a colour (07 §1).
  final String reason;

  /// What the thing is for, when the name alone does not say it (the export
  /// sheet's formats). Null on S8.1, where the report names speak.
  final String? description;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      enabled: false,
      label: description == null
          ? '$title. $reason'
          : '$title. $description. $reason',
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
                      // *Family Reconciliation* is 455 px of a single word at
                      // 200% and a 360 px phone is 328 px wide: a word that
                      // long cannot be wrapped, only cut. Cut it with an
                      // ellipsis, so the reader can see that there is more of
                      // the name rather than reading a word that silently
                      // ends (07 §1 rule 11).
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description!,
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

/// An enterable report/format row: the same rhythm as [ReportsDisabledRow] but
/// in full-strength ink, with a leading icon and a chevron so *enterable* is
/// never carried by colour alone (07 §1 rule 3). Its tap target is the whole
/// row at [RkSpace.rowMinHeight].
class ReportsActionRow extends StatelessWidget {
  /// Creates the row.
  const ReportsActionRow({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.description,
  });

  /// The report's (or format's) name.
  final String title;

  /// What it is for, under the name.
  final String? description;

  /// Leading icon — paired with the words, never instead of them.
  final IconData icon;

  /// Opens it.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Past 1.3x a ListTile cannot hold an icon, the name and a chevron on one
    // line at 360 px, so the chevron drops and the text takes the width
    // (07 §1 rule 11 — the same fold S4 and the FY sheet use).
    final crowded = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return ListTile(
      minTileHeight: RkSpace.rowMinHeight,
      leading: Icon(icon),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge,
        // See [ReportsDisabledRow]: at 200% a long report name is wider than
        // the phone and can only be cut — with an ellipsis, never silently.
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: description == null ? null : Text(description!),
      trailing: crowded ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
