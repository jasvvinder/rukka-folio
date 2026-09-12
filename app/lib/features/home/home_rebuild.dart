// S1.4 *Book incomplete — rebuilding* — the progress seam (07 §28 🔒, ADR
// 2026-09-05f §B, ADR 2026-09-05c §3/§6).
//
// A book's projections are dropped and recomputed on local corruption, on
// Recompute-on-upgrade and on a `store_epoch` re-pull. While that runs the
// Home card is replaced by the determinate loader rule with a **count**
// (11 §4.5 🔒: never a spinner, counts and never percentages), and the book
// is never shown as whole meanwhile.
//
// The producer is `Recompute.watchProgress` (packages/data, E-03-29): a live
// per-book reading of (done, total) entry envelopes read back, `null` when the
// book is not rebuilding, with the reading in hand replayed to every new
// listener so a Home that mounts mid-rebuild renders S1.4 at once. The shell
// adapts it with [recomputeRebuildProgress]; tests still pass a fake stream.
import 'package:data/data.dart';
import 'package:flutter/widgets.dart';

import '../../shared/ledger/ledger_scope.dart';

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

/// The real S1.4 producer: `Recompute`'s per-book readings as [RebuildProgress].
///
/// A straight `map` — no `await` anywhere in the chain, so cancelling the
/// subscription stays synchronous inside `flutter_test`'s fake-async zone
/// (an awaited cancel deadlocks widget teardown for the whole timeout).
RebuildProgressSource recomputeRebuildProgress(Recompute recompute) =>
    (bookId) => recompute
        .watchProgress(bookId)
        .map(
          (p) =>
              p == null ? null : RebuildProgress(done: p.done, total: p.total),
        );

/// The S1.4 producer for the tree below [context], or null when no ledger is
/// in scope (a screen pumped without data has no rebuild to report).
RebuildProgressSource? rebuildProgressOf(BuildContext context) {
  final ledger = LedgerScope.maybeOf(context);
  return ledger == null ? null : recomputeRebuildProgress(ledger.recompute);
}
