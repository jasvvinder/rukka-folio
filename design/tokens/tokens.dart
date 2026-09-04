// Rukka Folio tokens — generated view of design/tokens/tokens.json (v0.1.0; brand 11 v1.4).
// Hand-synced until scripts/gen_tokens exists (M0). Lives in app/ (UI layer);
// never imported by core packages. Do not add values not present in tokens.json.

import 'package:flutter/material.dart';

/// Colors. Light and dark are full sets — the app never derives one from the other.
abstract final class RkColorsLight {
  static const bg = Color(0xFFF5F0E4);
  static const surface = Color(0xFFFBF8F0);
  static const sunk = Color(0xFFEFE9DA); // PROPOSED — recessed wells
  static const text = Color(0xFF1A1A18);
  static const textMuted = Color(0xFF6E6A5E);
  static const hairline = Color(0xFFE3DCCB);
  static const primary = Color(0xFF2B3A67); // never a value judgement
  static const onPrimary = Color(0xFFF5F0E4);
  static const accent = Color(0xFFC1502E); // bahi red — one accent per screen
  static const credit = Color(0xFF2F7A55); // numerals only, always with '+'
  static const debit = Color(0xFFA83232); // numerals only, always with '−'
  static const loaderTrack = Color(0x241A1A18); // rgba(26,26,24,.14) — the loader is a rule (11 §4.5)
  static const loaderSegment = Color(0xFF1A1A18); // ink, never primary/accent
  static const skeletonLabel = Color(0x171A1A18); // rgba .09
  static const skeletonAmount = Color(0x211A1A18); // rgba .13
  static const pending = Color(0xFF8F5F00); // PROPOSED — owner sign-off
  static const locked = Color(0xFF8A857A); // PROPOSED — owner sign-off
  static const dangerSurface = Color(0xFFF6E3DD);
  static const scrim = Color(0x6B1A1A18); // PROPOSED — rgba(26,26,24,0.42)
  static const focus = Color(0xFF2B3A67);
}

abstract final class RkColorsDark {
  static const bg = Color(0xFF1A1A18);
  static const surface = Color(0xFF24231F);
  static const sunk = Color(0xFF1F1E1B); // PROPOSED
  static const text = Color(0xFFF5F0E4);
  static const textMuted = Color(0xFFA5A093);
  static const hairline = Color(0xFF3A382F);
  static const primary = Color(0xFF93A5D6);
  static const onPrimary = Color(0xFF1A1A18);
  static const accent = Color(0xFFD9754F);
  static const credit = Color(0xFF57A87F);
  static const debit = Color(0xFFD4776F); // ⚠️ SPEC: motion page uses C96A6A (credit 4FA37A) — owner to pick
  static const loaderTrack = Color(0x29F5F0E4); // rgba(245,240,228,.16)
  static const loaderSegment = Color(0xFFF5F0E4);
  static const skeletonLabel = Color(0x17F5F0E4); // .09
  static const skeletonAmount = Color(0x24F5F0E4); // .14
  static const pending = Color(0xFFD9A93F); // PROPOSED
  static const locked = Color(0xFF7A756A); // PROPOSED
  static const dangerSurface = Color(0xFF3A2723);
  static const scrim = Color(0x73000000); // PROPOSED — rgba(0,0,0,0.45)
  static const focus = Color(0xFF93A5D6);
}

/// Type scale (logical px @ textScaleFactor 1.0; must survive 200%).
/// Family: Mukta (Latin+Devanagari) + Mukta Mahee (Gurmukhi), fallback Noto Sans.
abstract final class RkType {
  static const family = 'Mukta';
  static const familyGurmukhi = 'MuktaMahee';
  static const familyFallback = 'NotoSans';

  static const display = TextStyle(fontSize: 40, fontWeight: FontWeight.w600, height: 1.2);
  static const page = TextStyle(fontSize: 28, fontWeight: FontWeight.w600, height: 1.2);
  static const section = TextStyle(fontSize: 20, fontWeight: FontWeight.w500, height: 1.2);
  static const body = TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5);
  static const tableRow = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.5);

  /// Amounts: ALWAYS tabular figures (brand §4.4).
  static const _tabular = [FontFeature.tabularFigures()];
  static const amountHero =
      TextStyle(fontSize: 44, fontWeight: FontWeight.w600, fontFeatures: _tabular);
  static const amountRow =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w500, fontFeatures: _tabular);
}

/// 4pt spatial grid.
abstract final class RkSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0;
  static const s5 = 20.0, s6 = 24.0, s8 = 32.0, s10 = 40.0, s12 = 48.0;
  static const gutter = 16.0;
  static const rowMinHeight = 56.0;
}

abstract final class RkRadius {
  static const sm = 4.0, md = 8.0, lg = 12.0;
  static const ruleLeftWidth = 3.0; // 3px left rule; never rounded on that side
}

abstract final class RkMotion {
  static const easeBrand = Cubic(0.45, 0, 0.25, 1);
  static const easeEntries = Cubic(0.35, 0, 0.2, 1);
  static const xs = Duration(milliseconds: 120);
  static const s = Duration(milliseconds: 200);
  static const m = Duration(milliseconds: 300);
  static const l = Duration(milliseconds: 400);

  /// Sealed→open mark (brand §4.2): total ≈ 860ms × multiplier.
  /// Splash = 1.0; biometric unlock = 0.6. Plays ONLY on a real unlock.
  static const markSplashMultiplier = 1.0; // only when the session is already open
  static const markBiometricMultiplier = 0.6;

  /// Failed unlock: mark stays sealed, horizontal shake ±2 units × 3 (11 §4.5).
  static const failShake = Duration(milliseconds: 240);
  static const failShakeAmplitudeUnits = 2.0;
  static const failShakeCycles = 3;

  /// The loader is a RULE (11 §4.5): LinearProgressIndicator(minHeight: loaderTrackHeight,
  /// backgroundColor: loaderTrack, color: loaderSegment). Never a spinner; never the mark.
  static const loaderTrackHeight = 2.0;
  static const loaderSegmentFraction = 0.3;
  static const loaderSweep = Duration(milliseconds: 1200); // easeEntries, continuous
  static const loaderAppearDelay = Duration(milliseconds: 200);
  static const loaderEscalate = Duration(seconds: 8); // then one plain status line

  /// Skeletons are static (no shimmer), true row pitch, label width 38–58 %.
  static const skeletonLabelWidthMin = 0.38;
  static const skeletonLabelWidthMax = 0.58;

  /// Splash: past this, the loader rule fades in under the stacked lockup.
  static const splashSlowStart = Duration(seconds: 3);
}
