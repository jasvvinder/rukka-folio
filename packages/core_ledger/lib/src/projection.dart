import '../core_ledger.dart' show projectorVersion;
import 'accounts.dart';
import 'balances.dart';
import 'cash_count.dart';
import 'entry.dart';
import 'events.dart';
import 'hlc.dart';
import 'invariants.dart';
import 'local_date.dart';
import 'money.dart';

/// The state an entry is in after folding every later envelope (02 §1.3, §3, §5, §7).
enum EffectiveStatus {
  /// Counts in balances.
  posted,

  /// Advance request awaiting approval — contributes nothing (02 §7, §9).
  pending,

  /// Advance request rejected — never counted.
  rejected,

  /// Replaced by an amendment; the head of the chain counts instead (02 §5).
  superseded,

  /// Fully reversed; both it and its mirror stay in history (02 §5).
  voided,

  /// A late arrival in the closer's tray — valid, in every *live* balance, but
  /// out of the *certified* month until re-dated or the month is re-opened
  /// (02 §3, §8; ADR 2026-09-05e §3). Named `inTray` so that `held` means one
  /// thing only: a dangling reference awaiting its target (ADR 2026-09-05e §10).
  inTray,
}

/// The review flag of a posted entry (03 §3.3.5). Never affects a balance (02 §9).
enum ReviewState {
  /// Not flagged.
  none,

  /// Flagged, awaiting a different member (02 §7.2 item 1).
  open,

  /// Flag cleared.
  approved,

  /// Rejected; the mirror reversal removes its effect (02 §3).
  rejected,
}

/// An accepted entry with its projected state.
final class ProjectedEntry {
  ProjectedEntry._(
    this.entry,
    this.status,
    this.reviewState, {
    this.supersededBy,
    this.reversedBy,
    this.decidedBy,
  });

  /// The payload.
  final Entry entry;

  /// Effective status.
  final EffectiveStatus status;

  /// Review flag state.
  final ReviewState reviewState;

  /// Id of the amendment that replaced this entry.
  final String? supersededBy;

  /// Id of the reversal that voided this entry.
  final String? reversedBy;

  /// Who took the last decision.
  final String? decidedBy;

  /// True when this entry's lines are in the balances right now.
  bool get isCounted =>
      status == EffectiveStatus.posted || status == EffectiveStatus.voided;

  ProjectedEntry _with({
    EffectiveStatus? status,
    ReviewState? reviewState,
    String? supersededBy,
    String? reversedBy,
    String? decidedBy,
  }) => ProjectedEntry._(
    entry,
    status ?? this.status,
    reviewState ?? this.reviewState,
    supersededBy: supersededBy ?? this.supersededBy,
    reversedBy: reversedBy ?? this.reversedBy,
    decidedBy: decidedBy ?? this.decidedBy,
  );
}

/// An envelope every honest reader refuses (02 preamble). A security event.
final class QuarantinedEvent {
  /// Creates a record.
  const QuarantinedEvent(this.eventId, this.hlc, this.violations);

  /// The envelope.
  final String eventId;

  /// Its HLC.
  final Hlc hlc;

  /// Why.
  final List<Violation> violations;

  @override
  String toString() => 'Quarantined($eventId: ${violations.join('; ')})';
}

/// Which reference of a held envelope is dangling.
enum HeldReason {
  /// `refs.amends` points at an entry this reader has not accepted.
  amends,

  /// `refs.reverses` points at an entry this reader has not accepted.
  reverses,

  /// An approval decision on an entry this reader has not accepted.
  decision,
}

/// An envelope waiting for its target (02 §5; ADR 2026-09-05b §4): not
/// projected, not quarantined. It counts nothing until the target arrives; when
/// the target is in the set, folding is ordinary. Part of the projector's
/// output, so `project()` stays a pure function of the envelope set.
final class HeldEvent {
  const HeldEvent._(this.event, this.heldFor, this.reason);

  /// The waiting envelope.
  final LedgerEvent event;

  /// The missing target's id.
  final String heldFor;

  /// Which reference dangles.
  final HeldReason reason;

  @override
  String toString() => 'Held(${event.id} ${reason.name} $heldFor)';
}

/// A hole in one author's sequence (ADR 2026-09-05b §3): the book is waiting
/// for envelope [expectedSeq] from [authorDevice]; every later envelope of that
/// author has arrived out of order or something is being withheld. The status
/// surface says *waiting for entries from {device}'s phone*; the projection is
/// provisional and no month or year closes while a gap is open (ADR 2026-09-05e §4).
final class AuthorGap {
  const AuthorGap._(this.authorDevice, this.expectedSeq, this.sinceHlc);

  /// The author with the hole.
  final String authorDevice;

  /// The first missing `author_seq`.
  final int expectedSeq;

  /// HLC of the first envelope seen past the hole — how long the gap has been
  /// visible (the 24 h Inbox rule is applied by the caller against its clock).
  final Hlc sinceHlc;

  @override
  String toString() =>
      'AuthorGap($authorDevice expects #$expectedSeq since ${sinceHlc.raw})';
}

/// How this reader's replay relates to a certified close (02 §8 step 4, §8.1;
/// ADR 2026-09-05c §3).
enum CloseVerification {
  /// This reader reproduced the published vector.
  verified,

