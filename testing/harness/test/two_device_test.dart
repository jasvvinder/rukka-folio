// Suite D — first behavioural two-device tests (09 §1 "two-client harness",
// 09 §2 D; ADR 2026-09-05b §3–§4). Two SimulatedDevices on the real data
// stack, one seeded network between them, no server yet (M4). Every seed below
// was chosen so the reorder or drop the test needs actually happens, and each
// test asserts that it did — the scenario is never green by luck.
//
// Setup envelopes (book_config + accounts) reach the second device out of band
// (a bootstrap pull, 05 §8), so they do not consume network decisions and the
// pinned seeds address the entries alone.
@Tags(['D'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:harness/harness.dart';
import 'package:test/test.dart';

const _book = 'b1';

final _config = BookConfig(
  id: _book,
  tenantId: 't1',
  type: BookType.family,
  name: 'Sharma family',
);

Account _acct(
  String id,
  String name,
  AccountClass c,
  int order, [
  MoneySubtype? sub,
]) => Account(
  id: '$_book:$id',
  bookId: _book,
  name: name,
  accountClass: c,
  subtype: sub,
  createdOrder: order,
);

final _cash = _acct('cash', 'Cash', AccountClass.money, 0, MoneySubtype.cash);
final _kirana = _acct('kirana', 'Kirana', AccountClass.categoryExpense, 1);
final _salary = _acct('salary', 'Salary', AccountClass.categoryIncome, 2);
final _accounts = [_cash, _kirana, _salary];

Entry _moneyOut(
  SimulatedDevice by,
  String id,
  int rupees, {
  required int physicalMs,
  int day = 5,
}) => Entry(
  id: id,
  bookId: _book,
  kind: EntryKind.moneyOut,
  status: EntryStatus.posted,
  reviewRequired: false,
  accountingDate: LocalDate(2026, 4, day),
  lines: Verbs.moneyOut(
    from: _cash,
    forWhat: _kirana,
    amount: Paise.rupees(rupees),
  ),
  createdByUser: 'ramesh',
  createdByDevice: by.id,
  hlc: by.nextHlc(physicalMs),
);

final class Rig {
  Rig(this.s, this.a, this.b, this.relay);
  final Scheduler s;
  final SimulatedDevice a;
  final SimulatedDevice b;
  final Relay relay;

  static Future<Rig> open(Network net) async {
    final s = Scheduler();
    final a = await SimulatedDevice.open('phone-a');
    final b = await SimulatedDevice.open('phone-b');
    final relay = Relay(s, net, {a.id: a, b.id: b});
    // Bootstrap: the book's all-time objects, out of band.
    for (final rec in await a.authorSetup(_config, _accounts, physicalMs: 0)) {
      await b.receive(rec);
    }
    return Rig(s, a, b, relay);
  }

  Future<void> close() async {
    await a.close();
    await b.close();
  }
}

/// The D-05b-2 scenario over any [Network]; returns what was observed on B
/// after the amendment alone, then the final dumps.
Future<
  ({
    bool a1First,
    bool held,
    String? heldFor,
    bool a1Projected,
    int cashAfterA1,
    bool? integrityAfterA1,
    int? cashFinal,
    String? supersededBy,
    bool? integrityFinal,
    String dumpA,
    String dumpB,
  })
>
_orphanScenario(Network net) async {
  final r = await Rig.open(net);
  final (s, a, b) = (r.s, r.a, r.b);

  final e = _moneyOut(a, 'E', 250, physicalMs: s.now);
  r.relay.broadcast(a.id, await a.author(e));
  s.run(untilMs: 100);
  final a1 = e.amendWith(
    newId: 'A1',
    hlc: a.nextHlc(s.now),
    lines: Verbs.moneyOut(
      from: _cash,
      forWhat: _kirana,
      amount: const Paise.rupees(300),
    ),
  );
  r.relay.broadcast(a.id, await a.author(a1));

  // Run until the first arrival only, deliver it, observe.
  final firstAt = r.relay.decisions
      .map((d) => d.arrivesAt!)
      .reduce((x, y) => x < y ? x : y);
  s.run(untilMs: firstAt);
  await r.relay.deliverPending();
  final first = r.relay.arrivals.single;
  final row = await b.envelopeRow('env-A1');
  final observed = (
    a1First: first.record.envelopeId == 'env-A1',
    held: row?.held == 1,
    heldFor: row?.heldFor,
    a1Projected: await b.entryRow('A1') != null,
    cashAfterA1: await b.balance(_cash.id) ?? 0,
    integrityAfterA1: await b.integrityOk(_book),
  );

  s.run();
  await r.relay.deliverPending();
  final result = (
    a1First: observed.a1First,
    held: observed.held,
    heldFor: observed.heldFor,
    a1Projected: observed.a1Projected,
    cashAfterA1: observed.cashAfterA1,
    integrityAfterA1: observed.integrityAfterA1,
    cashFinal: await b.balance(_cash.id),
    supersededBy: (await b.entryRow('E'))?.supersededBy,
    integrityFinal: await b.integrityOk(_book),
    dumpA: await a.dump(),
    dumpB: await b.dump(),
  );
  await r.close();
  return result;
}

void main() {
  test('D-05b-2 orphan amendment: held on the second device until its original '
      'arrives, then both fold and the amount counts once; identical dumps; the '
      'whole run replays from the network log', () async {
    // seed 1: E arrives at 4251 ms, A1 at 3406 ms (0–5000 ms delays).
    final model = NetworkModel(seed: 1, minDelayMs: 0, maxDelayMs: 5000);
    final live = await _orphanScenario(model);

    expect(live.a1First, isTrue, reason: 'the pinned seed must reorder');
    expect(live.held, isTrue);
    expect(live.heldFor, 'E');
    expect(live.a1Projected, isFalse, reason: 'held = not projected');
    expect(live.cashAfterA1, 0, reason: 'nothing counted while held');
    expect(live.integrityAfterA1, isFalse);

    expect(live.cashFinal, -300 * 100, reason: 'counted exactly once');
    expect(live.supersededBy, 'A1');
    expect(live.integrityFinal, isTrue);
    expect(live.dumpB, live.dumpA);

    // Replay: same scenario, fresh devices, decisions from the log only.
    final log = model.log;
    expect(log.deliveries.length, 2);
    final replayed = await _orphanScenario(log.replay());
    expect(replayed, live);
  });

  test('D-05b-3 withheld envelope: the second device shows the author gap, '
      'integrity 0, month lock and year close refuse with authorGapOpen; the '
      're-sent envelope closes the gap and the dumps converge', () async {
    // seed 10 with dropRate 0.34: decisions keep, DROP, keep, keep.
    final model = NetworkModel(
      seed: 10,
      minDelayMs: 10,
      maxDelayMs: 500,
      dropRate: 0.34,
    );
    final r = await Rig.open(model);
    final (s, a, b) = (r.s, r.a, r.b);

    final recs = <EnvelopeRecord>[];
    for (var i = 0; i < 3; i++) {
      s.run(untilMs: i * 100);
      final rec = await a.author(
        _moneyOut(a, 'e$i', 100 * (i + 1), physicalMs: s.now, day: 5 + i),
      );
      recs.add(rec);
      r.relay.broadcast(a.id, rec);
    }
    s.run();
    await r.relay.deliverPending();
    expect(r.relay.decisions.map((d) => d.dropped), [
      false,
      true,
      false,
    ], reason: 'the pinned seed must drop exactly the second envelope');

    final gaps = await b.gaps(_book);
    expect(gaps.length, 1);
    expect(gaps.single.authorDevice, a.id);
    expect(gaps.single.expectedSeq, recs[1].authorSeq);
    expect(await b.integrityOk(_book), isFalse);
    // e0 and e2 still count on B (live balance, 02 §3); only the close is blocked.
    expect(await b.balance(_cash.id), -(100 + 300) * 100);

    final (state, chart) = await b.state(_book);
    expect(state.authorGaps.map((g) => g.authorDevice), [a.id]);
    final fy = FinancialYear.of(LocalDate(2026, 4, 5));
    final lock = monthLockPreconditions(state, YearMonth(2026, 4));
    expect(lock.map((x) => x.kind), contains(CloseBlocker.authorGapOpen));
    expect(
      lock.firstWhere((x) => x.kind == CloseBlocker.authorGapOpen).ref,
      a.id,
    );
    final close = yearClosePreconditions(state, chart, fy);
    expect(close.map((x) => x.kind), contains(CloseBlocker.authorGapOpen));

    // A re-sends the withheld envelope (05 §4 retry); the model records it.
    s.run(untilMs: 300);
    r.relay.broadcast(a.id, recs[1]);
    s.run();
    await r.relay.deliverPending();
    expect(r.relay.decisions.last.dropped, isFalse);
    expect(model.log.deliveries.length, 4);

    expect(await b.gaps(_book), isEmpty);
    expect(await b.integrityOk(_book), isTrue);
    expect(await b.balance(_cash.id), -(100 + 200 + 300) * 100);
    final (state2, _) = await b.state(_book);
    expect(monthLockPreconditions(state2, YearMonth(2026, 4)), isEmpty);
    expect(await b.dump(), await a.dump());
    await r.close();
  });

  test(
    'D-05b-4 two authors interleaved under reordering converge: arrival order '
    'differs from authoring order on both phones, dumps are identical',
    () async {
      final model = NetworkModel(seed: 1, minDelayMs: 0, maxDelayMs: 3000);
      final r = await Rig.open(model);
      final (s, a, b) = (r.s, r.a, r.b);

      final sentToB = <String>[];
      final sentToA = <String>[];
      for (var i = 0; i < 20; i++) {
        s.run(untilMs: i * 100);
        final by = i.isEven ? a : b;
        final rec = await by.author(
          _moneyOut(by, 'e$i', 10 + i, physicalMs: s.now, day: 1 + i),
        );
        r.relay.broadcast(by.id, rec);
        (i.isEven ? sentToB : sentToA).add(rec.envelopeId);
      }
      s.run();
      await r.relay.deliverPending();

      List<String> arrivedAt(String id) => [
        for (final x in r.relay.arrivals)
          if (x.to == id) x.record.envelopeId,
      ];
      expect(
        arrivedAt(b.id),
        isNot(sentToB),
        reason: 'B saw A\'s entries reordered',
      );
      expect(
        arrivedAt(a.id),
        isNot(sentToA),
        reason: 'A saw B\'s entries reordered',
      );
      expect(arrivedAt(b.id).toSet(), sentToB.toSet(), reason: 'lossless');

      expect(await a.integrityOk(_book), isTrue);
      expect(await b.integrityOk(_book), isTrue);
      final total = List.generate(
        20,
        (i) => 10 + i,
      ).fold<int>(0, (x, y) => x + y);
      expect(await a.balance(_cash.id), -total * 100);
      expect(await a.dump(), await b.dump());
      await r.close();
    },
  );
}
