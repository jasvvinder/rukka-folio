// S12.5 at the entry Save path — the two signals that may stop a posting
// before it reaches the ledger (13 §3.2 row S12.5; 07 §5 *Book full*; 07 §20
// 🔒; ADR 2026-09-05f §B row *Book full*; ADR 2026-09-05g §4, §5; ADR
// 2026-09-05b §7).
//
//   1. **Read-only** — tenant-wide, server-declared (`grace_kind = lapsed` on
//      a *fresh* token). Lapse blocks new entry only (13 §6).
//   2. **Book full** — per book, the server answered `rejected:quota`. Book
//      full blocks posting only; drafts are kept (13 §6, ADR 2026-09-05g §3).
//
// Read-only is asked first: it is the wider fact, and its sheet says so.
//
// What never blocks here, by rule:
//   * **Offline grace** — `Entitlement.state` turns every *stale* reading into
//     `offlineGrace`, whose `blocksEntry` is false (ADR 2026-09-05g §4 🔒:
//     read-only engages only after the device has reached the server **and
//     been told lapsed**). Dunning grace is *the grace*: entry keeps working.
//   * **No token** — Free, never locked (ADR 2026-09-05g §1 🔒). Production
//     mounts no `EntitlementScope` yet, so the untokened source is the honest
//     default, not a stand-in.
//   * **Export** — never blocked by either signal (ADR 2026-09-05g §3, §5).
//
// Nothing here reads a clock, a network or a setting: both sources are the
// seams above the screen.
//
// **Scope — every write that creates an envelope (ADR 2026-09-24b §13,
// desk 30).** Read-only (lapsed, S12.5) blocks post, amend, reverse, opening
// balances (S3.1 and onboarding), cash count, advances and partner entries;
// each path raises the same S12.5 sheet, drafts are kept, export always
// works. Each path calls [entryRestrictionSourcesOf] before its first await
// and [refuseIfEntryRestricted] (or [entryRestrictionFor] + the sheet) with
// every book it appends to:
//   * S2 Save — `screens/s2_add_entry_screen.dart` (F1-07-491…496)
//   * S2.1 inline new A/C — `screens/s2_add_entry_screen.dart` `_create`
//     (the same `addAccount` write S3.1 gates)
//   * S2.x advances spend / return — `advances/widgets/advance_entry_sheet.dart`
//   * S14.2 pay-out / partner-to-partner — `partners/widgets/settlement_sheet.dart`
//   * S14.1 distribute — `partners/screens/s14_1_distribute_screen.dart`
//   * S5.5 cash count — `cash_count/screens/s5_5_cash_count_screen.dart`
//   * S4.1 amend and reverse — `ledger/screens/s4_1_entry_detail_screen.dart`
//   * S3.1 quick add (account + opening balance) — `ledger/screens/s3_1_quick_add_sheet.dart`
//   * S0.6b / S0.6f / S0.6i opening balances — `onboarding/widgets/*_opening_host.dart`
//   * the same hosts' book creation (`createBook`, also S9.5 *Add a
//     business*) — no book id passed: a book not yet made has no quota
// (F1-24b-7).
//
// **One exception:** the 10-second Undo of an entry this phone just saved
// (S2's snackbar). Blocking it would trap a mistake the person made seconds
// ago (07 §1 rule 2) — so S2's `_undo` / `_undoPair` never call this gate.
// **Book full** keeps its narrower scope: it blocks posting to that book only
// (ADR 2026-09-05b §7), which is why every caller passes the books it appends
// to rather than asking a tenant-wide question.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:go_router/go_router.dart';

import '../../shared/seams/sync_client.dart';
import '../../shared/widgets/rk_restriction.dart';
import '../../shared/widgets/rk_restriction_copy.dart';
import '../subscription/entitlement_source.dart';
import '../subscription/subscription_paths.dart';
import 'entry_sync.dart';

