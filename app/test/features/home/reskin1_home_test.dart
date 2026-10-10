// RESKIN1 audit captures for S1's children (ADR 2026-10-05 §2; ADR
// 2026-10-10b §1 phase 1 — an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S1.1 — canvas 7 *You will give · drill-down*: the list behind the
//        position row, several suppliers owed.
// S1.2 — canvas 7 / 12 *Scope switcher · two books, two chips*: Me plus one
//        business, Home in the shell.
// S1.3 — canvas 7 *Scope switcher sheet · three or more books (D1)*: the
//        grouped sheet open over Home.
//
// Home is mounted through the production wiring ([homeScreenFor]) with
// setup finished, so the S0.7 checklist does not stand in for the baseline.
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_routes.dart';
import 'package:rukka_folio/features/home/screens/s1_1_position_drilldown_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_scope_switcher.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

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

/// Home as shipped, past setup for every book [ledger] holds.
Future<Widget> _home(LocalLedger ledger) async {
  final prefs = MemoryPrefs()..values[RkPrefKeys.recoverySheetVerified] = '1';
  for (final id in await ledger.mirror.bookIds()) {
    prefs.values[RkPrefKeys.openingBalancesOf(id)] = '1';
  }
  final settings = AppSettings(prefs: prefs);
  await settings.load();
  return AppSettingsScope(
    settings: settings,
    child: Builder(builder: homeScreenFor),
  );
}

/// S1.1's suppliers, in creation order: the smallest balance first, the
/// largest second, the middle one last — so creation order is neither
/// balance order nor its reverse.
const _suppliers = [
  ('Vardhman Dairy', 360_000),
  ('Tuglaq Yarn Company', 17_000_000),
  ('Avtar Transport Co.', 1_120_000),
];

Future<SeededLedger> _withBooks(List<(String, BookType)> extra) async {
  final seed = await seedSoloLedger();
  for (final (name, type) in extra) {
    await seed.ledger.createBook(
      name: name,
      type: type,
      startDate: seed.ledger.today().addDays(-7),
    );
  }
  return seed;
}

void main() {
  testWidgets('F1-1010rD-1 design capture S1.1 (you will give)', (
    tester,
  ) async {
    for (final target in RkDesignTarget.values) {
      final seed = await seedSoloLedger();
      // Synthetic suppliers (CLAUDE.md rule 4), each owed a different sum —
      // created out of balance order, so the capture shows whether S1.1
      // sorts by balance (07 §7 🔒) or by creation order (R1D finding 2).
      for (final (name, paise) in _suppliers) {
        final party = await seed.ledger.addAccount(
          seed.bookId,
          name: name,
          accountClass: AccountClass.party,
        );
        await seed.ledger.tookCredit(
          bookId: seed.bookId,
          fromWhom: party.id,
          took: seed.fuelId,
          paise: paise,
          date: seed.ledger.today().addDays(-3),
        );
      }
      await rkDesignCapture(
        tester,
        sid: 'S1.1',
        state: 'you-will-give',
        target: target,
        ledger: seed.ledger,
        child: PositionDrilldownScreen(
          line: PositionLine.youWillGive,
          onOpenAccount: (_) {},
        ),
      );
      expect(find.text('Tuglaq Yarn Company'), findsOneWidget);
      await _unmount(tester);
    }
  });

  // Desk 193 (i): what the ageing chips look like once ages are known. No
  // doc yet defines a party's age, so production draws none; this capture
  // feeds the seam a fake (95 / 41 / 12 days — one red, one amber, one none) so
  // the chip and footnote can be paired with canvas c7 S1.1.
  testWidgets('F1-193-7 design capture S1.1 with ageing chips (fake ages '
      'through the seam)', (tester) async {
    const fakeAges = {
      'Tuglaq Yarn Company': 95,
      'Avtar Transport Co.': 41,
      'Vardhman Dairy': 12,
    };
    for (final target in RkDesignTarget.values) {
      final seed = await seedSoloLedger();
      for (final (name, paise) in _suppliers) {
        final party = await seed.ledger.addAccount(
          seed.bookId,
          name: name,
          accountClass: AccountClass.party,
        );
        await seed.ledger.tookCredit(
          bookId: seed.bookId,
          fromWhom: party.id,
          took: seed.fuelId,
          paise: paise,
          date: seed.ledger.today().addDays(-3),
        );
      }
      await rkDesignCapture(
        tester,
        sid: 'S1.1',
        state: 'ageing-fake',
        target: target,
        ledger: seed.ledger,
        child: PositionDrilldownScreen(
          line: PositionLine.youWillGive,
          onOpenAccount: (_) {},
          ageDaysOf: (row) => fakeAges[row.account.name],
        ),
      );
      expect(find.text('> 90 days'), findsOneWidget);
      expect(find.text('> 30 days'), findsOneWidget);
      await _unmount(tester);
    }
  });

  // 07 §7 🔒: *party list sorted by balance*. The doc does not say which way,
  // so the test asks only that the list is ordered by balance — the party
  // with the middle balance sits between the other two.
  testWidgets(
    'F1-1010rD-10 S1.1 sorts parties by balance, not creation order',
    // R1D finding 2, fixed by F193H (desk 193 (i)); F1-193-4 pins the way.
    (tester) async {
      final seed = await seedSoloLedger();
      for (final (name, paise) in _suppliers) {
        final party = await seed.ledger.addAccount(
          seed.bookId,
          name: name,
          accountClass: AccountClass.party,
        );
        await seed.ledger.tookCredit(
          bookId: seed.bookId,
          fromWhom: party.id,
          took: seed.fuelId,
          paise: paise,
          date: seed.ledger.today().addDays(-3),
        );
      }
      await pumpRk(
        tester,
        PositionDrilldownScreen(
          line: PositionLine.youWillGive,
          onOpenAccount: (_) {},
        ),
        ledger: seed.ledger,
      );
      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      final small = top('Vardhman Dairy');
      final middle = top('Avtar Transport Co.');
      final large = top('Tuglaq Yarn Company');
      expect(
        (small < middle && middle < large) ||
            (large < middle && middle < small),
        isTrue,
        reason: 'the middle balance must sit between the other two',
      );
      await _unmount(tester);
    },
  );

  testWidgets('F1-1010rD-2 design capture S1.2 (two chips) and S1.3 (grouped '
      'sheet)', (tester) async {
    for (final target in RkDesignTarget.values) {
      final seed = await _withBooks([('Sharma Textile', BookType.business)]);
      await rkDesignCapture(
        tester,
        sid: 'S1.2',
        state: 'two-chips',
        target: target,
        tab: RkTab.home,
        ledger: seed.ledger,
        child: await _home(seed.ledger),
      );
      expect(find.byType(HomeScopeToggle), findsOneWidget);
      await _unmount(tester);
    }
    for (final target in RkDesignTarget.values) {
      final seed = await _withBooks([
        ('Sharma Joint Family', BookType.family),
        ('Agriculture Business', BookType.business),
        ('Sharma Super Store', BookType.business),
      ]);
      await rkDesignCapture(
        tester,
        sid: 'S1.3',
        state: 'sheet-pre',
        target: target,
        tab: RkTab.home,
        ledger: seed.ledger,
        child: await _home(seed.ledger),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(HomeScopeSheetButton),
          matching: find.byType(ActionChip),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScopeSheet), findsOneWidget);
      await _snap(tester, 'S1.3__sheet${target.suffix}');
      final pre = File(
        '$rkDesignCaptureDir/S1.3__sheet-pre${target.suffix}.png',
      );
      if (pre.existsSync()) pre.deleteSync();
      await _unmount(tester);
    }
  });
}
