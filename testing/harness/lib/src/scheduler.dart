import 'dart:collection';

import 'package:meta/meta.dart';

/// A unit of work due at a virtual instant.
typedef Action = void Function(Scheduler s);

/// One scheduled event. Ordered by `(at, seq)` so equal instants run in insertion order —
/// the tie-break that keeps a run reproducible.
@immutable
class ScheduledEvent implements Comparable<ScheduledEvent> {
  /// Creates an event due at [at] with insertion sequence [seq].
  const ScheduledEvent(this.at, this.seq, this.label, this.action);

  /// Virtual time (milliseconds since the run began).
  final int at;

  /// Insertion order, the deterministic tie-break.
  final int seq;

  /// Human label, shown in traces.
  final String label;

  /// What runs.
  final Action action;

  @override
  int compareTo(ScheduledEvent other) =>
      at != other.at ? at.compareTo(other.at) : seq.compareTo(other.seq);
}

/// Discrete-event scheduler with a **virtual clock**.
///
/// Nothing here reads `DateTime.now()`: time advances only when [run] pops the next event.
/// Two runs with the same seed and the same actions produce the same [trace], so any
/// two-client failure is replayable (09 §1).
class Scheduler {
  /// Creates an empty scheduler at virtual time zero.
  Scheduler();

  final SplayTreeSet<ScheduledEvent> _queue = SplayTreeSet<ScheduledEvent>();
  final List<String> _trace = [];
  int _seq = 0;
  int _now = 0;
  int _executed = 0;

  /// Current virtual time in ms.
  int get now => _now;

  /// Events executed so far.
  int get executed => _executed;

  /// Events still queued.
  int get pending => _queue.length;

  /// `"$at $label"` per executed event, in execution order.
  List<String> get trace => List.unmodifiable(_trace);

  /// Schedules [action] to run [delayMs] after [now]. Returns the event.
  ScheduledEvent at(int delayMs, String label, Action action) {
    if (delayMs < 0) {
      throw ArgumentError.value(delayMs, 'delayMs', 'must be ≥ 0');
    }
    final e = ScheduledEvent(_now + delayMs, _seq++, label, action);
    _queue.add(e);
    return e;
  }

  /// Removes a queued event. Returns false when it already ran or was cancelled.
  bool cancel(ScheduledEvent e) => _queue.remove(e);

  /// Runs events in `(at, seq)` order until the queue is empty or [untilMs] is reached
  /// (events due after [untilMs] stay queued; [now] becomes [untilMs]). Returns the
  /// number of events executed.
  int run({int? untilMs, int maxEvents = 1 << 20}) {
    var n = 0;
    while (_queue.isNotEmpty && n < maxEvents) {
      final e = _queue.first;
      if (untilMs != null && e.at > untilMs) break;
      _queue.remove(e);
      _now = e.at;
      _trace.add('${e.at} ${e.label}');
      _executed++;
      n++;
      e.action(this);
    }
    // Time advances to [untilMs] even when later events remain queued — every
    // one of them is due after it, so a caller may author "now" at that instant.
    if (untilMs != null && _now < untilMs) _now = untilMs;
    if (n >= maxEvents) {
      throw StateError('scheduler exceeded $maxEvents events — runaway loop?');
    }
    return n;
  }
}
