// At-rest encryption of the local ledger (03 §3, 06 §3, CLAUDE.md rule 7).
//
// The SQLCipher key is 32 random bytes from libsodium's CSPRNG through the
// injected [CryptoSuite] — never `dart:math` — kept under
// [KeyIds.databaseKey] in the platform keystore ([KeychainKeyStore]) and handed
// to `package:data`'s `sqlcipherSetup` as raw bytes. It is generated once per
// install and never derived from anything the user knows: the MPIN is a gate
// on the keystore, not a key (06 §4.4 🔒).
//
// ── Integration (main.dart, owned by the shell lane) ────────────────────────
//
//   final keys = KeychainKeyStore();
//   final suite = CryptoSuite(await SodiumInit.init());   // sodium_libs, once
//   final dbKey = await provisionDatabaseKey(keys, suite);
//   final result = await openLedgerDatabase(
//     NativeDatabase.createInBackground(file, setup: sqlcipherSetup(dbKey)),
//     cipherKey: dbKey,        // data verifies the key unlocked the file and
//   );                         // zeroises the buffer (03 §5, 04 §8.1)
//
// `openLedgerDatabase` zeroises `dbKey`; `sqlcipherSetup` captured its own hex
// copy for the connection, which the isolate discards once the pragma ran.
//
// ── SQLCipher binary ────────────────────────────────────────────────────────
//
// `sqlcipher_flutter_libs` is end-of-life ("update to version 3.x of
// package:sqlite3"). With sqlite3 3.x the cipher build is chosen through the
// build hook's user-defines, which pub reads from the **workspace root**
// pubspec.yaml (not app/pubspec.yaml — a workspace member's user-defines are
// ignored):
//
//   hooks:
//     user_defines:
//       sqlite3:
//         source: sqlcipher      # community SQLCipher build (OpenSSL on Android)
//
// Until that block lands the dev loop runs plain SQLite, `PRAGMA key` is a
// no-op there, and the file must not ship (main.dart's ⚠️ SPEC note).
// `dart test` in packages/data is unaffected — it uses the in-memory executor.
//
// ── A phone backup does not carry the books ─────────────────────────────────
//
// The database file is excluded from platform backups (E-05c-8, ADR
// 2026-09-05c) and the key is this-device-only in the keystore, so an iCloud /
// Google backup restored onto another phone has neither. S11.4 states this
// plainly (04 §7.6, ADR 2026-09-05f §G); restoration is the recovery ladder.
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

import '../../shared/seams/key_store.dart';

/// Length of the SQLCipher raw key (`sqlcipherSetup` asserts it).
const int databaseKeyBytes = 32;

/// Returns the SQLCipher key for this install, creating it on first run.
///
/// The returned buffer is the caller's to zeroise — pass it straight to
/// `openLedgerDatabase(…, cipherKey:)`, which does. A stored key of the wrong
/// length is treated as corruption and surfaces as [StateError] rather than
/// being silently replaced (replacing it would orphan the encrypted file).
Future<Uint8List> provisionDatabaseKey(KeyStore keys, CryptoSuite suite) async {
  final existing = await keys.read(KeyIds.databaseKey);
  if (existing != null) {
    if (existing.length != databaseKeyBytes) {
      zeroise(existing);
      throw StateError(
        'database key item has ${existing.length} bytes, expected $databaseKeyBytes',
      );
    }
    return existing;
  }
  final fresh = suite.randomBytes(databaseKeyBytes);
  await keys.write(KeyIds.databaseKey, fresh);
  return fresh;
}