  /// Same projector version, different vector — a real discrepancy, flagged.
  mismatch,

  /// The certifier used a **newer** projector than this reader: *Update the app
  /// to verify this close*. Kept as unverified-by-you, never shown as a mismatch.
  readerOutdated,

  /// The certifier used an **older** projector and this reader's newer one does
  /// not reproduce the vector: the close needs re-certifying on a current app.
  certifierOutdated,
}

/// Period state (02 §8).
enum PeriodStatus {
  /// Accepts entries.
  open,

  /// Locked by a signed envelope; re-openable by an admin, logged.
  locked,
}

/// The lock / unlock history of every month, answering "was P open at HLC h?".
/// Locks and unlocks are all-time objects (ADR 2026-09-05e §5): the rule needs
/// the complete history even for archived years.
final class PeriodTimeline {
  PeriodTimeline._(this._events);

  /// Builds the timeline from lock and unlock events, in `(hlc, id)` order.
  factory PeriodTimeline.fromEvents(Iterable<LedgerEvent> events) {
    final byPeriod = <YearMonth, List<LedgerEvent>>{};
    for (final e in events) {
      switch (e) {
        case PeriodLock(:final period):
          byPeriod.putIfAbsent(period, () => []).add(e);
        case PeriodUnlock(:final period):
          byPeriod.putIfAbsent(period, () => []).add(e);
        default:
          break;
      }
    }
    for (final list in byPeriod.values) {
      list.sort((a, b) => compareEventOrder(a.hlc, a.id, b.hlc, b.id));
    }
    return PeriodTimeline._(byPeriod);
  }

  final Map<YearMonth, List<LedgerEvent>> _events;

  /// Status of [period] as seen by an envelope at [hlc]: an entry is valid only
  /// if its HLC precedes the lock's, so a lock at the same HLC already binds.
  PeriodStatus statusAt(YearMonth period, Hlc hlc) {
    var status = PeriodStatus.open;
    for (final e in _events[period] ?? const <LedgerEvent>[]) {
      if (e.hlc > hlc) break;
      status = e is PeriodLock ? PeriodStatus.locked : PeriodStatus.open;
    }
    return status;
  }

  /// Status after every known event.
  PeriodStatus currentStatus(YearMonth period) {
    final list = _events[period];
    if (list == null || list.isEmpty) return PeriodStatus.open;
    return list.last is PeriodLock ? PeriodStatus.locked : PeriodStatus.open;
  }

  /// The lock in force for [period], or `null` when open.
  PeriodLock? lockFor(YearMonth period) {
    final list = _events[period];
    if (list == null || list.isEmpty) return null;
    final last = list.last;
    return last is PeriodLock ? last : null;
  }

  /// Every month that has ever been locked, in order.
  List<YearMonth> get periods => _events.keys.toList()..sort();
}

/// Year state (02 §8.1). "Certified ✓" is badge copy, not a state (ADR 2026-09-05e §12).
enum YearStatus {
  /// Not closed.
  open,

  /// Closed; certified opening balances for the next FY exist.
  closed,

  /// Was closed, then a month inside it (or an earlier year) was re-opened;
  /// reports show an *uncertified* banner until re-closed in order.
  uncertified,
}

/// A financial year's close state.
final class YearState {
  const YearState._(
    this.status, {
    this.certifiedVector,
    this.closeId,
    this.verification,
  });

  /// Status.
  final YearStatus status;

  /// The closing vector published by the closer.
  final BalanceVector? certifiedVector;

  /// The close envelope.
  final String? closeId;

  /// How this reader's own replay relates to the published vector.
  final CloseVerification? verification;

  /// Whether this reader's own replay reproduced the published vector.
  bool? get vectorMatchesReplay =>
      verification == null ? null : verification == CloseVerification.verified;
}

/// A blocker of a month lock or the Year Close ceremony (02 §8 step 3, §8.1;
/// ADR 2026-09-05e §4).
enum CloseBlocker {
  /// A month of the FY is not locked.
  monthOpen,

  /// Suspense is not zero (02 §10).
  suspenseNonZero,

  /// A review flag is open (02 §3).
  reviewFlagOpen,

  /// An advance request is pending (02 §7) — a distinct queue from flags.
  advancePending,

  /// An author's sequence has a hole — entries are known to be missing
  /// (ADR 2026-09-05b §3). Nobody certifies a balance with entries missing.
  authorGapOpen,

  /// An envelope is held for a target that has not arrived (ADR 2026-09-05b §4).
  heldEnvelope,
}

/// One blocker with the object it points at.
final class CloseBlockerItem {
  /// Creates an item.
  const CloseBlockerItem(this.kind, this.ref);

  /// Kind.
  final CloseBlocker kind;

  /// The month, account, entry, envelope or device id concerned.
  final String ref;
}

/// The projected state of one book: a pure function of the ordered envelope
/// stream and the certified opening vector (03 §3.3 rule 2).
final class LedgerState {
  LedgerState._({
    required this.balances,
    required this.entries,
    required this.quarantined,
    required this.held,
    required this.authorGaps,
    required this.periods,
    required this.lockVerification,
    required this.years,
    required this.lastCount,
    required this.opening,
  });

