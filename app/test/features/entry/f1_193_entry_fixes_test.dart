// PLAN desk 193 slice E — the S2 defects the RESKIN1 round-1 audit measured
// (design/match/S2*.json), each pinned against the rule that makes it one.
//
//   F1-193-11  enabled Save is the solid primary (07 §5 step 5.5 🔒), and a
//              disabled Save is not.
//   F1-193-12  the preview's dotted gap and arrow are icons, never U+22EF /
//              U+2192 text — neither glyph is in Mukta / Mukta Mahee / Noto
//              Sans (11 §4.4), so as text they draw as boxes.
//   F1-193-13  the keypad's backspace is an icon, never U+232B text.
//   F1-193-14  the Saved toast's tick is an icon, never U+2713 text, and the
//              copy around it is intact.
//   F1-193-15  *+ More* is wholly on screen at 390 wide on every verb.
//   F1-193-16  the chosen verb is always inside the pill row's viewport.
//   F1-193-17  S2.5 — with the drawings banner up, the keypad takes the
//              room down to Save; nothing is left empty under it.
//   F1-193-19  *+ More* and every money chip have a ≥ 44 pt hit area
//              (13 §8), and *+ More*'s spoken node carries the tap.
//   F1-193-20  every keypad key's spoken node carries the tap (a button
//              that TalkBack / VoiceOver cannot press is a dead end).
//   F1-193-21  S2.5 — while the For slot is re-searched with the keyboard
//              up, the drawings banner is hidden with its slot, and it is
//              back once the search closes.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/entry/widgets/entry_chip_row.dart';
import 'package:rukka_folio/features/entry/widgets/entry_drawings_banner.dart';
import 'package:rukka_folio/features/entry/widgets/entry_keypad.dart';
import 'package:rukka_folio/features/entry/widgets/entry_preview_line.dart';
import 'package:rukka_folio/features/entry/widgets/entry_tick_text.dart';
import 'package:rukka_folio/features/entry/widgets/entry_verb_pill.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/tokens.dart';

import '../../shared/test_app.dart';

int _seq = 0;

Future<SeededLedger> _pump(
  WidgetTester tester, {
  EntryKind kind = EntryKind.moneyOut,
  Size size = const Size(390, 844),
  SeededLedger? seeded,
}) async {
  final s = seeded ?? await seedSoloLedger();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await pumpRk(
    tester,
    AddEntryScreen(
      key: ValueKey('f193-${_seq++}'),
      bookId: s.bookId,
      kind: kind,
    ),
    ledger: s.ledger,
  );
  await tester.pumpAndSettle();
  return s;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AddEntryScreen)));

/// Every string actually laid out as text under [root] (icons excluded).
List<String> _drawnText(WidgetTester tester, Finder root) => [
  for (final p in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: root, matching: find.byType(RichText)),
  ))
    if (p.text.style?.fontFamily != 'MaterialIcons') p.text.toPlainText(),
];

Future<void> _typeAmount(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.byKey(AddEntryKeys.pad(k)));
    await tester.pump();
  }
}

