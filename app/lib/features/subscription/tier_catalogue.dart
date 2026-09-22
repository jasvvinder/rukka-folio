// The tier catalogue — 08 §2's table as **data** (07 §20, 08 §3.1 🔒).
//
// Every number 08 §2 🔒 fixes lives here and nowhere else: no quota, no price
// and no member band is written into a widget, so a plan card renders a tier
// and a doc change lands in one file.
//
// 💰 **Integer paise, always** (CLAUDE.md rule 1). Prices are paise, GST-
// inclusive at 18 % per 08 §3.1 🔒, and the annual saving is computed by
// integer arithmetic — `~/`, never a `double`. The truncation is deliberate:
// a truncated percentage **understates** the saving, and a price screen may
// never overstate one.
//
// ⚠️ SPEC — **monthly prices are not in the docs.** 08 §2 prices each tier per
// *year* only ("Annual billing … monthly only as a fallback"), while 08 §3.1 🔒
// requires a Monthly/Annual toggle *showing the saving*, which cannot be shown
// without a monthly figure. The conservative reading is taken: the annual
// prices are 08 §2's, and each monthly figure is a **placeholder** derived to
// ADR 2026-09-05g / 08 §3.1's own illustration ("Annual — save 20%") —
// `annual ÷ 0.8 ÷ 12`, rounded **up** to the whole rupee so the displayed
// saving is never larger than the real one. Nothing else in the app reads
// them. The lane report carries this as an owner item; 08 §2's banner already
// marks every price a placeholder pending the launch competitor check.
library;

import 'entitlement_source.dart';

const int _kb = 1024;
const int _mb = 1024 * _kb;
const int _gb = 1024 * _mb;

/// The largest member count any plan covers today (08 §2, ADR 2026-09-05g §14
/// 🔒). Above this a tenant is **told so**, never refused.
const int rkLargestMemberBand = 15;

/// How a subscription is billed. 08 §3.1 🔒 puts both on one toggle.
enum RkBillingCycle {
  /// The fallback (08 §2 principle 2).
  monthly,

  /// The default — and the one the saving is shown against.
  annual,
}

/// One tier: its limits, its two prices in paise, and whether it carries the
/// *popular* badge.
class RkTier {
  /// Creates a tier.
  const RkTier({
    required this.plan,
    required this.limits,
    required this.monthlyPaise,
    required this.annualPaise,
    required this.popular,
  });

  /// Which plan this is.
  final RkPlan plan;

  /// 08 §2's 🔒 quota row for this plan.
  final EntitlementLimits limits;

  /// Placeholder monthly price, integer paise, GST-inclusive (see the ⚠️ SPEC
  /// note at the head of this file). Zero on Free.
  final int monthlyPaise;

  /// 08 §2's annual price, integer paise, GST-inclusive. Zero on Free.
  final int annualPaise;

  /// The *popular* badge of 08 §3.1 🔒.
  ///
  /// ⚠️ SPEC — 08 §3.1 and DESIGN-PACK §11 both say the badge sits on "the
  /// recommended tier" without naming it. **Family** is taken: it is the tier
  /// the 30-day trial gives (08 §2), and 08 §1 principle 1 🔒 — *price the
  /// family, not the seat* — is the product's own recommendation. Flagged in
  /// the lane report for the owner rather than settled here.
  final bool popular;

  /// Whether this tier is bought at all.
  bool get isFree => annualPaise == 0 && monthlyPaise == 0;

  /// What twelve monthly payments cost — the figure the annual saving is
  /// measured against (08 §3.1 🔒).
  int get twelveMonthsPaise => monthlyPaise * 12;

  /// Paise saved by paying annually. Never negative in this catalogue.
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
}

