@Tags(['F1'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

void main() {
  group('KeyStore seam (04 §3.3, ADR 2026-09-05d §4)', () {
    test('F1-13-13 FakeKeyStore: read returns a copy, write replaces, delete zeroises and forgets', () async {
      final store = FakeKeyStore();
      final secret = Uint8List.fromList(List.generate(32, (i) => i + 1));

      expect(await store.contains(KeyIds.databaseKey), isFalse);
      expect(await store.read(KeyIds.databaseKey), isNull);

      await store.write(KeyIds.databaseKey, secret);
      zeroise(secret); // caller's copy gone — the store kept its own
      final back = (await store.read(KeyIds.databaseKey))!;
      expect(back, List.generate(32, (i) => i + 1));

      back[0] = 99; // mutating a read copy never touches the store
      expect((await store.read(KeyIds.databaseKey))![0], 1);

      await store.write(KeyIds.databaseKey, Uint8List.fromList([7, 7]));
      expect(await store.read(KeyIds.databaseKey), [7, 7]);
      expect(store.writes, [KeyIds.databaseKey, KeyIds.databaseKey]);

      await store.delete(KeyIds.databaseKey);
      expect(await store.contains(KeyIds.databaseKey), isFalse);
      await store.delete(KeyIds.databaseKey); // idempotent
    });

    test('F1-13-14 zeroise overwrites every byte in place', () {
      final b = Uint8List.fromList([1, 2, 3, 4]);
      zeroise(b);
      expect(b, [0, 0, 0, 0]);
    });
  });
}
