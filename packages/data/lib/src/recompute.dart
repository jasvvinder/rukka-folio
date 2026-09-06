// Recompute (03 §3.3 rule 3; ADR 2026-09-05c §3, §6): drop every projection
// row of a book and rebuild it from the mirror through `core_ledger.project()`.
// This file is the ONE place the data layer touches the projector's API. `held`,
// `authorGaps`, `lockVerification` and `YearState.verification` are projector
// output (ADR 2026-09-05b §3–4, 05c §3); this layer only mirrors them into rows.
import 'dart:convert';

import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart';

import 'database.dart';
import 'mirror.dart';
import 'payload_codec.dart';

/// What Recompute found and did for one book.
final class BookRecompute {
  /// Creates the report.
  const BookRecompute({
    required this.bookId,
    required this.eventsApplied,
    required this.held,
    required this.quarantined,
    required this.unverified,
    required this.corrupt,
    required this.authorGaps,
    required this.seededFromVector,
    required this.integrityOk,
  });

  /// Book.
  final String bookId;

  /// Events handed to the projector.
  final int eventsApplied;

  /// Envelopes held for a missing target (ADR 05b §4).
  final List<String> held;

  /// Envelopes the projector or the payload boundary refused.
  final List<String> quarantined;

  /// Envelopes whose signature chain is not yet verified.
  final int unverified;

  /// Envelopes whose blob failed its hash — re-bootstrap (ADR 05c §6).
  final List<String> corrupt;

  /// Open author gaps (ADR 05b §3): mirror-derived (every object type) plus
  /// those the projector saw among its own events.
  final int authorGaps;

  /// True when the rebuild seeded from a certified vector (03 §3.3 rule 3).
  final bool seededFromVector;

  /// `books_p.integrity_ok` as written.
  final bool integrityOk;

  /// `books_p.needs_rebootstrap` as written.
  bool get needsRebootstrap => corrupt.isNotEmpty;
}

/// A `balances` row that disagrees with `entry_lines_p`.
final class BalanceMismatch {
  /// Creates the mismatch.
  const BalanceMismatch(this.accountId, this.stored, this.recomputed);

  /// Account.
  final String accountId;

  /// What `balances` holds (null = row missing).
  final int? stored;

  /// What the lines say.
  final int recomputed;

  @override
  String toString() => '$accountId: balances=$stored lines=$recomputed';
}

/// Rebuilds Layer 2 from Layer 1.
final class Recompute {
  /// Creates the rebuilder. [opener] decrypts payloads (`core_crypto`, M3).
  Recompute(this.db, {required this.mirror, required this.opener});

  /// The database.
  final LedgerDatabase db;

  /// The mirror facade (hash verification).
  final Mirror mirror;

  /// Payload opener.
  final PayloadOpener opener;

  /// Rebuilds every book, or just [bookId]. Each book is one transaction:
  /// projection rows dropped and rewritten atomically, so a reader never sees a
  /// half-built book (03 §5 fail-closed spirit).
  Future<List<BookRecompute>> run({String? bookId}) async {
    final books = bookId == null ? await mirror.bookIds() : [bookId];
    final out = <BookRecompute>[];
    for (final b in books) {
      out.add(await db.transaction(() => _rebuildBook(b)));
    }
    return out;
  }

