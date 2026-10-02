// F1-24b-17 — S7.1's inline *Create* under read-only (ADR 2026-09-24b §13;
// 13 §3.2 rows S7.1, S12.5; 07 §11 item 2 🔒).
//
// Creating an A/C from the import picker is `LocalLedger.addAccount` — the
// same envelope-writing call S2.1 and S3.1 gate — so read-only refuses it
// with the same S12.5 sheet, through ENT2's `refuseIfEntryRestricted`. Book
// full keeps its per-book scope (ADR 2026-09-05b §7). The picker and the typed
// name stay open under the sheet (drafts kept, 07 §1 rule 6).
//
// Test-honesty: [FakeImportSource.createCounterpart] appends to the fake's own
// `counterpartList`, so "no A/C was made" is the source's count, not a
// widget's claim. A gate that answered "allowed" unconditionally would let the
// create through and every `_made(source)` = 0 below would fail; the untokened
// case proves the same tap does make the A/C when nothing blocks.
// Synthetic statement only (CLAUDE.md rule 4); amounts are integer paise.
@Tags(['F1'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/import/import_routes.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../../shared/test_app.dart' show rkTallViewport;
import '../entry/restriction_support.dart';

const _csv = '''
Test Bank Ltd.

Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
02/08/2026,TEST PAYMENT ONE,"1,000.00",,"9,000.00"
''';

ParsedStatement _statement() => parseStatement(
  bytes: Uint8List.fromList(utf8.encode(_csv)),
  fileName: 'statement.csv',
  accountId: 'bank-1',
) as ParsedStatement;

const _name = 'Test new A/C';

/// A slow entitlement read, so a second tap can land before the first tap's
/// sheet rises.
final class _HeldSource extends FakeEntitlementSource {
  _HeldSource({super.entitlement});

  final hold = Completer<void>();

  @override
  Future<Entitlement> read() async {
    await hold.future;
    return super.read();
  }
}

/// How many A/Cs the source was asked to create.
int _made(FakeImportSource source) =>
    source.counterpartList.where((c) => c.name == _name).length;

Future<(FakeImportSource, String)> _pumpAndType(
  WidgetTester tester, {
  EntitlementSource? entitlement,
  FakeSyncClient? sync,
}) async {
  final statement = _statement();
  final source = FakeImportSource();
  await pumpUnderEntitlement(
    tester,
    ImportScope(
      source: source,
      filePort: FakeStatementFilePort(),
      bookId: 'book-1',
      child: ImportInboxScreen(statement: statement),
    ),
    entitlement: entitlement,
    sync: sync,
    viewport: rkTallViewport,
  );
  final id = '${statement.accountId}#${statement.lines.first.rowIndex}';
  await tester.tap(find.byKey(ImportInboxKeys.choose(id)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(ImportInboxKeys.search(id)), _name);
  await tester.pumpAndSettle();
  return (source, id);
}

Finder _createTile(WidgetTester tester) => find.text(
  AppLocalizations.of(tester.element(find.byType(Scaffold).first))
      .importInboxCreate(_name),
);

void main() {
  group('F1-24b-17 S7.1 inline create appends an envelope: read-only '
      'refuses it', () {
    testWidgets('F1-24b-17 lapsed: the read-only sheet rises, no A/C is made, '
        'and the picker still holds the typed name', (tester) async {
      final (source, id) = await _pumpAndType(
        tester,
        entitlement: lapsedSource(),
      );

      await tester.tap(_createTile(tester));
      await settleIo(tester);

      expectReadOnlySheet(tester);
      expect(_made(source), 0);

      await dismissRestrictionSheet(tester);
      // Draft kept (07 §1 rule 6): the picker is still open on the same text,
      // and the line is still unanswered.
      expect(find.byKey(ImportInboxKeys.search(id)), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(ImportInboxKeys.search(id)),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        _name,
      );
      expect(_createTile(tester), findsOneWidget);
      expect(_made(source), 0);
      await unmountTree(tester);
    });

    testWidgets('F1-24b-17 untokened (Free, never locked): the same tap makes '
        'the A/C and answers the line with it', (tester) async {
      final (source, _) = await _pumpAndType(tester);

      await tester.tap(_createTile(tester));
      await settleIo(tester);

      expect(raisedSheetKind(tester), isNull);
      expect(_made(source), 1);
      final l = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );
      expect(find.text(l.importInboxAnswerOut(_name)), findsOneWidget);
      await unmountTree(tester);
    });

    testWidgets('F1-24b-17 this book is full: the book-full sheet, no A/C '
        'made', (tester) async {
      final sync = FakeSyncClient()..fullBooks.add('book-1');
      final (source, _) = await _pumpAndType(tester, sync: sync);

      await tester.tap(_createTile(tester));
      await settleIo(tester);

      expect(raisedSheetKind(tester), RkRestrictionKind.bookFull);
      expect(_made(source), 0);
      // Dismissed, still nothing written: the refusal is not a delay.
      await dismissRestrictionSheet(tester);
      expect(_made(source), 0);
      await unmountTree(tester);
    });

    testWidgets('F1-24b-17 lapsed with a slow read: a double tap raises one '
        'sheet and makes nothing', (tester) async {
      final held = _HeldSource(entitlement: lapsedSource().entitlement);
      final (source, _) = await _pumpAndType(tester, entitlement: held);

      // Two taps before any frame — only the screen's re-entry guard stops a
      // second sheet.
      await tester.tap(_createTile(tester));
      await tester.tap(_createTile(tester));
      await tester.pump();
      held.hold.complete();
      await settleIo(tester);

      expect(find.byType(RkBlockedEntrySheet), findsOneWidget);
      expect(_made(source), 0);
      // Dismissed, still nothing written: the refusal is not a delay.
      await dismissRestrictionSheet(tester);
      expect(_made(source), 0);
      await unmountTree(tester);
    });
  });
}
