// The app theme — built only from the generated tokens (design/tokens/tokens.json
// → shared/tokens.dart). Light and dark are full sets; nothing here derives one
// from the other (11 §4.3). Features read colours through the theme
// (ColorScheme + [RkStatusColors]) and never touch RkColorsLight/Dark directly.
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The fallback chain behind [RkType.family] (11 §4.4): Mukta Mahee for
/// Gurmukhi, then Noto Sans — the only fallback.
const rkFontFallback = [RkType.familyGurmukhi, RkType.familyFallback];

/// Builds the theme for [brightness]. 11 §4.4: Mukta (Latin + Devanagari),
/// Mukta Mahee (Gurmukhi), Noto Sans as the only fallback.
ThemeData rkTheme(Brightness brightness) {
  final status = switch (brightness) {
    Brightness.light => RkStatusColors.light,
    Brightness.dark => RkStatusColors.dark,
  };
  final scheme = switch (brightness) {
    Brightness.light => ColorScheme(
      brightness: Brightness.light,
      primary: RkColorsLight.primary,
      onPrimary: RkColorsLight.onPrimary,
      secondary: RkColorsLight.accent,
      onSecondary: RkColorsLight.onPrimary,
      error: RkColorsLight.debit,
      onError: RkColorsLight.onPrimary,
      errorContainer: RkColorsLight.dangerSurface,
      onErrorContainer: RkColorsLight.text,
      surface: RkColorsLight.surface,
      onSurface: RkColorsLight.text,
      onSurfaceVariant: RkColorsLight.textMuted,
      surfaceContainerLowest: RkColorsLight.bg,
      surfaceContainerHighest: RkColorsLight.sunk,
      outline: RkColorsLight.textMuted,
      outlineVariant: RkColorsLight.hairline,
      scrim: RkColorsLight.scrim,
    ),
    Brightness.dark => ColorScheme(
      brightness: Brightness.dark,
      primary: RkColorsDark.primary,
      onPrimary: RkColorsDark.onPrimary,
      secondary: RkColorsDark.accent,
      onSecondary: RkColorsDark.onPrimary,
      error: RkColorsDark.debit,
      onError: RkColorsDark.onPrimary,
      errorContainer: RkColorsDark.dangerSurface,
      onErrorContainer: RkColorsDark.text,
      surface: RkColorsDark.surface,
      onSurface: RkColorsDark.text,
      onSurfaceVariant: RkColorsDark.textMuted,
      surfaceContainerLowest: RkColorsDark.bg,
      surfaceContainerHighest: RkColorsDark.sunk,
      outline: RkColorsDark.textMuted,
      outlineVariant: RkColorsDark.hairline,
      scrim: RkColorsDark.scrim,
    ),
  };
  final bg = switch (brightness) {
    Brightness.light => RkColorsLight.bg,
    Brightness.dark => RkColorsDark.bg,
  };

  final text = rkTextTheme(scheme.onSurface);
  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: RkType.family,
    fontFamilyFallback: rkFontFallback,
    textTheme: text,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    dividerColor: status.hairline,
    focusColor: status.focus,
    splashFactory: InkSparkle.splashFactory,
    // Hairlines over shadows — this is a paper product (11 §4.1).
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: status.hairline)),
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RkRadius.md),
        side: BorderSide(color: status.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: status.hairline,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(minTileHeight: RkSpace.rowMinHeight),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(RkSpace.s12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RkRadius.md),
        ),
        textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(RkSpace.s12),
        side: BorderSide(color: status.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RkRadius.md),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      modalBarrierColor: status.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RkRadius.lg)),
      ),
    ),
    extensions: [status],
  );
  // PLAN desk 193 (j): ThemeData merges [text] over Material 2021's type
  // scale, which tracks every role (bodyLarge 0.5, bodyMedium 0.25, labelLarge
  // 0.1 …). The roles rkTextTheme does not map — and every component default
  // that reads them — would keep that tracking, and so would any Text that
  // inherits the ambient body style. tokens.json defines no tracking, and
  // the frames draw running body/label text untracked (CSS `normal`), so 0
  // is the baseline. The frames *do* track a few roles — c2/S2 *State 1 ·
  // typing* sets -0.02em on the hero amount, 0.08em on the uppercase
  // FROM/FOR captions, 0.16em on the ⋯ placeholders — but no token carries
  // those values yet, so they are a recorded deviation (design/match/S2.json),
  // not literals here.
  return theme.copyWith(
    textTheme: _untracked(theme.textTheme),
    primaryTextTheme: _untracked(theme.primaryTextTheme),
  );
}

