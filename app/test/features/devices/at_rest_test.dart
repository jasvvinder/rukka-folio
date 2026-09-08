@Tags(['C'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/at_rest.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import 'crypto_helpers.dart';

void main() {
  group('At-rest key (03 §3, 06 §3, rule 7)', () {
    test('C-06-5 provisionDatabaseKey draws 32 bytes from the injected suite once, keeps them under KeyIds.databaseKey, returns the same key afterwards, and sqlcipherSetup accepts it', () async {
      final keys = FakeKeyStore();
      final s = await sodium();
      var draws = 0;
      final suite = CryptoSuite(
        s,
        random: (n) {
          draws++;
          return Uint8List.fromList(List.generate(n, (i) => (i * 7) & 0xff));
        },
      );

      final first = await provisionDatabaseKey(keys, suite);
      expect(first, hasLength(databaseKeyBytes));
      expect(draws, 1);
      expect(keys.writes, [KeyIds.databaseKey]);
      expect(await keys.read(KeyIds.databaseKey), first);

      // Second run: no new randomness, same key, a fresh buffer.
      final second = await provisionDatabaseKey(keys, suite);
      expect(second, first);
      expect(draws, 1);
      expect(identical(first, second), isFalse);

      // Consumable by package:data's executor hook (raw-key pragma).
      expect(sqlcipherSetup(second), isA<Function>());

      // A wrong-length item is corruption, never silently replaced.
      await keys.write(KeyIds.databaseKey, Uint8List(16));
      await expectLater(
        provisionDatabaseKey(keys, suite),
        throwsA(isA<StateError>()),
      );
      expect(keys.writes, [KeyIds.databaseKey, KeyIds.databaseKey]);
    });

    test('C-06-6 with the live CSPRNG two installs never share a key, and the key is never a String on the KeyStore boundary', () async {
      final suite = await liveSuite();
      final a = await provisionDatabaseKey(FakeKeyStore(), suite);
      final b = await provisionDatabaseKey(FakeKeyStore(), suite);
      expect(a, isNot(equals(b)));
      expect(a.where((x) => x != 0).length, greaterThan(20));
    });
  });
}