/// 08 §2's table, in the order the plan screen shows it (cheapest first).
const List<RkTier> rkTiers = [
  RkTier(
    plan: RkPlan.free,
    limits: EntitlementLimits(
      members: 1,
      // "personal + 1 business book" (08 §2) — the business-book limit is 1.
      businessBooks: 1,
      devices: 5,
      envelopesPerBook: 10000,
      tenantBytes: 250 * _mb,
      attachmentBytes: 100 * _mb,
      perFileBytes: 10 * _mb,
    ),
    monthlyPaise: 0,
    annualPaise: 0,
    popular: false,
  ),
  RkTier(
    plan: RkPlan.personal,
    limits: EntitlementLimits(
      members: 1,
      // "unlimited books" (08 §2).
      businessBooks: null,
      devices: 5,
      envelopesPerBook: 100000,
      tenantBytes: 2 * _gb,
      attachmentBytes: 2 * _gb,
      perFileBytes: 10 * _mb,
    ),
    // ₹63/month placeholder → ₹756 a year against ₹599 annual (20 % saving).
    monthlyPaise: 6300,
    // 08 §2 🔒 — ₹599 a year.
    annualPaise: 59900,
    popular: false,
  ),
  RkTier(
    plan: RkPlan.family,
    limits: EntitlementLimits(
      members: 5,
      businessBooks: 3,
      devices: 8,
      envelopesPerBook: 250000,
      tenantBytes: 5 * _gb,
      attachmentBytes: 5 * _gb,
      perFileBytes: 10 * _mb,
    ),
    // ₹209/month placeholder → ₹2,508 a year against ₹1,999 annual.
    monthlyPaise: 20900,
    // 08 §2 🔒 — ₹1,999 a year.
    annualPaise: 199900,
    popular: true,
  ),
  RkTier(
    plan: RkPlan.familyPlus,
    limits: EntitlementLimits(
      members: rkLargestMemberBand,
      businessBooks: null,
      devices: 15,
      envelopesPerBook: 1000000,
      tenantBytes: 15 * _gb,
      attachmentBytes: 20 * _gb,
      perFileBytes: 10 * _mb,
    ),
    // ₹417/month placeholder → ₹5,004 a year against ₹3,999 annual.
    monthlyPaise: 41700,
    // 08 §2 🔒 — ₹3,999 a year.
    annualPaise: 399900,
    popular: false,
  ),
];

/// The catalogue row for [plan].
RkTier rkTierFor(RkPlan plan) => rkTiers.firstWhere((t) => t.plan == plan);

/// Storage shown in whole GB where it divides, otherwise whole MB — the
/// "plain words, not a spec table" of DESIGN-PACK §11 (S12.1) 🔒. Integer
/// arithmetic throughout.
({int amount, bool gigabytes}) rkStorageOf(int bytes) => bytes % _gb == 0
    ? (amount: bytes ~/ _gb, gigabytes: true)
    : (amount: bytes ~/ _mb, gigabytes: false);

/// The saving the Monthly/Annual toggle shows (08 §3.1 🔒 — the toggle *shows
/// the saving*).
///
/// The **smallest** annual saving across the paid tiers, so the one headline
/// is true of every card under it and overstates none. Integer arithmetic on
/// integer paise, like everything else in this file.
int get rkAnnualSavingPercent => rkTiers
    .where((t) => !t.isFree)
    .map((t) => t.annualSavingPercent)
    .reduce((a, b) => a < b ? a : b);

/// Where a purchase is made — 08 §3.2 🔒 as ruled by ADR 2026-09-05g §8:
/// In-App Purchase on iOS, gateway on Android and web.
///
/// It changes what S12.1 may say, not what it costs: the **single INR price
/// on every channel** is the same ruling's other half.
enum RkCheckoutChannel {
  /// iOS. Apple is merchant of record, so there is **no coupon field and no
  /// external payment link** on this platform, and a GST buyer is pointed to
  /// web checkout (ADR 2026-09-05g §8 🔒).
  inAppPurchase,

  /// Android and web: coupon and GSTIN live on this checkout (08 §3.1 🔒).
  gateway,
}
