// Suite D — two SyncedDevices, the real engine on each, one in-memory server,
// requests through the seeded network (05 §3–§4; ADR 2026-09-05b §3–§4, §6).
// Everything is driven by the scheduler's virtual clock and replays from the
// network log.
@Tags(['D'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:harness/harness.dart';
import 'package:sync_engine/sync_engine.dart';
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
final _accounts = [_cash, _kirana];

Entry _moneyOut(
  SyncedDevice by,
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
  hlc: by.device.nextHlc(physicalMs),
);

final class Rig {
  Rig(this.s, this.server, this.a, this.b);
  final Scheduler s;
  final FakeSyncServer server;
  final SyncedDevice a;
  final SyncedDevice b;

  static Future<Rig> open({Network? network, NetworkModel? model}) async {
    final s = Scheduler();
    final server = FakeSyncServer(
      clock: SchedulerClock(s),
      rateLimits: RateLimits.none,
    );
    final a = await SyncedDevice.open(
      'phone-a',
      server: server,
      scheduler: s,
      userId: 'u-a',
      network: network,
      model: model,
      books: {_book},
    );
    final b = await SyncedDevice.open(
      'phone-b',
      server: server,
      scheduler: s,
      userId: 'u-b',
      network: network,
      model: model,
      books: {_book},
    );
    return Rig(s, server, a, b);
  }

  Future<void> close() async {
    await a.close();
    await b.close();
  }
}

void main() {
  test('D-05-2 orphan amendment through the server: the amendment arrives '
      'before its original (withheld) → held, nothing counted, author gap; the '
      'original arrives on re-bootstrap → exactly one entry in balances, '
      'identical dumps', () async {
    final r = await Rig.open();
    final (s, a, b) = (r.s, r.a, r.b);
    await a.authorSetup(_config, _accounts);
    await a.sync();
    await b.sync();
    expect(await b.device.integrityOk(_book), isTrue);

    final e = _moneyOut(a, 'E', 250, physicalMs: s.now);
    final recE = await a.author(e);
    s.run(untilMs: 100);
    final a1 = e.amendWith(
      newId: 'A1',
      hlc: a.device.nextHlc(s.now),
      lines: Verbs.moneyOut(
        from: _cash,
        forWhat: _kirana,
        amount: const Paise.rupees(300),
      ),
    );
    await a.author(a1);
    r.server.withheld.add(recE.envelopeId);
    await a.sync();

    final rb = await b.sync();
    expect(rb.pulled, 1);
    final row = (await b.device.envelopeRow('env-A1'))!;
    expect(row.held, 1);
    expect(row.heldFor, 'E');
    expect(
      await b.device.entryRow('A1'),
      isNull,
      reason: 'held = not projected',
    );
    expect(await b.device.balance(_cash.id) ?? 0, 0, reason: 'nothing counted');
    expect(await b.device.integrityOk(_book), isFalse);
    expect(await b.engine.status(), WaitingFor(a.id));

    r.server.withheld.clear();
    await b.engine.rebootstrapBook(_book);
    await b.sync();
    expect((await b.device.envelopeRow('env-A1'))!.held, 0);
    expect(await b.device.balance(_cash.id), -300 * 100, reason: 'once');
    expect((await b.device.entryRow('E'))!.supersededBy, 'A1');
    expect(await b.device.integrityOk(_book), isTrue);
    expect(await b.engine.status(), const Synced());
    expect(await b.device.dump(), await a.device.dump());
    await r.close();
  });

  test('D-05-13 two authors through a lossy network converge: dropped requests '
      'back off and retry, every entry lands once, dumps are identical, and the '
      'run replays from the network log', () async {
    Future<(String, int, List<Delivery>)> scenario(
      Network? net,
      NetworkModel? model,
    ) async {
      final r = await Rig.open();
      final (s, a, b) = (r.s, r.a, r.b);
      await a.authorSetup(_config, _accounts);
      await a.sync();
      await b.sync(); // bootstrap lossless (05 §8); then the line gets lossy
      a.setNetwork(network: net, model: model);
      b.setNetwork(network: net, model: model);
      for (var i = 0; i < 10; i++) {
        s.run(untilMs: s.now + 100);
        final by = i.isEven ? a : b;
        await by.author(
          _moneyOut(by, 'e$i', 10 + i, physicalMs: s.now, day: 1 + i),
        );
      }
      var rounds = 0;
      while (rounds++ < 60) {
        s.run(untilMs: s.now + 5000);
        await a.sync();
        await b.sync();
        if (await a.engine.status() == const Synced() &&
            await b.engine.status() == const Synced() &&
            await a.device.dump() == await b.device.dump()) {
          break;
        }
      }
      final dump = await a.device.dump();
      final decisions = (model?.log ?? (net! as ReplayNetwork).log).deliveries;
      await r.close();
      return (dump, rounds, decisions);
    }

    final model = NetworkModel(
      seed: 3,
      minDelayMs: 0,
      maxDelayMs: 1,
      dropRate: 0.3,
    );
    final (dump, rounds, decisions) = await scenario(null, model);
    expect(decisions.any((d) => d.dropped), isTrue, reason: 'seed must drop');
    expect(rounds, lessThan(60), reason: 'converged');
    final total = List.generate(
      10,
      (i) => 10 + i,
    ).fold<int>(0, (x, y) => x + y);
    expect(dump, contains('${-total * 100}'));

    final (dump2, rounds2, _) = await scenario(model.log.replay(), null);
    expect(dump2, dump);
    expect(rounds2, rounds);
  });
}
