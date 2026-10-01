// The plan catalogue as the app holds it — what `GET /sync-meta/plans`
// returns (ADR 2026-09-25 §6 🔒: *"The app downloads the catalogue on the
// meta channel (05 §5) and renders S12.1 from it"*).
//
// ⚠️ WIRE — the contract is `server/supabase/functions/sync-meta/index.ts`
// (`planToWire`) over migration `0018_plan_catalogue.sql`:
//   `{plans: [{id, entity_type, name, sort_order, limits{members,
//   business_books, devices, envelopes_per_book, tenant_bytes,
//   attachment_bytes}, features[], price_yearly_paise, price_monthly_paise,
//   popular, placeholder, updated_at}], catalogue_updated_at}`.
//
// **Display only.** The catalogue is unsigned product configuration; no gate
// reads it. What a tenant *holds* — limits and features — is the signed
// token's (`Entitlement.limits`, `Entitlement.has`). This file prices and
// describes plans; it never decides what a tenant may do.
//
// 🔒 **Unknown ids and unknown fields round-trip** (CLAUDE.md rule 6). A plan
// id this build has no words for is still a plan; a field the server adds
// tomorrow is kept in [RkTier.extra] and written back by [RkTier.toJson]; a
// row this build cannot read at all is kept whole in
// [RkPlanCatalogue.unreadable] and simply not drawn. Nothing here crashes on
// the catalogue growing.
//
// 💰 **Integer paise, always** (CLAUDE.md rule 1). A price that arrives as
// anything but a JSON integer makes its row unreadable rather than being
// rounded into one. The annual saving is integer arithmetic (`~/`), and the
// truncation is deliberate: a price screen may never overstate a saving.
//
// **The offline fallback** ([rkOfflineCatalogue]) is a labelled mirror of
// 0018's seed rows. It exists because two things have nothing else to draw:
// the untokened reading's Free limits (no token, so no `limits{}` to read —
// ADR 2026-09-05g §1 🔒) and S12.1 in a build where no catalogue channel is
// mounted yet. It is never a gate, and the HTTP source never falls back to
// it: once the server has answered, the server's catalogue is the one shown.
// F1-25-10 reads 0018 itself, so the mirror cannot drift from the seed.
library;

import 'entitlement_source.dart';

const int _kb = 1024;
const int _mb = 1024 * _kb;
const int _gb = 1024 * _mb;

/// The largest member count any plan covers **before the catalogue** (08 §2,
/// ADR 2026-09-05g §14 🔒: above this a tenant is told so, never refused).
///
/// ⚠️ SPEC (M13-CAT2): ADR 2026-09-25 §5's catalogue seats up to 30 (Family+,
/// Business+) and 40 (Trust+), so 15 is no longer *the largest band*. §14's
/// rule — *told, never refused* — is untouched, and the number is left as 08
/// §2 wrote it until the owner rules whether the organisation line follows
/// the catalogue's largest plan. PLAN desk item.
const int rkLargestMemberBand = 15;

/// How a subscription is billed. 08 §3.1 🔒 puts both on one toggle.
enum RkBillingCycle {
  /// The fallback (08 §2 principle 2).
  monthly,

  /// The default — and the one the saving is shown against.
  annual,
}

/// ADR 2026-09-25 §5's entity types — S0.3's cards (0018
/// `plan_catalogue.entity_type`). Strings, not an enum: a type this build
/// does not know still groups and round-trips.
abstract final class RkEntityType {
  /// *Myself*.
  static const String individual = 'individual';

  /// *My family*.
  static const String family = 'family';

  /// *My shop* / *My businesses*.
  static const String business = 'business';

  /// A trust or society.
  static const String trust = 'trust';
}

/// One catalogue row: its entity type, limits, extras, two prices in paise and
/// whether it is the entity type's *popular* plan.
class RkTier {
  /// Creates a row.
  const RkTier({
    required this.plan,
    required this.entityType,
    required this.limits,
    required this.features,
    required this.monthlyPaise,
    required this.annualPaise,
    required this.popular,
    this.sortOrder = 0,
    this.placeholder = true,
    this.extra = const {},
    this.limitsExtra = const {},
  });

