// S8.1 Reports list (13 §3.2 row S8.1, 07 §14 🔒). Row order is normative —
// do not reorder without a doc change: Day Book · Cash Book · A/C statement
// (any) · Trial Balance (02 §8) · You-will-get/You-will-give with ageing ·
// Profit/Loss (per FY/range) · Full Position (02 §1.2) · Advances ageing ·
// Family Reconciliation · Partner positions (02 §7.1, shared-ownership
// businesses only) · Business comparison (Everything scope).
//
// Every report name renders so the screen is never a dead end (07 §1 rule 6).
// Two of them open: **Day Book** → S8.2 (the report viewer + export), because
// 10's M5 row is *"basic day-book export"*, and — since M8 — **Family
// Reconciliation** → S8.3, which 07 §10 🔒 places here ("Menu → Reports") and
// which the inter-book surface of 02 §6 made buildable. ADR 2026-09-12's
// Consequences put the remaining nine reports and every F3 export golden at
// M12, so those stay disabled-with-reason. This screen reads no ledger data of
// its own — it is a list of doors.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../widgets/reports_row.dart';

/// S8.1 — the Reports list, reached from Menu (S8) → Reports.
class ReportsListScreen extends StatelessWidget {
  /// Creates the screen.
  const ReportsListScreen({
    super.key,
    this.onOpenDayBook,
    this.onOpenReconciliation,
    this.showPartnerPositions = false,
    this.onOpenPartnerPositions,
  });

  /// Opens S8.2 for the Day Book — row 1 of 07 §14's 🔒 order. Null leaves it
  /// disabled-with-reason like the unbuilt rows, so the screen is still never
  /// a dead end.
  final VoidCallback? onOpenDayBook;

  /// Opens S8.3 Family reconciliation — row 9 of 07 §14's 🔒 order, the screen
  /// 07 §10 🔒 reaches from *Menu → Reports*. Null, again, leaves the row
  /// disabled-with-reason rather than inert.
  final VoidCallback? onOpenReconciliation;

  /// Whether this book is a **shared business** — the only book that has
  /// partners at all (02 §7.1 🔒). 07 §14 🔒 spells the row *"Partner
  /// positions (02 §7.1, shared-ownership businesses only)"*, and ADR
  /// 2026-09-09b 🔒 goes further: a *Just me* business never mentions
  /// partners, ratios or profit distribution **anywhere**. So the row is
  /// *absent* here rather than disabled-with-reason — a disabled row names
  /// the thing, and naming it is exactly what the ADR forbids. The default is
  /// false: an unread or unrecorded ownership is *not recorded*, never
  /// *shared* (the conservative reading, as `PartnerPosition.ratioWeight`
  /// takes for the weights).
  final bool showPartnerPositions;

  /// Opens S14 Partner positions for this book. Only consulted when
  /// [showPartnerPositions]; null there leaves the row
  /// disabled-with-reason like the unbuilt reports, never an inert tap
  /// (07 §1 rule 6).
  final VoidCallback? onOpenPartnerPositions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = l10n.reportsRowReason;
    // 07 §14 🔒 order — do not reorder without a doc change. A row with a null
    // `onTap` is disabled-with-reason (13 §4.3), never an inert tap.
    final rows = <({String title, IconData icon, VoidCallback? onTap})>[
      (
        title: l10n.reportsDayBookRowTitle,
        icon: Icons.menu_book_outlined,
        onTap: onOpenDayBook,
      ),
      (
        title: l10n.reportsCashBookRowTitle,
        icon: Icons.payments_outlined,
        onTap: null,
      ),
      (
        title: l10n.reportsAccountStatementRowTitle,
        icon: Icons.receipt_long_outlined,
        onTap: null,
      ),
      (
        title: l10n.reportsTrialBalanceRowTitle,
        icon: Icons.balance_outlined,
        onTap: null,
      ),
      (
        title: l10n.reportsGetGiveAgeingRowTitle,
        icon: Icons.people_outline,
        onTap: null,
      ),
      (
        title: l10n.reportsProfitLossRowTitle,
        icon: Icons.trending_up_outlined,
        onTap: null,
      ),
      (
        title: l10n.reportsFullPositionRowTitle,
        icon: Icons.account_balance_outlined,
        onTap: null,
      ),
      (
        title: l10n.reportsAdvancesAgeingRowTitle,
        icon: Icons.schedule_outlined,
        onTap: null,
      ),
      (
        title: l10n.reportsFamilyReconciliationRowTitle,
        icon: Icons.compare_arrows_outlined,
        onTap: onOpenReconciliation,
      ),
      if (showPartnerPositions)
        (
          title: l10n.reportsPartnerPositionsRowTitle,
          icon: Icons.handshake_outlined,
          onTap: onOpenPartnerPositions,
        ),
      (
        title: l10n.reportsBusinessComparisonRowTitle,
        icon: Icons.compare_outlined,
        onTap: null,
      ),
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
              for (final row in rows)
                if (row.onTap case final open?)
                  ReportsActionRow(
                    title: row.title,
                    icon: row.icon,
                    onTap: open,
                  )
                else
                  ReportsDisabledRow(title: row.title, reason: reason),
            ],
          ),
        ),
      ),
    );
  }
}
