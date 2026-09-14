// Multiple admins and the quorum rule (02 §7.2.1 🔒): the structural / routine
// split, the `structural_quorum` setting, pending-structural requests, signed
// approval counting, veto, expiry, and single-owner books.
//
// Counting follows the guardian-revocation precedent of ADR 2026-09-06 §3
// (`packages/sync_engine/lib/src/revocation.dart`): a pure function of the
// record set, recomputed every time and never cached as final, counted against
// the owner-set version each record names, one approval per author, with the
// threshold taken from the earliest version among counted records so a
// re-versioned owner set can neither reset the count nor raise the bar
// mid-request. Every device walks the same `(hlc, id)` order and lands on the
// same outcome whatever the arrival order.
//
// Purity (CLAUDE.md rule 3): no clock — the expiry window is judged against an
// injected `asOfMs`, and approvals are dated by the HLC their author signed.
// Signature verification is the sync layer's job (04 §8.3): every record
// passed in is already verified; the server-fabricated approval of 09 suite
// H2b never reaches this function.
import 'package:meta/meta.dart';

import 'events.dart';
import 'hlc.dart';
import 'local_date.dart';

/// The `structural_quorum` field of a book's settings (02 §7.2.1). The engine
/// reads and writes it on a JSON payload map so the same codec serves the
/// `book_config` and `business_setting` envelopes alike (ADR 2026-09-05e §11).
const String structuralQuorumKey = 'structural_quorum';

/// The expiry window (02 §7.2.1: "14 days without quorum → lapsed").
/// ⚠️ SPEC: 02 §7.2.1 marks the window "confirm"; taken as written.
const int structuralExpiryDays = 14;

/// [structuralExpiryDays] in the physical-millisecond scale of [Hlc.physicalMs].
const int structuralExpiryMs = structuralExpiryDays * 24 * 60 * 60 * 1000;

/// How many owners must sign for a structural action to take effect.
enum StructuralQuorum {
  /// Every current owner (the default).
  allOwners('all_owners'),

  /// More than half: ⌊n/2⌋ + 1 (ADR 2026-09-14 ruling 1 🔒). 02 §7.2.1 read
  /// ⌈n/2⌉ + 1, which equals *all owners* for n ≤ 3 and so made this quorum
  /// indistinguishable from [allOwners] in every book the app has today.
  majority('majority');

  const StructuralQuorum(this.wire);

  /// Wire value.
  final String wire;

  /// Parses a wire value; `null` when it is not one this build knows.
  static StructuralQuorum? fromWire(Object? wire) {
    for (final q in values) {
      if (q.wire == wire) return q;
    }
    return null;
  }

  /// Approvals required of [owners] owners. A single owner is a quorum of one
  /// (02 §7.2.1 *Single-owner books*).
  int requiredOf(int owners) {
    if (owners < 1) throw ArgumentError.value(owners, 'owners', 'must be ≥ 1');
    if (owners == 1) return 1;
    return switch (this) {
      allOwners => owners,
      // ⌊n/2⌋ + 1 — *more than half*, ADR 2026-09-14 ruling 1 🔒. 02 §7.2.1 read
      // ⌈n/2⌉ + 1, which equals `owners` for n ≤ 3 and so made *majority*
      // identical to *all owners* for the family sizes this product is built
      // around; the clamp that needed is gone with it.
      majority => owners ~/ 2 + 1,
    };
  }
}

/// The book's `structural_quorum`, read conservatively: an absent field is the
/// default (all owners), and a value this build cannot interpret — one a newer
/// app wrote — is *also* read as all owners, the strictest rule, while
/// [withStructuralQuorum] leaves it untouched unless the setting itself is
/// being changed (03 §3.3 rule 4 🔒).
StructuralQuorum structuralQuorumOf(Map<String, Object?> settings) =>
    StructuralQuorum.fromWire(settings[structuralQuorumKey]) ??
    StructuralQuorum.allOwners;

/// False when the field is present with a value this build cannot interpret.
bool isStructuralQuorumKnown(Map<String, Object?> settings) =>
    !settings.containsKey(structuralQuorumKey) ||
    StructuralQuorum.fromWire(settings[structuralQuorumKey]) != null;

/// A copy of [settings] with `structural_quorum` set to [quorum]. Every other
/// field — known or not — is carried over verbatim, same object, same order;
/// the input is never mutated (03 §3.3 rule 4 🔒).
Map<String, Object?> withStructuralQuorum(
  Map<String, Object?> settings,
  StructuralQuorum quorum,
) => {...settings, structuralQuorumKey: quorum.wire};

