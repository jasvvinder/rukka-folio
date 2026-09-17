// Cash count feature routes (features/README "Routes"). One screen, S5.5, on
// the **root** navigator: it is opened from a statement row, from the month
// close wizard and from the account screen, and in each case it covers the
// tab bar until the count is saved or abandoned.
//
// The doors themselves are other lanes' screens — this feature only publishes
// the destination and the path constant they link to.
import 'package:go_router/go_router.dart';

import 'cash_count_paths.dart';
import 'screens/s5_5_cash_count_screen.dart';

export 'cash_count_paths.dart';
export 'cash_count_source.dart';
export 'screens/s5_5_cash_count_screen.dart';

/// Root-navigator routes this feature owns: S5.5 the cash count sheet.
final List<RouteBase> cashCountRoutes = [
  GoRoute(
    path: CashCountPaths.pattern,
    builder: (context, state) => CashCountScreen(
      accountId: state.pathParameters[CashCountPaths.accountParam]!,
    ),
  ),
];
