// Reports feature routes (features/README "Routes", 13 §3.2 depth rule).
// S8.1 nests *under* the Menu tab root rather than covering the tab bar
// (unlike S4/S1.1): `features/menu` imports [reportsRoutes] and passes it as
// the Menu [RkTabRoot]'s own `routes`, so the path resolves to
// `/menu/reports` with the tab bar still visible — Reports is a hub page
// inside Menu, not a detail viewer exempt from the depth rule.
import 'package:go_router/go_router.dart';

import '../partners/partners_paths.dart';
import 'reports_paths.dart';
import 'screens/s8_1_reports_list_route.dart';
import 'screens/s8_2_report_viewer_screen.dart';
import 'screens/s8_3_family_reconciliation_screen.dart';

export 'reports_paths.dart';

/// The routes `features/menu` mounts as the Menu tab root's own: S8.1, with
/// S8.2 and S8.3 nested under it (see [ReportsPaths.dayBook] for the ⚠️ SPEC
/// note on the 13 §3.2 depth rule).
final List<RouteBase> reportsRoutes = [
  GoRoute(
    path: ReportsPaths.root,
    // S8.1 through [ReportsListRoute]: the screen itself is a list of doors,
    // the wrapper reads the one fact that decides whether the S14 door exists
    // (07 §14 🔒, ADR 2026-09-09b 🔒). S14 is a **root-navigator** route
    // (features/partners mounts it), so this pushes an absolute location and
    // the sheet covers the tab bar.
    builder: (context, state) => ReportsListRoute(
      onOpenDayBook: () => context.push(ReportsPaths.dayBookLocation),
      onOpenReconciliation: () =>
          context.push(ReportsPaths.reconciliationLocation),
      onOpenPartnerPositions: (bookId) =>
          context.push(PartnersPaths.of(bookId)),
    ),
    routes: [
      GoRoute(
        path: ReportsPaths.dayBook,
        builder: (context, state) => const ReportViewerScreen(),
      ),
      GoRoute(
        path: ReportsPaths.reconciliation,
        builder: (context, state) => const FamilyReconciliationScreen(),
      ),
    ],
  ),
];
