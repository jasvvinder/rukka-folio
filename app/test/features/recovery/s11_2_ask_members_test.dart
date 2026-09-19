@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/recovery/screens/s11_2_ask_members_screen.dart';
import 'package:rukka_folio/features/recovery/widgets/recovery_parts.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

/// The pack's own example: 2-of-3, one approval in, one waiting, one not
/// asked — with a number on the two who have been asked.
GuardianRecoveryAttempt _twoOfThree({
  RecoveryAttemptState state = RecoveryAttemptState.pending,
  DateTime? waitUntil,
  RecoveryProgress? restore,
  TrustedApproverState second = TrustedApproverState.waiting,
}) => GuardianRecoveryAttempt(
  requestId: 'req-1',
  k: 2,
  n: 3,
  state: state,
  waitUntil: waitUntil,
  restore: restore,
  approvers: [
    const TrustedApprover(
      memberId: 'm1',
      name: 'Sunita',
      state: TrustedApproverState.approved,
      phone: '98765 43210',
    ),
    TrustedApprover(
      memberId: 'm2',
      name: 'Harjit',
      state: second,
      phone: '98765 43211',
    ),
    const TrustedApprover(memberId: 'm3', name: 'Balwinder'),
  ],
);

/// A seam already holding [attempt], scanning with [scan].
FakeGuardianRecovery _seam({
  GuardianRecoveryAttempt? attempt,
  RecoveryScanOutcome scan = RecoveryScanOutcome.verified,
}) => FakeGuardianRecovery(initial: attempt ?? _twoOfThree(), scan: scan);

