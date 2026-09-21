// Suite C — the seam between the ceremony and the key it proves (04 §6.3,
// §8.2 🔒).
//
// `CryptoVerifyMemberRepository` used to log a verification and keep nothing.
// These tests pin the repaired contract end to end, over the *real*
// `VerifiedMemberDirectory` inside a real `LocalLedger`: the key lands, it
// lands before the event is logged, a mismatch lands nothing, and a store
// that fails is not reported as a completed ceremony.
//
// Synthetic ids and keys only (rule 4).
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ceremony/ceremony_repository.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

const _memberId = '3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const _strangerId = '11112222-3333-4444-8555-666677778888';

Uint8List _bytes(int seed, [int length = 32]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (seed + i * 7) % 256));

Uint8List get _nonceBytes => _bytes(9, ceremonyNonceBytes);

Uint8List get _showerRandom => _bytes(21, sasContributionBytes);

FakeVerifierSessionRelay _relay(
  CryptoSuite suite, {
  required UmkPublic umk,
  String userId = _memberId,
}) => FakeVerifierSessionRelay(
  commitmentBytes: sasCommitment(
    suite,
    fp: Fingerprint.of(suite, umk),
    userId: userId,
    showerRandom: _showerRandom,
  ),
  openingBytes: _showerRandom,
  issuedAt: testNow(),
);

/// Records the order in which the repository touched its two sinks.
final class _TracingSink implements VerifiedMemberSink {
  _TracingSink(this.inner, this.trace);

  final VerifiedMemberSink inner;
  final List<String> trace;
  Object? failure;

  @override
  Future<VerifiedMember> storeVerified({
    required String userId,
    required VerifiedUmkPublic verified,
    required VerificationMethod method,
  }) async {
    trace.add('store');
    final f = failure;
    if (f != null) throw f;
    return inner.storeVerified(
      userId: userId,
      verified: verified,
      method: method,
    );
  }
}

final class _TracingLog implements CeremonyEventLog {
  _TracingLog(this.trace);

  final List<String> trace;
  final List<String> mismatches = [];
  final List<(String, VerificationMethod)> verifications = [];

  @override
  Future<void> mismatch({required String memberName}) async {
    trace.add('mismatch');
    mismatches.add(memberName);
  }

  @override
  Future<void> verified({
    required String memberName,
    required VerificationMethod method,
  }) async {
    trace.add('log');
    verifications.add((memberName, method));
  }
}

