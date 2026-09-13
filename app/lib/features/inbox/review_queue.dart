// The Inbox feature's seam to the review queue (02 §3 post-then-review, 07
// §9, 13 §3.2 S6/S6.1/S6.2). Phase A: the screens run against
// [FakeReviewQueue]; the real one arrives with the sync/server lanes, which
// own the signed approve/reject envelopes (02 §3, 04 §8.3).
//
// ⚠️ WIRE — the whole interface is this lane's. Two rules the real
// implementation must keep, because the screens above assume them and cannot
// check them:
//
//  1. **The entries in here are already in the book.** 02 §3 🔒: every entry
//     posts and affects balances the moment it is saved; the review flag is a
//     threshold, not a gate. Nothing on S6/S6.1/S6.2 may draw the money as
//     pending, held, or waiting — that state does not exist.
//  2. **Nobody clears their own flag** (02 §7.2 item 1 🔒). The queue must
//     never yield a group authored by the reading member, and a book with one
//     member raises no flag at all. The screens have no author identity of
//     their own to filter on.
//
// Nothing here holds money as anything but integer paise (CLAUDE.md rule 1).
import 'dart:async';

import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/widgets.dart';

/// What the reviewer decides about one flagged entry (02 §3).
///
/// *Skip* is deliberately absent: 07 §9's third stepper action leaves the flag
/// exactly as it was, so it reaches no envelope and is a screen-local state.
enum ReviewDecision {
  /// A signed envelope clearing the flag (02 §3).
  approve,

  /// A signed rejection that auto-posts the mirror reversal with the reason
  /// (02 §3, §5). The original and the reversal both stay visible.
  reject,
}

/// One flagged entry as the reviewer sees it (07 §9 stepper contents: photo,
/// amount, A/Cs, date, author, note).
@immutable
final class ReviewEntry {
  /// Creates the row.
  const ReviewEntry({
    required this.id,
    required this.paise,
    required this.fromLabel,
    required this.toLabel,
    required this.date,
    required this.postedAt,
    this.note,
    this.hasPhoto = false,
  });

  /// The entry's envelope id.
  final String id;

  /// Signed integer paise from the money account's own side: positive is
  /// money in, negative is money out (02 §10 🔒 — this is a consumer surface,
  /// so the words beside it are *Money in / Money out*, never Dr/Cr).
  final int paise;

  /// Where the money came from, in the user's words.
  final String fromLabel;

  /// Where the money went, in the user's words.
  final String toLabel;

  /// The accounting date (03 §1: a calendar day, not an instant).
  final LocalDate date;

  /// When the author saved it — the moment it started counting (02 §3).
  final DateTime postedAt;

  /// The author's own narration, when they wrote one.
  final String? note;

  /// Whether a bill photo is attached (07 §9 thumbnails, *ask for a better
  /// photo*).
  final bool hasPhoto;
}

/// S6.1 — one card per (author, book, day), never one per item (13 §4.1 P3).
@immutable
final class ReviewGroup {
  /// Creates the card's data.
  const ReviewGroup({
    required this.id,
    required this.authorName,
    required this.bookName,
    required this.day,
    required this.entries,
  });

  /// Stable id for the card and its stepper route.
  final String id;

  /// The member who entered them — shown, never inferred (13 §2.3).
  final String authorName;

  /// The book they landed in.
  final String bookName;

  /// The day they were entered.
  final LocalDate day;

  /// The flagged entries, oldest first.
  final List<ReviewEntry> entries;

  /// How many entries the card covers.
  int get count => entries.length;

  /// Sum of the magnitudes, in paise — the card's *"· ₹23,400"* (07 §9). A
  /// group mixes money in and money out, so the total carries no direction and
  /// is never coloured or signed (07 §1 rule 3).
  int get totalPaise =>
      entries.fold(0, (sum, e) => sum + (e.paise < 0 ? -e.paise : e.paise));
}

/// What S6 renders.
@immutable
final class InboxSnapshot {
  /// Creates the snapshot.
  const InboxSnapshot({this.reviews = const [], this.readOnly = false});

  /// Review cards, newest day first.
  final List<ReviewGroup> reviews;

  /// The reader is a viewer in every book in scope (13 §2.3.1: *Inbox ·
  /// Viewer → empty state*). The screen states the reason rather than
  /// silently showing an ordinary empty tray (13 §2.3 🔒).
  final bool readOnly;

  /// Whether anything at all is waiting.
  bool get isEmpty => reviews.isEmpty;

  /// A copy with [reviews] replaced.
  InboxSnapshot copyWith({List<ReviewGroup>? reviews, bool? readOnly}) =>
      InboxSnapshot(
        reviews: reviews ?? this.reviews,
        readOnly: readOnly ?? this.readOnly,
      );
}

/// Anything the queue could not do. Carries no plaintext financial data
/// (CLAUDE.md rule 4) — the screens show their own copy, never this.
final class ReviewQueueFailure implements Exception {
  /// Creates the failure.
  const ReviewQueueFailure([this.reason = 'review queue unavailable']);

