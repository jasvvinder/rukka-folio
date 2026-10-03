# ADR 2026-10-03 — Server readings accepted as built

**Status:** accepted (owner-ruled, 3 Oct 2026, in one sitting, clearing PLAN desk 46, 49, 60, 61,
64, 71, 73, 78, 84, 86). Desk 48 / 62 is **not** ruled here and stays open. Desk 45 was ruled
later the same day and is recorded in *§ Desk 45* at the end; unlike §1–§10 it changes code.
**Amends:** 05 §5 (the meta channel no longer carries `recovery_blob`, §5 below) · 03 §6 (gains a
`seat_grants` retention line, §10 below) · 06 §7 and ADR 2026-09-05d §9, both owner-locked (an exception: an
admin's `membership_status` record can move a person with no invite into
`joined_pending_verification`, an edge 06 §7's state machine does not draw; §9 *Left as built*
below). **Ratifies:** `0018` · `0019` §3, §7 · `0020` · `0021` ·
`0022` · `0023` · `server/supabase/functions/_shared/otp/select.ts` · `sync-push/index.ts` ·
S12.4's no-date case · ADR 2026-09-24b §6 (completes it on the client). Everything else in those
documents stands.

## Context

Each item below was built by a server lane on the conservative reading and flagged `⚠️ SPEC` in the
file that holds it, because no doc settled it. The owner read the desk and accepted every one of
these readings **as built**. So §1–§10 change no code behaviour: no code, no migration and no
test moves for them. (*§ Desk 45* at the end, ruled later the same day, is the one exception: it
adds a migration, changes the edge and MemStore, and flips tests under ADR 2026-09-05i §4. It
carries its own consequences.) It writes the readings down where the docs can be held to them, and it makes the doc
edits the readings need. 05 §5 and 03 §6 described less than the server already does. 06 §7 and
ADR 2026-09-05d §9 promised more than it does: their only way into `joined_pending_verification`
is an accepted, phone-bound invite, and §9 below accepts a second one. Each of those two gains a
cross-reference line that names the exception, and neither one's own text changes.

Where a reading named an alternative (a stricter form, a shorter window, a wire change), that
alternative is **declined for now**. A later ADR can take it up again. Quotations are from the files
as they stand on 3 Oct 2026, with line numbers.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Dunning with a null `grace_until`: no countdown, and entry carries on (desk 46) ⟦tests: E-24b-2, F1-24b-5⟧
- **Server** (`_shared/entitlement.ts:99–108`, `graceUntilOf`): a dunning row whose
  `subscriptions.grace_until` is null is minted with `grace_until: null`. Only a hand edit makes
  such a row: *"0013 always writes the two together, so only a hand edit makes one … the server
  states what it holds"*. It never fills in `period_end + 7 d`, the derivation ADR 2026-09-24b §6
  forbids.
- **Client** (`s12_4_payment_problem_screen.dart:20–24`): *"never invent a date. The headline, what
  changes when the time is up, and both actions stay; the countdown line and the date line are
  simply not drawn."* Entry is unaffected. The grace blocks nothing, which is what a grace is.
- ADR 2026-09-24b §6 ruled what the server sends and left the client's dunning + null case open.
  This section closes it.

### 2. The plan-catalogue readings seeded in `0018` (desk 49) ⟦tests: E-03-77, E-03-79, E-25-3, G-25-3, G-25-4⟧
All five are in `server/supabase/migrations/0018_plan_catalogue.sql`. (a)–(c) are catalogue rows,
so changing one stays a data change (ADR 2026-09-25 §6). (d) and (e) are code.
- **(a) Trust's popular plan is `trust`** (0018:130–133): *"Trust's row bolds neither plan, yet
  'Family, Business and Trust have … a 30-day trial [that] always runs on the entity type's popular
  plan', so Trust needs one … with two plans the top one is the anchor, so `trust` (the lower) is
  popular."*
- **(b) No Individual plan is popular** (0018:133–134): *"Individual has no trial and no bolded
  plan, so neither of its rows is popular."*
- **(c) Quotas for the six new plans** (0018:123–127): *"no new plan is given less than 08 §2 gave
  its nearest predecessor: every plan below the top of its entity type (shop, business,
  family_lite, trust) takes the Family column (8 devices, 250 k envelopes/book, 5 GiB, 5 GiB), and
  every top plan (business_plus, trust_plus) takes the Family+ column (15, 1 M, 15 GiB, 20 GiB)."*
