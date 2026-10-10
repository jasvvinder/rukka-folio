// Design captures for S0.7 Setup checklist (ADR 2026-10-05 §2; ADR 2026-10-07
// ruling 3; desk 174), drawn on S1 in the production shell. Pair with
// `python3 scripts/design_match.py pair S0.7`. One state per canvas 1 frame,
// named after it so the pair lines up:
//
// O8  — *Home, first run*: Opening balances ticked, the amber sheet row,
//       Add your family.
// O8b — *family, invites skipped*: *Finish Sandhu Family* with its ⋮.
// O8c — *trust, invites skipped*: *Finish Gurdwara Sahib, Ballowal*.
// O8d — *a branch finished*: the trust row ticked and struck.
// O8e — *Not needed*: the ⋮ menu open over the family row.
// O8f — *after Not needed*: the row gone, the toast with Undo.
//
// Home is mounted through [homeScreenFor], the production wiring, never a
// hand-built HomeScreen with a copied door set.
//
// O8e and O8f are states reached by a tap, so they are snapped after the
// tap from the same mounted screen ([_snap]) rather than pumped fresh.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_routes.dart';
import 'package:rukka_folio/features/home/home_scope.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

/// Writes the screen as it stands now under the capture's own name — the
/// same root-layer picture [rkDesignCapture] takes, for a state a tap
/// reached.
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

void main() {
  testWidgets('F1-1007-4 design capture S0.7 (O8 · O8b · O8c · O8d · O8e · '
      'O8f)', (tester) async {
    Future<void> capture(
      String state, {
      required String person,
      required String purpose,
      BookType? branchType,
      String? branchName,
      String? branchState,
      Future<void> Function(RkDesignTarget target)? then,
    }) async {
      for (final target in RkDesignTarget.values) {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: person);
        final personal = (await ledger.mirror.bookIds()).single;
        final prefs = MemoryPrefs()
          ..values[RkPrefKeys.openingBalancesOf(personal)] = '1'
          ..values[RkPrefKeys.setupPurpose] = purpose;
        if (branchType != null) {
          final book = await ledger.createBook(
            name: branchName!,
            type: branchType,
            startDate: ledger.today(),
          );
          prefs.values[RkPrefKeys.openingBalancesOf(book)] = '1';
          if (branchState != null) {
            prefs.values[RkPrefKeys.setupBranch] = jsonEncode({
              'purpose': purpose,
              'state': branchState,
              'book': book,
            });
          }
        }
        final settings = AppSettings(prefs: prefs);
        await settings.load();
        final scope = HomeScopeController()..select(HomeScope.book(personal));
        await rkDesignCapture(
          tester,
          sid: 'S0.7',
          state: state,
          target: target,
          tab: RkTab.home,
          ledger: ledger,
          child: AppSettingsScope(
            settings: settings,
            // The production wiring (home_routes.dart homeScreenFor) — the
            // same doors, search and position wiring the shipped S1 mounts,
            // with scope on the personal book (R1D review finding 1).
            child: Builder(
              builder: (context) =>
                  homeScreenFor(context, scopeController: scope),
            ),
          ),
        );
        // The state each capture claims to show — through the production
        // wiring, so the header carries S21's search door.
        expect(find.text('Check your recovery sheet'), findsOneWidget);
        expect(find.byIcon(Icons.search), findsOneWidget);
        if (then != null) await then(target);
        await _unmount(tester);
        await tester.pump(const Duration(milliseconds: 1));
      }
    }

    await capture('O8', person: 'Amrit Kaur', purpose: 'myself');
    await capture(
      'O8b',
      person: 'Gurpreet Sandhu',
      purpose: 'family',
      branchType: BookType.family,
      branchName: 'Sandhu Family',
      branchState: 'open',
      then: (_) async =>
          expect(find.text('Finish Sandhu Family'), findsOneWidget),
    );
    await capture(
      'O8c',
      person: 'Baldev Singh',
      purpose: 'trust',
      branchType: BookType.organization,
      branchName: 'Gurdwara Sahib, Ballowal',
      branchState: 'open',
      then: (_) async =>
          expect(find.text('Finish Gurdwara Sahib, Ballowal'), findsOneWidget),
    );
    await capture(
      'O8d',
      person: 'Baldev Singh',
      purpose: 'trust',
      branchType: BookType.organization,
      branchName: 'Gurdwara Sahib, Ballowal',
      branchState: 'done',
      then: (_) async =>
          expect(find.byIcon(Icons.check_circle), findsNWidgets(2)),
    );
    // O8e / O8f: the family row's ⋮ → Not needed, snapped after each tap.
    await capture(
      'O8b-tap',
      person: 'Gurpreet Sandhu',
      purpose: 'family',
      branchType: BookType.family,
      branchName: 'Sandhu Family',
      branchState: 'open',
      then: (target) async {
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        expect(find.text('Not needed'), findsOneWidget);
        await _snap(tester, 'S0.7__O8e${target.suffix}');
        await tester.tap(find.text('Not needed'));
        await tester.pumpAndSettle();
        expect(find.text('Undo'), findsOneWidget);
        await _snap(tester, 'S0.7__O8f${target.suffix}');
        // The SnackBar's own timer must run out inside the test.
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
      },
    );
    // The pre-tap picture duplicates O8b; it is not a state of its own.
    for (final target in RkDesignTarget.values) {
      final f = File('$rkDesignCaptureDir/S0.7__O8b-tap${target.suffix}.png');
      if (f.existsSync()) f.deleteSync();
    }
  });
}
