// S8.1 Reports list (13 §3.2 row S8.1, 07 §14 🔒). Row order is normative —
// do not reorder without a doc change: Day Book · Cash Book · A/C statement
// (any) · Trial Balance (02 §8) · You-will-get/You-will-give with ageing ·
// Profit/Loss (per FY/range) · Full Position (02 §1.2) · Advances ageing ·
// Family Reconciliation · Partner positions (02 §7.1, shared-ownership
// businesses only) · Business comparison (Everything scope).
//
// Every report name renders so the screen is never a dead end (07 §1 rule 6).
// Exactly one of them opens at M5: **Day Book** → S8.2 (the report viewer +
// export), because 10's M5 row is *"basic day-book export"* and ADR
// 2026-09-12's Consequences put the remaining ten reports and every F3 export
// golden at M12. The other ten stay disabled-with-reason. This screen reads
// no ledger data of its own — it is a list of doors.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../widgets/reports_row.dart';

/// S8.1 — the Reports list, reached from Menu (S8) → Reports.
class ReportsListScreen extends StatelessWidget {
  /// Creates the screen.
  const ReportsListScreen({super.key, this.onOpenDayBook});

  /// Opens S8.2 for the Day Book — row 1 of 07 §14's 🔒 order, and the only
  /// row with a destination at M5. Null leaves it disabled-with-reason like
  /// the other ten, so the screen is still never a dead end.
  final VoidCallback? onOpenDayBook;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = l10n.reportsRowReason;
    // 07 §14 🔒 order — do not reorder without a doc change.
    final rows = <String>[
      l10n.reportsCashBookRowTitle,
      l10n.reportsAccountStatementRowTitle,
      l10n.reportsTrialBalanceRowTitle,
      l10n.reportsGetGiveAgeingRowTitle,
      l10n.reportsProfitLossRowTitle,
      l10n.reportsFullPositionRowTitle,
      l10n.reportsAdvancesAgeingRowTitle,
      l10n.reportsFamilyReconciliationRowTitle,
      l10n.reportsPartnerPositionsRowTitle,
      l10n.reportsBusinessComparisonRowTitle,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportsTitle)),
      body: SafeArea(
        // Non-lazy on purpose: a `ListView` only builds the rows inside the
        // viewport, so the tail of 07 §14's 🔒 order would be absent from the
        // tree at 200% scale. Same shape as S13 (07 §16) and S8 (07 §2).
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1 of 11 — the one report S8.2 can show at M5.
              if (onOpenDayBook != null)
                ReportsActionRow(
                  title: l10n.reportsDayBookRowTitle,
                  icon: Icons.menu_book_outlined,
                  onTap: onOpenDayBook!,
                )
              else
                ReportsDisabledRow(
                  title: l10n.reportsDayBookRowTitle,
                  reason: reason,
                ),
              // Rows 2–11, still M12.
              for (final title in rows)
                ReportsDisabledRow(title: title, reason: reason),
            ],
          ),
        ),
      ),
    );
  }
}
