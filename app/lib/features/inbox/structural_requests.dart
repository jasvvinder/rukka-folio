// The Inbox feature's seam to pending **structural** requests — S6.3, the
// typed attention card of ADR 2026-09-05f §D, against the quorum rule of
// 02 §7.2.1 🔒.
//
// The counting is **not** here and must never be. `core_ledger`'s
// `evaluateStructural` (A-02-94, A-02-95) walks the signed records in
// `(hlc, id)` order, counts one approval per author against the owner-set
// version each record names, honours a veto, and lapses the request 14 days
// after its initiation — on an injected clock, so every device agrees. This
// seam carries that engine's own [StructuralOutcome] to the screen, and the
// screen **displays** its numbers:
//
//   quorum progress = outcome.approvedBy.length of outcome.threshold
//
// Never `owners.length`, never a local `~/ 2 + 1`. The two differ the moment
// the book's quorum is *majority* (⌊n/2⌋ + 1 — ADR 2026-09-14 ruling 1 🔒) or
// the owner set has been re-versioned since the request was authored, and a
// screen that recomputed would tell one owner a different story from the next.
//
// ⚠️ WIRE — rules the real implementation must keep, because the screens
// above assume them and cannot check them:
//
//  1. **Nothing is applied early** (02 §7.2.1 🔒). A pending request changes no
//     balance and no permission. [approve] and [veto] author one signed
//     envelope each and nothing else; applying an approved request is
//     `applyStructural`'s job, downstream of this seam.
//  2. **An initiation is not an approval.** The engine is explicit: the
//     initiator authors an approval envelope like every other owner. The one
//     exception is the single-owner book, where the initiation *is* the
//     quorum of one — and there the concept is invisible, so such a request
//     never reaches this seam (see [StructuralItem.isVisible]).
//  3. **Only an owner's own device may sign.** [approve] and [veto] are
//     offered only where [StructuralItem.viewerIsOwner]; the server cannot
//     manufacture either (02 §7.2.1).
//  4. Every initiation, approval, veto and lapse joins the member-visible
//     admin-actions feed permanently (02 §7.2 item 3) — the veto sheet says
//     so before it confirms.
//
// ⚠️ SPEC (ADR 2026-09-14 ruling 2, **unresolved**): 02 §7.1 line 229 says the
// ownership ratio is "fixed at creation … not allowed to change", while
// 02 §7.2.1's 🔒 table lists "change the ownership ratio" as a structural
// action requiring quorum. Both are 🔒 lines in 02 and neither outranks the
// other, so no lane may pick one. This screen therefore *renders* a
// [StructuralAction.ownershipRatio] request — it is 07 §26's own worked
// example — and **applies nothing**: whether such a request may be raised at
// all is [checkStructuralRequest]'s question, in the engine, where the ruling
// will land. Nothing here depends on where the ratio is stored.
//
// Money is integer paise throughout (CLAUDE.md rule 1).
import 'dart:async';

import 'package:core_ledger/core_ledger.dart'
    show
        LocalDate,
        StructuralAction,
        StructuralOutcome,
        StructuralRequest,
        StructuralStatus;
import 'package:flutter/widgets.dart';

// The engine's own vocabulary is the feature's vocabulary: the card and the
// review surface switch on these, and re-exporting keeps a second, drifting
// copy from ever being defined here (02 §7.2.1's action set is 🔒).
export 'package:core_ledger/core_ledger.dart'
    show
        StructuralAction,
        StructuralOutcome,
        StructuralRequest,
        StructuralStatus;

/// One value on a *what will change* line — a term in force, or the term
/// proposed beside it.
///
/// Money keeps its own case so it can never be handed about as text: an
/// amount is integer paise until the widget formats it (CLAUDE.md rule 1).
sealed class StructuralValue {
  const StructuralValue();
}

/// A value that is already in the user's own words — a partner's weight, a
/// financial-year start, a member's name. Never a UI string: UI strings come
/// from ARB, this is data.
@immutable
final class StructuralText extends StructuralValue {
  /// Creates the value.
  const StructuralText(this.text);

  /// The value as the book records it.
  final String text;
}

/// An amount, in integer paise (CLAUDE.md rule 1).
@immutable
final class StructuralMoney extends StructuralValue {
  /// Creates the value.
  const StructuralMoney(this.paise);

  /// Signed integer paise.
  final int paise;
}

/// A calendar day — a financial-year start, the year being re-opened. The
/// widget formats it (07 §1 rule 5: full month names in ਪੰਜਾਬੀ and हिन्दी),
/// so no date ever reaches the screen pre-rendered in one language.
@immutable
final class StructuralDay extends StructuralValue {
  /// Creates the value.
  const StructuralDay(this.day);

  /// The day, as the ledger holds it (03 §1: a calendar day, not an instant).
  final LocalDate day;
}

