import 'dart:math';

import 'package:meta/meta.dart';

import 'scheduler.dart';

/// What the network decided for one message.
@immutable
class Delivery {
  /// Creates a delivery decision.
  const Delivery({
    required this.index,
    required this.from,
    required this.to,
    required this.label,
    required this.sentAt,
    required this.delayMs,
    required this.dropped,
  });

  /// Restores a decision written by [toJson].
  factory Delivery.fromJson(Map<String, Object?> j) => Delivery(
    index: j['i'] as int,
    from: j['from'] as String,
    to: j['to'] as String,
    label: j['label'] as String,
    sentAt: j['sentAt'] as int,
    delayMs: j['delayMs'] as int,
    dropped: j['dropped'] as bool,
  );

  /// Position in the log (0-based).
  final int index;

  /// Sending device id.
  final String from;

  /// Receiving device id (or `server`).
  final String to;

  /// Message label, for traces.
  final String label;

  /// Virtual send time.
  final int sentAt;

  /// Delivery delay decided by the model; meaningless when [dropped].
  final int delayMs;

  /// True when the message never arrives (the sender must retry, 05 §4).
  final bool dropped;

  /// Virtual arrival time, or null when dropped.
  int? get arrivesAt => dropped ? null : sentAt + delayMs;

  /// JSON for the replay log.
  Map<String, Object?> toJson() => {
    'i': index,
    'from': from,
    'to': to,
    'label': label,
    'sentAt': sentAt,
    'delayMs': delayMs,
    'dropped': dropped,
  };

  @override
  String toString() =>
      '#$index $from→$to $label @$sentAt ${dropped ? 'DROP' : '+${delayMs}ms'}';
}

/// A closed interval of virtual time during which a device has no connectivity.
@immutable
class OfflineWindow {
  /// Creates a window covering `[fromMs, toMs]`.
  const OfflineWindow(this.device, this.fromMs, this.toMs)
    : assert(fromMs <= toMs, 'window must not end before it starts');

  /// Device id.
  final String device;

  /// First offline ms (inclusive).
  final int fromMs;

  /// Last offline ms (inclusive).
  final int toMs;

  /// Whether [device] is offline at [t].
  bool covers(String d, int t) => d == device && t >= fromMs && t <= toMs;
}

/// What a scenario talks to: the seeded generator ([NetworkModel]) or its replay
/// ([ReplayNetwork]). Devices and the server (M4) depend on this interface only, so any
/// failing run can be re-driven from its log.
abstract interface class Network {
  /// Decides the fate of a message sent at [now].
  Delivery decide({
    required String from,
    required String to,
    required String label,
    required int now,
  });

  /// Decides, then schedules [onArrive] on [s] at the decided time unless dropped.
  Delivery send(
    Scheduler s, {
    required String from,
    required String to,
    required String label,
    required void Function(Scheduler s, Delivery d) onArrive,
  });
}

/// Decides delay, reordering and drops from **one seed**, and records every decision.
///
/// Reordering falls out of independent random delays: two messages sent in order may arrive
/// swapped whenever `delay(a) > delay(b) + gap`. Offline windows (09 §1 "scriptable
/// connectivity") hold a device's outbound and inbound messages until the window ends, so a
/// device that was offline across a month lock delivers late arrivals in one burst (02 §8).
class NetworkModel implements Network {
  /// Creates a model. Delays are uniform in `[minDelayMs, maxDelayMs]`; each message is
  /// dropped with probability [dropRate] (0 ⇒ lossless).
  NetworkModel({
    required this.seed,
    this.minDelayMs = 20,
    this.maxDelayMs = 2000,
    this.dropRate = 0.0,
    List<OfflineWindow> offline = const [],
  }) : _rng = Random(seed),
       _offline = List.unmodifiable(offline) {
    if (minDelayMs < 0 || maxDelayMs < minDelayMs) {
      throw ArgumentError('delay range must satisfy 0 ≤ min ≤ max');
    }
    if (dropRate < 0 || dropRate >= 1) {
      throw ArgumentError.value(dropRate, 'dropRate', 'must be in [0, 1)');
    }
  }

  /// The seed every decision derives from — print it in any failure message.
  final int seed;

  /// Minimum delivery delay.
  final int minDelayMs;

  /// Maximum delivery delay.
  final int maxDelayMs;

  /// Probability of a dropped message.
  final double dropRate;

  final Random _rng;
  final List<OfflineWindow> _offline;
  final List<Delivery> _log = [];

  /// Every decision so far, in send order.
  NetworkLog get log => NetworkLog(seed, List.unmodifiable(_log));

