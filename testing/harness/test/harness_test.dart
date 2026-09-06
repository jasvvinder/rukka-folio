// Suite D — harness self-tests (09 §1 "two-client harness"; ADR 2026-09-05i §7).
// The rig must be deterministic before any device or server is wired into it at M4.
@Tags(['D'])
library;

import 'dart:convert';

import 'package:harness/harness.dart';
import 'package:test/test.dart';

/// Drives [n] messages between two devices through [net] and returns the arrival trace.
List<String> runScenario(Scheduler s, Network net, int n) {
  final arrivals = <String>[];
  for (var i = 0; i < n; i++) {
    final from = i.isEven ? 'phone-a' : 'phone-b';
    final to = i.isEven ? 'phone-b' : 'phone-a';
    s.at(i * 100, 'send $i', (s) {
      net.send(
        s,
        from: from,
        to: to,
        label: 'env-$i',
        onArrive: (s, d) => arrivals.add('${s.now} ${d.label}'),
      );
    });
  }
  s.run();
  return arrivals;
}

void main() {
  group('scheduler', () {
    test('D-09-4 events run in (at, seq) order; equal instants keep insertion order; '
        'cancel removes; run(untilMs) leaves later events queued', () {
      final s = Scheduler();
      final order = <String>[];
      s.at(50, 'b', (_) => order.add('b'));
      s.at(10, 'a1', (_) => order.add('a1'));
      s.at(10, 'a2', (_) => order.add('a2'));
      final c = s.at(30, 'cancelled', (_) => order.add('never'));
      s.at(500, 'late', (_) => order.add('late'));
      expect(s.cancel(c), isTrue);
      expect(s.cancel(c), isFalse);
      expect(s.run(untilMs: 100), 3);
      expect(order, ['a1', 'a2', 'b']);
      expect(s.now, 100, reason: 'time advances to untilMs');
      expect(s.pending, 1);
      s.run();
      expect(order.last, 'late');
      expect(s.now, 500);
      expect(s.trace, ['10 a1', '10 a2', '50 b', '500 late']);
    });
  });

  group('seeded network', () {
    test('D-09-1 the same seed yields the same log and the same arrival order; '
        'a different seed reorders differently', () {
      List<String> run(int seed) => runScenario(
        Scheduler(),
        NetworkModel(seed: seed, minDelayMs: 0, maxDelayMs: 5000),
        40,
      );
      final a = runScenario(
        Scheduler(),
        NetworkModel(seed: 20260906, minDelayMs: 0, maxDelayMs: 5000),
        40,
      );
      expect(run(20260906), a);
      expect(run(20260906), a, reason: 'no hidden clock or global RNG');
      expect(run(7), isNot(a), reason: 'seed 7 must produce a different order');
      // Reordering actually happens: with delays up to 5 s over 100 ms send gaps,
      // some later message overtakes an earlier one.
      final labels = a.map((e) => e.split(' ').last).toList();
      expect(labels, isNot(List.generate(40, (i) => 'env-$i')));
      expect(labels.toSet().length, 40, reason: 'lossless when dropRate is 0');
    });

    test('D-09-2 a run replays byte-for-byte from its log without the generator, '
        'and a drifted scenario is refused', () {
      final model = NetworkModel(
        seed: 99,
        minDelayMs: 10,
        maxDelayMs: 3000,
        dropRate: 0.2,
      );
      final live = runScenario(Scheduler(), model, 30);
      final json = jsonEncode(model.log.toJson());
      final restored = NetworkLog.fromJson(
        jsonDecode(json) as Map<String, Object?>,
      );
      expect(restored.seed, 99);
      expect(restored.deliveries.length, 30);
      expect(restored.deliveries.where((d) => d.dropped), isNotEmpty);
      expect(live.length, lessThan(30), reason: 'drops happened');

      final replayed = runScenario(Scheduler(), restored.replay(), 30);
      expect(replayed, live);

      // The same log against a scenario that sends one message more → refused.
      expect(
        () => runScenario(Scheduler(), restored.replay(), 31),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('replay exhausted'),
          ),
        ),
      );
      // …or a scenario whose labels differ → refused at the first drift.
      final r = restored.replay();
      expect(
        () => r.decide(from: 'phone-a', to: 'phone-b', label: 'other', now: 0),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('replay drift'),
          ),
        ),
      );
    });

    test('D-09-3 an offline window holds messages: nothing reaches an offline '
        'receiver until it reconnects, and an offline sender queues until its window ends', () {
      final net = NetworkModel(
        seed: 1,
        minDelayMs: 10,
        maxDelayMs: 100,
        offline: const [
          OfflineWindow('phone-b', 0, 10000), // receiver dark for 10 s
          OfflineWindow('phone-a', 20000, 30000), // sender dark 20–30 s
        ],
      );
      expect(net.isOffline('phone-b', 5000), isTrue);
      expect(net.isOffline('phone-b', 10001), isFalse);

      final s = Scheduler();
      final arrivals = <String>[];
      void arrive(Scheduler s, Delivery d) =>
          arrivals.add('${s.now} ${d.label}');
      for (var i = 0; i < 5; i++) {
        s.at(i * 1000, 'send $i', (s) {
          net.send(
            s,
            from: 'phone-a',
            to: 'phone-b',
            label: 'early-$i',
            onArrive: arrive,
          );
        });
      }
      s.at(25000, 'send while offline', (s) {
        net.send(
          s,
          from: 'phone-a',
          to: 'phone-b',
          label: 'queued',
          onArrive: arrive,
        );
      });
      s.run();

      final early = arrivals.where((a) => a.contains('early')).toList();
      expect(early.length, 5);
      for (final a in early) {
        final t = int.parse(a.split(' ').first);
        expect(t, greaterThan(10000), reason: 'held until phone-b reconnects');
        expect(t, lessThanOrEqualTo(10001 + 100));
      }
      final queued = arrivals.singleWhere((a) => a.endsWith('queued'));
      final t = int.parse(queued.split(' ').first);
      expect(t, greaterThan(30000), reason: 'sender offline until 30 s');
      expect(t, lessThanOrEqualTo(30001 + 100));
      // The log records the decision relative to the real send instant.
      expect(net.log.deliveries.last.sentAt, 25000);
      expect(net.log.deliveries.last.arrivesAt, t);
    });

    test('D-09-5 the model rejects impossible parameters', () {
      expect(
        () => NetworkModel(seed: 1, minDelayMs: 5, maxDelayMs: 1),
        throwsArgumentError,
      );
      expect(() => NetworkModel(seed: 1, dropRate: 1), throwsArgumentError);
      expect(() => Scheduler().at(-1, 'x', (_) {}), throwsArgumentError);
    });
  });
}
