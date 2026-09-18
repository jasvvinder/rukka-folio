// S7.2 — the import balance check (13 §3.2 row S7.2; ADR 2026-09-01 §2 🔒:
// *S7.2 = import balance check — passing · matched · failing*; 07 §11 item 1
// 🔒 **Balance check**).
//
// The statement's own opening and closing balances against the book for those
// dates, each outcome **stated in words with the numbers**:
//
//   *Opening matches your book ✓ · Closing will match once these 23 lines are
//   recorded.*
//
// A mismatched opening means an earlier statement is missing, **and says so**
// (07 §11 item 1 🔒) — with the gap, the date, and the one next action. The
// check never blocks the import: the way out is always *Back to the lines*
// (07 §1 rule 6).
//
// Bank vocabulary throughout (02 §10 🔒): no Dr, no Cr, on this screen or the
// one it came from.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../balance_check.dart';

/// Widget keys S7.2's tests drive it by.
abstract final class ImportBalanceKeys {
  /// The verdict block — one per outcome.
  static const verdict = Key('import.balance.verdict');

  /// Back to S7.1.
  static const back = Key('import.balance.back');
}

/// S7.2 — does the statement agree with the book?
class ImportBalanceCheckScreen extends StatelessWidget {
  /// Creates the screen.
  const ImportBalanceCheckScreen({super.key, required this.check, this.onBack});

  /// The computed check.
  final ImportBalanceCheck check;

  /// Back to the lines; null pops the route.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    String money(int? paise) => paise == null
        ? ''
        : formatPaise(paise, locale: locale, showPaise: paise % 100 != 0);
    return Scaffold(
      appBar: AppBar(title: RkFitText(l.importBalanceTitle, maxLines: 1)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(RkSpace.gutter),
          children: [
            if (check.firstDate != null && check.lastDate != null)
              RkFitText(
                l.importBalancePeriod(
                  formatLedgerDate(check.firstDate!, strings: l),
                  formatLedgerDate(check.lastDate!, strings: l),
                ),
                style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
              ),
            const SizedBox(height: RkSpace.s4),
            Column(
              key: ImportBalanceKeys.verdict,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _verdict(l, theme, status, money),
            ),
            const SizedBox(height: RkSpace.s6),
            FilledButton(
              key: ImportBalanceKeys.back,
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              child: RkFitText(l.importBalanceBack),
            ),
          ],
        ),
      ),
    );
  }

  /// The three outcomes, each a word-plus-figure pair. The icon and the words
  /// carry the verdict; the tint only reinforces them (07 §1 rule 3).
  List<Widget> _verdict(
    AppLocalizations l,
    ThemeData theme,
    RkStatusColors status,
    String Function(int?) money,
  ) => switch (check.outcome) {
    ImportBalanceOutcome.unavailable => [
      _Line(
        icon: Icons.help_outline,
        tint: status.muted,
        text: l.importBalanceUnavailable,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: RkSpace.s2),
      RkFitText(
        l.importBalanceUnavailableNext,
        style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
      ),
    ],
    ImportBalanceOutcome.matched => [
      _Line(
        icon: Icons.check_circle_outline,
        tint: status.success,
        text: l.importBalanceOpeningMatch,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: RkSpace.s2),
      _Line(
        icon: Icons.check_circle_outline,
        tint: status.success,
        text: l.importBalanceMatched,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: RkSpace.s2),
      RkFitText(
        l.importBalanceClosingFigures(
          money(check.statementClosingPaise),
          money(check.ledgerClosingPaise),
        ),
        style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
      ),
    ],
    ImportBalanceOutcome.passing => [
      _Line(
        icon: Icons.check_circle_outline,
        tint: status.success,
        text: l.importBalanceOpeningMatch,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: RkSpace.s1),
      RkFitText(
        l.importBalanceOpeningFigures(
          money(check.statementOpeningPaise),
          money(check.ledgerOpeningPaise),
        ),
        style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
      ),
      const SizedBox(height: RkSpace.s4),
      _Line(
        icon: check.closingWillMatch
            ? Icons.trending_flat
            : Icons.warning_amber_outlined,
        tint: check.closingWillMatch ? status.info : status.warning,
        text: check.closingWillMatch
            ? l.importBalanceClosingWill(check.lineCount)
            : l.importBalanceClosingWont,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: RkSpace.s1),
      RkFitText(
        l.importBalanceClosingFigures(
          money(check.statementClosingPaise),
          money(check.projectedClosingPaise),
        ),
        style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
      ),
    ],
    ImportBalanceOutcome.failing => [
      _Line(
        icon: Icons.error_outline,
        tint: status.warning,
        text: l.importBalanceOpeningMismatch,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: RkSpace.s1),
      RkFitText(
        l.importBalanceOpeningFigures(
          money(check.statementOpeningPaise),
          money(check.ledgerOpeningPaise),
        ),
        style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
      ),
      const SizedBox(height: RkSpace.s4),
      _Line(
        icon: Icons.history,
        tint: status.warning,
        text: l.importBalanceFailing,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: RkSpace.s1),
      RkFitText(
        l.importBalanceFailingGap(
          money(check.openingGapPaise?.abs()),
          check.firstDate == null
              ? ''
              : formatLedgerDate(check.firstDate!, strings: l),
        ),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: RkSpace.s2),
      RkFitText(
        l.importBalanceFailingNext,
        style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
      ),
    ],
  };
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.tint,
    required this.text,
    this.style,
  });

  final IconData icon;
  final Color tint;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: RkIcon.grid, color: tint),
      const SizedBox(width: RkSpace.s2),
      Expanded(child: RkFitText(text, style: style)),
    ],
  );
}
