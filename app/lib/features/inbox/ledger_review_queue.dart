// [ReviewQueue] over the real ledger — what S6, S6.1 and S6.2 read and write
// through in the shipped app (02 §3 🔒 post-then-review, 03 §3.3 rule 5 🔒,
// 07 §9 🔒, 13 §3.2 rows S6/S6.1/S6.2).
//
// **The Inbox is one surface** (07 §9 🔒), so this queue is device-wide: it
// watches every book `LocalLedger.watchBooks()` reports and merges their open
// flags, each card carrying its own book's name — the same reading
// `LedgerLateArrivals` settled, and deliberately not coupled to Home's
// selected book.
//
// It is a **composer**, not a decider. Every judgement is the ledger's:
//
//   * what is flagged — `watchOpenReviews`, which reads the projector's own
//     `entries_p.review_state = 'open'`. Nothing here classifies, and nothing
//     here may be drawn as money that has not moved: a flagged entry posted
//     and counted the moment it was saved (02 §3 🔒);
//   * *Approve all* and *Approve* — `approveEntry`, one signed
//     `approval_decision` per entry that clears the flag and moves nothing;
//   * *Reject* — `rejectEntry`, the signed decision plus the auto-posted
//     mirror reversal of 02 §5, with the reason on both.
//
// The seam's two rules (`review_queue.dart`) are kept here:
//
//  1. entries in the queue are already in the book — nothing below is drawn as
//     pending or held;
//  2. **nobody clears their own flag** (02 §7.2 item 1 🔒). Groups authored by
//     the reading member are filtered out here, and `LocalLedger` refuses a
//     self-decision again underneath. A book with one member therefore raises
//     nothing, whatever its flags say.
//
// Money is signed integer paise (CLAUDE.md rule 1).
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BooksPData;

import '../../shared/ledger/local_ledger.dart';
import 'review_queue.dart';

/// [ReviewQueue] backed by [LocalLedger], across every book on this device.
final class LedgerReviewQueue implements ReviewQueue {
  /// Creates the queue over [ledger] and starts watching.
  ///
  /// [authorNameOf] resolves a `user_id` to the display name 07 §9's card
  /// shows. The ledger holds no contact book — `Member.displayName` is the
  /// members repository's, and it is null where this device does not hold the
  /// contact (ADR 2026-09-05c §4) — so the name arrives as an injected lookup
  /// rather than this file reaching across to `features/members`. Unresolved
  /// is the empty string, never a raw user id: an id on a card would be worse
  /// than no name.
  LedgerReviewQueue(this.ledger, {String Function(String userId)? authorNameOf})
    : _authorNameOf = authorNameOf ?? _noName {
    _books = ledger.watchBooks().listen(_onBooks, onError: _onError);
  }

  /// The ledger facade. One instance per app, installed by the shell.
  final LocalLedger ledger;

  final String Function(String userId) _authorNameOf;

  static String _noName(String _) => '';

  final _controller = StreamController<InboxSnapshot>.broadcast();
  final _flags = <String, List<FlaggedEntry>>{};
  final _subs = <String, StreamSubscription<List<FlaggedEntry>>>{};
  final _names = <String, String>{};
  final _groups = <String, ReviewGroup>{};

  /// Entry ids a better photo has been asked for **on this device, this run**.
  ///
  /// ⚠️ SPEC: 07 §9 🔒 gives the stepper a quiet *ask for a better photo* link
  /// and stops there. No object type in 03 §3 carries such a request, 02 §3's
  /// lifecycle has only approve and reject, and 07 §17 / 13 §3.4's
  /// notification catalogue has no *photo requested* push. The conservative
  /// reading is therefore that it is **not** a ledger act: inventing an object
  /// type would put an envelope every other reader would have to guess at into
  /// an append-only book. So it authors nothing and reaches no one — it only
  /// keeps the stepper's own *asked* state honest within the session. Closing
  /// it needs either a notification type (07 §17) or an object type (03 §3);
  /// reported to the owner rather than invented here.
  final askedForPhoto = <String>{};

