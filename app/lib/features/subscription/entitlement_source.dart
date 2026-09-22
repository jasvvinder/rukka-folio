// The app's first entitlement seam (S12.x, 07 §20 🔒; ADR 2026-09-05g §1).
//
// `shared/widgets/rk_restriction.dart` states the position this lane inherits:
// *"There is no entitlement or quota source in the app yet — the signal lands
// with sync"*. That is still true of the **producer**. What lands here is the
// shape the producer will fill: a read-only mirror of the entitlement token's
// fields, so the two subscription screens render a state rather than invent
// one.
//
// **Faithful to the token, not to a screen** (ADR 2026-09-05g §1): the server
// signs `{tenant_id, plan, limits{members, business_books, devices,
// envelopes_per_book, tenant_bytes, attachment_bytes}, period_end, grace_kind,
// iat, exp}`. Every one of those is a field below, under the same name. The
// one addition is [EntitlementSourceKind] — **where this reading came from** —
// because the device-local half of ADR 2026-09-05g §4's *two graces* is not in
// the token at all: it is the fact that this phone has not reached the server
// since the last one expired.
//
// 🔒 **Two graces, two copies.** The dunning grace is tenant-wide and
// server-declared; offline grace is device-local and **never** says the plan
// lapsed. That rule is made structural here rather than left to a screen:
// [Entitlement.state] returns [EntitlementState.offlineGrace] for a stale
// reading whatever the stale token said, so no caller can reach the lapse
// words with a phone that has merely been off-network.
//
// 🔒 **No token is not a lock** (ADR 2026-09-05g §1: *"A tenant with no valid
// token is Free, never locked"*). An absent reading is a live Free tenant, not
// read-only.
//
// No clock, no network, no producer: nothing here reads `DateTime.now()`. A
// reading is handed to this app already resolved (the meta channel refreshes
// it, 05 §5), which is also why the app's own clock cannot be used to lapse a
// tenant — ADR 2026-09-05g §4's clock floor is the server's job.
library;

import 'package:flutter/widgets.dart';

import 'tier_catalogue.dart';

/// Which of ADR 2026-09-05g §1's plans a tenant is on.
///
/// Names, quotas and prices are **not** here — they live in
/// `tier_catalogue.dart` as data, so no widget carries a number.
enum RkPlan {
  /// 08 §2 — 1 member, personal + 1 business book, watermarked report exports.
  free,

  /// 08 §2 — 1 member, unlimited books, clean exports, statement import.
  personal,

  /// 08 §2 — up to 5 active members, up to 3 business books.
  family,

  /// 08 §2 — up to 15 active members, unlimited business books.
  familyPlus,
}

/// The token's `grace_kind` — what the **server** has declared about this
/// tenant (13 §6: `trial → active → dunning grace → read-only`).
///
/// Offline grace is deliberately **not** a member: it is not something a
/// server can declare about a tenant, it is something a device knows about
/// itself ([EntitlementSourceKind.stale]).
enum EntitlementGraceKind {
  /// A paid, current subscription.
  none,

  /// The 30-day Family trial — once per user, not per tenant (08 §2).
  trial,

  /// Renewal failed: 7 days from `period_end`, tenant-wide, S12.4 (ADR
  /// 2026-09-05g §4).
  dunning,

  /// The server has said the plan ended. Read-only: entry stops, reading,
  /// exporting and closing carry on (08 §1 🔒 *lapsed ≠ locked*).
  lapsed,
}

/// Where a reading came from — the device-local half of the two graces.
enum EntitlementSourceKind {
  /// A token this device holds and that has not expired.
  fresh,

  /// The last token this device saw, past its `exp`, with no reach to the
  /// server since. **Offline grace**: nothing is blocked and nothing has
  /// lapsed (ADR 2026-09-05g §4 🔒).
  stale,

  /// No token has ever been seen — a new install, or a build with no meta
  /// channel yet. Free, and *never* locked (ADR 2026-09-05g §1 🔒).
  absent,
}