Future<void> _completeMoneyOut(WidgetTester tester) async {
  await _typeAmount(tester, '2400');
  await tester.tap(find.text('Cash in hand'));
  await tester.pump();
  await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Diesel').last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('F1-193-11 enabled Save is the solid primary; disabled is not '
      '(07 §5 step 5.5 🔒)', (tester) async {
    await _pump(tester);
    final scheme = Theme.of(tester.element(find.byType(AddEntryScreen)))
        .colorScheme;
    Color? fill() {
      final m = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(AddEntryKeys.save),
              matching: find.byType(Material),
            )
            .first,
      );
      return m.color;
    }

    final save = tester.widget<ButtonStyleButton>(
      find.byKey(AddEntryKeys.save),
    );
    expect(save.enabled, isFalse);
    expect(fill(), isNot(scheme.primary));

    await _completeMoneyOut(tester);
    expect(
      tester.widget<ButtonStyleButton>(find.byKey(AddEntryKeys.save)).enabled,
      isTrue,
    );
    expect(fill(), scheme.primary);
    final label = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(AddEntryKeys.save),
        matching: find.byType(RichText),
      ),
    );
    expect(label.text.style?.color, scheme.onPrimary);
    await _unmount(tester);
  });

  testWidgets('F1-193-12 preview gap and arrow are icons, not uncovered '
      'glyphs (11 §4.4)', (tester) async {
    await pumpRk(
      tester,
      const Scaffold(body: EntryPreviewLine(amountPaise: 0, complete: false)),
    );
    expect(find.byIcon(previewGapIcon), findsNWidgets(2));
    expect(find.byIcon(previewArrowIcon), findsOneWidget);
    final drawn = _drawnText(tester, find.byType(EntryPreviewLine)).join();
    expect(drawn, contains('₹0'));
    expect(drawn, isNot(contains('⋯')));
    expect(drawn, isNot(contains('→')));

    await pumpRk(
      tester,
      const Scaffold(
        body: EntryPreviewLine(
          amountPaise: 240000,
          creditName: 'Cash A/c',
          debitName: 'Diesel Expense A/c',
          complete: true,
        ),
      ),
    );
    expect(find.byIcon(previewGapIcon), findsNothing);
    expect(find.byIcon(previewArrowIcon), findsOneWidget);
    final full = _drawnText(tester, find.byType(EntryPreviewLine)).join();
    expect(full, contains('Cash A/c'));
    expect(full, contains('Diesel Expense A/c'));
    expect(full, isNot(contains('→')));
  });

  testWidgets('F1-193-13 keypad backspace is an icon, not U+232B', (
    tester,
  ) async {
    await _pump(tester);
    final key = find.byKey(AddEntryKeys.pad(keypadBackspace));
    expect(
      find.descendant(of: key, matching: find.byIcon(keypadBackspaceIcon)),
      findsOneWidget,
    );
    expect(
      _drawnText(tester, find.byKey(AddEntryKeys.keypad)).join(),
      isNot(contains('⌫')),
    );
    // Still deletes the last digit.
    await _typeAmount(tester, '24');
    await tester.tap(key);
    await tester.pump();
    expect(
      tester
          .widget<EntryPreviewLine>(find.byType(EntryPreviewLine))
          .amountPaise,
      200,
    );
    await _unmount(tester);
  });

  testWidgets('F1-193-14 the Saved toast draws its tick as an icon, copy '
      'intact', (tester) async {
    await _pump(tester);
    await _completeMoneyOut(tester);
    await tester.tap(find.byKey(AddEntryKeys.save));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final bar = find.byType(SnackBar);
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.byIcon(entryTickIcon)),
      findsOneWidget,
    );
    final drawn = _drawnText(tester, bar).join(' ');
    expect(drawn, isNot(contains('✓')));
    // The words of `entry.saved` survive, only the glyph became an icon.
    final words = _l10n(tester).entrySaved.replaceAll('✓', '').trim();
    for (final w in words.split(RegExp(r'\s+'))) {
      expect(drawn, contains(w));
    }
    expect(find.byKey(AddEntryKeys.savedMessage), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('F1-193-15 + More is wholly on screen at 390 wide, every verb', (
    tester,
  ) async {
    final s = await seedSoloLedger();
    for (final kind in entryVerbs) {
      await _pump(tester, kind: kind, seeded: s);
      final more = find.byKey(EntryChipRowKeys.more);
      expect(more, findsWidgets, reason: kind.name);
      for (final e in more.evaluate()) {
        final r = tester.getRect(find.byElementPredicate((x) => x == e));
        expect(
          r.left,
          greaterThanOrEqualTo(RkSpace.gutter - 0.5),
          reason: kind.name,
        );
        expect(
          r.right,
          lessThanOrEqualTo(390 - RkSpace.gutter + 0.5),
          reason: kind.name,
        );
      }
      await _unmount(tester);
    }
  });

  testWidgets('F1-193-16 the chosen verb stays inside the pill row', (
    tester,
  ) async {
    final s = await seedSoloLedger();
    for (final kind in [EntryKind.tookCredit, EntryKind.transfer]) {
      await _pump(tester, kind: kind, seeded: s);
      final row = tester.getRect(find.byKey(AddEntryKeys.verbPill));
      final chosen = tester.getRect(
        find.descendant(
          of: find.byKey(AddEntryKeys.verbPill),
          matching: find.text(verbLabel(_l10n(tester), kind)),
        ),
      );
      expect(
        chosen.left,
        greaterThanOrEqualTo(row.left - 0.5),
        reason: kind.name,
      );
      expect(
        chosen.right,
        lessThanOrEqualTo(row.right + 0.5),
        reason: kind.name,
      );
      await _unmount(tester);
    }

    // A position switched from the parent scrolls into view too.
    var kind = EntryKind.moneyIn;
    late StateSetter set;
    await pumpRk(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            child: StatefulBuilder(
              builder: (c, s) {
                set = s;
                return EntryVerbPill(
                  key: AddEntryKeys.verbPill,
                  kind: kind,
                  onKind: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    set(() => kind = EntryKind.transfer);
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byKey(AddEntryKeys.verbPill));
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(AddEntryKeys.verbPill)),
    );
    final chosen = tester.getRect(find.text(verbLabel(l10n, kind)));
    expect(chosen.left, greaterThanOrEqualTo(row.left - 0.5));
    expect(chosen.right, lessThanOrEqualTo(row.right + 0.5));
  });

  testWidgets('F1-193-17 S2.5 the keypad keeps its room under the drawings '
      'banner — nothing empty under Save', (tester) async {
    final s = await seedSoloLedger();
    await s.ledger.addAccount(
      s.bookId,
      name: 'Drawings',
      accountClass: AccountClass.equitySystem,
      systemRole: SystemRole.drawings,
    );
    await _pump(tester, seeded: s);
    final keypadBefore = tester.getSize(find.byKey(AddEntryKeys.keypad)).height;

    await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AddEntryKeys.search), 'Drawings');
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(AddEntryKeys.picker),
            matching: find.text('Drawings'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(EntryDrawingsBannerKeys.banner), findsOneWidget);

    final banner = tester.getSize(find.byKey(EntryDrawingsBannerKeys.banner));
    final keypad = tester.getRect(find.byKey(AddEntryKeys.keypad));
    final save = tester.getRect(find.byKey(AddEntryKeys.save));
    // The banner's room comes off the keypad, and only its room.
    expect(
      keypad.height,
      greaterThanOrEqualTo(keypadBefore - banner.height - RkSpace.s2 - 1),
    );
    // Save sits at the foot of the body, as it does without the banner.
    expect(844 - save.bottom, lessThanOrEqualTo(RkSpace.s2 + 1));
    expect(save.top - keypad.bottom, lessThanOrEqualTo(RkSpace.s2 + 1));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('F1-193-19 + More and the money chips have a 44 pt hit area; '
      '+ More speaks with a tap action', (tester) async {
    final handle = tester.ensureSemantics();
    final s = await seedSoloLedger();
    for (final scale in const [1.0, 2.0]) {
      for (final kind in entryVerbs) {
        await pumpRk(
          tester,
          AddEntryScreen(
            key: ValueKey('f193-${_seq++}'),
            bookId: s.bookId,
            kind: kind,
          ),
          ledger: s.ledger,
          textScale: scale,
          viewport: const Size(390, 844),
        );
        await tester.pumpAndSettle();
        final at = '${kind.name} at ${scale * 100} %';
        final more = find.byKey(EntryChipRowKeys.more);
        for (final e in more.evaluate()) {
          final f = find.byElementPredicate((x) => x == e);
          final r = tester.getSize(f);
          expect(r.width, greaterThanOrEqualTo(44), reason: at);
          expect(r.height, greaterThanOrEqualTo(44), reason: at);
          final node = tester.getSemantics(f);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
            reason: '$at: + More must carry a semantic tap',
          );
        }
        for (final chip in find.byType(EntryAccountChip).evaluate()) {
          final ink = find.descendant(
            of: find.byElementPredicate((x) => x == chip),
            matching: find.byType(InkWell),
          );
          expect(
            tester.getSize(ink).height,
            greaterThanOrEqualTo(44),
            reason: '$at: a money chip is under 44 pt',
          );
        }
        expect(tester.takeException(), isNull, reason: at);
        await _unmount(tester);
      }
    }
    handle.dispose();
  });

  testWidgets('F1-193-20 every keypad key carries a semantic tap', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    for (final row in keypadRows) {
      for (final k in row) {
        final node = tester.getSemantics(find.byKey(AddEntryKeys.pad(k)));
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'key $k',
        );
      }
    }
    // The spoken tap does what the finger does.
    final one = tester.getSemantics(find.byKey(AddEntryKeys.pad('7')));
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      one.id,
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(AddEntryKeys.amount)).data,
      contains('7'),
    );
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('F1-193-21 S2.5 the drawings banner hides while For is '
      're-searched with the keyboard up, and returns after', (tester) async {
    final s = await seedSoloLedger();
    await s.ledger.addAccount(
      s.bookId,
      name: 'Drawings',
      accountClass: AccountClass.equitySystem,
      systemRole: SystemRole.drawings,
    );
    for (final scale in const [1.0, 2.0]) {
      await pumpRk(
        tester,
        AddEntryScreen(
          key: ValueKey('f193-${_seq++}'),
          bookId: s.bookId,
          kind: EntryKind.moneyOut,
        ),
        ledger: s.ledger,
        textScale: scale,
        viewport: const Size(360, 800),
      );
      final dpr = tester.view.devicePixelRatio;
      tester.view.padding = FakeViewPadding(top: 24 * dpr);
      tester.view.viewPadding = FakeViewPadding(top: 24 * dpr);
      await tester.pumpAndSettle();
      final at = '${scale * 100} %';

      // Choose Drawings for the For slot: the banner fires.
      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(AddEntryKeys.search), 'Drawings');
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(AddEntryKeys.picker),
              matching: find.text('Drawings'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(EntryDrawingsBannerKeys.banner),
        findsOneWidget,
        reason: at,
      );

      // Re-open For and search with the keyboard up: the slot's field is
      // hidden, and its banner with it — the picker keeps the room.
      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      // The keyboard arrives on focus, then the user types.
      await tester.showKeyboard(find.byKey(AddEntryKeys.search));
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * dpr);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(AddEntryKeys.search), 'Di');
      await tester.pumpAndSettle();
      expect(
        find.byKey(EntryDrawingsBannerKeys.banner),
        findsNothing,
        reason: '$at: banner stayed while For was searched',
      );
      expect(tester.takeException(), isNull, reason: at);

      // Search cleared, keyboard down, list closed: the slot still answers
      // Drawings, so the banner is back.
      await tester.enterText(find.byKey(AddEntryKeys.search), '');
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: at);
      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(EntryDrawingsBannerKeys.banner),
        findsOneWidget,
        reason: '$at: banner did not return',
      );
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      await _unmount(tester);
    }
  });
}