  /// Reads one `plans[]` row. Throws [FormatException] when a field this
  /// build must read is missing or of the wrong type — a price that is not a
  /// JSON integer included (CLAUDE.md rule 1). Every other key is kept in
  /// [extra]; unknown `limits` keys in [limitsExtra].
  factory RkTier.fromJson(Map<String, Object?> j) {
    final limits = switch (j['limits']) {
      final Map<Object?, Object?> m => m.cast<String, Object?>(),
      final other => throw FormatException('limits is not an object', '$other'),
    };
    return RkTier(
      plan: RkPlan.fromWire(j['id']),
      entityType: switch (j['entity_type']) {
        final String t when t.isNotEmpty => t,
        final other => throw FormatException('entity_type', '$other'),
      },
      limits: EntitlementLimits.fromWire(limits),
      features: rkFeaturesFromWire(j['features']),
      annualPaise: _paise(j, 'price_yearly_paise'),
      monthlyPaise: _paise(j, 'price_monthly_paise'),
      popular: switch (j['popular']) {
        final bool b => b,
        final other => throw FormatException('popular', '$other'),
      },
      sortOrder: switch (j['sort_order']) {
        null => 0,
        final int n => n,
        final other => throw FormatException('sort_order', '$other'),
      },
      placeholder: switch (j['placeholder']) {
        null => true,
        final bool b => b,
        final other => throw FormatException('placeholder', '$other'),
      },
      extra: {
        for (final e in j.entries)
          if (!_rowFields.contains(e.key)) e.key: e.value,
      },
      limitsExtra: {
        for (final e in limits.entries)
          if (!EntitlementLimits.wireFields.contains(e.key)) e.key: e.value,
      },
    );
  }

  static const _rowFields = {
    'id',
    'entity_type',
    'sort_order',
    'limits',
    'features',
    'price_yearly_paise',
    'price_monthly_paise',
    'popular',
    'placeholder',
  };

  static int _paise(Map<String, Object?> j, String field) => switch (j[field]) {
    final int p when p >= 0 => p,
    final other => throw FormatException(
      '$field is not integer paise',
      '$other',
    ),
  };

  /// Which plan this is — any catalogue id.
  final RkPlan plan;

  /// The entity type it is sold to ([RkEntityType]).
  final String entityType;

  /// The limits the catalogue *describes*. What a tenant holds is its token's
  /// `limits{}` ([Entitlement.limits]), which the server signs from this row.
  final EntitlementLimits limits;

  /// The extras this plan includes (sorted, unique — [RkFeature] wire names,
  /// unknown ones kept).
  final List<String> features;

  /// Monthly price, integer paise, GST-inclusive. Zero on Free.
  final int monthlyPaise;

  /// Yearly price, integer paise, GST-inclusive. Zero on Free.
  final int annualPaise;

  /// The entity type's *popular* plan — the intended buy, and the one its
  /// trial runs on (ADR 2026-09-25 §5).
  final bool popular;

  /// Order within the entity type (cheapest first in 0018).
  final int sortOrder;

  /// The catalogue's own flag that this row's numbers are working
  /// placeholders (ADR 2026-09-25 §5: *"placeholders until the pilot"*).
  final bool placeholder;

  /// Every other field of the row, as it arrived — `name` (the owner's
  /// English console label, **never rendered**: CLAUDE.md rule 8 — S12.1 names
  /// a plan from ARB by its id), `updated_at`, and whatever the server adds.
  final Map<String, Object?> extra;

  /// `limits` keys this build does not read, as they arrived.
  final Map<String, Object?> limitsExtra;

  /// Whether this plan includes [feature] — for **describing** the plan on a
  /// card. A gate asks the token ([Entitlement.has]), never this.
  bool describes(RkFeature feature) => features.contains(feature.wire);

  /// Whether this plan is bought at all.
  bool get isFree => annualPaise == 0 && monthlyPaise == 0;

  /// What twelve monthly payments cost — the figure the annual saving is
  /// measured against (08 §3.1 🔒).
  int get twelveMonthsPaise => monthlyPaise * 12;

  /// Paise saved by paying annually. Never negative in 0018 (its CHECK is
  /// monthly × 10 = yearly: *ten months' price for twelve*, ADR 25 §5).
  int get annualSavingPaise => twelveMonthsPaise - annualPaise;