  /// Whether [device] is offline at virtual time [t].
  bool isOffline(String device, int t) =>
      _offline.any((w) => w.covers(device, t));

  /// Decides the fate of a message sent at [now] and returns it. Delivery is held until both
  /// ends are online: an offline sender queues it locally (its own outbox, 03 §3.1) and an
  /// offline receiver gets it when it reconnects — so the arrival is pushed past every window
  /// that covers the sender at send time or the receiver at the tentative arrival.
  @override
  Delivery decide({
    required String from,
    required String to,
    required String label,
    required int now,
  }) {
    var sentAt = now;
    for (final w in _offline) {
      if (w.covers(from, sentAt)) sentAt = w.toMs + 1;
    }
    final dropped = dropRate > 0 && _rng.nextDouble() < dropRate;
    var delay = minDelayMs + _rng.nextInt(maxDelayMs - minDelayMs + 1);
    var arrives = sentAt + delay;
    var moved = true;
    while (moved) {
      moved = false;
      for (final w in _offline) {
        if (w.covers(to, arrives)) {
          arrives = w.toMs + 1;
          moved = true;
        }
      }
    }
    delay = arrives - now;
    final d = Delivery(
      index: _log.length,
      from: from,
      to: to,
      label: label,
      sentAt: now,
      delayMs: delay,
      dropped: dropped,
    );
    _log.add(d);
    return d;
  }

  /// Sends through [s]: decides, then schedules [onArrive] at the decided time unless dropped.
  @override
  Delivery send(
    Scheduler s, {
    required String from,
    required String to,
    required String label,
    required void Function(Scheduler s, Delivery d) onArrive,
  }) {
    final d = decide(from: from, to: to, label: label, now: s.now);
    if (!d.dropped) {
      s.at(d.delayMs, 'deliver $from→$to $label', (s) => onArrive(s, d));
    }
    return d;
  }
}

/// The seeded record of a run's network decisions: what to attach to a failing test so the
/// same reorder replays without the generator (ADR 2026-09-05i §7 "seeded network-reorder log").
@immutable
class NetworkLog {
  /// Creates a log for [seed].
  const NetworkLog(this.seed, this.deliveries);

  /// Restores a log written by [toJson].
  factory NetworkLog.fromJson(Map<String, Object?> j) => NetworkLog(
    j['seed'] as int,
    List.unmodifiable(
      (j['deliveries'] as List<Object?>).map(
        (e) => Delivery.fromJson(e! as Map<String, Object?>),
      ),
    ),
  );

  /// The generating seed.
  final int seed;

  /// Decisions in send order.
  final List<Delivery> deliveries;

  /// Serialises the log.
  Map<String, Object?> toJson() => {
    'seed': seed,
    'deliveries': [for (final d in deliveries) d.toJson()],
  };

  /// A replaying network that hands back exactly these decisions, in order, and refuses to
  /// improvise: sending more messages than the log holds, or a message whose endpoints or
  /// label differ from the recorded one, is a test error — the scenario drifted from the log.
  ReplayNetwork replay() => ReplayNetwork(this);
}

/// Plays a [NetworkLog] back decision by decision. See [NetworkLog.replay].
class ReplayNetwork implements Network {
  /// Creates a replayer over [log].
  ReplayNetwork(this.log);

  /// The log being replayed.
  final NetworkLog log;
  int _cursor = 0;

  /// Decisions consumed so far.
  int get cursor => _cursor;

  /// Returns the next recorded decision after checking it matches the request.
  @override
  Delivery decide({
    required String from,
    required String to,
    required String label,
    required int now,
  }) {
    if (_cursor >= log.deliveries.length) {
      throw StateError(
        'replay exhausted after ${log.deliveries.length} messages; scenario sent $from→$to $label',
      );
    }
    final d = log.deliveries[_cursor++];
    if (d.from != from || d.to != to || d.label != label || d.sentAt != now) {
      throw StateError(
        'replay drift at #${d.index}: log has $d, scenario sent $from→$to $label @$now',
      );
    }
    return d;
  }

  /// Sends through [s] using the recorded decision.
  @override
  Delivery send(
    Scheduler s, {
    required String from,
    required String to,
    required String label,
    required void Function(Scheduler s, Delivery d) onArrive,
  }) {
    final d = decide(from: from, to: to, label: label, now: s.now);
    if (!d.dropped) {
      s.at(d.delayMs, 'deliver $from→$to $label', (s) => onArrive(s, d));
    }
    return d;
  }
}
