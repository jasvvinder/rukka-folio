@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/tokens.dart';

void main() {
  test('F1-13-8 rkTheme builds light and dark from their own full token sets, Mukta first', () {
    final light = rkTheme(Brightness.light);
    final dark = rkTheme(Brightness.dark);
    expect(light.colorScheme.primary, RkColorsLight.primary);
    expect(light.scaffoldBackgroundColor, RkColorsLight.bg);
    expect(light.colorScheme.surface, RkColorsLight.surface);
    expect(dark.colorScheme.primary, RkColorsDark.primary);
    expect(dark.scaffoldBackgroundColor, RkColorsDark.bg);
    expect(dark.colorScheme.surface, RkColorsDark.surface);
    expect(dark.colorScheme.primary, isNot(light.colorScheme.primary));

    final ls = light.extension<RkStatusColors>()!;
    final ds = dark.extension<RkStatusColors>()!;
    expect(ls.credit, RkColorsLight.credit);
    expect(ls.debit, RkColorsLight.debit);
    expect(ls.muted, RkColorsLight.textMuted);
    expect(ds.credit, RkColorsDark.credit);
    expect(ds.debit, RkColorsDark.debit);
    expect(ds.pending, RkColorsDark.pending);

    // 11 §4.4 — one family across scripts, Noto Sans only as fallback.
    expect(light.textTheme.bodyLarge!.fontFamily, 'Mukta');
    expect(light.textTheme.bodyLarge!.fontFamilyFallback, [
      'MuktaMahee',
      'NotoSans',
    ]);
    // Scale from tokens: body 16/400, page 28/600, amount-row tabular.
    expect(light.textTheme.bodyLarge!.fontSize, 16);
    expect(light.textTheme.headlineMedium!.fontSize, 28);
    expect(light.textTheme.headlineMedium!.fontWeight, FontWeight.w600);
    expect(light.textTheme.labelLarge!.fontFeatures, RkType.tabular);
  });
}
