/// The live sync wiring: the engine-backed [SyncClient], its app-open trigger,
/// the session credential the transport carries (06 §4) and the platform half
/// of SPKI pinning (05 §1). The seam itself (and its fake) stays in
/// `shared/seams`.
library;

export 'auth_sync_credentials.dart';
export 'engine_sync_client.dart';
export 'sync_lifecycle.dart';
export 'tls_chain_source.dart';
