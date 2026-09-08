// The countdown atom (13 §4.2) for the 24 h cancel windows — formatted from
// the injected clock, Latin digits, tabular figures.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/tokens.dart';

/// `23 h 59 min` · `12 min` · `40 s`.
String formatCountdown(AppLocalizations l10n, Duration d) {
  if (d.inHours >= 1) {
    return l10n.devicesTimeHoursMinutes(d.inHours, d.inMinutes % 60);
  }
  if (d.inMinutes >= 1) return l10n.devicesTimeMinutes(d.inMinutes);
  return l10n.devicesTimeSeconds(d.inSeconds);
}

/// One line: clock icon + "Completes in {time}".
class CountdownLine extends StatelessWidget {
  const CountdownLine({super.key, required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          Icons.schedule,
          size: RkIcon.grid - RkSpace.s1,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: Text(
            l10n.devicesWindowCompletesIn(formatCountdown(l10n, remaining)),
            style: text.bodyMedium?.copyWith(fontFeatures: RkType.tabular),
          ),
        ),
      ],
    );
  }
}
