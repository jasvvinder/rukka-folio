// The app's door to the **guardian-set** routes of 04 §7.3 🔒 — the setup
// half of the recovery ladder, the one `recovery_api.dart` does not cover.
//
// ⚠️ WIRE — the contract is migration
// `server/supabase/migrations/0010_recovery_guardian_write_side.sql` and the
// `pull` + `recovery` blocks of
// `server/supabase/functions/sync-meta/index.ts`, pinned by
// `server/supabase/functions/_tests/recovery_meta.test.ts`. Two routes, one
// read and one write:
//
//   • GET  `sync-meta`  → the meta pull. Its `guardian_sets` array is the
//     **whole history** of the caller's sets, one entry per
//     `share_set_version`: `{subject_user_id, share_set_version, k, n,
//     guardian_user_ids, guardians:[{guardian_user_id, umk_pub_ed}]}`. It is
//     not paged by the meta cursor — `pull` builds it from
//     `tx.guardianSetHistory(subject)` on every call — so this client reads
//     it **without a cursor** and never advances one: cursors belong to the
//     sync engine, and a second reader of the same route must not move them.
//   • POST `sync-meta/recovery/guardians`
//     `{share_set_version, k, n, guardians:[{guardian_user_id, umk_pub_ed,
//     blob}]}` → `{share_set_version}`.
//
// **What the server does with the write** (`store_pg.publishGuardianSet`):
// the set row is inserted for `rf.user_id()` — *the authenticated user*, not
// an id in the body — and each `blob` lands in `wrapped_keys` as a
// `guardian_share` row addressed to **that guardian**. 0005's select policy
// then puts it out of the subject's own reach: a device that publishes a set
// can never read its own shares back. Nothing here tries to.
//
// **Three things this client must never do.**
//
//   1. It never seals to a key the server sent. `guardians[].umk_pub_ed` on
//      the read side is a *claim* — the server's copy of a public key — and
//      [GuardianSetMemberWire] exists to display and compare it, nothing
//      else. The write side cannot carry it: [GuardianSealWire] takes only a
//      [VerifiedGuardian], whose key comes from a [VerifiedUmkPublic], a type
//      only a passed ceremony mints (04 §8.2 🔒, CLAUDE.md rule 5).
//   2. It never computes `k`. 04 §7.3 🔒 fixes `k = ⌈(n+1)/2⌉` and 0010's
//      `rf.guardian_set_guard` enforces it in the database; the value is
//      derived once, by `guardianThreshold` in the seam, and carried.
//   3. It never opens or inspects a share. A blob is opaque bytes in and a
//      version out (04 §8.6) — and 04 §7.6 🔒 names "guardian shares in
//      reconstructable form" among the things that are never backed up, by
//      any route, so no accessor here returns share plaintext.
//
// Nothing here logs: bodies carry access tokens and sealed shares (rule 4).
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

import '../seams/http_transport.dart';
import 'recovery_api.dart';

// Both routes live in `sync-meta` and `recoveryError` names every refusal, so
// the guardian half speaks the recovery half's vocabulary rather than minting
// a second one for the same server words.
export 'recovery_api.dart'
    show
        RecoveryApiFailure,
        RecoveryRefusal,
        decodeB64Url,
        encodeB64Url,
        recoveryRefusalOf;

/// Route table under the edge-functions root (⚠️ WIRE sync-meta/index.ts).
final class GuardiansEndpoints {
  /// Creates the table from the functions root (`…/functions/v1/`).
  GuardiansEndpoints(Uri functionsRoot)
    : base = functionsRoot.path.endsWith('/')
          ? functionsRoot
          : functionsRoot.replace(path: '${functionsRoot.path}/');

  /// Slash-terminated root, so `resolve` appends rather than replaces.
  final Uri base;

  /// The function both routes live under.
  static const String function = 'sync-meta';

  /// `GET sync-meta` — the meta pull, read here for `guardian_sets` only.
  Uri get meta => base.resolve(function);

  /// `POST sync-meta/recovery/guardians` — 04 §7.3 Setup.
  Uri get publish => base.resolve('$function/recovery/guardians');
}

/// One guardian as the **read** side names them (⚠️ WIRE `pull`'s
/// `guardian_sets[].guardians[]`).
///
/// [umkPubEd] is the server's copy of that guardian's Ed25519 UMK half. It is
/// a claim and is treated as one: it is carried so a screen can show a set
/// that already exists and so a device can *compare*, and there is no path
/// from this field to a seal. Sealing takes [VerifiedGuardian], which this
/// class cannot produce.
final class GuardianSetMemberWire {
  /// Creates the row.
  GuardianSetMemberWire({
    required this.guardianUserId,
    required Uint8List umkPubEd,
  }) : umkPubEd = Uint8List.fromList(umkPubEd);

