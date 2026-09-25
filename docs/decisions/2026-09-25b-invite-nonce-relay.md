# ADR 2026-09-25b — the invite nonce is the inviter's, and the invitee is handed it

**Status:** accepted (owner-ruled, 25 Sep 2026, PLAN desk 32 — "relay what's built")
**Amends:** 04 §6.1 (*server-generated*) · 04 §10 acceptance excerpt (*the nonce is dead*, reading) · 06 §7
(two relayed fields). Everything else in those documents stands, including ADR 2026-09-13d in full.

## Context

The M11-CER2 slice (25 Sep) left S9.2 *Show my code* on its placeholder. It could not bind
`LiveCeremonySessions.nonces` (`app/lib/bootstrap.dart:815-819`), because 04 §6.1 🔒 says the per-invite nonce
is *server-generated at invite creation* and no route returns it to the invitee. Checked against the code on
25 Sep:

- **The server does not generate it.** The admin's device draws it and signs it inside the `invite` record's
  payload `{roles, nonce}` (`0008_signed_verification_and_invite_records.sql:20`). `POST /sync-meta/invites`
  passes `payload.nonce` into `createInvite` (`server/supabase/functions/sync-meta/index.ts:563`), and
  `rf.create_invite` stores it (`0006_invites_membership_state.sql:182-193`). The size is checked at 16 bytes
  (`0006:28`), and the nonce is fixed at issue (`0008:188`).
- **The invitee never receives it.** `GET /sync-meta/invites` returns `invite_id, tenant_id, roles, expires_at,
  created_by` (`sync-meta/index.ts:507-513`). It lists only invites still at `sent` (`store_mem.ts:1129`,
  `rf.my_invites()`), so after acceptance, which is when the ceremony runs, the invite drops out of that list
  altogether.

Since ADR 2026-09-13d §1 the nonce derives no code. It *"stays in the QR payload only"*, where 04 §6.1 says it
*"scopes and expires codes"* and is *"not secret"*. Nothing now depends on the server choosing it. A nonce the
inviter drew and signed is attested by the inviter's own key, which is stronger than one a relay chose.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The inviter's device draws the nonce ⟦tests: E-25b-1 @M11⟧
- **Amends 04 §6.1** *"server-generated at invite creation"*. The per-invite nonce (128-bit) is drawn from
  libsodium randomness by the **admin's device** when it creates the invite. It is carried in the signed
  `invite` record (0008), and the server stores it and relays it. It is fixed at issue (0006/0008 triggers), is
  not secret, and scopes and expires the QR. The server never chooses a nonce and never alters one.

### 2. The invitee is handed its own invite's nonce ⟦tests: E-25b-1 @M11, E-25b-2 @M11⟧
- `GET /sync-meta/invites` rows gain **`nonce`** (base64url, 16 bytes). The rows it returns widen to invites
  **at `sent`, or accepted by the caller**, within the invite's 7-day window. An accepted invite stays
  reachable for S9.2 after a restart without the device keeping a copy.
- `POST /sync-meta/invites/accept` returns **`nonce`** beside `invite_id` and `status`.
- Scope is unchanged. The caller sees only invites addressed to its own phone HMAC, or accepted by itself. A
  second user, another tenant's admin and an uncertified stranger see nothing (hostile-query tests, `E-25b-2`).
  No route gains a way to look an invite up by nonce.

### 3. S9.2 shows the relayed nonce and never draws one ⟦tests: F1-25b-1 @M11⟧
- `bootstrap.dart` binds `LiveCeremonySessions.nonces` to the relayed nonce of the invite that brought this
  user into the tenant. The invitee's device **never draws** an invite nonce. With no relayed nonce, S9.2 keeps
  its placeholder and says why.

### 4. *Regenerate* opens a fresh session, not a fresh nonce ⟦tests: F1-25b-2 @M11⟧
- The nonce is fixed at issue, so it cannot be redrawn without a new invite. Following 04 §6.3 as amended by
  ADR 2026-09-13d (*"Regenerate opens a fresh session"*), *Regenerate* draws a new `r_S` and commitment and
  keeps the invite's nonce. `InviteNonceSource({fresh: true})` returns the same nonce. The flag is dropped when
  the seam is next touched.
- **Reading of 04 §10** (*"a wrong 8-digit code entered 3×, then the nonce is dead and a new Regenerate is
  required"*). This predates 13d. What dies is the **session**, and *Regenerate* opens a new one.

## Consequences
- **Build rows** (PLAN.md, M11). §1 + §2 go to `lane-server` at xhigh with the three-lens verify (ADR 2026-09-24
  §2): `rf.my_invites()` + the store (pg and mem), both routes, and `E-25b-1/2`. §3 + §4 go to `lane-ui-hard`,
  `features/ceremony` + `bootstrap.dart`: `F1-25b-1/2`. The server slice lands first.
- **Docs:** cross-reference lines in 04 §6.1, 04 §10 and 06 §7.
- Needs no migration to the `invites` table. The column, its size check and its immutability are already built.

## Open ⚠️
- **Ceremonies not born of an invite.** Device linking, delegated verification by a member who is not the
  inviter, and annual re-verification have no invite nonce. What these QRs carry in the nonce slot is not ruled
  here, and the next ceremony slice must ask rather than invent it.
