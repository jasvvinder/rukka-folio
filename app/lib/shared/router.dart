// Navigation (13 §3.1 🔒): four tabs — Home /home · Ledger /ledger · Inbox
// /inbox · Menu /menu — in a stateful shell, plus the centre ( + ) which
// pushes /entry over the shell as an action (not a tab). No hamburger, no
// nested tabs, nothing deeper than two levels from a root.
//
// Feature contract: `app/lib/features/<feature>/<feature>_routes.dart` exports
// `final List<RouteBase> <feature>Routes`; the app composes them with
// [buildRouter]. A feature that owns a tab root passes an [RkTabRoot] for it.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/gen/app_localizations.dart';
import 'widgets/placeholder_screen.dart';
import 'widgets/rk_tab_bar.dart';

export 'package:go_router/go_router.dart' show GoRouter, GoRoute, RouteBase;

export 'widgets/rk_tab_bar.dart' show RkTab;

/// Path constants — the only place the strings live.
abstract final class RkPaths {
  static const home = '/home';
  static const ledger = '/ledger';
  static const entry = '/entry';
  static const inbox = '/inbox';
  static const menu = '/menu';

  // Root-navigator screens owned by features (features/README "Routes").
  /// S0.2 Phone + OTP (features/auth).
  static const authPhone = '/auth/phone';

  /// S19.1 Update required — 426 (06 §4.5); global, no dismiss.
  static const updateRequired = '/update-required';

  /// S11 Devices & security (features/devices); reached from Menu (07 §15).
  static const devices = '/devices';

  /// S11.4 Backup settings.
  static const devicesBackup = '/devices/backup';

  /// S11.9 / S11.10 cancel window; `:id` is the window id.
  static const devicesWindow = '/devices/window/:id';

  /// S15.4 Device suspended (global).
  static const suspended = '/suspended';

  /// S19.5 This phone has been modified (global, once per app version).
  static const modifiedDevice = '/modified-device';

  /// Path of a tab's root.
  static String of(RkTab tab) => switch (tab) {
    RkTab.home => home,
    RkTab.ledger => ledger,
    RkTab.inbox => inbox,
    RkTab.menu => menu,
  };
}

/// A tab's root screen and the routes nested beneath it (rendered inside the
/// shell, tab bar visible). Routes here are relative to the root path.
class RkTabRoot {
  const RkTabRoot({required this.builder, this.routes = const []});

  final WidgetBuilder builder;
  final List<RouteBase> routes;
}

/// Composes the shell with tab roots and feature routes.
///
/// [featureRoutes] mount on the root navigator — they cover the tab bar, as
/// entry (S2) and detail screens do. Pass tab-nested routes through the
/// matching [RkTabRoot.routes] instead.
GoRouter buildRouter({
  required List<RouteBase> featureRoutes,
  RkTabRoot? home,
  RkTabRoot? ledger,
  RkTabRoot? inbox,
  RkTabRoot? menu,
  WidgetBuilder? entry,
  String initialLocation = RkPaths.home,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final rootKey = navigatorKey ?? GlobalKey<NavigatorState>(debugLabel: 'root');
  StatefulShellBranch branch(RkTab tab, RkTabRoot? root) {
    final r = root ?? RkTabRoot(builder: (c) => _placeholder(c, tab));
    return StatefulShellBranch(
      routes: [
        GoRoute(
          path: RkPaths.of(tab),
          builder: (context, _) => r.builder(context),
          routes: r.routes,
        ),
      ],
    );
  }

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => RkShell(shell: shell),
        branches: [
          branch(RkTab.home, home),
          branch(RkTab.ledger, ledger),
          branch(RkTab.inbox, inbox),
          branch(RkTab.menu, menu),
        ],
      ),
      GoRoute(
        path: RkPaths.entry,
        parentNavigatorKey: rootKey,
        builder: (context, _) =>
            entry?.call(context) ?? _entryPlaceholder(context),
      ),
      ...featureRoutes,
    ],
  );
}

/// The shell: branch content above the one tab bar.
class RkShell extends StatelessWidget {
  const RkShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: RkTabBar(
        selected: RkTab.values[shell.currentIndex],
        labels: {
          RkTab.home: l10n.navHomeLabel,
          RkTab.ledger: l10n.navLedgerLabel,
          RkTab.inbox: l10n.navInboxLabel,
          RkTab.menu: l10n.navMenuLabel,
        },
        actionLabel: l10n.navEntryLabel,
        onSelect: (tab) => shell.goBranch(
          tab.index,
          // Re-tapping the active tab returns to its root (13 §3.1).
          initialLocation: tab.index == shell.currentIndex,
        ),
        onAction: () => context.push(RkPaths.entry),
      ),
    );
  }
}

Widget _placeholder(BuildContext context, RkTab tab) {
  final l10n = AppLocalizations.of(context);
  return switch (tab) {
    RkTab.home => RkPlaceholderScreen(
      title: l10n.appName,
      body: l10n.homePlaceholderBody,
    ),
    RkTab.ledger => RkPlaceholderScreen(
      title: l10n.navLedgerLabel,
      body: l10n.ledgerPlaceholderBody,
    ),
    RkTab.inbox => RkPlaceholderScreen(
      title: l10n.navInboxLabel,
      body: l10n.inboxPlaceholderBody,
    ),
    RkTab.menu => RkPlaceholderScreen(
      title: l10n.navMenuLabel,
      body: l10n.menuPlaceholderBody,
    ),
  };
}

Widget _entryPlaceholder(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return RkPlaceholderScreen(
    title: l10n.navEntryLabel,
    body: l10n.entryPlaceholderBody,
  );
}
