// Layer 1 behaviour (03 §3.1; ADR 2026-09-05b §3, §4, §6; ADR 2026-09-05c §2, §6):
// the append-only envelope mirror, the outbox state machine, per-author sequence
// numbers, the store epoch and the derived author-gap table.
import 'package:drift/drift.dart';

import 'database.dart';
import 'payload_codec.dart';

/// An envelope as it arrives from the server or from this device's authoring
/// path: routing fields in the clear, the object sealed in [blob].
final class EnvelopeRecord {
  /// Creates a record.
  const EnvelopeRecord({
    required this.envelopeId,
    required this.bookId,
    required this.objectId,
    required this.objectType,
    required this.keyVersion,
    required this.hlc,
    required this.authorDevice,
    required this.authorSeq,
    required this.blob,
    required this.blobHash,
    this.seq,
    this.verified = false,
  });

  /// Envelope id.
  final String envelopeId;

  /// Book.
  final String bookId;

  /// Object id.
  final String objectId;

  /// Registry type.
  final String objectType;

  /// Book-key version.
  final int keyVersion;

  /// HLC.
  final int hlc;

  /// Author device.
  final String authorDevice;

  /// Per-author sequence (from inside the ciphertext).
  final int authorSeq;

  /// Sealed object.
  final Uint8List blob;

  /// Hash of [blob].
  final Uint8List blobHash;

  /// Server seq, once known.
  final int? seq;

  /// Whether the signature chain already checked out.
  final bool verified;
}

/// Result of reading a blob back with its hash re-checked (ADR 05c §2).
sealed class BlobRead {
  const BlobRead();
}

/// The bytes are intact.
final class BlobOk extends BlobRead {
  /// Creates the result.
  const BlobOk(this.bytes);

  /// The blob.
  final Uint8List bytes;
}

/// The stored hash does not match: local corruption, never tampering
/// (tampering is a signature failure on an intact blob). Re-fetch / re-bootstrap.
final class BlobCorrupt extends BlobRead {
  /// Creates the result.
  const BlobCorrupt(this.envelopeId);

  /// Which envelope.
  final String envelopeId;
}

/// Outbox states (03 §3.1). Prune only at `observed` (ADR 05b §6).
enum PushState {
  /// Waiting to be pushed.
  queued,

  /// Push in progress.
  inflight,

  /// Server acknowledged with a seq.
  acked,

  /// Seen back on a pull — read-your-writes confirmed.
  observed,

  /// Server refused; reason recorded, row kept for Inbox.
  rejected,
}

const _allowedTransitions = <PushState, Set<PushState>>{
  PushState.queued: {PushState.inflight, PushState.rejected},
  PushState.inflight: {PushState.acked, PushState.queued, PushState.rejected},
  PushState.acked: {PushState.observed, PushState.queued, PushState.rejected},
  PushState.observed: {},
  PushState.rejected: {PushState.queued},
};

/// Operations on the mirror and outbox. Every method is a single transaction.
final class Mirror {
  /// Creates the facade over [db] with the hash function the mirror verifies with.
  Mirror(this.db, {required this.hasher});

  /// The database.
  final LedgerDatabase db;

  /// Blob hash (injected; `core_crypto` at M3).
  final BlobHasher hasher;

  // ── envelopes ─────────────────────────────────────────────────────────────

  /// Appends an envelope. Idempotent: a second append of the same id is a no-op
  /// (sync retries, 05 §4). Returns true when a row was inserted.
  Future<bool> append(EnvelopeRecord e) => db.transaction(() async {
    final exists =
        await (db.selectOnly(db.envelopesLocal)
              ..addColumns([db.envelopesLocal.envelopeId])
              ..where(db.envelopesLocal.envelopeId.equals(e.envelopeId)))
            .getSingleOrNull();
    if (exists != null) return false;
    await db
        .into(db.envelopesLocal)
        .insert(
          EnvelopesLocalCompanion.insert(
            envelopeId: e.envelopeId,
            bookId: e.bookId,
            objectId: e.objectId,
            objectType: e.objectType,
            keyVersion: e.keyVersion,
            hlc: e.hlc,
            seq: Value(e.seq),
            authorDevice: e.authorDevice,
            authorSeq: e.authorSeq,
            envelopeBlob: e.blob,
            blobHash: e.blobHash,
            verified: Value(e.verified ? 1 : 0),
          ),
        );
    return true;
  });

  /// Reads a blob, re-hashing it (ADR 05c §2).
  Future<BlobRead> readBlob(String envelopeId) async {
    final row = await (db.select(
      db.envelopesLocal,
    )..where((t) => t.envelopeId.equals(envelopeId))).getSingle();
    return _check(row);
  }

  /// Re-hashes an already-loaded row (Recompute iterates the mirror once).
  BlobRead readBlobOfRow(EnvelopesLocalData row) => _check(row);