  Future<BookRecompute> _rebuildBook(String bookId) async {
    final rows = await mirror.envelopesOf(bookId);
    final gaps = await mirror.recomputeAuthorGaps(bookId);
    // (gaps is List<SeqGap>)

    // 1. Open every usable payload; note corruption, quarantine failures.
    final corrupt = <String>[];
    final quarantined = <String>[];
    var unverified = 0;
    final opened = <(EnvelopesLocalData, Map<String, Object?>)>[];
    for (final r in rows) {
      if (r.quarantined == 1) {
        quarantined.add(r.envelopeId);
        continue;
      }
      if (r.verified != 1) {
        unverified++;
        continue;
      }
      final read = mirror.readBlobOfRow(r);
      if (read is! BlobOk) {
        corrupt.add(r.envelopeId);
        continue;
      }
      try {
        opened.add((
          r,
          opener.open(
            read.bytes,
            objectType: r.objectType,
            keyVersion: r.keyVersion,
          ),
        ));
      } on Object catch (e) {
        await mirror.quarantine(r.envelopeId, 'payload: $e');
        quarantined.add(r.envelopeId);
      }
    }

    // 1b. Author sequences for the projector (ADR 05b §3–4). The projector sees
    //     only the object types it consumes, while an author's `author_seq`
    //     numbers every object (accounts, rules, config …), so handing it the raw
    //     seqs would show holes that are not gaps. The mirror holds the complete
    //     view: `author_gaps` is derived there over every object type. For an
    //     author with **no** mirror gap we pass the projector a dense rank of its
    //     projected events (contiguous ⇒ a missing target is provably absent →
    //     `target_missing`); for an author **with** a gap we pass null, so the
    //     projector keeps that author's dangling references `held`.
    //     ⚠️ SPEC: interpretation of 05b §3–4 for a projector that sees a subset
    //     of the authored objects; the mirror's gap table stays authoritative.
    final authorsWithGaps = {for (final g in gaps) g.authorDevice};
    final projectedSeqs = <String, List<int>>{};
    for (final (r, _) in opened) {
      if (!projectedObjectTypes.contains(r.objectType)) continue;
      if (authorsWithGaps.contains(r.authorDevice)) continue;
      projectedSeqs.putIfAbsent(r.authorDevice, () => []).add(r.authorSeq);
    }
    final rankOf = <(String, int), int>{};
    for (final MapEntry(key: author, value: seqs) in projectedSeqs.entries) {
      seqs.sort();
      for (var i = 0; i < seqs.length; i++) {
        rankOf[(author, seqs[i])] = i + 1;
      }
    }

    // 1c. Decode.
    BookConfig? config;
    final accountsByObject = <String, AccountPayload>{};
    final events = <String, LedgerEvent>{}; // envelope id → event
    final rawByEnvelope = <String, Map<String, Object?>>{};
    for (final (r, json) in opened) {
      try {
        switch (r.objectType) {
          case 'book_config':
            config = BookConfig.fromJson(json);
          case 'account':
            // Latest version of each account object wins (rows are in (hlc, id) order).
            accountsByObject[r.objectId] = AccountPayload.fromJson(json);
          default:
            final ev = decodeEvent(
              r.objectType,
              json,
              authorDevice: r.authorDevice,
              authorSeq: rankOf[(r.authorDevice, r.authorSeq)],
            );
            if (ev != null) {
              events[r.envelopeId] = ev;
              rawByEnvelope[r.envelopeId] = json;
            }
        }
      } on Object catch (e) {
        await mirror.quarantine(r.envelopeId, 'payload: $e');
        quarantined.add(r.envelopeId);
      }
    }

    // 3. Chart and book row.
    final chart = Chart(
      bookId: bookId,
      accounts: accountsByObject.values.map((a) => a.account),
    );
    final fyStart = config?.fyStartMonth ?? 4;

    // 4. Seed (03 §3.3 rule 3): when the mirror holds a year_close whose FY has
    //    no entries locally (cold-archived, 05 §8), start from its vector and
    //    replay only later envelopes. Otherwise full replay — exact, and the
    //    path the golden suite proves.
    final seed = _seedFor(events.values, fyStart);
    Iterable<LedgerEvent> toProject = events.values;
    if (seed != null) {
      final keptEntries = <String>{
        for (final e in events.values)
          if (e is Entry && e.accountingDate.isAfter(seed.fy.lastDay)) e.id,
      };
      toProject = events.values
          .where(
            (e) => switch (e) {
              Entry() => keptEntries.contains(e.id),
              // Decisions ride with their entries; an archived entry's decision
              // is already folded into the certified vector.
              ApprovalDecision() => keptEntries.contains(e.entryId),
              CashCount() => e.date.isAfter(seed.fy.lastDay),
              // The seed close itself stays so year_close_p keeps the vector.
              YearClose() => !e.financialYear.firstDay.isBefore(
                seed.fy.firstDay,
              ),
              // Locks / unlocks are all-time objects (ADR 05e §5).
              _ => true,
            },
          )
          .toList();
    }
    final envelopeByEventId = <String, String>{
      for (final e in events.entries) e.value.id: e.key,
    };
    final state = project(toProject, chart, opening: seed?.vector);
    for (final q in state.quarantined) {
      final envId = envelopeByEventId[q.eventId]!;
      await mirror.quarantine(envId, q.violations.join('; '));
      quarantined.add(envId);
    }

    // 2. Dangling references are held, not counted (ADR 05b §4): projector
    //    output, mirrored into the flag columns so the status surface and the
    //    sync layer see them. A held event is absent from `state.entries`, so
    //    nothing below writes it to entries_p / entry_lines_p.
    final held = <String>[];
    for (final h in state.held) {
      final envId = envelopeByEventId[h.event.id]!;
      held.add(envId);
      await mirror.hold(envId, targetId: h.heldFor);
    }
    for (final r in rows) {
      if (r.held == 1 && !held.contains(r.envelopeId)) {
        await mirror.release(r.envelopeId);
      }
    }

    // 5. Write Layer 2. A book is whole only when every envelope is verified and
    //    intact, nothing is held, and no author has a gap — whether the gap is
    //    seen by the mirror (all object types) or by the projector (ADR 05c §6).
    await _dropBook(bookId);
    final integrityOk =
        unverified == 0 &&
        corrupt.isEmpty &&
        held.isEmpty &&
        gaps.isEmpty &&
        state.authorGaps.isEmpty;
    await db
        .into(db.booksP)
        .insert(
          BooksPCompanion.insert(
            id: bookId,
            tenantId: config?.tenantId ?? '',
            type: config?.type.name ?? BookType.family.name,
            name: config?.name ?? bookId,
            fyStartMonth: Value(fyStart),
            integrityOk: Value(integrityOk ? 1 : 0),
            needsRebootstrap: Value(corrupt.isEmpty ? 0 : 1),
          ),
        );
    for (final a in accountsByObject.values) {
      await db
          .into(db.accountsP)
          .insert(
            AccountsPCompanion.insert(
              id: a.account.id,
              bookId: bookId,
              name: a.account.name,
              accountClass: accountClassWire[a.account.accountClass]!,
              moneySubtype: Value(moneySubtypeWire[a.account.subtype]),
              collectionIncomeAccountId: Value(a.collectionIncomeAccountId),
              usualCategoryId: Value(a.usualCategoryId),
              archived: Value(a.archived ? 1 : 0),
              systemRole: Value(systemRoleWire[a.account.systemRole]),
              memberId: Value(a.account.memberId),
              counterpartBookId: Value(a.account.counterpartBookId),
              createdOrder: a.account.createdOrder,
            ),
          );
    }
    var maxHlc = 0;
    for (final e in toProject) {
      if (e.hlc.raw > maxHlc) maxHlc = e.hlc.raw;
    }
    for (final p in state.entries.values) {
      final e = p.entry;
      final decision = _decisionFor(e.id, events.values);
      await db
          .into(db.entriesP)
          .insert(
            EntriesPCompanion.insert(
              id: e.id,
              bookId: bookId,
              kind: e.kind.wire,
              status: _statusWire[p.status]!,
              accountingDate: e.accountingDate.toIso(),
              note: Value(e.note),
              channel: Value(e.extra['channel'] as String?),
              partyId: Value(e.partyId),
              advanceRef: Value(e.advanceId),
              transferGroup: Value(e.refs.transferGroup),
              amends: Value(e.refs.amends),
              reverses: Value(e.refs.reverses),
              supersededBy: Value(p.supersededBy),
              reviewState: Value(p.reviewState.name),
              reviewApprover: Value(p.decidedBy ?? e.reviewApprover),
              reviewDecidedHlc: Value(decision?.hlc.raw),
              reviewReason: Value(decision?.reason),
              createdByUser: e.createdByUser,
              hlc: e.hlc.raw,
            ),
          );
      for (var i = 0; i < e.lines.length; i++) {
        final l = e.lines[i];
        await db
            .into(db.entryLinesP)
            .insert(
              EntryLinesPCompanion.insert(
                entryId: e.id,
                accountId: l.accountId,
                amountPaise: l.amount.raw,
                bookId: bookId,
                accountingDate: e.accountingDate.toIso(),
                lineIndex: i,
              ),
            );
      }
    }
    for (final MapEntry(key: account, value: bal)
        in state.balances.nonZero.entries) {
      // A certified year's net result rides in the vector (year_close_p), not in
      // `balances`: it is a computed line, never an account (ADR 05e §2).
      if (isNetResultKey(account)) continue;
      await db
          .into(db.balances)
          .insert(
            BalancesCompanion.insert(
              accountId: account,
              balancePaise: bal.raw,
              asOfHlc: maxHlc,
            ),
          );
    }
    await _writeSnapshots(state, seed?.vector);
    for (final ym in state.periods.periods) {
      final lock = state.periods.lockFor(ym);
      await db
          .into(db.periodsP)
          .insert(
            PeriodsPCompanion.insert(
              bookId: bookId,
              year: ym.year,
              month: ym.month,
              state: lock == null ? 'open' : 'locked',
              lockHlc: Value(lock?.hlc.raw),
              verification: Value(
                lock == null ? null : state.lockVerification[lock.id]?.wire,
              ),
            ),
          );
    }
    for (final MapEntry(key: fy, value: ys) in state.years.entries) {
      await db
          .into(db.yearCloseP)
          .insert(
            YearClosePCompanion.insert(
              bookId: bookId,
              fyLabel: fy.label,
              state: ys.status.name,
              vector: Value(
                ys.certifiedVector == null
                    ? null
                    : jsonEncode({
                        for (final e in ys.certifiedVector!.nonZero.entries)
                          e.key: e.value.raw,
                      }),
              ),
              projectorVersion: Value(
                _closeOf(ys, toProject)?.projectorVersion,
              ),
              verification: Value(ys.verification?.wire),
            ),
          );
    }
    for (final ev in toProject) {
      if (ev is! CashCount || !chart.contains(ev.accountId)) continue;
      final raw = rawByEnvelope.values.firstWhere(
        (j) => j['id'] == ev.id,
        orElse: () => const {},
      );
      await db
          .into(db.cashCountsP)
          .insert(
            CashCountsPCompanion.insert(
              id: ev.id,
              accountId: ev.accountId,
              mode:
                  chart.account(ev.accountId).subtype ==
                      MoneySubtype.cashCollection
                  ? 'collect'
                  : 'verify',
              countedAt: ev.date.toIso(),
              countedTotalPaise: ev.counted.raw,
              breakdownJson: Value(
                raw['sheet'] == null ? null : jsonEncode(raw['sheet']),
              ),
              postedEntryId: Value(raw['posted_entry_id'] as String?),
              countedBy: Value(ev.countedBy),
              witness: Value(ev.witness),
            ),
          );
    }

    return BookRecompute(
      bookId: bookId,
      eventsApplied: toProject.length,
      held: held,
      quarantined: quarantined,
      unverified: unverified,
      corrupt: corrupt,
      authorGaps: gaps.length + state.authorGaps.length,
      seededFromVector: seed != null,
      integrityOk: integrityOk,
    );
  }

