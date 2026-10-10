// RESKIN1 audit captures for the entry flow (ADR 2026-10-05 §2; ADR
// 2026-10-10b §1 phase 1 — an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S2   — canvas 2 / 11 *State 1 · typing*, *State 2 · choosing, in the same
//        space*, *State 3 · chosen, Save turns solid*, *No chip row · milk on
//        khata* (Took on credit, FROM WHOM picker open).
// S2.1 — canvas 2 S2-B *Saved · over the member's limit*: the screen after
//        Save (keypad zeroed, both sides kept, the toast). Member limits do
//        not exist yet (07 §5 step 6, M7), so the toast is the plain one.
//        Also the in-place A/C picker, which 13 §3.2 calls S2.1.
// S2.2 — canvas 2 *Date picker* and *A locked day*. Production S2 passes no
//        lock lookup (entry_date_picker.dart ⚠️ SPEC), so the locked day is
//        the picker widget alone with one injected.
// S2.3 — canvas 2 / 13 *Transfer within one book*, *Transfer between books*.
// S2.4 — canvas 2 *Cash count difference*: the only wizard built, the guided
//        confirmation on S5.5's Save (ADR 2026-09-03b §2).
// S2.5 — canvas 2 / 12 B5 *Drawings confirmation*.
//
// States reached by taps are snapped from the mounted screen after the taps
// ([_snap]); the pre-tap picture is deleted.
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/cash_count/cash_count_fake.dart';
import 'package:rukka_folio/features/cash_count/cash_count_routes.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/entry/widgets/entry_chip_row.dart';
import 'package:rukka_folio/features/entry/widgets/entry_date_picker.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

/// Writes the screen as it stands now — the same root-layer picture
/// [rkDesignCapture] takes, for a state a tap reached.
Future<void> _snap(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: rkDesignPixelRatio,
    );
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('$rkDesignCaptureDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Captures [state] of [sid] on both targets. [act] drives the mounted screen
/// to the state; without it the first frame is the state.
Future<void> _shoot(
  WidgetTester tester, {
  required String sid,
  required String state,
  required Future<(Widget, LocalLedger?)> Function() setup,
  Future<void> Function()? act,
}) async {
  for (final target in RkDesignTarget.values) {
    final (child, ledger) = await setup();
    final first = act == null ? state : '$state-pre';
    await rkDesignCapture(
      tester,
      sid: sid,
      state: first,
      target: target,
      ledger: ledger,
      child: child,
    );
    if (act != null) {
      await act();
      await _snap(tester, '${sid}__$state${target.suffix}');
      final pre = File(
        '$rkDesignCaptureDir/${sid}__$first${target.suffix}.png',
      );
      if (pre.existsSync()) pre.deleteSync();
    }
    await _unmount(tester);
  }
}

int _seq = 0;

Widget _entry(SeededLedger s, EntryKind kind) => AddEntryScreen(
  key: ValueKey('r1d-${_seq++}'),
  bookId: s.bookId,
  kind: kind,
);

Future<void> _type(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.byKey(AddEntryKeys.pad(k)));
    await tester.pump();
  }
}

Future<void> _chip(
  WidgetTester tester,
  String name, {
  bool last = false,
}) async {
  final f = find.widgetWithText(EntryAccountChip, name);
  await tester.tap(last ? f.last : f.first);
  await tester.pumpAndSettle();
}

Future<void> _openSlot(WidgetTester tester, EntrySlot slot) async {
  await tester.tap(find.byKey(AddEntryKeys.slot(slot)));
  await tester.pumpAndSettle();
}

