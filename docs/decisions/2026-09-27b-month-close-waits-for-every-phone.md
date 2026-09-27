# ADR 2026-09-27b — a month closes only when every writing phone has reported in

**Status:** accepted (owner-ruled, 27 Sep 2026; §2 tightened the same day: *"close only once confirmed every one has closed"*, so there is no Close anyway)
**Amends:** 02 §8 step 3 (close preconditions) · 03 `object_type` registry (adds `sync_mark`) · 05 §7 (a nudge)
· 07 §13 and §17 · 13 S10.5 · ADR 2026-09-27 §1 (late arrivals now block exports). **Extends, does not replace:**
ADR 2026-09-05b §3 and ADR 2026-09-05e §4. A gap or a `held` envelope still blocks the lock outright.

## Context

The per-author sequence (ADR 2026-09-05b §3) catches an entry missing *between* two that arrived. It cannot
catch entries still on an offline phone after its last sync. Suppose Ramesh's phone last pushed #12, and #13 (a
₹2,400 diesel entry dated 28 Aug) waits in its outbox. Readers see no gap, August locks on 31 Aug, and #13 lands
on 2 Sep as a late arrival (02 §8). It counts live but not in the certified month, so a printed August statement
disagrees with the August close. On 27 Sep 2026 the owner asked that a month not close until every
collaborator's entries are in. Two alternatives were weighed: showing the closer each phone's last sync, which
cannot tell whether entries are pending, and a manual close by every collaborator, which is a monthly chore and
blocks forever on an absent phone. The owner ruled for automatic per-phone reports and a lock that waits for all of them,
with no override. Exports are held back while a late arrival is unresolved.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Every phone reports "clear" automatically ⟦tests: A-27b-1 @M12, D-27b-1 @M12, D-27b-2 @M12, E-27b-1 @M12⟧
- **Clear for a period.** Device *D* is *clear for period P* of a book when a reader holds D's envelopes in that
  book as an unbroken run 1…N of `author_seq`, and envelope N's HLC is **on or after the first day after P**.
  A device's `author_seq` rises with time, so nothing D wrote before that moment can still be missing.
- **Any envelope proves it.** An ordinary entry D writes after P ends makes D clear. A phone that has written
  nothing in the book since P ended emits a **`sync_mark`** on its next successful sync. This is a new
  `object_type` that carries no financial content. It is signed and encrypted like every envelope, with
  `author_seq` inside the payload (ADR 2026-09-05b §3), so the server can neither forge nor withhold it
  unseen. The projector ignores it. At most one is emitted per device, per book, per period.
- **Who must be clear:** every non-revoked device, certified **before P ended**, belonging to a member whose
  role in the book can write (Admin, Head, Member, Operator). Viewers, removed members, revoked phones and members
  not yet verified in person are not listed, because none of them can write to the book.

### 2. The lock waits for every writing phone, with no override ⟦tests: A-27b-2 @M12, A-27b-3 @M12, F1-27b-1 @M12, F1-27b-2 @M12, F1-27b-3 @M12⟧
- **New precondition in 02 §8 step 3.** P cannot lock until every device listed under §1 is clear for P. There
  is **no Close anyway**, and no role, including Admin, can lock past an unconfirmed phone.
- **S10.5 lists each writing phone:** ✓ *Sunita's phone — all in*, or ⏳ *Ramesh's phone — last heard from
  29 Aug*. Each ⏳ row has **Nudge**, which sends that phone a content-free push (04 §4 generic text: *"Open Rukka
  Folio to finish syncing"*) that prompts a pull and a push (05 §7). A push is a hint and never a dependency.
- **A phone that will never report back** (lost, broken, a member who has left) is resolved through membership,
  never through the close. The admin **revokes the device** (06 §6, *"This phone was stolen"*) or removes the
  member. Once revoked, the phone is no longer listed under §1, and the lock can proceed. S10.5 offers that
  route on every ⏳ row, after Nudge, so the screen is never a dead end (07 §1). Its consequence is stated before
  confirming: *"Entries still on this phone will never reach the book."*
- A gap or a `held` envelope still blocks the lock outright (ADR 2026-09-05e §4).
- The year close inherits this through its precondition that every month is locked (02 §8.1). No separate rule.

### 3. An unresolved late arrival blocks exports of its period ⟦tests: F1-27b-4 @M12, F1-27b-5 @M12⟧
- **Extends ADR 2026-09-27 §1.** A report or statement is not generated or exported while a late arrival whose
  `accounting_date` falls in the report's own books and period is still in the Late arrivals tray, meaning it has
  been neither re-dated nor absorbed by a re-open. The export row is disabled-with-reason and opens the tray
  (S10.3).
- *Export everything* stays exempt (ADR 2026-09-27 §2; 08 §4).

## Consequences
- **Code:**
  - `packages/core_ledger`: a pure clearance function over the device roster, the received `(author_seq, hlc)`
    runs and the period, feeding the lock precondition.
  - `packages/data`: `payload_codec.dart` gains `sync_mark`.
  - `packages/sync_engine`: emits `sync_mark` after a drained push, and on the first sync of a new period.
  - `server/supabase`: a migration extends the `object_type` check (`0003_envelope_store.sql:21`), plus
    `_shared/registry.ts` and a rate-limited, membership-checked nudge route.
  - `app`: S10/S10.5 phone list with Nudge and the revoke route, and the ADR 2026-09-27
    export gate extended to late arrivals.
- **Tests:** not checked here. Any green test that locks a month while another writing device has sent nothing
  dated after the month ended will fail under §2. The lane owning it adds a `sync_mark` to the fixture, or marks
  it `@Skip` per ADR 2026-09-05i §4 in the same commit.
- **Docs:** cross-reference lines at 02 §8, 03 registry, 05 §7, 07 §13, 07 §17, 13 S10.5, and ADR 2026-09-27 Open.
- **Milestone:** PLAN places it. It spans lane-sync, lane-server (both xhigh), core_ledger and lane-ui.

## Open ⚠️
- **"The first day after P"** uses each device's HLC, which the clock clamp bounds (05 §1). A phone whose clock
  runs days slow could look clear late or never. It is handled like any unconfirmed phone: Nudge, and fix the clock, or revoke
  it. No new mechanism.