  /// Live balances.
  final BalanceVector balances;

  /// Every accepted entry by id (quarantined and held envelopes are not here).
  final Map<String, ProjectedEntry> entries;

  /// Refused envelopes — security events, never summed.
  final List<QuarantinedEvent> quarantined;

  /// Envelopes waiting for a target (ADR 2026-09-05b §4), in `(hlc, id)` order.
  final List<HeldEvent> held;

  /// Open holes in author sequences (ADR 2026-09-05b §3), one per author.
  final List<AuthorGap> authorGaps;

  /// Lock history.
  final PeriodTimeline periods;

  /// This reader's verification of every month lock that published a vector,
  /// by lock envelope id (02 §8 step 4; ADR 2026-09-05c §3).
  final Map<String, CloseVerification> lockVerification;

  /// Year close states.
  final Map<FinancialYear, YearState> years;

  /// Latest cash count per account (*verified on {date}*, 02 §8.2).
  final Map<String, CashCount> lastCount;

  /// The certified opening vector this projection started from.
  final BalanceVector opening;

  /// True while envelopes are known to be missing: an author gap or a held
  /// envelope. Figures are shown, but marked provisional (05 §9).
  bool get isProvisional => authorGaps.isNotEmpty || held.isNotEmpty;

  /// Entries whose review flag is open — the approver's Inbox (02 §3).
  List<ProjectedEntry> get openReviewFlags => entries.values
      .where((p) => p.reviewState == ReviewState.open && p.isCounted)
      .toList();

  /// Advance requests awaiting approval — the advance queue (02 §7).
  List<ProjectedEntry> get pendingAdvances =>
      entries.values.where((p) => p.status == EffectiveStatus.pending).toList();

  /// Entries whose lines are in the balances, in `(accounting_date, hlc, id)`
  /// order — the locked statement order (ADR 2026-09-05e §12), identical on
  /// every device.
  List<ProjectedEntry> get counted {
    final list = entries.values.where((p) => p.isCounted).toList();
    list.sort((a, b) {
      final c = a.entry.accountingDate.compareTo(b.entry.accountingDate);
      return c != 0
          ? c
          : compareEventOrder(a.entry.hlc, a.entry.id, b.entry.hlc, b.entry.id);
    });
    return list;
  }

  /// The current head of the amend chain starting at [entryId].
  String headOf(String entryId) {
    var id = entryId;
    while (true) {
      final next = entries[id]?.supersededBy;
      if (next == null) return id;
      id = next;
    }
  }
}

/// The key under which a closing vector records one financial year's net
/// surplus (Cr, negative) or deficit (Dr, positive) — one line per certified
/// year (ADR 2026-09-05e §2). Category accounts are never carried; these lines
/// are what *Accumulated surplus* / *Corpus* sums. Sorts beside account ids in
/// [BalanceVector.canonical].
String netResultKey(FinancialYear fy) => 'net_result:${fy.label}';

/// True for a [netResultKey].
bool isNetResultKey(String key) => key.startsWith('net_result:');