/// Searches the open picker for [name] and taps its row.
Future<void> _pickIn(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(AddEntryKeys.search), name);
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(
          of: find.byKey(AddEntryKeys.picker),
          matching: find.text(name),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<SeededLedger> _withDrawings() async {
  final s = await seedSoloLedger();
  await s.ledger.addAccount(
    s.bookId,
    name: 'Drawings',
    accountClass: AccountClass.equitySystem,
    systemRole: SystemRole.drawings,
  );
  return s;
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('F1-1010rD-3 design capture S2 (typing · choosing · chosen · '
      'took-on-credit)', (tester) async {
    late SeededLedger s;
    Future<(Widget, LocalLedger?)> moneyOut() async {
      s = await seedSoloLedger();
      return (_entry(s, EntryKind.moneyOut), s.ledger);
    }

    await _shoot(
      tester,
      sid: 'S2',
      state: 'typing',
      setup: moneyOut,
      act: () => _type(tester, '2400'),
    );
    await _shoot(
      tester,
      sid: 'S2',
      state: 'choosing',
      setup: moneyOut,
      act: () async {
        await _type(tester, '2400');
        await _chip(tester, 'Cash in hand');
        await _openSlot(tester, EntrySlot.ledger);
        expect(find.byKey(AddEntryKeys.picker), findsOneWidget);
      },
    );
    await _shoot(
      tester,
      sid: 'S2',
      state: 'chosen',
      setup: moneyOut,
      act: () async {
        await _type(tester, '2400');
        await _chip(tester, 'Cash in hand');
        await _openSlot(tester, EntrySlot.ledger);
        await _pickIn(tester, 'Diesel');
        expect(
          tester
              .widget<ButtonStyleButton>(find.byKey(AddEntryKeys.save))
              .enabled,
          isTrue,
        );
      },
    );
    await _shoot(
      tester,
      sid: 'S2',
      state: 'took-on-credit',
      setup: () async {
        s = await seedSoloLedger();
        return (_entry(s, EntryKind.tookCredit), s.ledger);
      },
      act: () async {
        await _type(tester, '3600');
        await _openSlot(tester, EntrySlot.ledger);
        expect(find.byKey(AddEntryKeys.picker), findsOneWidget);
      },
    );
  });

  testWidgets('F1-1010rD-4 design capture S2.1 (saved · picker)', (
    tester,
  ) async {
    late SeededLedger s;
    Future<(Widget, LocalLedger?)> moneyOut() async {
      s = await seedSoloLedger();
      return (_entry(s, EntryKind.moneyOut), s.ledger);
    }

    await _shoot(
      tester,
      sid: 'S2.1',
      state: 'saved',
      setup: moneyOut,
      act: () async {
        await _type(tester, '2400');
        await _chip(tester, 'Cash in hand');
        await _openSlot(tester, EntrySlot.ledger);
        await _pickIn(tester, 'Diesel');
        await tester.tap(find.byKey(AddEntryKeys.save));
        await _settleIo(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Undo'), findsOneWidget);
      },
    );
    // The toast's own 10 s timer is left to the unmount; nothing waits on it.
    await _shoot(
      tester,
      sid: 'S2.1',
      state: 'picker',
      setup: moneyOut,
      act: () async {
        await _type(tester, '2400');
        await _openSlot(tester, EntrySlot.ledger);
        expect(find.byKey(AddEntryKeys.search), findsOneWidget);
      },
    );
  });

  testWidgets('F1-1010rD-5 design capture S2.2 (date picker · locked day)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S2.2',
      state: 'date-picker',
      setup: () async {
        final s = await seedSoloLedger();
        return (_entry(s, EntryKind.moneyOut), s.ledger);
      },
      act: () async {
        await _type(tester, '2400');
        await _chip(tester, 'Cash in hand');
        await tester.tap(find.byKey(AddEntryKeys.dateChip));
        await tester.pumpAndSettle();
        expect(find.byKey(AddEntryKeys.datePicker), findsOneWidget);
      },
    );
    // The widget alone: every earlier month locked, this month open.
    await _shoot(
      tester,
      sid: 'S2.2',
      state: 'locked-day',
      setup: () async {
        final ledger = await openTestLedger();
        final today = ledger.today();
        return (
          Scaffold(
            body: SafeArea(
              child: EntryDatePicker(
                today: today,
                selected: today,
                isLocked: (p) => p.compareTo(today.yearMonth) < 0,
                onPick: (_) {},
                onFixOldEntry: () {},
              ),
            ),
          ),
          ledger,
        );
      },
      act: () async {
        // Back one month, then a day in it.
        await tester.tap(find.byKey(EntryDatePickerKeys.prevMonth));
        await tester.pumpAndSettle();
        await tester.tap(find.text('10').first);
        await tester.pumpAndSettle();
        expect(find.byKey(EntryDatePickerKeys.lockedMessage), findsOneWidget);
      },
    );
  });

  testWidgets('F1-1010rD-6 design capture S2.3 (within one book · between '
      'books)', (tester) async {
    await _shoot(
      tester,
      sid: 'S2.3',
      state: 'within-one-book',
      setup: () async {
        final s = await seedSoloLedger();
        return (_entry(s, EntryKind.transfer), s.ledger);
      },
      act: () async {
        await _type(tester, '20000');
        await _chip(tester, 'Cash in hand');
        await _chip(tester, 'SBI Saving', last: true);
      },
    );
    await _shoot(
      tester,
      sid: 'S2.3',
      state: 'between-books',
      setup: () async {
        final s = await seedSoloLedger();
        final family = await s.ledger.createBook(
          name: 'Sharma Family',
          type: BookType.family,
          cashName: 'Family Cash',
        );
        expect(family, isNotEmpty);
        return (_entry(s, EntryKind.transfer), s.ledger);
      },
      act: () async {
        await _type(tester, '50000');
        await _chip(tester, 'SBI Saving');
        await _openSlot(tester, EntrySlot.ledger);
        await tester.tap(find.text('Sharma Family').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Family Cash').last);
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('F1-1010rD-7 design capture S2.4 (cash count difference)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S2.4',
      state: 'cash-count-difference',
      setup: () async {
        final source = FakeCashCountSource(
          target: CashCountTarget(
            bookId: 'book-1',
            bookType: BookType.business,
            account: Account(
              id: 'galla',
              bookId: 'book-1',
              name: 'Galla',
              accountClass: AccountClass.money,
              subtype: MoneySubtype.cash,
              createdOrder: 1,
            ),
            bookBalance: const Paise(13060000),
          ),
        );
        return (
          CashCountScreen(accountId: 'galla', source: source) as Widget,
          null,
        );
      },
      act: () async {
        await tester.enterText(find.byType(TextField).first, '130000');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save count').last);
        await tester.pumpAndSettle();
        expect(find.text('Record the difference?'), findsOneWidget);
      },
    );
  });

  testWidgets('F1-1010rD-8 design capture S2.5 (drawings)', (tester) async {
    await _shoot(
      tester,
      sid: 'S2.5',
      state: 'drawings',
      setup: () async {
        final s = await _withDrawings();
        return (_entry(s, EntryKind.moneyOut), s.ledger);
      },
      act: () async {
        await _type(tester, '30000');
        await _chip(tester, 'Cash in hand');
        await _openSlot(tester, EntrySlot.ledger);
        await _pickIn(tester, 'Drawings');
        expect(find.byKey(AddEntryKeys.drawingsBanner), findsOneWidget);
      },
    );
  });
}
