// The signed-record mirror (03 §3.1 `signed_records_local`).
//
// A signed record is a structural fact authored on a certified device (ADR
// 2026-09-05b §1 🔒) — membership, roles, device add/revoke, and since ADR
// 2026-09-05d §7 the **verification events** of the ceremony (04 §6.4). The
// server's rows are its copy, never the origin, so this store is deliberately
// dumb about meaning: it keeps opaque `payload` and `sig` bytes and never
// re-serialises them. Interpretation, signature checking and the trust
// decision all live above it (`app/lib/shared/ledger/verified_members.dart`
// for the ceremony's), which is what keeps this package free of crypto.
//
// Two properties are the reason it is a store and not a raw query:
//
//   • the signed bytes round-trip byte-for-byte, so a field a newer build
//     added survives this one (03 §3.3.4 🔒, CLAUDE.md rule 6) *and* the
//     digest a verifier recomputes is the digest the author signed;
//   • [append] never overwrites an id already stored. Records are immutable
//     facts, and the same table takes rows from this device's own authoring
//     path and from a server pull — so an id collision must resolve to "keep
//     what is here", or a relayed record could displace a locally authored
//     one and a reader would verify the wrong bytes.
//
// `verified` and `seq` move only through [markVerified] and [attachSeq]:
// `verified` is a reader's conclusion (chain checked, 05b §1) and `seq` is the
// server's stamp at receipt (05b §5), neither of them signed.
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import 'database.dart';

/// One row of `signed_records_local` (03 §3.1).
///
/// [payload] and [sig] are the exact bytes as authored. Nothing in this
/// package decodes either.
@immutable
final class SignedRecordRow {
  /// Creates a row. The byte fields are copied so a caller's buffer cannot
  /// mutate what was stored.
  SignedRecordRow({
    required this.id,
    required this.tenantId,
    required this.kind,
    required Uint8List payload,
    required this.authorDevice,
    required Uint8List sig,
    required this.hlc,
    this.seq,
    this.verified = false,
  }) : payload = Uint8List.fromList(payload),
       sig = Uint8List.fromList(sig);

  /// Record id (uuid).
  final String id;

  /// Tenant the fact belongs to — also inside the signed header.
  final String tenantId;

  /// Record kind (`core_crypto`'s `SignedRecordKind`), stored as the plain
  /// string an unknown kind arrives as.
  final String kind;

  /// The exact signed payload bytes (UTF-8 JSON object, plaintext).
  final Uint8List payload;

  /// Authoring device id.
  final String authorDevice;

  /// `Ed25519(BLAKE2b-256(payload ‖ header))`, 64 bytes.
  final Uint8List sig;

  /// Author's HLC (05 §2).
  final int hlc;

  /// Server receipt sequence, or null until the record has been stored
  /// server-side (05b §5). Never signed.
  final int? seq;

  /// True once a reader has checked the signature and the chain (05b §1).
  final bool verified;
}

/// Layer 1 store over `signed_records_local` (03 §3.1).
final class SignedRecordMirror {
  /// Creates the store over [db].
  SignedRecordMirror(this.db);

  /// The client database.
  final LedgerDatabase db;

  /// Files [row] if its id is not already stored, and does nothing at all if
  /// it is. See the header: keeping the stored bytes is the whole point.
  ///
  /// Returns true when the row was written.
  Future<bool> append(SignedRecordRow row) => db.transaction(() async {
    // Read-then-insert rather than `insertOrIgnore`: SQLite's rowid tells a
    // caller nothing about whether an ignored insert wrote, and the answer is
    // load-bearing — `VerifiedMemberDirectory` refuses to believe a row it
    // holds in memory but the store does not.
    final existing =
        await (db.select(db.signedRecordsLocal)
              ..where((t) => t.id.equals(row.id))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return false;
    await db
        .into(db.signedRecordsLocal)
        .insert(
          SignedRecordsLocalCompanion.insert(
            id: row.id,
            tenantId: row.tenantId,
            kind: row.kind,
            payload: row.payload,
            authorDevice: row.authorDevice,
            sig: row.sig,
            hlc: row.hlc,
            seq: Value(row.seq),
            verified: Value(row.verified ? 1 : 0),
          ),
        );
    return true;
  });

  /// The record stored under [id], or null.
  Future<SignedRecordRow?> byId(String id) async {
    final r = await (db.select(
      db.signedRecordsLocal,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _row(r);
  }

  /// Every record of [kind], in `(hlc, id)` order.
  ///
  /// The order is the fold order: where two records name the same subject the
  /// later one wins, and `id` breaks an HLC tie so two devices reading the
  /// same set reach the same answer. [tenantId] restricts to one tenant;
  /// [believedOnly] drops rows a reader has not yet verified (C-05d-7: an
  /// unsigned — or unchecked — record is not believed).
  Future<List<SignedRecordRow>> ofKind(
    String kind, {
    String? tenantId,
    bool believedOnly = false,
  }) async {
    final q = db.select(db.signedRecordsLocal)
      ..where((t) {
        var w = t.kind.equals(kind);
        if (tenantId != null) w = w & t.tenantId.equals(tenantId);
        if (believedOnly) w = w & t.verified.equals(1);
        return w;
      })
      ..orderBy([
        (t) => OrderingTerm(expression: t.hlc),
        (t) => OrderingTerm(expression: t.id),
      ]);
    return (await q.get()).map(_row).toList();
  }

  /// Raises `verified` on [id]. Monotone: nothing here lowers it.
  Future<void> markVerified(String id) async {
    await (db.update(db.signedRecordsLocal)
          ..where((t) => t.id.equals(id) & t.verified.equals(0)))
        .write(const SignedRecordsLocalCompanion(verified: Value(1)));
  }

  /// Stamps the server [seq] on [id] if it has none. The first seq observed
  /// wins: the cut-off arithmetic of ADR 2026-09-05b §5 must not move because
  /// the same record was seen twice.
  Future<void> attachSeq(String id, int seq) async {
    await (db.update(db.signedRecordsLocal)
          ..where((t) => t.id.equals(id) & t.seq.isNull()))
        .write(SignedRecordsLocalCompanion(seq: Value(seq)));
  }

  static SignedRecordRow _row(SignedRecordsLocalData r) => SignedRecordRow(
    id: r.id,
    tenantId: r.tenantId,
    kind: r.kind,
    payload: r.payload,
    authorDevice: r.authorDevice,
    sig: r.sig,
    hlc: r.hlc,
    seq: r.seq,
    verified: r.verified == 1,
  );
}
