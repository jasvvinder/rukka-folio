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
// S10.1 (family close status), S10.2 (month summary card), S10.3 (late
// arrivals tray) and S10.4 (year close) are **not** this slice; nothing here
// claims their paths.
import 'package:go_router/go_router.dart';

import 'close_paths.dart';
import 'close_period.dart';
import 'screens/s10_month_close_screen.dart';

export 'close_fake.dart';
export 'close_paths.dart';
export 'close_period.dart';
export 'close_source.dart';
export 'screens/s10_month_close_screen.dart';

/// Root-navigator routes this feature owns: S10 the month-close wizard, with
/// S10.5 inside it.
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
      );
    },
  ),
];