/// One line of *exactly what will change* (07 §26 🔒): a subject, the term in
/// force, and the term proposed.
///
/// A null [current] means **the book has no value recorded for this subject**
/// — which is never the same as a default. 02 §7.1 🔒 is explicit for the
/// ownership ratio: *"An absent or empty map means the ratio was never
/// recorded — never that the shares are equal"*. The card says *not recorded*
/// and, for a ratio, says why; it never divides anything evenly.
///
/// A null [proposed] means the subject goes away — an owner or member removed.
@immutable
final class StructuralTerm {
  /// Creates the line.
  const StructuralTerm({required this.subject, this.current, this.proposed});

  /// Whose or what term this is, in the user's words (a partner's name, the
  /// member being removed, *Financial year starts*).
  final String subject;

  /// The term in force, or null when nothing is recorded.
  final StructuralValue? current;

  /// The term proposed, or null when the subject is being removed.
  final StructuralValue? proposed;
}

/// One pending — or lately decided — structural request, as S6.3 draws it.
///
/// Everything about *the count* is read off [outcome]; nothing on this class
/// recomputes it.
@immutable
final class StructuralItem {
  /// Creates the item.
  const StructuralItem({
    required this.request,
    required this.outcome,
    required this.bookName,
    required this.initiatorName,
    required this.ownerNames,
    required this.viewerId,
    required this.viewerIsOwner,
    this.terms = const [],
    this.subject,
    this.viewerCanInitiate = false,
  });

  /// The signed request (02 §7.2.1). Its `action` is the 🔒 kind and its
  /// `hlc` dates the 14-day window.
  final StructuralRequest request;

  /// The engine's verdict — the sole source of the count, the threshold, the
  /// veto and the deadline.
  final StructuralOutcome outcome;

  /// The book the request is about.
  final String bookName;

  /// Who raised it, in the user's words.
  final String initiatorName;

  /// Owner id → display name, for *who has approved* (13 §2.3: the actor is
  /// shown, never inferred).
  final Map<String, String> ownerNames;

  /// The reading member's own id, so the screen can tell *you* from *them*.
  final String viewerId;

  /// Whether the reader is one of the owners who may sign. A member who is
  /// not an owner sees the request — it is in the member-visible admin
  /// feed — and is told plainly who decides (13 §2.3.1 role variant).
  final bool viewerIsOwner;

  /// The *what will change* lines, terms in force beside the proposed ones.
  final List<StructuralTerm> terms;

  /// The one thing being acted on, where the action names one: the member to
  /// remove, the book to archive, the year to re-open.
  final String? subject;

  /// Whether the reader may raise a fresh request — an admin (02 §7.2.1:
  /// *an admin initiates*). Drives the lapsed card's one next action.
  final bool viewerCanInitiate;

  /// What kind of structural change (02 §7.2.1's 🔒 table).
  StructuralAction get action => request.action;

  /// Where it stands, per the engine.
  StructuralStatus get status => outcome.status;

  /// Approvals counted so far — the *2* of *2 of 3*.
  int get approvals => outcome.approvedBy.length;

  /// Approvals required — the *3*. Null when the request names an owner-set
  /// version this phone does not know, in which case it can never reach
  /// quorum here and the card says so rather than showing a fake total.
  int? get required => outcome.threshold;

  /// Owners whose approval counted, named where a name is known.
  List<String> get approverNames => [
    for (final id in outcome.approvedBy) ownerNames[id] ?? id,
  ];

  /// True once the reading owner's own approval is among them.
  bool get viewerHasApproved => outcome.approvedBy.contains(viewerId);

  /// True when the reader raised this request. It is **not** an approval
  /// (02 §7.2.1, and the engine asserts it): the initiator signs one like
  /// everybody else, and the card says so.
  bool get viewerIsInitiator => request.byUser == viewerId;

  /// True while the reading owner may still sign either way.
  bool get viewerMayDecide =>
      viewerIsOwner &&
      status == StructuralStatus.pending &&
      !viewerHasApproved &&
      required != null;

  /// Why the two buttons are absent, when they are (13 §4.3
  /// *disabled-with-reason* — never a silently missing control).
  StructuralBlock? get block {
    if (status != StructuralStatus.pending) return null;
    if (!viewerIsOwner) return StructuralBlock.notAnOwner;
    if (viewerHasApproved) return StructuralBlock.alreadyApproved;
    if (required == null) return StructuralBlock.unknownOwnerSet;
    return null;
  }

  /// The last moment an approval still counts, from the engine's own
  /// deadline (02 §7.2.1: 14 days from initiation).
  DateTime get deadline =>
      DateTime.fromMillisecondsSinceEpoch(outcome.deadlineMs);

  /// The reason recorded with the veto that closed it, if any.
  String? get vetoReason => outcome.veto?.reason;

  /// Who vetoed, named.
  String? get vetoBy {
    final v = outcome.veto;
    if (v == null) return null;
    return ownerNames[v.byUser] ?? v.byUser;
  }

