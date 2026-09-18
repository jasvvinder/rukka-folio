// The seam S14 / S14.2 read and write through (02 §7.1 🔒, 13 §3.2 rows S14,
// S14.2). It is deliberately feature-local: `shared/ledger/local_ledger.dart`
// and `packages/data`'s structural reader belong to other lanes this round, so
// the screens depend on this interface and nothing else, and the next lane
// implements it over `LocalLedger` + `readStructuralState` without touching a
// single widget.
//
// **No parallel state.** Every derived figure here already exists in
// `core_ledger`'s `partners.dart` (`settlementCapacity`, `partnerDrift`,
// pinned by A-02-62…67). [PartnersView.fromEngine] is the one conversion
// point: it takes the engine's own result objects and only attaches names, so
// an implementation cannot quietly recompute capacity or drift in the UI
// layer. The per-owner **put in / took out / share** split (13 §3.2 row S14)
// is the one figure the engine does not yet expose — see [PartnerPosition].
import 'package:core_ledger/core_ledger.dart';

/// Who owns the book (02 §7.1 🔒 *Shared ownership is optional*).
///
/// ADR 2026-09-09b: a [justMe] business **never mentions partners, ratios or
/// profit distribution anywhere in the app**. S14 is therefore not reachable
/// for it — and, if it is reached anyway (a stale deep link, a book whose
/// ownership changed under a live route), the screen must show a state that
/// speaks none of those words rather than an empty partner list.
enum BookOwnership {
  /// One owner: Capital/Drawings pair, no partner accounts.
  justMe,

  /// Several owners: one Partner Current A/c each.
  shared,
}

/// One owner's position in the business (13 §3.2 row S14).
///
/// Amounts are **integer paise** throughout ([Paise]); no figure on this
/// surface is ever a double (CLAUDE.md rule 1).
///
/// The three components are the three distinct events of 02 §7.1 🔒, kept
/// distinct because *keeping them distinct is the whole model*:
///
/// | field      | posting                                        |
/// |------------|------------------------------------------------|
/// | [putIn]    | `Dr Expense · Cr Partner Current` — they paid a business cost from their own pocket |
/// | [tookOut]  | `Dr Partner Current · Cr business money a/c`   |
/// | [share]    | `Dr Profit Distributed · Cr Partner Current` (profit share and any `interest`-tagged line) |
///
/// 🔒 *The payer never books an expense in their own book* — [putIn] is a
/// claim on the business, never an expense of theirs. The wording on the
/// screen says so.
///
/// ⚠️ SPEC: `core_ledger/partners.dart` derives capacity and drift but has no
/// function for this three-way split, and 02 §7.1 names no account for it
/// either — the split is only specified by 13 §3.2 row S14. The implementing
/// lane must derive it from the counted lines of the Partner Current A/c
/// (by the verb that posted them), **in the engine or in `packages/data`, not
/// in a widget**, so that S14, S14.1 and any export agree. Reported in the
/// lane report rather than invented here.
final class PartnerPosition {
  /// Creates a position. [net] is the balance as *what the business owes
  /// them*: positive = the business owes them (a Cr balance), negative = they
  /// owe the business (a Dr balance — 02 §7.1 🔒 *Debit balances are real and
  /// must be shown*).
  const PartnerPosition({
    required this.accountId,
    required this.name,
    required this.putIn,
    required this.tookOut,
    required this.share,
    required this.net,
    this.other = Paise.zero,
    this.ratioWeight,
  });

  /// The Partner Current A/c id — the identity the ratio and the remainder
  /// rule both key on (02 §7.1 🔒, ADR 2026-09-13 §3).
  final String accountId;

  /// The owner's name as the account carries it.
  final String name;

  /// Business costs they paid from their own pocket.
  final Paise putIn;

  /// Money they took out of the business.
  final Paise tookOut;

  /// Profit (and interest) credited to them.
  final Paise share;

  /// What the business owes them today; negative = they owe the business.
  final Paise net;

  /// Lines 02 §7.1 does not classify — an owner's **cash** contribution
  /// (`Dr money · Cr Partner Current`) and a partner-to-partner settlement,
  /// plus any certified opening balance carried in from a closed year.
  ///
  /// ⚠️ SPEC: 02 §7.1 🔒 names three events and these are not among them, so
  /// `packages/data`'s derivation keeps them in their own bucket rather than
  /// folding them into [putIn] or [tookOut] (E-02-5, E-02-6, E-02-7). The
  /// three named figures therefore stay exactly what the spec says they are,
  /// and `putIn − tookOut + share + other` still reconciles to [net].
  final Paise other;

