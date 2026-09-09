// Ledger feature routes (features/README "Routes", 13 §3.1/§3.2). The Ledger
// tab (S3) is a bottom-bar root — `ledgerRoot` is the [RkTabRoot] main.dart
// passes to `buildRouter(ledger: ledgerRoot, ...)`. S4/S4.1/S21 sit one level
// below the root (ledger_paths.dart depth-rule note) so they mount on the
// *root* navigator, covering the tab bar, exactly as entry (S2) does — hence
// `ledgerRoutes` rather than `ledgerRoot.routes`. S3.1 quick-add is a sheet
// (`showModalBottomSheet`, wired from S3 itself), never a route.
import 'package:go_router/go_router.dart';

import '../../shared/router.dart';
import 'ledger_paths.dart';
import 'screens/s3_ledger_index_screen.dart';
import 'screens/s4_account_statement_screen.dart';

export 'ledger_paths.dart';

/// S3 ledger index — the Ledger tab's root screen. Row tap pushes
/// [LedgerPaths.statementOf] on the root navigator (covers the tab bar);
/// the FAB opens the S3.1 sheet in place, no navigation involved.
final RkTabRoot ledgerRoot = RkTabRoot(
  builder: (context) => LedgerIndexScreen(
    onOpenAccount: (accountId) =>
        context.push(LedgerPaths.statementOf(accountId)),
  ),
);

/// Root-navigator routes this feature owns beyond its tab root: S4 A/C
/// statement today; S4.1 entry detail and S21 search follow in later lanes
/// (ledger_paths.dart already reserves their paths).
final List<RouteBase> ledgerRoutes = [
  GoRoute(
    path: LedgerPaths.statement,
    builder: (context, state) =>
        AccountStatementScreen(accountId: state.pathParameters['id']!),
  ),
];
