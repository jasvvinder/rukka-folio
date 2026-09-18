// Close feature routes (features/README "Routes"). One screen, S10, on the
// **root** navigator: it is opened from the Home close card and from the
// family close status, and in both cases it covers the tab bar until the
// closer leaves it.
//
// The doors are other lanes' screens — this feature publishes the destination
// and the path constant they link to. `features/home` owns the *Close card*
// (07 §13 bullet 1, `Close August ▸ 4 steps`); it should link
// `ClosePaths.forBook(bookId, period.toString())`.
//
// S10.1 (family close status) and S10.2 (month summary card) landed with this
// feature: S10.1 draws inside the wizard's last step and has no path of its
// own, and S10.2 draws there too the moment the lock lands — plus, at
// [ClosePaths.summaryPattern], on its own, which is the door the Home close
// card gives way to once a book has closed (07 §13 🔒).
//
// S10.4 (year close) landed at M9 and takes [ClosePaths.yearPattern], also on
// the root navigator. It has two doors: the prompt on S10.2 the moment the
// financial year's last month locks (wired below, `onOpenYear`), and
// Menu → per book, which belongs to `features/menu` (S8) — another lane's
// folder — and should link `ClosePaths.forYear(bookId,
// ClosePaths.fyStartOf(fy))`.
//
// S10.3 (late arrivals tray) is **not** this slice; nothing here claims its
// path.
import 'package:go_router/go_router.dart';

import 'close_paths.dart';
import 'close_period.dart';
import 'screens/s10_2_month_summary_screen.dart';
import 'screens/s10_4_year_close_screen.dart';
import 'screens/s10_month_close_screen.dart';

export 'close_fake.dart';
export 'close_paths.dart';
export 'close_period.dart';
export 'close_source.dart';
export 'screens/s10_2_month_summary_screen.dart';
export 'screens/s10_4_year_close_screen.dart';
export 'screens/s10_month_close_screen.dart';
export 'widgets/family_close_status.dart';
export 'widgets/month_summary_card.dart';
export 'widgets/year_close_prompt.dart';
export 'year_close_fake.dart';
export 'year_close_source.dart';

/// Root-navigator routes this feature owns: S10 the month-close wizard (with
/// S10.1/S10.2/S10.5 inside it), S10.2 on its own, and S10.4 the year close.
final List<RouteBase> closeRoutes = [
  GoRoute(
    path: ClosePaths.pattern,
    builder: (context, state) {
      final bookId = state.pathParameters[ClosePaths.bookParam]!;
      final period = parseClosePeriod(
        state.pathParameters[ClosePaths.periodParam],
      );
      if (period == null) {
        return CloseUnavailableScreen(onBack: () => GoRouter.of(context).pop());
      }
      return MonthCloseScreen(
        bookId: bookId,
        period: period,
        onOpenCount: (path) => GoRouter.of(context).push(path),
        onOpenYear: (path) => GoRouter.of(context).push(path),
        onDone: () => GoRouter.of(context).pop(),
      );
    },
  ),
  GoRoute(
    path: ClosePaths.summaryPattern,
    builder: (context, state) {
      final bookId = state.pathParameters[ClosePaths.bookParam]!;
      final period = parseClosePeriod(
        state.pathParameters[ClosePaths.periodParam],
      );
      if (period == null) {
        return CloseUnavailableScreen(onBack: () => GoRouter.of(context).pop());
      }
      return MonthSummaryScreen(
        bookId: bookId,
        period: period,
        onDone: () => GoRouter.of(context).pop(),
      );
    },
  ),
  GoRoute(
    path: ClosePaths.yearPattern,
    builder: (context, state) {
      final bookId = state.pathParameters[ClosePaths.bookParam]!;
      // Guesses nothing: a malformed `:fyStart` is a way back, never the
      // current financial year, because certifying the wrong year is the one
      // mistake 02 §8.1 🔒 makes permanent.
      final fy = parseFinancialYear(state.pathParameters[ClosePaths.yearParam]);
      if (fy == null) {
        return YearCloseUnavailableScreen(
          onBack: () => GoRouter.of(context).pop(),
        );
      }
      return YearCloseScreen(
        bookId: bookId,
        financialYear: fy,
        onOpen: (path) => GoRouter.of(context).push(path),
        onDone: () => GoRouter.of(context).pop(),
      );
    },
  ),
];
