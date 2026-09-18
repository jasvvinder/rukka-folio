// Partners feature routes (13 §3.1/§3.2). S14 is not a bottom-bar root: 13
// §3.2 reaches it from S8.1, so it pushes on the **root** navigator and covers
// the tab bar, exactly as the entry and advances flows do.
//
// ADR 2026-09-09b 🔒: a *Just me* business never mentions partners, ratios or
// distribution anywhere in the app. The route therefore must not be linked
// from a Just-me book's S8.1 — that is the shell's wiring — and S14 itself
// refuses to speak partner vocabulary when the book it opens on turns out to
// be Just me (see [PartnerPositionsScreen]).
import 'package:go_router/go_router.dart';

import 'partners_paths.dart';
import 'screens/s14_1_distribute_screen.dart';
import 'screens/s14_partner_positions_screen.dart';

export 'partners_paths.dart';
export 'partners_port.dart';
export 'partners_scope.dart';

/// Root-navigator routes this feature owns: S14 Partner positions (with the
/// S14.2 drift & settlement card inside it).
final List<RouteBase> partnersRoutes = [
  GoRoute(
    path: PartnersPaths.pattern,
    builder: (context, state) =>
        PartnerPositionsScreen(bookId: state.pathParameters['bookId']!),
  ),
  // S14.1, reached from S14 (13 §3.2). A sibling route rather than a child:
  // the wizard covers S14 rather than nesting inside it, as the entry flow
  // covers Home.
  GoRoute(
    path: PartnersPaths.distributePattern,
    builder: (context, state) =>
        DistributeProfitScreen(bookId: state.pathParameters['bookId']!),
  ),
];
