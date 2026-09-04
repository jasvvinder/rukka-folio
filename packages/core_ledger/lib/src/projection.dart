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

  /// A late arrival held in the closer's tray — valid, but absent from totals
  /// until re-dated or the month is re-opened (02 §8).
  held,
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

/// Period state (02 §8).
enum PeriodStatus {
  /// Accepts entries.
  open,

  /// Locked by a signed envelope; re-openable by an admin, logged.
  locked,
}

/// The lock / unlock history of every month, answering "was P open at HLC h?".
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

/// Year state (02 §8.1).
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
    this.vectorMatchesReplay,
  });

  /// Status.
  final YearStatus status;

  /// The closing vector published by the closer.
  final BalanceVector? certifiedVector;

  /// The close envelope.
  final String? closeId;

  /// Whether this reader's own replay reproduced the published vector at the
  /// moment of close (02 §8.1: every member's device independently recomputes).
  final bool? vectorMatchesReplay;
}

/// A blocker of the Year Close ceremony (02 §8.1 preconditions).
enum CloseBlocker {
  /// A month of the FY is not locked.
  monthOpen,

  /// Suspense is not zero (02 §10).
  suspenseNonZero,

  /// A review flag is open (02 §3).
  reviewFlagOpen,

  /// An advance request is pending (02 §7) — a distinct queue from flags.
  advancePending,
}

/// One blocker with the object it points at.
final class CloseBlockerItem {
  /// Creates an item.
  const CloseBlockerItem(this.kind, this.ref);

  /// Kind.
  final CloseBlocker kind;

  /// The month, account or entry id concerned.
  final String ref;
}

/// The projected state of one book: a pure function of the ordered envelope
/// stream and the certified opening vector (03 §3.3 rule 2).
final class LedgerState {
  LedgerState._({
    required this.balances,
    required this.entries,
    required this.quarantined,
    required this.periods,
    required this.years,
    required this.lastCount,
    required this.opening,
  });

  /// Live balances.
  final BalanceVector balances;

  /// Every accepted entry by id (quarantined envelopes are not here).
  final Map<String, ProjectedEntry> entries;

  /// Refused envelopes — security events, never summed.
  final List<QuarantinedEvent> quarantined;

  /// Lock history.
  final PeriodTimeline periods;

  /// Year close states.
  final Map<FinancialYear, YearState> years;

  /// Latest cash count per account (*verified on {date}*, 02 §8.2).
  final Map<String, CashCount> lastCount;

  /// The certified opening vector this projection started from.
  final BalanceVector opening;

  /// Entries whose review flag is open — the approver's Inbox (02 §3).
  List<ProjectedEntry> get openReviewFlags => entries.values
      .where((p) => p.reviewState == ReviewState.open && p.isCounted)
      .toList();

  /// Advance requests awaiting approval — the advance queue (02 §7).
  List<ProjectedEntry> get pendingAdvances =>
      entries.values.where((p) => p.status == EffectiveStatus.pending).toList();

