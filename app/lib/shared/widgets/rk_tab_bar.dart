// The one tab bar (design-system §4.1 🔒; 13 §3.1): Home · Ledger · Inbox · Menu
// plus a docked centre ( + ) that is an action, not a tab — no active state,
// no label. Values here are the locked ones: min-height 50, icons 21×21 on a
// viewBox of 24, label 10.5px, active = primary / stroke 2 / weight 600,
// inactive = muted / stroke 1.8 / weight 400. Glyph paths are canonical and
// never redrawn per screen.
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import 'svg_path.dart';

/// The four destinations, in bar order. The centre action sits between
/// [ledger] and [inbox] and is deliberately not a member.
enum RkTab { home, ledger, inbox, menu }

/// Canonical glyph path data — design-system §4.1, copied verbatim.
abstract final class RkGlyphs {
  /// Open two-path house.
  static const home = ['M3 10.5 12 3l9 7.5', 'M5 9.5V21h14V9.5'];

  /// Bound book.
  static const ledger = [
    'M4 19.5A2.5 2.5 0 0 1 6.5 17H20',
    'M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z',
  ];

  /// Tray in box.
  static const inbox = [
    'M22 12h-6l-2 3h-4l-2-3H2',
    'M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z',
  ];

  /// Three lines.
  static const menu = ['M4 6h16', 'M4 12h16', 'M4 18h16'];

  /// The centre action's plus — not one of the four tabs; drawn in the same
  /// stroke language so the bar reads as one set.
  static const plus = ['M12 5v14', 'M5 12h14'];

  /// Glyph for a tab.
  static List<String> of(RkTab tab) => switch (tab) {
    RkTab.home => home,
    RkTab.ledger => ledger,
    RkTab.inbox => inbox,
    RkTab.menu => menu,
  };
}

/// Locked geometry of the bar (design-system §4.1).
abstract final class RkTabBarSpec {
  static const minHeight = 50.0;
  static const iconSize = 21.0;
  static const viewBox = 24.0;
  static const labelSize = 10.5;
  static const activeStroke = 2.0;
  static const inactiveStroke = 1.8;
  static const activeWeight = FontWeight.w600;
  static const inactiveWeight = FontWeight.w400;

  /// Minimum touch target (design-system §2, WCAG 2.5.8).
  static const minTouchTarget = 44.0;
}

/// The bottom bar. Labels arrive from the caller so this widget stays free of
/// the l10n class (features and tests can pass any strings).
class RkTabBar extends StatelessWidget {
  const RkTabBar({
    super.key,
    required this.selected,
    required this.labels,
    required this.actionLabel,
    required this.onSelect,
    required this.onAction,
  });

  /// The active tab.
  final RkTab selected;

  /// Visible label per tab (all four required).
  final Map<RkTab, String> labels;

  /// Semantics-only label for the centre action (it renders no text).
  final String actionLabel;

  /// Called with the tapped tab.
  final ValueChanged<RkTab> onSelect;

  /// Called when the centre ( + ) is pressed.
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    Widget tab(RkTab t) => Expanded(
      child: RkTabItem(
        tab: t,
        label: labels[t] ?? '',
        active: t == selected,
        onTap: () => onSelect(t),
      ),
    );
    return Material(
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: status.hairline, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: RkTabBarSpec.minHeight,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                tab(RkTab.home),
                tab(RkTab.ledger),
                Expanded(
                  child: RkCentreAction(label: actionLabel, onTap: onAction),
                ),
                tab(RkTab.inbox),
                tab(RkTab.menu),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the four tabs: glyph over a 10.5px label.
class RkTabItem extends StatelessWidget {
  const RkTabItem({
    super.key,
    required this.tab,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final RkTab tab;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final color = active ? scheme.primary : status.muted;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RkTabBarSpec.minHeight,
            minWidth: RkTabBarSpec.minTouchTarget,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: RkSpace.s1),
              RkGlyph(
                paths: RkGlyphs.of(tab),
                color: color,
                strokeWidth: active
                    ? RkTabBarSpec.activeStroke
                    : RkTabBarSpec.inactiveStroke,
              ),
              const SizedBox(height: RkSpace.s1 / 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: RkTabBarSpec.labelSize,
                  height: RkType.lineHeightNormal,
                  fontWeight: active
                      ? RkTabBarSpec.activeWeight
                      : RkTabBarSpec.inactiveWeight,
                  color: color,
                ),
              ),
              const SizedBox(height: RkSpace.s1),
            ],
          ),
        ),
      ),
    );
  }
}

/// The docked ( + ). An action: never selected, never labelled on screen.
class RkCentreAction extends StatelessWidget {
  const RkCentreAction({super.key, required this.label, required this.onTap});

  /// Spoken label only.
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Center(
        child: SizedBox.square(
          dimension: RkTabBarSpec.minTouchTarget,
          child: Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: RkGlyph(
                  paths: RkGlyphs.plus,
                  color: scheme.onPrimary,
                  strokeWidth: RkTabBarSpec.activeStroke,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 21×21 stroke glyph drawn from viewBox-24 path data.
class RkGlyph extends StatelessWidget {
  const RkGlyph({
    super.key,
    required this.paths,
    required this.color,
    required this.strokeWidth,
    this.size = RkTabBarSpec.iconSize,
  });

  final List<String> paths;
  final Color color;

  /// Stroke width in viewBox units (as the SVG spec applies it).
  final double strokeWidth;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: RkGlyphPainter(
        paths: paths,
        color: color,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

/// Paints stroke paths (round caps and joins — feather style) scaled from the
/// 24-unit viewBox to the widget's size.
class RkGlyphPainter extends CustomPainter {
  RkGlyphPainter({
    required this.paths,
    required this.color,
    required this.strokeWidth,
  });

  final List<String> paths;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / RkTabBarSpec.viewBox;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(scale);
    for (final d in paths) {
      canvas.drawPath(parseSvgPath(d), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RkGlyphPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.paths != paths;
}
