// The app's first entitlement seam (S12.x, 07 §20 🔒; ADR 2026-09-05g §1).
//
// `shared/widgets/rk_restriction.dart` states the position this lane inherits:
// *"There is no entitlement or quota source in the app yet — the signal lands
// with sync"*. That is still true of the **producer**. What lands here is the
// shape the producer will fill: a read-only mirror of the entitlement token's
// fields, so the two subscription screens render a state rather than invent
// one.
//
// **Faithful to the token, not to a screen** (ADR 2026-09-05g §1, amended by
// ADR 2026-09-24b §6): the server signs `{tenant_id, plan, limits{members,
// business_books, devices, envelopes_per_book, tenant_bytes,
// attachment_bytes}, period_end, grace_kind, grace_until, iat, exp}` — and,
// since ADR 2026-09-25 §6, `features` after `limits` (M11-CAT1; read here
// since M13-CAT2 as [Entitlement.features], which every feature gate asks).
// Every field this app reads is below, under the same name. The
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

/// A tenant's plan: a **catalogue id**, not one of four fixed names (ADR
/// 2026-09-25 §6 🔒: *"The token's `plan` becomes a catalogue id"*).
///
/// The id is the whole identity. A plan this build has never heard of — the
/// owner adds one to `plan_catalogue` tomorrow — is still a plan: it reads,
/// compares and round-trips like any other, and a screen names it with the
/// generic words (`subscription_copy.dart`), never a crash (CLAUDE.md rule 6).
///
/// Names, quotas and prices are **not** here. Quotas and features the tenant
/// holds come from the signed token ([Entitlement]); prices and the popular
/// flag come from the catalogue (`plan_catalogue_source.dart`).
@immutable
final class RkPlan {
  /// A plan by its catalogue id.
  const RkPlan(this.id);

  /// Reads the token's or the catalogue's `plan`/`id`. Any non-empty string
  /// is a plan; anything else is a malformed payload.
  factory RkPlan.fromWire(Object? raw) => switch (raw) {
    final String id when id.isNotEmpty => RkPlan(id),
    _ => throw FormatException('plan is not a catalogue id', '$raw'),
  };

  /// The catalogue id (`plan_catalogue.id`, 0018).
  final String id;

  /// Individual — the permanent Free plan (ADR 2026-09-25 §5), and the
  /// reading of a tenant with no token (ADR 2026-09-05g §1 🔒).
  static const RkPlan free = RkPlan('free');

  /// Individual — Personal.
  static const RkPlan personal = RkPlan('personal');

  /// Business — Shop.
  static const RkPlan shop = RkPlan('shop');

  /// Business — Business.
  static const RkPlan business = RkPlan('business');

  /// Business — Business+.
  static const RkPlan businessPlus = RkPlan('business_plus');

  /// Family — Family Lite.
  static const RkPlan familyLite = RkPlan('family_lite');

  /// Family — Family.
  static const RkPlan family = RkPlan('family');

  /// Family — Family+.
  static const RkPlan familyPlus = RkPlan('family_plus');

  /// Trust — Trust.
  static const RkPlan trust = RkPlan('trust');

  /// Trust — Trust+.
  static const RkPlan trustPlus = RkPlan('trust_plus');

  /// The ids this build has **words** for (ARB, EN/PA/HI). Not a whitelist:
  /// a plan outside it is read, compared and shown under generic words.
  static const List<RkPlan> named = [
    free,
    personal,
    shop,
    business,
    businessPlus,
    familyLite,
    family,
    familyPlus,
    trust,
    trustPlus,
  ];

  @override
  bool operator ==(Object other) => other is RkPlan && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RkPlan($id)';
}

/// The extras a plan may include — the token's `features` (ADR 2026-09-25
/// §5–§6 🔒). ADR 25 §5 names exactly two, and `registry.ts`'s `FEATURES` is
/// the same list; everything else a book does is *never restricted*.
///
/// A gate asks [Entitlement.has] for one of these. It never infers a feature
/// from the plan's name: moving a feature between plans is a catalogue edit
/// that reaches the app at the next sync, with no release.
enum RkFeature {
  /// PDF statements and reports, and sharing them (ADR 25 §5).
  pdfOutput('pdf_output'),