/// The structural actions of 02 §7.2.1's table 🔒 — those that need a quorum of
/// owners rather than any one admin — plus the `structural_quorum` setting,
/// which the same section makes "itself a structural action to change". The
/// set is locked: adding or dropping a value is a 🔒 change and needs an ADR.
enum StructuralAction {
  /// Change the ownership ratio (`partner_shares`, 02 §7.1).
  ownershipRatio('ownership_ratio', changesConfig: true),

  /// Distribute profit (02 §7.1) — applied as the one multi-line entry.
  profitDistribution('profit_distribution', changesConfig: false),

  /// Enable, change or disable interest on capital (02 §7.1).
  interestOnCapital('interest_on_capital', changesConfig: true),

  /// Add or remove an owner.
  ownerAddOrRemove('owner_add_or_remove', changesConfig: true),

  /// Remove a member (ADR 2026-09-05e §9).
  memberRemoval('member_removal', changesConfig: false),

  /// Re-open a **closed** year (02 §8.1) — applied as a `period_unlock`.
  yearReopen('year_reopen', changesConfig: false),

  /// Change the book's financial-year start — forbidden outright once any
  /// year has closed (ADR 2026-09-05e §9; see [checkStructuralRequest]).
  fyStartChange('fy_start_change', changesConfig: true),

  /// Delete or archive the book (ADR 2026-09-05e §9).
  bookArchiveOrDelete('book_archive_or_delete', changesConfig: false),

  /// Change `structural_quorum` itself (02 §7.2.1 *How quorum works*).
  quorumSetting('quorum_setting', changesConfig: true);

  const StructuralAction(this.wire, {required this.changesConfig});

  /// Wire value.
  final String wire;

  /// True when the action is applied by merging the request's payload into
  /// the book's settings ([applyStructural]); false when it is applied by its
  /// own posting, ceremony or membership act once quorum exists.
  final bool changesConfig;

  /// Every structural action needs a quorum — by definition.
  bool get requiresQuorum => true;

  /// Parses a wire value; `null` for anything not in the 🔒 set.
  static StructuralAction? fromWire(Object? wire) {
    for (final a in values) {
      if (a.wire == wire) return a;
    }
    return null;
  }
}

/// The phase of a `structural_approval` envelope (ADR 2026-09-05e §11: one
/// object type, a `phase` field).
enum StructuralPhase {
  /// The request itself.
  initiation,

  /// One owner's signed approval.
  approval,

  /// One owner's veto, with a reason.
  veto,

  /// The recorded lapse after the expiry window.
  lapse,
}

/// Any `structural_approval` envelope. They travel in the book's stream with
/// every other event; the projector neither sums nor quarantines them.
sealed class StructuralEvent implements LedgerEvent {
  const StructuralEvent();

  /// Phase.
  StructuralPhase get phase;

  /// The request this envelope is about (the request's own id for the
  /// initiation).
  String get requestId;
}

/// A pending-structural request (02 §7.2.1): an admin's signed statement of
/// exactly what will change. It applies nothing by itself.
@immutable
final class StructuralRequest extends StructuralEvent {
  /// Creates a request.
  const StructuralRequest({
    required this.id,
    required this.bookId,
    required this.hlc,
    required this.action,
    required this.byUser,
    required this.ownerSetVersion,
    this.payload = const {},
    this.authorDevice,
    this.authorSeq,
  });

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;
  @override
  final String? authorDevice;
  @override
  final int? authorSeq;

  /// What kind of change.
  final StructuralAction action;

  /// The initiating admin. Initiation is not an approval: a quorum is a count
  /// of signed approval envelopes, and the initiator authors one like every
  /// other owner (the exception is the single-owner book, where the
  /// initiation itself is the one approval a quorum of one needs).
  final String byUser;

  /// The owner-set version in force when the request was authored.
  final int ownerSetVersion;

  /// What will change. For an action with [StructuralAction.changesConfig] it
  /// is the settings fields to set (e.g. `{"partner_shares": {...}}`,
  /// `{"structural_quorum": "majority"}`), merged verbatim at quorum. For the
  /// others it names the subject (the FY to re-open, the member to remove).
  final Map<String, Object?> payload;

  @override
  StructuralPhase get phase => StructuralPhase.initiation;

  @override
  String get requestId => id;