void main() {
  group('CryptoVerifyMemberRepository persists what it proved (04 §8.2 🔒)', () {
    late LocalLedger ledger;
    late CryptoSuite suite;
    late UmkKeyPair memberUmk;

    setUp(() async {
      ledger = await openTestLedger();
      await ledger.bootstrapSolo(firstBookName: 'Me');
      suite = ledger.suite;
      memberUmk = UmkKeyPair.generate(suite);
      addTearDown(memberUmk.dispose);
    });

    test(
      'C-06-66 a QR ceremony that matches stores the member key and only then '
      'logs the event: the ledger answers for the member afterwards, which is '
      'what 04 §7.3 Setup needs',
      () async {
        final trace = <String>[];
        final log = _TracingLog(trace);
        final sink = _TracingSink(ledger.verifiedMembers, trace);
        final repository = CryptoVerifyMemberRepository(
          suite: suite,
          relayedUmk: memberUmk.public,
          relayedUserId: _memberId,
          relay: _relay(suite, umk: memberUmk.public),
          memberName: 'Sunita',
          now: testNow,
          log: log,
          keys: sink,
        );

        expect(ledger.keyMaterial.verifiedUmkOf(_memberId), isNull);

        final result = await repository.verifyScanned(
          QrPayload(
            userId: _memberId,
            umk: memberUmk.public,
            nonce: _nonceBytes,
          ).encode(),
        );

        expect(result, isA<CeremonyVerified>());
        // Store first: a screen must never say *verified* over a key nothing
        // kept.
        expect(trace, ['store', 'log']);
        expect(log.verifications, [('Sunita', VerificationMethod.qrInPerson)]);
        final back = ledger.keyMaterial.verifiedUmkOf(_memberId);
        expect(back, isA<VerifiedUmkPublic>());
        expect(back!.public, memberUmk.public);
        expect(
          ledger.verifiedMembers.memberOf(_memberId)!.method,
          VerificationMethod.qrInPerson,
        );
      },
    );

    test(
      'C-06-67 the key stored is the one the SERVER relayed, under the user '
      'id the server relayed — a scanned payload is compared, never trusted',
      () async {
        final trace = <String>[];
        final repository = CryptoVerifyMemberRepository(
          suite: suite,
          relayedUmk: memberUmk.public,
          relayedUserId: _memberId,
          relay: _relay(suite, umk: memberUmk.public),
          memberName: 'Sunita',
          now: testNow,
          log: _TracingLog(trace),
          keys: _TracingSink(ledger.verifiedMembers, trace),
        );

        await repository.verifyScanned(
          QrPayload(
            userId: _memberId,
            umk: memberUmk.public,
            nonce: _nonceBytes,
          ).encode(),
        );

        expect(
          ledger.verifiedMembers.memberOf(_memberId)!.umk.public,
          memberUmk.public,
        );
        expect(ledger.keyMaterial.verifiedUmkOf(_strangerId), isNull);
      },
    );

    test(
      'C-06-68 a mismatch stores nothing: the hard-fail path writes the '
      'security event and leaves the member unverified (04 §6.3 🔒)',
      () async {
        final trace = <String>[];
        final log = _TracingLog(trace);
        final impostor = UmkKeyPair.generate(suite);
        addTearDown(impostor.dispose);
        final repository = CryptoVerifyMemberRepository(
          suite: suite,
          relayedUmk: memberUmk.public,
          relayedUserId: _memberId,
          relay: _relay(suite, umk: memberUmk.public),
          memberName: 'Sunita',
          now: testNow,
          log: log,
          keys: _TracingSink(ledger.verifiedMembers, trace),
        );

        final result = await repository.verifyScanned(
          QrPayload(
            userId: _memberId,
            umk: impostor.public,
            nonce: _nonceBytes,
          ).encode(),
        );

        expect(result, isA<CeremonyMismatch>());
        expect(trace, ['mismatch']);
        expect(log.mismatches, ['Sunita']);
        expect(ledger.keyMaterial.verifiedUmkOf(_memberId), isNull);
        expect(ledger.verifiedMembers.believed, isEmpty);
      },
    );

    test('C-06-69 a store that fails is not a completed ceremony: the error '
        'reaches the caller and nothing is logged as verified', () async {
      final trace = <String>[];
      final log = _TracingLog(trace);
      final sink = _TracingSink(ledger.verifiedMembers, trace)
        ..failure = StateError('disk full');
      final repository = CryptoVerifyMemberRepository(
        suite: suite,
        relayedUmk: memberUmk.public,
        relayedUserId: _memberId,
        relay: _relay(suite, umk: memberUmk.public),
        memberName: 'Sunita',
        now: testNow,
        log: log,
        keys: sink,
      );

      await expectLater(
        repository.verifyScanned(
          QrPayload(
            userId: _memberId,
            umk: memberUmk.public,
            nonce: _nonceBytes,
          ).encode(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(log.verifications, isEmpty);
      expect(trace, ['store']);
      expect(ledger.keyMaterial.verifiedUmkOf(_memberId), isNull);
    });

    test(
      'C-06-70 the code path stores too, and the record carries codeRemote — '
      'the method 04 §6.4 requires be logged is the one that comes back',
      () async {
        final trace = <String>[];
        final log = _TracingLog(trace);
        final relay = _relay(suite, umk: memberUmk.public);
        final repository = CryptoVerifyMemberRepository(
          suite: suite,
          relayedUmk: memberUmk.public,
          relayedUserId: _memberId,
          relay: relay,
          memberName: 'Sunita',
          now: testNow,
          log: log,
          keys: _TracingSink(ledger.verifiedMembers, trace),
          mode: CeremonyMode.remote,
        );

        expect(await repository.armCodePath(), CodePathArming.armed);
        final digits = sasCode(
          suite,
          fp: Fingerprint.of(suite, memberUmk.public),
          userId: _memberId,
          showerRandom: _showerRandom,
          verifierRandom: relay.contributions.single,
        );

        final result = await repository.verifyTyped(digits);

        expect(result, isA<CeremonyVerified>());
        expect(trace, ['store', 'log']);
        expect(
          ledger.verifiedMembers.memberOf(_memberId)!.method,
          VerificationMethod.codeRemote,
        );
        expect(
          ledger.keyMaterial.verifiedUmkOf(_memberId)!.public,
          memberUmk.public,
        );
      },
    );
  });
}
