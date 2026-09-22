// S8 Menu (13 §3.2 row S8, 07 §2 🔒 bottom bar). Row order is normative — do
// not reorder without a doc change: Reports · Close the month (ADR
// 2026-09-03) · Year close, per book (07 §13 last bullet 🔒) · Books & members ·
// Backup · Devices & security · Subscription · Settings · Help · Legal
// (owner-added 3 Sep 2026).
//
// Reports (S8.1), Books (S9 — `features/books`, whose list carries the S9.5
// *Add a business* entry point 07 §5.7 🔒 names this row as), Backup (S11.4),
// Devices & security (S11), Settings (S13) and Legal (S18 —
// `features/legal`) already have a real destination — S11.4/S11/S13/S18
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
    required this.onOpenSubscription,
    required this.onOpenSettings,
    required this.onOpenHelp,
    required this.onOpenLegal,
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

  /// Pushes S12 Subscription (features/subscription) — the sixth Menu row
  /// (07 §2 🔒 order, 07 §20). Live since M13; it was a
  /// disabled-with-reason row while S12 did not exist.
  final VoidCallback onOpenSubscription;

  /// Pushes S13 Settings (features/settings).
  final VoidCallback onOpenSettings;

  /// Pushes S17 Help (features/help) — the eighth Menu row under *This app*
  /// (07 §2 🔒, 07 §22).
  final VoidCallback onOpenHelp;

  /// Pushes S18 Legal & trust (features/legal) — the last Menu row under
  /// *This app* (07 §2 🔒, 07 §23).
  final VoidCallback onOpenLegal;

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
              // Subscription is live: `features/subscription` landed S12 and
              // S12.1 (22 Sep) and `subscriptionRoutes` is mounted, so the row
              // opens the hub instead of stating a reason that stopped being
              // true — the turn Help took on 21 Sep and Legal on 19 Sep.
              MenuRow(
                title: l10n.menuSubscriptionRowTitle,
                subtitle: l10n.menuSubscriptionRowSubtitle,
                onTap: onOpenSubscription,
              ),
              MenuRow(
                title: l10n.menuSettingsRowTitle,
                subtitle: l10n.menuSettingsRowSubtitle,
                onTap: onOpenSettings,
              ),
              // Help is live: `features/help` landed S17 and all three pages
              // (21 Sep) and `helpRoutes` is mounted, so the row opens the
              // hub instead of stating a reason that stopped being true —
              // the same turn Legal took on 19 Sep.
              MenuRow(
                title: l10n.menuHelpRowTitle,
                subtitle: l10n.menuHelpRowSubtitle,
                onTap: onOpenHelp,
              ),
              // ⚠️ SPEC — S16 HAS NO DOOR AT ALL. 13 §3.2 row S16 names S8 as
              // its parent, but 07 §2 🔒 enumerates the Menu rows and *My
              // account* is not among them — and `F1-07-14` pins that list,
              // Reports first, Legal last. Two normative sources, same level;
              // 07 owns screens, so the conservative reading (no row) is what
              // stands here, and `features/account` is routed but unreachable
              // until the owner rules. Adding the row is a 🔒 change to 07 §2,
              // not a lane's call.
              //
              // Legal is live: `features/legal` landed S18 and all four pages
              // (19 Sep) and `legalRoutes` is mounted, so the row opens the
              // hub instead of stating a reason that stopped being true.
              MenuRow(
                title: l10n.menuLegalRowTitle,
                subtitle: l10n.menuLegalRowSubtitle,
                onTap: onOpenLegal,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
