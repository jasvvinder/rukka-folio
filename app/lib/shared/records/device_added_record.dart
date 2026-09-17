// The `device_added` signed record (06 §5 🔒 final paragraph; ADR
// 2026-09-05d §6 🔒: *the record **is** the certificate itself*).
//
// Every newly certified device — signup, link, guardian recovery, paper
// sheet, platform key sync, iOS Keychain remnant — announces itself as a
// signed record authored on that device (ADR 2026-09-05d §7: device events
// are records; the server's rows are its copy). This file is the one place
// that shapes and files that record. It adds no author and no wire path:
// [DeviceRecordAuthor] signs it (`shared/records`) and `MembersApi
// .postRecords` carries it on the meta channel's generic record route
// (05 §5, ADR 2026-09-05b §1) — the same two the invite and verification
// records already use.
//
// **What the server checks.** `server/supabase/functions/_shared/records.ts`
// `parseRecord` is the only gate this payload passes through: `id`,
// `tenant_id` and `author_device_id` canonical uuids, `kind` in
// `RECORD_KINDS`, `suite_version` an integer, `hlc` a bigint, `payload_json`
// base64 of a UTF-8 JSON **object** and `author_sig` base64 of exactly 64
// bytes. `applyRecord`'s `device_added` arm then returns `"no projection"` —
// it reads no field of the payload, because the `devices` row is the server's
// copy already. So the field names below are the *client's* contract, not the
// server's: they are kept identical to the `devices/certify` body
// (`http_auth_client.dart`) so one certificate is described one way on both
// wires, and a reader that has the record needs nothing else to rebuild the
// certificate and verify the chain (04 §3.4).
//
// **No retry.** 05 §5 gives records no durable queue: the outbox of §3 is for
// envelopes, and nothing in §5 states an ordering or retry policy for
// authored records. ⚠️ SPEC — rather than invent one, a failed post is
// dropped after a content-free log line and the device stays certified. The
// certificate is on the server (it accepted it) and reaches other devices on
// the meta channel regardless; what is lost is the *signed* announcement,
// which no later code path currently re-files. Named in the lane report.
//
// Nothing here logs anything but fixed event names (rule 4): a payload names
// a device.
library;

import 'package:core_crypto/core_crypto.dart' show Bytes, DeviceCert;

import '../../features/members/members_api.dart' show MembersApi;
import '../../features/members/server_members_repository.dart'
    show MembersRecordAuthor;

/// Posts already-signed records and returns the server's apply note per
/// record — [MembersApi.postRecords], named as a function so this file needs
/// no repository and no second client.
typedef PostRecords = Future<List<String>> Function(
  List<Map<String, Object?>> records,
);

/// What `features/auth` calls once a certificate has been **installed**
/// (06 §5 🔒). Implemented by [DeviceAddedRecorder]; the seam exists so the
/// auth client neither shapes a payload nor holds a record author.
abstract interface class DeviceAddedAnnouncer {
  /// Announces [cert] as a `device_added` record.
  ///
  /// **Never throws and never reports failure**: certification has already
  /// succeeded by the time this is called, and an unfiled announcement must
  /// not un-certify a device (06 §3 step 3 / ADR 2026-09-05d §2 — a device
  /// that is certified sees the tenant; nothing about that depends on this).
  Future<void> deviceAdded(
    DeviceCert cert, {
    required int umkKeyVersion,
    String? issuedByDevice,
  });
}

/// The [DeviceAddedAnnouncer] over the existing record author and the
/// existing record route.
final class DeviceAddedRecorder implements DeviceAddedAnnouncer {
  /// Creates the recorder. [tenantId] is the tenant the record is filed in —
  /// the one this install's ledger identity names.
  ///
  /// ⚠️ SPEC ADR 2026-09-05d §6: the ruling says a new device notifies
  /// *every* tenant the user belongs to. This build has exactly one tenant
  /// per install (the ledger mints it at first run, 04 §4 / ADR 2026-09-16
  /// §1) and no route that enumerates the others, so exactly one record is
  /// filed, in that tenant. Fanning out across tenants is the conservative
  /// thing left undone, not something guessed at here.
  const DeviceAddedRecorder({
    required this.author,
    required this.tenantId,
    required this.post,
    void Function(String event)? log,
  }) : _log = log ?? _noLog;

  /// Signs under this device's Ed25519 key (04 §3.3, 04 §8.3).
  final MembersRecordAuthor author;

  /// The tenant the record belongs to.
  final String tenantId;

  /// Where a signed record goes (05 §5).
  final PostRecords post;

  final void Function(String) _log;

  static void _noLog(String _) {}

  /// `kind` on the wire (`SignedRecordKind.deviceAdded`, `RECORD_KINDS`).
  static const String kind = 'device_added';

  /// Fixed event name for an announcement that did not land. Carries nothing
  /// about the device (rule 4).
  static const String unfiledEvent = 'device_added_unfiled';

  /// The payload for [cert] — the certificate itself (ADR 2026-09-05d §6),
  /// field for field as `devices/certify` sends it.
  static Map<String, Object?> payloadFor(
    DeviceCert cert, {
    required int umkKeyVersion,
    String? issuedByDevice,
  }) => {
    'device_id': cert.deviceId,
    'signature': Bytes.base64Url(cert.signature),
    'issued_at_ms': cert.issuedAtMs,
    // Self-issued today (04 §3.4 first bullet); a linked device's certificate
    // names the device that issued it (04 §9.1, M8) and the caller says so.
    'issued_by_device': issuedByDevice ?? cert.deviceId,
    'umk_key_version': umkKeyVersion,
  };

  @override
  Future<void> deviceAdded(
    DeviceCert cert, {
    required int umkKeyVersion,
    String? issuedByDevice,
  }) async {
    try {
      final record = await author.sign(
        tenantId: tenantId,
        kind: kind,
        payload: payloadFor(
          cert,
          umkKeyVersion: umkKeyVersion,
          issuedByDevice: issuedByDevice,
        ),
      );
      final notes = await post([record]);
      // A refused record comes back as a note, not an exception: `records.ts`
      // rolls the row back in the same transaction and answers
      // `rejected:<why>`. Treated exactly like a failed post — logged, never
      // retried, never allowed to matter.
      if (notes.any((n) => n.startsWith('rejected:'))) _log(unfiledEvent);
    } on Object {
      // Offline, refused, unsigned — all the same from here: the device is
      // certified and stays certified. No body, no id, no reason (rule 4).
      _log(unfiledEvent);
    }
  }
}
