// Advances feature routes (features/README "Routes", 13 §3.1/§3.2). S5 is not
// a bottom-bar root: 13 §3.2 reaches it from S1 (the Home advances position
// row) and from S6, so it pushes on the **root** navigator and covers the tab
// bar, exactly as the entry flow does.
//
// S5.1 (the advance request) is deliberately absent — another lane builds it,
// and declaring an empty route for it would put a door on the screen that
// leads nowhere (07 §1 rule 6). `AdvancesPaths.request` reserves the path.
import 'package:go_router/go_router.dart';

import 'advances_paths.dart';
import 'screens/s5_advances_screen.dart';

export 'advances_paths.dart';

/// Root-navigator routes this feature owns: S5 Advances.
final List<RouteBase> advancesRoutes = [
  GoRoute(
    path: AdvancesPaths.index,
    builder: (context, state) => const AdvancesScreen(),
  ),
];
