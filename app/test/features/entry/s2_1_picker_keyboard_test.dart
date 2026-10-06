// S2.1 with the soft keyboard up — PLAN desk 173.
//
//   F1-1006c-9  the phase-0 journey harness on rf_min (360×800 dp) logged
//               "A RenderFlex overflowed by 93 pixels on the bottom" at the
//               picker's Column during F2's first entry. Searching for an
//               account is the one moment S2 summons the keyboard, and the
//               Scaffold gives the keyboard's height back out of the body —
//               so the screen must work at the *shrunken* height, on both
//               default phones (with their status bars), at 100 % and 200 %:
//                 · nothing overflows, and the search field keeps its text
//                   and focus as the layout changes under it;
//                 · what is already entered — amount, verb, chips — stays on
//                   screen, never scrolled away (07 §5 "Single screen,
//                   always" 🔒);
//                 · an account matching the search is on screen above the
//                   keyboard and is picked *with the keyboard still up*
//                   (07 §5 step 3, 13 §3.2 row S2.1 "search-first");
//                 · the pick lands in the slot, and once the keyboard goes
//                   Save is back.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/entry/widgets/entry_chip_row.dart';

import '../../shared/test_app.dart';

/// Each test phone: its size, the soft keyboard's height (Gboard on the
/// 360×800 dp Android floor; the iOS keyboard with its suggestion bar on
/// 390×844) and the status bar the screen sits under.
const _phones = <(Size, double, double)>[
  (Size(360, 800), 300, 24),
  (Size(390, 844), 336, 47),
];

int _pumpSeq = 0;

void main() {
  testWidgets(
    'F1-1006c-9 S2.1 search with the keyboard up — entry stays visible, a '
    'matching account is on screen and picked, no overflow (360×800, '
    '390×844 · 100 %, 200 %)',
    (tester) async {
      final seeded = await seedSoloLedger();
      final failures = <String>[];
      for (final (size, keyboard, statusBar) in _phones) {
        for (final scale in const [1.0, 2.0]) {
          for (final kind in EntryKind.values.where(
            (k) => k != EntryKind.adjustment,
          )) {
            final at = '${kind.wire} at ${scale * 100} % on $size';
            await pumpRk(
              tester,
              AddEntryScreen(
                key: ValueKey('kb-${_pumpSeq++}'),
                bookId: seeded.bookId,
                kind: kind,
              ),
              ledger: seeded.ledger,
              textScale: scale,
              viewport: size,
            );
            final dpr = tester.view.devicePixelRatio;
            tester.view.padding = FakeViewPadding(top: statusBar * dpr);
            tester.view.viewPadding = FakeViewPadding(top: statusBar * dpr);
            await tester.pump();
            // Type an amount, open the counterpart list in place.
            for (final k in '2400'.split('')) {
              await tester.tap(find.byKey(AddEntryKeys.pad(k)));
              await tester.pump();
            }
            await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
            await tester.pumpAndSettle();
            // The account the user is after: the list's first row, searched
            // for by its first two letters.
            final firstRow = find
                .descendant(
                  of: find.byKey(AddEntryKeys.picker),
                  matching: find.byType(ListTile),
                )
                .first;
            final name =
                (tester
                            .widget<Text>(
                              find
                                  .descendant(
                                    of: firstRow,
                                    matching: find.byType(Text),
                                  )
                                  .first,
                            )
                            .data ??
                        '')
                    .trim();
            final query = name.substring(0, 2);
            // Focus the search field, type — and the keyboard arrives.
            await tester.showKeyboard(find.byKey(AddEntryKeys.search));
            await tester.enterText(find.byKey(AddEntryKeys.search), query);
            await tester.pump();
            tester.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
            await tester.pumpAndSettle();

            final error = tester.takeException();
            if (error != null) {
              failures.add('$at: ${error.toString().split('\n').first}');
            }
            // The layout changes under the field the user is typing in: it
            // must keep its text and its focus, or the keyboard would drop.
            final field = tester.widget<EditableText>(
              find.descendant(
                of: find.byKey(AddEntryKeys.search),
                matching: find.byType(EditableText),
              ),
            );
            if (field.controller.text != query || !field.focusNode.hasFocus) {
              failures.add('$at: the search field lost its text or focus');
            }

            final visible = Rect.fromLTRB(
              0,
              statusBar,
              size.width,
              size.height - keyboard,
            );
            void onScreen(String what, Finder f) {
              final hit = f.hitTestable();
              if (hit.evaluate().isEmpty) {
                failures.add('$at: $what is not on screen');
                return;
              }
              final r = tester.getRect(hit.first);
              if (r.height < 1 ||
                  r.top < visible.top - 0.5 ||
                  r.bottom > visible.bottom + 0.5) {
                failures.add('$at: $what at $r is not wholly in $visible');
              }
            }

            onScreen('the search field', find.byKey(AddEntryKeys.search));
            // Everything already entered stays visible (07 §5 🔒) — and
            // the screen does not scroll it away to make room.
            onScreen('the amount', find.byKey(AddEntryKeys.amount));
            onScreen('the verb', find.byKey(AddEntryKeys.verbPill));
            final chipRows = find.byType(EntryChipRow);
            for (var i = 0; i < chipRows.evaluate().length; i++) {
              onScreen('chip row $i', chipRows.at(i));
            }
            // The account being searched for is there to pick (07 §5
            // step 3) — on screen at scroll 0, above the keyboard.
            final match = find.descendant(
              of: find.byKey(AddEntryKeys.picker),
              matching: find.text(name),
            );
            onScreen('the matching account "$name"', match);
            if (match.hitTestable().evaluate().isEmpty) {
              tester.view.resetViewInsets();
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump(const Duration(milliseconds: 1));
              continue;
            }

            // Pick it with the keyboard still up.
            await tester.tap(match.hitTestable().first);
            await tester.pump();
            final duringPick = tester.takeException();
            if (duringPick != null) {
              failures.add(
                '$at: picking: ${duringPick.toString().split('\n').first}',
              );
            }
            // The text field has gone with the list, so the keyboard goes.
            tester.view.resetViewInsets();
            await tester.pumpAndSettle();
            if (find.byKey(AddEntryKeys.picker).evaluate().isNotEmpty) {
              failures.add('$at: the list stayed open after the pick');
            }
            if (find
                .descendant(
                  of: find.byKey(AddEntryKeys.slot(EntrySlot.ledger)),
                  matching: find.textContaining(name),
                )
                .evaluate()
                .isEmpty) {
              failures.add('$at: "$name" did not land in the slot');
            }
            if (find
                .byKey(AddEntryKeys.save)
                .hitTestable()
                .evaluate()
                .isEmpty) {
              failures.add('$at: Save did not come back with the keyboard');
            }
            final after = tester.takeException();
            if (after != null) {
              failures.add('$at: ${after.toString().split('\n').first}');
            }
            tester.view.resetPadding();
            tester.view.resetViewPadding();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 1));
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    },
  );
}
