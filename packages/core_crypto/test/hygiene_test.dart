@Tags(['B'])
library;

// B-04-8 (ADR 2026-09-05 §8; 09 §2 B): key material never lives in a Dart
// `String`, never crosses a platform channel, and is zeroised after use.
// Test code may read files — the purity rule binds lib/, not test/.
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Same pattern as `scripts/check_purity.sh` (kept in step by hand): a
/// `String`-typed name that says it holds a key, secret, seed, share, nonce,
/// signature, ciphertext or plaintext.
final RegExp _stringKey = RegExp(
  r'\bString\??\s+[A-Za-z0-9_]*([Kk]ey|[Ss]ecret|[Ss]eed|[Ss]hare|[Nn]once|'
  r'[Ss]ignature|[Ss]ig\b|[Cc]iphertext|[Pp]riv|[Pp]laintext)[A-Za-z0-9_]*\b',
);
final RegExp _allowedName = RegExp(
  r'[Kk]eyVersion|[Kk]eyRef|[Kk]eyId|[Kk]ind\b',
);

Iterable<File> _libSources() =>
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

void main() {
  test('B-04-8 no String-typed key material and no platform channel in core_crypto/lib', () {
    final offenders = <String>[];
    for (final f in _libSources()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (_stringKey.hasMatch(line) && !_allowedName.hasMatch(line)) {
          offenders.add('${f.path}:${i + 1}: $line');
        }
        if (line.contains('MethodChannel') || line.contains('EventChannel')) {
          offenders.add('${f.path}:${i + 1}: platform channel');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('B-04-70 zeroize clears an exported UMK secret and dispose() locks every SecureKey', () async {
    final s = await testSuite(seed: 11);
    final umk = UmkKeyPair.generate(s);
    final secret = umk.exportSecretBytes();
    expect(secret.any((b) => b != 0), isTrue);
    s.zeroize(secret);
    expect(secret, everyElement(0));
    expect(secret, Uint8List(64));

    // After dispose the guarded memory is gone: no read path remains.
    umk.dispose();
    expect(() => umk.exportSecretBytes(), throwsA(anything));
    expect(
      () => umk.ed25519Secret.runUnlockedSync((b) => b.length),
      throwsA(anything),
    );

    final device = DeviceKeyPair.generate(s, deviceId: deviceA);
    device.dispose();
    expect(
      () => device.ed25519Secret.runUnlockedSync((b) => b.length),
      throwsA(anything),
    );

    final bk = BookKey.generate(s, bookId: bookA, keyVersion: 1);
    bk.dispose();
    expect(() => bk.key.runUnlockedSync((b) => b.length), throwsA(anything));
  });

  test('B-04-71 the public API exposes secrets only as SecureKey or Uint8List, never String', () async {
    final s = await testSuite(seed: 12);
    final umk = UmkKeyPair.generate(s);
    addTearDown(umk.dispose);
    expect(umk.exportSecretBytes(), isA<Uint8List>());
    expect(umk.x25519Secret.runUnlockedSync((b) => b), isA<Uint8List>());
    // toString of key holders must not print bytes.
    expect(umk.toString(), isNot(contains(Bytes.hex(umk.exportSecretBytes()))));
    expect(umk.toString(), isNot(contains(Bytes.hex(umk.public.x25519))));
    final fp = Fingerprint.of(s, umk.public);
    expect(fp.toString(), contains('…'));
    expect(fp.toString().length, lessThan(30));
  });
}
