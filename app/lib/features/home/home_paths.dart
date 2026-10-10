// Paths owned by the Home feature. `RkPaths.home` is the tab root (S1, shared
// router); the S1.1 drill-down is pushed on the *root* navigator so it covers
// the tab bar, exactly as S4 does (13 §3.2 depth rule: S1.1 is one level below
// the S1 root).
import '../../shared/router.dart';

/// Which position line a drill-down is behind (07 §4: "every line drills into
/// its list"; 13 §3.2 row S1.1). The wire name is the path segment.
enum PositionLine {
  /// Cash in hand — the `money` accounts of subtype `cash` (02 §9).
  cash('cash'),

  /// One bank, card, wallet or loan account from the hero breakdown.
  bank('bank'),

  /// You will get — parties with a debit balance (02 §9, 07 §7).
  youWillGet('you-will-get'),

  /// You will give — parties with a credit balance (02 §9, 07 §7).
  youWillGive('you-will-give'),

  /// Advances out — open advances given (02 §7, §9).
  advancesOut('advances-out'),

  /// In transit — money between your own books (02 §6, §9).
  inTransit('in-transit');

  const PositionLine(this.wire);

  /// Path segment / wire name.
  final String wire;

  /// Parses a path segment; null when it names no line.
  static PositionLine? parse(String wire) {
    for (final l in values) {
      if (l.wire == wire) return l;
    }
    return null;
  }
}

/// Paths under the Home tab (S1 root).
abstract final class HomePaths {
  /// S1 Home / Position — the tab root.
  static const home = RkPaths.home;

  /// S1.1 Position line drill-down; `:line` is a [PositionLine] wire name.
  static const position = '${RkPaths.home}/position/:line';

  /// The S1.1 path for [line] over the book Home has in scope ([bookId]),
  /// so the drill-down totals the same rows as the position row it came from
  /// (02 §9 "per selected scope"; 13 §2.2). The book rides as `?book=`.
  static String positionOf(PositionLine line, {String? bookId}) {
    final path = '${RkPaths.home}/position/${line.wire}';
    return bookId == null
        ? path
        : '$path?$bookQuery=${Uri.encodeQueryComponent(bookId)}';
  }

  /// The query parameter naming S1.1's book.
  static const bookQuery = 'book';
}
