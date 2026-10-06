// Whether S0.6's *Finish* has been pressed (desk 172, owner-ruled 6 Oct:
// *Finish* ticks the S0.7 checklist's *Opening balances* row, *Skip for now*
// leaves it open as the way back).
//
// Why a record and not only the ledger: Home already ticks the row when the
// personal book's `Opening Balance / Capital A/c` carries a figure
// (`HomeSnapshot.openingBalancesDone`), but a person who has nothing yet and
// presses *Finish* with every row at ₹0 posts nothing (02 §4: zero balances
// post nothing) — and the ruling still ticks the row. So the press itself is
// kept: one bit about this install, beside `onboarded`, in the same protected
// device store ([RkPrefs]). Not financial data — no figure, no name.
//
// ⚠️ SPEC / open (P1A): `shared/prefs.dart` says `RkPrefKeys` is "the only
// place these strings live"; that file is not this lane's, so the key lives
// here until its owner moves it there.
import 'package:flutter/foundation.dart';

import '../../shared/prefs.dart';

/// The S0.6 *Finish* record.
abstract final class OpeningSetupRecord {
  /// The store key prefix; [keyFor] appends the book id.
  static const key = 'setup.openingBalances';

  /// The store key for [bookId]: `1` once S0.6's *Finish* was pressed over
  /// that book; absent before.
  static String keyFor(String bookId) => '$key.$bookId';

  /// Bumped whenever [markFinished] records — Home listens, so a row ticked by
  /// S0.6 is ticked on the Home it returns to without a restart.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// True once *Finish* was pressed over [bookId].
  static Future<bool> isFinished(RkPrefs? prefs, String bookId) async {
    if (prefs == null) return false;
    try {
      return await prefs.read(keyFor(bookId)) == '1';
    } on Object {
      // An unreadable store reads as "not yet" — the row stays open, which is
      // the way back, never a dead end (07 §1 rule 6).
      return false;
    }
  }

  /// Records the press over [bookId]. Never cleared.
  static Future<void> markFinished(RkPrefs? prefs, String bookId) async {
    if (prefs != null) {
      try {
        await prefs.write(keyFor(bookId), '1');
      } on Object {
        // Nothing to report: the row simply stays open.
      }
    }
    changes.value++;
  }
}
