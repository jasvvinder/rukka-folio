@Tags(['C'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import 'crypto_helpers.dart';

void main() {
  late FakeKeyStore keys;
  late TestClock clock;
  late PinVault vault;

  setUp(() async {
    keys = FakeKeyStore();
    clock = TestClock(DateTime.utc(2026, 9, 7, 4, 30));
    vault = PinVault(keys: keys, suite: await liveSuite(), now: clock.call);
  });

  Future<void> miss([String pin = '000000']) async {
    expect(await vault.verify(pin), isA<PinRejected>());
  }

  group('PinVault (06 §4.4, ADR 2026-09-05d §5)', () {
    test('C-06-1 setPin stores HMAC(random key, pin) in one item; verify accepts the PIN and rejects any other; format is exactly six digits', () async {
      expect(await vault.status(), isA<PinNotSet>());
      expect(await vault.verify('123456'), isA<PinRejected>());

      for (final bad in ['12345', '1234567', '12a456', '', '１２３４５６']) {
        await expectLater(vault.setPin(bad), throwsA(isA<InvalidPinFormat>()));
      }
      await vault.setPin('482913');

      // Exactly one protected item, and the PIN itself is not in it.
      expect(keys.writes, [PinVault.itemId]);
      final raw = (await keys.read(PinVault.itemId))!;
      expect(raw, hasLength(77));
      expect(String.fromCharCodes(raw), isNot(contains('482913')));

      expect(await vault.verify('482913'), isA<PinAccepted>());
      expect(await vault.verify('482914'), isA<PinRejected>());
      expect(await vault.verify('48291'), isA<PinRejected>());

      // Two vaults, same PIN → different keys, different tags (random key,
      // never a KDF of the PIN — 04 §2).
      final other = FakeKeyStore();
      final v2 = PinVault(
        keys: other,
        suite: await liveSuite(),
        now: clock.call,
      );
      await v2.setPin('482913');
      expect(await other.read(PinVault.itemId), isNot(equals(raw)));
    });

    test('C-05d-1 attempt policy: 5 free, then 30 s · 1 min · 5 min · 15 min · 1 h; attempts during a cooldown are refused and not counted', () async {
      await vault.setPin('111111');
      for (var i = 1; i <= 4; i++) {
        await miss();
        final s = await vault.status() as PinReady;
        expect(s.failures, i);
        expect(s.inPenaltyBand, isFalse);
      }
      final waits = [
        const Duration(seconds: 30),
        const Duration(minutes: 1),
        const Duration(minutes: 5),
        const Duration(minutes: 15),
        const Duration(hours: 1),
      ];
      for (var k = 0; k < waits.length; k++) {
        final r = await vault.verify('000000') as PinRejected;
        final cd = r.status as PinCooldown;
        expect(cd.failures, 5 + k);
        expect(cd.until, clock.now.add(waits[k]), reason: 'failure ${5 + k}');

        // Inside the window: refused, even with the right PIN, and the
        // counter does not move.
        clock.advance(waits[k] - const Duration(seconds: 1));
        final again = await vault.verify('111111') as PinRejected;
        expect(again.status, isA<PinCooldown>());
        expect((again.status as PinCooldown).failures, 5 + k);
        expect(await vault.verify('000000'), isA<PinRejected>());
        expect((await vault.status() as PinCooldown).failures, 5 + k);

        // The window ends at `until` exactly.
        clock.advance(const Duration(seconds: 1));
        expect(await vault.status(), isA<PinReady>());
      }
      // Nine failures so far; the next is the tenth.
      expect((await vault.status() as PinReady).attemptsLeft, 1);
    });

    test('C-05d-2 the tenth failure disables the PIN; only the OTP + biometric reset path re-enables it, with a new PIN and a clean counter', () async {
      await vault.setPin('222222');
      for (var i = 0; i < 9; i++) {
        await miss();
        final s = await vault.status();
        if (s is PinCooldown) clock.now = s.until;
      }
      final r = await vault.verify('999999') as PinRejected;
      expect(r.status, isA<PinDisabled>());
      expect(await vault.status(), isA<PinDisabled>());

      // Disabled is not a cooldown: time does not help, the right PIN does
      // not help.
      clock.advance(const Duration(days: 30));
      expect(await vault.status(), isA<PinDisabled>());
      expect(
        (await vault.verify('222222') as PinRejected).status,
        isA<PinDisabled>(),
      );

      await vault.resetAfterReverification('333333');
      expect(await vault.status(), isA<PinReady>());
      expect((await vault.status() as PinReady).failures, 0);
      expect(await vault.verify('222222'), isA<PinRejected>());
      expect(await vault.verify('333333'), isA<PinAccepted>());
    });

    test('C-05d-3 counter and lockout live in the same protected item as the key: a fresh vault over the same store resumes the lockout; clearing everything else changes nothing', () async {
      await vault.setPin('444444');
      for (var i = 0; i < 6; i++) {
        await miss();
        final s = await vault.status();
        if (s is PinCooldown && i < 5) clock.now = s.until;
      }
      final before = await vault.status() as PinCooldown;
      expect(before.failures, 6);

      // "Clearing app data" = every other item gone, this one kept (it is
      // the keystore's, not the app sandbox's).
      await keys.write(KeyIds.databaseKey, Uint8List(32));
      await keys.delete(KeyIds.databaseKey);
      await keys.delete(KeyIds.wrappedUmk);

      final resumed = PinVault(
        keys: keys,
        suite: await liveSuite(),
        now: clock.call,
      );
      final after = await resumed.status() as PinCooldown;
      expect(after.failures, 6);
      expect(after.until, before.until);
      expect(keys.writes.toSet(), {PinVault.itemId, KeyIds.databaseKey});

      // The only thing that resets it is removing the item itself.
      await resumed.clear();
      expect(await resumed.status(), isA<PinNotSet>());
    });

    test('C-05d-4 a correct PIN resets the counter and lockout; a wrong one straight after starts from zero again', () async {
      await vault.setPin('555555');
      for (var i = 0; i < 5; i++) {
        await miss();
      }
      final cd = await vault.status() as PinCooldown;
      clock.now = cd.until;
      expect(await vault.verify('555555'), isA<PinAccepted>());
      final s = await vault.status() as PinReady;
      expect(s.failures, 0);
      expect(s.attemptsLeft, PinVault.maxFailures);
      await miss();
      expect((await vault.status() as PinReady).failures, 1);
    });

    test('C-05d-5 cooldownAfter table and a corrupt item: unknown layout reads as not set rather than as a guess', () async {
      expect(PinVault.cooldownAfter(0), isNull);
      expect(PinVault.cooldownAfter(4), isNull);
      expect(PinVault.cooldownAfter(5), const Duration(seconds: 30));
      expect(PinVault.cooldownAfter(9), const Duration(hours: 1));
      expect(PinVault.cooldownAfter(10), isNull);

      await keys.write(PinVault.itemId, Uint8List.fromList([9, 9, 9]));
      expect(await vault.status(), isA<PinNotSet>());
      expect(await vault.verify('000000'), isA<PinRejected>());
    });
  });
}
