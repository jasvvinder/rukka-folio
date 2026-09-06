/// Local persistence: Drift + SQLCipher, projector (pure), snapshots, recompute (03). M2.
///
/// Spec owner: `docs/03-data-model.md`. Pure Dart — no Flutter (CLAUDE.md rule 3;
/// CI-enforced by `scripts/check_purity.sh`). The database takes an injected
/// `QueryExecutor`; the app supplies a SQLCipher-backed one (`sqlcipherSetup`),
/// tests use `NativeDatabase.memory()`. Hashing and decryption are injected too
/// (`BlobHasher`, `PayloadOpener`); `blake2bHasher` and `CryptoPayloadOpener`
/// are the `core_crypto`-backed implementations (M3).
library;

export 'src/crypto_opener.dart';
export 'src/database.dart';
export 'src/mirror.dart';
export 'src/payload_codec.dart';
export 'src/recompute.dart';
export 'src/tables.dart' show layer1Tables, layer2Tables;

/// Package identity used by the M0 hello-world gate.
const String packageName = 'data';
