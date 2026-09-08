@Tags(['F1'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

void main() {
  group('SyncClient seam (05 §9)', () {
    test('F1-13-9 SyncStatus has exactly the five 05 §9 states', () {
      // Exhaustive switch over the sealed type: a sixth variant fails to
      // compile here; a missing one fails the list below.
      String word(SyncStatus s) => switch (s) {
        Synced() => 'synced',
        SavedWillSync(:final count) => 'saved:$count',
        Offline() => 'offline',
        WaitingFor(:final name) => 'waiting:$name',
        NeedsAttention() => 'attention',
      };
      const all = <SyncStatus>[
        Synced(),
        SavedWillSync(3),
        Offline(),
        WaitingFor('Sunita'),
        NeedsAttention(),
      ];
      expect(all.map(word), [
        'synced',
        'saved:3',
        'offline',
        'waiting:Sunita',
        'attention',
      ]);
      expect(all.map((s) => s.runtimeType).toSet(), hasLength(5));
    });

    test(
      'F1-13-10 FakeSyncClient emits current then changes and counts syncNow',
      () async {
        final fake = FakeSyncClient(initial: const Offline());
        addTearDown(fake.dispose);
        final seen = <SyncStatus>[];
        final sub = fake.status.listen(seen.add);
        await Future<void>.delayed(Duration.zero);
        fake.current = const SavedWillSync(2);
        fake.afterSync = const Synced();
        await fake.syncNow();
        await fake.syncNow();
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(fake.syncNowCalls, 2);
        expect(seen.map((s) => s.runtimeType), [
          Offline,
          SavedWillSync,
          Synced,
          Synced,
        ]);
        expect((seen[1] as SavedWillSync).count, 2);
      },
    );
  });

  group('AuthClient seam (06 §2–§4)', () {
    test('F1-13-11 OTP round-trip: requestOtp → verifyOtp ticket → activateDevice → Active(uncertified)', () async {
      final fake = FakeAuthClient();
      addTearDown(fake.dispose);
      final states = <AuthState>[];
      final sub = fake.state.listen(states.add);
      await Future<void>.delayed(Duration.zero);
      expect(fake.current, isA<SignedOut>());

      await fake.requestOtp('+91 99999 00001');
      expect(fake.current, isA<OtpSent>());
      expect((fake.current as OtpSent).phone, '+91 99999 00001');

      final ticket = await fake.verifyOtp('123456');
      expect(ticket.value, isNotEmpty);
      // Still not signed in: the ticket must be consumed by registration.
      expect(fake.current, isA<OtpSent>());

      final session = await fake.activateDevice(ticket);
      expect(session.userId, isNotEmpty);
      final active = fake.current as Active;
      expect(active.session.deviceId, session.deviceId);
      expect(active.deviceCertified, isFalse);

      // Tickets are consumable exactly once (06 §2).
      await expectLater(
        fake.activateDevice(ticket),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.invalidTicket,
          ),
        ),
      );

      await fake.signOut();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(states.map((s) => s.runtimeType), [
        SignedOut,
        OtpSent,
        Active,
        SignedOut,
      ]);
    });

    test('F1-13-12 wrong codes: attempts counted, third failure expires the code; non-6-digit rejected; failNext fires once', () async {
      final fake = FakeAuthClient(expectedCode: '654321');
      addTearDown(fake.dispose);
      await expectLater(
        fake.verifyOtp('654321'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.noPendingCode,
          ),
        ),
      );
      await fake.requestOtp('+91 99999 00002');
      for (final left in [2, 1]) {
        await expectLater(
          fake.verifyOtp('000000'),
          throwsA(
            isA<AuthFailure>()
                .having((f) => f.kind, 'kind', AuthFailureKind.invalidCode)
                .having((f) => f.attemptsLeft, 'attemptsLeft', left),
          ),
        );
      }
      await expectLater(
        fake.verifyOtp('000000'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.codeExpired,
          ),
        ),
      );
      // A new code is required even for the right digits.
      await expectLater(
        fake.verifyOtp('654321'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.noPendingCode,
          ),
        ),
      );
      await fake.requestOtp('+91 99999 00002');
      expect((await fake.verifyOtp('654321')).value, isNotEmpty);

      final any = FakeAuthClient();
      addTearDown(any.dispose);
      await any.requestOtp('+91 99999 00003');
      await expectLater(any.verifyOtp('12345'), throwsA(isA<AuthFailure>()));
      any.failNext = const AuthFailure(AuthFailureKind.rateLimited);
      await expectLater(
        any.requestOtp('+91 99999 00003'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.rateLimited,
          ),
        ),
      );
      await any.requestOtp('+91 99999 00003');
      expect(any.requestedPhones, hasLength(2));
    });
  });
}