  /// Entries whose lines are in the balances, in `(accounting_date, hlc, id)` order.
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

/// Projects one book. Pure and deterministic: input order does not matter
/// (events are sorted by `(hlc, id)`), nothing here reads a clock, the network
/// or settings. [opening] is the certified vector a rebuild seeds from (02 §8.1,
/// 03 §3.3 rule 3). [heldInTray] are late arrivals the closer has not yet
/// re-dated (02 §8) — a client-local fact, passed in, never read.
LedgerState project(
  Iterable<LedgerEvent> events,
  Chart chart, {
  BalanceVector? opening,
  Set<String> heldInTray = const {},
}) {
  final ordered = events.toList()
    ..sort((a, b) => compareEventOrder(a.hlc, a.id, b.hlc, b.id));
  final periods = PeriodTimeline.fromEvents(ordered);
  final balances = <String, Paise>{...?opening?.nonZero};
  final entries = <String, ProjectedEntry>{};
  final quarantined = <QuarantinedEvent>[];
  final years = <FinancialYear, YearState>{};
  final lastCount = <String, CashCount>{};

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

  for (final ev in ordered) {
    if (ev.bookId != chart.bookId) {
      quarantined.add(
        QuarantinedEvent(ev.id, ev.hlc, [
          Violation(
            ViolationKind.accountNotInBook,
            'event of book ${ev.bookId} in ${chart.bookId}',
          ),
        ]),
      );
      continue;
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
        ProjectedEntry? amendTarget;
        if (ev.refs.amends case final targetId?) {
          amendTarget = entries[targetId];
          if (amendTarget == null) {
            violations.add(
              Violation(ViolationKind.amendTargetMissing, targetId),
            );
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
            violations.add(
              Violation(ViolationKind.reverseTargetMissing, targetId),
            );
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
          continue;
        }
        final EffectiveStatus status;
        if (heldInTray.contains(ev.id)) {
          status = EffectiveStatus.held;
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

      case ApprovalDecision():
        final target = entries[ev.entryId];
        if (target == null) {
          quarantined.add(
            QuarantinedEvent(ev.id, ev.hlc, [
              Violation(ViolationKind.decisionTargetMissing, ev.entryId),
            ]),
          );
          continue;
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
          continue;
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
                    ? EffectiveStatus.held
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
        break; // already in the timeline

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
                vectorMatchesReplay: st.vectorMatchesReplay,
              );
            }
          }
        }

      case YearClose():
        final replay = BalanceVector(balances);
        years[ev.financialYear] = YearState._(
          YearStatus.closed,
          certifiedVector: ev.vector,
          closeId: ev.id,
          vectorMatchesReplay: replay == ev.vector,
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
          continue;
        }
        lastCount[ev.accountId] = ev; // a count never moves money (02 §8.2)

      default:
        break;
    }
  }

  return LedgerState._(
    balances: BalanceVector(balances),
    entries: Map.unmodifiable(entries),
    quarantined: List.unmodifiable(quarantined),
    periods: periods,
    years: Map.unmodifiable(years),
    lastCount: Map.unmodifiable(lastCount),
    opening: opening ?? BalanceVector(const {}),
  );
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

/// Preconditions to close [fy] (02 §8.1): every month locked, Suspense zero,
/// no open review flag, no pending advance request. Aged advances warn only.
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
  return out;
}

// ─── reports on a state ───────────────────────────────────────────────────────

/// One trial-balance row (02 §8: the Trial Balance report under Reports).
final class TrialBalanceRow {
  /// Creates a row.
  const TrialBalanceRow(this.accountId, this.dr, this.cr);

  /// Account.
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
TrialBalance trialBalance(
  LedgerState state,
  Chart chart, {
  bool includeZero = false,
}) {
  final rows = <TrialBalanceRow>[];
  var dr = Paise.zero;
  var cr = Paise.zero;
  for (final a in chart.accounts) {
    final b = state.balances[a.id];
    if (b.isZero && !includeZero) continue;
    if (b.isDebit) {
      dr += b;
      rows.add(TrialBalanceRow(a.id, b, null));
    } else if (b.isCredit) {
      cr += -b;
      rows.add(TrialBalanceRow(a.id, null, -b));
    } else {
      rows.add(TrialBalanceRow(a.id, null, null));
    }
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
/// `(accounting_date, hlc, id)` order, running from the certified opening
/// (b/f). [from]/[to] bound the rows returned; the running balance still
/// starts from the true b/f, so the first row in range carries the balance
/// brought down as of [from].
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

/// Net profit for the projected span: income earned − expenses spent (02 §7.1,
/// computed by the app from the ledger itself — never typed).
Paise netProfit(LedgerState state, Chart chart) {
  var income = Paise.zero;
  var expense = Paise.zero;
  for (final a in chart.accounts) {
    switch (a.accountClass) {
      case AccountClass.categoryIncome:
        income += -state.balances[a.id];
      case AccountClass.categoryExpense:
        expense += state.balances[a.id];
      default:
        break;
    }
  }
  return income - expense;
}
