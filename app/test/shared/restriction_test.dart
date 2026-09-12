@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction_copy.dart';

import 'test_app.dart';

/// A host that owns a draft, exactly as S2 will: a filled field plus the Save
/// that raises the sheet. The sheet must never reach into it.
class _DraftHost extends StatefulWidget {
  const _DraftHost({required this.kind, this.onExport});

  final RkRestrictionKind kind;
  final VoidCallback? onExport;

  @override
  State<_DraftHost> createState() => _DraftHostState();
}

class _DraftHostState extends State<_DraftHost> {
  final _note = TextEditingController(text: 'Diesel A/C');
  RkBlockedEntryOutcome? outcome;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        // The draft: an amount the user typed, and a note.
        const Text('12,340'),
        TextField(controller: _note),
        Builder(
          builder: (inner) => TextButton(
            onPressed: () async {
              final result = await showRkBlockedEntrySheet(
                inner,
                kind: widget.kind,
                copy: widget.kind.copy(inner),
                onExport: widget.onExport,
              );
              if (mounted) setState(() => outcome = result);
            },
            child: const Text('Save'),
          ),
        ),
      ],
    ),
  );
}

Widget _banner(
  RkRestrictionKind kind, {
  VoidCallback? onAction,
  VoidCallback? onExport,
}) => Scaffold(
  // The banner is persistent and sits above scrolling content, so the host —
  // never the banner — owns the scroll. At 200 % scale in Gurmukhi and
  // Devanagari the banner is genuinely taller than a 360×800 viewport; what
  // 07 §18 forbids is truncation, and the words must wrap in full.
  body: SingleChildScrollView(
    child: Builder(
      builder: (context) => RkRestrictionBanner(
        kind: kind,
        copy: kind.copy(context),
        onAction: onAction ?? () {},
        onExport: onExport,
      ),
    ),
  ),
);