  /// A copy with some fields replaced (a re-initiation is a fresh request).
  StructuralRequest copyWith({
    String? id,
    Hlc? hlc,
    int? ownerSetVersion,
    Map<String, Object?>? payload,
  }) => StructuralRequest(
    id: id ?? this.id,
    bookId: bookId,
    hlc: hlc ?? this.hlc,
    action: action,
    byUser: byUser,
    ownerSetVersion: ownerSetVersion ?? this.ownerSetVersion,
    payload: payload ?? this.payload,
    authorDevice: authorDevice,
    authorSeq: authorSeq,
  );
}

/// One owner's signed approval, authored on their own device.
@immutable
final class StructuralApproval extends StructuralEvent {
  /// Creates an approval.
  const StructuralApproval({
    required this.id,
    required this.bookId,
    required this.hlc,
    required this.requestId,
    required this.byUser,
    required this.ownerSetVersion,
    this.authorDevice,
    this.authorSeq,
  });

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;
  @override
  final String? authorDevice;
  @override
  final int? authorSeq;
  @override
  final String requestId;

  /// The approving owner.
  final String byUser;

  /// The owner-set version the approver was counting under.
  final int ownerSetVersion;

  @override
  StructuralPhase get phase => StructuralPhase.approval;
}

/// One owner's veto — closes the request immediately with a recorded reason.
@immutable
final class StructuralVeto extends StructuralEvent {
  /// Creates a veto. [reason] is required and may not be blank.
  StructuralVeto({
    required this.id,
    required this.bookId,
    required this.hlc,
    required this.requestId,
    required this.byUser,
    required this.ownerSetVersion,
    required this.reason,
    this.authorDevice,
    this.authorSeq,
  }) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'a veto records its reason');
    }
  }

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;
  @override
  final String? authorDevice;
  @override
  final int? authorSeq;
  @override
  final String requestId;

  /// The vetoing owner.
  final String byUser;

  /// The owner-set version the vetoer was an owner under.
  final int ownerSetVersion;

  /// Why — joins the admin-actions feed (02 §7.2 item 3).
  final String reason;

  @override
  StructuralPhase get phase => StructuralPhase.veto;
}

/// The recorded lapse of a request whose window passed without quorum. Any
/// member's client may log it; the request is re-initiable as a new request.
@immutable
final class StructuralLapse extends StructuralEvent {
  /// Creates a lapse record.
  const StructuralLapse({
    required this.id,
    required this.bookId,
    required this.hlc,
    required this.requestId,
    required this.byUser,
    this.authorDevice,
    this.authorSeq,
  });

  @override
  final String id;
  @override
  final String bookId;
  @override
  final Hlc hlc;
  @override
  final String? authorDevice;
  @override
  final int? authorSeq;
  @override
  final String requestId;

  /// Who logged it.
  final String byUser;

  @override
  StructuralPhase get phase => StructuralPhase.lapse;
}

/// One version of a book's owner set with the quorum rule in force at that
/// version — the analogue of `GuardianSetVersion`. A version changes only by an
/// approved structural action (add/remove owner, change the quorum setting).
@immutable
final class OwnerSetVersion {
  /// Creates a version.
  const OwnerSetVersion({
    required this.version,
    required this.ownerIds,
    required this.quorum,
  });

  /// Version number, monotone per book.
  final int version;

  /// The owners at this version — the identities that sign approvals.
  final Set<String> ownerIds;

  /// The `structural_quorum` in force at this version.
  final StructuralQuorum quorum;

  /// Approvals a request under this version needs.
  int get required => quorum.requiredOf(ownerIds.length);
}

/// Where a request stands.
enum StructuralStatus {
  /// Short of quorum, inside the window, not vetoed.
  pending,

  /// Quorum reached: the action applies at [StructuralOutcome.decidedAt].
  approved,

  /// An owner vetoed it.
  vetoed,

  /// The window passed without quorum.
  lapsed,
}

/// Why a record did not count.
enum StructuralIgnoreReason {
  /// The record names an owner-set version no reader knows.
  unknownVersion,

  /// The author was not an owner at the version the record names.
  notOwner,

  /// The same owner already approved (the earliest in order counts).
  duplicateAuthor,

  /// Authored after the expiry window closed.
  afterDeadline,

  /// Ordered after the request was already decided (approved, vetoed or
  /// lapsed) — nothing can reopen a decided request.
  afterDecision,

  /// A lapse record authored before the window had closed.
  lapseBeforeDeadline,
}

/// A record that did not count, with the reason (logged, never silent).
@immutable
final class StructuralIgnored {
  /// Creates the entry.
  const StructuralIgnored(this.recordId, this.reason);

  /// Record.
  final String recordId;

  /// Why.
  final StructuralIgnoreReason reason;
}

