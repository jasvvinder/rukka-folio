// Home feature routes (features/README "Routes", 13 §3.1/§3.2). Home (S1) is a
// bottom-bar root — `homeRoot` is the [RkTabRoot] the app passes to
// `buildRouter(home: homeRoot, ...)`. S1.1 sits one level below it and mounts
// on the *root* navigator so it covers the tab bar, as S4 does.
//
// S1.2/S1.3 (the scope switcher) now live inside [HomeScreen]: it owns a
// [HomeScopeController] for its own lifetime, so the chip appears by itself
// the moment a second book exists (13 §2.2 🔒) and nothing is routed. The
// shell will pass a controller in when scope persists per tab.
//
// S1.4's producer is `Recompute.watchProgress` (packages/data, E-03-29),
// adapted by [rebuildProgressOf] — null when no ledger is in scope, so a
// preview or a test pumped without data still shows the book. `main()` builds
// the same screen with the shell's scope controller and must pass the same
// source; the two wirings change together. S1.1 resolves the one book a solo
// ledger has ([soloBookId]) until it takes scope too.
import 'package:go_router/go_router.dart';

import '../../shared/router.dart';
import '../ledger/ledger_paths.dart';
import 'home_paths.dart';
import 'home_rebuild.dart';
import 'screens/s1_1_position_drilldown_screen.dart';
import 'screens/s1_home_screen.dart';

export 'home_paths.dart';

/// S1 Home — the Home tab's root screen. A position row pushes S1.1 on the
/// root navigator; a verb button pushes the S2 entry flow with the verb
/// pre-chosen (07 §4, 07 §5).
final RkTabRoot homeRoot = RkTabRoot(
  builder: (context) => HomeScreen(
    rebuildProgress: rebuildProgressOf(context),
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
