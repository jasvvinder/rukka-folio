// Recompute (03 §3.3 rule 3; ADR 2026-09-05c §3, §6): drop every projection
// row of a book and rebuild it from the mirror through `core_ledger.project()`.
// This file is the ONE place the data layer touches the projector's API. `held`,
// `authorGaps`, `lockVerification` and `YearState.verification` are projector
// output (ADR 2026-09-05b §3–4, 05c §3); this layer only mirrors them into rows.
import 'dart:async';
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
    required this.authorDuplicates,
    required this.seededFromVector,
    required this.integrityOk,
    required this.state,
    required this.chart,
    this.config,
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

  /// Open author gaps (ADR 05b §3), mirror-derived over every object type;
  /// `state.authorGaps` names the same holes by projected rank.
  final int authorGaps;

  /// Repeated `author_seq` values (ADR 05b §3): the later envelope of each
  /// pair is quarantined `author_seq_duplicate`; the book is not whole.
  final List<String> authorDuplicates;

  /// True when the rebuild seeded from a certified vector (03 §3.3 rule 3).
  final bool seededFromVector;

  /// `books_p.integrity_ok` as written.
  final bool integrityOk;

  /// The projector's state for this book as Recompute composed it — the same
  /// `authorGaps` / `held` the rows were written from, so callers
  /// (`monthLockPreconditions`, `yearClosePreconditions`, tests) see one truth.
  final LedgerState state;

  /// The chart the state was projected against.
  final Chart chart;

  /// The book's `book_config` as decoded (03 §2.3), or null when the book has
  /// no config envelope yet. Handed out so the fields `books_p` does not
  /// project — `ownership`, the 02 §7.1 🔒 share weights, the 07 §3.1.1
  /// organization subtype — have a read path that is still the envelope
  /// stream, not a second copy of the truth.
  final BookConfig? config;

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

/// One reading of a book's rebuild: [done] of [total] entry envelopes read
/// back (07 §28 🔒, 11 §4.5 🔒).
///
/// A **count**, never a percentage and never a spinner — the loader rule says
/// *"{done} of {total} entries restored"*, so the producer hands over the two
/// numbers and nothing derived. [total] is the book's `entry` envelopes as the
/// plaintext mirror column reports them (03 §3.1), which is why it is known
/// before a single payload is opened and the loader can be determinate.
final class RecomputeProgress {
  /// Creates the reading.
  const RecomputeProgress({
    required this.bookId,
    required this.done,
    required this.total,
  });

  /// The book being rebuilt.
  final String bookId;

  /// Entry envelopes read back so far. Never decreases within one rebuild and
  /// ends equal to [total], whatever each envelope turned out to be — a
  /// corrupt or quarantined row is still a reading, so the count cannot stall
  /// short of the number the user was shown.
  final int done;

  /// Entry envelopes this rebuild has to read.
  final int total;

  @override
  bool operator ==(Object other) =>
      other is RecomputeProgress &&
      other.bookId == bookId &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(bookId, done, total);

  @override
  String toString() => 'RecomputeProgress($bookId, $done/$total)';
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

  // ── rebuild progress (S1.4; 07 §28 🔒, ADR 2026-09-05c §3/§6) ─────────────
  //
  // Counts only. Nothing here reads a clock, a locale or a setting, and the
  // projector never sees this controller — `project()` is still called once,
  // with the whole ordered event list, from `_rebuildBook`. Progress is an
  // observation *about* the rebuild, never an input to it, so two runs over
  // the same envelopes still produce byte-identical projections (E-03-9).
  final StreamController<(String, RecomputeProgress?)> _progress =
      StreamController<(String, RecomputeProgress?)>.broadcast();

  /// Book → the reading in hand. Absent means "not rebuilding".
  final Map<String, RecomputeProgress> _live = {};

  /// Book → how many `run()` calls are inside it. A book stops reporting only
  /// when the last one leaves, so an overlapping rebuild cannot end the first
  /// one's report early and drop the loader on a half-built book.
  final Map<String, int> _running = {};

  /// The reading in hand for [bookId], or null when it is not rebuilding.
  RecomputeProgress? progressOf(String bookId) => _live[bookId];

