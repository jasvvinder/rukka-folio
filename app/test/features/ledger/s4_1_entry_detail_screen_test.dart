// F1 widget tests for S4.1 entry detail (13 §3.2 row S4.1, 07 §6, 02 §5,
// ADR 2026-09-05b §4).
//
// S4.1 is a CONSUMER surface (02 §10 🔒): *Money in / Money out*, never Dr/Cr
// — that vocabulary belongs to S4, the trial balance and the exports. The
// figures are the same signed integer paise on both surfaces; only the words
// change, and the posting never bends to either.
//
// The two ids:
//   F1-07-60 — audit trail, who entered, photo, both-vocabulary rendering.
//   F1-07-61 — the amend / reverse actions and the held state.
@Tags(['F1'])
library;

import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/entry_detail.dart';
import 'package:rukka_folio/features/ledger/screens/s4_1_entry_detail_screen.dart';
import 'package:rukka_folio/shared/format/money_format.dart';

import '../../shared/test_app.dart';

/// A viewport tall enough that the detail's `ListView` builds every section.
void tallViewport(WidgetTester tester, {double width = 500}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Tears the tree down *inside* the test, so drift's zero-duration cleanup
/// timer fires before the binding's pending-timer invariant runs. The cancel
/// is never awaited — an awaited Drift subscription cancel deadlocks inside
/// `flutter_test`'s fake-async zone.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// The seeded *Money out* entry (Diesel paid from cash).
Entry moneyOutOf(SeededLedger seed) =>
    seed.entries.firstWhere((e) => e.kind == EntryKind.moneyOut);

/// Every [MoneyText] on screen, in tree order.
List<MoneyText> moneyOn(WidgetTester tester) =>
    tester.widgetList<MoneyText>(find.byType(MoneyText)).toList();

void main() {
  group('S4.1 entry detail (13 §3.2, 07 §6)', () {
    testWidgets(
      'F1-07-60 shows the amount, both sides, the date, the note, who '
      'entered it and the bill-photo section',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final entry = moneyOutOf(seed);
        await pumpRk(
          tester,
          EntryDetailScreen(entryId: entry.id),
          ledger: seed.ledger,
        );

        // The verb heads the screen, then both sides by name.
        expect(find.text('Money out'), findsWidgets);
        expect(find.text('Both sides'), findsOneWidget);
        expect(find.text('Cash in hand'), findsOneWidget);
        expect(find.text('Diesel'), findsOneWidget);

        // The user's own words, the date, and the author — this device's own
        // user, so *you* rather than a uuid.
        expect(find.text('Diesel A/C'), findsOneWidget);
        expect(find.text('Date'), findsOneWidget);
        expect(find.text('Entered by you'), findsOneWidget);
        expect(find.textContaining(seed.ledger.identity.userId), findsNothing);

        // The bill-photo section states the empty case rather than vanishing.
        expect(find.text('Bill photo'), findsOneWidget);
        expect(find.text('No bill photo on this entry'), findsOneWidget);

        // The audit trail, with the append-only rule in plain words.
        expect(find.text('History'), findsOneWidget);
        expect(find.textContaining('Saved'), findsWidgets);
        expect(
          find.text('Nothing is ever rubbed out. Every version stays here.'),
          findsOneWidget,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-60 speaks the consumer vocabulary only — Money in / Money out, '
      'never Dr/Cr (02 §10 🔒)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          EntryDetailScreen(entryId: moneyOutOf(seed).id),
          ledger: seed.ledger,
        );

        expect(find.text('Dr'), findsNothing);
        expect(find.text('Cr'), findsNothing);
        final money = moneyOn(tester);
        expect(money, isNotEmpty);
        expect(
          money.every((m) => m.vocabulary == Vocabulary.consumer),
          isTrue,
          reason: 'a professional-vocabulary amount leaked onto S4.1 (02 §10)',
        );

        // …and the figures are the engine's integer paise, not a re-derived
        // double: the money side of the seeded Money out is −2,400.00.
        expect(money.map((m) => m.paise), contains(-240000));
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-60 the trail links the chain both ways and the original is never '
      'mutated (02 §5, CLAUDE.md rule 2)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final original = moneyOutOf(seed);
        final amended = (await tester.runAsync(
          () => seed.ledger.amend(original.id, note: 'Diesel for the tractor'),
        ))!;

        // The head shows the new note and points back at what it corrects.
        await pumpRk(
          tester,
          EntryDetailScreen(entryId: amended.id),
          ledger: seed.ledger,
        );
        expect(find.text('Diesel for the tractor'), findsOneWidget);
        expect(find.text('Corrects an earlier version'), findsOneWidget);
        await unmount(tester);

        // The original still carries its own note — append-only: the earlier
        // version is left exactly as it was posted — and says it was replaced.
        await pumpRk(
          tester,
          EntryDetailScreen(entryId: original.id),
          ledger: seed.ledger,
        );
        expect(find.text('Diesel A/C'), findsOneWidget);
        expect(find.text('Replaced'), findsOneWidget);
        expect(
          find.text('A newer version has replaced this one'),
          findsOneWidget,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-60 renders in EN, PA and HI at 200% on a 360x800 phone',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final seed = await seedSoloLedger();
          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: EntryDetailScreen(entryId: moneyOutOf(seed).id),
            ),
            ledger: seed.ledger,
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      },
    );

    testWidgets('F1-07-60 an unknown id is a stated fact with a way out', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const EntryDetailScreen(entryId: 'no-such-entry'),
        ledger: seed.ledger,
      );
      expect(find.text("This entry isn't on this phone"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('S4.1 corrections and the held state (02 §5, ADR 2026-09-05b §4)', () {
    testWidgets(
      'F1-07-61 Reverse this posts the mirror entry; both stay in history and '
      'the original is not edited',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final original = moneyOutOf(seed);
        await pumpRk(
          tester,
          EntryDetailScreen(entryId: original.id),
          ledger: seed.ledger,
        );

        await tester.tap(find.text('Reverse this'));
        await tester.pumpAndSettle();
        // A guided sheet, never a freeform ledger screen (02 §5).
        expect(find.text('Reverse this entry'), findsOneWidget);
        expect(
          find.textContaining('the original is never rubbed out'),
          findsOneWidget,
        );
        await tester.tap(find.text('Post the reversal'));
        await tester.pumpAndSettle();

        // The engine has a second entry carrying refs.reverses…
        final reversal = (await tester.runAsync(
          () async =>
              (await seed.ledger.db
                      .customSelect(
                        'SELECT id FROM entries_p WHERE reverses = ?',
                        variables: [Variable.withString(original.id)],
                      )
                      .get())
                  .single
                  .read<String>('id'),
        ))!;
        expect(reversal, isNot(original.id));
        // …which the facade answers for S4.1 (ADR 2026-09-09 §4 consequences:
        // no screen reaches into the Drift tables itself). `reversalOf` is
        // the only way entry_detail learns what reversed an entry.
        expect(
          await tester.runAsync(() => seed.ledger.reversalOf(original.id)),
          reversal,
        );
        expect(
          await tester.runAsync(() => seed.ledger.reversalOf(reversal)),
          isNull,
          reason: 'a reversal is not itself reversed',
        );
        await tester.pumpAndSettle();

        // …and the original, unchanged, now reads as reversed, with both
        // actions disabled and the reason on screen (13 §4.3).
        expect(find.text('Reversed'), findsOneWidget);
        expect(find.text('This entry is already reversed'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Correct this'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Reverse this'),
              )
              .onPressed,
          isNull,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-61 Correct this posts an amendment — a new entry, the old one '
      'kept (02 §5)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final original = moneyOutOf(seed);
        await pumpRk(
          tester,
          EntryDetailScreen(entryId: original.id),
          ledger: seed.ledger,
        );

        await tester.tap(find.text('Correct this'));
        await tester.pumpAndSettle();
        expect(find.text('Correct this entry'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField).last,
          'Diesel for the tractor',
        );
        await tester.tap(find.text('Save the correction'));
        await tester.pumpAndSettle();

        final detail = (await tester.runAsync(
          () => loadEntryDetail(seed.ledger, original.id),
        ))!;
        expect(detail, isA<EntryDetailPosted>());
        final posted = detail as EntryDetailPosted;
        // Append-only: the version on screen still holds its own note, and a
        // *new* entry carries the correction.
        expect(posted.view.note, 'Diesel A/C');
        expect(posted.isReplaced, isTrue);
        expect(posted.correctedBy!.note, 'Diesel for the tractor');
        expect(posted.correctedBy!.amends, original.id);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-61 a replaced version cannot be corrected again — the reason is '
      'on screen and the newest version is one tap away (02 §5)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final original = moneyOutOf(seed);
        final amended = (await tester.runAsync(
          () => seed.ledger.amend(original.id, note: 'Diesel for the tractor'),
        ))!;
        final opened = <String>[];
        await pumpRk(
          tester,
          EntryDetailScreen(entryId: original.id, onOpenEntry: opened.add),
          ledger: seed.ledger,
        );

        // Amend chains are linear: only the head is amendable (02 §5).
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Correct this'),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.text('Open the newest version to correct it'),
          findsOneWidget,
        );

        // …and the trail is not a dead end (07 §1 rule 2).
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(opened, [amended.id]);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-61 a held entry waits for the entry it changes — not an error, '
      'not counted (ADR 2026-09-05b §4)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        const heldId = 'held-amendment-1';
        final target = moneyOutOf(seed).id;
        // A correction that reached this phone before its target: the mirror
        // holds the envelope, the projector never sees it, `entries_p` has no
        // row for it. This is the shape Recompute writes (recompute.dart §2).
        await tester.runAsync(
          () => seed.ledger.db
              .into(seed.ledger.db.envelopesLocal)
              .insert(
                EnvelopesLocalCompanion.insert(
                  envelopeId: 'env-$heldId',
                  bookId: seed.bookId,
                  objectId: heldId,
                  objectType: 'entry',
                  keyVersion: 1,
                  hlc: 1,
                  authorDevice: 'another-device',
                  authorSeq: 1,
                  envelopeBlob: Uint8List(0),
                  blobHash: Uint8List(0),
                  held: const Value(1),
                  heldFor: Value(target),
                ),
              ),
        );

        await pumpRk(
          tester,
          const EntryDetailScreen(entryId: heldId),
          ledger: seed.ledger,
        );

        // The facade answers *is this envelope held, and what is it waiting
        // for* — `heldFor` — so the screen never queries the mirror itself.
        final held = await tester.runAsync(() => seed.ledger.heldFor(heldId));
        expect(held, isNotNull);
        expect(held!.objectId, heldId);
        expect(held.waitingForId, target);
        expect(
          await tester.runAsync(() => seed.ledger.heldFor(target)),
          isNull,
          reason: 'a projected entry is not held',
        );

        expect(find.text('Waiting for the entry this changes'), findsOneWidget);
        expect(find.text('Waiting'), findsOneWidget);
        // Held is waiting, not failure: no error wording, no retry button, and
        // no amount — nothing is counted yet.
        expect(find.textContaining("Couldn't"), findsNothing);
        expect(find.text('Try again'), findsNothing);
        expect(find.byType(MoneyText), findsNothing);
        await unmount(tester);
      },
    );
  });
}
