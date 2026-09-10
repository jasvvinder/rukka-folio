// Home feature routes (features/README "Routes", 13 §3.1/§3.2). Home (S1) is a
// bottom-bar root — `homeRoot` is the [RkTabRoot] the app passes to
// `buildRouter(home: homeRoot, ...)`. S1.1 sits one level below it and mounts
// on the *root* navigator so it covers the tab bar, as S4 does.
//
// S1.2/S1.3 (the scope switcher) and S1.4 (rebuilding) are later lanes; until
// S1.2 lands every screen here resolves the one book a solo ledger has
// ([soloBookId]), and the S1.4 slot on S1 stays empty.
import 'package:go_router/go_router.dart';

import '../../shared/router.dart';
import '../ledger/ledger_paths.dart';
import 'home_paths.dart';
import 'screens/s1_1_position_drilldown_screen.dart';
import 'screens/s1_home_screen.dart';

export 'home_paths.dart';

/// S1 Home — the Home tab's root screen. A position row pushes S1.1 on the
/// root navigator; a verb button pushes the S2 entry flow with the verb
/// pre-chosen (07 §4, 07 §5).
final RkTabRoot homeRoot = RkTabRoot(
  builder: (context) => HomeScreen(
    onOpenPosition: (line) => context.push(HomePaths.positionOf(line)),
    onOpenAccount: (accountId) =>
        context.push(LedgerPaths.statementOf(accountId)),
    onVerb: (kind) => context.push('${RkPaths.entry}?verb=${kind.wire}'),
  ),
);

/// Root-navigator routes this feature owns beyond its tab root.
final List<RouteBase> homeRoutes = [
  GoRoute(
    path: HomePaths.position,
    builder: (context, state) => PositionDrilldownScreen(
      line:
          PositionLine.parse(state.pathParameters['line']!) ??
          PositionLine.cash,
      accountId: state.uri.queryParameters['account'],
      onOpenAccount: (accountId) =>
          context.push(LedgerPaths.statementOf(accountId)),
    ),
  ),
];