  /// This owner's whole-number weight from the book's `partner_shares`
  /// (02 §7.1 🔒, ADR 2026-09-13 §3) — **null means the ratio was never
  /// recorded, never that the shares are equal**. A reader that finds no map
  /// must say so rather than divide evenly, so the screen prints *not
  /// recorded* and no number.
  final int? ratioWeight;

  /// True when they owe the business (a Dr balance).
  bool get owesBusiness => net.raw < 0;
}

/// One partner more than the configured margin above the group average
/// (02 §7.1 🔒 *Drift visibility*) — the subject of the S14.2 card.
final class PartnerDriftView {
  /// Creates the view.
  const PartnerDriftView({
    required this.accountId,
    required this.name,
    required this.owed,
    required this.aboveAverage,
  });

  /// Reads a [PartnerDrift] the engine derived, attaching the owner's name.
  PartnerDriftView.fromEngine(PartnerDrift drift, String ownerName)
    : accountId = drift.accountId,
      name = ownerName,
      owed = drift.owed,
      aboveAverage = drift.aboveAverage;

  /// The Partner Current A/c.
  final String accountId;

  /// The owner's name.
  final String name;

  /// What the business owes them.
  final Paise owed;

  /// How far above the group average that is.
  final Paise aboveAverage;
}

/// A money account the *pay out* door can pay from (02 §7.1 settlement route
/// 1, `Dr Partner Current · Cr bank`).
final class SettlementSource {
  /// Creates the source.
  const SettlementSource({
    required this.accountId,
    required this.name,
    required this.balance,
  });

  /// The money A/c id.
  final String accountId;

  /// Its name.
  final String name;

  /// Its balance (positive = money there).
  final Paise balance;
}

/// Everything S14 and S14.2 draw, for one book.
final class PartnersView {
  /// Creates the view.
  const PartnersView({
    required this.ownership,
    required this.positions,
    required this.canSettleAll,
    required this.shortBy,
    required this.moneyTotal,
    required this.partnerCreditTotal,
    required this.drift,
    required this.sources,
    this.driftMargin,
    this.readOnly = false,
    this.offline = false,
  });

  /// Builds the view from the engine's own derivations — the only permitted
  /// route (02 §7.1, A-02-65/66/67). [names] maps Partner Current A/c id →
  /// owner name.
  ///
  /// [positions] still arrives from the caller because the put-in / took-out /
  /// share split has no engine function yet (see [PartnerPosition]).
  factory PartnersView.fromEngine({
    required BookOwnership ownership,
    required SettlementCapacity capacity,
    required List<PartnerDrift> drift,
    required List<PartnerPosition> positions,
    required Map<String, String> names,
    required List<SettlementSource> sources,
    Paise? driftMargin,
    bool readOnly = false,
    bool offline = false,
  }) => PartnersView(
    ownership: ownership,
    positions: positions,
    canSettleAll: capacity.canSettleAll,
    shortBy: capacity.shortBy,
    moneyTotal: capacity.moneyTotal,
    partnerCreditTotal: capacity.partnerCreditTotal,
    drift: [
      for (final d in drift)
        PartnerDriftView.fromEngine(d, names[d.accountId] ?? ''),
    ],
    sources: sources,
    driftMargin: driftMargin,
    readOnly: readOnly,
    offline: offline,
  );

  /// Which kind of book this is.
  final BookOwnership ownership;

  /// One per owner, in the book's account order.
  final List<PartnerPosition> positions;

  /// 02 §7.1 🔒 *Settlement capacity* — could the business pay everyone out
  /// today?
  final bool canSettleAll;

  /// How far short it is; zero when [canSettleAll].
  final Paise shortBy;

  /// Total across the money accounts — shown beneath the sentence, *never
  /// left for the reader to subtract* (02 §7.1 🔒).
  final Paise moneyTotal;

  /// Total the business owes its owners (credit balances only).
  final Paise partnerCreditTotal;

  /// Partners above the margin; empty when nobody is, or when no margin is
  /// configured (see [driftMargin]).
  final List<PartnerDriftView> drift;

  /// Money accounts the *pay out* door may draw on.
  final List<SettlementSource> sources;

