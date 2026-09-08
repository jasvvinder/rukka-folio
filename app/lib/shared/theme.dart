// The app theme — built only from the generated tokens (design/tokens/tokens.json
// → shared/tokens.dart). Light and dark are full sets; nothing here derives one
// from the other (11 §4.3). Features read colours through the theme
// (ColorScheme + [RkStatusColors]) and never touch RkColorsLight/Dark directly.
import 'package:flutter/material.dart';

import 'tokens.dart';

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
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: RkType.family,
    fontFamilyFallback: const [RkType.familyGurmukhi, RkType.familyFallback],
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
}

/// The RkType scale mapped onto Material's TextTheme slots, ink-coloured.
/// display→displayLarge · page→headlineMedium · section→titleLarge ·
/// body→bodyLarge · table-row→bodyMedium · caption→bodySmall ·
/// amount-row→labelLarge (tabular). amount-hero has no Material slot; use
/// [RkType.amountHero] directly.
TextTheme rkTextTheme(Color ink) {
  TextStyle c(TextStyle s) => s.copyWith(color: ink);
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
/// ⚠️ SPEC: the `success` / `warning` / `info` / `danger` family is approved
/// in name but its values are pending a token session (design-system §2);
/// add them here when tokens.json carries them — never invent values.
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
    );
  }
}
