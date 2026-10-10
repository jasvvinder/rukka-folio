// RESKIN1 round 2, slice R2C — audit captures for statement import (ADR
// 2026-10-05 §2; ADR 2026-10-10b §1 phase 1 — an audit, not a build). Pair
// with `python3 scripts/design_match.py pair <S-id>`.
//
// S7   — canvas 8 draws it as three frames: *S7.0a Choose a file*, *S7.0b
//        Column mapping*, *S7.0c Duplicates skipped · stated as work done*.
// S7.1 — canvas 8 *Import inbox · four row states*.
// S7.2 — canvas 8 *Balance check · passing / matched / failing*.
//
// TEST HONESTY: every screen is built with the constructor arguments its
// production route passes (import_routes.dart: `ImportScreen(onParsed:)`,
// then `ImportMappingScreen(statement:, account:, bytes:, onContinue:,
// onAnotherFile:)`, then `ImportInboxScreen(statement:)`; S7.2 is
// `ImportBalanceCheckScreen(check:)`, pushed from S7.1).
//
// ⚠️ SPEC: production mounts **no `ImportScope`** (bootstrap.dart builds no
// `LedgerImportSource`; `grep -rn ImportScope app/lib` finds only the import
// feature) and its entitlement is untokened (bootstrap.dart:1217), so the S7
// route opens on the error state (`S7__production`) and S7.0a–S7.2 are not
// reachable in a shipped build. Every capture after `S7__production` mounts
// the ImportScope production *would* need — `LedgerImportSource` over a real
// seeded `LocalLedger` — and an entitlement that includes
// `statement_import`, and is therefore a state production cannot reach today.
//
// ⚠️ SPEC: `LedgerImportSource.alreadyImported` returns `const {}`
// (ledger_import_source.dart), so S7.0c's *12 lines already imported —
// skipped* cannot be produced even with the scope. `S7__duplicates-skipped`
// uses the feature's `FakeImportSource(alreadyImported:)` to show what the
// screen draws for it; `S7__duplicates` is what the ledger door produces.
// Amounts and names are synthetic (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/import/import_routes.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

// ---- fixtures ---------------------------------------------------------------

/// An Indian Bank-shaped statement: separate withdrawal and deposit columns
/// and a running balance, the shape canvas 8 draws.
const _csv = '''
Indian Bank
Account: XXXXXX0192

Txn Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
02/08/2026,UPI/DR/425634789012/VERMA DAI/TSTB/vermadairy@oktst,"20,000.00",,"1,00,000.00"
04/08/2026,NEFT MEHTA TRADERS 4471,,"31,000.00","1,31,000.00"
05/08/2026,BILLPAY BHARAT POWER 88213,"2,450.00",,"1,28,550.00"
11/08/2026,IMPS TO SBI 4471 SELF,"50,000.00",,"78,550.00"
''';

Uint8List _bytes() => Uint8List.fromList(utf8.encode(_csv));

const _file = 'aug-statement.csv';

ParsedStatement _parse(
  String accountId, {
  Set<LineIdentity> already = const {},
}) => parseStatement(
  bytes: _bytes(),
  fileName: _file,
  accountId: accountId,
  alreadyImported: already,
) as ParsedStatement;

/// A reading whose token includes `statement_import` (ADR 2026-09-25 §5–§6).
EntitlementSource _importIncluded() => FakeEntitlementSource(
  entitlement: Entitlement(
    tenantId: 't-synthetic',
    plan: RkPlan.family,
    limits: rkTierFor(RkPlan.family).limits,
    periodEnd: null,
    graceKind: EntitlementGraceKind.none,
    source: EntitlementSourceKind.fresh,
    activeMembers: 1,
    features: [RkFeature.statementImport.wire],
  ),
);

/// The ImportScope production would need (⚠️ SPEC above).
Widget _scoped(SeededLedger seed, Widget child, {ImportSource? source}) =>
    ImportScope(
      source: source ?? LedgerImportSource(seed.ledger),
      filePort: FakeStatementFilePort(),
      bookId: seed.bookId,
      child: child,
    );

int _seq = 0;

ImportAccount _account(SeededLedger seed) => ImportAccount(
  id: seed.bankId,
  name: 'SBI Saving',
  bankKey: LedgerImportSource.bankKeyOf('SBI Saving'),
  subtitle: null,
);