  Future<void> _dropBook(String bookId) async {
    final accountIds =
        await (db.selectOnly(db.accountsP)
              ..addColumns([db.accountsP.id])
              ..where(db.accountsP.bookId.equals(bookId)))
            .map((r) => r.read(db.accountsP.id)!)
            .get();
    if (accountIds.isNotEmpty) {
      await (db.delete(
        db.balances,
      )..where((t) => t.accountId.isIn(accountIds))).go();
      await (db.delete(
        db.dailySnapshots,
      )..where((t) => t.accountId.isIn(accountIds))).go();
      await (db.delete(
        db.cashCountsP,
      )..where((t) => t.accountId.isIn(accountIds))).go();
    }
    await (db.delete(
      db.entryLinesP,
    )..where((t) => t.bookId.equals(bookId))).go();
    await (db.delete(db.entriesP)..where((t) => t.bookId.equals(bookId))).go();
    await (db.delete(db.periodsP)..where((t) => t.bookId.equals(bookId))).go();
    await (db.delete(
      db.yearCloseP,
    )..where((t) => t.bookId.equals(bookId))).go();
    await (db.delete(db.accountsP)..where((t) => t.bookId.equals(bookId))).go();
    await (db.delete(db.booksP)..where((t) => t.id.equals(bookId))).go();
  }