  /// The saving as a whole percent, **truncated** — integer arithmetic on
  /// integer paise (CLAUDE.md rule 1), and truncation never overstates.
  /// Zero when there is nothing to save.
  int get annualSavingPercent =>
      twelveMonthsPaise == 0 || annualSavingPaise <= 0
      ? 0
      : (annualSavingPaise * 100) ~/ twelveMonthsPaise;

  /// Price for [cycle], in paise.
  int priceFor(RkBillingCycle cycle) => switch (cycle) {
    RkBillingCycle.monthly => monthlyPaise,
    RkBillingCycle.annual => annualPaise,
  };

  /// The row back on the wire — every field it arrived with, unknown ones
  /// included (CLAUDE.md rule 6).
  Map<String, Object?> toJson() => {
    ...extra,
    'id': plan.id,
    'entity_type': entityType,
    'sort_order': sortOrder,
    'limits': {...limitsExtra, ...limits.toWire()},
    'features': [...features],
    'price_yearly_paise': annualPaise,
    'price_monthly_paise': monthlyPaise,
    'popular': popular,
    'placeholder': placeholder,
  };
}

/// The whole catalogue.
class RkPlanCatalogue {
  /// Creates a catalogue.
  const RkPlanCatalogue({
    required this.plans,
    this.unreadable = const [],
    this.extra = const {},
    this.offline = false,
  });

  /// Reads a `GET /sync-meta/plans` body. The body must be an object with a
  /// `plans` list — anything else is a malformed answer and throws
  /// [FormatException]. A row that cannot be read is kept whole in
  /// [unreadable] and not drawn; one bad row never costs the others.
  factory RkPlanCatalogue.fromJson(Map<String, Object?> body) {
    final rows = switch (body['plans']) {
      final List<Object?> l => l,
      final other => throw FormatException('plans is not a list', '$other'),
    };
    final plans = <RkTier>[];
    final unreadable = <Object?>[];
    for (final row in rows) {
      if (row is! Map) {
        unreadable.add(row);
        continue;
      }
      try {
        plans.add(RkTier.fromJson(row.cast<String, Object?>()));
      } on FormatException {
        unreadable.add(row);
      }
    }
    return RkPlanCatalogue(
      plans: List.unmodifiable(plans),
      unreadable: List.unmodifiable(unreadable),
      extra: {
        for (final e in body.entries)
          if (e.key != 'plans') e.key: e.value,
      },
    );
  }

  /// Every readable row, in the order the server sent them.
  final List<RkTier> plans;

  /// Rows this build could not read, kept as they arrived.
  final List<Object?> unreadable;

  /// Every other top-level field (`catalogue_updated_at`, and whatever else).
  final Map<String, Object?> extra;

  /// True only for [rkOfflineCatalogue] — the labelled fallback, never the
  /// server's answer.
  final bool offline;

  /// The row for [plan], or null when the catalogue has none.
  RkTier? tierFor(RkPlan plan) {
    for (final t in plans) {
      if (t.plan == plan) return t;
    }
    return null;
  }

  /// [entityType]'s plans, cheapest first ([RkTier.sortOrder]).
  List<RkTier> forEntity(String entityType) =>
      plans.where((t) => t.entityType == entityType).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The plans S12.1 draws for a tenant on [current].
  ///
  /// ⚠️ SPEC (M13-CAT2): ADR 2026-09-25 §5 says S12.1 *"shows only the user's
  /// entity type's plans"*, where the entity type is the one **chosen at
  /// signup** (S0.3). The app holds no signup entity type on the tenant yet,
  /// and S12.1 per entity type is F1-25-5 (waits on Canvas 10). Until then
  /// the entity type is read off the current plan's own catalogue row. When
  /// the current plan is not in the catalogue at all, **every** plan is
  /// returned — ADR 25 §5: *"nothing is hidden"* — rather than guessing a
  /// type.
  List<RkTier> plansAlongside(RkPlan current) {
    final mine = tierFor(current);
    if (mine == null) {
      final all = [...plans];
      final types = <String>[];
      for (final t in all) {
        if (!types.contains(t.entityType)) types.add(t.entityType);
      }
      all.sort((a, b) {
        final byType = types
            .indexOf(a.entityType)
            .compareTo(types.indexOf(b.entityType));
        return byType != 0 ? byType : a.sortOrder.compareTo(b.sortOrder);
      });
      return all;
    }
    return forEntity(mine.entityType);
  }

