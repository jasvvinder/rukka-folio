// The pieces S7 and S7.0a–c are built from (13 §4.1: one component, one
// definition). Tokens only — a hex literal here is review-blocking.
//
// Bank vocabulary throughout: *Money in* / *Money out*, never Dr/Cr
// (02 §10 🔒, CLAUDE.md rule 9). Nothing in this file names a side.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../parse/parsed_statement.dart';

/// A step heading — *1 · Which A/C is this statement for?*
class ImportStepTitle extends StatelessWidget {
  /// Creates the heading.
  const ImportStepTitle(this.text, {super.key, this.help});

  /// The heading.
  final String text;

  /// One muted line beneath it.
  final String? help;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s5,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(text, style: theme.textTheme.titleMedium),
          if (help != null) ...[
            const SizedBox(height: RkSpace.s1),
            RkFitText(
              help!,
              style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The drop zone (design S7.0a): what it accepts, how big, and where the file
/// is read.
///
/// The three lines are not decoration. *CSV, XLS, OFX or PDF · up to 10 MB* is
/// 07 §11 item 1 🔒 verbatim, and *read on this phone* is the on-device rule
/// said where the user is about to act on it (04).
class ImportDropZone extends StatelessWidget {
  /// Creates the zone.
  const ImportDropZone({
    super.key,
    required this.onPick,
    this.busyWith,
    this.enabled = true,
  });

  /// Opens the file picker.
  final VoidCallback onPick;

  /// The file being read, when one is; the zone shows the loader rule and the
  /// name instead of the action.
  final String? busyWith;

  /// Whether a file can be picked at all.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final busy = busyWith != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(RkSpace.s5),
        decoration: BoxDecoration(
          color: status.sunk,
          borderRadius: BorderRadius.circular(RkRadius.lg),
          border: Border.all(color: status.hairline),
        ),
        child: Column(
          children: [
            if (busy) ...[
              // The determinate-shaped rule, never a spinner (11 §4.5).
              LinearProgressIndicator(
                minHeight: RkMotion.loaderTrackHeight,
                backgroundColor: status.loaderTrack,
                color: status.loaderSegment,
              ),
              const SizedBox(height: RkSpace.s3),
              RkFitText(
                l.importFileReading(busyWith!),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ] else
              FilledButton.icon(
                onPressed: enabled ? onPick : null,
                icon: const Icon(Icons.description_outlined),
                label: RkFitText(l.importFileChoose),
              ),
            const SizedBox(height: RkSpace.s3),
            RkFitText(
              l.importFileAccepts,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s1),
            RkFitText(
              l.importFileToday,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.phone_iphone,
                  size: RkIcon.grid,
                  color: status.success,
                ),
                const SizedBox(width: RkSpace.s2),
                Flexible(
                  child: RkFitText(
                    l.importFileOndevice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The parse-failure state (07 §11 item 4 🔒): *Couldn't read this file* + the
/// supported-format list + *send file format to support* — and the standing
/// promise that the file itself never leaves the device.
///
/// The icon and the words carry the failure; the tint only reinforces it
/// (07 §1 rule 3). It is never a dead end: [onAnother] is always offered.
class ParseFailurePanel extends StatelessWidget {
  /// Creates the panel.
  const ParseFailurePanel({
    super.key,
    required this.failure,
    required this.onAnother,
    this.onTellUs,
  });

  /// What went wrong.
  final StatementParseFailure failure;

  /// Pick a different file.
  final VoidCallback onAnother;

  /// Offer this bank's format to support. Absent until the support door
  /// exists; the panel then states the formats and nothing more.
  final VoidCallback? onTellUs;

  /// The one line that names the cause (07 §1 rule 12: named cause + path).
  static String reasonLine(AppLocalizations l, StatementParseFailure f) =>
      switch (f.reason) {
        ParseFailureReason.tooLarge => l.importFailToobig,
        ParseFailureReason.notYetSupported => l.importFailNotyet(
          f.format?.name.toUpperCase() ?? '',
        ),
        ParseFailureReason.unsupportedFormat => l.importFailNotyet(
          _extensionOf(f.fileName),
        ),
        ParseFailureReason.noHeaderRow ||
        ParseFailureReason.unreadable => l.importFailUnreadable,
        ParseFailureReason.noAmountColumn => l.importFailNocolumns,
        ParseFailureReason.noLines => l.importFailNolines,
      };

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: RkFitText(
                  l.importFailTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s2),
          RkFitText(reasonLine(l, failure), style: theme.textTheme.bodyMedium),
          const SizedBox(height: RkSpace.s2),
          RkFitText(
            l.importFailFormats,
            style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s4),
          FilledButton(
            onPressed: onAnother,
            child: RkFitText(l.importFailAnother),
          ),
          if (onTellUs != null) ...[
            const SizedBox(height: RkSpace.s2),
            TextButton(
              onPressed: onTellUs,
              child: RkFitText(l.importFailSupport),
            ),
          ],
          const SizedBox(height: RkSpace.s1),
          RkFitText(
            l.importFailSupportHelp,
            style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
          ),
        ],
      ),
    );
  }
}
