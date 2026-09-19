// The trusted-member seam (`shared/seams/guardians.dart`), consumed by S11.1.
//
// The threshold rule of 04 §7.3 🔒 and the two refusals of 04 §8.2 🔒 are
// tested here rather than through the screen: they are the contract every
// implementation of the seam must keep, and a widget test would only prove
// that one screen happens to respect it.
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/guardians.dart';

void main() {
  group('guardians seam (04 §7.3 🔒)', () {
    test(
      'C-06-37 k = ⌈(n+1)/2⌉ for every n the spec allows — 2-of-2, 2-of-3, '
      '3-of-4, 3-of-5 — and n outside 2..5 is refused, never silently clamped',
      () {
        expect(guardianThreshold(2), 2);
        expect(guardianThreshold(3), 2, reason: 'the default 2-of-3');
        expect(guardianThreshold(4), 3);
        expect(guardianThreshold(5), 3);
        expect(() => guardianThreshold(1), throwsArgumentError);
        expect(() => guardianThreshold(6), throwsArgumentError);
        expect(guardianMinCount, 2);
        expect(guardianMaxCount, 5);
        expect(guardianDefaultCount, 3);
        // Only 2-of-2 carries the ADR 2026-09-06 checklist 4 🔒 confirmation.
        expect(guardianNeedsTypedConfirmation(2), isTrue);
        for (var n = 3; n <= 5; n++) {
          expect(guardianNeedsTypedConfirmation(n), isFalse);
        }
      },
    );

    test(
      'C-06-38 the seam refuses a set it must not seal: a size outside 2..5, '
      'and a member whose mutual ceremony is not done (04 §8.2 🔒 — no key '
      'material is ever wrapped to an unverified fingerprint)',
      () async {
        final repo = FakeGuardians(
          initial: const GuardianSetup(
            candidates: [
              TrustedMemberCandidate(
                memberId: 'm1',
                name: 'Sunita',
                ceremony: GuardianCeremony.done,
              ),
              TrustedMemberCandidate(
                memberId: 'm2',
                name: 'Harpreet',
                ceremony: GuardianCeremony.done,
              ),
              TrustedMemberCandidate(
                memberId: 'm3',
                name: 'Gurmeet',
                ceremony: GuardianCeremony.started,
              ),
            ],
          ),
        );
        addTearDown(repo.dispose);

        await expectLater(
          repo.save(['m1']),
          throwsA(isA<GuardiansFailure>()),
          reason: 'n = 1 is below the minimum',
        );
        await expectLater(
          repo.save(['m1', 'm2', 'm3', 'm1', 'm2', 'm1']),
          throwsA(isA<GuardiansFailure>()),
          reason: 'n = 6 is above the maximum',
        );
        await expectLater(
          repo.save(['m1', 'm3']),
          throwsA(isA<GuardiansFailure>()),
          reason: 'Gurmeet has not finished the mutual ceremony',
        );
        expect(repo.saved, isEmpty);

        await repo.save(['m1', 'm2']);
        expect(repo.saved, [
          ['m1', 'm2'],
        ]);
        expect(repo.current!.chosenIds, ['m1', 'm2']);
        expect(repo.current!.isConfigured, isTrue);
      },
    );
  });
}
