// The dunning countdown (S12.4; 08 §3 🔒, ADR 2026-09-05g §4 🔒, ADR
// 2026-09-24b §6 🔒) as a pure function of (`grace_until`, now).
//
// 🔒 **The end date is the server's, never derived** (ADR 2026-09-24b §6,
// amending 08 §3 and ADR 2026-09-05g §1). The token declares `grace_until`;
// the client reads it and never computes `period_end + 7 d`. The 7 days remain
// the gateway default the *server* writes — a store-run channel may carry its
// own grace length, which is why the server declares the date. So there is no
// grace duration in this app at all: the constant that used to live here
// (`rkDunningGrace`) is gone, not kept unused.
//
// 🔒 **The clock is injected, never read.** ADR 2026-09-05g §4's floor —
// `max(local clock, highest server timestamp seen)` — is the *server's* rule;
// this function takes whatever `now` its caller was handed and no widget in
// this feature calls `DateTime.now()`. A screen that worked a lapse out from
// the phone's clock would be the defect that ADR forbids.
//
// 🔒 **Dunning only.** Offline grace never reaches this file: it is
// device-local, it has no countdown, and its copy never says a plan ended
// (07 §20 — two graces, two copies). Which reading has a date to count is
// [Entitlement.dunningGraceUntil]'s call, not this file's.
library;

/// Whole days left of the dunning grace at [now], never negative.
///
/// [graceUntil] is the token's `grace_until` — the date the server declared
/// (ADR 2026-09-24b §6 🔒). A caller with no such date has no countdown to
/// show and must not call this with a made-up one.
///
/// **Truncated, never rounded up**: a part-day reads as the smaller number, so
/// the screen can only ever understate the time left. Overstating it would be
/// telling someone they have two days when entry stops tomorrow, which 07 §1
/// rule 12 (say what is true, and what to do) does not allow.
int rkDunningDaysLeft({required DateTime graceUntil, required DateTime now}) {
  final left = graceUntil.difference(now);
  return left.isNegative ? 0 : left.inDays;
}