  /// Live rebuild readings for [bookId]: a [RecomputeProgress] while the book
  /// is being rebuilt, `null` while it is not.
  ///
  /// The reading in hand is replayed to **every** new listener, so a screen
  /// that mounts in the middle of a rebuild renders S1.4 at once instead of
  /// waiting for the next tick — which is the normal case for the three
  /// triggers (local corruption, Recompute-on-upgrade, `store_epoch` re-pull;
  /// ADR 2026-09-05c §3/§6), all of which start before Home is on screen.
  ///
  /// Re-listenable and multi-listener by construction ([Stream.multi]): Home
  /// unmounts the gate when the scope switches to *Everything* and mounts it
  /// again on the way back, over the same memoised stream.
  Stream<RecomputeProgress?> watchProgress(String bookId) =>
      Stream<RecomputeProgress?>.multi((controller) {
        // Captured at listen time, so the replay is the reading that was true
        // when the listener arrived — not whatever it has become by the time
        // the event is delivered.
        controller.add(_live[bookId]);
        final sub = _progress.stream.listen((e) {
          if (e.$1 == bookId) controller.add(e.$2);
        }, onDone: controller.close);
        // Deliberately synchronous: awaiting a cancel inside `flutter_test`'s
        // fake-async zone deadlocks widget teardown (the U2a finding).
        controller.onCancel = () => unawaited(sub.cancel());
      });

  /// Stops the progress stream. The facade owns a [Recompute] for the life of
  /// the process, so this is for tests and for a store that is torn down.
  Future<void> dispose() {
    _live.clear();
    _running.clear();
    return _progress.close();
  }

  void _report(String bookId, int done, int total) {
    final reading = RecomputeProgress(bookId: bookId, done: done, total: total);
    _live[bookId] = reading;
    if (!_progress.isClosed) _progress.add((bookId, reading));
  }

  /// Rebuilds every book, or just [bookId]. Each book is one transaction:
  /// projection rows dropped and rewritten atomically, so a reader never sees a
  /// half-built book (03 §5 fail-closed spirit).
  Future<List<BookRecompute>> run({String? bookId}) async {
    final books = bookId == null ? await mirror.bookIds() : [bookId];
    final out = <BookRecompute>[];
    for (final b in books) {
      _running[b] = (_running[b] ?? 0) + 1;
      try {
        out.add(await db.transaction(() => _rebuildBook(b)));
      } finally {
        // Whatever happened — finished, or the transaction rolled back on a
        // throw — the book stops reporting, so S1.4 can never stick up over a
        // rebuild that is no longer running (07 §28 🔒, 07 §1 no dead ends).
        final left = (_running[b] ?? 1) - 1;
        if (left > 0) {
          _running[b] = left;
        } else {
          _running.remove(b);
          _live.remove(b);
          if (!_progress.isClosed) _progress.add((b, null));
        }
      }
    }
    return out;
  }

