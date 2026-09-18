// The Inbox feature's seam to the **Late Arrivals tray** — S10.3 (13 §3.2, its
// parent is S6), 02 §8 🔒, 07 §13 🔒, ADR 2026-09-05e §3 and §10.
//
// ⚠️ WIRE — three rules the implementation must keep, because the screens
// above assume them and cannot check them:
//
//  1. **Everything here is already in the book.** 02 §3 🔒 and 02 §8 🔒: a
//     late arrival counts in every live balance the moment it lands. Only the
//     *certified* month figures leave it out. Nothing on S10.3 may draw the
//     money as pending, held or waiting — that state does not exist.
//  2. **Re-dating is an amend, not a re-post** (02 §5, 02 §8 "default, one
//     tap"): identical lines, only the accounting date moves, into the open
//     period. An implementation that reverses and re-posts would show the
//     family two movements of money where one happened.
//  3. **A re-open is one signed envelope and the log itself** (02 §7.2 item 3,
//     02 §8). It never re-closes the month, and it is refused outright when
//     the month sits inside a **closed** financial year — that re-open voids
//     the certificate and every later one, and is the structural act of
//     02 §7.2.1 🔒, not this routine one.
//
// Money is signed integer paise throughout (CLAUDE.md rule 1).
import 'dart:async';

import 'package:core_ledger/core_ledger.dart' show LocalDate, YearMonth;
import 'package:flutter/widgets.dart';

/// One entry in the tray, as the closer sees it (07 §13 🔒: *entry + why it is
/// here*).
@immutable
final class LateArrivalItem {
  /// Creates the card's data.
  const LateArrivalItem({
    required this.entryId,
    required this.bookId,
    required this.bookName,
    required this.lockedPeriod,
    required this.date,
    required this.paise,
    required this.fromLabel,
    required this.toLabel,
    this.note,
    this.lockedOn,
    this.closedYear,
  });

  /// The entry — the head of its amend chain.
  final String entryId;

  /// The book it landed in.
  final String bookId;

  /// The book's name, as the user wrote it.
  final String bookName;

  /// The **locked** month it is dated into. The *Re-open* action names it.
  final YearMonth lockedPeriod;

  /// Its accounting date (03 §1: a calendar day, not an instant).
  final LocalDate date;

  /// Signed integer paise from the money A/C's own side: positive is money
  /// in, negative is money out (02 §10 🔒 — a consumer surface, so the words
  /// beside it are *Money in / Money out*, never Dr/Cr).
  final int paise;

  /// Where the money came from, in the user's words.
  final String fromLabel;

  /// Where it went, in the user's words.
  final String toLabel;

  /// The author's own narration, when they wrote one.
  final String? note;

  /// The day the month locked — the second half of *why it is here*. Null
  /// when this phone has no lock row for the month.
  final LocalDate? lockedOn;

  /// The label of the **closed** financial year this month sits inside, when
  /// it does (02 §8.1 🔒). Non-null disables *Re-open* and puts the plain
  /// sentence about the year-close ceremony in its place — the card never
  /// offers a tap that can only be refused (07 §1 rule 6).
  final String? closedYear;

  /// True when only the one-tap default is available.
  bool get reopenBlocked => closedYear != null;

  /// The magnitude, for the amount line. Direction is carried by [paise]'s
  /// sign and said in words beside it — colour is never alone (07 §1 rule 3).
  int get magnitudePaise => paise < 0 ? -paise : paise;
}

/// What S10.3 renders.
@immutable
final class LateArrivalsTray {
  /// Creates the snapshot.
  const LateArrivalsTray({this.items = const [], this.readOnly = false});

  /// The tray, oldest entry first.
  final List<LateArrivalItem> items;

  /// The reader may view the book but not close it (13 §2.3.1). The screen
  /// states the capability instead of showing a bare empty tray (13 §2.3 🔒).
  final bool readOnly;

  /// Whether anything is waiting.
  bool get isEmpty => items.isEmpty;
}

/// Anything the tray could not do. Carries no plaintext financial data
/// (CLAUDE.md rule 4) — the screens show their own copy, never this.
final class LateArrivalsFailure implements Exception {
  /// Creates the failure.
  const LateArrivalsFailure([this.reason = 'late arrivals unavailable']);

  /// Developer-facing only.
  final String reason;

  @override
  String toString() => 'LateArrivalsFailure($reason)';
}

/// The refusal a re-open can come back with — a *state of the book*, not an
/// error. The screen turns each into one plain sentence (07 §1 rule 6).
enum ReopenRefusal {
  /// The month sits inside a closed FY: the re-open voids that certificate
  /// and every later one, so it belongs to the year-close ceremony
  /// (02 §8.1 🔒, 02 §7.2.1 🔒).
  closedYear,

