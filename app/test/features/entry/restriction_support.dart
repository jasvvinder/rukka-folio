// Shared support for F1-24b-7 — read-only blocks every new envelope (ADR
// 2026-09-24b §13). Each feature's test pumps its own surface through
// [pumpUnderEntitlement] and asserts with the helpers here, so every path is
// judged by the same three facts: the S12.5 read-only sheet rose, **no
// envelope was appended** (counted in the real ledger's `envelopes_local`),
// and the draft is still on screen after dismiss.
//
// Test-honesty: the count is taken from the real in-memory ledger, so a gate
// that returned null unconditionally would let the write through and every
// "nothing appended" expectation would fail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../../shared/test_app.dart';

/// A synthetic entitlement reading (CLAUDE.md rule 4 — no real tenant).
Entitlement entitlementReading(
  EntitlementGraceKind grace, {
  EntitlementSourceKind source = EntitlementSourceKind.fresh,
}) => Entitlement(
  tenantId: 't-synthetic',
  plan: RkPlan.family,
  limits: rkTierFor(RkPlan.family).limits,
  periodEnd: DateTime(2026, 9, 1),
  graceKind: grace,
  source: source,
  activeMembers: 1,
);

/// The server has said lapsed, on a token this phone holds fresh.
FakeEntitlementSource lapsedSource() => FakeEntitlementSource(
  entitlement: entitlementReading(EntitlementGraceKind.lapsed),
);

/// Pumps [child] as the home of an app whose [EntitlementScope] sits **above
/// the Navigator** — where the shell will mount it — so a modal sheet's own
/// context (a sibling of the home route, not a child of it) still reads it.
Future<void> pumpUnderEntitlement(
  WidgetTester tester,
  Widget child, {
  LocalLedger? ledger,
  EntitlementSource? entitlement,
  FakeSyncClient? sync,
  Size viewport = const Size(400, 1200),
}) async {
  rkViewport(tester, viewport);
  final app = EntitlementScope(
    source: entitlement ?? const UntokenedEntitlementSource(),
    child: MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: rkLocalizationsDelegates,
      theme: rkTheme(Brightness.light),
      home: child,
    ),
  );
  final db = ledger?.db ?? (await tester.runAsync(openTestDb))!;
  await tester.pumpWidget(
    RkScope(
      db: db,
      sync: sync ?? FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: (ledger?.keys as FakeKeyStore?) ?? FakeKeyStore(),
      now: ledger?.now ?? testNow,
      child: ledger == null ? app : LedgerScope(ledger: ledger, child: app),
    ),
  );
  await settleIo(tester);
}

/// Real event-loop turns: a ledger write is sqlite I/O, which `pumpAndSettle`
/// alone never lets finish.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}

/// Every envelope this device has authored or received, from the real ledger.
Future<int> envelopeCount(WidgetTester tester, LocalLedger ledger) async {
  final row = (await tester.runAsync(
    () => ledger.db
        .customSelect('SELECT COUNT(*) AS n FROM envelopes_local')
        .getSingle(),
  ))!;
  return row.read<int>('n');
}

/// Which S12.5 kind the raised sheet narrates, or null when none is up.
RkRestrictionKind? raisedSheetKind(WidgetTester tester) {
  final f = find.byType(RkBlockedEntrySheet);
  if (f.evaluate().isEmpty) return null;
  return tester.widget<RkBlockedEntrySheet>(f).kind;
}

/// The S12.5 read-only sheet is up, in its own words (never book full's).
void expectReadOnlySheet(WidgetTester tester) {
  expect(raisedSheetKind(tester), RkRestrictionKind.readOnly);
  final l10n = AppLocalizations.of(
    tester.element(find.byType(RkBlockedEntrySheet)),
  );
  expect(find.text(l10n.subscriptionSheetReadOnlyTitle), findsOneWidget);
  expect(find.text(l10n.subscriptionSheetBookFullTitle), findsNothing);
}

/// Dismisses the S12.5 sheet and lets the screen underneath settle.
Future<void> dismissRestrictionSheet(WidgetTester tester) async {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(RkBlockedEntrySheet)),
  );
  await tester.tap(find.text(l10n.subscriptionSheetDismiss));
  await tester.pumpAndSettle();
  expect(find.byType(RkBlockedEntrySheet), findsNothing);
}

/// Tears the tree down inside the test so drift's stream cleanup timer fires
/// before the binding's pending-timer invariant runs.
Future<void> unmountTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