- **(d) A trial is fixed when it starts, and once per tenant as well as once per person**
  (0018:205–213). The plan is *"the entity type's popular row AT THE TIME the trial starts, written
  onto `subscriptions.plan`"*. Moving the popular flag later does not move a trial in flight. On
  top of ADR 2026-09-05g §12's once per person, *"a tenant that has already had a trial, a paid
  period or a gateway reference is refused (`trial_unavailable`)"*.
- **(e) Only the trust ⇔ organization link is checked** (0018:200–203). `rf.start_trial` notes
  that *"07 does not say which tenant type Myself / My shop / My businesses create, so family vs
  business vs individual is taken from the caller and only the trust link is checked"*. Billing
  activation (0018 §7, `rf.apply_billing_event`, 0018:269–278) checks only that the plan id is in
  the catalogue. An unknown id is recorded and not applied (`unknown_plan`). It does not check that
  the plan's entity type matches the tenant.

### 3. The seat-cap readings in `0019` §3 and §7 (desk 60) ⟦tests: E-05g-3, E-05g-6, E-05g-7, E-05g-9⟧
ADR 2026-09-05g §6 says *"distinct members per year"* and *"within 30 days"* without saying what
they key on. `0019_seat_and_book_caps.sql` §3 (0019:87–103) reads them so:
- **(a) "Per year" is rolling.** *"the trailing year from now(), never a calendar or financial
  year (the ADR says 'rolling'; a calendar year would hand out a second budget every 1 January)"*.
- **(b) A member is a person.** *"the user_id when the invitee has signed up, else the invite's
  invitee_hmac (joined through invite_id), so the same person invited before sign-up and accepted
  after is one member, not two"*.
- **(c) The 30-day re-invite exemption** spares only the rotation budget. It is measured from that
  person's last **counted** grant, so *"the exemption cannot be chained into a permanent free
  pass"*. It *"never bends the instantaneous seat cap: `members` seats are never exceeded by a new
  entry, whoever it is"*.
- **(d) An archived business book still counts** (0019 §7, 0019:257–260): *"Archiving is not
  deleting (the rows and the envelopes stay), 08 §3 counts the 'business-book count' without an
  exception"*.

### 4. Expired and refunded tenants keep their plan's caps (desk 61) ⟦tests: E-05g-12, E-05g-31 @M13⟧
- `rf.tenant_plan` (0019:53–56) is
  `coalesce((select s.plan from subscriptions s where s.tenant_id = p_tenant), 'free')`. It reads
  `subscriptions.plan` whatever the row's `status` or `dispute_state`. A tenant at `expired`, or
  refunded, therefore keeps its plan's seat, business-book and device caps. They do not drop to
  Free.
- The owner accepted this as built. ADR 2026-09-05g §5 (lapsed ≠ locked) stands unchanged, and so
  does the token's clamp of a lapsed `period_end` to `iat` (ADR 2026-09-24b §7 (a)).
- **What pins what.** E-05g-12 pins the resolver's formula (the subscription's plan, else
  `free`) and that all three caps read it. It does **not** pin this ruling: its fixture inserts
  `subscriptions (tenant_id, plan)` with no `status` (`seat_book_caps.test.ts:170`), so every row it
  reads is at 0004's default `active`, and a resolver that dropped an expired tenant to Free would
  leave it green. The ruling is pinned by **E-05g-31, planned (`@M13`) and not yet written**: a
  tenant at `status = 'expired'`, and one refunded (0013's `end_now`, `status = 'expired'` with
  `dispute_state` recorded, 0013:19–20), keeps its plan's seat, business-book and device caps (see
  *Open*).

