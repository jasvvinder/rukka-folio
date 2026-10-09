# ADR 2026-10-09b — An uncertified phone may read its own account's UMK public key

Rung 3 (04 §7.4) runs on a wiped, uncertified phone. To adopt the UMK it opens from the sheet, the phone needs the
account's published UMK public halves as `expected` (ADR 2026-10-06d ruling 2; ADR 2026-09-13c §1 makes the AEAD under
the paper RK this rung's authenticator, so a lying server can only cause a refusal). M13-RUNG3S relays them on
`GET /recovery/sheet`. ADR 2026-09-05d §2 🔒 lists what an uncertified device may read, and its own UMK public key is not
on that list. The database already allowed the read (`0005:317-318`, `umk_select` admits the caller's own rows without
certification); the list did not say so. **Owner ruled 9 Oct 2026** (PLAN desk 186 (a), (b)).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The uncertified read list gains the device's own account's registered UMK public key 🔒 ⟦tests: E-1006d-1, E-1006d-2, E-1006d-4⟧
- ADR 2026-09-05d §2's list gains one read: the **caller's own** account's registered UMK public key — both halves,
  `pub_ed` and `pub_x` — at its **live** row (`superseded_at is null`). Never another user's, never a retired row, never
  a fallback to an older version.
- It travels on `GET /sync-meta/recovery/sheet` beside the sheet, as `umk_pub_ed` / `umk_pub_x` (b64url, 32 bytes each).
- It is a public key, and only the caller's own. Everything else in 05d §2 stands: no memberships, names, roles, device
  lists or verification log.

### 2. A sheet with no live registered UMK is served with null key fields, not refused 🔒 ⟦tests: E-1006d-3⟧
- When the caller has a sheet but no live UMK row (or an Ed-only row, which relays `umk_pub_x = null`), the route answers
  `200` with the key fields **present and null**. It invents no key. `404 no_sheet` keeps its one meaning: there is no
  sheet.
- Why not a distinct 404: S0.5b's *sheet on the server* check and its scan-back read the same route and need no key
  (`recovery_sheet_service.dart:254, :285`); a 404 there would break them for any account whose key row is missing.
- On the restoring phone a null field means **cannot verify**: the opener ends in a recovery failure, never adopts, and
  never shows R2.4 *"that code didn't work"*, because the code may be right (F1-06-40). This client half lands with the
  S11.3 opener (PLAN desk 171 (b)).

## Consequences
- Code: `server/supabase/functions/sync-meta/index.ts` (`/recovery/sheet`), `_shared/store*.ts` — built 9 Oct, M13-RUNG3S.
  No grant or policy changed. The client parse and opener are desk 171 (b).
- Docs: cross-reference lines under ADR 2026-09-05d §2, 03 §2.5 (certified-only RLS) and 04 §7.4.
- Milestone: M13 (rung 3, desk 171).

## Open ⚠️
- The sheet blob itself (`recovery_sheets`, 0011) is read by the same uncertified phone on the same route and is not on
  05d §2's list either. It is the caller's own sealed blob, which the server cannot open. Not ruled here; the owner may add
  it beside ruling 1.
- `recovery_sheets` records no `umk_key_version`, so the relayed key is the account's live one, not necessarily the one
  the blob was sealed under. They agree until a UMK rotation without a new sheet, and rotation has no write path yet
  (0031's ⚠️ SPEC). Parked until rotation is specified (desk 186 (e)).
