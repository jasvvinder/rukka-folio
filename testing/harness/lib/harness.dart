/// Two-client test rig (09 §1 "two-client harness", ADR 2026-09-05i §7).
///
/// M2 lands the deterministic core: a discrete-event [Scheduler] with a virtual clock, a
/// seeded [NetworkModel] that decides delay, reordering and drops per message, and a
/// [NetworkLog] that records every decision so a failing run **replays from its seed or its
/// log** — never from wall-clock luck. Simulated devices and the in-memory server join at M4
/// (sync_engine, 05); the hostile-envelope fixture at M3/M4.
///
/// Pure Dart. `dart:math` is allowed here (this is not a `core_*` package) but every random
/// choice flows from one injected seed, and no code path reads the wall clock.
library;

export 'src/network.dart';
export 'src/scheduler.dart';