### 5. `recovery_blob` leaves only by the step-4 route: the RS1 readings in `0020` (desk 64) ⟦tests: E-06-45, E-06-75, E-06-76, E-06-79, E-06-80, E-06-81⟧
Desk 64's letters are not `0020`'s: desk (a) is 0020's ⚠️ SPEC (d), desk (b) is its (a), desk (c)
is its (b), and desk (d) is its section 4.
- **(a) The meta channel never carries `recovery_blob`** (0020:115–126). *"Since this file, kind
  `recovery_blob` never travels that channel, to anyone. It leaves only through GET
  /sync-meta/recovery/shares (rf.recovery_shares), because the meta channel has no notion of an
  attempt's state and cannot hold back the 24 h wait of 04 §7.3 step 6"*. **05 §5 is amended to say
  so** (the cross-reference line under its list). 03 §2.5 (*"wrapped_keys: readable only by the
  subject"*) and ADR 2026-09-05d §2 (*"wrapped keys and shares addressed to it"*) are upper bounds.
  This stays inside them, and neither changes.
- **(b) No fetch deadline** (0020:92–99). An approved attempt's shares stay fetchable until
  `rf.sweep_recovery` (0010:547–560) removes its rows, 30 days after `expires_at`. That 30 days is
  the sweep's code and nothing more: 0010:545 and 0020:95–96 attribute it to 03 §6, and 03 §6 names
  no retention for recovery attempts (see *Open*). *"A second timer here would be an invented
  rule."* The seal bounds the exposure: only the phone holding the
  candidate secret can open the bytes, and ADR 2026-09-24b §1 zeroises that secret. A shorter
  window is declined for now.
- **(c) A suspended candidate device is withheld** (0020:100–103). `rf.has_guardian_set` (0016)
  still answers it its one yes/no bit. *"What this read gives away is the key to the user's
  vault."*
- **(d) `rf.recovery_derive` is restated** (0020:60–78). The effective ladder is `waiting_24h` when
  the attempt opened on it, or when the user has an active certified device other than the
  candidate now. It is *"never relaxed the other way"*. So `state` can go back to `waiting_24h`
  when the user regains a certified device. `opened_state` still reports the ladder the attempt
  opened on. **Clients key on `state` and `wait_until`, never on `opened_state`.** Desk 64 noted
  that the restated function was not re-reviewed in its own right. The owner accepted it as built,
  and E-06-80 (database) and E-06-81 (route) pin it.

### 6. The OTP2 readings in `_shared/otp/select.ts` (desk 71) ⟦tests: E-25-4, E-25-5, E-25-6, E-25-7, E-25-8, E-25-9⟧
The letters below are desk 71's, not the file's. The ⚠️ SPEC block in the header of
`server/supabase/functions/_shared/otp/select.ts:24–35` letters its own five readings (a)–(e).
Desk (a) is that block's (a) and (b) together, desk (b) is its (e), desk (c) is its (c), and desk
(e) is its (d). Desk (d) is not in that block: it is the file's opening lines (select.ts:9–10) and
`_shared/deps.ts:61–77` (`refusal` and `entry`).
- **(a) The project is named by the platform.** The fixed dev code needs `OTP_PROVIDER=fake`, plus
  `RF_DEV_PROJECT_REF` equal to the ref inside the platform-injected `SUPABASE_URL`, which
  operators cannot set. What remains is *"a person who deliberately writes the pilot's own ref
  into a variable named RF_DEV_PROJECT_REF on the pilot as well as setting OTP_PROVIDER=fake: two
  deliberate acts, not a mistype"*. The stricter form, pinning the dev ref in source, is declined
  for now.
- **(b) The hosted URL form is unverified.** *"`https://<20-char ref>.supabase.co` is taken from
  .env.example and is not verified against a live project. If it differs, a set switch refuses to
  start and the log says `otp_fixed_code_unbound`. That fails closed."* Confirming it on the first
  dev deploy stays an ops check.
- **(c) One fixed code for every number** on dev (`DEV_FIXED_OTP_CODE`, select.ts:60), *"since the
  fake delivers nothing and every tester needs some code"*. A third dev-only secret is declined.
  06 §2's attempt and rate limits still bind (E-25-8).
- **(d) A bad configuration answers 503** (select.ts:9–10, deps.ts:61–77). A bad `OTP_PROVIDER`
  makes every function answer `503 unconfigured`. A missing secret is `503` with
  `missing_env <NAME>` in the log, never a 500. The startup check logs `startup refused <reason>`
  (deps.ts:104).
- **(e) Local `supabase functions serve` can never issue the fixed code.** It injects
  `SUPABASE_URL=http://kong:8000`, which names no project.
- OTP3's hook stays `NOT_BUILT = {"2factor"}` (select.ts:81). E-25-5 flips when OTP3 builds it.

### 7. The CAPR readings in `0021` and the `/records` replay (desk 73) ⟦tests: E-05g-15, E-05g-16⟧
All three answers in (a) and (b) are the `if (duplicate)` branch of `postRecords` in
`sync-meta/index.ts`. They are cited by name, not line: desk 83 (M13-EDGE83) edits the same file
in the same round and moves its lines.
- **(a) A re-sent `/records` id whose stored record was never applied is asked again.** A plan that
  is still full answers the same `rejected:<name>`. Once there is room, the record applies and is
  acked. Returning the first outcome verbatim instead would need `_shared` to expose `apply_note`
  on a duplicate, and is declined for now. The same exposure is what a re-sent id whose record was
  refused **with a note** would need: today it replays as `acked` (the `stored.applied_at` arm,
  since a refusal's note is written by `markRecordApplied` too). That behaviour predates CAPR and
  is unchanged here (see *Open*).
- **(b) A re-sent id owned by another device** answers `rejected:shape` with check `id` (the arm
  that compares the stored record's `id` and `author_device`). Before this, it answered `acked`.
- **(c) One personal book per (tenant, owner)**, enforced by the unique partial index
  `books_one_personal_per_owner` (0021:26–32). A person in two tenants keeps a personal book in
  each. The alternative, one per owner across tenants, is declined.
- **(d) Ops:** 0021's pre-check refuses to apply on a hosted project that already holds duplicate
  personal books. Run the query from desk 73 (d) before applying it there.
- **(e)** The future book-create route maps 23505 on that index to a named 409 (for example
  `personal_book_exists`) beside `book_cap`. That route is desk 85, still unbuilt.

### 8. sync-push keeps `rejected:no_role` for every non-`fk` refusal (desk 78) ⟦tests: E-05g-17, E-05-4⟧
- `sync-push/index.ts:129–137`: a `StoreDenied` from the envelope insert answers
  `e.reason === "fk" ? "rejected:unknown_book" : "rejected:no_role"`. Any other reason folds into
  `no_role`, a named one or a `check` included. `/records` still passes the cap names through
  (`CAP_REFUSALS` in `sync-meta/index.ts`).
- Naming them on sync-push would be a wire change to 05 and `wire.dart`, and is declined. **No wire
  change.**

### 9. The SEC58 readings in `0022` (desk 84) ⟦tests: E-06-82, E-06-83, E-06-84, E-06-85, E-06-86, E-06-87, E-06-88, E-06-89, E-06-90, E-06-93, E-05g-5⟧
All are in the header of `0022_record_tenant_check.sql` (0022:65–103).
- **(a) Who may file:** *"a member at `active` or `joined_pending_verification`"*. `invited`,
  `blocked` and `removed` may not.
- **(b) The founder is first-come.** `tenants` (0001:59) records no creator, so *"the tenant has no
  member yet" is the only test the database can make*. It is narrowed to the caller's own
  `membership_status` at `active`, on a certified device, serialised per tenant. The creator column
  that would close it fully is a 03 §2.1 change, and is declined for now.
- **(c) Book roles need an admin of that book** (06 §1.0). When 0022 was written the edge asked
  only `isTenantAdmin`, so the database was the stricter of the two. Desk 83 (M13-EDGE83, the
  same round) moved the edge onto the same question: `applyRecord`'s `book_role` arm in
  `_shared/records.ts` decides from `rf.book_access` and needs `admin` on **that** book (E-06-93).
  The database stays the authority either way. Cited by name, not line, because that file is
  moving in the same round.
- **(d) A book's first role is its creator's own.** On a role-less, envelope-less book, the
  first role is the caller's own `admin` role.
- **(e) Device revocation** is bounded to *"the device's own user, or a guardian of that user in
  any share_set_version"*, inside a tenant where that user holds a membership other than
  `removed`. *"A guardian who shares no tenant with the subject can no longer complete a
  revocation through this projector."* The k-of-n count stays the edge's and the client's (ADR
  2026-09-06 §3).
- **Left as built, an exception to 06 §7 and ADR 2026-09-05d §9 (both owner-locked):** an admin can move a
  person to `joined_pending_verification` by a `membership_status` record, inside the seat cap,
  without an accepted, phone-bound invite. The person may have no membership row or be `removed`.
  06 §7's state machine draws one edge into that state, `invited ──install+OTP──▶`, and ADR
  2026-09-05d §9 makes the invite phone-bound. Both still hold for an **invite**: the link alone
  admits nobody. They do not bind this second edge. The code allows it in three places: the
  database's transition table (`rf.membership_transition_ok`, 0006:91–101, `-` and `removed` both
  reach `joined_pending_verification`), its guard (`rf.membership_guard`, 0006:123–133, demands a
  live invite only for `invited`), and the edge's mirror (`MEMBERSHIP_EDGES` in
  `_shared/records.ts`). Requiring an accepted invite for this edge is declined for now. 06 §7 and
  ADR 2026-09-05d §9 each gain a cross-reference line naming the exception, and their own text is
  unchanged. Two caveats. (1) E-05g-5 pins only part of it. It applies the record to a `removed`
  member once a seat is free, but for a person with no row it asserts only the refusal at a full
  plan. (2) 0006:123–124's comment, *"neither does an admin's bare assertion (ADR 2026-09-05d
  §9)"*, now says more than its code does (see *Open*).