void main() {
  group('S12.5 read-only / book-full pattern (07 §20, 13 §3.2, §4.2)', () {
    testWidgets(
      'F1-07-78 the banner states the fact with an icon beside the words — colour is never alone (07 §1 rule 3)',
      (tester) async {
        for (final kind in RkRestrictionKind.values) {
          await pumpRk(tester, _banner(kind));
          final context = tester.element(find.byType(RkRestrictionBanner));
          final copy = kind.copy(context);
          expect(find.text(copy.bannerTitle), findsOneWidget);
          expect(find.text(copy.bannerBody), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(RkRestrictionBanner),
              matching: find.byType(Icon),
            ),
            findsOneWidget,
            reason:
                '$kind lost its icon — tint would be carrying meaning '
                'alone',
          );
          // No dead end: the banner always offers a way forward (07 §1 rule 6).
          expect(find.text(copy.bannerActionLabel), findsOneWidget);
        }
      },
    );

    testWidgets(
      'F1-07-78 two graces, two copies: offline grace never says the plan lapsed (13 §5 🔒, ADR 2026-09-05g §4)',
      (tester) async {
        await pumpRk(tester, _banner(RkRestrictionKind.offlineGrace));
        var context = tester.element(find.byType(RkRestrictionBanner));
        final offline = RkRestrictionKind.offlineGrace.copy(context);
        final readOnly = RkRestrictionKind.readOnly.copy(context);

        // 07 §20 🔒 names this line exactly.
        expect(offline.bannerTitle, 'Connect once to keep entering');
        for (final line in [offline.bannerTitle, offline.bannerBody]) {
          expect(
            line.toLowerCase(),
            isNot(anyOf(contains('lapse'), contains('plan'))),
            reason:
                'offline grace is device-local; the server has not said '
                'lapsed',
          );
        }
        // ...and it is a genuinely different copy set, not the read-only one.
        expect(offline.bannerTitle, isNot(readOnly.bannerTitle));
        expect(offline.bannerBody, isNot(readOnly.bannerBody));
        expect(offline.bannerActionLabel, isNot(readOnly.bannerActionLabel));

        // The read-only banner is the one that may speak of the plan.
        await pumpRk(tester, _banner(RkRestrictionKind.readOnly));
        context = tester.element(find.byType(RkRestrictionBanner));
        expect(find.text(readOnly.bannerTitle), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-78 offline grace blocks nothing; read-only and book full block entry only, never export',
      (tester) async {
        expect(RkRestrictionKind.offlineGrace.blocksEntry, isFalse);
        expect(RkRestrictionKind.readOnly.blocksEntry, isTrue);
        expect(RkRestrictionKind.bookFull.blocksEntry, isTrue);
        for (final kind in RkRestrictionKind.values) {
          expect(kind.blocksExport, isFalse, reason: '$kind blocked export');
        }
      },
    );

    testWidgets(
      'F1-07-78 read-only names reading, exporting AND closing; book full promises only reading and exports (DESIGN-PACK §11 S12.5 🔒, ADR 2026-09-05g §3)',
      (tester) async {
        await pumpRk(tester, _banner(RkRestrictionKind.readOnly));
        final context = tester.element(find.byType(RkRestrictionBanner));
        final readOnly = RkRestrictionKind.readOnly.copy(context);
        final bookFull = RkRestrictionKind.bookFull.copy(context);

        // A lapse stops entry only — reading, exporting and closing continue
        // (07 §20 S12.4).
        for (final line in [readOnly.bannerBody, readOnly.sheetStillWorks]) {
          expect(line, contains('read'));
          expect(line, contains('export'));
          expect(line, contains('close'));
        }
        // A full book cannot accept the envelopes a close writes, so the
        // book-full copy must not promise it.
        for (final line in [bookFull.bannerBody, bookFull.sheetStillWorks]) {
          expect(line.toLowerCase(), contains('read'));
          expect(line.toLowerCase(), contains('export'));
          expect(line.toLowerCase(), isNot(contains('clos')));
        }
      },
    );

    for (final kind in const [
      RkRestrictionKind.readOnly,
      RkRestrictionKind.bookFull,
    ]) {
      testWidgets(
        'F1-07-78 the blocked-entry sheet for ${kind.name} says what is blocked, what still works, and offers S12.1',
        (tester) async {
          await pumpRk(tester, _DraftHost(kind: kind));
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          final context = tester.element(find.byType(RkBlockedEntrySheet));
          final copy = kind.copy(context);
          expect(find.text(copy.sheetTitle), findsOneWidget);
          expect(find.text(copy.sheetBlocked), findsOneWidget);
          expect(find.text(copy.sheetStillWorks), findsOneWidget);
          // The route on: S12.1 Plans (13 §3.2 row S12.5).
          expect(find.text(copy.sheetActionLabel), findsOneWidget);
          expect(find.text(copy.sheetDismissLabel), findsOneWidget);
        },
      );

      testWidgets(
        'F1-07-78 dismissing the ${kind.name} sheet returns to a STILL-FILLED screen — the draft is preserved (07 §5 🔒, ADR 2026-09-05f §B)',
        (tester) async {
          await pumpRk(tester, _DraftHost(kind: kind));
          expect(find.text('12,340'), findsOneWidget);
          expect(find.text('Diesel A/C'), findsOneWidget);

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          final copy = kind.copy(
            tester.element(find.byType(RkBlockedEntrySheet)),
          );
          await tester.tap(find.text(copy.sheetDismissLabel));
          await tester.pumpAndSettle();

          expect(find.byType(RkBlockedEntrySheet), findsNothing);
          // Every part of the draft is exactly where it was.
          expect(find.text('12,340'), findsOneWidget);
          expect(find.text('Diesel A/C'), findsOneWidget);
          final host = tester.state<_DraftHostState>(find.byType(_DraftHost));
          expect(host.outcome, RkBlockedEntryOutcome.dismissed);
          expect(host._note.text, 'Diesel A/C');
        },
      );

      testWidgets(
        'F1-07-78 export is offered and enabled on both ${kind.name} surfaces — export is never blocked (ADR 2026-09-05g §3, §5)',
        (tester) async {
          var exports = 0;
          await pumpRk(tester, _banner(kind, onExport: () => exports++));
          final copy = kind.copy(
            tester.element(find.byType(RkRestrictionBanner)),
          );
          await tester.tap(find.text(copy.exportLabel));
          await tester.pumpAndSettle();
          expect(exports, 1);

          await pumpRk(
            tester,
            _DraftHost(kind: kind, onExport: () => exports++),
          );
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(copy.exportLabel));
          await tester.pumpAndSettle();
          expect(exports, 2, reason: 'the sheet refused an export');
        },
      );

      testWidgets(
        'F1-07-78 the ${kind.name} sheet reaches S12.1 through the outcome, and never clears the draft on the way',
        (tester) async {
          await pumpRk(tester, _DraftHost(kind: kind));
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          final copy = kind.copy(
            tester.element(find.byType(RkBlockedEntrySheet)),
          );
          await tester.tap(find.text(copy.sheetActionLabel));
          await tester.pumpAndSettle();

          final host = tester.state<_DraftHostState>(find.byType(_DraftHost));
          expect(host.outcome, RkBlockedEntryOutcome.action);
          expect(find.text('Diesel A/C'), findsOneWidget);
          expect(find.text('12,340'), findsOneWidget);
        },
      );
    }

    // 07 §18: 200 % OS font scale on the smallest supported screens, in every
    // script (ADR 2026-09-05f §G, §H15).
    for (final size in const [Size(375, 667), Size(360, 800)]) {
      for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
        testWidgets(
          'F1-07-78 banner and sheet survive 200% text scale at ${size.width.toInt()}x${size.height.toInt()} in ${locale.languageCode}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            for (final kind in RkRestrictionKind.values) {
              await pumpRk(
                tester,
                MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(2.0),
                  ),
                  child: _banner(kind, onExport: () {}),
                ),
                locale: locale,
              );
              expect(tester.takeException(), isNull, reason: 'banner $kind');
            }

            await pumpRk(
              tester,
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
                child: const _DraftHost(kind: RkRestrictionKind.bookFull),
              ),
              locale: locale,
            );
            await tester.tap(find.text('Save'));
            await tester.pumpAndSettle();
            expect(find.byType(RkBlockedEntrySheet), findsOneWidget);
            expect(tester.takeException(), isNull, reason: 'sheet');
          },
        );
      }
    }
  });
}
