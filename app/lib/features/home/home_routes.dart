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
// The Close card reads [CloseScope], which `bootstrap.dart` installs above the
// router; with no scope (a preview, a test) no card is drawn and Home is
// otherwise unchanged.
//
// S1.4's producer is `Recompute.watchProgress` (packages/data, E-03-29),
// adapted by [rebuildProgressOf] — null when no ledger is in scope, so a
// preview or a test pumped without data still shows the book. The shipped app
// mounts [homeTabRootWith] with the shell's scope controller; it and
// [homeRoot] build through one function, [homeScreenFor], so there is one
// wiring, not two. S1.1 resolves the one book a solo
// ledger has ([soloBookId]) until it takes scope too.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../shared/router.dart';
import '../ledger/ledger_paths.dart';
import '../reports/reports_paths.dart';
import 'home_paths.dart';
import 'home_rebuild.dart';
import 'home_scope.dart';
import 'screens/s1_1_position_drilldown_screen.dart';
import 'screens/s1_home_screen.dart';

export 'home_paths.dart';

/// S1 Home, wired — the one place S1's doors are spelled. A position row
/// pushes S1.1 on the root navigator; a verb button pushes the S2 entry flow
/// with the verb pre-chosen (07 §4, 07 §5).
///
/// Both tab roots below build through this, so the production root
/// ([homeTabRootWith], which the shell gives its scope holder) and the
/// preview/test root ([homeRoot]) cannot drift apart: a door added here is a
/// door in the shipped app.
Widget homeScreenFor(
  BuildContext context, {
  HomeScopeController? scopeController,
}) => HomeScreen(
  scopeController: scopeController,
  // S1.4's producer (07 §28 🔒).
  rebuildProgress: rebuildProgressOf(context),
  onOpenPosition: (line) => context.push(HomePaths.positionOf(line)),
  onOpenAccount: (accountId) =>
      context.push(LedgerPaths.statementOf(accountId)),
  // S21 Search (07 §25 🔒; 13 §3.2: reached from S3 and S1) — the route the
  // ledger feature owns, over the book S1 has in scope.
  onOpenSearch: (bookId) => context.push(LedgerPaths.searchIn(bookId)),
  onVerb: (kind) => context.push('${RkPaths.entry}?verb=${kind.wire}'),
  // 07 §10 🔒 names the destination ("the Family Reconciliation screen
  // (Menu → Reports)") — the path constant is read from the feature that
  // owns S8.3, never re-spelled here.
  onOpenReconciliation: () => context.push(ReportsPaths.reconciliationLocation),
  // The Home *Close card* (07 §13 🔒 bullet 1). The path is S10's or
  // S10.2's, built by the card from `ClosePaths` — the feature that owns
  // the route spells it, never this file. The push is awaited so the card
  // re-reads its state when the closer comes back.
  onOpenClose: (path) async {
    await context.push<void>(path);
  },
);

/// S1 as the shipped app mounts it: [homeScreenFor] with the shell's scope
/// holder, so scope outlives the screen (13 §2.2). `bootstrap.dart` passes
/// this as `homeTabRoot`.
RkTabRoot homeTabRootWith(HomeScopeController scopeController) => RkTabRoot(
  builder: (context) =>
      homeScreenFor(context, scopeController: scopeController),
);

/// S1 with a scope holder of its own lifetime — for tests and previews; the
/// same wiring as [homeTabRootWith].
final RkTabRoot homeRoot = RkTabRoot(
  builder: (context) => homeScreenFor(context),
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