  /// Developer-facing only.
  final String reason;

  @override
  String toString() => 'ReviewQueueFailure($reason)';
}

/// The seam S6 / S6.1 / S6.2 read and write through.
abstract interface class ReviewQueue {
  /// The last snapshot, or null before the first load (→ skeleton).
  InboxSnapshot? get current;

  /// Snapshots as they change.
  Stream<InboxSnapshot> watch();

  /// Reloads; throws [ReviewQueueFailure] on failure (→ error-with-retry).
  Future<void> refresh();

  /// *Approve all* (07 §9 🔒): clears every flag on the card in one tap. The
  /// entries were already posted and counted (02 §3), so this moves no money.
  Future<void> approveAll(String groupId);

  /// One decision on one entry (07 §9 stepper).
  ///
  /// [reason] is **required** for [ReviewDecision.reject] — the rejection
  /// envelope carries it and the auto-reversal records it (02 §3). Passing a
  /// blank one is a programming error, not a user-facing state.
  Future<void> decide({
    required String groupId,
    required String entryId,
    required ReviewDecision decision,
    String? reason,
  });

  /// The quiet *ask for a better photo* link (07 §9). Notifies the author;
  /// the flag stays exactly as it was.
  Future<void> askForPhoto({required String groupId, required String entryId});
}

/// In-memory fake for tests and the Phase A shell.
class FakeReviewQueue implements ReviewQueue {
  /// Starts holding [initial] (null = not loaded yet → skeleton).
  FakeReviewQueue({InboxSnapshot? initial}) : _current = initial;

  final _controller = StreamController<InboxSnapshot>.broadcast();
  InboxSnapshot? _current;

  /// Next call to any method throws this once, then clears.
  ReviewQueueFailure? failNext;

  /// What [refresh] loads when it runs (null keeps the current snapshot).
  InboxSnapshot? onRefresh;

  /// Every decision recorded, in order.
  final decisions =
      <
        ({
          String groupId,
          String entryId,
          ReviewDecision decision,
          String? reason,
        })
      >[];

  /// Group ids passed to [approveAll].
  final approvedGroups = <String>[];

  /// Entry ids a better photo was asked for.
  final photoAsks = <String>[];

  @override
  InboxSnapshot? get current => _current;

  /// Replaces the snapshot and notifies [watch].
  set current(InboxSnapshot? s) {
    _current = s;
    if (s != null) _controller.add(s);
  }

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Stream<InboxSnapshot> watch() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _controller.stream;
  }

  @override
  Future<void> refresh() async {
    _maybeFail();
    final next = onRefresh;
    if (next != null) current = next;
  }

  @override
  Future<void> approveAll(String groupId) async {
    _maybeFail();
    approvedGroups.add(groupId);
    _drop(groupId, (g) => const <ReviewEntry>[]);
  }

  @override
  Future<void> decide({
    required String groupId,
    required String entryId,
    required ReviewDecision decision,
    String? reason,
  }) async {
    if (decision == ReviewDecision.reject &&
        (reason == null || reason.trim().isEmpty)) {
      throw ArgumentError.value(reason, 'reason', 'a rejection needs a reason');
    }
    _maybeFail();
    decisions.add((
      groupId: groupId,
      entryId: entryId,
      decision: decision,
      reason: reason,
    ));
    _drop(groupId, (g) => g.entries.where((e) => e.id != entryId).toList());
  }

  @override
  Future<void> askForPhoto({
    required String groupId,
    required String entryId,
  }) async {
    _maybeFail();
    photoAsks.add(entryId);
  }

  void _drop(String groupId, List<ReviewEntry> Function(ReviewGroup) next) {
    final c = _current;
    if (c == null) return;
    final groups = <ReviewGroup>[];
    for (final g in c.reviews) {
      if (g.id != groupId) {
        groups.add(g);
        continue;
      }
      final rest = next(g);
      if (rest.isNotEmpty) {
        groups.add(
          ReviewGroup(
            id: g.id,
            authorName: g.authorName,
            bookName: g.bookName,
            day: g.day,
            entries: rest,
          ),
        );
      }
    }
    current = c.copyWith(reviews: groups);
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// Provides the queue to the Inbox screens. Integration wraps the app in one;
/// absent, the screens fall back to an empty [FakeReviewQueue] — an empty
/// tray, never a crash.
class ReviewQueueScope extends InheritedWidget {
  /// Creates the scope.
  const ReviewQueueScope({
    super.key,
    required this.queue,
    required super.child,
  });

  /// The queue below this point.
  final ReviewQueue queue;

  static final _fallback = FakeReviewQueue(initial: const InboxSnapshot());

  /// The nearest queue, or a shared empty fake.
  static ReviewQueue of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReviewQueueScope>()?.queue ??
      _fallback;

  @override
  bool updateShouldNotify(ReviewQueueScope old) => queue != old.queue;
}
