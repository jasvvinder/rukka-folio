// Entry feature route (features/README "Routes", 13 §3.1/§3.2). S2 is not a
// tab: the centre ( + ) and Home's verb buttons push `/entry` over the shell
// on the *root* navigator, so it covers the tab bar. `buildRouter` owns the
// path ([RkPaths.entry]) and takes this builder as its `entry:` argument —
// main.dart wires it, exactly as it wires `homeRoot` and `ledgerRoot`.
//
// Home pushes `/entry?verb=<EntryKind.wire>` (07 §4). The verb only chooses
// the pill's opening position; every position is one swipe away either way
// (07 §5, ADR 2026-09-03b), so an absent or unreadable `verb` opens on
// *Money in* rather than failing — a bad deep link is never a dead end
// (07 §1 rule 6).
//
// The book comes from the same seam Home uses: [AddEntryScreen] resolves the
// solo book through `LedgerScope` when no `bookId` is passed. When the scope
// switcher owns a persisted scope, the caller passes `bookId` instead.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'screens/s2_add_entry_screen.dart';

export 'screens/s2_add_entry_screen.dart' show AddEntryKeys, AddEntryScreen;

/// The pill position a `verb` query parameter asks for, or *Money in*.
EntryKind entryVerbOf(String? wire) {
  if (wire == null) return EntryKind.moneyIn;
  try {
    final kind = EntryKind.parse(wire);
    // `adjustment` is guided-only (02 §2 verb 6): its wizards live behind
    // S2.4's own doors and are never a position on this screen.
    return kind == EntryKind.adjustment ? EntryKind.moneyIn : kind;
  } on FormatException {
    return EntryKind.moneyIn;
  }
}

/// S2 Add entry — the builder `buildRouter(entry: entryScreen)` mounts.
Widget entryScreen(BuildContext context) => AddEntryScreen(
  kind: entryVerbOf(GoRouterState.of(context).uri.queryParameters['verb']),
);