  Future<void> _writeSnapshots(
    LedgerState state,
    BalanceVector? opening,
  ) async {
    final running = <String, int>{
      for (final e in (opening?.nonZero ?? const <String, Paise>{}).entries)
        if (!isNetResultKey(e.key)) e.key: e.value.raw,
    };
    String? date;
    final touched = <String>{};
    Future<void> flush() async {
      if (date == null) return;
      for (final a in touched) {
        await db
            .into(db.dailySnapshots)
            .insert(
              DailySnapshotsCompanion.insert(
                accountId: a,
                date: date,
                balancePaise: running[a] ?? 0,
              ),
            );
      }
      touched.clear();
    }

    for (final p in state.counted) {
      final d = p.entry.accountingDate.toIso();
      if (d != date) {
        await flush();
        date = d;
      }
      for (final l in p.entry.lines) {
        running[l.accountId] = (running[l.accountId] ?? 0) + l.amount.raw;
        touched.add(l.accountId);
      }
    }
    await flush();
  }

  /// Cross-check (ADR 05c §6): recompute every balance of [bookId] from
  /// `entry_lines_p` (counted entries only, plus the seed vector when the
  /// rebuild seeded) and compare with `balances`. Empty = consistent.
  Future<List<BalanceMismatch>> verifyBalances(String bookId) async {
    final lines = await db
        .customSelect(
          'SELECT l.account_id AS a, SUM(l.amount_paise) AS s '
          'FROM entry_lines_p l JOIN entries_p e ON e.id = l.entry_id '
          "WHERE l.book_id = ? AND e.status IN ('posted','void') GROUP BY l.account_id",
          variables: [Variable.withString(bookId)],
        )
        .get();
    final expected = <String, int>{};
    final seed = await _storedSeed(bookId);
    for (final e in (seed ?? const <String, int>{}).entries) {
      if (isNetResultKey(e.key)) continue;
      expected[e.key] = e.value;
    }
    for (final r in lines) {
      final a = r.read<String>('a');
      expected[a] = (expected[a] ?? 0) + r.read<int>('s');
    }
    expected.removeWhere((_, v) => v == 0);
    final stored = <String, int>{};
    final accountIds =
        await (db.selectOnly(db.accountsP)
              ..addColumns([db.accountsP.id])
              ..where(db.accountsP.bookId.equals(bookId)))
            .map((r) => r.read(db.accountsP.id)!)
            .get();
    if (accountIds.isNotEmpty) {
      for (final b in await (db.select(
        db.balances,
      )..where((t) => t.accountId.isIn(accountIds))).get()) {
        stored[b.accountId] = b.balancePaise;
      }
    }
    final out = <BalanceMismatch>[];
    for (final a in {...expected.keys, ...stored.keys}) {
      if (expected[a] != stored[a]) {
        out.add(BalanceMismatch(a, stored[a], expected[a] ?? 0));
      }
    }
    out.sort((x, y) => x.accountId.compareTo(y.accountId));
    return out;
  }