  Future<BookRecompute> _rebuildBook(String bookId) async {
    var rows = await mirror.envelopesOf(bookId);
    final gaps = await mirror.recomputeAuthorGaps(bookId);
    // (gaps is List<SeqGap>)

    // 0. Duplicate author sequences (ADR 05b §3): the earlier envelope by
    //    (hlc, envelope_id) keeps the number; every later one is quarantined —
    //    the mirror counterpart of the projector's `authorSeqDuplicate`. A
    //    duplicate cannot be removed (append-only), so the book stays not-whole
    //    for as long as it exists, and a second Recompute finds the same state.
    final duplicates = await mirror.recomputeAuthorDuplicates(bookId);
    final duplicateIds = <String>[];
    for (final d in duplicates) {
      duplicateIds.add(d.duplicateEnvelopeId);
      final row = rows.firstWhere((r) => r.envelopeId == d.duplicateEnvelopeId);
      if (row.quarantined != 1) {
        await mirror.quarantine(d.duplicateEnvelopeId, 'author_seq_duplicate');
      }
    }
    if (duplicateIds.isNotEmpty) rows = await mirror.envelopesOf(bookId);

    // 1. Open every usable payload; note corruption, quarantine failures.
    //
    //    S1.4 (07 §28 🔒) is produced from this loop: `object_type` is a
    //    plaintext mirror column (03 §3.1), so the number of `entry` envelopes
    //    is known before the first payload is opened and the loader is
    //    determinate (11 §4.5 🔒 — a count, never a percentage, never a
    //    spinner). Only entries are counted, so the number matches the words
    //    the user reads: an `account` or `book_config` envelope is restored
    //    too but is not an entry. ⚠️ SPEC: 07 §28 quotes the copy and names no
    //    unit; counting the object the copy names is the conservative reading.
    final entryTotal = rows.where((r) => r.objectType == 'entry').length;
    var entryDone = 0;
    _report(bookId, 0, entryTotal);

    final corrupt = <String>[];
    final quarantined = <String>[];
    var unverified = 0;
    final opened = <(EnvelopesLocalData, Map<String, Object?>)>[];
    for (final r in rows) {
      try {
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
              BlobHeader(
                envelopeId: r.envelopeId,
                bookId: r.bookId,
                objectId: r.objectId,
                objectType: r.objectType,
                keyVersion: r.keyVersion,
                authorDevice: r.authorDevice,
                hlc: r.hlc,
              ),
            ),
          ));
        } on Object catch (e) {
          await mirror.quarantine(r.envelopeId, 'payload: $e');
          quarantined.add(r.envelopeId);
        }
      } finally {
        // Every path through the row — opened, held back, corrupt, thrown —
        // is one reading, so the count always reaches the total the user was
        // shown. `continue` runs this too.
        if (r.objectType == 'entry') _report(bookId, ++entryDone, entryTotal);
      }
    }

    // 1b. Author sequences for the projector (ADR 05b §3–4) — ONE ranking rule
    //     for every event. The projector sees only the object types it consumes,
    //     while an author's `author_seq` numbers every object (accounts, rules,
    //     config …), so handing it raw seqs would show holes that are not gaps.
    //     Per author we rank, in seq order, the set of its *projected* seqs ∪ the
    //     seqs the mirror knows are *missing* (`author_gaps`, derived over every
    //     object type). A hole keeps its rank and nothing occupies it, so the
    //     projector reports the gap with the right device and `expectedSeq` =
    //     the hole's rank; a contiguous author proves a missing target absent
    //     (`target_missing`). Mirror `author_gaps` and `state.authorGaps` are
    //     thereby one truth (existence + device exact; the numbers differ by
    //     construction: mirror = the authored seq, state = its projected rank).
    //     ⚠️ SPEC: interpretation of 05b §3–4 for a projector that sees a subset
    //     of the authored objects.
    final seqsByAuthor = <String, Set<int>>{};
    for (final (r, _) in opened) {
      if (!projectedObjectTypes.contains(r.objectType)) continue;
      seqsByAuthor.putIfAbsent(r.authorDevice, () => {}).add(r.authorSeq);
    }
    for (final g in gaps) {
      seqsByAuthor.putIfAbsent(g.authorDevice, () => {}).add(g.expectedSeq);
    }
    final rankOf = <(String, int), int>{};
    for (final MapEntry(key: author, value: set) in seqsByAuthor.entries) {
      final seqs = set.toList()..sort();
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
            // The inner `author_seq` (05b §3, inside the ciphertext) and the
            // mirror row's column (03 §3.1) must agree; a disagreement is a
            // shape problem, not a gap. ⚠️ SPEC: quarantine reason
            // `author_seq_mismatch` (05c §5 names shape refusals server-side;
            // this is the client-side counterpart for the one field it can check).
            final inner = json['author_seq'];
            if (inner is int && inner != r.authorSeq) {
              await mirror.quarantine(r.envelopeId, 'author_seq_mismatch');
              quarantined.add(r.envelopeId);
              continue;
            }
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
        duplicateIds.isEmpty &&
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
            startDate: Value(config?.startDate?.toIso()),
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
      authorGaps: gaps.length,
      authorDuplicates: duplicateIds,
      seededFromVector: seed != null,
      integrityOk: integrityOk,
      state: state,
      chart: chart,
      config: config,
    );
  }

  /// Rebuilds [bookId] and returns the projector state and chart it was written
  /// from. This *is* a Recompute (rows rewritten) — there is deliberately no
  /// read-only composition path, so nobody can hold a state the rows disagree with.
  Future<(LedgerState, Chart)> stateOf(String bookId) async {
    final r = (await run(bookId: bookId)).single;
    return (r.state, r.chart);
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
