// Who this install believes, and why (04 §6.4, §8.2 🔒; ADR 2026-09-05d §7).
//
// The gap this closes. Until now the mutual ceremony proved a member's UMK
// public key and then dropped it: `CryptoVerifyMemberRepository` logged a
// verification event and persisted no key, and `LedgerKeyMaterial
// .verifiedUmkOf` answered only for this install's own user. So every
// guardian candidate was refused as unverified — the correct posture, and one
// that made 04 §7.3 *Setup* impossible for anybody. This file is the missing
// half: a ceremony that succeeds stores the other member's verified key, and
// the key comes back out afterwards.
//
// Two properties are carried by types rather than by comment.
//
//   1. **What comes back out is a [VerifiedUmkPublic]** — the type
//      `core_crypto` mints and nothing in `app/` can construct (B-04-80 scans
//      for it) — never bytes plus a boolean. A caller therefore cannot
//      assemble a "verified" key that no ceremony produced, and
//      [VerifiedMemberSink.storeVerified] takes the same type, so a mismatch
//      or a raw [UmkPublic] does not compile.
//   2. **A key is believed only when a SIGNED record backs it.** C-05d-7
//      already pins that an unsigned `verification_events` row is not
//      believed; this is that rule one layer down, at the point where the key
//      becomes a *seal target*. Every key here arrives inside the payload of
//      a `verification_event` [SignedRecord] (ADR 2026-09-05d §7), and
//      [VerifiedMemberDirectory] re-checks the Ed25519 signature — against a
//      device it can resolve — on the write path *and* on every load. That is
//      what stops a server-relayed key from becoming a seal target: the
//      signed-record table takes rows from a pull as well as from this
//      device, and a row nothing this install can verify is stored and not
//      believed.
//
// Why the key is re-minted rather than restored. `VerifiedUmkPublic` has no
// public constructor and no deserialiser — deliberately (04 §8.2 🔒) — so the
// only way back to the type is through `core_crypto`'s ceremony module. This
// file uses the byte-for-byte QR check against the keys the record carries,
// exactly as `LocalLedger._selfVerifyUmk` does for the install's own UMK. The
// comparison is trivially true by construction; **all** of the security sits
// in the signature check that precedes it, which is why that check is not
// optional and not cached.
//
// ⚠️ SPEC (04 §6.4): [VerifiedUmkPublic.method] on a re-minted key always
// reads `qrInPerson`, because `Ceremony.verifyQr` is the only mint reachable
// from here and it records that method. The **authoritative** method is
// [VerifiedMember.method], read from the signed record — which is what 04
// §6.4 requires be logged, and what `verification_events.method` carries.
// 04 §6.3 already says the caller "may record it as remote in the
// verification event", so the record is the record; carrying the method into
// a restored key would need a `core_crypto` change and is not made here.
//
// ⚠️ SPEC (04 §6.4 *Delegated*): a verification performed by another member's
// device is not believed here. The conservative reading is taken — only
// records whose author this install can resolve to a device key are folded,
// which today means this user's own devices. Delegated verification needs a
// trust-transitivity ruling this lane did not have.
//
// Nothing here logs a key or a payload: a verification payload names people.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart' show Hlc;
import 'package:data/data.dart' show SignedRecordMirror, SignedRecordRow;
import 'package:sync_engine/sync_engine.dart' show VerifiedUmkSource;

/// Payload field names of a `verification_event` record (ADR 2026-09-05d §7).
///
/// ⚠️ WIRE `server/supabase/migrations/0008` — the server's copy in
/// `verification_events` (`subject_user`, `verifier_user`, `method`,
/// `result`) is derived from these fields; the record id is that row's
/// `source_record_id`.
abstract final class VerificationPayload {
  /// The user whose key was confirmed.
  static const String subjectUserId = 'subject_user_id';

  /// The user who performed the ceremony.
  static const String verifierUserId = 'verifier_user_id';

  /// `qr_in_person` | `code_remote` (04 §6.4).
  static const String method = 'method';

