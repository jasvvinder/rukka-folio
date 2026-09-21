// The 15-day cooling period of 06 §9.3 🔒, and the support-initiated request
// of ADR 2026-09-05h §2. Pure with respect to time: every query takes `now`
// from the injected clock (CLAUDE.md rule 3), so a clock jump is a question
// this model answers rather than a state it drifts into.
//
// The two types are deliberately separate. A **request** is not a clock:
// support may ask, and only the user's own certified device may start the
// countdown (06 §8, ADR 2026-09-05h §2). Folding them into one object with a
// nullable `startedAt` is exactly the mistake that ADR forbids, so the type
// system holds them apart.
import 'package:flutter/foundation.dart';

/// Who asked for the deletion. Both run the same 15 days once started; they
/// differ only in how the countdown began.
enum DeletionOrigin {
  /// Started in-app by the account holder (06 §9.3).
  user,

  /// Started by the account holder *accepting* a support request
  /// (ADR 2026-09-05h §2) — never by support itself.
  support,
}

/// A support request sitting on the user's devices. Nothing is running: it
/// lands as a card to accept, never as a started clock
/// (07 §21 🔒, ADR 2026-09-05h §2).
@immutable
final class DeletionRequest {
  /// Creates the request.
  const DeletionRequest({required this.id, required this.requestedAt});

  /// Server id of the request.
  final String id;

  /// When support raised it — shown so the user can place the phone call
  /// they remember having.
  final DateTime requestedAt;
}

/// A running cooling period. Cancel-anytime until it completes (06 §9.3 🔒).
@immutable
final class DeletionWindow {
  /// Creates the window.
  const DeletionWindow({
    required this.id,
    required this.origin,
    required this.startedAt,
    this.cancelled = false,
  });

  /// The cooling period — 15 days (06 §9.3 🔒).
  static const cooling = Duration(days: 15);

  /// Server id of the deletion.
  final String id;

  /// How the countdown began.
  final DeletionOrigin origin;

  /// Instant the user's own device started it.
  final DateTime startedAt;

  /// True once any device on the account cancelled it.
  final bool cancelled;

  /// The instant erasure runs.
  DateTime get completesAt => startedAt.add(cooling);

  /// Time left; zero once complete.
  Duration remaining(DateTime now) {
    final d = completesAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// Whole days still to run, rounded **up** — a window with 4 h left reads
  /// "1 day left", never "0 days left" over a screen that still offers
  /// Cancel.
  int daysLeft(DateTime now) {
    final r = remaining(now);
    if (r == Duration.zero) return 0;
    final whole = r.inDays;
    return r > Duration(days: whole) ? whole + 1 : whole;
  }

  /// Exactly at 15 days the window is complete.
  bool isComplete(DateTime now) => !now.isBefore(completesAt);

  /// Cancel-anytime (06 §9.3 🔒) — up to the last second.
  bool canCancel(DateTime now) => !cancelled && !isComplete(now);

  /// Copy with [cancelled] flipped.
  DeletionWindow copyWith({bool? cancelled}) => DeletionWindow(
    id: id,
    origin: origin,
    startedAt: startedAt,
    cancelled: cancelled ?? this.cancelled,
  );
}
