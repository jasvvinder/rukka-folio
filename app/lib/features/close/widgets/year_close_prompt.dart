// *The prompt after March locks* — 07 §13 🔒's second door into S10.4
// (*Year close (Menu → per book, or the prompt after March locks)*).
//
// It is drawn where the closer already is, on the reward screen the moment the
// financial year's last month locks (S10.2, 13 §3.2). That is the one moment
// the ceremony is both possible and obviously worth doing: every month of the
// year is now locked, which is 02 §8.1 🔒's first precondition, and the closer
// is holding the phone.
//
// It is an **offer, never a gate**: the *Done* action on the card beneath it is
// untouched, so a shopkeeper who wants to close the year in April can (07 §1
// rule 6 — a prompt that has to be answered is a dead end with extra steps).
//
// The other door — Menu → per book — belongs to `features/menu` (S8), which is
// another lane's folder; the path constant it links to is
// [ClosePaths.forYear].
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import 'close_parts.dart';

/// True when [period] is the **last month** of its financial year, and so the
/// moment 07 §13 🔒 says to prompt.
///
/// [fyStartMonth] is the book's own FY start (1–12): April for most books, but
/// a trust may run the calendar year, and hard-coding March would silently
/// prompt at the wrong time for it.
bool isLastMonthOfFy(YearMonth period, {int fyStartMonth = 4}) =>
    financialYearOf(period, fyStartMonth: fyStartMonth).months.last == period;

/// The financial year [period] falls in, for a book whose FY starts in
/// [fyStartMonth].
FinancialYear financialYearOf(YearMonth period, {int fyStartMonth = 4}) =>
    FinancialYear.of(period.firstDay, startMonth: fyStartMonth);

/// The offer to run the Year Close ceremony, shown once the FY's last month
/// has locked.
class YearClosePrompt extends StatelessWidget {
  /// Creates the prompt for [financialYear]. [onOpen] takes the caller to
  /// S10.4; null renders no action, which is how a surface with no router
  /// (a golden, a preview) draws it.
  const YearClosePrompt({super.key, required this.financialYear, this.onOpen});

  /// The year that has just finished.
  final FinancialYear financialYear;

  /// Opens S10.4.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return CloseCard(
      rule: status.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RkFitText(
            l.closeYearPromptTitle(financialYear.label),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: RkSpace.s1),
          Text(
            l.closeYearPromptBody,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: status.muted),
          ),
          if (onOpen != null) ...[
            const SizedBox(height: RkSpace.s3),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.verified_outlined),
                label: Text(l.closeYearPromptAction),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
