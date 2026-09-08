/// Two-client test rig (09 §1 "two-client harness", ADR 2026-09-05i §7).
///
/// M2 lands the deterministic core: a discrete-event [Scheduler] with a virtual clock, a
/// seeded [NetworkModel] that decides delay, reordering and drops per message, a
/// [NetworkLog] that records every decision so a failing run **replays from its seed or its
/// log** — never from wall-clock luck — and [SimulatedDevice], the real `packages/data`
/// stack per phone behind a content-blind [Relay] that stands in for the server. The
/// in-memory server and sync engine join at M4 (05); the hostile-envelope fixture at M3/M4.
///
/// Pure Dart. `dart:math` is allowed here (this is not a `core_*` package) but every random
/// choice flows from one injected seed, and no code path reads the wall clock.
library;

export 'src/device.dart';
export 'src/network.dart';
export 'src/scheduler.dart';
export 'src/synced_device.dart';