/// Walks the ceremony gate, so a test about the waiting screen can start
/// where the pack's drawing starts.
Future<void> _passCeremony(WidgetTester tester) async {
  await tester.tap(find.text('Scan their screen'));
  await tester.pumpAndSettle();
}

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  group('S11.2 Recovery — ask your trusted members '
      '(13 §3.2, design R2.2, 04 §7.3 🔒, ADR 2026-09-13c)', () {
    testWidgets(
      'F1-07-290 the recovery ceremony comes first: nothing about the '
      'attempt — no member, no tally — is drawn until this phone has been '
      'pinned to a human (ADR 2026-09-13c ruling 1 🔒)',
      (tester) async {
        final seam = _seam();
        await pumpRk(
          tester,
          AskTrustedMembersScreen(recovery: seam),
          viewport: rkTallViewport,
        );

        expect(
          find.text('First, scan your trusted member’s screen'),
          findsOneWidget,
        );
        // The attempt is loaded, and deliberately not shown.
        expect(seam.current, isNotNull);
        expect(find.text('Sunita'), findsNothing);
        expect(find.textContaining('approvals'), findsNothing);
        expect(seam.scans, 0);

        await _passCeremony(tester);
        expect(seam.scans, 1);
        expect(find.text('Sunita'), findsOneWidget);
      },
    );

    testWidgets('F1-13c-2 the QR path only: S11.2 offers scanning and no typed '
        'fallback anywhere — “enter code instead” is absent by ruling, not by '
        'omission (ADR 2026-09-13c ruling 2 🔒)', (tester) async {
      await pumpRk(
        tester,
        AskTrustedMembersScreen(recovery: _seam()),
        viewport: rkTallViewport,
      );
      expect(find.text('Scan their screen'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      for (final s in _texts(tester)) {
        expect(s.toLowerCase(), isNot(contains('type the code')), reason: s);
        expect(s.toLowerCase(), isNot(contains('enter code')), reason: s);
      }
    });

    testWidgets(
      'F1-13c-1 a ceremony mismatch fails closed: the one safe action is '
      'named, there is no way to scan again, and the attempt is never '
      'shown (ADR 2026-09-13c ruling 1 🔒 — no override)',
      (tester) async {
        final seam = _seam(scan: RecoveryScanOutcome.mismatch);
        await pumpRk(
          tester,
          AskTrustedMembersScreen(recovery: seam, onBack: () {}),
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);

        expect(
          find.textContaining('does not match this account'),
          findsOneWidget,
        );
        expect(find.textContaining('Stop here'), findsOneWidget);
        // No retry of the scan, and nothing of the attempt.
        expect(find.text('Scan their screen'), findsNothing);
        expect(find.text('Sunita'), findsNothing);
        expect(find.text('Try another way back in'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-291 the waiting screen (design R2.2): “Ask any 2 of 3 to '
      'approve”, the call advice, “1 of 2 approvals” counted from the rows, '
      'and one row per member carrying its state as an icon **and** a word',
      (tester) async {
        await pumpRk(
          tester,
          AskTrustedMembersScreen(recovery: _seam()),
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);

        expect(find.text('Ask any 2 of 3 to approve'), findsOneWidget);
        expect(
          find.text('Phone them — they are expecting this.'),
          findsOneWidget,
        );
        expect(find.text('1 of 2 approvals'), findsOneWidget);

        final rows = tester
            .widgetList<TrustedApproverRow>(find.byType(TrustedApproverRow))
            .map((r) => r.approver.name)
            .toList();
        expect(rows, ['Sunita', 'Harjit', 'Balwinder']);
        expect(find.text('Approved'), findsOneWidget);
        expect(find.text('Waiting…'), findsOneWidget);
        expect(find.text('Not asked'), findsOneWidget);

        // 11 §4.5 🔒 and R2.2: a rule, never a spinner.
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(RecoveryInlineRule), findsOneWidget);

        // No dialer is wired, so the number is shown rather than a control
        // that would do nothing (07 §1 rule 6).
        expect(find.textContaining('98765 43211'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-292 a member who refused is drawn as such and is not counted '
      'as an approval — 04 §7.3 step 7 🔒 requires the requester be told, '
      'and the rows can say it even though the attempt state cannot',
      (tester) async {
        await pumpRk(
          tester,
          AskTrustedMembersScreen(
            recovery: _seam(
              attempt: _twoOfThree(second: TrustedApproverState.declined),
            ),
          ),
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);

        expect(find.text('Said no'), findsOneWidget);
        expect(find.text('1 of 2 approvals'), findsOneWidget);
        // Plain, never blaming (01 §1.3 tone).
        for (final s in _texts(tester)) {
          expect(s.toLowerCase(), isNot(contains('rejected')), reason: s);
          expect(s.toLowerCase(), isNot(contains('refused')), reason: s);
        }
      },
    );

    testWidgets(
      'F1-07-293 the 24 h wait states the delay as protection and the hours '
      'left, measured from the k-th approval (ADR 2026-09-05d §1 🔒)',
      (tester) async {
        await pumpRk(
          tester,
          AskTrustedMembersScreen(
            recovery: _seam(
              attempt: _twoOfThree(
                state: RecoveryAttemptState.waiting24h,
                waitUntil: testNow().add(const Duration(hours: 20)),
              ),
            ),
          ),
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);

        expect(find.text('Your books open here tomorrow'), findsOneWidget);
        expect(find.text('About 20 hours left'), findsOneWidget);
        expect(find.textContaining('one tap'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-294 a closed attempt claims neither a refusal nor a timeout — '
      '03 §2.2 has no `denied`, so the two are one state (migration 0010) — '
      'and it still offers a live path (07 §1 rule 6 🔒)',
      (tester) async {
        var back = 0;
        await pumpRk(
          tester,
          AskTrustedMembersScreen(
            recovery: _seam(
              attempt: _twoOfThree(state: RecoveryAttemptState.expired),
            ),
            onBack: () => back++,
          ),
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);

        expect(find.text('This request has closed'), findsWidgets);
        expect(find.textContaining('three days'), findsOneWidget);
        for (final s in _texts(tester)) {
          expect(s.toLowerCase(), isNot(contains('denied')), reason: s);
          expect(s.toLowerCase(), isNot(contains('expired')), reason: s);
        }
        await tester.tap(find.text('Try another way back in').first);
        await tester.pumpAndSettle();
        expect(back, 1);
      },
    );

    testWidgets(
      'F1-07-295 the completed state (design R2.2): the ticks, then one '
      'calm line with a **count** over the determinate rule — never a '
      'percentage (11 §4.5 🔒)',
      (tester) async {
        await pumpRk(
          tester,
          AskTrustedMembersScreen(
            recovery: _seam(
              attempt: _twoOfThree(
                state: RecoveryAttemptState.approved,
                second: TrustedApproverState.approved,
                restore: const RecoveryProgress(
                  done: 1240,
                  total: 3890,
                  unit: RecoveryUnit.entries,
                ),
              ),
            ),
          ),
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);

        expect(find.text('Everyone needed has approved'), findsOneWidget);
        expect(find.text('1,240 of 3,890 entries restored'), findsOneWidget);
        expect(find.byType(RecoveryLoaderRule), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        for (final s in _texts(tester)) {
          expect(s, isNot(contains('%')), reason: s);
        }
      },
    );

    testWidgets(
      'F1-07-296 the three states of 13 §4.3 that are not the happy path: '
      'no seam at all is an error-with-retry and never a red screen, and '
      'offline is a quiet chip that blocks nothing (07 §1 rule 7)',
      (tester) async {
        await pumpRk(
          tester,
          const AskTrustedMembersScreen(),
          viewport: rkTallViewport,
        );
        expect(find.text('We could not check this request.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);

        final sync = FakeSyncClient(initial: const Offline());
        await pumpRk(
          tester,
          AskTrustedMembersScreen(recovery: _seam()),
          sync: sync,
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);
        expect(find.textContaining('approvals will show up'), findsOneWidget);
        // Still the live screen underneath, not a blocking banner.
        expect(find.text('1 of 2 approvals'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-297 the screen holds at 130 % and 200 % text on 360×800 and '
      '375×667 in all three languages, with no overflow and no cut word',
      (tester) async {
        for (final locale in rkLocales) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                AskTrustedMembersScreen(
                  recovery: _seam(
                    attempt: _twoOfThree(
                      state: RecoveryAttemptState.waiting24h,
                      waitUntil: testNow().add(const Duration(hours: 20)),
                    ),
                  ),
                ),
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              final reason = '$locale $size ×$scale';
              // The ceremony step, walked to its end.
              await _sweep(tester, reason);
              // Then the waiting list, from a fresh pump so the scan
              // control is where a person would find it — at the top.
              await pumpRk(
                tester,
                AskTrustedMembersScreen(
                  recovery: _seam(
                    attempt: _twoOfThree(
                      state: RecoveryAttemptState.waiting24h,
                      waitUntil: testNow().add(const Duration(hours: 20)),
                    ),
                  ),
                ),
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              await _passCeremonyIn(tester);
              await _sweep(tester, reason);
            }
          }
        }
      },
    );
  });
}

/// Taps the scan control in whichever language is on screen.
Future<void> _passCeremonyIn(WidgetTester tester) async {
  final button = find.byType(FilledButton);
  if (button.evaluate().isEmpty) return;
  await tester.tap(button.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Walks the whole scrollable, checking at each screenful that nothing
/// overflowed and no word was silently cut.
Future<void> _sweep(WidgetTester tester, String reason) async {
  for (var i = 0; i < 8; i++) {
    expect(tester.takeException(), isNull, reason: reason);
    expectTextFits(tester, reason: reason);
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) return;
    await tester.drag(scrollable.first, const Offset(0, -320));
    await tester.pumpAndSettle();
  }
}