  BlobRead _check(EnvelopesLocalData row) {
    final actual = hasher(row.envelopeBlob);
    if (actual.length != row.blobHash.length) {
      return BlobCorrupt(row.envelopeId);
    }
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != row.blobHash[i]) return BlobCorrupt(row.envelopeId);
    }
    return BlobOk(row.envelopeBlob);
  }

  /// Marks the signature chain verified.
  Future<void> markVerified(String envelopeId) =>
      _flags(envelopeId, const EnvelopesLocalCompanion(verified: Value(1)));

  /// Quarantines with a reason (a security event, never summed).
  Future<void> quarantine(String envelopeId, String reason) => _flags(
    envelopeId,
    EnvelopesLocalCompanion(
      quarantined: const Value(1),
      quarantineReason: Value(reason),
    ),
  );

  /// Holds a dangling reference until [targetId] arrives (ADR 05b §4).
  Future<void> hold(String envelopeId, {required String targetId}) => _flags(
    envelopeId,
    EnvelopesLocalCompanion(held: const Value(1), heldFor: Value(targetId)),
  );

  /// Releases a held envelope (its target arrived).
  Future<void> release(String envelopeId) => _flags(
    envelopeId,
    const EnvelopesLocalCompanion(held: Value(0), heldFor: Value(null)),
  );

  /// Records the server seq once acknowledged.
  Future<void> setSeq(String envelopeId, int seq) =>
      _flags(envelopeId, EnvelopesLocalCompanion(seq: Value(seq)));

  Future<void> _flags(String envelopeId, EnvelopesLocalCompanion c) async {
    final n = await (db.update(
      db.envelopesLocal,
    )..where((t) => t.envelopeId.equals(envelopeId))).write(c);
    if (n == 0) throw StateError('no envelope $envelopeId');
  }

  /// Every envelope of [bookId] in `(hlc, envelope_id)` order (03 §3.3 rule 1).
  Future<List<EnvelopesLocalData>> envelopesOf(String bookId) =>
      (db.select(db.envelopesLocal)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.hlc),
              (t) => OrderingTerm.asc(t.envelopeId),
            ]))
          .get();

  /// Distinct book ids in the mirror.
  Future<List<String>> bookIds() async {
    final rows = await db
        .customSelect(
          'SELECT DISTINCT book_id FROM envelopes_local ORDER BY book_id',
        )
        .get();
    return [for (final r in rows) r.read<String>('book_id')];
  }

  /// The guarded re-bootstrap path (ADR 05c §6): drops the book's mirror rows
  /// so 05 §8 can re-pull them. **Never touches the outbox** — rows the user
  /// authored stay until they are observed or shown in Inbox. Cursors reset.
  Future<int> rebootstrapBook(String bookId) => db.transaction(() async {
    await db.customStatement(
      'DROP TRIGGER IF EXISTS envelopes_local_append_only_delete',
    );
    try {
      final n = await (db.delete(
        db.envelopesLocal,
      )..where((t) => t.bookId.equals(bookId))).go();
      await (db.delete(
        db.syncCursors,
      )..where((t) => t.bookId.equals(bookId))).go();
      await (db.delete(
        db.authorGaps,
      )..where((t) => t.bookId.equals(bookId))).go();
      return n;
    } finally {
      await db.customStatement(_deleteGuard);
    }
  });

  static const _deleteGuard =
      'CREATE TRIGGER IF NOT EXISTS envelopes_local_append_only_delete '
      "BEFORE DELETE ON envelopes_local BEGIN SELECT RAISE(ABORT, 'envelopes_local is append-only; use rebootstrapBook'); END";

  // ── outbox ────────────────────────────────────────────────────────────────

  /// Queues an authored envelope for push. [createdAt] is injected (ms).
  Future<void> enqueue({
    required String envelopeId,
    required String bookId,
    required Uint8List blob,
    required int createdAt,
  }) => db
      .into(db.outbox)
      .insert(
        OutboxCompanion.insert(
          envelopeId: envelopeId,
          bookId: bookId,
          envelopeBlob: blob,
          createdAt: createdAt,
          pushState: PushState.queued.name,
        ),
      );

  /// Moves an outbox row along the state machine; illegal moves throw.
  Future<void> transition(
    String envelopeId,
    PushState to, {
    int? ackedSeq,
    String? rejectReason,
  }) => db.transaction(() async {
    final row = await (db.select(
      db.outbox,
    )..where((t) => t.envelopeId.equals(envelopeId))).getSingleOrNull();
    if (row == null) throw StateError('no outbox row $envelopeId');
    final from = PushState.values.byName(row.pushState);
    if (!_allowedTransitions[from]!.contains(to)) {
      throw StateError('outbox $envelopeId: $from → $to is not allowed');
    }
    if (to == PushState.acked && ackedSeq == null) {
      throw ArgumentError('acked needs the server seq');
    }
    if (to == PushState.rejected && rejectReason == null) {
      throw ArgumentError('rejected needs a reason');
    }
    await (db.update(
      db.outbox,
    )..where((t) => t.envelopeId.equals(envelopeId))).write(
      OutboxCompanion(
        pushState: Value(to.name),
        ackedSeq: to == PushState.acked
            ? Value(ackedSeq)
            : to == PushState.queued
            ? const Value(null)
            : const Value.absent(),
        rejectReason: to == PushState.rejected
            ? Value(rejectReason)
            : const Value.absent(),
      ),
    );
  });

  /// Deletes rows in `observed` — the only state that may be pruned (ADR 05b §6).
  Future<int> pruneObserved() => (db.delete(
    db.outbox,
  )..where((t) => t.pushState.equals(PushState.observed.name))).go();

  /// Outbox rows, oldest first.
  Future<List<OutboxData>> outboxRows({PushState? state}) =>
      (db.select(db.outbox)
            ..where(
              (t) => state == null
                  ? const Constant(true)
                  : t.pushState.equals(state.name),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  // ── author sequence ───────────────────────────────────────────────────────

  /// Hands out the next `author_seq` for (book, device): 1, 2, 3 … atomically
  /// (ADR 05b §3). The number goes inside the ciphertext.
  Future<int> nextAuthorSeq(String bookId, String deviceId) =>
      db.transaction(() async {
        final row =
            await (db.select(db.authorSeqLocal)..where(
                  (t) => t.bookId.equals(bookId) & t.deviceId.equals(deviceId),
                ))
                .getSingleOrNull();
        final next = row?.nextSeq ?? 1;
        await db
            .into(db.authorSeqLocal)
            .insertOnConflictUpdate(
              AuthorSeqLocalCompanion.insert(
                bookId: bookId,
                deviceId: deviceId,
                nextSeq: next + 1,
              ),
            );
        return next;
      });

  // ── store epoch ───────────────────────────────────────────────────────────

  /// The current store epoch, or null before the first sync.
  Future<String?> storeEpoch() async {
    final row = await db.select(db.storeEpoch).getSingleOrNull();
    return row?.epoch;
  }

  /// Records the epoch the server reported. When it differs from the stored one
  /// the server was restored (ADR 05b §6): every pull cursor resets and every
  /// `acked` outbox row goes back to `queued` so lost writes are re-pushed.
  /// Returns true when a reset happened.
  Future<bool> observeStoreEpoch(String epoch) => db.transaction(() async {
    final current = await storeEpoch();
    await db
        .into(db.storeEpoch)
        .insertOnConflictUpdate(
          StoreEpochCompanion.insert(id: const Value(1), epoch: epoch),
        );
    if (current == null || current == epoch) return false;
    await db.delete(db.syncCursors).go();
    await (db.update(
      db.outbox,
    )..where((t) => t.pushState.equals(PushState.acked.name))).write(
      const OutboxCompanion(pushState: Value('queued'), ackedSeq: Value(null)),
    );
    return true;
  });

  // ── author gaps (derived) ─────────────────────────────────────────────────

  /// Recomputes `author_gaps` for [bookId] from the mirror: for every author,
  /// each missing `author_seq` below the highest seen (ADR 05b §3). Returns the
  /// gaps found.
  Future<List<SeqGap>> recomputeAuthorGaps(String bookId) =>
      db.transaction(() async {
        final rows = await db
            .customSelect(
              'SELECT author_device, author_seq, hlc FROM envelopes_local '
              'WHERE book_id = ? ORDER BY author_device, author_seq',
              variables: [Variable.withString(bookId)],
            )
            .get();
        final byAuthor = <String, List<(int, int)>>{};
        for (final r in rows) {
          byAuthor.putIfAbsent(r.read<String>('author_device'), () => []).add((
            r.read<int>('author_seq'),
            r.read<int>('hlc'),
          ));
        }
        final gaps = <SeqGap>[];
        for (final MapEntry(key: author, value: seqs) in byAuthor.entries) {
          final present = {for (final s in seqs) s.$1: s.$2};
          final max = seqs.map((s) => s.$1).reduce((a, b) => a > b ? a : b);
          for (var expected = 1; expected <= max; expected++) {
            if (present.containsKey(expected)) continue;
            // Since when: the earliest envelope from this author past the hole.
            final since = seqs
                .where((s) => s.$1 > expected)
                .map((s) => s.$2)
                .reduce((a, b) => a < b ? a : b);
            gaps.add(SeqGap(bookId, author, expected, since));
          }
        }
        await (db.delete(
          db.authorGaps,
        )..where((t) => t.bookId.equals(bookId))).go();
        for (final g in gaps) {
          await db
              .into(db.authorGaps)
              .insert(
                AuthorGapsCompanion.insert(
                  bookId: g.bookId,
                  authorDevice: g.authorDevice,
                  expectedSeq: g.expectedSeq,
                  sinceHlc: g.sinceHlc,
                ),
              );
        }
        return gaps;
      });
}

/// A missing `author_seq` (ADR 05b §3) — the derived value behind `author_gaps`.
final class SeqGap {
  /// Creates a gap.
  const SeqGap(this.bookId, this.authorDevice, this.expectedSeq, this.sinceHlc);

  /// Book.
  final String bookId;

  /// Author.
  final String authorDevice;

  /// The missing number.
  final int expectedSeq;

  /// HLC of the earliest later envelope from that author.
  final int sinceHlc;

  @override
  String toString() =>
      'gap($bookId $authorDevice #$expectedSeq since $sinceHlc)';
}