  /// Decodes one wire row.
  factory GuardianSetMemberWire.fromJson(Map<String, Object?> j) =>
      GuardianSetMemberWire(
        guardianUserId: j['guardian_user_id']! as String,
        umkPubEd: decodeB64Url(j['umk_pub_ed'] as String?),
      );

  /// Whose share it is.
  final String guardianUserId;

  /// The server's copy of their Ed25519 UMK half — never sealed to.
  final Uint8List umkPubEd;
}

/// One published generation of a subject's guardian set (⚠️ WIRE
/// `guardian_sets[]`).
///
/// A set is never rewritten: a change is the **next** `share_set_version`
/// (0010 `rf.guardian_set_guard`, ADR 2026-09-06 §3), so this history is
/// append-only and the set in force is simply the highest version.
final class GuardianSetWire {
  /// Creates the row.
  const GuardianSetWire({
    required this.subjectUserId,
    required this.shareSetVersion,
    required this.k,
    required this.n,
    this.members = const [],
  });

  /// Decodes one wire row. `guardians` is preferred; a body that carries only
  /// `guardian_user_ids` still yields the membership, with empty keys.
  factory GuardianSetWire.fromJson(Map<String, Object?> j) {
    final raw = j['guardians'];
    final members = <GuardianSetMemberWire>[];
    if (raw is List) {
      for (final g in raw) {
        if (g is Map) {
          members.add(
            GuardianSetMemberWire.fromJson(g.cast<String, Object?>()),
          );
        }
      }
    } else {
      for (final id in (j['guardian_user_ids'] as List<Object?>? ?? const [])) {
        if (id is String) {
          members.add(
            GuardianSetMemberWire(guardianUserId: id, umkPubEd: Uint8List(0)),
          );
        }
      }
    }
    return GuardianSetWire(
      subjectUserId: j['subject_user_id'] as String? ?? '',
      shareSetVersion: (j['share_set_version'] as num?)?.toInt() ?? 0,
      k: (j['k'] as num?)?.toInt() ?? 0,
      n: (j['n'] as num?)?.toInt() ?? members.length,
      members: List.unmodifiable(members),
    );
  }

  /// Whose set it is — `rf.user_id()` at the time it was published.
  final String subjectUserId;

  /// Its generation (04 §7.3 `share_set_version`).
  final int shareSetVersion;

  /// The quorum the database enforced — `⌈(n+1)/2⌉`, never recomputed here.
  final int k;

  /// How many people hold a share.
  final int n;

  /// Who they are.
  final List<GuardianSetMemberWire> members;

  /// The member ids, in the order the route sent them.
  List<String> get guardianUserIds => [
    for (final m in members) m.guardianUserId,
  ];
}

/// A person a share **may** be sealed to: a member whose UMK public key this
/// device verified by ceremony (04 §6), carried as a [VerifiedUmkPublic].
///
/// This is CLAUDE.md rule 5 as a type rather than a comment. There is no
/// constructor that takes bare key bytes, so a guardian assembled from the
/// server's `umk_pub_ed`, from a scanned-but-unchecked QR or from a name and
/// a user id **cannot be built**; `core_crypto` mints [VerifiedUmkPublic]
/// only inside `ceremony.dart`, after a fingerprint matched. A guardian whose
/// verification is not backed by a verified key is therefore not a guardian
/// this file can address, and [GuardianSealWire] takes nothing else.
final class VerifiedGuardian {
  /// Names [userId] as a guardian, addressed by the ceremony-verified [umk].
  ///
  /// [userId] is the `guardian_user_id` the route takes — the person, never a
  /// device.
  VerifiedGuardian({required this.userId, required this.umk}) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'a guardian has a user id');
    }
  }

  /// The `guardian_user_id` the write route takes.
  final String userId;

  /// Their ceremony-verified UMK (04 §8.2 🔒).
  final VerifiedUmkPublic umk;

  /// The Ed25519 half the route carries as `umk_pub_ed` — read off the
  /// verified key, never off the wire.
  Uint8List get umkPubEd => umk.public.ed25519;
}

/// A guardian's share, sealed to that guardian's verified UMK, on its way to
/// the write route.
///
/// The recipient is a [VerifiedGuardian] and the blob is a [SealedBlob], so
/// the two can be checked against each other: a sealer that addressed share
/// *i* to guardian *j* is refused here rather than uploaded, and a share can
/// never be filed under a person it was not sealed to.
final class SealedGuardianShare {
  /// Pairs [blob] with the guardian it is addressed to.
  ///
  /// Throws [ArgumentError] when [blob]'s recipient is not [guardian]'s
  /// verified fingerprint, or when it carries no bytes.
  SealedGuardianShare({required this.guardian, required this.blob}) {
    if (blob.recipient != guardian.umk.fingerprint) {
      throw ArgumentError.value(
        blob.recipient.hex,
        'blob',
        'a share is sealed to the guardian it is filed under (04 §7.3 🔒)',
      );
    }
    if (blob.bytes.isEmpty) {
      throw ArgumentError.value(0, 'blob', 'a sealed share has bytes');
    }
  }

