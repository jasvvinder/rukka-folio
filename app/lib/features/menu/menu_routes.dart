// Menu feature routes (features/README "Routes", 13 §3.1/§3.2). Menu (S8) is
// a bottom-bar root — `menuRoot` is the [RkTabRoot] the app passes to
// `buildRouter(menu: menuRoot, ...)` / `RukkaFolioApp(menuTabRoot: menuRoot)`
// (the orchestrator wires the latter; not done in this lane). S8.1 Reports
// nests *under* the root as `menuRoot.routes` (13 §3.2 depth rule) rather
// than covering the tab bar, per this lane's brief — `features/menu`
// composes the routes it imports from `features/reports`.
//
// Books (S9) is the same shape: `features/books` owns `booksRoutes` and the
// orchestrator mounts them on the root navigator; Menu only pushes the path,
// which is the entry point 07 §5.7 🔒 requires for S9.5.
//
// Devices & security (S11), Backup (S11.4), Settings (S13), Help (S17) and
// Legal & trust (S18) are root-navigator routes already wired into the app's `featureRoutes`
// (`devicesRoutes`/`settingsRoutes`/`helpRoutes`/`legalRoutes` in
// bootstrap.dart, built by
// earlier lanes) — Menu just pushes their absolute path, exactly as Home
// pushes `LedgerPaths.statementOf`.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../shared/app_scope.dart';
import '../../shared/ledger/ledger_scope.dart';
import '../../shared/router.dart';
import '../books/books_paths.dart';
import '../close/close_paths.dart';
import '../close/close_source.dart';
import '../devices/devices_paths.dart';
import '../help/help_paths.dart';
import '../legal/legal_paths.dart';
import '../reports/reports_routes.dart';
import '../settings/settings_paths.dart';
import '../subscription/subscription_paths.dart';
import 'close_month_books.dart';
import 'menu_paths.dart';
import 'screens/s8_menu_screen.dart';
import 'year_close_books.dart';

export 'close_month_books.dart';
export 'menu_paths.dart';
export 'year_close_books.dart';

/// S8 Menu — the Menu tab's root screen. Row taps push a nested route
/// (Reports) or an existing feature's root-navigator screen (Books, Backup,
/// Devices & security, Settings, Legal & trust).
final RkTabRoot menuRoot = RkTabRoot(
  builder: (context) => const MenuTab(),
  routes: reportsRoutes,
);

/// S8 with its one piece of live data: the *Year close* rows.
///
/// [MenuScreen] itself stays a `StatelessWidget` that owns no scope — this
/// wrapper is the only thing that reads one, which keeps the screen pumpable
/// from a widget test with a plain list. With no [LedgerScope] above it (a
/// screen pumped without data) the rows are simply empty, and S8 says so with
/// its disabled row rather than failing (07 §1 rule 6).
class MenuTab extends StatefulWidget {
  /// Creates the tab.
  const MenuTab({super.key});

  @override
  State<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<MenuTab> {
  List<MenuYearCloseBook> _years = const [];
  MenuCloseMonthLoad _close = const MenuCloseMonthLoad(
    MenuCloseMonthState.loading,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // An InheritedWidget may only be read from here on, never from initState.
    if (_started) return;
    _started = true;
    _load();
    _loadClose();
  }

  Future<void> _load() async {
    final ledger = LedgerScope.maybeOf(context);
    if (ledger == null) return;
    try {
      final years = await menuYearCloseBooks(ledger);
      if (mounted) setState(() => _years = years);
    } on Object {
      // A door that could not be worked out is a door not offered — never a
      // red screen on the Menu (07 §1 rule 6). The disabled row still states
      // the case.
    }
  }

  /// The live *Close the month* row (ADR 2026-09-03 ruling 1 🔒).
  ///
  /// Every scope is read **before** the first await — an InheritedWidget may
  /// not be reached for across an async gap.
  Future<void> _loadClose() async {
    final source = CloseScope.maybeOf(context);
    final now = RkScope.of(context).now();
    if (source == null) {
      // No close seam above the Menu: the row says the read failed and offers
      // another try, rather than claiming there is nothing to close.
      if (mounted) {
        setState(
          () => _close = const MenuCloseMonthLoad(MenuCloseMonthState.failed),
        );
      }
      return;
    }
    if (mounted) {
      setState(
        () => _close = const MenuCloseMonthLoad(MenuCloseMonthState.loading),
      );
    }
    // The month that has just **ended**, never the one in progress — the same
    // reading the Home close card takes (07 §13 🔒).
    final load = await menuCloseMonthLoad(source, endedMonthAt(now));
    if (mounted) setState(() => _close = load);
  }

  @override
  Widget build(BuildContext context) => MenuScreen(
    onOpenReports: () => context.push(MenuPaths.reports),
    onOpenBooks: () => context.push(BooksPaths.root),
    onOpenBackup: () => context.push(DevicesPaths.backup),
    onOpenDevices: () => context.push(DevicesPaths.devices),
    onOpenSubscription: () => context.push(SubscriptionPaths.root),
    onOpenSettings: () => context.push(SettingsPaths.root),
    onOpenHelp: () => context.push(HelpPaths.root),
    onOpenLegal: () => context.push(LegalPaths.root),
    yearCloseBooks: _years,
    closeMonth: _close,
    // S10 for the book's **first open** month — `closeStatuses` already
    // reports the earlier month when one is still open (02 §8.1 🔒).
    onOpenCloseMonth: (book) =>
        context.push(ClosePaths.forBook(book.bookId, book.period.toString())),
    onRetryCloseMonth: _loadClose,
    // Built with `ClosePaths.forYear` / `ClosePaths.fyStartOf`, never by hand:
    // the parameter is the financial year's **first month** as `YYYY-MM`,
    // because a book's FY need not start in April.
    onOpenYearClose: (book) => context.push(
      ClosePaths.forYear(book.bookId, ClosePaths.fyStartOf(book.year)),
    ),
  );
}