  /// The corruption path for projections (ADR 05c §6): if [verifyBalances]
  /// finds any mismatch, drop and rebuild the book. Returns the mismatches found.
  Future<List<BalanceMismatch>> checkAndRepair(String bookId) async {
    final bad = await verifyBalances(bookId);
    if (bad.isNotEmpty) await run(bookId: bookId);
    return bad;
  }

  // The seed vector a seeded rebuild used, re-derived from year_close_p and the
  // entries present — same rule as _seedFor, read back from Layer 2.
  Future<Map<String, int>?> _storedSeed(String bookId) async {
    final closes = await (db.select(
      db.yearCloseP,
    )..where((t) => t.bookId.equals(bookId) & t.vector.isNotNull())).get();
    if (closes.isEmpty) return null;
    final book = await (db.select(
      db.booksP,
    )..where((t) => t.id.equals(bookId))).getSingle();
    final earliest = await db
        .customSelect(
          'SELECT MIN(accounting_date) AS d FROM entries_p WHERE book_id = ?',
          variables: [Variable.withString(bookId)],
        )
        .getSingle();
    final earliestDate = earliest.read<String?>('d');
    FinancialYear? best;
    String? bestVector;
    for (final c in closes) {
      final fy = _fyFromLabel(c.fyLabel, book.fyStartMonth);
      if (earliestDate != null &&
          !LocalDate.parse(earliestDate).isAfter(fy.lastDay)) {
        continue; // entries of that FY are present: full replay covered it
      }
      if (best == null || fy.firstDay.isAfter(best.firstDay)) {
        best = fy;
        bestVector = c.vector;
      }
    }
    if (bestVector == null) return null;
    return {
      for (final e in (jsonDecode(bestVector) as Map<String, Object?>).entries)
        e.key: e.value as int,
    };
  }
}

