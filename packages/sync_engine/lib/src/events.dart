// Typed events the engine surfaces — security events and Inbox causes.
// Nothing here carries financial content (CLAUDE.md rule 4): ids and reasons only.
import 'package:meta/meta.dart';

/// Something the app or a test must be able to see. Never silent.
@immutable
sealed class SyncEvent {
  const SyncEvent(this.atMs);

  /// Engine clock when raised.
  final int atMs;
}

/// An acked envelope did not come back in the device's own pull (ADR 05b §6).
final class WriteLost extends SyncEvent {
  /// Creates the event.
  const WriteLost(super.atMs, this.envelopeId);

  /// Envelope re-pushed.
  final String envelopeId;
}

/// A server row disagrees with (or lacks) its signed record (ADR 05b §1).
final class MetaMismatch extends SyncEvent {
  /// Creates the event.
  const MetaMismatch(super.atMs, this.table, this.rowId, this.detail);

  /// Server table.
  final String table;

  /// Row id.
  final String rowId;

  /// What differed.
  final String detail;
}

/// The device entered `suspended` on an unsigned revocation claim (ADR 05b §2).
final class Suspended extends SyncEvent {
  /// Creates the event.
  const Suspended(super.atMs, this.source);

  /// `401 device_revoked` or `devices row`.
  final String source;
}

/// Suspension lifted (auth succeeded or a signed record resolved it).
final class Resumed extends SyncEvent {
  /// Creates the event.
  const Resumed(super.atMs);
}

/// The device's own verified revocation arrived — keys and projections dropped.
final class Wiped extends SyncEvent {
  /// Creates the event.
  const Wiped(super.atMs, this.recordId);

  /// The revocation record.
  final String recordId;
}

/// A verified `member_removal` names this user — book keys dropped, the
/// mirror kept (05 §5 "keep nothing but the row saying it existed").
final class KeysDropped extends SyncEvent {
  /// Creates the event.
  const KeysDropped(super.atMs, this.recordId);

  /// The removal record.
  final String recordId;
}

/// A terminal push rejection (05 §3 table).
final class PushRejected extends SyncEvent {
  /// Creates the event.
  const PushRejected(super.atMs, this.envelopeId, this.result, {this.check});

  /// Envelope.
  final String envelopeId;

  /// The `result` string.
  final String result;

  /// Named shape check, if any.
  final String? check;
}

/// `413 batch_too_large` — the whole push batch was refused, nothing judged;
/// the rows stay queued and the next batch is smaller (05 §3 caps).
final class BatchRefused extends SyncEvent {
  /// Creates the event.
  const BatchRefused(super.atMs, this.bookId, this.envelopes, this.bytes);

  /// Book.
  final String bookId;

  /// Envelopes in the refused batch.
  final int envelopes;

  /// Blob bytes in the refused batch.
  final int bytes;
}

/// A book's route was refused as a whole (pull 404 `unknown_book` / 403
/// `no_role`, or the same on push). Cursor, mirror and outbox stay put.
final class PullRefused extends SyncEvent {
  /// Creates the event.
  const PullRefused(super.atMs, this.bookId, this.code, {this.route = 'pull'});

  /// Book.
  final String bookId;

  /// The server's `error` code.
  final String code;

  /// `pull` or `push`.
  final String route;
}

/// `rejected:rate_limited` — backing off (never Inbox; no UI, 13 §6).
final class Throttled extends SyncEvent {
  /// Creates the event.
  const Throttled(super.atMs, this.untilMs);

  /// When the next push may run.
  final int untilMs;
}

/// `rejected:quota` — pushes to the book stop; reads continue.
final class QuotaStopped extends SyncEvent {
  /// Creates the event.
  const QuotaStopped(super.atMs, this.bookId);

  /// Book.
  final String bookId;
}

/// `rejected:tenant_frozen` — pushes stop tenant-wide; pull continues.
final class TenantFrozen extends SyncEvent {
  /// Creates the event.
  const TenantFrozen(super.atMs);
}

/// A pulled envelope was quarantined by this reader (04 §8.3).
final class Quarantined extends SyncEvent {
  /// Creates the event.
  const Quarantined(super.atMs, this.envelopeId, this.reason);

  /// Envelope.
  final String envelopeId;

  /// Reason as stored in `quarantine_reason`.
  final String reason;
}

/// A pulled envelope failed `blob_hash` — corruption, not tampering
/// (ADR 05c §2); it is re-fetched, no security event.
final class BlobCorruptOnPull extends SyncEvent {
  /// Creates the event.
  const BlobCorruptOnPull(super.atMs, this.envelopeId);

  /// Envelope.
  final String envelopeId;
}

/// A pulled envelope waits for its book key (05 §4 `key_wait`).
final class KeyWait extends SyncEvent {
  /// Creates the event.
  const KeyWait(super.atMs, this.envelopeId, this.bookId, this.keyVersion);

  /// Envelope.
  final String envelopeId;

  /// Book.
  final String bookId;

  /// Missing version.
  final int keyVersion;
}

/// A signed record was not applied (chain failed or it did not count).
final class RecordIgnored extends SyncEvent {
  /// Creates the event.
  const RecordIgnored(super.atMs, this.recordId, this.reason);

  /// Record.
  final String recordId;

  /// Why.
  final String reason;
}

/// A queued envelope was re-sealed under a newer book key before push (05 §3).
final class Resealed extends SyncEvent {
  /// Creates the event.
  const Resealed(super.atMs, this.envelopeId, this.fromVersion, this.toVersion);

  /// Envelope.
  final String envelopeId;

  /// Old `key_version`.
  final int fromVersion;

  /// New `key_version`.
  final int toVersion;
}

/// The server answered 426.
final class UpdateRequiredEvent extends SyncEvent {
  /// Creates the event.
  const UpdateRequiredEvent(super.atMs);
}

/// A revocation cut-off moved (ADR 2026-09-06 §3: only ever earlier).
final class CutoffChanged extends SyncEvent {
  /// Creates the event.
  const CutoffChanged(super.atMs, this.deviceId, this.previousSeq, this.seq);

  /// Revoked device.
  final String deviceId;

  /// Previous cut-off (null = none).
  final int? previousSeq;

  /// New cut-off.
  final int seq;
}
