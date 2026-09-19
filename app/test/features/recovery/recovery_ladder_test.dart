@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';

void main() {
  group('Recovery ladder seam (04 §7, 06 §5, 13 §5 F11)', () {
    test(
      'F1-07-265 the fork offers exactly three rungs in the 🔒 R2.1 order — '
      'another phone · trusted members · recovery sheet — and rung 0 is not '
      'among them, because it has already run by the time a fork is drawn',
      () {
        expect(RecoveryRung.forkOrder, [
          RecoveryRung.anotherDevice,
          RecoveryRung.trustedMembers,
          RecoveryRung.recoverySheet,
        ]);
        expect(
          RecoveryRung.forkOrder.contains(RecoveryRung.platformKeySync),
          isFalse,
        );
      },
    );

    test('F1-07-266 every fork rung is always answered for: the default fake '
        'offers all three available, and the nothing-worked fake blocks all '
        'three with their own reasons — a rung is never absent (13 §4.3 has no '
        'hidden state)', () async {
      final all = await FakeRecoveryLadder().rungs();
      expect(all.map((o) => o.rung), RecoveryRung.forkOrder);
      expect(all.every((o) => o.isAvailable), isTrue);

      final none = await FakeRecoveryLadder.nothingWorked().rungs();
      expect(none.map((o) => o.rung), RecoveryRung.forkOrder);
      expect(none.map((o) => o.blocked), [
        RecoveryRungBlocked.noOtherDevice,
        RecoveryRungBlocked.noTrustedMembers,
        RecoveryRungBlocked.noRecoverySheet,
      ]);
    });

    test('F1-07-267 progress is a count, and its fraction is 0 while the total '
        'is unknown — so the rule can never be handed a null and degrade into '
        'an indeterminate sweep (11 §4.5 🔒)', () {
      const unknown = RecoveryProgress(
        done: 3,
        total: 0,
        unit: RecoveryUnit.books,
      );
      expect(unknown.fraction, 0);
      const half = RecoveryProgress(
        done: 2,
        total: 4,
        unit: RecoveryUnit.books,
      );
      expect(half.fraction, 0.5);
      const over = RecoveryProgress(
        done: 9,
        total: 4,
        unit: RecoveryUnit.entries,
      );
      expect(over.fraction, 1);
      expect(half.finished, isFalse);
    });

    test(
      'F1-07-268 the seam carries no key material: a rung report is an enum '
      'and a reason, a progress reading is three ints and a unit — there is '
      'nothing on it a screen could render as a secret (04 §7.4, 07 §5.6 🔒)',
      () {
        const offer = RecoveryRungOffer.available(RecoveryRung.recoverySheet);
        expect(offer.toString(), 'RecoveryRungOffer(recoverySheet, available)');
        const p = RecoveryProgress(
          done: 1240,
          total: 3890,
          unit: RecoveryUnit.entries,
        );
        expect(p.toString(), 'RecoveryProgress(1240/3890 entries)');
        // A key would have to arrive as bytes or a string; neither type
        // appears anywhere on the seam's surface.
        expect(p.done, isA<int>());
        expect(p.total, isA<int>());
      },
    );

    test(
      'F1-07-269 a failing ladder surfaces its failure and counts the ask, so '
      'a retry is observable (13 §4.3 error-with-retry)',
      () async {
        final ladder = FakeRecoveryLadder.failing();
        await expectLater(ladder.rungs(), throwsA(isA<Exception>()));
        expect(ladder.asked, 1);
        await expectLater(ladder.rungs(), throwsA(isA<Exception>()));
        expect(ladder.asked, 2);
      },
    );

    test(
      'F1-07-270 a rung that reports nothing yields an empty stream, never a '
      'null reading — the screens never distinguish not-started from zero',
      () async {
        final ladder = FakeRecoveryLadder(
          progress: {
            RecoveryRung.platformKeySync: const [
              RecoveryProgress(done: 1, total: 2, unit: RecoveryUnit.books),
              RecoveryProgress(
                done: 2,
                total: 2,
                unit: RecoveryUnit.books,
                finished: true,
              ),
            ],
          },
        );
        expect(
          await ladder.progressOf(RecoveryRung.platformKeySync).toList(),
          hasLength(2),
        );
        expect(
          await ladder.progressOf(RecoveryRung.recoverySheet).toList(),
          isEmpty,
        );
      },
    );

    testWidgets(
      'F1-07-271 the scope is optional: a tree with no RecoveryLadderScope '
      'reads null rather than throwing, so a missing scope is never a red '
      'screen (07 §1 rule 6)',
      (tester) async {
        RecoveryLadder? seen;
        var sawScoped = false;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              seen = RecoveryLadderScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        );
        expect(seen, isNull);

        final ladder = FakeRecoveryLadder();
        await tester.pumpWidget(
          RecoveryLadderScope(
            ladder: ladder,
            child: Builder(
              builder: (context) {
                sawScoped = RecoveryLadderScope.maybeOf(context) == ladder;
                return const SizedBox();
              },
            ),
          ),
        );
        expect(sawScoped, isTrue);
      },
    );
  });
}
