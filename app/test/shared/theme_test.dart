@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  // 11 §4.4 / ADR 2026-10-05 §2 (desk 141): ThemeData(fontFamily:) faces only
  // the textTheme it merges; a TextStyle handed straight to a component theme
  // (AppBar title, button label…) replaces the widget's default whole, so it
  // must carry the face itself or the phone draws it in the system font.
  for (final b in Brightness.values) {
    test('F1-1005-6 every TextStyle the ${b.name} theme hands out is Mukta '
        'with the Mukta Mahee and Noto Sans fallbacks', () {
      final slots = _textStyleSlots(rkTheme(b));
      // The slots the theme sets itself must be among them, or this test has
      // stopped looking at what desk 141 broke.
      expect(slots.keys, containsAll(['appBar.title', 'filledButton.text']));
      final unfaced = [
        for (final MapEntry(:key, :value) in slots.entries)
          if (value.fontFamily != RkType.family ||
              !_listEquals(value.fontFamilyFallback, _fallback))
            '$key: ${value.fontFamily} ${value.fontFamilyFallback}',
      ];
      expect(unfaced, isEmpty);
    });

    testWidgets('F1-1005-7 under the ${b.name} theme an AppBar title and every '
        'component label draws in Mukta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: rkTheme(b),
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Home'),
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Tab one'),
                    Tab(text: 'Tab two'),
                  ],
                ),
              ),
              body: ListView(
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Filled')),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Outlined'),
                  ),
                  TextButton(onPressed: () {}, child: const Text('TextBtn')),
                  const Chip(label: Text('Chip')),
                  const ListTile(
                    title: Text('Tile title'),
                    subtitle: Text('Tile subtitle'),
                  ),
                  const TextField(
                    decoration: InputDecoration(
                      labelText: 'Label',
                      hintText: 'Hint',
                      helperText: 'Helper',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final ctx = tester.element(find.byType(ListView));
      ScaffoldMessenger.of(ctx)
          .showSnackBar(const SnackBar(content: Text('Snack')));
      showDialog<void>(
        context: ctx,
        builder: (_) => const AlertDialog(
          title: Text('Dialog title'),
          content: Text('Dialog body'),
        ),
      );
      await tester.pumpAndSettle();

      // The AppBar title, as desk 141 states it.
      final title = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == 'Home',
          ),
        ),
      );
      expect(title.text.style?.fontFamily, RkType.family);
      expect(title.text.style?.fontFamilyFallback, _fallback);

      // Everything else drawn on the page.
      final seen = <String>{};
      final unfaced = <String>[];
      void visit(RenderObject o) {
        if (o is RenderParagraph) {
          final style = o.text.style;
          final t = o.text.toPlainText().trim();
          if (t.isNotEmpty && style?.fontFamily != 'MaterialIcons') {
            seen.add(t);
            if (style?.fontFamily != RkType.family ||
                !_listEquals(style?.fontFamilyFallback, _fallback)) {
              unfaced.add(
                '"$t": ${style?.fontFamily} ${style?.fontFamilyFallback}',
              );
            }
          }
        }
        o.visitChildren(visit);
      }

      visit(tester.binding.renderViews.first);
      expect(
        seen,
        containsAll([
          'Home',
          'Tab one',
          'Filled',
          'Outlined',
          'TextBtn',
          'Chip',
          'Tile title',
          'Tile subtitle',
          'Label',
          'Helper',
          'Snack',
          'Dialog title',
          'Dialog body',
        ]),
      );
      expect(unfaced, isEmpty);
    });
  }

  // PLAN desk 193 (j): Material 2021's type scale tracks every role
  // (bodyLarge 0.5, bodyMedium 0.25, labelLarge 0.1 …), and a style that
  // does not say otherwise inherits it — so body and label text ran wider
  // than the canvas on every audited screen. tokens.json defines no
  // tracking and the frames draw running text untracked, so 0 is the
  // baseline; the few roles the frames do track (c2/S2 hero amount -0.02em,
  // uppercase captions 0.08em) have no token yet and are a recorded
  // deviation in design/match/S2.json.
  for (final b in Brightness.values) {
    testWidgets('F1-193-18 the ${b.name} theme tracks no text — every text '
        'style and the ambient body style carry letterSpacing 0', (
      tester,
    ) async {
      final theme = rkTheme(b);
      final tracked = [
        for (final MapEntry(:key, :value) in _textStyleSlots(theme).entries)
          if ((value.letterSpacing ?? 0) != 0) '$key: ${value.letterSpacing}',
      ];
      expect(tracked, isEmpty);
      for (final tt in [theme.textTheme, theme.primaryTextTheme]) {
        for (final s in [
          tt.displayLarge,
          tt.displayMedium,
          tt.displaySmall,
          tt.headlineLarge,
          tt.headlineMedium,
          tt.headlineSmall,
          tt.titleLarge,
          tt.titleMedium,
          tt.titleSmall,
          tt.bodyLarge,
          tt.bodyMedium,
          tt.bodySmall,
          tt.labelLarge,
          tt.labelMedium,
          tt.labelSmall,
        ]) {
          expect(s?.letterSpacing, 0);
        }
      }
      // rkTextTheme on its own (component themes take styles from it).
      final own = rkTextTheme(theme.colorScheme.onSurface);
      expect(own.bodyLarge!.letterSpacing, 0);
      expect(own.bodySmall!.letterSpacing, 0);

      // What a bare `Text(RkType.body…)` inherits under a Scaffold.
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                Text('Body', style: RkType.body),
                TextButton(onPressed: () {}, child: const Text('Btn')),
              ],
            ),
          ),
        ),
      );
      for (final t in ['Body', 'Btn']) {
        final p = tester.renderObject<RenderParagraph>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == t,
          ),
        );
        expect(p.text.style?.letterSpacing ?? 0, 0, reason: t);
      }
    });
  }
}

