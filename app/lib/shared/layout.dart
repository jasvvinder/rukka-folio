// Form factor (ADR 2026-09-13b §2 🔒, ratified 14 Sep 2026; amends 13 §3.1).
//
// One set of screens on two form factors. Everything here is applied *by the
// shell*: a screen that reads a breakpoint directly is a defect. The two
// widgets a screen may legitimately touch are [RkWideSurface] — the opt-out a
// professional surface takes — and nothing else.
//
// Values mirror `design/tokens/tokens.json` → `layout.*`; `RkLayout` is not
// emitted by `scripts/gen_tokens.dart` (that generator has no `layout`
// section), so `F1-13-17` reads tokens.json and fails on any drift between
// this file and the token source.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Material 3's canonical window classes, which Flutter aligns to.
///
/// Portrait iPads measure roughly 744–834pt and are therefore [medium];
/// landscape iPads are [expanded].
enum RkBreakpoint {
  /// < 600 — phones, and a split-screen tablet pane.
  compact,

  /// 600–839 — portrait tablets, large foldables.
  medium,

  /// ≥ 840 — landscape tablets. The shell shows a rail here and nowhere else.
  expanded,
}

/// The layout base: breakpoints, the readable measure, the rail threshold.
abstract final class RkLayout {
  /// Lower bound of [RkBreakpoint.medium], logical px.
  static const mediumMin = 600.0;

  /// Lower bound of [RkBreakpoint.expanded], logical px.
  static const expandedMin = 840.0;

  /// Max width of a **reading or form** surface, gutters included; wider
  /// viewports centre it on `bg`.
  ///
  /// ⚠️ SPEC: proposed, not ruled — ADR 2026-09-13b left this as its Open
  /// item and it wants the owner's eye. 600 − 32 (the two 16px gutters) is
  /// 568px of text, ≈ 75 characters at body 16 Mukta — the top of the 45–75
  /// readable measure and inside WCAG 1.4.8's 80. It is set equal to
  /// [mediumMin] so the cap provably never engages on a phone: below 600
  /// there is nothing to cap.
  ///
  /// Professional surfaces are **not** capped — see [RkWideSurface].
  static const readableMeasure = 600.0;

  /// Rail width at 1.0 text scale — clears the 44pt target
  /// (design-system §3.1 rule 9) with room for a label under a 21px glyph.
  static const railMinWidth = 88.0;

  /// The class [width] (logical px) falls in.
  static RkBreakpoint forWidth(double width) => width >= expandedMin
      ? RkBreakpoint.expanded
      : width >= mediumMin
      ? RkBreakpoint.medium
      : RkBreakpoint.compact;

  /// The window's class. Shell-only — see the file header.
  static RkBreakpoint of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  /// Whether the shell shows a [NavigationRail] rather than the tab bar.
  static bool railAt(RkBreakpoint b) => b == RkBreakpoint.expanded;
}

/// What the shell decided, published for the shared widgets that need it.
/// Screens do not read this.
class RkLayoutScope extends InheritedWidget {
  /// Wraps [child] with the resolved layout.
  const RkLayoutScope({
    super.key,
    required this.breakpoint,
    required this.contentWidth,
    required this.paneWidth,
    required super.child,
  });

  /// The window's class.
  final RkBreakpoint breakpoint;

  /// Full width the shell gave the content region (window minus any rail).
  final double contentWidth;

  /// Width a capped surface actually gets — `min(contentWidth, measure)`.
  final double paneWidth;

  /// The nearest scope, or null when pumped without a shell (screen tests).
  static RkLayoutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RkLayoutScope>();

  @override
  bool updateShouldNotify(RkLayoutScope old) =>
      old.breakpoint != breakpoint ||
      old.contentWidth != contentWidth ||
      old.paneWidth != paneWidth;
}

/// Caps [child] to [RkLayout.readableMeasure] and centres it, and publishes
/// the [RkLayoutScope] beneath. The shell's content region — no screen builds
/// one of these.
///
/// The child is given a **tight** width and the pane's full height, so a
/// `ListView` below it has a real viewport to build rows into. (The defect
/// this foundation replaces gave every tab 0px of height.)
class RkReadablePane extends StatelessWidget {
  /// Wraps the shell's branch content.
  const RkReadablePane({super.key, required this.child});

  /// The branch content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final breakpoint = RkLayout.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        final pane = math.min(full, RkLayout.readableMeasure);
        return RkLayoutScope(
          breakpoint: breakpoint,
          contentWidth: full,
          paneWidth: pane,
          child: Center(
            child: SizedBox(
              width: pane,
              height: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : null,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The professional-surface opt-out: takes the width the shell was given
/// instead of the readable cap.
///
/// `ਨਾਮੇ | ਜਮ੍ਹਾਂ | ਬਾਕੀ` is a real data table and design-system §3.1 rule 8
/// requires it to reflow wide; capping it would waste a tablet on exactly the
/// surface a bookkeeper bought one for (ADR 2026-09-13b §2). Wrap the A/C
/// statement, the trial balance and the reports in this — and nothing else.
/// Outside a shell it is a no-op, so a screen test pumping bare is unaffected.
class RkWideSurface extends StatelessWidget {
  /// Wraps a professional surface.
  const RkWideSurface({super.key, required this.child});

  /// The surface.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = RkLayoutScope.maybeOf(context);
    if (scope == null || scope.contentWidth <= scope.paneWidth) return child;
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: scope.contentWidth,
      maxWidth: scope.contentWidth,
      child: child,
    );
  }
}