  /// Always `verified` here — a mismatch authors no record (04 §6.3).
  static const String result = 'result';

  /// Subject's Ed25519 UMK half, base64url, unpadded.
  static const String umkEd25519 = 'umk_ed25519';

  /// Subject's X25519 UMK half, base64url, unpadded.
  static const String umkX25519 = 'umk_x25519';

  /// Lower-case hex of the fingerprint the human confirmed (04 §3.1).
  static const String fingerprint = 'fingerprint';

  /// The one result a stored record may carry.
  static const String resultVerified = 'verified';
}

/// Wire spelling of [VerificationMethod] — the server's
/// `verification_events.method` check constraint.
String verificationMethodName(VerificationMethod m) => switch (m) {
  VerificationMethod.qrInPerson => 'qr_in_person',
  VerificationMethod.codeRemote => 'code_remote',
};

/// Reads [verificationMethodName] back. Null for a spelling this build does
/// not know — the record is then not believed rather than guessed at.
VerificationMethod? verificationMethodOf(String? name) => switch (name) {
  'qr_in_person' => VerificationMethod.qrInPerson,
  'code_remote' => VerificationMethod.codeRemote,
  _ => null,
};

/// One member this install believes, and the record that says so.
///
/// [umk] is the seal target (04 §8.2 🔒); [method] is the authoritative
/// method of 04 §6.4 — see the file header's ⚠️ SPEC note on why the two do
/// not always agree.
final class VerifiedMember {
  /// Creates the entry.
  const VerifiedMember({
    required this.userId,
    required this.umk,
    required this.method,
    required this.recordId,
    required this.hlc,
    required this.verifiedByDevice,
  });

  /// The user whose key was confirmed.
  final String userId;

  /// Their ceremony-verified UMK public halves.
  final VerifiedUmkPublic umk;

  /// How the ceremony was done (04 §6.4), from the signed record.
  final VerificationMethod method;

  /// The backing `verification_event` record.
  final String recordId;

  /// The record's HLC — the fold's ordering key.
  final int hlc;

  /// The device that performed and signed the ceremony.
  final String verifiedByDevice;
}

/// Where a completed ceremony's key is persisted.
///
/// Declared here rather than in `features/ceremony` so the ceremony feature
/// depends on `shared/`, never the other way round. The argument type is
/// [VerifiedUmkPublic]: a screen cannot reach this method with anything a
/// ceremony did not produce.
abstract class VerifiedMemberSink {
  /// Files the ceremony that just succeeded and makes [verified] available to
  /// [VerifiedUmkSource.verifiedUmkOf] from this moment on.
  ///
  /// Throws if the record cannot be signed or believed — a ceremony whose key
  /// did not land must not be reported as done, or *Setup* (04 §7.3) fails
  /// later and elsewhere.
  Future<VerifiedMember> storeVerified({
    required String userId,
    required VerifiedUmkPublic verified,
    required VerificationMethod method,
  });
}

/// Resolves a signed record's author device to the public key that must have
/// signed it, or null when this install cannot place the device.
typedef RecordAuthorResolver = DevicePublic? Function(String deviceId);

