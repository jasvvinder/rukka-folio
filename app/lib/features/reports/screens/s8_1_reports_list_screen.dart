// S8.1 Reports list (13 §3.2 row S8.1, 07 §14 🔒). Row order is normative —
// do not reorder without a doc change: Day Book · Cash Book · A/C statement
// (any) · Trial Balance (02 §8) · You-will-get/You-will-give with ageing ·
// Profit/Loss (per FY/range) · Full Position (02 §1.2) · Advances ageing ·
// Family Reconciliation · Partner positions (02 §7.1, shared-ownership
// businesses only) · Business comparison (Everything scope).
//
// Every report name renders so the screen is never a dead end (07 §1 rule
// 6), but none opens yet: S8.2 (report viewer + export, per scope with FY +
// date-range control and share/export) is a later lane. This screen reads
// no ledger data of its own — it is a pure list of doors, each disabled with
// the same reason until S8.2 lands.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../widgets/reports_row.dart';

/// S8.1 — the Reports list, reached from Menu (S8) → Reports.
class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = l10n.reportsRowReason;
    final rows = <String>[
      l10n.reportsDayBookRowTitle,
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
              for (final title in rows)
                ReportsDisabledRow(title: title, reason: reason),
            ],
          ),
        ),
      ),
    );
  }
}
