// S8.1's disabled-with-reason row (13 §4.3, 07 §1 rule 6): every report name
// from 07 §14 is present so the screen is never a dead end, but none opens
// yet — S8.2 (the report viewer + export) is a later lane. Dimmed title +
// a clock icon paired with the reason text, so the state never rides on
// colour alone (07 §1 rule 3). Mirrors `features/settings`'
// `SettingsDisabledRow` (the 13 §4.3 precedent), kept local to this feature
// rather than shared since neither feature owns the other.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

class ReportsDisabledRow extends StatelessWidget {
  const ReportsDisabledRow({
    super.key,
    required this.title,
    required this.reason,
  });

  final String title;
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