  /// The body back on the wire, unknown fields and unreadable rows included
  /// (CLAUDE.md rule 6). Unreadable rows follow the readable ones.
  Map<String, Object?> toJson() => {
    ...extra,
    'plans': [for (final t in plans) t.toJson(), ...unreadable],
  };
}

/// The saving the Monthly/Annual toggle shows (08 §3.1 🔒 — the toggle *shows
/// the saving*) over the [tiers] on screen.
///
/// The **smallest** annual saving across the paid ones, so the one headline
/// is true of every card under it and overstates none. Zero when none is
/// paid. Integer arithmetic on integer paise.
int rkAnnualSavingPercentOf(Iterable<RkTier> tiers) {
  int? least;
  for (final t in tiers) {
    if (t.isFree) continue;
    final p = t.annualSavingPercent;
    if (least == null || p < least) least = p;
  }
  return least ?? 0;
}

/// The catalogue row for [plan] in the **offline fallback**.
///
/// For the untokened reading and for test fixtures only — a screen that has
/// a catalogue source reads that, and a gate reads the token. Throws
/// [StateError] for an id 0018 does not seed.
RkTier rkTierFor(RkPlan plan) =>
    rkOfflineCatalogue.tierFor(plan) ??
    (throw StateError('no ${plan.id} row in the offline fallback'));

/// Storage shown in whole GB where it divides, otherwise whole MB — the
/// "plain words, not a spec table" of DESIGN-PACK §11 (S12.1) 🔒. Integer
/// arithmetic throughout.
({int amount, bool gigabytes}) rkStorageOf(int bytes) => bytes % _gb == 0
    ? (amount: bytes ~/ _gb, gigabytes: true)
    : (amount: bytes ~/ _mb, gigabytes: false);

