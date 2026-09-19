@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/recovery/screens/s11_7_guardian_approval_screen.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';

import '../../shared/test_app.dart';

const _ask = GuardianRecoveryAsk(
  requestId: 'req-1',
  requesterName: 'Gurpreet',
  newDeviceName: 'iPhone 13',
  newDeviceFingerprint: '8F3C 21A9 5B70 D4E1',
  requesterPhone: '98765 43210',
);

FakeGuardianApprovals _seam({
  RecoveryScanOutcome scan = RecoveryScanOutcome.verified,
  bool failLoad = false,
}) => FakeGuardianApprovals(ask: _ask, scan: scan, failLoad: failLoad);

/// Ticks the caution.
Future<void> _acknowledge(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
}

/// Scans the new phone.
Future<void> _scan(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byType(OutlinedButton), 120);
  await tester.tap(find.byType(OutlinedButton).first);
  await tester.pumpAndSettle();
}

Future<void> _approve(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byType(FilledButton), 120);
  await tester.tap(find.byType(FilledButton).first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  group(
    'S11.7 Recovery — the guardian’s side '
    '(13 §3.2, design R2.3 🔒, 04 §7.3 steps 2–3, ADR 2026-09-13c ruling 3 🔒)',
    () {
      testWidgets(
        'F1-07-305 what arrives on the relative’s phone (design R2.3): the '
        'name and the sentence, the new phone and its fingerprint, and the '
        'caution sitting **above** the two buttons — with no financial '
        'content anywhere on it (04 §4 🔒)',
        (tester) async {
          await pumpRk(
            tester,
            GuardianApprovalScreen(requestId: 'req-1', approvals: _seam()),
            viewport: rkTallViewport,
          );

          expect(
            find.text('Gurpreet wants to restore their books on a new phone'),
            findsOneWidget,
          );
          expect(find.text('New phone: iPhone 13'), findsOneWidget);
          expect(find.text('Its fingerprint'), findsOneWidget);
          expect(find.text('8F3C 21A9 5B70 D4E1'), findsOneWidget);
          expect(
            find.text('Call them first to be sure it is really them.'),
            findsOneWidget,
          );
          expect(find.text('Approve'), findsOneWidget);
          expect(find.text('Not now'), findsOneWidget);

          // The caution is drawn above both buttons — it cannot be reached
          // past.
          final caution = tester.getTopLeft(
            find.text('Call them first to be sure it is really them.'),
          );
          expect(
            caution.dy,
            lessThan(tester.getTopLeft(find.text('Approve')).dy),
          );
          expect(
            caution.dy,
            lessThan(tester.getTopLeft(find.text('Not now')).dy),
          );

          // Content-free: no amount, no book, no balance (04 §4 🔒).
          for (final w in tester.widgetList<Text>(find.byType(Text))) {
            final s = w.data ?? '';
            expect(s, isNot(contains('₹')), reason: s);
          }
        },
      );

      testWidgets(
        'F1-13c-3 Approve is impossible until **both** checks are done — the '
        'caution ticked and the new phone scanned — and the seam itself '
        'refuses an unverified approval, so the check lives in the contract '
        'and not only in this layout (ADR 2026-09-13c ruling 3 🔒)',
        (tester) async {
          final seam = _seam();
          await pumpRk(
            tester,
            GuardianApprovalScreen(requestId: 'req-1', approvals: seam),
            viewport: rkTallViewport,
          );

          FilledButton approve() => tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve'),
          );

          // Nothing done: blocked, with its reason on the control.
          expect(approve().onPressed, isNull);
          expect(
            find.text('Call them and scan their new phone first.'),
            findsOneWidget,
          );

          // Caution alone is not enough.
          await _acknowledge(tester);
          expect(approve().onPressed, isNull);

          // Scan alone is not enough either.
          await pumpRk(
            tester,
            GuardianApprovalScreen(requestId: 'req-1', approvals: _seam()),
            viewport: rkTallViewport,
          );
          await _scan(tester);
          expect(find.text('Their phone matched this request'), findsOneWidget);
          expect(approve().onPressed, isNull);

          // Both: alive, and it reaches the seam with this request's id.
          await _acknowledge(tester);
          expect(approve().onPressed, isNotNull);

          // And the contract refuses what a screen bug might have offered.
          await expectLater(
            FakeGuardianApprovals(ask: _ask).approve('req-1'),
            throwsA(isA<RecoveryCandidateUnverified>()),
          );
        },
      );

      testWidgets(
        'F1-07-306 a scan that does not match says **do not approve** and '
        'leaves Approve blocked — there is no override (ADR 2026-09-13c '
        'ruling 3 🔒)',
        (tester) async {
          await pumpRk(
            tester,
            GuardianApprovalScreen(
              requestId: 'req-1',
              approvals: _seam(scan: RecoveryScanOutcome.mismatch),
            ),
            viewport: rkTallViewport,
          );
          await _acknowledge(tester);
          await _scan(tester);

          expect(find.textContaining('Do not approve'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Approve'),
                )
                .onPressed,
            isNull,
          );
        },
      );

      testWidgets(
        'F1-07-307 a phone that cannot scan cannot approve — the reason is '
        'stated (13 §4.3) and *Not now* is still available, because refusing '
        'is always the safe answer',
        (tester) async {
          final seam = _seam(scan: RecoveryScanOutcome.unavailable);
          await pumpRk(
            tester,
            GuardianApprovalScreen(requestId: 'req-1', approvals: seam),
            viewport: rkTallViewport,
          );
          await _acknowledge(tester);
          await _scan(tester);

          expect(find.textContaining('cannot scan a code yet'), findsWidgets);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Approve'),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.text('Not now'));
          await tester.pumpAndSettle();
          expect(seam.declined, ['req-1']);
          expect(seam.approved, isEmpty);
        },
      );

      testWidgets(
        'F1-07-308 *Not now* needs no checks and says so plainly: nothing was '
        'sent, and the door stays open (04 §7.3 step 7)',
        (tester) async {
          final seam = _seam();
          await pumpRk(
            tester,
            GuardianApprovalScreen(requestId: 'req-1', approvals: seam),
            viewport: rkTallViewport,
          );
          await tester.tap(find.text('Not now'));
          await tester.pumpAndSettle();

          expect(seam.declined, ['req-1']);
          expect(find.text('Not approved'), findsWidgets);
          expect(find.textContaining('Nothing was sent'), findsOneWidget);
          expect(find.textContaining('they can ask again'), findsOneWidget);
        },
      );

      testWidgets(
        'F1-07-309 after both checks the approval reaches the seam with this '
        'request’s id, and the member is told what happens next without '
        'being shown the tally (ADR 2026-09-05d §2)',
        (tester) async {
          final seam = _seam();
          await pumpRk(
            tester,
            GuardianApprovalScreen(requestId: 'req-1', approvals: seam),
            viewport: rkTallViewport,
          );
          await _acknowledge(tester);
          await _scan(tester);
          await _approve(tester);

          expect(seam.approved, ['req-1']);
          expect(find.text('Approved'), findsWidgets);
          expect(find.textContaining('Your part is done'), findsOneWidget);
          // A guardian reads the ask, not the tally.
          for (final w in tester.widgetList<Text>(find.byType(Text))) {
            expect(w.data ?? '', isNot(contains('of 2')), reason: w.data);
          }
        },
      );

      testWidgets(
        'F1-07-310 the states of 13 §4.3 that are not the decision: a loading '
        'skeleton, and a seam that cannot be read is an error-with-retry that '
        'asks again — never a red screen (07 §1 rule 6)',
        (tester) async {
          await pumpRk(
            tester,
            const GuardianApprovalScreen(requestId: 'req-1'),
            viewport: rkTallViewport,
          );
          expect(find.text('We could not open this request.'), findsOneWidget);

          final seam = _seam(failLoad: true);
          await pumpRk(
            tester,
            GuardianApprovalScreen(requestId: 'req-1', approvals: seam),
            viewport: rkTallViewport,
          );
          expect(find.text('We could not open this request.'), findsOneWidget);
          seam.failLoad = false;
          await tester.tap(find.text('Try again'));
          await tester.pumpAndSettle();
          expect(find.text('New phone: iPhone 13'), findsOneWidget);
        },
      );

      testWidgets(
        'F1-07-311 the screen holds at 130 % and 200 % text on 360×800 and '
        '375×667 in all three languages, walked to the bottom',
        (tester) async {
          for (final locale in rkLocales) {
            for (final size in rkPhones) {
              for (final scale in rkTextScales) {
                final reason = '$locale $size ×$scale';
                await pumpRk(
                  tester,
                  GuardianApprovalScreen(
                    requestId: 'req-1',
                    approvals: _seam(),
                  ),
                  locale: locale,
                  textScale: scale,
                  viewport: size,
                );
                for (var i = 0; i < 8; i++) {
                  expect(tester.takeException(), isNull, reason: reason);
                  expectTextFits(tester, reason: reason);
                  final scrollable = find.byType(Scrollable);
                  if (scrollable.evaluate().isEmpty) break;
                  await tester.drag(scrollable.first, const Offset(0, -320));
                  await tester.pumpAndSettle();
                }
              }
            }
          }
        },
      );
    },
  );
}