  StreamSubscription<List<BooksPData>>? _books;
  InboxSnapshot? _current;
  Object? _lastError;
  int _emitSeq = 0;

  @override
  InboxSnapshot? get current => _current;

  /// The snapshot as it changes, starting with the one standing now.
  ///
  /// It subscribes to the broadcast stream **before** replaying [current],
  /// because the obvious `async*` shape (`yield current; yield* stream`) drops
  /// any snapshot produced between the two — a rebuild that lands in that gap
  /// would leave the Inbox showing a card the ledger has already cleared.
  @override
  Stream<InboxSnapshot> watch() {
    late final StreamController<InboxSnapshot> out;
    StreamSubscription<InboxSnapshot>? sub;
    out = StreamController<InboxSnapshot>(
      onListen: () {
        final standing = _current;
        sub = _controller.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        if (standing != null) out.add(standing);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// A fresh read of every book's open flags.
  ///
  /// The streams are live, so this is a re-read rather than the only load —
  /// what the error state's *Try again* needs (13 §4.3). It rethrows as
  /// [ReviewQueueFailure] so nothing below the seam ever carries plaintext
  /// financial data into an error (CLAUDE.md rule 4).
  @override
  Future<void> refresh() async {
    try {
      final books = await ledger.watchBooks().first;
      _names
        ..clear()
        ..addEntries([for (final b in books) MapEntry(b.id, b.name)]);
      _flags.removeWhere((id, _) => !_names.containsKey(id));
      for (final b in books) {
        _flags[b.id] = await ledger.watchOpenReviews(b.id).first;
      }
      _lastError = null;
      await _emit();
    } on Object catch (e) {
      throw ReviewQueueFailure('review queue unavailable: ${e.runtimeType}');
    }
  }

  /// *Approve all* (07 §9 🔒) — N signed decisions, one per entry, in the
  /// card's own order.
  ///
  /// **Partial failure, stated exactly.** The ledger is append-only, so a
  /// decision already authored can never be taken back: every member the run
  /// clears stays cleared. A member the ledger refuses because it is no longer
  /// open for decision — decided by another device between the read and the
  /// tap, no longer flagged, no longer the head, no longer here — is **skipped
  /// silently**, because the outcome the tap asked for (no open flag on that
  /// entry) already holds, and the stream re-emits what is genuinely left.
  /// Any other refusal — a self-decision or an advance request, both of which
  /// mean this queue yielded something it never should have — is applied to
  /// nobody's detriment but **does** surface as a [ReviewQueueFailure], after
  /// the rest of the card has been approved. Rejecting one never blocks the
  /// rest, and neither does refusing one (07 §9 🔒).
  @override
  Future<void> approveAll(String groupId) async {
    final group = _groups[groupId];
    if (group == null) {
      throw const ReviewQueueFailure('no such group');
    }
    final unexpected = <ReviewRefusal>[];
    for (final e in group.entries) {
      try {
        await ledger.approveEntry(e.id);
      } on ReviewRefused catch (r) {
        if (!settledAlready(r.refusal)) unexpected.add(r.refusal);
      } on Object catch (e) {
        throw ReviewQueueFailure('approve all failed: ${e.runtimeType}');
      }
    }
    if (unexpected.isNotEmpty) {
      throw ReviewQueueFailure(
        'approve all refused: ${unexpected.map((r) => r.name).join(',')}',
      );
    }
  }

  /// True when the refusal means *this entry is no longer open for a
  /// decision* — the flag is already gone or the entry is no longer the one a
  /// reviewer should be deciding on. Re-trying would change nothing.
  static bool settledAlready(ReviewRefusal r) => switch (r) {
    ReviewRefusal.unknownEntry ||
    ReviewRefusal.notFlagged ||
    ReviewRefusal.alreadyDecided ||
    ReviewRefusal.notHead => true,
    ReviewRefusal.pendingAdvance ||
    ReviewRefusal.selfApproval ||
    ReviewRefusal.alreadyReversed ||
    ReviewRefusal.reversalRefused => false,
  };

  @override
  Future<void> decide({
    required String groupId,
    required String entryId,
    required ReviewDecision decision,
    String? reason,
  }) async {
    if (decision == ReviewDecision.reject &&
        (reason == null || reason.trim().isEmpty)) {
      // A programming error, not a user-facing state: the reject sheet
      // collects the reason before this is reached (07 §9 🔒).
      throw ArgumentError.value(reason, 'reason', 'a rejection needs a reason');
    }
    try {
      switch (decision) {
        case ReviewDecision.approve:
          await ledger.approveEntry(entryId);
        case ReviewDecision.reject:
          await ledger.rejectEntry(entryId, reason: reason!);
      }
    } on ReviewRefused catch (r) {
      // A state of the book, carried across as the seam's own failure so the
      // screen says one plain sentence and offers its retry (07 §1 rule 6).
      throw ReviewQueueFailure('decision refused: ${r.refusal.name}');
    } on Object catch (e) {
      throw ReviewQueueFailure('decision failed: ${e.runtimeType}');
    }
  }

  /// The quiet *ask for a better photo* link (07 §9). Device-local and
  /// session-local — see [askedForPhoto] for why it authors nothing.
  @override
  Future<void> askForPhoto({
    required String groupId,
    required String entryId,
  }) async {
    askedForPhoto.add(entryId);
  }

  /// Stops watching every book.
  Future<void> dispose() async {
    await _books?.cancel();
    for (final s in _subs.values) {
      await s.cancel();
    }
    _subs.clear();
    await _controller.close();
  }

  /// What the last stream event failed with, for a caller that wants to know
  /// whether the standing snapshot is stale. Developer-facing only.
  Object? get lastError => _lastError;

  // ── the merge ─────────────────────────────────────────────────────────────

  void _onBooks(List<BooksPData> rows) {
    final books = {for (final b in rows) b.id: b.name};
    _names
      ..clear()
      ..addAll(books);
    for (final id in _subs.keys.toList()) {
      if (books.containsKey(id)) continue;
      _subs.remove(id)?.cancel();
      _flags.remove(id);
    }
    for (final id in books.keys) {
      if (_subs.containsKey(id)) continue;
      _subs[id] = ledger
          .watchOpenReviews(id)
          .listen((flags) => unawaited(_onFlags(id, flags)), onError: _onError);
    }
    unawaited(_emit());
  }

  Future<void> _onFlags(String bookId, List<FlaggedEntry> flags) async {
    if (!_names.containsKey(bookId)) return;
    _flags[bookId] = flags;
    _lastError = null;
    await _emit();
  }

  void _onError(Object error) {
    _lastError = error;
    // An error is never a silently empty queue: the last good snapshot stands
    // and `refresh()` is what the screen's *Try again* calls.
  }

  // ── flags → one card per author + book + day (07 §9 🔒) ───────────────────

  /// Composes and publishes the next snapshot.
  ///
  /// Composition is asynchronous (it reads each book's chart), so two
  /// projections landing close together can compose concurrently and finish
  /// out of order. Publishing is therefore token-guarded: a composition that
  /// a newer one overtook is dropped rather than written over the newer
  /// answer. Without this the Inbox keeps a card the ledger has cleared —
  /// a card offering a decision that can now only be refused (07 §1 rule 6).
  Future<void> _emit() async {
    if (_controller.isClosed) return;
    final token = ++_emitSeq;
    try {
      final groups = await _compose();
      if (token != _emitSeq || _controller.isClosed) return;
      _groups
        ..clear()
        ..addEntries([for (final g in groups) MapEntry(g.id, g)]);
      // ⚠️ SPEC: 13 §2.3.1's read-only member is a *role* and this app has no
      // book-role source yet — the same gap `LedgerLateArrivals` and
      // `LedgerCloseSource` record. The conservative reading that keeps 07 §1
      // rule 6 is to leave the gate to the ledger: the card opens, and the
      // decision is the thing that can refuse.
      _current = InboxSnapshot(reviews: List.unmodifiable(groups));
      _controller.add(_current!);
    } on Object catch (e) {
      // A closed ledger (app lock, sign-out) or a failed read is never a
      // silently empty queue: the last good snapshot stands and `refresh()`
      // is what the screen's *Try again* calls.
      _lastError = e;
    }
  }

  Future<List<ReviewGroup>> _compose() async {
    final mine = ledger.identity.userId;
    final byGroup = <String, List<FlaggedEntry>>{};
    final chartOf = <String, Chart>{};
    for (final MapEntry(key: bookId, value: flags) in _flags.entries) {
      for (final f in flags) {
        final author = f.createdByUser;
        // Rule 2: nobody clears their own flag, so the reader never sees a
        // card of their own — nor one whose author cannot be named at all,
        // which would be a card no one may decide on.
        if (author == null || author == mine) continue;
        byGroup.putIfAbsent(_groupId(bookId, author, f), () => []).add(f);
      }
      if (flags.isNotEmpty && !chartOf.containsKey(bookId)) {
        chartOf[bookId] = await ledger.chartOf(bookId);
      }
    }

    final groups = <ReviewGroup>[];
    for (final MapEntry(key: id, value: flags) in byGroup.entries) {
      final bookId = flags.first.bookId;
      final money = {
        for (final a in chartOf[bookId]?.accounts ?? const <Account>[])
          if (a.isMoney) a.id,
      };
      final entries = [...flags]
        ..sort((a, b) {
          final byHlc = a.hlc.compareTo(b.hlc);
          return byHlc != 0 ? byHlc : a.entryId.compareTo(b.entryId);
        });
      groups.add(
        ReviewGroup(
          id: id,
          authorName: _authorNameOf(flags.first.createdByUser!),
          bookName: _names[bookId] ?? '',
          day: _dayOfHlc(entries.first.hlc),
          entries: [
            for (final f in entries)
              ReviewEntry(
                id: f.entryId,
                paise: _signedPaise(f, money),
                fromLabel: f.from.map((l) => l.accountName).join(', '),
                toLabel: f.to.map((l) => l.accountName).join(', '),
                date: f.accountingDate,
                postedAt: _instantOfHlc(f.hlc),
                note: f.note,
              ),
          ],
        ),
      );
    }
    // Newest day first (07 §9's card order), then book, then author, so two
    // cards of the same day never swap places between rebuilds.
    groups.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      if (byDay != 0) return byDay;
      final byBook = a.bookName.compareTo(b.bookName);
      return byBook != 0 ? byBook : a.id.compareTo(b.id);
    });

    return groups;
  }

  /// One card per **author + book + day** (07 §9 🔒). Stable across rebuilds,
  /// so S6.1's route survives a re-projection.
  static String _groupId(String bookId, String author, FlaggedEntry f) =>
      '$bookId|$author|${_dayOfHlc(f.hlc).toIso()}';

  /// The movement **from the money A/C's own side**: + is money in, − is money
  /// out (02 §10 🔒 — the words beside it on S6.1 are *Money in / Money out*,
  /// never Dr/Cr).
  ///
  /// An entry with no money line — a credit sale, say — has no money side to
  /// read, so its magnitude is stated without a direction rather than a
  /// direction being invented.
  static int _signedPaise(FlaggedEntry f, Set<String> money) {
    for (final l in f.lines) {
      if (money.contains(l.accountId)) return l.amount.raw;
    }
    return f.amountPaise;
  }

  /// The instant the author saved it, from the HLC the entry carries (03 §1:
  /// 48 bits of physical milliseconds + a 16-bit counter).
  ///
  /// ⚠️ SPEC: the physical half is the **author's** wall clock, read back here
  /// in this phone's own zone, so the *day* a card groups by is *the day this
  /// device says they entered it* rather than a certified one — an entry
  /// carries an `accounting_date`, which is a different question and is shown
  /// on every row. It is the honest answer to 07 §9 🔒's *one card per author +
  /// book + day*, which is about when they were entered.
  static DateTime _instantOfHlc(int raw) =>
      DateTime.fromMillisecondsSinceEpoch(Hlc(raw).physicalMs);

  static LocalDate _dayOfHlc(int raw) {
    final at = _instantOfHlc(raw);
    return LocalDate(at.year, at.month, at.day);
  }
}