/// What a screen shows — 13 §6's five states, four declarable by the server
/// and one known only to this phone.
enum EntitlementState {
  /// 30-day Family trial (08 §2).
  trial,

  /// Paid and current — or an untokened Free tenant, which is equally live.
  active,

  /// Renewal failed, tenant-wide, counting down to read-only (S12.4).
  dunningGrace,

  /// Server-declared lapse: new entry is blocked, everything else works
  /// (S12.5, 08 §1 🔒).
  readOnly,

  /// Device-local: this phone has not reached the server since its token
  /// expired. **Blocks nothing** (ADR 2026-09-05g §4 🔒).
  offlineGrace;

  /// Whether new entry is blocked in this state.
  ///
  /// Only the server-declared lapse blocks. Dunning grace is *the grace* — it
  /// exists so entry keeps working while a payment is retried — and offline
  /// grace blocks nothing by rule.
  bool get blocksEntry => this == EntitlementState.readOnly;

  /// Export is never blocked, in any state, ever (08 §1 🔒, ADR 2026-09-05g
  /// §3, §5). A getter so a call site reads the rule instead of restating it.
  bool get blocksExport => false;
}

/// The token's `limits{}` block, field for field (ADR 2026-09-05g §1), with
/// the per-file cap 08 §2 lists in the same table.
///
/// A null count means **unlimited** — 08 §2 gives Personal unlimited books and
/// Family+ unlimited business books, and unlimited is not a large number.
class EntitlementLimits {
  /// Creates a limits block.
  const EntitlementLimits({
    required this.members,
    required this.businessBooks,
    required this.devices,
    required this.envelopesPerBook,
    required this.tenantBytes,
    required this.attachmentBytes,
    required this.perFileBytes,
  });

  /// Active members, counting `invited` + `joined_pending_verification` +
  /// `active` (06 §7, ADR 2026-09-05g §6). Null = unlimited.
  final int? members;

  /// Business books. Null = unlimited.
  final int? businessBooks;

  /// Devices per user — the highest across the user's active tenants (06 §6).
  final int? devices;

  /// Envelopes per book before `rejected:quota` (08 §2 🔒).
  final int? envelopesPerBook;

  /// Tenant envelope bytes (08 §2 🔒).
  final int? tenantBytes;

  /// Attachment bytes (08 §2 🔒).
  final int? attachmentBytes;

  /// Per-file cap — 10 MB on every tier (08 §2 🔒).
  final int? perFileBytes;
}

/// One resolved reading of a tenant's entitlement.
class Entitlement {
  /// Creates a reading.
  const Entitlement({
    required this.tenantId,
    required this.plan,
    required this.limits,
    required this.periodEnd,
    required this.graceKind,
    required this.source,
    required this.activeMembers,
  });

  /// The untokened reading — the only honest one until the meta channel
  /// delivers a token (05 §5). Free, live, blocking nothing (ADR
  /// 2026-09-05g §1 🔒).
  factory Entitlement.untokened({int activeMembers = 1}) => Entitlement(
    tenantId: null,
    plan: RkPlan.free,
    limits: rkTierFor(RkPlan.free).limits,
    periodEnd: null,
    graceKind: EntitlementGraceKind.none,
    source: EntitlementSourceKind.absent,
    activeMembers: activeMembers,
  );

  /// The token's `tenant_id`. Null when no token has been seen.
  final String? tenantId;

  /// The token's `plan`.
  final RkPlan plan;

  /// The token's `limits{}`.
  final EntitlementLimits limits;

  /// The token's `period_end` — the renewal date S12 shows. Null on Free and
  /// on an untokened reading: there is nothing to renew.
  final DateTime? periodEnd;

  /// The token's `grace_kind`.
  final EntitlementGraceKind graceKind;

  /// Active members counted against [EntitlementLimits.members] — plaintext
  /// metadata, the only thing 08 §3 🔒 enforces on.
  final int activeMembers;