  /// Bank statement import (ADR 25 §3, §5).
  statementImport('statement_import');

  const RkFeature(this.wire);

  /// The name on the wire.
  final String wire;
}

/// The token's `features` as the app holds them: **sorted, unique, and `[]`
/// when the plan has none** (ADR 2026-09-25 §6; M11-CAT1's `featuresOf`).
///
/// A name this build does not know is **kept**, not dropped (CLAUDE.md rule
/// 6): it gates nothing here, and it is still there for whatever reads the
/// reading next. Absent or null reads as `[]`. Anything that is not a list of
/// strings is a malformed token and throws [FormatException] — reading it as
/// `[]` would quietly turn a broken token into a Free one.
List<String> rkFeaturesFromWire(Object? raw) => switch (raw) {
  null => const [],
  final List<Object?> list => rkNormalisedFeatures([
    for (final f in list)
      if (f is String && f.isNotEmpty)
        f
      else
        throw FormatException('features holds a non-name', '$f'),
  ]),
  _ => throw FormatException('features is not a list', '$raw'),
};

/// Sorted and de-duplicated, unmodifiable.
List<String> rkNormalisedFeatures(Iterable<String> features) =>
    List.unmodifiable(features.toSet().toList()..sort());

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

  /// Renewal failed: tenant-wide, S12.4, ending on the date the server
  /// declares in `grace_until` (ADR 2026-09-05g §4, ADR 2026-09-24b §6 🔒).
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

/// 08 §2's per-file cap — 10 MB on every plan. Plan-independent, so it is
/// in neither the token's `limits{}` nor the catalogue (`registry.ts`
/// `PlanLimits`: "08 §2's per-file cap … is deliberately absent").
const int rkPerFileBytes = 10 * 1024 * 1024;

/// "No cap" on the wire — ADR 2026-09-24b §7 (b) 🔒: *"An unlimited limit … is
/// **`-1`** on the wire."* The app holds it as null, never as a number.
const int rkNoCapOnWire = -1;

