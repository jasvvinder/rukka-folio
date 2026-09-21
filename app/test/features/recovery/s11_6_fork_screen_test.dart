@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/recovery/screens/s11_6_fork_screen.dart';
import 'package:rukka_folio/features/recovery/widgets/recovery_parts.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

/// The ladder as M11 actually ships it: rung 1 and rung 3 are real, and the
/// two screens that walk rung 2 (S11.2) and rung 3's scanner (S11.3) are not
/// built this round — so those rungs report `notOnThisPhoneYet`.
FakeRecoveryLadder _asShipped() => FakeRecoveryLadder(
  offers: const [
    RecoveryRungOffer.available(RecoveryRung.anotherDevice),
    RecoveryRungOffer.blocked(
      RecoveryRung.trustedMembers,
      RecoveryRungBlocked.notOnThisPhoneYet,
    ),
    RecoveryRungOffer.blocked(
      RecoveryRung.recoverySheet,
      RecoveryRungBlocked.notOnThisPhoneYet,
    ),
  ],
);

void main() {
  group('S11.6 Recovery — the fork (13 §3.2, design R2.1, 04 §7, 06 §5)', () {
    testWidgets(
      'F1-07-272 the quiet screen: the heading, then the three ways in the 🔒 '
      'R2.1 order — another phone · trusted members · recovery sheet — each '
      'with its one-line explanation, the sheet row carrying its sub-line, '
      'and the muted closing line about the private book',
      (tester) async {
        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: FakeRecoveryLadder()),
          viewport: rkTallViewport,
        );
        expect(
          find.text('Let’s get your books back on this phone'),
          findsOneWidget,
        );
        expect(
          find.text('Use another phone you’re signed in on'),
          findsOneWidget,
        );
        expect(find.text('Ask your trusted members'), findsOneWidget);
        expect(find.text('Use your recovery sheet'), findsOneWidget);
        expect(
          find.text(
            'Hold the two phones together for a minute. '
            'Nobody else has to do anything.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('approve on their own phones'),
          findsOneWidget,
        );
        expect(
          find.text('Scan the code on it, or type the code in by hand.'),
          findsOneWidget,
        );
        expect(find.text('paper or the file you saved'), findsOneWidget);
        expect(
          find.text(
            'Your family books can also be restored by your family — '
            'your own private book cannot.',
          ),
          findsOneWidget,
        );

        // The order is the pack's, read off the rendered rows rather than
        // assumed from the list the fake happened to return.
        final rows = tester
            .widgetList<RecoveryRungRow>(find.byType(RecoveryRungRow))
            .map((r) => r.rung)
            .toList();
        expect(rows, RecoveryRung.forkOrder);
      },
    );

    testWidgets(
      'F1-07-273 an available row reaches the caller with its rung; the '
      'vocabulary is Trusted member and Recovery sheet — never guardian, '
      'never share (01 §1.3)',
      (tester) async {
        final taken = <RecoveryRung>[];
        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: FakeRecoveryLadder(), onRung: taken.add),
          viewport: rkTallViewport,
        );
        await tester.tap(find.text('Ask your trusted members'));
        await tester.pump();
        await tester.tap(find.text('Use your recovery sheet'));
        await tester.pump();
        expect(taken, [
          RecoveryRung.trustedMembers,
          RecoveryRung.recoverySheet,
        ]);

        for (final w in tester.widgetList<Text>(find.byType(Text))) {
          final s = (w.data ?? '').toLowerCase();
          expect(s.contains('guardian'), isFalse, reason: w.data);
          expect(s.contains('share'), isFalse, reason: w.data);
        }
      },
    );

    testWidgets(
      'F1-07-274 a rung this build cannot walk is disabled-with-reason and '
      'never hidden (13 §4.3): S11.2 and S11.3 are not built at M11, so both '
      'rows still render, state why, name a way that works, and do not fire',
      (tester) async {
        final taken = <RecoveryRung>[];
        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: _asShipped(), onRung: taken.add),
          viewport: rkTallViewport,
        );
        expect(find.byType(RecoveryRungRow), findsNWidgets(3));
        expect(
          find.text(
            'Not ready on this phone yet. Use one of the other ways for now.',
          ),
          findsNWidgets(2),
        );
        await tester.tap(find.text('Ask your trusted members'));
        await tester.pump();
        expect(taken, isEmpty);

        // The one live rung still works — a disabled neighbour never blocks it.
        await tester.tap(find.text('Use another phone you’re signed in on'));
        await tester.pump();
        expect(taken, [RecoveryRung.anotherDevice]);
      },
    );

    testWidgets(
      'F1-07-275 each blocked reason is its own sentence, and none of them '
      'is a dead end: with every rung blocked the screen offers the honest '
      'way onward to S11.8 (07 §1 rule 6, 13 §5 F11 "none → S11.8")',
      (tester) async {
        var onward = 0;
        await pumpRk(
          tester,
          RecoveryForkScreen(
            ladder: FakeRecoveryLadder.nothingWorked(),
            onNothingWorked: () => onward++,
          ),
          viewport: rkTallViewport,
        );
        expect(
          find.text('No other phone of yours is signed in right now.'),
          findsOneWidget,
        );
        expect(
          find.text('You haven’t chosen trusted members yet.'),
          findsOneWidget,
        );
        expect(
          find.text('No recovery sheet was made for this account.'),
          findsOneWidget,
        );
        await tester.tap(find.text('None of these work for me'));
        await tester.pump();
        expect(onward, 1);
      },
    );

    testWidgets(
      'F1-07-276 while another phone of yours is signed in, the trusted-member '
      'row says to link instead — 06 §5 🔒 "a user who still has a phone '
      'should link instead, and the screen says so". With no such phone the '
      'line is gone, because then it would be false',
      (tester) async {
        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: FakeRecoveryLadder()),
          viewport: rkTallViewport,
        );
        expect(
          find.textContaining('use that instead. It is instant'),
          findsOneWidget,
        );

        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: FakeRecoveryLadder.nothingWorked()),
          viewport: rkTallViewport,
        );
        expect(
          find.textContaining('use that instead. It is instant'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'F1-07-277 the three states of 13 §4.3: loading is announced in words '
      'over a ruled skeleton, the failure names what failed and retries '
      'through the ladder, and offline is a quiet chip that blocks nothing',
      (tester) async {
        final failing = FakeRecoveryLadder.failing();
        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: failing),
          viewport: rkTallViewport,
        );
        expect(find.text('We couldn’t check your ways back in.'), findsOne);
        expect(failing.asked, 1);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(failing.asked, 2);

        final sync = FakeSyncClient(initial: const Offline());
        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: FakeRecoveryLadder()),
          sync: sync,
          viewport: rkTallViewport,
        );
        expect(
          find.text(
            'Offline — connect once so we can check your ways back in.',
          ),
          findsOneWidget,
        );
        // Never a blocking banner (07 §1 rule 7): the rows are still live.
        expect(find.byType(RecoveryRungRow), findsNWidgets(3));
      },
    );

    testWidgets(
      'F1-07-418 a rung nothing could check is drawn as neither of the two '
      'easy answers: it is not greyed out as refused — it stays takeable and '
      'reaches the caller — and it is not the confirmed row either, because '
      'it carries the plain admission that this phone could not check '
      '(recovery_ladder.dart RecoveryRungOffer.unknown 🔒)',
      (tester) async {
        final taken = <RecoveryRung>[];
        await pumpRk(
          tester,
          RecoveryForkScreen(
            ladder: FakeRecoveryLadder.allUnknown(),
            onRung: taken.add,
          ),
          viewport: rkTallViewport,
        );

        // Not denied: the row fires, and nothing refuses it.
        await tester.tap(find.text('Use your recovery sheet'));
        await tester.pump();
        expect(taken, [RecoveryRung.recoverySheet]);
        expect(
          find.byIcon(Icons.lock_outline),
          findsNothing,
          reason: 'the lock is the refusal’s own shape; nothing refused here',
        );
        for (final row in tester.widgetList<RecoveryRungRow>(
          find.byType(RecoveryRungRow),
        )) {
          expect(row.reason, isNull, reason: row.rung.name);
        }

        // Not confirmed either: every row says so, in words, beside an icon
        // that is not the lock.
        expect(
          find.text(
            'We couldn’t check this one from this phone. '
            'It may still work — tap to try it.',
          ),
          findsNWidgets(3),
        );
        expect(find.byIcon(Icons.help_outline), findsNWidgets(3));

        // And a screen reader that never sees either icon still hears it.
        final sem = tester
            .widgetList<Semantics>(
              find.descendant(
                of: find.byWidgetPredicate(
                  (w) =>
                      w is RecoveryRungRow &&
                      w.rung == RecoveryRung.recoverySheet,
                ),
                matching: find.byType(Semantics),
              ),
            )
            .first
            .properties;
        expect(sem.enabled, isTrue);
        expect(sem.hint, contains('could'));
      },
    );

    testWidgets(
      'F1-07-419 the difference survives with colour removed (07 §1 rule 3 '
      '🔒): reading only the words, the liveness and the icons, an unchecked '
      'rung matches neither the available one nor the refused one',
      (tester) async {
        // Everything about the sheet row a reader gets **without** colour.
        Future<String> signature(RecoveryRungOffer sheet) async {
          await pumpRk(
            tester,
            RecoveryForkScreen(
              ladder: FakeRecoveryLadder(
                offers: [
                  const RecoveryRungOffer.available(RecoveryRung.anotherDevice),
                  const RecoveryRungOffer.available(
                    RecoveryRung.trustedMembers,
                  ),
                  sheet,
                ],
              ),
              onRung: (_) {},
            ),
            viewport: rkTallViewport,
          );
          final finder = find.byWidgetPredicate(
            (w) => w is RecoveryRungRow && w.rung == RecoveryRung.recoverySheet,
          );
          final row = tester.widget<RecoveryRungRow>(finder);
          final words = [
            for (final t in tester.widgetList<Text>(
              find.descendant(of: finder, matching: find.byType(Text)),
            ))
              t.data,
          ];
          final icons = [
            for (final i in tester.widgetList<Icon>(
              find.descendant(of: finder, matching: find.byType(Icon)),
            ))
              i.icon?.codePoint,
          ];
          return 'live=${row.onTap != null} words=$words icons=$icons';
        }

        final unchecked = await signature(
          const RecoveryRungOffer.unknown(RecoveryRung.recoverySheet),
        );
        final available = await signature(
          const RecoveryRungOffer.available(RecoveryRung.recoverySheet),
        );
        final refused = await signature(
          const RecoveryRungOffer.blocked(
            RecoveryRung.recoverySheet,
            RecoveryRungBlocked.noRecoverySheet,
          ),
        );

        expect(
          unchecked,
          isNot(available),
          reason: 'an unchecked rung was never confirmed by anyone',
        );
        expect(
          unchecked,
          isNot(refused),
          reason: 'an unchecked rung was never refused by anyone',
        );
        // Guards the guard: the two ends really do differ too, so the
        // signature is reading something rather than returning a constant.
        expect(available, isNot(refused));
      },
    );

    testWidgets(
      'F1-07-420 "None of these work for me" counts refusals and never '
      'unchecked rungs: an all-unchecked ladder offers no such control, '
      'because every row is still takeable and the control would invite '
      'giving up while a door may be open (13 §5 F11 "none → S11.8")',
      (tester) async {
        var onward = 0;
        await pumpRk(
          tester,
          RecoveryForkScreen(
            ladder: FakeRecoveryLadder.allUnknown(),
            onRung: (_) {},
            onNothingWorked: () => onward++,
          ),
          viewport: rkTallViewport,
        );
        expect(find.text('None of these work for me'), findsNothing);
        expect(onward, 0);

        // The refused ladder is unchanged — the control is still there, which
        // is what stops the assertion above from passing by deletion.
        await pumpRk(
          tester,
          RecoveryForkScreen(
            ladder: FakeRecoveryLadder.nothingWorked(),
            onNothingWorked: () => onward++,
          ),
          viewport: rkTallViewport,
        );
        expect(find.text('None of these work for me'), findsOneWidget);

        // A ladder that is part refused, part unchecked offers it neither:
        // one rung may still work.
        await pumpRk(
          tester,
          RecoveryForkScreen(
            ladder: FakeRecoveryLadder(
              offers: const [
                RecoveryRungOffer.unknown(RecoveryRung.anotherDevice),
                RecoveryRungOffer.blocked(
                  RecoveryRung.trustedMembers,
                  RecoveryRungBlocked.noTrustedMembers,
                ),
                RecoveryRungOffer.blocked(
                  RecoveryRung.recoverySheet,
                  RecoveryRungBlocked.noRecoverySheet,
                ),
              ],
            ),
            onNothingWorked: () => onward++,
          ),
          viewport: rkTallViewport,
        );
        expect(find.text('None of these work for me'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-421 an unchecked rung 1 promises nothing: 06 §5’s "use that '
      'instead" line is attached to a phone a real source confirmed, so a '
      'ladder that could not check says it to nobody',
      (tester) async {
        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: FakeRecoveryLadder.allUnknown()),
          viewport: rkTallViewport,
        );
        expect(
          find.textContaining('use that instead. It is instant'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'F1-07-422 the unchecked rendering holds at 200 % text on 360×800 and '
      '375×667 in all three languages — the third state adds a sentence to '
      'every row, which is exactly where a fork overflows',
      (tester) async {
        for (final locale in rkLocales) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                RecoveryForkScreen(
                  ladder: FakeRecoveryLadder.allUnknown(),
                  onRung: (_) {},
                ),
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$locale $size ×$scale',
              );
              expectTextFits(tester, reason: '$locale $size ×$scale');
            }
          }
        }
      },
    );

    testWidgets(
      'F1-07-278 the fork holds at 200 % text on 360×800 and 375×667 in all '
      'three languages, with no overflow and no silently cut word',
      (tester) async {
        for (final locale in rkLocales) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                RecoveryForkScreen(ladder: _asShipped()),
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$locale $size ×$scale',
              );
              expectTextFits(tester, reason: '$locale $size ×$scale');
            }
          }
        }
      },
    );
  });
}
