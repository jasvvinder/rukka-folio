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