/// S7.0b exactly as import_routes.dart pushes it.
Widget _mapping(SeededLedger seed, ParsedStatement statement) =>
    ImportMappingScreen(
      key: ValueKey('r2c-map-${_seq++}'),
      statement: statement,
      account: _account(seed),
      bytes: _bytes(),
      onContinue: (_) {},
      onAnotherFile: () {},
    );

/// A blank route with one door that pushes [child]: S7 itself is pushed from
/// the S2 header (s2_add_entry_screen.dart, `push(ImportPaths.root)`), and
/// S7.0b, S7.1 and S7.2 are pushed after it (import_routes.dart,
/// s7_1_inbox_screen.dart), so every app bar carries the back button a root
/// mount would not draw.
class _PushBase extends StatelessWidget {
  const _PushBase({required this.child});

  static const door = Key('r2c-push-door');

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: door,
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => child)),
        child: const SizedBox.square(dimension: 48),
      ),
    ),
  );
}

// ---- capture plumbing -------------------------------------------------------

Finder _has(String text) => find.textContaining(text, findRichText: true);

Future<void> _snap(
  WidgetTester tester,
  String name, {
  Set<String> platformFaces = const {},
}) async {
  final view = tester.binding.renderViews.first;
  // The face check of rkDesignCapture (ADR 2026-10-05 §2 🔒), run on the
  // frame this PNG is written from, not on the deleted '-pre' frame.
  final unfaced = rkUnfacedText(
    view,
    allowed: {...rkDesignFaces, ...platformFaces},
  );
  if (unfaced.isNotEmpty) {
    fail(
      'design capture $name draws text outside the design faces '
      "(ADR 2026-10-05 §2):\n${unfaced.join('\n')}",
    );
  }
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Captures [state] of [sid] on both targets: mounts, lets the real I/O land,
/// runs [act], checks [expectState] and snaps. The pre-load picture is
/// deleted.
Future<void> _shoot(
  WidgetTester tester, {
  required String sid,
  required String state,
  required Future<(Widget, LocalLedger?)> Function() setup,
  required void Function() expectState,
  Future<void> Function()? act,
  bool push = false,
}) async {
  for (final target in RkDesignTarget.values) {
    final (child, ledger) = (await tester.runAsync(setup))!;
    final first = '$state-pre';
    await rkDesignCapture(
      tester,
      sid: sid,
      state: first,
      target: target,
      ledger: ledger,
      platformFaces: const {'monospace'},
      child: push ? _PushBase(child: child) : child,
    );
    debugDefaultTargetPlatformOverride = target.platform;
    try {
      await _settle(tester);
      if (push) {
        await tester.tap(find.byKey(_PushBase.door));
        await _settle(tester);
      }
      if (act != null) await act();
      await _settle(tester);
      expectState();
      await _snap(
        tester,
        '${sid}__$state${target.suffix}',
        platformFaces: const {'monospace'},
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    final pre = File('$rkDesignCaptureDir/${sid}__$first${target.suffix}.png');
    if (pre.existsSync()) pre.deleteSync();
    await _unmount(tester);
  }
}

void main() {
  testWidgets('F1-1010r2C-1 design capture S7 as production routes it '
      '(no ImportScope: the error state)', (tester) async {
    await _shoot(
      tester,
      sid: 'S7',
      state: 'production',
      push: true,
      setup: () async => (ImportScreen(onParsed: (_, _, _) {}), null),
      expectState: () =>
          expect(_has('Couldn’t open your bank A/Cs.'), findsOneWidget),
    );
  });

  testWidgets('F1-1010r2C-2 design capture S7.0a choose a file '
      '(⚠️ SPEC: scope + statement_import, unreachable today)', (tester) async {
    await _shoot(
      tester,
      sid: 'S7',
      state: 'choose-file',
      push: true,
      setup: () async {
        final seed = await seedSoloLedger();
        return (
          _scoped(
            seed,
            ImportScreen(
              entitlement: _importIncluded(),
              onParsed: (_, _, _) {},
            ),
          ),
          seed.ledger,
        );
      },
      expectState: () {
        expect(_has('2 · Which file?'), findsOneWidget);
        expect(_has('SBI Saving'), findsWidgets);
      },
    );
  });

  testWidgets('F1-1010r2C-3 design capture S7.0b column mapping '
      '(⚠️ SPEC: unreachable today)', (tester) async {
    await _shoot(
      tester,
      sid: 'S7',
      state: 'mapping',
      push: true,
      setup: () async {
        final seed = await seedSoloLedger();
        return (
          _scoped(seed, _mapping(seed, _parse(seed.bankId))),
          seed.ledger,
        );
      },
      expectState: () => expect(_has('Check the columns'), findsOneWidget),
    );
  });

  testWidgets('F1-1010r2C-4 design capture S7.0c after confirming, through '
      'the ledger door (nothing skipped: alreadyImported is empty)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S7',
      state: 'duplicates',
      push: true,
      setup: () async {
        final seed = await seedSoloLedger();
        return (
          _scoped(seed, _mapping(seed, _parse(seed.bankId))),
          seed.ledger,
        );
      },
      act: () async {
        await tester.dragUntilVisible(
          _has('That’s right'),
          find.byType(Scrollable).last,
          const Offset(0, -200),
        );
        await tester.tap(_has('That’s right'));
      },
      expectState: () => expect(
        _has('Nothing in this file was imported before.'),
        findsOneWidget,
      ),
    );
  });

  testWidgets('F1-1010r2C-5 design capture S7.0c duplicates skipped '
      '(⚠️ SPEC: FakeImportSource — the ledger door never skips)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S7',
      state: 'duplicates-skipped',
      push: true,
      setup: () async {
        final seed = await seedSoloLedger();
        final first = _parse(seed.bankId);
        final already = {
          for (final line in first.lines.take(2))
            LineIdentity.of(line, accountId: seed.bankId),
        };
        return (
          _scoped(
            seed,
            _mapping(seed, _parse(seed.bankId, already: already)),
            source: FakeImportSource(alreadyImported: already),
          ),
          seed.ledger,
        );
      },
      act: () async {
        await tester.dragUntilVisible(
          _has('That’s right'),
          find.byType(Scrollable).last,
          const Offset(0, -200),
        );
        await tester.tap(_has('That’s right'));
      },
      expectState: () =>
          expect(_has('2 lines already imported — skipped'), findsOneWidget),
    );
  });

  testWidgets('F1-1010r2C-6 design capture S7.1 import inbox through the '
      'ledger door (⚠️ SPEC: unreachable today)', (tester) async {
    await _shoot(
      tester,
      sid: 'S7.1',
      state: 'default',
      push: true,
      setup: () async {
        final seed = await seedSoloLedger();
        return (
          _scoped(seed, ImportInboxScreen(statement: _parse(seed.bankId))),
          seed.ledger,
        );
      },
      expectState: () => expect(_has('Import inbox'), findsOneWidget),
    );
  });

  for (final (n, state) in [
    (7, ImportBalanceOutcome.passing),
    (8, ImportBalanceOutcome.matched),
    (9, ImportBalanceOutcome.failing),
  ]) {
    testWidgets('F1-1010r2C-$n design capture S7.2 balance check '
        '${state.name}', (tester) async {
      await _shoot(
        tester,
        sid: 'S7.2',
        state: state.name,
        push: true,
        setup: () async {
          final statement = _parse('bank-1');
          // The statement's own ends, read through the production check.
          final ends = ImportBalanceCheck.of(
            statement,
            ledgerOpeningPaise: 0,
            ledgerClosingPaise: 0,
          );
          final open = ends.statementOpeningPaise!;
          final close = ends.statementClosingPaise!;
          final check = switch (state) {
            ImportBalanceOutcome.passing => ImportBalanceCheck.of(
              statement,
              ledgerOpeningPaise: open,
              ledgerClosingPaise: open,
            ),
            ImportBalanceOutcome.matched => ImportBalanceCheck.of(
              statement,
              ledgerOpeningPaise: open,
              ledgerClosingPaise: close,
            ),
            _ => ImportBalanceCheck.of(
              statement,
              ledgerOpeningPaise: open - 420000,
              ledgerClosingPaise: open - 420000,
            ),
          };
          expect(check.outcome, state);
          return (ImportBalanceCheckScreen(check: check), null);
        },
        expectState: () =>
            expect(find.byKey(ImportBalanceKeys.verdict), findsOneWidget),
      );
    });
  }
}
