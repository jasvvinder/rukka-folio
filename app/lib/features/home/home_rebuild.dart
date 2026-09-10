// S1.4 *Book incomplete — rebuilding* — the progress seam (07 §28 🔒, ADR
// 2026-09-05f §B, ADR 2026-09-05c §3/§6).
//
// A book's projections are dropped and recomputed on local corruption, on
// Recompute-on-upgrade and on a `store_epoch` re-pull. While that runs the
// Home card is replaced by the determinate loader rule with a **count**
// (11 §4.5 🔒: never a spinner, counts and never percentages), and the book
// is never shown as whole meanwhile.
//
// ⚠️ SPEC / seam: `Recompute.run` (packages/data, recompute.dart:112) exposes
// no progress today — it returns when it is done. This typedef is the shape
// S1 consumes; the missing `Stream<RebuildProgress>` on `packages/data` is
// recorded as an open item rather than invented here (that package is another
// lane's). Until it exists, a caller supplies the stream (the app's shell
// while a rebuild runs; a fake in tests) and Home renders whatever it emits.
import 'package:flutter/foundation.dart';

/// How far a rebuild has got: [done] of [total] entries restored (07 §28).
@immutable
final class RebuildProgress {
  /// Creates the reading.
  const RebuildProgress({required this.done, required this.total});

  /// Entries restored so far.
  final int done;

  /// Entries the rebuild has to restore in all.
  final int total;

  /// 0..1 for the determinate loader; 0 while [total] is not known yet, so
  /// the rule never renders as an indeterminate sweep by accident.
  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  @override
  bool operator ==(Object other) =>
      other is RebuildProgress && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(done, total);
}

/// The seam S1 consumes: a live rebuild reading for a book, or `null` when
/// that book is not rebuilding.
typedef RebuildProgressSource = Stream<RebuildProgress?> Function(
  String bookId,
);