final class _Seed {
  const _Seed(this.fy, this.vector);
  final FinancialYear fy;
  final BalanceVector vector;
}

/// The latest year_close whose FY has no entry present locally — the archived
/// case rule 3 seeds from. Null when every closed FY's entries are here.
_Seed? _seedFor(Iterable<LedgerEvent> events, int fyStart) {
  LocalDate? earliest;
  for (final e in events) {
    if (e is Entry &&
        (earliest == null || e.accountingDate.isBefore(earliest))) {
      earliest = e.accountingDate;
    }
  }
  _Seed? best;
  for (final e in events) {
    if (e is! YearClose) continue;
    final fy = e.financialYear;
    if (earliest != null && !earliest.isAfter(fy.lastDay)) continue;
    if (best == null || fy.firstDay.isAfter(best.fy.firstDay)) {
      best = _Seed(fy, e.vector);
    }
  }
  return best;
}

FinancialYear _fyFromLabel(String label, int startMonth) {
  final y = int.parse(label.split('-').first);
  return FinancialYear(y, startMonth: startMonth);
}

YearClose? _closeOf(YearState ys, Iterable<LedgerEvent> events) {
  if (ys.closeId == null) return null;
  for (final e in events) {
    if (e is YearClose && e.id == ys.closeId) return e;
  }
  return null;
}

extension on CloseVerification {
  /// Column form: `verified | mismatch | reader_outdated | certifier_outdated`.
  String get wire => switch (this) {
    CloseVerification.verified => 'verified',
    CloseVerification.mismatch => 'mismatch',
    CloseVerification.readerOutdated => 'reader_outdated',
    CloseVerification.certifierOutdated => 'certifier_outdated',
  };
}

ApprovalDecision? _decisionFor(String entryId, Iterable<LedgerEvent> events) {
  ApprovalDecision? last;
  for (final e in events) {
    if (e is ApprovalDecision && e.entryId == entryId) {
      if (last == null ||
          compareEventOrder(e.hlc, e.id, last.hlc, last.id) > 0) {
        last = e;
      }
    }
  }
  return last;
}

const _statusWire = {
  EffectiveStatus.posted: 'posted',
  EffectiveStatus.pending: 'pending',
  EffectiveStatus.rejected: 'rejected',
  EffectiveStatus.superseded: 'superseded',
  EffectiveStatus.voided: 'void',
  EffectiveStatus.inTray: 'in_tray',
};