/// The token's `limits{}` block, field for field (ADR 2026-09-05g §1), with
/// the per-file cap 08 §2 lists in the same table.
///
/// A null count means **unlimited** (`-1` on the wire) — unlimited is not a
/// large number.
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

  /// The six wire names, in the token's order (`registry.ts` `PlanLimits`).
  static const List<String> wireFields = [
    'members',
    'business_books',
    'devices',
    'envelopes_per_book',
    'tenant_bytes',
    'attachment_bytes',
  ];

  /// Reads a `limits{}` object — the token's, or a catalogue row's (the two
  /// carry the same six names). `-1` is unlimited. A missing or non-integer
  /// count is malformed and throws [FormatException]: guessing a cap would
  /// either invent entitlement or take it away. Keys this build does not
  /// know are ignored here; the catalogue keeps them for its round trip.
  factory EntitlementLimits.fromWire(Map<String, Object?> wire) {
    int? count(String field) => switch (wire[field]) {
      rkNoCapOnWire => null,
      final int n when n >= 0 => n,
      final other => throw FormatException(
        'limits.$field is not a count',
        '$other',
      ),
    };
    return EntitlementLimits(
      members: count('members'),
      businessBooks: count('business_books'),
      devices: count('devices'),
      envelopesPerBook: count('envelopes_per_book'),
      tenantBytes: count('tenant_bytes'),
      attachmentBytes: count('attachment_bytes'),
      perFileBytes: rkPerFileBytes,
    );
  }

  /// The six wire fields back, unlimited as `-1`.
  Map<String, Object?> toWire() => {
    'members': members ?? rkNoCapOnWire,
    'business_books': businessBooks ?? rkNoCapOnWire,
    'devices': devices ?? rkNoCapOnWire,
    'envelopes_per_book': envelopesPerBook ?? rkNoCapOnWire,
    'tenant_bytes': tenantBytes ?? rkNoCapOnWire,
    'attachment_bytes': attachmentBytes ?? rkNoCapOnWire,
  };

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
  /// Creates a reading. [features] is normalised — sorted, unique — so two
  /// readings of one token compare alike however the list arrived.
  ///
  /// [features] defaults to `[]`, which gates **closed**: a reading built
  /// without it holds no PDF output and no statement import. Callers outside
  /// this feature (the S12.5 test harnesses) build readings without it and
  /// are, correctly, readings of a plan with no extras.
  Entitlement({
    required this.tenantId,
    required this.plan,
    required this.limits,
    required this.periodEnd,
    required this.graceKind,
    this.graceUntil,
    required this.source,
    required this.activeMembers,
    Iterable<String> features = const [],
  }) : features = rkNormalisedFeatures(features);

  /// The untokened reading — the only honest one until the meta channel
  /// delivers a token (05 §5). Free, live, blocking nothing (ADR
  /// 2026-09-05g §1 🔒).
  ///
  /// Its `features` are `[]`: Free includes neither PDF output nor statement
  /// import (ADR 2026-09-25 §5 🔒). Its limits are the Free row of the
  /// **offline fallback** catalogue (`rkOfflineCatalogue`, a mirror of 0018's
  /// seed) — there is no token to read them from, and the server signs the
  /// same Free floor for a tenant with no row (M11-CAT1 `planOf`).
  factory Entitlement.untokened({int activeMembers = 1}) => Entitlement(
    tenantId: null,
    plan: RkPlan.free,
    limits: rkTierFor(RkPlan.free).limits,
    periodEnd: null,
    graceKind: EntitlementGraceKind.none,
    source: EntitlementSourceKind.absent,
    activeMembers: activeMembers,
  );

  /// A reading from a verified token. This is the one constructor a producer
  /// uses (PLAN desk 23c). Both dates come from [times], the wire parse
  /// ([EntitlementTokenTimes.fromPayload]), so the producer cannot fill
  /// `period_end` and drop `grace_until` (ADR 2026-09-24b §6 🔒). [source] is
  /// fresh or stale, never absent: an absent reading is
  /// [Entitlement.untokened].
  ///
  /// ⚠️ SPEC (owner item): the plain constructor still leaves [graceUntil]
  /// optional, because test files outside this feature build an
  /// [Entitlement] without it. Making it `required` is the stronger guard,
  /// and it needs those files changed at the same time.
  ///
  /// [features] is the token's `features` ([rkFeaturesFromWire] reads it).
  /// ⚠️ SPEC (M13-CAT2, owner item): it is optional here only because a test
  /// outside this feature (`test/shared/entitlement_shell_test.dart`) builds
  /// a token reading without it; omitted, it gates closed. Making it
  /// `required` is the stronger guard once that file passes it.
  factory Entitlement.fromToken({
    required String tenantId,
    required RkPlan plan,
    required EntitlementLimits limits,
    required EntitlementGraceKind graceKind,
    required EntitlementTokenTimes times,
    required EntitlementSourceKind source,
    required int activeMembers,
    Iterable<String> features = const [],
  }) {
    if (source == EntitlementSourceKind.absent) {
      throw ArgumentError.value(
        source,
        'source',
        'a token reading is fresh or stale; absent is Entitlement.untokened',
      );
    }
    return Entitlement(
      tenantId: tenantId,
      plan: plan,
      limits: limits,
      periodEnd: times.periodEnd,
      graceKind: graceKind,
      graceUntil: times.graceUntil,
      source: source,
      activeMembers: activeMembers,
      features: features,
    );
  }

  /// The token's `tenant_id`. Null when no token has been seen.
  final String? tenantId;

  /// The token's `plan`.
  final RkPlan plan;

  /// The token's `limits{}`.
  final EntitlementLimits limits;

  /// The token's `features` — the extras this plan includes (ADR 2026-09-25
  /// §6): sorted, unique, `[]` when the plan has none. Unknown names are
  /// kept (see [rkFeaturesFromWire]).
  final List<String> features;

  /// Whether this reading includes [feature].
  ///
  /// 🔒 The **only** question a feature gate asks (ADR 2026-09-25 §6: *"The
  /// app's gates read the token"*). Not the plan's name, not the catalogue
  /// (unsigned, display-only), and not [state]: a lapsed or stale reading
  /// still names the extras its plan carries, and the read-only rule is
  /// [EntitlementState.blocksEntry]'s business, not a feature gate's.
  bool has(RkFeature feature) => features.contains(feature.wire);

  /// The token's `period_end` — the renewal date S12 shows. Null on Free and
  /// on an untokened reading: there is nothing to renew.
  final DateTime? periodEnd;

  /// The token's `grace_kind`.
  final EntitlementGraceKind graceKind;

  /// The token's `grace_until` — the date the **server** declares the dunning
  /// grace ends (ADR 2026-09-24b §6 🔒). Null unless `grace_kind = dunning`,
  /// and null on an untokened reading. Mirrored as the token carries it; read
  /// it through [dunningGraceUntil], which ignores it outside dunning.
  ///
  /// 🔒 The client never derives `period_end + 7 d` in its place.
  final DateTime? graceUntil;

  /// The dunning end date a screen may count down to, or null when there is
  /// none to show.
  ///
  /// Null outside [EntitlementState.dunningGrace] whatever the token carried
  /// — the token says `grace_until` is null unless dunning, and a stale
  /// reading is offline grace, which has no countdown (07 §20). Null, too, in
  /// dunning when the token carried no date.
  ///
  /// ⚠️ SPEC (PLAN desk 46, unruled): dunning with a null `grace_until` — only
  /// a hand edit of `subscriptions` makes one, and ADR 2026-09-24b §6 does not
  /// say what the client shows. Conservative reading: **never invent a date**.
  /// S12.4 shows the payment problem and its fix path with no countdown and
  /// no day count; entry keeps working, because dunning *is* the grace
  /// ([EntitlementState.blocksEntry]).
  DateTime? get dunningGraceUntil =>
      state == EntitlementState.dunningGrace ? graceUntil : null;

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

