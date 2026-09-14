// The rail (ADR 2026-09-13b §2 🔒, ratified 14 Sep 2026; amends 13 §3.1).
//
// At `expanded` — landscape tablets, ≥ 840pt — the shell presents this
// instead of RkTabBar. Same four destinations in the same order, the same
// canonical glyphs of design-system §4.1, the same labels from the same ARB
// keys, the same docked ( + ) that is an action and not a tab. It is a
// presentation switch, not a second information architecture: nothing here
// may be a destination the bar does not have, or vice versa.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout.dart';
import '../theme.dart';
import '../tokens.dart';
import 'rk_tab_bar.dart';

/// The expanded-width navigation. Labels arrive from the caller, exactly as
/// [RkTabBar] takes them, so the two can never drift apart.
class RkNavRail extends StatelessWidget {
  /// Creates the rail.
  const RkNavRail({
    super.key,
    required this.selected,
    required this.labels,
    required this.actionLabel,
    required this.onSelect,
    required this.onAction,
  });

  /// The active tab.
  final RkTab selected;

  /// Visible label per tab (all four required) — the tab bar's map.
  final Map<RkTab, String> labels;

  /// Semantics-only label for the ( + ) action.
  final String actionLabel;

  /// Called with the chosen tab.
  final ValueChanged<RkTab> onSelect;

  /// Called when ( + ) is pressed.
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    // The rail widens with the user's font scale, or a 200 % label would be
    // drawn into 88px. Measured off the label, which is the part that grows.
    final scale =
        MediaQuery.textScalerOf(context).scale(RkTabBarSpec.labelSize) /
        RkTabBarSpec.labelSize;
    final width = RkLayout.railMinWidth * math.min(scale, 2.0);

    TextStyle labelStyle({required bool active}) => TextStyle(
      fontSize: RkTabBarSpec.labelSize,
      height: RkType.lineHeightNormal,
      fontWeight: active
          ? RkTabBarSpec.activeWeight
          : RkTabBarSpec.inactiveWeight,
      color: active ? scheme.primary : status.muted,
    );

    Widget glyph(RkTab tab, {required bool active}) => RkGlyph(
      paths: RkGlyphs.of(tab),
      color: active ? scheme.primary : status.muted,
      strokeWidth: active
          ? RkTabBarSpec.activeStroke
          : RkTabBarSpec.inactiveStroke,
    );

    return NavigationRail(
      backgroundColor: scheme.surface,
      minWidth: width,
      selectedIndex: selected.index,
      onDestinationSelected: (i) => onSelect(RkTab.values[i]),
      labelType: NavigationRailLabelType.all,
      // The selected pill is a *shape*, so the active state survives
      // grayscale — 07 §1 rule 3, colour is never the only signal (the
      // heavier label and the thicker stroke carry it too).
      indicatorColor: status.sunk,
      selectedLabelTextStyle: labelStyle(active: true),
      unselectedLabelTextStyle: labelStyle(active: false),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
        child: RkCentreAction(label: actionLabel, onTap: onAction),
      ),
      destinations: [
        for (final tab in RkTab.values)
          NavigationRailDestination(
            icon: glyph(tab, active: false),
            selectedIcon: glyph(tab, active: true),
            label: Text(
              labels[tab] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