/// The two seams the Save path consults, captured from [context] **before**
/// the first await (a Save handler must not reach into its context after one).
typedef EntryRestrictionSources = ({
  EntitlementSource entitlement,
  SyncClient? sync,
});

/// Reads both seams from [context] without registering a dependency — this is
/// an event-handler lookup, exactly like [syncClientOf]: the entry screen must
/// never rebuild because an entitlement or a quota changed.
///
/// No [EntitlementScope] above → [UntokenedEntitlementSource]: Free, live,
/// nothing blocked (ADR 2026-09-05g §1 🔒).
EntryRestrictionSources entryRestrictionSourcesOf(BuildContext context) => (
  entitlement:
      context.getInheritedWidgetOfExactType<EntitlementScope>()?.source ??
      const UntokenedEntitlementSource(),
  sync: syncClientOf(context),
);

/// Which S12.5 kind, if any, blocks posting into [bookIds] — every book the
/// posting would append to (both halves of an inter-book movement, 02 §6:
/// either book full blocks the pair, because one half without the other is
/// the non-zero pair 02 §6 🔒 exists to catch).
///
/// Returns null when the posting may go ahead. Never returns
/// [RkRestrictionKind.offlineGrace] or [RkRestrictionKind.suspended]: the
/// first blocks nothing, the second is the devices surface's (07 §15).
Future<RkRestrictionKind?> entryRestrictionFor(
  EntryRestrictionSources sources,
  Iterable<String> bookIds,
) async {
  Entitlement reading;
  try {
    reading = await sources.entitlement.read();
  } on Object {
    // Ruled (ADR 2026-09-24b §14, desk 31): a failed `read()` reads as
    // untokened — Free, never locked (ADR 2026-09-05g §1 🔒) — so a read
    // error never blocks a save (07 §1 rule 6: no dead ends). The server
    // stays the hard cap (ADR 2026-09-05g §2): a lapsed tenant's push is
    // refused there whatever this phone concluded.
    reading = Entitlement.untokened();
  }
  if (reading.state.blocksEntry) return RkRestrictionKind.readOnly;
  final sync = sources.sync;
  if (sync != null && bookIds.any(sync.isBookFull)) {
    return RkRestrictionKind.bookFull;
  }
  return null;
}

/// The whole S12.5 gate for a write path that is not S2 (ADR 2026-09-24b §13):
/// asks [entryRestrictionFor] for [bookIds] and, when blocked, raises the
/// S12.5 sheet over [context].
///
/// Resolves **true when the write must not go ahead** — the caller returns
/// before touching the ledger and leaves its draft exactly as it is (the
/// sheet returns an outcome, never a command to clear anything). The sheet's
/// way forward opens S12.1 Plans: [onPlans] when given, otherwise
/// [SubscriptionPaths.plans] on the ambient router, and nothing at all
/// without one rather than a thrown red screen.
///
/// [onBlocked] runs just before the sheet rises (and only while [context] is
/// still mounted) — where a caller drops its busy flag, so the draft under the
/// sheet is editable again the moment it is dismissed.
///
/// [sources] must have been read with [entryRestrictionSourcesOf] before the
/// caller's first await.
Future<bool> refuseIfEntryRestricted(
  BuildContext context,
  EntryRestrictionSources sources,
  Iterable<String> bookIds, {
  VoidCallback? onBlocked,
  VoidCallback? onPlans,
}) async {
  final kind = await entryRestrictionFor(sources, bookIds);
  if (kind == null) return false;
  if (!context.mounted) return true;
  onBlocked?.call();
  final outcome = await showRkBlockedEntrySheet(
    context,
    kind: kind,
    copy: kind.copy(context),
  );
  if (outcome != RkBlockedEntryOutcome.action || !context.mounted) return true;
  if (onPlans != null) {
    onPlans();
  } else {
    final router = GoRouter.maybeOf(context);
    if (router != null) unawaited(router.push<void>(SubscriptionPaths.plans));
  }
  return true;
}
