// S8 Menu (13 §3.2 row S8, 07 §2 🔒 bottom bar). Row order is normative — do
// not reorder without a doc change: Reports · Close the month (ADR
// 2026-09-03) · Books & members · Backup · Devices & security ·
// Subscription · Settings · Help · Legal (owner-added 3 Sep 2026).
//
// Reports (S8.1), Books (S9 — `features/books`, whose list carries the S9.5
// *Add a business* entry point 07 §5.7 🔒 names this row as), Backup (S11.4),
// Devices & security (S11) and Settings (S13) already have a real destination — S11.4/S11/S13
// were built by earlier lanes and are wired into the app's featureRoutes
// (main.dart), so this screen only needs their path to push. Every other
// row's screen has not landed in this milestone, so it renders
// disabled-with-reason (07 §1 rule 6) — dimmed, paired with an icon and a
// sentence, never a silently inert tap and never simply removed from the
// list (13 §4.3).
//
// Navigation is handed up through required callbacks (matching the
// `LedgerIndexScreen`/`HomeScreen` convention for real navigation, as
// opposed to `SettingsScreen`'s nullable-callback lifted-state pattern) —
// this screen owns no router or scope of its own.
//
// ⚠️ SPEC: 07 §3.1 step 6 places a verified-storage nag badge on Menu until
// the printed recovery sheet is scanned back, but no persisted flag for
// "has the sheet been verified" exists anywhere the shell can read yet
// (`features/onboarding`'s S0.5b keeps that state, if any, to itself) — so
// the badge is left off rather than invented (CLAUDE.md rule 11); see this
// lane's report.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../widgets/menu_row.dart';

/// S8 — the Menu hub, one of the four bottom-bar tabs.
class MenuScreen extends StatelessWidget {
  const MenuScreen({
    super.key,
    required this.onOpenReports,
    required this.onOpenBooks,
    required this.onOpenBackup,
    required this.onOpenDevices,
    required this.onOpenSettings,
  });

  /// Pushes S8.1 Reports list (built in this lane).
  final VoidCallback onOpenReports;

  /// Pushes S9 Books (features/books) — Menu → Books, the entry point
  /// 07 §5.7 🔒 gives S9.5 *Add a business*.
  final VoidCallback onOpenBooks;

  /// Pushes S11.4 Backup settings (features/devices).
  final VoidCallback onOpenBackup;

  /// Pushes S11 Devices & security (features/devices).
  final VoidCallback onOpenDevices;

  /// Pushes S13 Settings (features/settings).
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.menuTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MenuRow(
                title: l10n.menuReportsRowTitle,
                subtitle: l10n.menuReportsRowSubtitle,
                onTap: onOpenReports,
              ),
              MenuDisabledRow(
                title: l10n.menuCloseMonthRowTitle,
                reason: l10n.menuCloseMonthRowReason,
              ),
              MenuRow(
                title: l10n.menuBooksMembersRowTitle,
                subtitle: l10n.menuBooksMembersRowSubtitle,
                onTap: onOpenBooks,
              ),
              MenuRow(
                title: l10n.menuBackupRowTitle,
                subtitle: l10n.menuBackupRowSubtitle,
                onTap: onOpenBackup,
              ),
              MenuRow(
                title: l10n.menuDevicesRowTitle,
                subtitle: l10n.menuDevicesRowSubtitle,
                onTap: onOpenDevices,
              ),
              MenuDisabledRow(
                title: l10n.menuSubscriptionRowTitle,
                reason: l10n.menuSubscriptionRowReason,
              ),
              MenuRow(
                title: l10n.menuSettingsRowTitle,
                subtitle: l10n.menuSettingsRowSubtitle,
                onTap: onOpenSettings,
              ),
              MenuDisabledRow(
                title: l10n.menuHelpRowTitle,
                reason: l10n.menuHelpRowReason,
              ),
              MenuDisabledRow(
                title: l10n.menuLegalRowTitle,
                reason: l10n.menuLegalRowReason,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
