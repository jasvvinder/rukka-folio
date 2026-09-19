/// The live sync wiring: the engine-backed [SyncClient], its app-open trigger,
/// the session credential the transport carries (06 §4), the platform half of
/// SPKI pinning (05 §1) and the producers behind the recovery-ladder seams
/// (04 §7.3 🔒 over migration 0010). The seams themselves (and their fakes)
/// stay in `shared/seams`.
library;

export 'auth_sync_credentials.dart';
export 'engine_sync_client.dart';
export 'recovery_api.dart';
export 'recovery_seams.dart';
export 'sync_lifecycle.dart';
export 'tls_chain_source.dart';