/// Projects one book. Pure and deterministic: input order does not matter
/// (events are sorted by `(hlc, id)`), nothing here reads a clock, the network
/// or settings. [opening] is the certified vector a rebuild seeds from (02 §8.1,
/// 03 §3.3 rule 3). [heldInTray] are late arrivals the closer has not yet
/// re-dated (02 §8) — a client-local fact, passed in, never read.
///
/// An amendment, reversal or decision whose target is not in the set is
/// **held** (ADR 2026-09-05b §4), whatever its HLC: the set is scanned as a
/// whole, so an orphan that arrives before its original counts exactly once
/// either way. A held envelope is quarantined `target_missing` only when the
/// target can be proven never to have existed — every envelope in the set
/// carries an `author_seq` and no author has a gap.
LedgerState project(
  Iterable<LedgerEvent> events,
  Chart chart, {
  BalanceVector? opening,
  Set<String> heldInTray = const {},
}) {
  final ordered = events.toList()
    ..sort((a, b) => compareEventOrder(a.hlc, a.id, b.hlc, b.id));
  final quarantined = <QuarantinedEvent>[];

  // ── author sequences: duplicates refused, gaps reported (ADR 2026-09-05b §3) ──
  final seqOwner = <String, Set<int>>{}; // device → seqs seen
  final accepted = <LedgerEvent>[];
  var everyEventSequenced = true;
  for (final ev in ordered) {
    final dev = ev.authorDevice;
    final seq = ev.authorSeq;
    if (dev == null || seq == null) {
      everyEventSequenced = false;
      accepted.add(ev);
      continue;
    }
    final seen = seqOwner.putIfAbsent(dev, () => {});
    if (!seen.add(seq)) {
      quarantined.add(
        QuarantinedEvent(ev.id, ev.hlc, [
          Violation(
            ViolationKind.authorSeqDuplicate,
            '$dev already used author_seq $seq',
          ),
        ]),
      );
      continue;
    }
    accepted.add(ev);
  }
  final authorGaps = <AuthorGap>[];
  for (final MapEntry(key: dev, value: seqs) in seqOwner.entries) {
    final sorted = seqs.toList()..sort();
    var expected = 1;
    for (final s in sorted) {
      if (s == expected) {
        expected++;
        continue;
      }
      // First hole: since the earliest envelope (in projection order) past it.
      final since = accepted
          .where((e) => e.authorDevice == dev && (e.authorSeq ?? 0) > expected)
          .first
          .hlc;
      authorGaps.add(AuthorGap._(dev, expected, since));
      break;
    }
  }
  authorGaps.sort((a, b) => a.authorDevice.compareTo(b.authorDevice));
  final provenComplete = everyEventSequenced && authorGaps.isEmpty;

  final periods = PeriodTimeline.fromEvents(accepted);
  final balances = <String, Paise>{...?opening?.nonZero};
  final entries = <String, ProjectedEntry>{};
  final years = <FinancialYear, YearState>{};
  final lastCount = <String, CashCount>{};
  final lockVerification = <String, CloseVerification>{};
  final openingVector = opening ?? BalanceVector(const {});
  // target id → envelopes waiting for it, in projection order
  final waiting = <String, List<(LedgerEvent, HeldReason)>>{};

  void apply(Entry e, {required bool add}) {
    for (final l in e.lines) {
      balances[l.accountId] =
          (balances[l.accountId] ?? Paise.zero) + (add ? l.amount : -l.amount);
    }
  }

  bool sameLinesMirrored(List<Line> a, List<Line> b) {
    if (a.length != b.length) return false;
    final want = [for (final l in a) '${l.accountId}\t${-l.amount.raw}']
      ..sort();
    final got = [for (final l in b) '${l.accountId}\t${l.amount.raw}']..sort();
    for (var i = 0; i < want.length; i++) {
      if (want[i] != got[i]) return false;
    }
    return true;
  }

  void defer(LedgerEvent ev, String target, HeldReason reason) =>
      waiting.putIfAbsent(target, () => []).add((ev, reason));

  late void Function(LedgerEvent ev) process;

  /// Once [id] is accepted, everything that was waiting for it folds in order.
  void release(String id) {
    final list = waiting.remove(id);
    if (list == null) return;
    for (final (ev, _) in list) {
      process(ev);
    }
  }

  process = (LedgerEvent ev) {
    if (ev.bookId != chart.bookId) {
      quarantined.add(
        QuarantinedEvent(ev.id, ev.hlc, [
          Violation(
            ViolationKind.accountNotInBook,
            'event of book ${ev.bookId} in ${chart.bookId}',
          ),
        ]),
      );
      return;
    }
    switch (ev) {
      case Entry():
        final violations = checkUniversalInvariants(ev, chart);
        if (periods.statusAt(ev.accountingDate.yearMonth, ev.hlc) ==
            PeriodStatus.locked) {
          violations.add(
            Violation(
              ViolationKind.periodLocked,
              '${ev.accountingDate.yearMonth} was locked before hlc ${ev.hlc.raw}',
            ),
          );
        }
        // Dangling targets: held (ADR 2026-09-05b §4), unless the envelope is
        // broken on its own terms — then it is refused outright.
        if (ev.refs.amends case final t? when !entries.containsKey(t)) {
          if (violations.isEmpty) {
            defer(ev, t, HeldReason.amends);
            return;
          }
        }
        if (ev.refs.reverses case final t? when !entries.containsKey(t)) {
          if (violations.isEmpty) {
            defer(ev, t, HeldReason.reverses);
            return;
          }
        }
        ProjectedEntry? amendTarget;
        if (ev.refs.amends case final targetId?) {
          amendTarget = entries[targetId];
          if (amendTarget == null) {
            violations.add(Violation(ViolationKind.targetMissing, targetId));
          } else if (amendTarget.reversedBy != null) {
            violations.add(
              Violation(ViolationKind.alreadyReversed, '$targetId is void'),
            );
          } else if (amendTarget.supersededBy != null) {
            violations.add(
              Violation(
                ViolationKind.amendNotHead,
                '$targetId was already amended by ${amendTarget.supersededBy}',
              ),
            );
          } else if (amendTarget.entry.kind != ev.kind) {
            violations.add(
              Violation(
                ViolationKind.amendKindChanged,
                '${amendTarget.entry.kind.wire} → ${ev.kind.wire}',
              ),
            );
          } else if (periods.statusAt(
                    amendTarget.entry.accountingDate.yearMonth,
                    ev.hlc,
                  ) ==
                  PeriodStatus.locked &&
              !_isRedate(amendTarget.entry, ev, periods)) {
            violations.add(
              Violation(
                ViolationKind.amendInLockedPeriod,
                '${amendTarget.entry.accountingDate.yearMonth} is locked; reverse instead',
              ),
            );
          }
        }
        ProjectedEntry? reverseTarget;
        if (ev.refs.reverses case final targetId?) {
          reverseTarget = entries[targetId];
          if (reverseTarget == null) {
            violations.add(Violation(ViolationKind.targetMissing, targetId));
          } else if (reverseTarget.reversedBy != null) {
            violations.add(
              Violation(
                ViolationKind.alreadyReversed,
                '$targetId already reversed by ${reverseTarget.reversedBy}',
              ),
            );
          } else if (reverseTarget.status != EffectiveStatus.posted) {
            violations.add(
              Violation(
                ViolationKind.reverseTargetNotPosted,
                '$targetId is ${reverseTarget.status.name}',
              ),
            );
          } else if (!sameLinesMirrored(reverseTarget.entry.lines, ev.lines)) {
            violations.add(
              Violation(
                ViolationKind.reversalNotMirror,
                'lines do not mirror $targetId',
              ),
            );
          }
        }
        if (violations.isNotEmpty) {
          quarantined.add(QuarantinedEvent(ev.id, ev.hlc, violations));
          return;
        }
        final EffectiveStatus status;
        if (heldInTray.contains(ev.id)) {
          status = EffectiveStatus.inTray;
        } else if (ev.status == EntryStatus.pending) {
          status = EffectiveStatus.pending;
        } else {
          status = EffectiveStatus.posted;
          apply(ev, add: true);
        }
        entries[ev.id] = ProjectedEntry._(
          ev,
          status,
          ev.reviewRequired ? ReviewState.open : ReviewState.none,
        );
        if (amendTarget != null) {
          if (amendTarget.isCounted) apply(amendTarget.entry, add: false);
          entries[amendTarget.entry.id] = amendTarget._with(
            status: EffectiveStatus.superseded,
            supersededBy: ev.id,
          );
        }
        if (reverseTarget != null) {
          entries[reverseTarget.entry.id] = reverseTarget._with(
            status: EffectiveStatus.voided,
            reversedBy: ev.id,
          );
        }
        release(ev.id);

      case ApprovalDecision():
        final target = entries[ev.entryId];
        if (target == null) {
          defer(ev, ev.entryId, HeldReason.decision);
          return;
        }
        if (ev.byUser == target.entry.createdByUser) {
          quarantined.add(
            QuarantinedEvent(ev.id, ev.hlc, [
              Violation(
                ViolationKind.selfApproval,
                '${ev.byUser} decided on their own entry ${ev.entryId}',
              ),
            ]),
          );
          return;
        }
        if (target.entry.status == EntryStatus.pending) {
          // The advance queue: approval itself moves the money (02 §7).
          final shouldCount =
              ev.decision == Decision.approve &&
              !heldInTray.contains(target.entry.id);
          if (shouldCount && !target.isCounted) apply(target.entry, add: true);
          if (!shouldCount && target.isCounted) apply(target.entry, add: false);
          final newStatus = ev.decision == Decision.approve
              ? (heldInTray.contains(target.entry.id)
                    ? EffectiveStatus.inTray
                    : EffectiveStatus.posted)
              : EffectiveStatus.rejected;
          entries[ev.entryId] = target._with(
            status: newStatus,
            decidedBy: ev.byUser,
          );
        } else {
          // The review queue: the flag changes, the balance never does (02 §9).
          entries[ev.entryId] = target._with(
            reviewState: ev.decision == Decision.approve
                ? ReviewState.approved
                : ReviewState.rejected,
            decidedBy: ev.byUser,
          );
        }

      case PeriodLock():
        // Already in the timeline. Re-verify the published vector (02 §8 step 4).
        if (ev.vectorCanonical case final published?) {
          lockVerification[ev.id] = _verify(
            ev.projectorVersion,
            matches: BalanceVector(balances).canonical() == published,
          );
        }

      case PeriodUnlock():
        // Re-opening a month of a closed year voids that certificate and every later one (02 §8.1).
        final affected = years.keys
            .where((fy) => fy.months.contains(ev.period))
            .toList();
        for (final fy in affected) {
          for (final MapEntry(key: y, value: st) in years.entries.toList()) {
            if (st.status == YearStatus.closed &&
                (y == fy || y.firstDay.isAfter(fy.firstDay))) {
              years[y] = YearState._(
                YearStatus.uncertified,
                certifiedVector: st.certifiedVector,
                closeId: st.closeId,
                verification: st.verification,
              );
            }
          }
        }

      case YearClose():
        final replay = _closingVector(
          entries.values.where((p) => p.isCounted),
          openingVector,
          chart,
          ev.financialYear,
        );
        years[ev.financialYear] = YearState._(
          YearStatus.closed,
          certifiedVector: ev.vector,
          closeId: ev.id,
          verification: _verify(
            ev.projectorVersion,
            matches: replay == ev.vector,
          ),
        );

      case CashCount():
        final account = chart.maybeAccount(ev.accountId);
        if (account == null || !account.isMoney) {
          quarantined.add(
            QuarantinedEvent(ev.id, ev.hlc, [
              Violation(
                ViolationKind.unknownAccount,
                '${ev.accountId} is not a money account',
              ),
            ]),
          );
          return;
        }
        lastCount[ev.accountId] = ev; // a count never moves money (02 §8.2)

      default:
        break;
    }
  };

  for (final ev in accepted) {
    process(ev);
  }

  // Whatever is still waiting is held — or, when the set is provably complete,
  // its target never existed (ADR 2026-09-05b §4).
  final held = <HeldEvent>[];
  for (final MapEntry(key: target, value: list) in waiting.entries) {
    for (final (ev, reason) in list) {
      if (provenComplete) {
        quarantined.add(
          QuarantinedEvent(ev.id, ev.hlc, [
            Violation(
              ViolationKind.targetMissing,
              '${reason.name} $target: every author sequence is contiguous and it never arrived',
            ),
          ]),
        );
      } else {
        held.add(HeldEvent._(ev, target, reason));
      }
    }
  }
  held.sort(
    (a, b) =>
        compareEventOrder(a.event.hlc, a.event.id, b.event.hlc, b.event.id),
  );
  quarantined.sort(
    (a, b) => compareEventOrder(a.hlc, a.eventId, b.hlc, b.eventId),
  );

  return LedgerState._(
    balances: BalanceVector(balances),
    entries: Map.unmodifiable(entries),
    quarantined: List.unmodifiable(quarantined),
    held: List.unmodifiable(held),
    authorGaps: List.unmodifiable(authorGaps),
    periods: periods,
    lockVerification: Map.unmodifiable(lockVerification),
    years: Map.unmodifiable(years),
    lastCount: Map.unmodifiable(lastCount),
    opening: openingVector,
  );
}

