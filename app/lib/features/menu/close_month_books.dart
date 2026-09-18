// What the S8 *Close the month* row shows — ADR 2026-09-03 ruling 1 🔒: a Menu
// row in *The books* group directly after Reports, with a **live subtitle**
// (*August open · 3 items waiting*), opening the month-close wizard (S10).
//
// Two reads, both through [CloseSource] and neither re-deciding anything:
//
//   * `closeStatuses(upTo)` says, per book, **which month closes next** — not
//     necessarily the month asked for, because months lock in order (02 §8.1 🔒)
//     and a book with July still open offers July. The row therefore never
//     opens a wizard the engine would refuse (07 §1 rule 6).
//   * `loadClose(bookId, period)` gives that month's tray, and the subtitle's
//     count is `blocks.length + warns.length` — *items waiting*. The Menu says
//     **how many**; the tray step itself is what states which of them block and
//     which only warn (07 §13 🔒), so nothing is flattened where it matters.
//
// A book already locked through the month contributes no row and is never
// loaded. With no row left the Menu still draws the row, disabled, saying which
// case it is in ([MenuCloseMonthState]) — a door that quietly disappears is the
// dead end 07 §1 rule 6 forbids, and so is a built screen sitting behind a *not
// built yet* sentence.
import 'package:core_ledger/core_ledger.dart';

import '../close/close_source.dart';

/// One *Close the month* row on S8: a book, the month it closes next, and how
/// much is waiting on that month.
final class MenuCloseMonthBook {
  /// Creates the row's data.
  const MenuCloseMonthBook({
    required this.bookId,
    required this.bookName,
    required this.period,
    required this.waiting,
    this.resumable = false,
  });

  /// The book whose month would be closed.
  final String bookId;

  /// Its name, as the user wrote it.
  final String bookName;

  /// The month the wizard opens at — this book's **first open** one.
  final YearMonth period;

  /// Everything on that month's tray, blocks and warns alike.
  final int waiting;

  /// True when progress is saved and the wizard resumes (07 §13 *Resumable* 🔒).
  final bool resumable;
}

/// Which of the row's five states the Menu is in (13 §4.3).
enum MenuCloseMonthState {
  /// The close is still being read — the row says so and cannot be entered.
  loading,

  /// At least one book has a month to close; [MenuCloseMonthLoad.books] is it.
  ready,

  /// Every book this device holds is already locked through the month asked
  /// for. The row states that and disables.
  closed,

  /// This device holds no book with a month to close at all.
  nothing,

  /// The close could not be read. The row stays tappable and the tap retries.
  failed,
}

/// The whole of what S8's *Close the month* row draws, in one value.
final class MenuCloseMonthLoad {
  /// Creates the load.
  const MenuCloseMonthLoad(this.state, {this.books = const [], this.upTo});

  /// Which state the row is in.
  final MenuCloseMonthState state;

  /// One entry per book with a month to close, in `closeStatuses` order.
  /// Non-empty exactly when [state] is [MenuCloseMonthState.ready].
  final List<MenuCloseMonthBook> books;

  /// The month that was asked for — the [MenuCloseMonthState.closed] sentence
  /// names it, so the row says *what* is closed rather than only that it is.
  final YearMonth? upTo;
}

/// The month the Menu offers to close, from the device's clock: the one that
/// has just **ended**, never the month in progress.
///
/// 07 §13 🔒 puts the close card on Home *from the 1st*, for the month before
/// today's, and the Menu row is the same door — offering September on 10
/// September would be offering a month with nothing to close. January reaches
/// back to December of the year before.
YearMonth endedMonthAt(DateTime now) => now.month == 1
    ? YearMonth(now.year - 1, 12)
    : YearMonth(now.year, now.month - 1);

/// Reads the *Close the month* row's state from [source], for the month at
/// [upTo] (the device's current month).
///
/// Never throws: a read that failed is [MenuCloseMonthState.failed], which the
/// row shows with a retry. The Menu is not a screen that may go red.
Future<MenuCloseMonthLoad> menuCloseMonthLoad(
  CloseSource source,
  YearMonth upTo,
) async {
  try {
    final statuses = await source.closeStatuses(upTo);
    if (statuses.isEmpty) {
      return const MenuCloseMonthLoad(MenuCloseMonthState.nothing);
    }
    final books = <MenuCloseMonthBook>[];
    for (final status in statuses) {
      if (status.state == BookCloseState.closed) continue;
      final view = await source.loadClose(status.bookId, status.period);
      books.add(
        MenuCloseMonthBook(
          bookId: status.bookId,
          bookName: status.bookName,
          period: status.period,
          waiting: view.tray.blocks.length + view.tray.warns.length,
          resumable: status.resumable,
        ),
      );
    }
    if (books.isEmpty) {
      return MenuCloseMonthLoad(MenuCloseMonthState.closed, upTo: upTo);
    }
    return MenuCloseMonthLoad(
      MenuCloseMonthState.ready,
      books: List.unmodifiable(books),
      upTo: upTo,
    );
  } on Object {
    // A door that could not be worked out is a door that says so and offers
    // another try — never a red Menu (07 §1 rule 6).
    return const MenuCloseMonthLoad(MenuCloseMonthState.failed);
  }
}