/// [t] with every role's tracking set to 0 — sizes, weights, faces kept.
TextTheme _untracked(TextTheme t) {
  TextStyle? z(TextStyle? s) => s?.copyWith(letterSpacing: 0);
  return t.copyWith(
    displayLarge: z(t.displayLarge),
    displayMedium: z(t.displayMedium),
    displaySmall: z(t.displaySmall),
    headlineLarge: z(t.headlineLarge),
    headlineMedium: z(t.headlineMedium),
    headlineSmall: z(t.headlineSmall),
    titleLarge: z(t.titleLarge),
    titleMedium: z(t.titleMedium),
    titleSmall: z(t.titleSmall),
    bodyLarge: z(t.bodyLarge),
    bodyMedium: z(t.bodyMedium),
    bodySmall: z(t.bodySmall),
    labelLarge: z(t.labelLarge),
    labelMedium: z(t.labelMedium),
    labelSmall: z(t.labelSmall),
  );
}

/// The RkType scale mapped onto Material's TextTheme slots, ink-coloured.
/// display→displayLarge · page→headlineMedium · section→titleLarge ·
/// body→bodyLarge · table-row→bodyMedium · caption→bodySmall ·
/// amount-row→labelLarge (tabular). amount-hero has no Material slot; use
/// [RkType.amountHero] directly.
///
/// Every style carries the face itself (11 §4.4; desk 141, F1-1005-6/7):
/// `ThemeData(fontFamily:)` faces only the textTheme it merges, while a style
/// handed to a component theme (AppBar title, button label) replaces the
/// widget's default whole — without the family here it draws in the system
/// face, and Gurmukhi/Devanagari in whatever the OS picks.
///
/// Tracking is 0 on every role (PLAN desk 193 (j)): tokens.json defines no
/// letter-spacing, the canvas frames draw running body/label text untracked,
/// and without an explicit 0 a role inherits Material 2021's (0.1–0.5). The
/// few roles the frames do track (hero amount, uppercase captions) wait on a
/// token — see the note in [rkTheme].
TextTheme rkTextTheme(Color ink) {
  TextStyle c(TextStyle s) => s.copyWith(
    color: ink,
    letterSpacing: 0,
    fontFamily: RkType.family,
    fontFamilyFallback: rkFontFallback,
  );
  return TextTheme(
    displayLarge: c(RkType.display),
    headlineMedium: c(RkType.page),
    titleLarge: c(RkType.section),
    bodyLarge: c(RkType.body),
    bodyMedium: c(RkType.tableRow),
    bodySmall: c(RkType.caption),
    labelLarge: c(RkType.amountRow),
  );
}

/// Status colours as a theme extension so widgets read
/// `RkStatusColors.of(context).credit` and never RkColorsLight/Dark.
/// 07 §1 rule 3: credit/debit colour NUMERALS ONLY, with sign and column;
/// pending/locked tint status words; nothing here floods a surface.
///
/// The `success` / `warning` / `info` / `danger` family landed at the 12 Sep
/// token session (ADR 2026-09-05f §H; design-system §3.1). Every value is
/// measured by `scripts/check_contrast.dart` on all four grounds in both
/// modes. They are near-iso-luminant by hue choice, so they are **never the
/// only signal** — an icon and a word always travel with the tint (07 §1).
@immutable
class RkStatusColors extends ThemeExtension<RkStatusColors> {
  const RkStatusColors({
    required this.credit,
    required this.debit,
    required this.pending,
    required this.locked,
    required this.dangerSurface,
    required this.muted,
    required this.hairline,
    required this.sunk,
    required this.scrim,
    required this.focus,
    required this.loaderTrack,
    required this.loaderSegment,
    required this.skeletonLabel,
    required this.skeletonAmount,
    required this.success,
    required this.warning,
    required this.info,
    required this.danger,
    required this.onDanger,
    required this.focusOnPrimary,
  });

  /// Money in — numerals only, always with + and column position.
  final Color credit;

  /// Money out — numerals only, always with − and column position.
  final Color debit;

  /// Awaiting approval / in transit.
  final Color pending;

  /// Locked periods, disabled dates, read-only.
  final Color locked;

  /// Background for the two loud security screens only.
  final Color dangerSurface;