  /// The month is not locked any more — somebody else re-opened it first.
  notLocked,
}

/// A re-open the ledger refused, thrown instead of authoring anything.
final class ReopenRefused implements Exception {
  /// Creates the refusal.
  const ReopenRefused(this.reason, {this.closedYearLabel});

  /// Why.
  final ReopenRefusal reason;

  /// The FY's label, when [reason] is [ReopenRefusal.closedYear].
  final String? closedYearLabel;

  @override
  String toString() => 'ReopenRefused(${reason.name})';
}

/// The seam S6's late-arrivals section and S10.3 read and write through.
abstract interface class LateArrivals {
  /// The last tray, or null before the first load (→ skeleton).
  LateArrivalsTray? get current;

  /// Trays as they change.
  Stream<LateArrivalsTray> watch();

  /// Reloads; throws [LateArrivalsFailure] on failure (→ error-with-retry).
  Future<void> refresh();

  /// *Re-date to today* — the one-tap default (02 §8 🔒). An amend: the lines
  /// are untouched and the entry moves into the open period.
  Future<void> redateToToday(String entryId);

  /// *Re-open {month}* — admin, logged (02 §8 🔒). Authors one signed
  /// `period_unlock` envelope carrying [reason]; the month then needs closing
  /// again. Throws [ReopenRefused] when the book refuses it, and
  /// [LateArrivalsFailure] when it could not be attempted.
  ///
  /// A blank [reason] is a programming error, not a user state: the sheet
  /// above this call cannot be confirmed without one.
  Future<void> reopenMonth({
    required String bookId,
    required YearMonth period,
    required String reason,
  });
}

/// In-memory fake for tests and the Phase A shell.
class FakeLateArrivals implements LateArrivals {
  /// Starts holding [initial] (null = not loaded yet → skeleton).
  FakeLateArrivals({LateArrivalsTray? initial}) : _current = initial;

  final _controller = StreamController<LateArrivalsTray>.broadcast();
  LateArrivalsTray? _current;

  /// Next call to any method throws this once, then clears.
  LateArrivalsFailure? failNext;

  /// Next [reopenMonth] throws this once, then clears.
  ReopenRefused? refuseNextReopen;

  /// What [refresh] loads when it runs (null keeps the current tray).
  LateArrivalsTray? onRefresh;

  /// Entry ids re-dated, in order.
  final redated = <String>[];

  /// Every re-open attempted, in order.
  final reopened = <({String bookId, YearMonth period, String reason})>[];

  @override
  LateArrivalsTray? get current => _current;

  /// Replaces the tray and notifies [watch].
  set current(LateArrivalsTray? t) {
    _current = t;
    if (t != null) _controller.add(t);
  }

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Stream<LateArrivalsTray> watch() async* {
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
  Future<void> redateToToday(String entryId) async {
    _maybeFail();
    redated.add(entryId);
    final c = _current;
    if (c == null) return;
    current = LateArrivalsTray(
      items: [
        for (final i in c.items)
          if (i.entryId != entryId) i,
      ],
      readOnly: c.readOnly,
    );
  }

  @override
  Future<void> reopenMonth({
    required String bookId,
    required YearMonth period,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'a re-open records why');
    }
    final refusal = refuseNextReopen;
    if (refusal != null) {
      refuseNextReopen = null;
      throw refusal;
    }
    _maybeFail();
    reopened.add((bookId: bookId, period: period, reason: reason.trim()));
    final c = _current;
    if (c == null) return;
    current = LateArrivalsTray(
      items: [
        for (final i in c.items)
          if (!(i.bookId == bookId && i.lockedPeriod == period)) i,
      ],
      readOnly: c.readOnly,
    );
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// Provides the tray to the Inbox screens. Integration wraps the app in one;
/// absent, the screens fall back to a shared empty fake — an empty tray, never
/// a crash.
class LateArrivalsScope extends InheritedWidget {
  /// Creates the scope.
  const LateArrivalsScope({
    super.key,
    required this.tray,
    required super.child,
  });

  /// The tray below this point.
  final LateArrivals tray;

  static final _fallback = FakeLateArrivals(initial: const LateArrivalsTray());

  /// The nearest tray, or a shared empty fake.
  static LateArrivals of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LateArrivalsScope>()?.tray ??
      _fallback;

  @override
  bool updateShouldNotify(LateArrivalsScope old) => tray != old.tray;
}