/// The result of evaluating one request.
@immutable
final class StructuralOutcome {
  const StructuralOutcome._({
    required this.request,
    required this.status,
    required this.approvedBy,
    required this.threshold,
    required this.decidedAt,
    required this.decidedById,
    required this.veto,
    required this.lapseRecorded,
    required this.deadlineMs,
    required this.ignored,
  });

  /// The request.
  final StructuralRequest request;

  /// Status.
  final StructuralStatus status;

  /// Owners whose approval counted, in `(hlc, id)` order.
  final List<String> approvedBy;

  /// Approvals required — of the earliest owner-set version among the
  /// request and counted records; `null` when the request names a version no
  /// reader knows (it can then never reach quorum).
  final int? threshold;

  /// The order point at which the request was decided: the k-th approval,
  /// the veto, the recorded lapse, or the request itself for a quorum of one.
  /// `null` while pending or when the lapse is derived from time alone.
  final Hlc? decidedAt;

  /// The id of the envelope at [decidedAt].
  final String? decidedById;

  /// The veto that closed it, if any.
  final StructuralVeto? veto;

  /// True when a lapse envelope was logged; false when [status] is lapsed by
  /// the injected time alone and no record exists yet.
  final bool lapseRecorded;

  /// Last physical millisecond at which an approval still counts.
  final int deadlineMs;

  /// Records that did not count.
  final List<StructuralIgnored> ignored;

  /// True only once quorum exists — the single gate on applying anything.
  bool get isApplied => status == StructuralStatus.approved;
}

/// Evaluates [request] against its [records] (every `structural_approval`
/// envelope of the book — those naming another request are skipped) and the
/// book's owner-set [owners], as of the injected physical time [asOfMs].
///
/// Deterministic on every device: records are walked in `(hlc, id)` order and
/// the walk stops at the first deciding record, so a late-arriving veto ordered
/// before the k-th approval flips an approved request to vetoed on the next
/// evaluation — the conservative direction, as ADR 2026-09-06 §3's cut-off
/// only moves earlier. [asOfMs] decides one thing only: whether a request still
/// short of quorum after its window is shown as pending or as lapsed.
StructuralOutcome evaluateStructural({
  required StructuralRequest request,
  required Iterable<StructuralEvent> records,
  required Iterable<OwnerSetVersion> owners,
  required int asOfMs,
}) {
  final byVersion = <int, OwnerSetVersion>{
    for (final v in owners) v.version: v,
  };
  final deadline = request.hlc.physicalMs + structuralExpiryMs;
  final ignored = <StructuralIgnored>[];
  final counted = <String, StructuralApproval>{}; // owner → first approval

  StructuralOutcome result({
    required StructuralStatus status,
    int? threshold,
    Hlc? decidedAt,
    String? decidedById,
    StructuralVeto? veto,
    bool lapseRecorded = false,
  }) => StructuralOutcome._(
    request: request,
    status: status,
    approvedBy: List.unmodifiable(counted.keys),
    threshold: threshold,
    decidedAt: decidedAt,
    decidedById: decidedById,
    veto: veto,
    lapseRecorded: lapseRecorded,
    deadlineMs: deadline,
    ignored: List.unmodifiable(ignored),
  );

  final atRequest = byVersion[request.ownerSetVersion];
  if (atRequest == null) {
    // No reader can say who the owners are: nothing counts, nothing applies.
    return result(status: StructuralStatus.pending);
  }
  if (atRequest.ownerIds.length <= 1) {
    // A quorum of one: the owner's own signed initiation is the approval, so
    // the request applies at its own order point and the concept is invisible.
    return result(
      status: StructuralStatus.approved,
      threshold: 1,
      decidedAt: request.hlc,
      decidedById: request.id,
    );
  }

  // Threshold from the earliest version among the request and counted records.
  var earliest = request.ownerSetVersion;
  int threshold() => byVersion[earliest]!.required;

  final sorted =
      records
          .where((r) => r.requestId == request.id && r is! StructuralRequest)
          .toList()
        ..sort((a, b) => compareEventOrder(a.hlc, a.id, b.hlc, b.id));

  for (final r in sorted) {
    switch (r) {
      case StructuralApproval():
        final set = byVersion[r.ownerSetVersion];
        if (set == null) {
          ignored.add(
            StructuralIgnored(r.id, StructuralIgnoreReason.unknownVersion),
          );
          continue;
        }
        if (!set.ownerIds.contains(r.byUser)) {
          ignored.add(StructuralIgnored(r.id, StructuralIgnoreReason.notOwner));
          continue;
        }
        if (r.hlc.physicalMs > deadline) {
          ignored.add(
            StructuralIgnored(r.id, StructuralIgnoreReason.afterDeadline),
          );
          continue;
        }
        if (counted.containsKey(r.byUser)) {
          ignored.add(
            StructuralIgnored(r.id, StructuralIgnoreReason.duplicateAuthor),
          );
          continue;
        }
        counted[r.byUser] = r;
        if (r.ownerSetVersion < earliest) earliest = r.ownerSetVersion;
        if (counted.length >= threshold()) {
          _ignoreRest(sorted, r, ignored);
          return result(
            status: StructuralStatus.approved,
            threshold: threshold(),
            decidedAt: r.hlc,
            decidedById: r.id,
          );
        }
      case StructuralVeto():
        final set = byVersion[r.ownerSetVersion];
        if (set == null) {
          ignored.add(
            StructuralIgnored(r.id, StructuralIgnoreReason.unknownVersion),
          );
          continue;
        }
        if (!set.ownerIds.contains(r.byUser)) {
          ignored.add(StructuralIgnored(r.id, StructuralIgnoreReason.notOwner));
          continue;
        }
        _ignoreRest(sorted, r, ignored);
        return result(
          status: StructuralStatus.vetoed,
          threshold: threshold(),
          decidedAt: r.hlc,
          decidedById: r.id,
          veto: r,
        );
      case StructuralLapse():
        if (r.hlc.physicalMs < deadline) {
          ignored.add(
            StructuralIgnored(r.id, StructuralIgnoreReason.lapseBeforeDeadline),
          );
          continue;
        }
        _ignoreRest(sorted, r, ignored);
        return result(
          status: StructuralStatus.lapsed,
          threshold: threshold(),
          decidedAt: r.hlc,
          decidedById: r.id,
          lapseRecorded: true,
        );
      case StructuralRequest():
        continue; // filtered above; the switch must be exhaustive
    }
  }

  if (asOfMs > deadline) {
    return result(status: StructuralStatus.lapsed, threshold: threshold());
  }
  return result(status: StructuralStatus.pending, threshold: threshold());
}