  /// Secondary text, meta, captions, inactive tab.
  final Color muted;

  /// Rules and dividers.
  final Color hairline;

  /// Recessed wells.
  final Color sunk;

  /// Backdrop behind sheets.
  final Color scrim;

  /// Focus ring.
  final Color focus;

  /// Loader rule track (11 §4.5).
  final Color loaderTrack;

  /// Loader ink segment.
  final Color loaderSegment;

  /// Skeleton label block.
  final Color skeletonLabel;

  /// Skeleton amount block.
  final Color skeletonAmount;

  /// Confirmed / healthy state — status word + icon, never alone.
  final Color success;

  /// Recoverable problem the user can act on (book full, quota near).
  final Color warning;

  /// Neutral notice in the app's own voice (read-only, offline grace).
  final Color info;

  /// Security or destructive state — distinct from [debit], so a warning
  /// never reads as money out.
  final Color danger;

  /// Text/icons on a filled [danger].
  final Color onDanger;

  /// Focus ring on primary buttons, where [focus] equals primary and
  /// vanishes (WCAG 2.2 §2.4.11).
  final Color focusOnPrimary;

  /// Full light set.
  static const light = RkStatusColors(
    credit: RkColorsLight.credit,
    debit: RkColorsLight.debit,
    pending: RkColorsLight.pending,
    locked: RkColorsLight.locked,
    dangerSurface: RkColorsLight.dangerSurface,
    muted: RkColorsLight.textMuted,
    hairline: RkColorsLight.hairline,
    sunk: RkColorsLight.sunk,
    scrim: RkColorsLight.scrim,
    focus: RkColorsLight.focus,
    loaderTrack: RkColorsLight.loaderTrack,
    loaderSegment: RkColorsLight.loaderSegment,
    skeletonLabel: RkColorsLight.skeletonLabel,
    skeletonAmount: RkColorsLight.skeletonAmount,
    success: RkColorsLight.success,
    warning: RkColorsLight.warning,
    info: RkColorsLight.info,
    danger: RkColorsLight.danger,
    onDanger: RkColorsLight.onDanger,
    focusOnPrimary: RkColorsLight.focusOnPrimary,
  );

  /// Full dark set.
  static const dark = RkStatusColors(
    credit: RkColorsDark.credit,
    debit: RkColorsDark.debit,
    pending: RkColorsDark.pending,
    locked: RkColorsDark.locked,
    dangerSurface: RkColorsDark.dangerSurface,
    muted: RkColorsDark.textMuted,
    hairline: RkColorsDark.hairline,
    sunk: RkColorsDark.sunk,
    scrim: RkColorsDark.scrim,
    focus: RkColorsDark.focus,
    loaderTrack: RkColorsDark.loaderTrack,
    loaderSegment: RkColorsDark.loaderSegment,
    skeletonLabel: RkColorsDark.skeletonLabel,
    skeletonAmount: RkColorsDark.skeletonAmount,
    success: RkColorsDark.success,
    warning: RkColorsDark.warning,
    info: RkColorsDark.info,
    danger: RkColorsDark.danger,
    onDanger: RkColorsDark.onDanger,
    focusOnPrimary: RkColorsDark.focusOnPrimary,
  );

  /// Reads the extension from the ambient theme.
  static RkStatusColors of(BuildContext context) =>
      Theme.of(context).extension<RkStatusColors>() ?? light;

  @override
  RkStatusColors copyWith() => this;

  @override
  RkStatusColors lerp(RkStatusColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return RkStatusColors(
      credit: l(credit, other.credit),
      debit: l(debit, other.debit),
      pending: l(pending, other.pending),
      locked: l(locked, other.locked),
      dangerSurface: l(dangerSurface, other.dangerSurface),
      muted: l(muted, other.muted),
      hairline: l(hairline, other.hairline),
      sunk: l(sunk, other.sunk),
      scrim: l(scrim, other.scrim),
      focus: l(focus, other.focus),
      loaderTrack: l(loaderTrack, other.loaderTrack),
      loaderSegment: l(loaderSegment, other.loaderSegment),
      skeletonLabel: l(skeletonLabel, other.skeletonLabel),
      skeletonAmount: l(skeletonAmount, other.skeletonAmount),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      info: l(info, other.info),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      focusOnPrimary: l(focusOnPrimary, other.focusOnPrimary),
    );
  }
}
