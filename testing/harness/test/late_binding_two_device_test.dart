// Suite D — late-bound identity on the two-client rig (ADR 2026-10-09 §1 🔒;
// PLAN desks 126, 168). One phone is registered from the start; the other is
// built before S0.2, as the composition root now builds it, and is told who it
// is only when its source answers. Everything runs on the scheduler's virtual
// clock against the in-memory server.
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

Entry _moneyOut(
  SyncedDevice by,
  String id,
  int rupees, {
  required int physicalMs,
}) => Entry(
  id: id,
  bookId: _book,
  kind: EntryKind.moneyOut,
  status: EntryStatus.posted,
  reviewRequired: false,
  accountingDate: LocalDate(2026, 4, 5),
  lines: Verbs.moneyOut(
    from: _cash,
    forWhat: _kirana,
    amount: Paise.rupees(rupees),
  ),
  createdByUser: 'ramesh',
  createdByDevice: by.id,
  hlc: by.device.nextHlc(physicalMs),
);

void main() {
  test('D-1009-1 two clients: a phone built before S0.2 makes no request at '
      'all while the other phone keeps entering; the moment its source answers '
      '(registration) the same engine — no rebuild — pulls every entry, its '
      'projection is identical to the other phone\'s, and its own first entry '
      'reaches the other phone once', () async {
    final s = Scheduler();
    final server = FakeSyncServer(
      clock: SchedulerClock(s),
      rateLimits: RateLimits.none,
    );
    final b = await SyncedDevice.open(
      'phone-b',
      server: server,
      scheduler: s,
      userId: 'u-b',
      books: {_book},
    );
    final identity = ManualIdentity(); // not registered yet
    final a = await SyncedDevice.open(
      'phone-a',
      server: server,
      scheduler: s,
      identity: identity,
      books: {_book},
    );
    addTearDown(() async {
      await a.close();
      await b.close();
    });

    await b.authorSetup(_config, [_cash, _kirana]);
    await b.author(_moneyOut(b, 'E1', 250, physicalMs: s.now));
    await b.sync();
    s.run(untilMs: 60 * 1000);

    final held = await a.sync();
    expect(held.held, SyncHold.notRegistered);
    expect(a.transport.calls, isEmpty, reason: 'not one request before S0.2');
    expect(await a.device.balance(_cash.id), isNull);
    expect(
      a.engine.events.whereType<SyncHeld>().single.reason,
      SyncHold.notRegistered,
    );

    // b keeps working meanwhile.
    s.run(untilMs: 2 * 60 * 1000);
    await b.author(_moneyOut(b, 'E2', 100, physicalMs: s.now));
    await b.sync();
    expect((await a.sync()).held, SyncHold.notRegistered);
    expect(a.transport.calls, isEmpty);

    // S0.2: the ledger mints the keys and the source starts answering.
    final engine = a.engine;
    identity.identity = const RegisteredIdentity(
      deviceId: 'phone-a',
      userId: 'u-a',
      tenantId: 't1',
    );
    s.run(untilMs: 3 * 60 * 1000);
    final r = await a.sync();
    expect(identical(a.engine, engine), isTrue);
    expect(r.held, isNull);
    expect(r.quarantined, 0);
    expect(await a.device.balance(_cash.id), -350 * 100);
    expect(await a.device.integrityOk(_book), isTrue);
    expect(await a.device.dump(), await b.device.dump());
    expect(await a.engine.status(), const Synced());

    // Its own first entry, authored after registration, reaches b once.
    s.run(untilMs: 4 * 60 * 1000);
    await a.author(_moneyOut(a, 'A1', 50, physicalMs: s.now));
    await a.sync();
    await b.sync();
    expect(await b.device.balance(_cash.id), -400 * 100);
    expect(await a.device.dump(), await b.device.dump());
    expect(
      server.stored.where((e) => e.authorDevice == 'phone-a'),
      hasLength(1),
    );
    expect(a.engine.events.whereType<IdentityRebound>(), isEmpty);
    expect(a.engine.events.whereType<Quarantined>(), isEmpty);
    expect(a.engine.events.whereType<SyncHeld>(), hasLength(1));
  });
}
