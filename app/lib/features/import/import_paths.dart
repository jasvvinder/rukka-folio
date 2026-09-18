// Where statement import lives (07 §11 🔒, 13 §3.2 rows S7 · S7.1).
//
// **Entry point 🔒 (ADR 2026-09-03):** the Import action is on the **entry
// screen (S2) header, top right** — importing is a way of entering many lines
// at once — and is *not* a Menu row. That header is `features/entry`'s file,
// so this lane publishes the destination and the constant to push, and the
// entry lane links to it.
//
// ⚠️ SPEC: `shared/router.dart`'s `RkPaths` has no `/import` constant, and it
// is another lane's file this round, so the literals live here — the same
// arrangement `AdvancesPaths` and `CashCountPaths` made. When the shell adopts
// the route, move these strings to `RkPaths.import` and point these at them.
abstract final class ImportPaths {
  /// S7 — pick the bank A/C, then the file. A **root-navigator** destination:
  /// it is opened from the S2 header and covers the tab bar until the import
  /// is abandoned or the lines reach the inbox.
  static const root = '/import';

  /// S7.1 — the import inbox, where parsed lines wait for their one question
  /// (02 §10 🔒).
  ///
  /// **Pushed, never routed.** S7.1 carries the parsed statement in memory,
  /// and a path cannot: nothing is written to disk to make a URL possible
  /// (07 §11 item 1 🔒, 04) — the same reason S7.0b is pushed. The constant
  /// stays because 13 §3.4 lists *import lines waiting* as an Inbox
  /// destination, and that deep link needs a name to point at once the lines
  /// outlive one import session.
  static const inbox = '/import/inbox';
}
