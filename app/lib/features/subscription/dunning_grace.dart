// The dunning countdown (S12.4; 08 §3 🔒, ADR 2026-09-05g §4 🔒) as a pure
// function of (`period_end`, now).
//
// 🔒 **Seven days from `period_end`, tenant-wide** — 08 §3's figure, written
// once, here. The screen counts nothing itself.
//
// 🔒 **The clock is injected, never read.** ADR 2026-09-05g §4's floor —
// `max(local clock, highest server timestamp seen)` — is the *server's* rule;
// this function takes whatever `now` its caller was handed and no widget in
// this feature calls `DateTime.now()`. A screen that worked a lapse out from
// the phone's clock would be the defect that ADR forbids.
//
// 🔒 **Dunning only.** Offline grace never reaches this file: it is
// device-local, it has no countdown, and its copy never says a plan ended
// (07 §20 — two graces, two copies).
library;

/// The dunning grace window: 7 days from `period_end` (08 §3 🔒).
const Duration rkDunningGrace = Duration(days: 7);

/// When the dunning grace ends — `period_end` plus [rkDunningGrace].
DateTime rkDunningEndsAt(DateTime periodEnd) => periodEnd.add(rkDunningGrace);

/// Whole days left of the dunning grace at [now], never negative.
///
/// **Truncated, never rounded up**: a part-day reads as the smaller number, so
/// the screen can only ever understate the time left. Overstating it would be
/// telling someone they have two days when entry stops tomorrow, which 07 §1
/// rule 12 (say what is true, and what to do) does not allow.
int rkDunningDaysLeft({required DateTime periodEnd, required DateTime now}) {
  final left = rkDunningEndsAt(periodEnd).difference(now);
  return left.isNegative ? 0 : left.inDays;
}
