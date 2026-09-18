// S8 Menu (13 §3.2 row S8, 07 §2 🔒 bottom bar). Row order is normative — do
// not reorder without a doc change: Reports · Close the month (ADR
// 2026-09-03) · Year close, per book (07 §13 last bullet 🔒) · Books & members ·
// Backup · Devices & security · Subscription · Settings · Help · Legal
// (owner-added 3 Sep 2026).
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
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../close_month_books.dart';
import '../widgets/menu_row.dart';
import '../year_close_books.dart';

/// S8 — the Menu hub, one of the four bottom-bar tabs.
class MenuScreen extends StatelessWidget {
  const MenuScreen({
    super.key,
    required this.onOpenReports,
    required this.onOpenBooks,
    required this.onOpenBackup,
    required this.onOpenDevices,
    required this.onOpenSettings,
    this.yearCloseBooks = const [],
    this.onOpenYearClose,
    this.closeMonth = const MenuCloseMonthLoad(MenuCloseMonthState.loading),
    this.onOpenCloseMonth,
    this.onRetryCloseMonth,
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

  /// One row per book with a financial year waiting to be certified — the
  /// *Menu → per book* door to S10.4 (07 §13 last bullet 🔒). Empty is an
  /// ordinary state: nothing has ended yet, or every ended year is certified.
  final List<MenuYearCloseBook> yearCloseBooks;

  /// Pushes S10.4 for one book's year. Null keeps the rows drawn but inert —
  /// which is how a shell that has not wired the ceremony yet still says the
  /// door exists rather than hiding it (07 §1 rule 6).
  final void Function(MenuYearCloseBook book)? onOpenYearClose;

  /// Where the month close stands, per book — the live subtitle ADR
  /// 2026-09-03 ruling 1 🔒 asks for. The default is the loading state: a row
  /// drawn before the read has answered says it is checking, never *not built
  /// yet* (07 §1 rule 6).
  final MenuCloseMonthLoad closeMonth;

  /// Pushes S10 for one book's first open month. Null keeps the rows drawn but
  /// inert, the way a shell that has not wired the wizard still says the door
  /// exists.
  final void Function(MenuCloseMonthBook book)? onOpenCloseMonth;

  /// Reads the close again after a failed read. Null leaves the error row
  /// stated but untappable.
  final VoidCallback? onRetryCloseMonth;

  /// The *Close the month* rows for [closeMonth]'s state (13 §4.3): one per
  /// book when something is closable, and a single stated row otherwise.
  List<Widget> _closeMonthRows(AppLocalizations l10n) {
    String monthOf(YearMonth m) => '${monthName(l10n, m.month)} ${m.year}';

    switch (closeMonth.state) {
      case MenuCloseMonthState.loading:
        return [
          MenuDisabledRow(
            title: l10n.menuCloseMonthRowTitle,
            reason: l10n.menuCloseMonthRowLoading,
          ),
        ];
      case MenuCloseMonthState.nothing:
        return [
          MenuDisabledRow(
            title: l10n.menuCloseMonthRowTitle,
            reason: l10n.menuCloseMonthRowReasonNone,
          ),
        ];
      case MenuCloseMonthState.closed:
        final upTo = closeMonth.upTo;
        return [
          MenuDisabledRow(
            title: l10n.menuCloseMonthRowTitle,
            reason: upTo == null
                ? l10n.menuCloseMonthRowReasonNone
                : l10n.menuCloseMonthRowReasonClosed(monthOf(upTo)),
          ),
        ];
      case MenuCloseMonthState.failed:
        // Tappable, because an error the user cannot act on is a dead end.
        return [
          MenuRow(
            title: l10n.menuCloseMonthRowTitle,
            subtitle: l10n.menuCloseMonthRowError,
            onTap: onRetryCloseMonth,
          ),
        ];
      case MenuCloseMonthState.ready:
        final many = closeMonth.books.length > 1;
        return [
          for (final book in closeMonth.books)
            MenuRow(
              title: l10n.menuCloseMonthRowTitle,
              subtitle: many
                  ? l10n.menuCloseMonthRowSubtitleBook(
                      book.bookName,
                      monthOf(book.period),
                      book.waiting,
                    )
                  : l10n.menuCloseMonthRowSubtitle(
                      monthOf(book.period),
                      book.waiting,
                    ),
              onTap: onOpenCloseMonth == null
                  ? null
                  : () => onOpenCloseMonth!(book),
            ),
        ];
    }
  }

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
              // *Close the month*, live, directly after Reports (ADR
              // 2026-09-03 ruling 1 🔒) — one row per book with a month to
              // close, otherwise one row saying why it cannot be entered.
              ..._closeMonthRows(l10n),
              // *Year close*, per book, directly under the month close — the
              // order ADR 2026-09-03 ruling 1 puts *The books* group in, with
              // the year the ceremony can actually take (02 §8.1 🔒: years
              // close in order). With nothing to certify the row stays,
              // disabled with its reason, rather than disappearing.
              if (yearCloseBooks.isEmpty)
                MenuDisabledRow(
                  title: l10n.menuYearCloseRowTitle,
                  reason: l10n.menuYearCloseRowReason,
                )
              else
                for (final book in yearCloseBooks)
                  MenuRow(
                    title: l10n.menuYearCloseRowTitle,
                    subtitle: yearCloseBooks.length == 1
                        ? l10n.menuYearCloseRowSubtitle(book.year.label)
                        : l10n.menuYearCloseRowSubtitleBook(
                            book.bookName,
                            book.year.label,
                          ),
                    onTap: onOpenYearClose == null
                        ? null
                        : () => onOpenYearClose!(book),
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