  /// Whether S6.3 draws this request at all.
  ///
  /// A single-owner book has a quorum of one and *"the concept is invisible
  /// there"* (02 §7.2.1 🔒): the owner's own initiation is already the
  /// approval, so there is nothing for an Inbox card to ask. The engine
  /// reports exactly that shape — approved at the request's own order point,
  /// with no approval records counted — and the screen stays quiet.
  bool get isVisible =>
      ownerNames.length > 1 &&
      !(status == StructuralStatus.approved && outcome.approvedBy.isEmpty);
}

/// Why the Approve / Veto pair is not offered (13 §4.3: every disabled
/// control states its reason).
enum StructuralBlock {
  /// The reader is a member of the book but not one of its owners.
  notAnOwner,

  /// The reader's approval is already counted.
  alreadyApproved,

  /// The request names an owner-set version this phone has not seen, so no
  /// reader here can say who the owners are (the engine counts nothing).
  unknownOwnerSet,
}

/// What S6's structural section renders.
@immutable
final class StructuralInbox {
  /// Creates the snapshot.
  const StructuralInbox({this.items = const []});

  /// Requests, newest first. Ones [StructuralItem.isVisible] rejects are
  /// dropped by the screen, not by the seam.
  final List<StructuralItem> items;

  /// The cards actually drawn.
  List<StructuralItem> get visible =>
      items.where((i) => i.isVisible).toList(growable: false);

  /// Whether anything is drawn at all.
  bool get isEmpty => visible.isEmpty;
}

/// Anything the seam could not do. Carries no plaintext financial data
/// (CLAUDE.md rule 4) — the screens show their own copy, never this.
final class StructuralRequestFailure implements Exception {
  /// Creates the failure.
  const StructuralRequestFailure([this.reason = 'structural seam unavailable']);

  /// Developer-facing only.
  final String reason;

  @override
  String toString() => 'StructuralRequestFailure($reason)';
}

/// The seam S6.3 reads and writes through.
abstract interface class StructuralRequests {
  /// The last snapshot, or null before the first load (→ skeleton).
  StructuralInbox? get current;

  /// Snapshots as they change.
  Stream<StructuralInbox> watch();

  /// Reloads; throws [StructuralRequestFailure] on failure.
  Future<void> refresh();

  /// Signs one approval envelope on this owner's own device (02 §7.2.1).
  /// It applies nothing by itself; quorum is the engine's to declare.
  Future<void> approve(String requestId);

  /// Signs a veto, which closes the request immediately with [reason]
  /// recorded (02 §7.2.1 🔒). A blank reason is a programming error, not a
  /// user-facing state — the sheet above can never produce one.
  Future<void> veto({required String requestId, required String reason});

  /// Raises a fresh request with the same terms after a lapse (02 §7.2.1:
  /// *lapsed, logged, re-initiable*). A new request, never a revival.
  Future<void> reinitiate(String requestId);
}

/// In-memory fake for tests and the Phase A shell.
class FakeStructuralRequests implements StructuralRequests {
  /// Starts holding [initial] (null = not loaded yet → skeleton).
  FakeStructuralRequests({StructuralInbox? initial}) : _current = initial;

  final _controller = StreamController<StructuralInbox>.broadcast();
  StructuralInbox? _current;

  /// Next call to any method throws this once, then clears.
  StructuralRequestFailure? failNext;

  /// What [refresh] loads when it runs (null keeps the current snapshot).
  StructuralInbox? onRefresh;

  /// Request ids approved, in order.
  final approved = <String>[];

  /// Vetoes recorded, in order.
  final vetoes = <({String requestId, String reason})>[];

  /// Request ids re-initiated.
  final reinitiated = <String>[];

  @override
  StructuralInbox? get current => _current;

  /// Replaces the snapshot and notifies [watch].
  set current(StructuralInbox? s) {
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
  Stream<StructuralInbox> watch() async* {
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
  Future<void> approve(String requestId) async {
    _maybeFail();
    approved.add(requestId);
  }

  @override
  Future<void> veto({required String requestId, required String reason}) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'a veto records its reason');
    }
    _maybeFail();
    vetoes.add((requestId: requestId, reason: reason));
  }

  @override
  Future<void> reinitiate(String requestId) async {
    _maybeFail();
    reinitiated.add(requestId);
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// Provides the seam to the Inbox screens. Integration wraps the app in one;
/// absent, the screens fall back to an empty fake — no cards, never a crash.
class StructuralRequestsScope extends InheritedWidget {
  /// Creates the scope.
  const StructuralRequestsScope({
    super.key,
    required this.requests,
    required super.child,
  });

  /// The seam below this point.
  final StructuralRequests requests;

  static final _fallback = FakeStructuralRequests(
    initial: const StructuralInbox(),
  );

  /// The nearest seam, or a shared empty fake.
  static StructuralRequests of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<StructuralRequestsScope>()
          ?.requests ??
      _fallback;

  @override
  bool updateShouldNotify(StructuralRequestsScope old) =>
      requests != old.requests;
}
