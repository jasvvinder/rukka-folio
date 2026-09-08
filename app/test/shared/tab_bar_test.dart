@Tags(['F1'])
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/tokens.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';
import 'package:rukka_folio/shared/widgets/svg_path.dart';

import 'test_app.dart';

const _labels = {
  RkTab.home: 'Home',
  RkTab.ledger: 'Ledger',
  RkTab.inbox: 'Inbox',
  RkTab.menu: 'Menu',
};

Widget _bar({RkTab selected = RkTab.home, ValueChanged<RkTab>? onSelect}) =>
    Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: RkTabBar(
        selected: selected,
        labels: _labels,
        actionLabel: 'Add entry',
        onSelect: onSelect ?? (_) {},
        onAction: () {},
      ),
    );

void main() {
  testWidgets(
    'F1-13-1 bar has exactly four labelled tabs and one unlabelled centre action with no selected state',
    (tester) async {
      await pumpRk(tester, _bar());
      expect(find.byType(RkTabItem), findsNWidgets(4));
      expect(find.byType(RkCentreAction), findsOneWidget);
      for (final l in _labels.values) {
        expect(find.text(l), findsOneWidget);
      }
      // The action renders no text at all.
      expect(
        find.descendant(
          of: find.byType(RkCentreAction),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      // ...and can never be "selected": its semantics carry no selected flag,
      // while exactly one tab does.
      final action = tester.getSemantics(find.byType(RkCentreAction));
      expect(
        action.getSemanticsData().flagsCollection.isSelected,
        Tristate.none,
      );
      expect(action.label, 'Add entry');
      final selected = RkTab.values
          .where(
            (t) =>
                tester
                    .getSemantics(find.byType(RkTabItem).at(t.index))
                    .getSemanticsData()
                    .flagsCollection
                    .isSelected ==
                Tristate.isTrue,
          )
          .toList();
      expect(selected, [RkTab.home]);
      // Order on the bar: Home · Ledger · ( + ) · Inbox · Menu.
      final xs = [
        tester.getCenter(find.text('Home')).dx,
        tester.getCenter(find.text('Ledger')).dx,
        tester.getCenter(find.byType(RkCentreAction)).dx,
        tester.getCenter(find.text('Inbox')).dx,
        tester.getCenter(find.text('Menu')).dx,
      ];
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]));
      }
    },
  );

  test('F1-13-2 glyph path strings equal design-system §4.1 verbatim', () {
    expect(RkGlyphs.home, ['M3 10.5 12 3l9 7.5', 'M5 9.5V21h14V9.5']);
    expect(RkGlyphs.ledger, [
      'M4 19.5A2.5 2.5 0 0 1 6.5 17H20',
      'M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z',
    ]);
    expect(RkGlyphs.inbox, [
      'M22 12h-6l-2 3h-4l-2-3H2',
      'M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z',
    ]);
    expect(RkGlyphs.menu, ['M4 6h16', 'M4 12h16', 'M4 18h16']);
    // The four glyphs parse; every one lands inside the 24-unit viewBox.
    for (final tab in RkTab.values) {
      for (final d in RkGlyphs.of(tab)) {
        final bounds = parseSvgPath(d).getBounds();
        expect(bounds.left, greaterThanOrEqualTo(0), reason: d);
        expect(bounds.top, greaterThanOrEqualTo(0), reason: d);
        expect(bounds.right, lessThanOrEqualTo(24), reason: d);
        expect(bounds.bottom, lessThanOrEqualTo(24), reason: d);
      }
    }
  });

  testWidgets(
    'F1-13-3 active tab is primary / stroke 2 / weight 600; inactive is muted / stroke 1.8 / weight 400',
    (tester) async {
      await pumpRk(tester, _bar(selected: RkTab.ledger));
      final context = tester.element(find.byType(RkTabBar));
      final primary = Theme.of(context).colorScheme.primary;
      final muted = RkStatusColors.of(context).muted;
      expect(primary, RkColorsLight.primary);
      expect(muted, RkColorsLight.textMuted);

      TextStyle styleOf(String label) =>
          tester.widget<Text>(find.text(label)).style!;
      RkGlyphPainter painterOf(RkTab tab) {
        final glyph = find.descendant(
          of: find.byType(RkTabItem).at(tab.index),
          matching: find.byType(CustomPaint),
        );
        return tester.widget<CustomPaint>(glyph).painter! as RkGlyphPainter;
      }

      expect(styleOf('Ledger').color, primary);
      expect(styleOf('Ledger').fontWeight, FontWeight.w600);
      expect(styleOf('Ledger').fontSize, 10.5);
      expect(painterOf(RkTab.ledger).color, primary);
      expect(painterOf(RkTab.ledger).strokeWidth, 2.0);

      for (final t in [RkTab.home, RkTab.inbox, RkTab.menu]) {
        final label = _labels[t]!;
        expect(styleOf(label).color, muted, reason: label);
        expect(styleOf(label).fontWeight, FontWeight.w400, reason: label);
        expect(styleOf(label).fontSize, 10.5, reason: label);
        expect(painterOf(t).color, muted, reason: label);
        expect(painterOf(t).strokeWidth, 1.8, reason: label);
      }
    },
  );

  testWidgets(
    'F1-13-4 bar is at least 50 tall, glyphs are 21×21, and tapping a tab reports it',
    (tester) async {
      RkTab? tapped;
      await pumpRk(tester, _bar(onSelect: (t) => tapped = t));
      expect(
        tester.getSize(find.byType(RkTabBar)).height,
        greaterThanOrEqualTo(50),
      );
      for (final glyph
          in find
              .descendant(
                of: find.byType(RkTabItem),
                matching: find.byType(RkGlyph),
              )
              .evaluate()) {
        expect(glyph.size, const Size(21, 21));
      }
      await tester.tap(find.text('Inbox'));
      expect(tapped, RkTab.inbox);
    },
  );

  test(
    'F1-13-5 svg path parser handles relative, chained and arc commands',
    () {
      final p = parseSvgPath('M4 6h16');
      expect(p.getBounds(), const Rect.fromLTRB(4, 6, 20, 6));
      final chained = parseSvgPath('M3 10.5 12 3l9 7.5');
      expect(chained.getBounds(), const Rect.fromLTRB(3, 3, 21, 10.5));
      final arc = parseSvgPath('M4 19.5A2.5 2.5 0 0 1 6.5 17H20');
      final b = arc.getBounds();
      expect(b.left, closeTo(4, 0.01));
      expect(b.right, closeTo(20, 0.01));
      expect(b.top, closeTo(17, 0.01));
      expect(b.bottom, closeTo(19.5, 0.01));
      expect(() => parseSvgPath('M0 0C1 1 2 2 3 3'), throwsFormatException);
    },
  );
}