/// The verification directory: the members whose UMK a ceremony on a device
/// this install can vouch for confirmed (04 §6, §8.2 🔒).
final class VerifiedMemberDirectory
    implements VerifiedUmkSource, VerifiedMemberSink {
  /// Creates the directory over [records] (03 §3.1 `signed_records_local`).
  ///
  /// [author] yields this device's signing pair at the moment of writing —
  /// a callback, not a field, so a disposed ledger's zeroised key is never
  /// held here. [authorOf] resolves a record's author; the default places
  /// only this device, which is the conservative reading of 04 §6.4
  /// *Delegated* (see the file header).
  VerifiedMemberDirectory({
    required this.suite,
    required this.records,
    required this.tenantId,
    required this.selfUserId,
    required this.author,
    required this.tick,
    required this.newRecordId,
    this.authorOf,
  });

  /// libsodium (CLAUDE.md rule 7).
  final CryptoSuite suite;

  /// Layer 1 store the records rest in.
  final SignedRecordMirror records;

  /// The tenant these verifications belong to — also inside the signed
  /// header, so a record of another tenant cannot be folded in here.
  final String tenantId;

  /// This install's own user; its own key comes from [LedgerKeyMaterial], not
  /// from a record, so a record naming it is stored and ignored.
  final String selfUserId;

  /// This device's signing pair at the moment of use (04 §3.3).
  final DeviceKeyPair Function() author;

  /// The device's monotone HLC (05 §2) — injected, never a wall clock here.
  final Hlc Function() tick;

  /// Mints a record id (a canonical uuid).
  final String Function() newRecordId;

  /// Places a record's author, or null for "this device only".
  final RecordAuthorResolver? authorOf;

  final Map<String, VerifiedMember> _believed = {};

  /// Every member believed, by user id. A read-only view of the fold.
  Map<String, VerifiedMember> get believed => Map.unmodifiable(_believed);

  @override
  VerifiedUmkPublic? verifiedUmkOf(String userId) => _believed[userId]?.umk;

  /// The entry for [userId], with its authoritative method and record id.
  VerifiedMember? memberOf(String userId) => _believed[userId];

  /// Folds every stored `verification_event` of this tenant, in `(hlc, id)`
  /// order, keeping the last believed record per subject. Records whose
  /// signature does not check, whose author cannot be placed, or whose
  /// payload this build cannot read are skipped — and, when the signature
  /// checks, marked believed in the store so a later reader need not guess.
  ///
  /// Idempotent: call it at open and after any pull that wrote records.
  Future<void> load() async {
    _believed.clear();
    for (final row in await records.ofKind(
      SignedRecordKind.verificationEvent,
      tenantId: tenantId,
    )) {
      final member = _believe(row);
      if (member == null) continue;
      if (!row.verified) await records.markVerified(row.id);
      _believed[member.userId] = member;
    }
  }

  @override
  Future<VerifiedMember> storeVerified({
    required String userId,
    required VerifiedUmkPublic verified,
    required VerificationMethod method,
  }) async {
    if (!Uuid16.isCanonical(userId)) {
      throw ArgumentError.value(userId, 'userId', 'must be a canonical uuid');
    }
    // The record is built and signed here, then read back through the *same*
    // gate the load path uses: one believing function, so the write path
    // cannot be looser than the read path.
    final payload = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          VerificationPayload.subjectUserId: userId,
          VerificationPayload.verifierUserId: selfUserId,
          VerificationPayload.method: verificationMethodName(method),
          VerificationPayload.result: VerificationPayload.resultVerified,
          VerificationPayload.umkEd25519: _b64(verified.public.ed25519),
          VerificationPayload.umkX25519: _b64(verified.public.x25519),
          VerificationPayload.fingerprint: verified.fingerprint.hex,
        }),
      ),
    );
    final signed = SignedRecord.sign(
      suite,
      tenantId: tenantId,
      kind: SignedRecordKind.verificationEvent,
      payloadJson: payload,
      hlc: tick().raw,
      author: author(),
    );
    final row = SignedRecordRow(
      id: newRecordId(),
      tenantId: signed.tenantId,
      kind: signed.kind,
      payload: signed.payloadJson,
      authorDevice: signed.authorDeviceId,
      sig: signed.authorSig,
      hlc: signed.hlc,
    );
    if (!await records.append(row)) {
      // A fresh uuid collided with a stored record: believing the in-memory
      // row would mean believing bytes the store does not hold.
      throw StateError('record id ${row.id} is already stored');
    }
    final member = _believe(row);
    if (member == null) {
      throw StateError(
        'the verification record this device just signed is not believed — '
        'the author device cannot be resolved (04 §8.2)',
      );
    }
    await records.markVerified(row.id);
    final current = _believed[member.userId];
    // Last record wins, by (hlc, id) — the same order `load()` folds in, so a
    // re-open reaches the same answer as this live insert.
    if (current == null ||
        current.hlc < member.hlc ||
        (current.hlc == member.hlc &&
            current.recordId.compareTo(member.recordId) < 0)) {
      _believed[member.userId] = member;
    }
    return member;
  }

  /// The one gate. Returns the member a row proves, or null when it proves
  /// nothing this install may act on.
  VerifiedMember? _believe(SignedRecordRow row) {
    if (row.tenantId != tenantId) return null;
    if (row.kind != SignedRecordKind.verificationEvent) return null;

    // ⚠️ SPEC 03 §3.1: `signed_records_local` stores no `suite_version`, but
    // the signed header begins with one (`u8(suite_version)`), so the digest
    // can only be recomputed under the version this build runs. A record
    // authored under an older suite therefore stops being believed after a
    // suite bump — fail-closed (the member reads unverified and a ceremony
    // repeats), never fail-open, and harmless while there is one suite. The
    // fix is a `suite_version` column, which is a 03 schema change and not
    // this lane's to make; reported.
    final SignedRecord record;
    try {
      record = SignedRecord(
        suiteVersion: suiteVersion,
        tenantId: row.tenantId,
        kind: row.kind,
        payloadJson: row.payload,
        authorDeviceId: row.authorDevice,
        authorSig: row.sig,
        hlc: row.hlc,
        seq: row.seq,
      );
    } on Object {
      return null; // malformed row — not a record, so not evidence
    }

    // 1. Signed, by a device this install can place. Without this the rest is
    //    a server's word (C-05d-7, ADR 2026-09-05d §7).
    final author = _resolve(row.authorDevice);
    if (author == null) return null;
    if (!record.verifySignature(suite, author)) return null;

    // 2. A payload this build understands, with a `verified` result.
    final Map<String, Object?> payload;
    try {
      payload = record.payload;
    } on FormatException {
      return null;
    }
    if (payload[VerificationPayload.result] !=
        VerificationPayload.resultVerified) {
      return null;
    }
    final subject = payload[VerificationPayload.subjectUserId];
    if (subject is! String || !Uuid16.isCanonical(subject)) return null;
    final method = verificationMethodOf(
      payload[VerificationPayload.method] as String?,
    );
    if (method == null) return null;

    final ed = _unb64(payload[VerificationPayload.umkEd25519]);
    final x = _unb64(payload[VerificationPayload.umkX25519]);
    if (ed == null || x == null || ed.length != 32 || x.length != 32) {
      return null;
    }
    final UmkPublic umk;
    try {
      umk = UmkPublic(x25519: x, ed25519: ed);
    } on ArgumentError {
      return null;
    }

    // 3. The fingerprint the human confirmed is the fingerprint of the keys
    //    the record carries. Cheap, and it catches a record whose key bytes
    //    were swapped for ones that still parse.
    if (payload[VerificationPayload.fingerprint] !=
        Fingerprint.of(suite, umk).hex) {
      return null;
    }

    // 4. Back to the type, through the only mint there is (see the header).
    final minted = Ceremony.verifyQr(
      suite,
      scanned: QrPayload(
        userId: subject,
        umk: umk,
        nonce: suite.randomBytes(ceremonyNonceBytes),
      ),
      relayed: umk,
      relayedUserId: subject,
    );
    return switch (minted) {
      CeremonyVerified(:final verified) => VerifiedMember(
        userId: subject,
        umk: verified,
        method: method,
        recordId: row.id,
        hlc: row.hlc,
        verifiedByDevice: row.authorDevice,
      ),
      _ => null,
    };
  }

  DevicePublic? _resolve(String deviceId) {
    final resolver = authorOf;
    if (resolver != null) return resolver(deviceId);
    final me = author();
    return me.public.deviceId == deviceId ? me.public : null;
  }

  static String _b64(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List? _unb64(Object? value) {
    if (value is! String) return null;
    try {
      return base64Url.decode(value.padRight((value.length + 3) & ~3, '='));
    } on FormatException {
      return null;
    }
  }
}