  /// Who holds it.
  final VerifiedGuardian guardian;

  /// The sealed box — opaque here and opaque on the server.
  final SealedBlob blob;

  /// This guardian's entry in the write body.
  Map<String, Object?> toJson() => {
    'guardian_user_id': guardian.userId,
    'umk_pub_ed': encodeB64Url(guardian.umkPubEd),
    'blob': encodeB64Url(blob.bytes),
  };
}

/// The server's side of 04 §7.3 Setup.
abstract interface class GuardiansApi {
  /// Every generation of this user's guardian set the server holds, as the
  /// meta pull carries it. Empty when no set was ever published.
  Future<List<GuardianSetWire>> sets();

  /// Publishes the next generation. [shares] is one sealed share per
  /// guardian; `n` is its length and `k` is the caller's (the seam's
  /// `guardianThreshold`, 04 §7.3 🔒). Returns the version the server filed.
  Future<int> publish({
    required int shareSetVersion,
    required int k,
    required List<SealedGuardianShare> shares,
  });
}

/// [GuardiansApi] over the edge functions.
///
/// Refusals are `recovery_api.dart`'s: both routes live in the same function
/// and `recoveryError` names them, so one mapping serves both.
final class HttpGuardiansApi implements GuardiansApi {
  /// Creates the client. [accessToken] yields the 15-minute JWT of 06 §4;
  /// [clientVersion] rides `x-rukka-client-version` (06 §4.5).
  HttpGuardiansApi({
    required RkHttpTransport transport,
    required Uri functionsRoot,
    required Future<String?> Function() accessToken,
    String? clientVersion,
  }) : _http = transport,
       _endpoints = GuardiansEndpoints(functionsRoot),
       _token = accessToken,
       _version = clientVersion;

  final RkHttpTransport _http;
  final GuardiansEndpoints _endpoints;
  final Future<String?> Function() _token;
  final String? _version;

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const RecoveryApiFailure(
        RecoveryRefusal.unauthorized,
        'no session',
      );
    }
    return {
      'authorization': 'Bearer $token',
      if (json) 'content-type': 'application/json',
      if (_version != null) HttpRecoveryApi.clientVersionHeader: _version,
    };
  }

  @override
  Future<List<GuardianSetWire>> sets() async {
    // No `after=` and no `subject_user_id=`: the cursor is the sync engine's
    // (this read never advances it) and the subject is `rf.user_id()`, the
    // authenticated user — an id this device holds could be the wrong one
    // (bootstrap's ⚠️ SPEC on the two user ids) and naming it would be a
    // guess where the server already knows.
    final body = await _send(
      () async => _http.get(_endpoints.meta, headers: await _headers()),
    );
    return [
      for (final s in (body['guardian_sets'] as List<Object?>? ?? const []))
        if (s is Map) GuardianSetWire.fromJson(s.cast<String, Object?>()),
    ];
  }

  @override
  Future<int> publish({
    required int shareSetVersion,
    required int k,
    required List<SealedGuardianShare> shares,
  }) async {
    final body = await _send(
      () async => _http.post(
        _endpoints.publish,
        headers: await _headers(json: true),
        body: jsonEncode({
          'share_set_version': shareSetVersion,
          'k': k,
          'n': shares.length,
          'guardians': [for (final s in shares) s.toJson()],
        }),
      ),
    );
    // The server's word for the generation it filed, not the one asked for.
    return (body['share_set_version'] as num?)?.toInt() ?? shareSetVersion;
  }

  /// Runs one request and turns anything but 2xx into a named failure. A
  /// transport that never answered is [RecoveryRefusal.offline].
  Future<Map<String, Object?>> _send(
    Future<RkHttpResponse> Function() run,
  ) async {
    final RkHttpResponse res;
    try {
      res = await run();
    } on RecoveryApiFailure {
      rethrow;
    } on Exception catch (_) {
      throw const RecoveryApiFailure(RecoveryRefusal.offline);
    }
    Map<String, Object?> body = const {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) body = decoded.cast<String, Object?>();
      } on FormatException {
        body = const {};
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    throw RecoveryApiFailure(
      recoveryRefusalOf(body['error'] as String?, res.statusCode),
    );
  }
}
