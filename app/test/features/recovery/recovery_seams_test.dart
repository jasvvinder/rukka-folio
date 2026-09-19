// The rung-2 and rung-3 halves of `shared/seams/recovery_ladder.dart`, tested
// as a **contract** rather than through a screen.
//
// Each of these is a rule some other implementation of the seam — the adapter
// over migration 0010's routes, when it lands — has to keep too. A widget test
// would only prove that one build method happened to respect it.
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';

void main() {
  group('recovery-ladder seam, rungs 2 and 3 (04 §7.3 / §7.4 🔒)', () {
    test('C-06-39 a sheet code reads by Crockford’s own rules — case folded, '
        'I and L as 1, O as 0, separators ignored — and a character outside the '
        'alphabet is refused rather than guessed (04 §7.4 🔒)', () {
      final typed = RecoverySheetCode.parse('k8n4 2qrt-9vwx yozi');
      expect(typed, isNotNull);
      expect(typed!.value, 'K8N42QRT9VWXY0Z1');
      // Read back in the sheet's own groups of four.
      expect(typed.grouped, 'K8N4-2QRT-9VWX-Y0Z1');
      // The same code however it was written down.
      expect(RecoverySheetCode.parse('K8N4-2QRT-9VWX-Y0Z1'), typed);

      // `U` is not in Crockford's alphabet, and nothing here invents a
      // reading for it.
      expect(RecoverySheetCode.parse('K8N4-2QRU'), isNull);
      expect(RecoverySheetCode.parse(''), isNull);
      // ⚠️ SPEC: 04 §7.4 names a "2-char checksum" but not which one, so
      // no checksum is verified here — a wrong algorithm would put a red
      // line under a correct code. A well-formed code goes to the server.
      expect(RecoverySheetCode.parse('ZZZZ'), isNotNull);
    });

    test('C-06-40 the tally is counted from the rows, one per member, so the '
        'attempt can say **which** member did what — a refusal is not an '
        'approval and is not silence (migration 0010 🔒, 04 §7.3 step 7)', () {
      const attempt = GuardianRecoveryAttempt(
        requestId: 'req-1',
        k: 3,
        n: 5,
        approvers: [
          TrustedApprover(
            memberId: 'a',
            name: 'A',
            state: TrustedApproverState.approved,
          ),
          TrustedApprover(
            memberId: 'b',
            name: 'B',
            state: TrustedApproverState.approved,
          ),
          TrustedApprover(
            memberId: 'c',
            name: 'C',
            state: TrustedApproverState.declined,
          ),
          TrustedApprover(
            memberId: 'd',
            name: 'D',
            state: TrustedApproverState.waiting,
          ),
          TrustedApprover(memberId: 'e', name: 'E'),
        ],
      );
      expect(attempt.approvals, 2);
      expect(attempt.declines, 1);
      expect(attempt.isClosed, isFalse);

      // 03 §2.2 has no `denied`: a closed attempt is closed, and the seam
      // exposes no way for a screen to claim which closed it.
      const closed = GuardianRecoveryAttempt(
        requestId: 'req-1',
        k: 2,
        n: 3,
        approvers: [],
        state: RecoveryAttemptState.expired,
      );
      expect(closed.isClosed, isTrue);
      expect(
        RecoveryAttemptState.values.map((s) => s.name),
        isNot(contains('denied')),
      );
    });

    test('C-06-41 the guardian seam refuses an approval that no scan preceded, '
        'and a scan that did not match never counts as one — the check of '
        'ADR 2026-09-13c ruling 3 🔒 lives in the contract', () async {
      final unscanned = FakeGuardianApprovals();
      await expectLater(
        unscanned.approve('req-1'),
        throwsA(isA<RecoveryCandidateUnverified>()),
      );

      final mismatched = FakeGuardianApprovals(
        scan: RecoveryScanOutcome.mismatch,
      );
      expect(
        await mismatched.verifyCandidateByScan('req-1'),
        RecoveryScanOutcome.mismatch,
      );
      await expectLater(
        mismatched.approve('req-1'),
        throwsA(isA<RecoveryCandidateUnverified>()),
      );

      // Declining never needs one: refusing is always safe.
      await mismatched.decline('req-1');
      expect(mismatched.declined, ['req-1']);
      expect(mismatched.approved, isEmpty);

      // A verified scan opens it, and only for the request it named.
      final verified = FakeGuardianApprovals();
      await verified.verifyCandidateByScan('req-1');
      await verified.approve('req-1');
      expect(verified.approved, ['req-1']);
      await expectLater(
        verified.approve('req-2'),
        throwsA(isA<RecoveryCandidateUnverified>()),
      );
    });
  });
}
