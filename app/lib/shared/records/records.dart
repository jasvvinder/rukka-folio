/// Signed structural records authored on this device (ADR 2026-09-05b §1 🔒).
/// The record *shape* and the signature live in `core_crypto`; this library is
/// only the device-side wiring — keys out of the key store, an HLC, an id.
library;

export 'device_added_record.dart';
export 'device_record_author.dart';