/// Marks every record ordered after [decider] as `afterDecision`.
void _ignoreRest(
  List<StructuralEvent> sorted,
  StructuralEvent decider,
  List<StructuralIgnored> ignored,
) {
  var after = false;
  for (final r in sorted) {
    if (after) {
      ignored.add(
        StructuralIgnored(r.id, StructuralIgnoreReason.afterDecision),
      );
    } else if (identical(r, decider)) {
      after = true;
    }
  }
}

/// Applies an approved, config-shaped request to the book's [settings]: the
/// request's payload keys are set, every other field is carried over verbatim
/// (03 §3.3 rule 4 🔒) and the input is never mutated. Anything not approved,
/// or whose action is not [StructuralAction.changesConfig], returns [settings]
/// itself — **nothing is applied early** (02 §7.2.1).
Map<String, Object?> applyStructural(
  Map<String, Object?> settings,
  StructuralOutcome outcome,
) {
  if (!outcome.isApplied || !outcome.request.action.changesConfig) {
    return settings;
  }
  return {...settings, ...outcome.request.payload};
}

/// Why a request may not even be initiated.
enum StructuralRefusal {
  /// Changing the FY start once any year has closed would re-boundary every
  /// certificate (ADR 2026-09-05e §9; 02 §7.2.1 table).
  fyStartAfterYearClose,
}

/// Checks whether [request] may be initiated at all, given the book's
/// [closedYears] (every FY that is or was certified — `closed` or `reopened`).
/// `null` means it may proceed to the quorum.
StructuralRefusal? checkStructuralRequest(
  StructuralRequest request, {
  required Iterable<FinancialYear> closedYears,
}) {
  if (request.action == StructuralAction.fyStartChange &&
      closedYears.isNotEmpty) {
    return StructuralRefusal.fyStartAfterYearClose;
  }
  return null;
}

/// Classifies a ledger event on the routine/structural line of 02 §7.2.1:
/// a `period_unlock` of a month inside a closed year is the structural
/// *re-open a closed year*; a lock, or an unlock inside an open year, is
/// routine (`null`). [closedYears] are the FYs that are or were certified.
StructuralAction? structuralActionOf(
  LedgerEvent event, {
  required Iterable<FinancialYear> closedYears,
}) {
  if (event is StructuralRequest) return event.action;
  if (event is PeriodUnlock) {
    final day = event.period.firstDay;
    for (final fy in closedYears) {
      if (fy.contains(day)) return StructuralAction.yearReopen;
    }
  }
  return null;
}