/// The reader's verdict on a published vector, given the projector version that
/// produced it (ADR 2026-09-05c §3). A missing version (pre-M2 envelope) is
/// verified as if current.
CloseVerification _verify(int? recorded, {required bool matches}) {
  if (matches) return CloseVerification.verified;
  if (recorded == null || recorded == projectorVersion) {
    return CloseVerification.mismatch;
  }
  return recorded > projectorVersion
      ? CloseVerification.readerOutdated
      : CloseVerification.certifierOutdated;
}

/// The one amendment 02 §5 allows against a locked period: the closer *re-dating*
/// a late arrival into the open period (02 §8, "default, one tap"). Accepted iff
/// the lines are identical and only the accounting date moves, into a period
/// that is open at the amendment's HLC. Anything else must go through reversal.
/// ⚠️ SPEC: whether the original actually sat in the tray is a client-local fact
/// the projector cannot see; this shape rule is the narrowest reading that lets
/// the tray work. A re-date of an entry that *was* counted in the closed month
/// shows up as a vector mismatch on re-verification, exactly like any other
/// change to closed figures.
bool _isRedate(Entry original, Entry amendment, PeriodTimeline periods) {
  if (original.accountingDate == amendment.accountingDate) return false;
  if (periods.statusAt(amendment.accountingDate.yearMonth, amendment.hlc) ==
      PeriodStatus.locked) {
    return false;
  }
  if (original.lines.length != amendment.lines.length) return false;
  final a = [for (final l in original.lines) '${l.accountId}\t${l.amount.raw}']
    ..sort();
  final b = [for (final l in amendment.lines) '${l.accountId}\t${l.amount.raw}']
    ..sort();
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether a valid entry is a *late arrival* (02 §8): created (HLC) before the
/// lock of its period but synced after it. Arrival order is a client-local fact
/// the projector cannot see, so the caller supplies it.
bool isLateArrival(
  Entry entry,
  PeriodLock lock, {
  required bool arrivedAfterLock,
}) =>
    arrivedAfterLock &&
    lock.period.contains(entry.accountingDate) &&
    entry.hlc < lock.hlc;

// ─── the certified vector (02 §8.1; ADR 2026-09-05e §2) ───────────────────────

const _balanceSheetClasses = {
  AccountClass.money,
  AccountClass.party,
  AccountClass.advance,
  AccountClass.partner,
  AccountClass.equitySystem,
};

BalanceVector _closingVector(
  Iterable<ProjectedEntry> counted,
  BalanceVector opening,
  Chart chart,
  FinancialYear fy,
) {
  final v = <String, Paise>{...opening.nonZero};
  for (final p in counted) {
    final date = p.entry.accountingDate;
    if (date.isAfter(fy.lastDay)) continue;
    for (final l in p.entry.lines) {
      final cls = chart.account(l.accountId).accountClass;
      final key = _balanceSheetClasses.contains(cls)
          ? l.accountId
          : netResultKey(FinancialYear.of(date, startMonth: fy.startMonth));
      v[key] = (v[key] ?? Paise.zero) + l.amount;
    }
  }
  return BalanceVector(v);
}

/// The closing balance vector of [fy] as every device must compute it (02 §8.1;
/// ADR 2026-09-05e §2): every **money, party, advance, partner and
/// equity_system** account, restricted to counted entries whose
/// `accounting_date` ≤ the FY's last day **regardless of HLC** — an entry dated
/// 3 April posted before a 5 April close belongs to the new year. Category
/// accounts are not carried; each year's net result is one [netResultKey] line,
/// so the vector still balances and *Accumulated surplus* / *Corpus* is a
/// computed sum, never a stored account. Lines in [state.opening] carry through
/// unchanged (they are earlier years' certified figures).
BalanceVector closingVector(LedgerState state, Chart chart, FinancialYear fy) =>
    _closingVector(state.counted, state.opening, chart, fy);

/// Preconditions to close [fy] (02 §8.1; ADR 2026-09-05e §4): every month
/// locked, Suspense zero, no open review flag, no pending advance request, no
/// author-sequence gap, no held envelope. Aged advances warn only.
List<CloseBlockerItem> yearClosePreconditions(
  LedgerState state,
  Chart chart,
  FinancialYear fy,
) {
  final out = <CloseBlockerItem>[];
  for (final m in fy.months) {
    if (state.periods.currentStatus(m) != PeriodStatus.locked) {
      out.add(CloseBlockerItem(CloseBlocker.monthOpen, m.toString()));
    }
  }
  for (final a in chart.accounts) {
    if (a.systemRole == SystemRole.suspense && !state.balances[a.id].isZero) {
      out.add(CloseBlockerItem(CloseBlocker.suspenseNonZero, a.id));
    }
  }
  for (final p in state.openReviewFlags) {
    out.add(CloseBlockerItem(CloseBlocker.reviewFlagOpen, p.entry.id));
  }
  for (final p in state.pendingAdvances) {
    out.add(CloseBlockerItem(CloseBlocker.advancePending, p.entry.id));
  }
  out.addAll(_syncBlockers(state));
  return out;
}

/// Preconditions to lock [month] (02 §8 step 3; ADR 2026-09-05b §3–4, ADR
/// 2026-09-05e §4): no open review flag, no author-sequence gap, no held
/// envelope. Suspense lines join at M10 (import). The closer's wizard refuses
/// on any item; the projector itself still records a lock it receives — a lock
/// is a signed all-time object every reader must agree on (ADR 2026-09-05e §5),
/// and the figures it certifies are re-verified through [LedgerState.lockVerification].
/// ⚠️ SPEC: 02 §8 step 3 says the lock "is refused"; refusing at authoring time
/// rather than at projection is the reading under which two honest readers with
/// different envelope sets cannot disagree about whether a month is locked.
List<CloseBlockerItem> monthLockPreconditions(
  LedgerState state,
  YearMonth month,
) {
  final out = <CloseBlockerItem>[];
  for (final p in state.openReviewFlags) {
    out.add(CloseBlockerItem(CloseBlocker.reviewFlagOpen, p.entry.id));
  }
  out.addAll(_syncBlockers(state));
  return out;
}

List<CloseBlockerItem> _syncBlockers(LedgerState state) => [
  for (final g in state.authorGaps)
    CloseBlockerItem(CloseBlocker.authorGapOpen, g.authorDevice),
  for (final h in state.held)
    CloseBlockerItem(CloseBlocker.heldEnvelope, h.event.id),
];

// ─── reports on a state ───────────────────────────────────────────────────────

/// One trial-balance row (02 §8: the Trial Balance report under Reports).
final class TrialBalanceRow {
  /// Creates a row.
  const TrialBalanceRow(this.accountId, this.dr, this.cr);

  /// Account — or a [netResultKey] for a certified year's result, presented as
  /// *Accumulated surplus* / *Corpus* (ADR 2026-09-05e §2).
  final String accountId;

  /// Debit column, or `null`.
  final Paise? dr;

  /// Credit column (positive magnitude), or `null`.
  final Paise? cr;
}

/// A trial balance: rows in chart order, both totals.
final class TrialBalance {
  /// Creates a trial balance.
  const TrialBalance(this.rows, this.totalDr, this.totalCr);

  /// Rows.
  final List<TrialBalanceRow> rows;

  /// Debit total.
  final Paise totalDr;

  /// Credit total.
  final Paise totalCr;

  /// Both columns agree.
  bool get isBalanced => totalDr == totalCr;
}

/// The trial balance of [state]; zero balances omitted unless [includeZero].
/// Certified net-result lines carried in from the opening vector follow the
/// chart's accounts, so a state seeded from a year close still balances.
TrialBalance trialBalance(
  LedgerState state,
  Chart chart, {
  bool includeZero = false,
}) {
  final rows = <TrialBalanceRow>[];
  var dr = Paise.zero;
  var cr = Paise.zero;
  void row(String id, Paise b) {
    if (b.isZero && !includeZero) return;
    if (b.isDebit) {
      dr += b;
      rows.add(TrialBalanceRow(id, b, null));
    } else if (b.isCredit) {
      cr += -b;
      rows.add(TrialBalanceRow(id, null, -b));
    } else {
      rows.add(TrialBalanceRow(id, null, null));
    }
  }

  for (final a in chart.accounts) {
    row(a.id, state.balances[a.id]);
  }
  final results = state.balances.nonZero.keys.where(isNetResultKey).toList()
    ..sort();
  for (final k in results) {
    row(k, state.balances[k]);
  }
  return TrialBalance(rows, dr, cr);
}

/// One row of an account statement: the traditional three-column layout with a
/// running balance and its side on every row (01 §1.9, reference standards §2).
final class StatementRow {
  /// Creates a row.
  const StatementRow({
    required this.date,
    required this.entryId,
    required this.dr,
    required this.cr,
    required this.running,
    this.tag,
  });

  /// Accounting date.
  final LocalDate date;

  /// The entry.
  final String entryId;

  /// Debit column, or `null`.
  final Paise? dr;

  /// Credit column (positive magnitude), or `null`.
  final Paise? cr;

  /// Running balance, signed.
  final Paise running;

  /// Line tag, if any.
  final String? tag;

  /// Side of the running balance; `null` at zero.
  Side? get side => running.side;
}

/// The statement of [accountId]: one row per counted line, in
/// `(accounting_date, hlc, id)` order (ADR 2026-09-05e §12 — locked, identical
/// on every device), running from the certified opening (b/f). [from]/[to]
/// bound the rows returned; the running balance still starts from the true b/f,
/// so the first row in range carries the balance brought down as of [from].
List<StatementRow> statement(
  LedgerState state,
  String accountId, {
  LocalDate? from,
  LocalDate? to,
}) {
  var running = state.opening[accountId];
  final rows = <StatementRow>[];
  for (final p in state.counted) {
    for (final l in p.entry.lines) {
      if (l.accountId != accountId) continue;
      running += l.amount;
      final date = p.entry.accountingDate;
      if (from != null && date.isBefore(from)) continue;
      if (to != null && date.isAfter(to)) continue;
      rows.add(
        StatementRow(
          date: date,
          entryId: p.entry.id,
          dr: l.amount.isDebit ? l.amount : null,
          cr: l.amount.isCredit ? -l.amount : null,
          running: running,
          tag: l.tag,
        ),
      );
    }
  }
  return rows;
}

/// Net profit for [fy] (02 §7.1; ADR 2026-09-05e §8): that year's income earned
/// − expenses spent − distributions already posted in the year, from counted
/// entries **dated** in the FY — computed by the app from the ledger itself,
/// never typed. Income and expense open every FY at zero (ADR §2).
Paise netProfit(LedgerState state, Chart chart, FinancialYear fy) {
  final (:income, :expense, :distributions) = _fyFigures(state, chart, fy);
  return income - expense - distributions;
}

({Paise income, Paise expense, Paise distributions}) _fyFigures(
  LedgerState state,
  Chart chart,
  FinancialYear fy,
) {
  var income = Paise.zero;
  var expense = Paise.zero;
  var distributions = Paise.zero;
  for (final p in state.counted) {
    if (!fy.contains(p.entry.accountingDate)) continue;
    for (final l in p.entry.lines) {
      final a = chart.account(l.accountId);
      switch (a.accountClass) {
        case AccountClass.categoryIncome:
          income += -l.amount;
        case AccountClass.categoryExpense:
          expense += l.amount;
        case AccountClass.equitySystem:
          if (a.systemRole == SystemRole.profitDistributed &&
              l.amount.isDebit) {
            distributions += l.amount;
          }
        default:
          break;
      }
    }
  }
  return (income: income, expense: expense, distributions: distributions);
}

/// *Accumulated surplus* (business / family) or *Corpus* (trust) — a computed
/// line, never a stored account (ADR 2026-09-05e §2): Σ certified net results
/// + opening equity − distributions. Certified results are the [netResultKey]
/// lines the state was seeded with plus, in a full replay, the category lines of
/// every counted entry dated before [openFy]; opening equity is the Opening
/// Balance account; distributions are every debit to Profit Distributed.
/// ⚠️ SPEC: Adjustments and Suspense are equity_system accounts too; the ADR's
/// formula does not name them, so they are left out here and stay visible as
/// their own lines.
Paise accumulatedSurplus(
  LedgerState state,
  Chart chart, {
  required FinancialYear openFy,
}) {
  var surplus = Paise.zero;
  for (final MapEntry(key: k, value: v) in state.balances.nonZero.entries) {
    if (isNetResultKey(k)) surplus += -v;
  }
  for (final p in state.counted) {
    if (!p.entry.accountingDate.isBefore(openFy.firstDay)) continue;
    for (final l in p.entry.lines) {
      switch (chart.account(l.accountId).accountClass) {
        case AccountClass.categoryIncome || AccountClass.categoryExpense:
          surplus += -l.amount;
        default:
          break;
      }
    }
  }
  for (final a in chart.accounts) {
    if (a.accountClass != AccountClass.equitySystem) continue;
    if (a.systemRole == SystemRole.openingBalance) {
      surplus += -state.balances[a.id];
    } else if (a.systemRole == SystemRole.profitDistributed) {
      final b = state.balances[a.id];
      if (b.isDebit) surplus -= b;
    }
  }
  return surplus;
}

/// The distribution ceiling (ADR 2026-09-05e §8): cumulative distributions may
/// not exceed accumulated surplus. [headroom] is what may still be distributed
/// today — certified surplus plus the open year's result so far, net of every
/// distribution already posted; [excess] is how far [proposed] overshoots it
/// (zero when it fits), so the wizard can refuse and say by how much.
({Paise headroom, Paise excess}) distributionHeadroom(
  LedgerState state,
  Chart chart, {
  required FinancialYear fy,
  required Paise proposed,
}) {
  final (:income, :expense, distributions: _) = _fyFigures(state, chart, fy);
  final headroom =
      accumulatedSurplus(state, chart, openFy: fy) + income - expense;
  final excess = proposed > headroom ? proposed - headroom : Paise.zero;
  return (headroom: headroom, excess: excess);
}

/// `cash` accounts whose balance has gone negative (ADR 2026-09-05e §12): legal
/// by placement-by-sign, but physical cash below zero is always a missing entry,
/// so the account shows a warning. Collection boxes and bank subtypes do not.
List<String> negativeCashWarnings(LedgerState state, Chart chart) => [
  for (final a in chart.accounts)
    if (a.subtype == MoneySubtype.cash && state.balances[a.id].isCredit) a.id,
];