/// The token's two dates, read from its decoded payload (ADR 2026-09-24b §6
/// 🔒; wire form in `server/supabase/functions/_shared/sodium.ts`: epoch
/// **milliseconds** as JSON integers, or null).
///
/// This is **not** the token verifier (PLAN desk 23c) and not a whole-payload
/// parse: signature and `exp` belong to the producer, and the other fields
/// have their own readers ([RkPlan.fromWire], [EntitlementLimits.fromWire],
/// [rkFeaturesFromWire]). It is the one place this feature
/// turns the wire's dates into [DateTime]s. The producer, when it lands,
/// passes the result to [Entitlement.fromToken], which fills
/// [Entitlement.periodEnd] and [Entitlement.graceUntil] from it. Both dates
/// are UTC, so a screen converts with `.toLocal()` before it takes the
/// calendar day (`localDateOf`).
///
/// **Tolerant of what it does not read** (CLAUDE.md rule 6's spirit): every
/// other key — `features`, or a field the server adds tomorrow — is ignored,
/// never an error. An **absent** date reads as null, like an explicit null.
/// A date of the wrong type is a malformed token and throws
/// [FormatException] — reading it as null would quietly turn a broken token
/// into desk 46's no-date case.
class EntitlementTokenTimes {
  /// Creates the pair.
  const EntitlementTokenTimes({this.periodEnd, this.graceUntil});

  /// Reads `period_end` and `grace_until` from a decoded token [payload].
  factory EntitlementTokenTimes.fromPayload(Map<String, Object?> payload) =>
      EntitlementTokenTimes(
        periodEnd: _epochMs(payload, 'period_end'),
        graceUntil: _epochMs(payload, 'grace_until'),
      );

  /// The token's `period_end`, in UTC.
  final DateTime? periodEnd;

  /// The token's `grace_until`, in UTC.
  final DateTime? graceUntil;

  static DateTime? _epochMs(Map<String, Object?> payload, String field) =>
      switch (payload[field]) {
        null => null,
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        final other => throw FormatException(
          'entitlement token: $field is not epoch milliseconds',
          other.runtimeType.toString(),
        ),
      };
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