  /// The configured drift margin.
  ///
  /// ⚠️ SPEC: 02 §7.1 🔒 says the margin is *configurable* but names neither
  /// its storage nor a default, and no `business_setting` key for it exists in
  /// 03 or the ADRs. The conservative reading is taken: **null means no margin
  /// is configured, and the S14.2 card is not shown at all** — the app never
  /// invents a threshold and so can never nag on a number nobody chose. When
  /// the setting lands, this carries it. Raised in the lane report.
  final Paise? driftMargin;

  /// Tenant read-only (dunning, S12.5 pattern; 13 §5): the figures still show,
  /// every door explains why it is closed.
  final bool readOnly;

  /// This phone is off-network (05 §9). 07 §1 rule 7: offline is normal, so
  /// the screen keeps working and says so quietly — the figures are local and
  /// complete either way.
  final bool offline;

  /// Whether the S14.2 card has anything to say.
  bool get hasDrift => driftMargin != null && drift.isNotEmpty;
}

/// What S14 / S14.2 need of the ledger. Implemented over `LocalLedger` and
/// `readStructuralState` by the lane that owns `app/lib/shared/ledger`.
abstract interface class PartnersPort {
  /// The live position of [bookId]. Errors on the stream drive the
  /// error-with-retry state (13 §4.3).
  Stream<PartnersView> watch(String bookId);

  /// Settlement route 1 (02 §7.1 🔒): the business pays a partner out —
  /// `Dr Partner Current · Cr {money account}`. [amount] is integer paise.
  Future<void> payOut({
    required String bookId,
    required String partnerAccountId,
    required String fromAccountId,
    required Paise amount,
  });

  /// Settlement route 2 (02 §7.1 🔒): partner-to-partner, settled outside the
  /// business — `Dr {over-funded partner} · Cr {under-funded partner}`. The
  /// payer has bought part of the other's claim; no money account moves.
  Future<void> settleBetweenPartners({
    required String bookId,
    required String fromPartnerAccountId,
    required String toPartnerAccountId,
    required Paise amount,
  });
}

/// Why S14.1 cannot hand anything out (02 §7.1 🔒, ADR 2026-09-05e §8), as a
/// **state the wizard shows** rather than a thrown string (13 §4.3, 07 §1
/// rule 6).
///
/// It mirrors the facade's own typed refusal one for one, deliberately: the
/// screen imports neither `LocalLedger` nor `packages/data`, so the seam
/// restates the vocabulary and the implementation maps it across. Nothing here
/// is a judgement the UI makes.
enum DistributionBlock {
  /// Not a shared business. ADR 2026-09-09b 🔒: the screen then says nothing
  /// about partners, ratios or distribution.
  notShared,

  /// A shared business whose owner accounts are not seeded yet.
  noPartners,

  /// Nowhere to record the appropriation yet.
  noProfitDistributed,

  /// `partner_shares` was never recorded. 02 §7.1 🔒 — **never** equal shares.
  ratioNotRecorded,

  /// The recorded shares do not cover every owner.
  ratioIncomplete,

  /// The business's agreed terms could not be read (ADR 2026-09-14b §5).
  termsUnverified,

  /// The year's figure is exactly zero.
  nothingToDistribute,

  /// Over the ceiling of ADR 2026-09-05e §8 —
  /// [DistributionView.excess] says by how much.
  ceiling,
}

/// One owner's two lines in the preview (02 §7.1 🔒 *The distribution preview
/// shows both lines per partner — interest and share*).
///
/// Both figures come off the engine's own entry lines. Positive = credited to
/// this owner; negative = charged to them (a debit balance's interest, or a
/// loss share).
final class DistributionOwnerView {
  /// Creates the row.
  const DistributionOwnerView({
    required this.accountId,
    required this.name,
    required this.ratioWeight,
    required this.interest,
    required this.share,
  });

  /// The owner's Partner Current A/c.
  final String accountId;

  /// Their name as the account carries it.
  final String name;

  /// Their whole-number weight in the ratio **in force** (ADR 2026-09-14b §6),
  /// never a percentage.
  final int ratioWeight;

  /// Interest on capital; zero when the setting is off, which is the default.
  final Paise interest;

  /// Their share of what is left after interest.
  final Paise share;

  /// What this one entry credits them altogether.
  Paise get total => interest + share;
}

