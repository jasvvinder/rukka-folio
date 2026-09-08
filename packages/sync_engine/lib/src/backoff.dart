// Retry backoff (05 §3): exponential with jitter, 1 s → 2 → 4 → … cap 10 min,
// reset on connectivity change. Jitter is injected (no `Random()` here).
import 'package:meta/meta.dart';

/// Jitter source: returns a value in `[0, maxMs]`. Injected; `null` = none.
typedef Jitter = int Function(int maxMs);

/// Backoff schedule state.
@immutable
final class Backoff {
  /// Creates a schedule.
  const Backoff({
    this.attempt = 0,
    this.baseMs = 1000,
    this.capMs = 10 * 60 * 1000,
  });

  /// Failures so far.
  final int attempt;

  /// First delay.
  final int baseMs;

  /// Maximum delay.
  final int capMs;

  /// Delay before the next try, without jitter.
  int get delayMs {
    if (attempt == 0) return 0;
    var d = baseMs;
    for (var i = 1; i < attempt && d < capMs; i++) {
      d *= 2;
    }
    return d > capMs ? capMs : d;
  }

  /// Delay with [jitter] added (bounded by the cap).
  int delayWith(Jitter? jitter) {
    final d = delayMs;
    if (jitter == null || d == 0) return d;
    final j = jitter(d ~/ 2);
    return d + j > capMs ? capMs : d + j;
  }

  /// After a failure.
  Backoff next() => Backoff(attempt: attempt + 1, baseMs: baseMs, capMs: capMs);

  /// After success or a connectivity change.
  Backoff reset() => Backoff(baseMs: baseMs, capMs: capMs);
}