  /// Where this reading came from — **not** a token field (see
  /// [EntitlementSourceKind]).
  final EntitlementSourceKind source;

  /// The state a screen renders.
  ///
  /// 🔒 The ordering is the rule, not a convenience: a **stale** reading is
  /// offline grace *whatever it says*, so the lapse copy is unreachable from
  /// a phone that has merely been off-network (ADR 2026-09-05g §4, 13 §6,
  /// 07 §20). An **absent** reading is a live Free tenant (ADR 2026-09-05g
  /// §1). Only a **fresh** reading can say read-only.
  EntitlementState get state => switch (source) {
    EntitlementSourceKind.stale => EntitlementState.offlineGrace,
    EntitlementSourceKind.absent => EntitlementState.active,
    EntitlementSourceKind.fresh => switch (graceKind) {
      EntitlementGraceKind.none => EntitlementState.active,
      EntitlementGraceKind.trial => EntitlementState.trial,
      EntitlementGraceKind.dunning => EntitlementState.dunningGrace,
      EntitlementGraceKind.lapsed => EntitlementState.readOnly,
    },
  };

  /// Whether this tenant is larger than any plan covers (08 §2, ADR
  /// 2026-09-05g §14 🔒): above 15 members a band is **decided at the pilot**,
  /// and until then the plan screen says so rather than refusing.
  bool get aboveLargestBand => activeMembers > rkLargestMemberBand;
}

/// Reads the tenant's entitlement. One method, because a token is a whole
/// reading: the app never asks "am I allowed to X" of a half-loaded state.
abstract interface class EntitlementSource {
  /// The current reading. Throws only on a genuine failure to read what the
  /// device already holds — never on being offline, which is a reading of its
  /// own ([EntitlementSourceKind.stale]).
  Future<Entitlement> read();
}

/// The production source until a producer exists: every device reads as
/// *no token seen* → Free, live, nothing blocked.
///
/// This is not a stub standing in for behaviour — it is exactly what ADR
/// 2026-09-05g §1 🔒 says an app with no valid token must conclude. When the
/// meta channel lands (05 §5) it replaces this one; nothing above it changes.
class UntokenedEntitlementSource implements EntitlementSource {
  /// Creates the source.
  const UntokenedEntitlementSource({this.activeMembers = 1});

  /// Members this tenant has, when the caller knows (the members feature owns
  /// that count; 1 is the solo reading).
  final int activeMembers;

  @override
  Future<Entitlement> read() async =>
      Entitlement.untokened(activeMembers: activeMembers);
}

/// Test double. Hands back whatever reading it was built with, or throws.
class FakeEntitlementSource implements EntitlementSource {
  /// Creates the fake. With [failure] set, [read] throws it — that is how the
  /// error state is reached.
  FakeEntitlementSource({Entitlement? entitlement, this.failure})
    : entitlement = entitlement ?? Entitlement.untokened();

  /// The reading handed back.
  Entitlement entitlement;

  /// When set, [read] throws this instead.
  Object? failure;

  /// How many times [read] was called — a retry is observable.
  int reads = 0;

  @override
  Future<Entitlement> read() async {
    reads++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return entitlement;
  }
}

/// Hands an [EntitlementSource] down the tree.
///
/// Absent, the routes fall back to [UntokenedEntitlementSource] — which is
/// not a placeholder but the reading ADR 2026-09-05g §1 🔒 requires of an app
/// holding no valid token: Free, and never locked. When the meta channel
/// (05 §5) lands, the shell mounts one of these and nothing below changes.
class EntitlementScope extends InheritedWidget {
  /// Creates the scope.
  const EntitlementScope({
    super.key,
    required this.source,
    required super.child,
  });

  /// The source screens below will read.
  final EntitlementSource source;

  /// The nearest scope, or null.
  static EntitlementScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EntitlementScope>();

  @override
  bool updateShouldNotify(EntitlementScope oldWidget) =>
      oldWidget.source != source;
}
