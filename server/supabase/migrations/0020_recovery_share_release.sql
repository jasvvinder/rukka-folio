-- 0020 — recovery step 4, the server half: release the re-sealed shares to the phone that asked,
-- and only once the attempt is approved.
-- 04 §7.3 🔒 (steps 3, 4, 6, 7), ADR 2026-09-05d §1 🔒 (24 h wait + one-tap Cancel) and §2 🔒
-- (uncertified devices), ADR 2026-09-13c §3, ADR 2026-09-24b §1 and §3, 06 §5 and §10, 03 §2.2/§2.5.
-- ⟦tests: E-06-70, E-06-71, E-06-72, E-06-73, E-06-74, E-06-75, E-06-76, E-06-77, E-06-78, E-06-79,
--         E-06-80, E-06-81⟧
--
-- ============================================================================================
-- WHAT WAS MISSING, AND WHAT WAS OPEN
-- ============================================================================================
-- 0010 lets a guardian file its share re-sealed to the attempt's candidate key
-- (`rf.recovery_decide` → `wrapped_keys` kind `recovery_blob`, addressed to the subject's user and
-- the candidate DEVICE). Nothing released those shares on purpose. They left anyway, through
-- 0005's `wrapped_keys_select` (`user_id = rf.user_id() and (device_id = rf.device_id() or
-- rf.is_certified())`), which sync-meta's meta pull pages as it stands. So:
--   * the candidate phone received each share THE MOMENT ITS GUARDIAN APPROVED. That was before k,
--     and inside the 24 h wait. 04 §7.3 step 6 🔒: "If the user still has an active certified
--     device, steps 4–6 wait 24 h behind a one-tap Cancel". 06 §10: "then nothing decrypts for 24 h,
--     the active device shows Cancel". The wait was enforced on the state the server REPORTED
--     (rf.recovery_derive) and not on the bytes it SERVED. A phone holding k shares reconstructs
--     UMK_priv with no further help from anyone (step 4), so a wait that does not withhold the
--     shares is only advice;
--   * every CERTIFIED device of the subject user received them too (the `or rf.is_certified()`
--     arm). They are sealed to a key only the candidate holds, so this was noise rather than a
--     break. It is still not "addressed to" anyone but the candidate (ADR 2026-09-05d §2).
--
-- ============================================================================================
-- THE SHAPE
-- ============================================================================================
-- 1. Two RESTRICTIVE policies take `recovery_blob` rows out of rf_api's reach on the table: no
--    SELECT (so neither a direct read nor the meta pull serves one) and no INSERT (so the only
--    writer stays `rf.recovery_decide`, a SECURITY DEFINER function, as 0010 intended). A
--    restrictive policy can only NARROW what the permissive policies grant. 0005's policies, every
--    other wrapped-key kind and the maintenance role's retention path are untouched.
-- 2. `rf.recovery_shares(request)` is the one way out, SECURITY DEFINER with search_path pinned,
--    EXECUTE for rf_api alone. It returns the shares of THAT attempt when all of these hold:
--      WHO   — the caller is the one that OPENED it: `user_id = rf.user_id()` AND
--              `candidate_device = rf.device_id()`, the claim pair 0005's `recovery_requests_insert`
--              bound into the row. The caller is uncertified by construction (06 §5 "New phone, no
--              old device"). It is authenticated exactly as the rung-2 open and the has-guardian-set
--              read (0016, ADR 2026-09-24b §3) authenticate it: our 15-minute JWT {user_id,
--              device_id} (06 §4), minted only after the device signs `nonce ‖ device_id ‖ unix_ts`
--              with the Ed25519 key registered for that device id. Certification is deliberately
--              NOT required, and not refused either: the candidate is certified only after step 6.
--              The device must still be LIVE (rf.device_live_for: not revoked, `revoked_at` null)
--              and NOT SUSPENDED, and the user not erased (06 §9.3; 0016's parity).
--      WHAT  — only rows reached through THIS attempt's own append-only decisions (0010
--              `recovery_approvals`, decision 'approved'). They must be declared sealed to THIS
--              attempt's `candidate_pub_x` and pinned to its `share_set_version`, with each
--              `wrapped_keys` row of kind `recovery_blob` addressed to the attempt's user and
--              candidate device and not revoked. It is never "every recovery_blob addressed to my
--              device": one phone may hold several live attempts (0010 allows five), and all their
--              shares are addressed to the same device id.
--      WHEN  — `rf.recovery_derive(request).state = 'approved'`, the single derivation 0010 made
--              the source of every state a client acts on. That is: k approvals, the 24 h wait
--              run out when the attempt opened on the waiting_24h ladder (measured from the k-th
--              approval), no cancellation, and not closed by three denials or by 72 h with fewer
--              than k. The release and the progress read therefore never disagree: the phone is
--              never told `approved` by one read and refused by the next.
-- 4. The 24 h question is asked AGAIN WHEN THE SHARES LEAVE, not only when the attempt opened.
--    0010 writes the ladder once, at INSERT (`recovery_requests.state`, from
--    rf.has_other_active_device), and no UPDATE can move it. ADR 2026-09-05d §1 🔒 ("complete
--    immediately only when the user has no active certified device") and 04 §7.3 step 6 🔒 ("If the
--    user still has an active certified device, steps 4–6 wait 24 h") are worded at COMPLETION,
--    and step 4 is exactly what this file releases. Without a second look, an attempt opened while
--    the user had no certified device would release at k even after the user is certified again
--    (rung 3, or a sibling attempt), with no Cancel window: open A on a borrowed phone while the
--    real phone is lost, wait for the real owner to recover, then have two colluding guardians
--    approve A. Nothing else closes A (store_pg.ts recoveryCancel is the manual tap).
--    So section 3 redefines rf.recovery_derive, the one derivation, with one change: the EFFECTIVE
--    ladder is `waiting_24h` when the attempt opened on it OR the user has an active certified
--    device other than the candidate NOW. It is never relaxed the other way: an attempt that opened
--    behind a live device keeps its wait if that device is lost meanwhile. Because the release, the
--    progress read, the guardian's decide and the Cancel all read state through rf.recovery_derive,
--    they move together: the newly certified device sees `waiting_24h` with a `wait_until` and can
--    Cancel (0010's cancellation policy is not state-gated), and the phone sees the same wait.
--    `opened_state` still reports the ladder the attempt opened on (`recovery_requests.state`),
--    which is untouched. E-06-80 (database) and E-06-81 (route) pin it.
-- 5. Every other case (not the opener, no such attempt, not approved yet, cancelled, expired,
--    revoked, suspended, erased) returns the EMPTY SET: no error, no reason, no distinction, the
--    same answer a nonexistent id gets. The route renders an empty release as the same 404 for
--    everybody, so it cannot tell a caller that an attempt it does not own exists. That is the
--    oracle 0010's `unknown_request` and BIL1's billing-webhook `applied` avoid. The opener
--    learns WHY from `GET /sync-meta/recovery?request_id=`, which it could already read.
--
-- What the server still does NOT do (04 §8.6): open, hash, compare or re-seal a share. `blob` is
-- bytea in and bytea out. The only comparison is 0010's, 32 public bytes against 32 public bytes,
-- which is done again here as the join condition, so a mis-filed row can never ride along.
--
-- ⚠️ SPEC (owner): two readings 04 §7.3 and 06 do not settle, each taken conservatively and each
-- pinned by one assertion, so a ruling flips a test rather than a guess:
--   (a) HOW LONG an approved attempt's shares stay fetchable. 04 §7.3 sets no deadline for step 4,
--       and 0010 reads the 72 h bound as the guardians' window to RESPOND ("once k approvals exist
--       the attempt is no longer waiting on guardians"). The release follows that derivation, so
--       an approved attempt stays releasable until retention removes its rows (03 §6: 30 days
--       after `expires_at`; rf.sweep_recovery). A second timer here would be an invented rule.
--       The exposure is bounded by the seal: only the phone holding the candidate secret, which
--       ADR 2026-09-24b §1 zeroises after reconstruct and on every close, can open these bytes.
--       E-06-75.
--   (b) A SUSPENDED candidate device is WITHHELD, whereas rf.has_guardian_set (0016 (c)) answers
--       one. Suspension is the state of a device someone asked to be revoked, pending its window
--       (ADR 2026-09-05d §3). 0016 kept parity with the open because what it gives away is one
--       bit. What this read gives away is the key to the user's vault. E-06-76.
--   (c) WHERE the re-checked wait (section 4 above) is measured from. It runs from the k-th approval,
--       which is 0010's own ruling for the waiting ladder (its ⚠️ SPEC: "the wait itself is measured
--       from the k-th approval"). So the usual order, where the user is certified again and the
--       guardians approve afterwards, always gets the full 24 h. One edge is left: k was reached while
--       no certified device existed, so the release was already legitimate, and a device is
--       certified later, before the phone has fetched. The wait then covers only what remains of
--       kth + 24 h, and may already be over. The devices table holds no server-stamped certification
--       time to measure from (`device_certs.issued_at` is the client's claim), and a phone that
--       could fetch at k would have fetched at k. The edge is pinned in E-06-80, where an attempt at
--       k and seconds old is withheld once a device is certified. Owner: is a full 24 h from the
--       moment of certification wanted? That needs a server-stamped column, and so a migration.
--   (d) 05 §5 🔒 (docs/05-sync-protocol.md, "Metadata & key sync") lists `wrapped_keys` on
--       GET /sync/meta, and says "New wrapped_keys → unwrap". Since this file, kind `recovery_blob`
--       never travels that channel, to anyone. It leaves only through GET
--       /sync-meta/recovery/shares (rf.recovery_shares), because the meta channel has no notion of an
--       attempt's state and cannot hold back the 24 h wait of 04 §7.3 step 6 🔒 / ADR 2026-09-05d §1
--       🔒. 03 §2.5 🔒 ("wrapped_keys: readable only by the subject") and ADR 2026-09-05d §2 🔒
--       ("wrapped keys and shares addressed to it") are upper bounds, and this stays inside them. 05
--       §5 enumerates the channel's contents without the exception, though. The doc line belongs to
--       the owner (a 🔒 section, and docs/ is outside this lane): 05 §5 should say that
--       `recovery_blob` rows are withheld from the meta channel and released by the step-4 route.
--       E-06-45 and E-06-79 assert the exception (store_pg.ts metaPage under this policy; store_mem.ts
--       mirrors it).
--
-- CLAUDE.md rule 2: no table, column or grant is added. No UPDATE or DELETE grant appears anywhere,
-- nothing touches `envelopes`, and neither function performs a write. 0005 and 0010 are committed
-- and their files are not edited. This file adds, and it REPLACES one 0010 function,
-- rf.recovery_derive, by CREATE OR REPLACE with the identical signature and result columns (so
-- every caller, and 0010's revoke from PUBLIC, stand). The one behavioural change is section 4
-- above. 0019 is not touched.

-- ---------------------------------------------------------------- 1. the table: no side door
create policy wrapped_keys_recovery_blob_no_select on wrapped_keys
  as restrictive for select to rf_api
  using (kind <> 'recovery_blob');

create policy wrapped_keys_recovery_blob_no_insert on wrapped_keys
  as restrictive for insert to rf_api
  with check (kind <> 'recovery_blob');

comment on policy wrapped_keys_recovery_blob_no_select on wrapped_keys is
  '0020: a re-sealed recovery share leaves only through rf.recovery_shares, once the attempt is '
  'approved (04 §7.3 step 6; ADR 2026-09-05d §1). Restrictive: it narrows 0005, never widens it.';
comment on policy wrapped_keys_recovery_blob_no_insert on wrapped_keys is
  '0020: only rf.recovery_decide (SECURITY DEFINER, 0010) files a recovery_blob, bound to one '
  'attempt, one guardian decision and one candidate key.';

-- ---------------------------------------------------------------- 2. the one way out
create function rf.recovery_shares(p_request uuid)
returns table (wrapped_key_id uuid, guardian_user_id uuid, candidate_device uuid,
               sealed_to_pub_x bytea, share_set_version int, blob bytea,
               approved_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare r recovery_requests%rowtype; st text;
begin
  select * into r from recovery_requests q where q.id = p_request;
  if not found then return; end if;

  -- WHO: the caller that opened it, both halves of the claim pair, on a device still live and
  -- not suspended, for a user who is not erased. Every miss returns the same empty set.
  if r.user_id is distinct from rf.user_id()
     or r.candidate_device is distinct from rf.device_id() then
    return;
  end if;
  if not rf.device_live_for(r.candidate_device, r.user_id)
     or not exists (select 1 from devices d
                    where d.id = r.candidate_device and d.status <> 'suspended')
     or not exists (select 1 from users u where u.id = r.user_id and u.erased_at is null) then
    return;
  end if;

  -- WHEN: the one derivation (0010). k approvals, the 24 h wait elapsed where it applies, not
  -- cancelled, not closed.
  select d.state into st from rf.recovery_derive(p_request) d;
  if st is distinct from 'approved' then return; end if;

  -- WHAT: this attempt's shares, addressed to this attempt's candidate, and nothing else.
  return query
    select a.wrapped_key_id, a.guardian_user_id, w.device_id, a.sealed_to_pub_x,
           a.share_set_version, w.blob, a.created_at
    from recovery_approvals a
    join wrapped_keys w on w.id = a.wrapped_key_id
    where a.request_id = r.id
      and a.decision = 'approved'
      and a.sealed_to_pub_x = r.candidate_pub_x
      and a.share_set_version = r.share_set_version
      and w.kind = 'recovery_blob'
      and w.user_id = r.user_id
      and w.device_id = r.candidate_device
      and w.revoked_at is null
    order by a.created_at, a.guardian_user_id;
end $$;

comment on function rf.recovery_shares(uuid) is
  '04 §7.3 step 4 (0020): the re-sealed shares of ONE attempt, addressed to its candidate, for the '
  'caller that opened it (user_id AND candidate_device), live and not suspended, once '
  'rf.recovery_derive says approved. Empty for everything else, identically. Opaque bytes; the '
  'server opens nothing.';

-- A new function is EXECUTE-able by PUBLIC by default, and 0005's blanket
-- `grant execute on all functions in schema rf to rf_api` ran before this existed: name both.
-- rf_maintenance is not granted it: retention needs no share.
revoke all on function rf.recovery_shares(uuid) from public;
grant execute on function rf.recovery_shares(uuid) to rf_api;

-- ---------------------------------------------------------------- 3. the wait, asked when it matters
-- 0010's rf.recovery_derive, restated with ONE change (header, section 4): the effective ladder is
-- re-read at derivation time. Everything else is 0010's text, including its two ⚠️ SPEC readings
-- (the 72 h bound is the guardians' window to respond; three denials surface as 'expired').
create or replace function rf.recovery_derive(p_request uuid)
returns table (request_id uuid, user_id uuid, candidate_device uuid, share_set_version int,
               k int, n int, approvals int, denials int, opened_state text, state text,
               kth_approval_at timestamptz, wait_until timestamptz,
               expires_at timestamptz, cancelled_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare r recovery_requests%rowtype; g record; c timestamptz; a int; d int;
        kth timestamptz; wait timestamptz; st text; ladder text;
begin
  select * into r from recovery_requests q where q.id = p_request;
  if not found then return; end if;
  select s.k, s.n into g from guardian_sets s
    where s.subject_user_id = r.user_id and s.share_set_version = r.share_set_version;
  select count(*) filter (where x.decision = 'approved'),
         count(*) filter (where x.decision = 'denied')
    into a, d from recovery_approvals x where x.request_id = p_request;
  select x.created_at into kth from recovery_approvals x
    where x.request_id = p_request and x.decision = 'approved'
    order by x.created_at offset greatest(g.k - 1, 0) limit 1;
  select x.created_at into c from recovery_cancellations x where x.request_id = p_request;

  -- ADR 2026-09-05d §1 🔒 / 04 §7.3 step 6 🔒, asked at completion: the wait applies when the
  -- attempt opened behind a live certified device (0010's ladder, written once) OR when the user has
  -- one now. Only ever tightened: a device lost mid-wait does not lift a wait already owed.
  ladder := case when r.state = 'waiting_24h'
                   or rf.has_other_active_device(r.user_id, r.candidate_device)
              then 'waiting_24h' else r.state end;
  if ladder = 'waiting_24h' and kth is not null then
    wait := kth + interval '24 hours';                  -- from the k-th approval (⚠️ SPEC (c))
  end if;

  if c is not null then st := 'cancelled';
  elsif d >= 3 then st := 'expired';                    -- 04 §7.3 step 7 (0010's ⚠️ SPEC)
  elsif a >= g.k then
    st := case when wait is null or now() >= wait then 'approved' else 'waiting_24h' end;
  elsif now() >= r.expires_at then st := 'expired';     -- 72 h with fewer than k approvals
  else st := ladder;
  end if;

  return query select r.id, r.user_id, r.candidate_device, r.share_set_version, g.k, g.n,
                      a, d, r.state, st, kth, wait, r.expires_at, c;
end $$;

comment on function rf.recovery_derive(uuid) is
  '0010, restated by 0020: the single derivation of an attempt''s state. The 24 h ladder is the one '
  'it opened on OR waiting_24h whenever the user has an active certified device other than the '
  'candidate at the time of the read (ADR 2026-09-05d §1; 04 §7.3 step 6). Owner-only.';

-- Restated for the reader; CREATE OR REPLACE keeps 0010's ACL, and this keeps it owner-only.
revoke all on function rf.recovery_derive(uuid) from public;
