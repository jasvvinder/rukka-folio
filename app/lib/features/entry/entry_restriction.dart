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
// ⚠️ SPEC: scope — this gate stands in front of **S2's Save only**. 13 §6
// blocks *posting* and *new entry* wherever they happen (ADR 2026-09-05f §B
// row *Book full*: "posting blocked with the S12.5 sheet pattern"), and other
// posting paths outside `features/entry` do not call it yet: S2.x advances
// (spend / return), partners (pay-out / settle), S16 cash count (the
// adjustment entry), S4.1 amend and reverse, S3.1 and onboarding opening
// balances. Those surfaces belong to other feature folders; each should call
// [entryRestrictionSourcesOf] before its first await and
// [entryRestrictionFor] with every book it appends to, then raise
// `showRkBlockedEntrySheet` — recorded as an open item for a follow-up slice.
import 'package:flutter/widgets.dart';

import '../../shared/seams/sync_client.dart';
import '../../shared/widgets/rk_restriction.dart';
import '../subscription/entitlement_source.dart';
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
    // ⚠️ SPEC: 07 §20 / ADR 2026-09-05g say nothing about a device that
    // cannot read the token it holds. The reading taken is ADR 2026-09-05g
    // §1 🔒's — *no valid token is Free, never locked* — so a read failure
    // never stands in front of a save (07 §1 rule 6: no dead ends). The
    // server stays the hard cap (ADR 2026-09-05g §2): a lapsed tenant's push
    // is refused there whatever this phone concluded.
    reading = Entitlement.untokened();
  }
  if (reading.state.blocksEntry) return RkRestrictionKind.readOnly;
  final sync = sources.sync;
  if (sync != null && bookIds.any(sync.isBookFull)) {
    return RkRestrictionKind.bookFull;
  }
  return null;
}