const _fallback = [RkType.familyGurmukhi, RkType.familyFallback];

bool _listEquals(List<String>? a, List<String> b) =>
    a != null &&
    a.length == b.length &&
    [for (var i = 0; i < b.length; i++) a[i] == b[i]].every((x) => x);

/// Every TextStyle slot on [t] that holds a value — the text themes and the
/// component themes that take a raw style. A null component slot falls back
/// to a textTheme role at build time, which the textTheme entries cover.
Map<String, TextStyle> _textStyleSlots(ThemeData t) {
  const states = <Set<WidgetState>>[
    {},
    {WidgetState.pressed},
    {WidgetState.hovered},
    {WidgetState.focused},
    {WidgetState.disabled},
    {WidgetState.selected},
    {WidgetState.error},
  ];
  final out = <String, TextStyle>{};
  void put(String k, TextStyle? s) {
    if (s != null) out[k] = s;
  }

  void putState(String k, WidgetStateProperty<TextStyle?>? p) {
    if (p == null) return;
    for (final s in states) {
      put(s.isEmpty ? k : '$k${s.map((e) => e.name).toList()}', p.resolve(s));
    }
  }

  void putTheme(String k, TextTheme tt) {
    for (final (n, s) in [
      ('displayLarge', tt.displayLarge),
      ('displayMedium', tt.displayMedium),
      ('displaySmall', tt.displaySmall),
      ('headlineLarge', tt.headlineLarge),
      ('headlineMedium', tt.headlineMedium),
      ('headlineSmall', tt.headlineSmall),
      ('titleLarge', tt.titleLarge),
      ('titleMedium', tt.titleMedium),
      ('titleSmall', tt.titleSmall),
      ('bodyLarge', tt.bodyLarge),
      ('bodyMedium', tt.bodyMedium),
      ('bodySmall', tt.bodySmall),
      ('labelLarge', tt.labelLarge),
      ('labelMedium', tt.labelMedium),
      ('labelSmall', tt.labelSmall),
    ]) {
      put('$k.$n', s);
    }
  }

  putTheme('textTheme', t.textTheme);
  putTheme('primaryTextTheme', t.primaryTextTheme);
  put('appBar.title', t.appBarTheme.titleTextStyle);
  put('appBar.toolbar', t.appBarTheme.toolbarTextStyle);
  put('tabBar.label', t.tabBarTheme.labelStyle);
  put('tabBar.unselectedLabel', t.tabBarTheme.unselectedLabelStyle);
  put('chip.label', t.chipTheme.labelStyle);
  put('chip.secondaryLabel', t.chipTheme.secondaryLabelStyle);
  put('snackBar.content', t.snackBarTheme.contentTextStyle);
  put('dialog.title', t.dialogTheme.titleTextStyle);
  put('dialog.content', t.dialogTheme.contentTextStyle);
  final input = t.inputDecorationTheme;
  put('input.label', input.labelStyle);
  put('input.floatingLabel', input.floatingLabelStyle);
  put('input.helper', input.helperStyle);
  put('input.hint', input.hintStyle);
  put('input.error', input.errorStyle);
  put('input.counter', input.counterStyle);
  put('input.prefix', input.prefixStyle);
  put('input.suffix', input.suffixStyle);
  put('listTile.title', t.listTileTheme.titleTextStyle);
  put('listTile.subtitle', t.listTileTheme.subtitleTextStyle);
  put('listTile.leadingTrailing', t.listTileTheme.leadingAndTrailingTextStyle);
  putState('filledButton.text', t.filledButtonTheme.style?.textStyle);
  putState('outlinedButton.text', t.outlinedButtonTheme.style?.textStyle);
  putState('textButton.text', t.textButtonTheme.style?.textStyle);
  putState('elevatedButton.text', t.elevatedButtonTheme.style?.textStyle);
  putState('iconButton.text', t.iconButtonTheme.style?.textStyle);
  putState('segmentedButton.text', t.segmentedButtonTheme.style?.textStyle);
  putState('menuButton.text', t.menuButtonTheme.style?.textStyle);
  put('fab.extended', t.floatingActionButtonTheme.extendedTextStyle);
  putState('navigationBar.label', t.navigationBarTheme.labelTextStyle);
  put('navigationRail.selected', t.navigationRailTheme.selectedLabelTextStyle);
  put(
    'navigationRail.unselected',
    t.navigationRailTheme.unselectedLabelTextStyle,
  );
  put('bottomNav.selected', t.bottomNavigationBarTheme.selectedLabelStyle);
  put('bottomNav.unselected', t.bottomNavigationBarTheme.unselectedLabelStyle);
  put('tooltip.text', t.tooltipTheme.textStyle);
  put('banner.content', t.bannerTheme.contentTextStyle);
  put('popupMenu.text', t.popupMenuTheme.textStyle);
  putState('popupMenu.label', t.popupMenuTheme.labelTextStyle);
  put('dropdownMenu.text', t.dropdownMenuTheme.textStyle);
  put('badge.text', t.badgeTheme.textStyle);
  put('dataTable.heading', t.dataTableTheme.headingTextStyle);
  put('dataTable.data', t.dataTableTheme.dataTextStyle);
  put('timePicker.helpText', t.timePickerTheme.helpTextStyle);
  put('datePicker.header', t.datePickerTheme.headerHeadlineStyle);
  return out;
}