### 10. The SWEEP readings: `seat_grants` is kept 1 year + 30 days (desk 86) ⟦tests: E-05g-27, E-05g-28, E-05g-29, E-05g-30⟧
- **(a) Retention.** `rf.sweep_seat_grants()` (`0023_seat_grants_sweep.sql`) deletes
  `granted_at < now() - interval '1 year 30 days'`. That is 30 days older than the longest window
  any reader uses: `rf.take_seat`'s trailing year, 0019:178–179. **03 §6 gains the line.** Before
  this, 03 §6 listed no retention for the table (0023:20–22).
- **(b) "Append-only" means no buy-back.** 0019 §8's comment, *"nobody can delete a grant to buy
  back rotation budget (append-only, CLAUDE.md rule 2's posture)"*, forbids deleting a row a reader
  still counts. It does not forbid retention past every reader's window (0023:11–19). The sweep
  takes no argument, so the maintenance role cannot choose a cutoff that hands budget back.
- **(c) Ops:** a daily `pg_cron` job runs `rf.sweep_seat_grants()` as `rf_maintenance`. Check that
  the hosted migration owner, which owns every SECURITY DEFINER function, has `BYPASSRLS`. Without
  it, every sweep deletes nothing and raises nothing, because every table is FORCE RLS (0005:271–278).
  The query is in `server/README.md` §5.
- **(d) The other sweeps:** `server/README.md` §5 now lists `rf.sweep_ceremony_sessions`,
  `rf.sweep_recovery_sheets` and `rf.sweep_recovery` with the cadence their code implies.

## Consequences
- **§1–§10: no test flips** and nothing is skipped (ADR 2026-09-05i §4 does not apply to them).
  Every doc edit they make describes behaviour the server already has. *§ Desk 45* is the
  exception: it changes behaviour, and its *Built in* and *Tests flipped* bullets say how. The tests that assert it are named in each marker,
  and where a marker is only partial (§4, §9 *Left as built*) the ruling says so.
- **Docs changed in this commit:**
  - 05 §5: the channel list and the *"New `wrapped_keys`"* bullet except `recovery_blob`, with a
    cross-reference line (§5).
  - 03 §6: a `seat_grants` retention sentence, with a cross-reference line (§10).
  - 06 §7 and ADR 2026-09-05d §9: one cross-reference line each, naming §9's exception. Neither
    one's own text changes.
  - Traceability markers for the 3 Oct ids: 06 §7 and §1.0, 03 §2.5, ADR 2026-09-05d §2 and ADR
    2026-09-05g §6 (PLAN desk 88).
  - `server/README.md` §5: the `pg_cron` cadences (§10 (d)) and the three ops checks below.
- **PLAN:** desk 46, 49, 60, 61, 64, 71, 73, 78, 84 and 86 close, and so does desk 45
  (*§ Desk 45*). Desk 85 (the book-create ADR)
  inherits §7 (e).
- **Ops carried to the deploy checklist** (`server/README.md` §5, each as its own item): §6 (b)
  confirm the hosted `SUPABASE_URL` form on the first dev deploy · §7 (d) the duplicate-personal-book
  query before 0021 on any hosted project · §10 (c) the daily `pg_cron` job, and the check that the
  owner of the SECURITY DEFINER functions has `BYPASSRLS`.

## Open ⚠️
- Desk 48 / 62 is not ruled here. (Desk 45 is: *§ Desk 45* below.)
- **0020's ⚠️ SPEC (c)** was not on desk 64 and is not ruled here: after a late certification, the
  re-checked wait runs from the k-th approval, not from certification (0020:104–114). A full 24 h
  from certification would need a server-stamped column, so a migration.
- **§4 has no test with `status = 'expired'`.** E-05g-12 pins the resolver, not the status.
  **E-05g-31** is reserved for it in §4's marker (`@M13`, planned, not yet written). A
  `lane-server` round writes it in `tests/rls/seat_book_caps.test.ts`: a tenant at
  `status = 'expired'`, and one at `expired` with `dispute_state` set (a refund), keeps its plan's
  seat, business-book and device caps. Once it lands, the `@M13` suffix comes off (check_coverage
  says so); if it has not landed when the gate runs `--strict --milestone M13`, the planned id fails.
- **§9's exception has two loose ends.** (1) No test applies an admin's `membership_status` record
  to a person with **no** membership row once a seat is free. E-05g-5 does it only for a `removed`
  member. (2) 0006:123–124's comment, *"neither does an admin's bare assertion (ADR 2026-09-05d
  §9)"*, says more than its code does: the guard demands an invite only for `invited`. 0006 is
  applied and is not edited. A later migration's header, or the next migration that touches
  `rf.membership_guard`, should correct it.
- **03 §6 names no retention for recovery attempts or superseded recovery sheets.** 03 §6 has no
  line for `recovery_requests`, `recovery_approvals`, `recovery_cancellations` or `recovery_sheets`
  (03 mentions them only in its schema, 03:85). Yet 0010:545 (*"03 §6: closed attempts and their
  rows go 30 days after the attempt's window ended"*) and 0020:95–96 (*"03 §6: 30 days after
  `expires_at`"*) both cite a 03 §6 rule. So the 30 days of §5 (b), and the 30 days of
  `rf.sweep_recovery_sheets`, live only in code. The owner accepted §5 (b) as built, and that does
  not write the 03 §6 line. A later ADR should add it to 03 §6, with the two migration comments
  then citing it. (`ceremony_sessions` is covered: 03 §2.2, 03:78, *"swept a day past expiry"*.)
- **§7 (a)'s neighbour:** a re-sent `/records` id whose record was refused with a note
  (`rejected:shape`, `rejected:unauthorized`, …) replays as `acked`. That predates CAPR and is
  unchanged by this ADR, and ADR 2026-09-05b §7 says *never a silent drop*. Fixing it needs the
  same `apply_note` exposure as §7 (a)'s alternative.
- **`rf.sweep_recovery_sheets` measures from the superseded sheet's own `created_at`**
  (0011:136–145). Its comment says *"30 days after they were replaced"*. A sheet older than 30 days
  is therefore swept at the first run after it is replaced. 04 §7.4 already invalidates the old
  sheet on regeneration, so nothing is exposed, but the code and its comment disagree.
  `server/README.md` §5 states what the code does.
- **`recovery_blob` rows have no retention path.** `rf.sweep_recovery` (0010:547–560) deletes an
  attempt's approvals, cancellations and request, but not the `wrapped_keys` rows of kind
  `recovery_blob` the approvals pointed at. `rf.purge_ephemeral_auth` (0004:169) deletes only
  revoked wrapped keys, and such a row is revoked only when its candidate device is. The shares stay
  stored, unreferenced, and unreadable: they are sealed to a zeroised candidate key, and 0020
  withholds them from every read. 03 §6 names no retention for them. Fixing it needs a migration,
  in a `lane-server` round (`server/README.md` §6).

## Desk 45 — `rf.has_guardian_set` refuses a caller it cannot answer, never `false` (owner, 3 Oct 2026) 🔒 ⟦tests: E-24b-3, E-24b-4, F1-24b-18, E-24b-1⟧
`0016_has_guardian_set.sql:42–58` took three readings of ADR 2026-09-24b §3 and asked the owner
about the second: *"(b) A REVOKED device (or a device claim that is not the caller user's) reads
FALSE, a constant, rather than a refusal … Owner: a refusal instead?"* (0016:50–53).
- **(b) is ruled the other way: refuse.** When the caller's device claim is not a live device of
  the caller's own user (a revoked phone, a device claim that is another user's, no device claim)
  or that user is erased, `rf.has_guardian_set()` **raises** instead of answering `false`. As
  built, the client rendered that `false` as rung 2's `noTrustedMembers`: a revoked phone reaching
  S11.6 was told *you set nobody up* even when members held its shares. 04 §7.3 🔒 forbids that
  false denial (and ADR 2026-09-24b §4 exists to prevent it).
- **One refusal, no new oracle.** The database raises `unknown_candidate_device` with errcode
  42501, the name and code 0010's rung-2 open already raises for the same caller
  (`rf.recovery_request_guard`). It is raised before the set is read, with one message, detail and
  hint, so it is identical for revoked, foreign, missing-claim, unknown-user and erased callers,
  and identical whether or not the user holds a set (E-24b-3 compares the whole error). The
  refusal tells the caller nothing a `false` did not.
- **On the wire it is an existing answer:** `GET /sync-meta/recovery/has-guardian-set` maps it
  through `recoveryError` in `sync-meta/index.ts` (cited by name) to **403 `unknown_request`**.
  For a revoked or foreign caller, that is byte-for-byte what `POST /sync-meta/recovery` answers
  (E-24b-4). **No new wire result.** The app needs no behaviour change: `HttpGuardiansApi._send` turns any
  non-2xx into a `RecoveryApiFailure`, and `trustedMembersProbe` reads every failure of the bit as
  `unknown` (F1-24b-18, with its twin: `200 false` is still `noTrustedMembers`). MemStore refuses
  by the same name.
- **(a) and (c) stand as built.** (a) A published set short of n members reads `true`. (c) A
  suspended device is answered, because `rf.device_live_for`, the predicate the open uses, counts
  it as live (and §5 (c) above already records that `rf.recovery_shares` withholds it). E-24b-1
  keeps pinning both.
- **Built in** `0025_has_guardian_set_refuses.sql`, append-only (0016 is not edited). It keeps
  0016's shape: no argument, a boolean return, STABLE, SECURITY DEFINER, 0024's
  `search_path = public, pg_temp`, and EXECUTE for rf_api only. A live device of a live user with
  no current set still reads `false`.
- **Tests flipped (ADR 2026-09-05i §4).** The E-24b-1 arms that asserted `false` for a revoked,
  foreign, missing-claim, unknown-user or erased caller are removed from E-24b-1, in
  `tests/rls/has_guardian_set.test.ts` and in `functions/_tests/has_guardian_set.test.ts`. They
  re-land in the same change, inverted, as E-24b-3 (the refusal) and E-24b-4 (parity with the
  open under the refusal). Nothing is left green against reading (b).
- **MemStore's open reads liveness as the database does.** `MemStore.openRecovery` refused only
  `status = 'revoked'`. `rf.device_live_for` (0010), which the bit and the open both use in
  Postgres, also refuses a device whose `revoked_at` is stamped before its status moves. The
  mirror now checks both, and E-24b-4 pins that device in both test files. This is a test-double
  fix, not a ruling: PgStore was already right.
- **Two texts still described reading (b) when 0025 was built:** the has-guardian-set row in
  `server/README.md` §2 (*"`false` for a revoked device, a device that is not the caller's, an
  erased user, or no set"*) and the ⚠️ SPEC (desk 45) comment on `trustedMembersProbe` in
  `app/lib/shared/sync/recovery_ladder_source.dart:277–281`. Each must state the refusal:
  403 `unknown_request` for those callers, which the app reads as `unknown`, and `false` only for
  a live caller with no current set. Both are text, not behaviour.
- **Still stricter than the open for an erased user.** 0010's guard does not check erasure
  (0016:33–37). The bit now refuses an erased caller and the open does not; that asymmetry
  predates this ruling and is unchanged.