/// ⚠️ **OFFLINE FALLBACK — not the catalogue.** A mirror of the ten rows
/// `0018_plan_catalogue.sql` seeds (placeholders, ADR 2026-09-25 §5), used
/// only where there is nothing else to draw (see the head of this file).
/// F1-25-10 parses 0018 and fails if a number here drifts from it.
const RkPlanCatalogue rkOfflineCatalogue = RkPlanCatalogue(
  offline: true,
  plans: [
    // Individual: Free ₹0 (personal only · 1) · Personal ₹990.
    RkTier(
      plan: RkPlan.free,
      entityType: RkEntityType.individual,
      sortOrder: 1,
      limits: EntitlementLimits(
        members: 1,
        businessBooks: 0,
        devices: 5,
        envelopesPerBook: 10000,
        tenantBytes: 250 * _mb,
        attachmentBytes: 100 * _mb,
        perFileBytes: rkPerFileBytes,
      ),
      features: [],
      annualPaise: 0,
      monthlyPaise: 0,
      popular: false,
    ),
    RkTier(
      plan: RkPlan.personal,
      entityType: RkEntityType.individual,
      sortOrder: 2,
      limits: EntitlementLimits(
        members: 1,
        businessBooks: 3,
        devices: 5,
        envelopesPerBook: 100000,
        tenantBytes: 2 * _gb,
        attachmentBytes: 2 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: ['pdf_output', 'statement_import'],
      annualPaise: 99000,
      monthlyPaise: 9900,
      popular: false,
    ),
    // Business: Shop ₹2,499 · Business ₹2,999 (popular) · Business+ ₹6,999.
    RkTier(
      plan: RkPlan.shop,
      entityType: RkEntityType.business,
      sortOrder: 1,
      limits: EntitlementLimits(
        members: 2,
        businessBooks: 1,
        devices: 8,
        envelopesPerBook: 250000,
        tenantBytes: 5 * _gb,
        attachmentBytes: 5 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: [],
      annualPaise: 249900,
      monthlyPaise: 24990,
      popular: false,
    ),
    RkTier(
      plan: RkPlan.business,
      entityType: RkEntityType.business,
      sortOrder: 2,
      limits: EntitlementLimits(
        members: 10,
        businessBooks: 5,
        devices: 8,
        envelopesPerBook: 250000,
        tenantBytes: 5 * _gb,
        attachmentBytes: 5 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: ['pdf_output', 'statement_import'],
      annualPaise: 299900,
      monthlyPaise: 29990,
      popular: true,
    ),
    RkTier(
      plan: RkPlan.businessPlus,
      entityType: RkEntityType.business,
      sortOrder: 3,
      limits: EntitlementLimits(
        members: 30,
        businessBooks: 15,
        devices: 15,
        envelopesPerBook: 1000000,
        tenantBytes: 15 * _gb,
        attachmentBytes: 20 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: ['pdf_output', 'statement_import'],
      annualPaise: 699900,
      monthlyPaise: 69990,
      popular: false,
    ),
    // Family: Family Lite ₹1,999 · Family ₹2,499 (popular) · Family+ ₹5,999.
    RkTier(
      plan: RkPlan.familyLite,
      entityType: RkEntityType.family,
      sortOrder: 1,
      limits: EntitlementLimits(
        members: 4,
        businessBooks: 2,
        devices: 8,
        envelopesPerBook: 250000,
        tenantBytes: 5 * _gb,
        attachmentBytes: 5 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: [],
      annualPaise: 199900,
      monthlyPaise: 19990,
      popular: false,
    ),
    RkTier(
      plan: RkPlan.family,
      entityType: RkEntityType.family,
      sortOrder: 2,
      limits: EntitlementLimits(
        members: 12,
        businessBooks: 8,
        devices: 8,
        envelopesPerBook: 250000,
        tenantBytes: 5 * _gb,
        attachmentBytes: 5 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: ['pdf_output', 'statement_import'],
      annualPaise: 249900,
      monthlyPaise: 24990,
      popular: true,
    ),
    RkTier(
      plan: RkPlan.familyPlus,
      entityType: RkEntityType.family,
      sortOrder: 3,
      limits: EntitlementLimits(
        members: 30,
        businessBooks: 20,
        devices: 15,
        envelopesPerBook: 1000000,
        tenantBytes: 15 * _gb,
        attachmentBytes: 20 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: ['pdf_output', 'statement_import'],
      annualPaise: 599900,
      monthlyPaise: 59990,
      popular: false,
    ),
    // Trust: Trust ₹1,999 (popular — ⚠️ SPEC desk 49a) · Trust+ ₹3,999.
    RkTier(
      plan: RkPlan.trust,
      entityType: RkEntityType.trust,
      sortOrder: 1,
      limits: EntitlementLimits(
        members: 15,
        businessBooks: 3,
        devices: 8,
        envelopesPerBook: 250000,
        tenantBytes: 5 * _gb,
        attachmentBytes: 5 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: ['pdf_output', 'statement_import'],
      annualPaise: 199900,
      monthlyPaise: 19990,
      popular: true,
    ),
    RkTier(
      plan: RkPlan.trustPlus,
      entityType: RkEntityType.trust,
      sortOrder: 2,
      limits: EntitlementLimits(
        members: 40,
        businessBooks: 10,
        devices: 15,
        envelopesPerBook: 1000000,
        tenantBytes: 15 * _gb,
        attachmentBytes: 20 * _gb,
        perFileBytes: rkPerFileBytes,
      ),
      features: ['pdf_output', 'statement_import'],
      annualPaise: 399900,
      monthlyPaise: 39990,
      popular: false,
    ),
  ],
);

/// Where a purchase is made — 08 §3.2 🔒 as ruled by ADR 2026-09-05g §8:
/// In-App Purchase on iOS, gateway on Android and web.
///
/// It changes what S12.1 may say, not what it costs: the **single INR price
/// on every channel** is the same ruling's other half. On iOS the price shown
/// is StoreKit's live price (ADR 2026-09-25 §6); the catalogue's paise are
/// the Android and web figures.
enum RkCheckoutChannel {
  /// iOS. Apple is merchant of record, so there is **no coupon field and no
  /// external payment link** on this platform, and a GST buyer is pointed to
  /// web checkout (ADR 2026-09-05g §8 🔒).
  inAppPurchase,

  /// Android and web: coupon and GSTIN live on this checkout (08 §3.1 🔒).
  gateway,
}
