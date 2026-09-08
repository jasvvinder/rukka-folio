// The status surface — exactly the five states 05 §9 owns (feeds 07 §1.7).
// Shape mirrors `app/lib/shared/seams/sync_client.dart` so the app adapter is
// a one-line switch; the engine speaks device ids where the app speaks names.
import 'package:meta/meta.dart';

/// One of five states. No other states; no spinners on entry save, ever.
@immutable
sealed class SyncStatus {
  const SyncStatus();
}

/// `Synced ✓` — outbox empty, cursors fresh, no author gaps.
final class Synced extends SyncStatus {
  /// Creates the state.
  const Synced();

  @override
  bool operator ==(Object other) => other is Synced;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'Synced';
}

/// `Saved on phone · will sync (N)`.
final class SavedWillSync extends SyncStatus {
  /// Creates the state.
  const SavedWillSync(this.count);

  /// Outbox depth (queued + in flight); ≥ 1.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is SavedWillSync && other.count == count;
  @override
  int get hashCode => Object.hash(2, count);
  @override
  String toString() => 'SavedWillSync($count)';
}

/// `Offline`.
final class Offline extends SyncStatus {
  /// Creates the state.
  const Offline();

  @override
  bool operator ==(Object other) => other is Offline;
  @override
  int get hashCode => 3;
  @override
  String toString() => 'Offline';
}

/// `Waiting for entries from {name}'s phone` — author gap < 24 h (ADR 05b §3).
/// The app maps [authorDevice] to the member's display name.
final class WaitingFor extends SyncStatus {
  /// Creates the state.
  const WaitingFor(this.authorDevice);

  /// The device whose `author_seq` run has a hole.
  final String authorDevice;

  @override
  bool operator ==(Object other) =>
      other is WaitingFor && other.authorDevice == authorDevice;
  @override
  int get hashCode => Object.hash(4, authorDevice);
  @override
  String toString() => 'WaitingFor($authorDevice)';
}

/// `Needs attention` → Inbox. [reasons] says why (typed, for the Inbox rows);
/// the app's state carries no payload and drops them.
final class NeedsAttention extends SyncStatus {
  /// Creates the state.
  const NeedsAttention(this.reasons);

  /// Every open reason, deduplicated, in first-seen order.
  final List<AttentionReason> reasons;

  @override
  bool operator ==(Object other) =>
      other is NeedsAttention &&
      other.reasons.length == reasons.length &&
      Iterable<int>.generate(reasons.length)
          .every((i) => other.reasons[i] == reasons[i]);
  @override
  int get hashCode => Object.hashAll([5, ...reasons]);
  @override
  String toString() =>
      'NeedsAttention(${reasons.map((r) => r.name).join(',')})';
}

/// The Inbox causes 05 §9 lists.
enum AttentionReason {
  /// A terminal push rejection sits in the outbox.
  rejection,

  /// A reader-side quarantine happened.
  quarantine,

  /// An envelope has waited for its key > 24 h.
  keyWaitOverdue,

  /// An author gap is open > 24 h.
  authorGapOverdue,

  /// An acked envelope never came back (ADR 05b §6).
  writeLost,

  /// Acked but un-observed for 30 days (ADR 05b §6 cap).
  unobservedOverdue,

  /// `hlc_future` / phone date looks wrong (05 §2).
  clockWarning,

  /// The device is suspended on the server's unsigned word (ADR 05b §2).
  suspended,

  /// The book is over quota (`rejected:quota`).
  quota,

  /// Pushes refused while the tenant is frozen.
  tenantFrozen,

  /// The server refused a book's route whole — pull 404 `unknown_book` or
  /// 403 `no_role` (05 §3 maps both to the Inbox: "ask your admin" /
  /// guided resolution). Nothing local was dropped.
  bookUnavailable,

  /// The server demands a newer app (426).
  updateRequired,
}