/// Everything S14.1 draws (13 §3.2 row S14.1). Every figure was computed by
/// `core_ledger`; this carries them and adds names.
final class DistributionView {
  /// Creates the view.
  const DistributionView({
    required this.bookId,
    required this.financialYearLabel,
    required this.from,
    required this.to,
    required this.netProfit,
    required this.owners,
    required this.headroom,
    required this.excess,
    required this.interestEnabled,
    required this.quorumOfOne,
    this.block,
    this.readOnly = false,
    this.offline = false,
  });

  /// The book being distributed.
  final String bookId;

  /// The open financial year, as `2026-27` (the profit figure is the year's,
  /// whatever period the interest covers — ADR 2026-09-05e §8).
  final String financialYearLabel;

  /// First day of the interest period.
  final LocalDate from;

  /// Last day of the interest period.
  final LocalDate to;

  /// The year's figure: positive = profit, negative = a loss to share.
  final Paise netProfit;

  /// One row per owner, in Partner Current A/c creation order.
  final List<DistributionOwnerView> owners;

  /// What may still be handed out (ADR 2026-09-05e §8).
  final Paise headroom;

  /// How far over the ceiling this would be; zero when it fits.
  final Paise excess;

  /// Whether interest on capital is on for this business (off by default).
  final bool interestEnabled;

  /// True when this book records the entry itself, false when it must be
  /// proposed to the owners (02 §7.2.1 🔒 *Single-owner books … quorum of
  /// one; the concept is invisible there*).
  final bool quorumOfOne;

  /// Why nothing can be handed out, or null when it can.
  final DistributionBlock? block;

  /// Tenant read-only (S12.5 pattern; 13 §5): the figures still show, the
  /// action explains why it is closed.
  final bool readOnly;

  /// This phone is off-network (07 §1 rule 7): never blocking, always said.
  final bool offline;

  /// Total interest across the owners.
  Paise get interestTotal => Paise.sum([for (final o in owners) o.interest]);

  /// Total shared by the agreed shares after interest.
  Paise get shareTotal => Paise.sum([for (final o in owners) o.share]);

  /// The sum of the owners' weights — the denominator the screen prints.
  int get ratioTotal => owners.fold<int>(0, (sum, o) => sum + o.ratioWeight);

  /// The period is a loss (ADR 2026-09-05e §8 mirror posting).
  bool get isLoss => netProfit.isCredit;

  /// Interest is owed even though it is more than the profit (02 §7.1 🔒).
  bool get interestExceedsProfit =>
      interestTotal.raw > 0 && interestTotal.raw > netProfit.raw;

  /// Nothing stands in the way and the plan allows writing.
  bool get canDistribute => block == null && !readOnly;
}

/// What a distribution did.
enum DistributionResult {
  /// A quorum-of-one book: the one multi-line entry is posted.
  posted,

  /// A shared book: one signed request is waiting in every owner's Inbox and
  /// **nothing has been applied** (02 §7.2.1 🔒).
  proposed,
}

/// The port refused; **nothing was authored**. Carries no plaintext financial
/// data beyond the overshoot the spec requires the wizard to state
/// (02 §7.1 🔒 *the wizard refuses and says by how much*).
final class DistributionBlocked implements Exception {
  /// Creates the refusal.
  const DistributionBlocked(this.block, {this.excess = Paise.zero});

  /// Which rule refused.
  final DistributionBlock block;

  /// How far over the ceiling, for [DistributionBlock.ceiling].
  final Paise excess;

  @override
  String toString() => 'DistributionBlocked(${block.name})';
}

/// What S14.1 needs of the ledger, on top of [PartnersPort].
///
/// It is a separate interface so S14's own tests and the S14.2 sheet do not
/// have to know the wizard exists; the real port implements both.
abstract interface class DistributionPort {
  /// The preview for [bookId] — 13 §3.2 row S14.1 step 2. [from] / [to] bound
  /// the **interest** period and default to the open FY's first day and today;
  /// the profit figure is the year's either way.
  Future<DistributionView> distributionPreview(
    String bookId, {
    LocalDate? from,
    LocalDate? to,
  });

  /// Records it, or proposes it (02 §7.1 🔒, §7.2.1 🔒). Throws
  /// [DistributionBlocked] with nothing authored when a rule refuses.
  Future<DistributionResult> distribute(
    String bookId, {
    LocalDate? from,
    LocalDate? to,
  });
}
