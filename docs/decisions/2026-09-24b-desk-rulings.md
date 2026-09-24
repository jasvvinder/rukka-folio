# ADR 2026-09-24b — Desk rulings: recovery, entitlement, read-only, exports

**Status:** accepted (owner-ruled, 24 Sep 2026, in one sitting, clearing PLAN desk 12, 14, 16,
19, 20, 22, 23, 25, 26, 27, 28, 30, 31)
**Amends:** 04 §7.3 step 1 (reading) · ADR 2026-09-05d §2 (one bounded read) · ADR 2026-09-05g
§1, §4, §9 · 08 §2, §3 · 13 §4.3, §5 F11, §6 · ADR 2026-09-19 ruling 2 (one more target) · 02 §8.1
*Presentation* (reading) · 03 §2.4 (ratifies `0013`). Everything else in those documents stands.

## Context

The owner asked for the desk to be finished before any more building. Each item had been ruled
conservatively by a lane and flagged `⚠️ SPEC`, or refused outright because it touched a 🔒 line.
The owner chose one option per item from a recommendation with its evidence. This ADR records the
choices. Where a ruling flips behaviour a green test asserts, that test is skipped in the same
commit (ADR 2026-09-05i §4) and re-lands with the build row named under *Consequences*.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The recovery candidate is its own X25519 pair, one per attempt (desk 12) ⟦tests: B-24b-1 @M11, F1-24b-1 @M11⟧
- 04 §7.3 step 1's *candidate X25519 pair* is **not** the new device's `pub_x`. The device mints a
  dedicated pair when it opens a recovery attempt and stores it in the platform key store until the
  attempt closes (approved, cancelled, denied or expired). Guardians re-seal to that pair's public
  half (step 3).
- The private half is zeroised after `reconstructVerified` (step 4) and on every close. It never
  wraps a BK and is never registered as a device key. An abandoned attempt therefore never shares a
  key with the device's identity.
- A seam with no candidate producer still refuses plainly and sends nothing (`F1-06-35` stands).

### 2. `umk_pub_x` is backfilled automatically, and a missing one is said, not swallowed (desk 14) ⟦tests: F1-24b-2 @M11, F1-24b-3 @M11⟧
- Every installed device re-offers `umk_pub_x` on its next `/devices/certify` after launch, with no
  prompt. `rf.set_umk_pubs` fills a NULL once, so the re-offer is idempotent.
- While the other person's row still has `pub_ed` only, the ceremony fails closed **and says so**:
  it tells the user to ask them to open the app once. The ceremony never fails silently.

### 3. An uncertified device may ask one yes/no question about its own guardians (desk 16) ⟦tests: E-24b-1 @M11, F1-24b-4 @M11⟧
- **Amends ADR 2026-09-05d §2** by one read. An uncertified device may learn whether **its own
  user** (`user_id = rf.user_id()`) has a current guardian set. The answer is a boolean: no k, no n,
  no member identity, no share, no generation. The read is deliberately **not** gated on
  `rf.is_certified()`. Everything else in 05d §2 stands: no memberships, names, roles, device lists
  or verification log.
- With it, rung 2 can truthfully answer `noTrustedMembers`. Absent the answer (offline, error),
  rung 2 stays `unknown`. The existing `guardian_sets` read under certification is unchanged, and
  *empty ≠ denial* (`F1-06-70…73`) still holds for it.
- Built by `lane-server` at xhigh with the three-lens verify (ADR 2026-09-24 §2), because it widens
  what a SIM-swapper's device can see by exactly one bit.

### 4. *None of these work for me* means every rung **refused** (desk 20) ⟦tests: F1-07-420⟧
- 13 §5 F11's *none* counts refusals (`isBlocked`), not *not confirmed*. An `unknown` rung is a door
  that might still be open, and surrender is never offered over one. This ratifies what shipped on
  22 Sep.

### 5. S11.6 is the one screen with an *unchecked* row (desk 19) ⟦tests: F1-07-418, F1-07-419, F1-07-421, F1-07-422⟧
- 13 §4.3's five component states stand for every other component. S11.6 (R2.1, the fork) adds a
  third row rendering for an `unknown` rung: takeable (chevron, live tap, enabled button
  semantics), marked with a help icon and a sentence that survives colour removal (07 §1 rule 3).
  No other screen may use it without its own ruling.
- The R2.1 canvas gains an unchecked row (owner, in the design project), so the rendering becomes a
  design decision and stops being a lane's.

### 6. The entitlement token carries `grace_until` (desk 22) ⟦tests: E-24b-2 @M13, F1-24b-5 @M13⟧
- **Amends ADR 2026-09-05g §1 and 08 §3.** The field set is
  `{tenant_id, plan, limits, period_end, grace_kind, grace_until, iat, exp}`. `grace_until` is null
  unless `grace_kind = dunning`, in which case it is `subscriptions.grace_until`. §4's
  *server-declared* now holds literally.
- The client reads the server's `grace_until` and never derives `period_end + 7 d`. The 7 days
  remain the gateway default the server writes. A store-run channel (IAP) may carry its own grace
  length; that is why the server declares the date instead of the client deriving it.

### 7. Three token readings, ratified (desk 23) ⟦tests: E-05-15, G-08-5⟧
- (a) A **lapsed** tenant (`subscriptions.status = 'expired'`, refund or chargeback included) is
  minted with `period_end` clamped to `iat`, so a refunded tenant can never read as paid.
- (b) An unlimited limit (Personal/Family+ business books, 08 §2 *∞*) is **`-1`** on the wire.
- (c) The token carries **no key id**. During the 30-day rotation overlap the app verifies against
  both pinned public keys and accepts either.

### 8. `billing_events` gains two columns, and `dispute_state` has three values (desk 25) ⟦tests: E-03-65, E-03-66, E-03-67, E-03-68, G-08-11⟧
- 03 §2.4 ratifies `0013`'s `billing_events.tenant_id uuid null` and `event_at timestamptz null`
  (the subscription the event is for, and the gateway's own time), which ADR 05g §9's out-of-order
  guard needs.
- `subscriptions.dispute_state` takes `null | 'refunded' | 'disputed' | 'chargeback'`. Any non-null
  value ends entitlement now and leaves data untouched (05g §11).
- Still open: the gateway pick, and the daily reconciliation poll that depends on it (`G-08-10`
  keeps `@M13`).

### 9. Exported ledgers close with the khata block and no separate c/f (desk 28b) ⟦tests: F1-07-162, F1-07-163, F1-07-164, F1-07-166⟧
- 02 §8.1 *Presentation*, read literally: an **on-screen** FY view opens *Opening balance b/f* and
  ends *Closing balance c/f*, as the worked examples draw it
  (`financial-accounting-standards.md` §3). A **printed or exported** ledger ends with the paper
  block *Closing balance c/d · Total · Opening balance b/d* (07 §14) and carries **no** c/f row
  above it. Two closing rows for one figure is the defect.
- The opening row of an export is unchanged. The amount-in-words line stays under the block.

### 10. A file name in a message may break at any character (desk 28a) ⟦tests: F1-07-434⟧
- 07 §1 rule 6 (name the file) and rule 11 (fit at 200 % on 360×800) both hold. A file name wraps
  preferring `-`, `/` and `.`, then any character. It is never ellipsised and never clipped.
  `F1-07-434` asserts the fit.

### 11. Monthly prices ship as flagged placeholders, and *popular* sits on Family (desk 26) ⟦tests: n/a — placeholder prices; G-08-7 @M13 owns the toggle⟧
- 08 §2 gains a placeholder monthly column: Personal ₹63, Family ₹209, Family+ ₹417 (integer paise,
  GST-inclusive, ≈ 20 % dearer than annual over 12 months, rounded **up** so the shown saving never
  overstates). Family carries the *popular* badge.
- The owner sets real prices before M13 exits. Until then both columns stay marked placeholder.

### 12. iOS cancel may open Apple's subscription settings (desk 27) ⟦tests: F1-24b-6 @M13⟧
- **Amends ADR 2026-09-19 ruling 2** by exactly one named target:
  `https://apps.apple.com/account/subscriptions`, opened through the same kind of one-method seam
  as the `Dialer` (never `canLaunchUrl`, no query-schemes entry). `url_launcher` stays otherwise
  `tel:`-only. It is still not a general door to the browser.
- If the launch fails, S12.3 shows the path in words (*Settings › Apple Account › Subscriptions*),
  so the path is never a dead end. Revisit when the IAP package lands: StoreKit has a native
  manage-subscriptions sheet.

### 13. Read-only blocks every new envelope except the 10-second Undo (desk 30) ⟦tests: F1-07-491, F1-24b-7 @M13⟧
- 13 §6's read-only (lapsed, S12.5) blocks **every** write that creates an envelope: post, amend,
  reverse, opening balances (S3.1 and onboarding), cash count, advances and partner entries. Each
  path raises the same S12.5 sheet. Drafts are kept, and export always works.
- **One exception:** the 10-second Undo of an entry this phone just saved. Blocking it would trap a
  mistake the person made seconds ago (07 §1 rule 2, no dead ends).
- Book full (`rejected:quota`) keeps its narrower scope: it blocks posting to that book only
  (ADR 2026-09-05b §7).

### 14. The S12.5 sheet's two conservative readings stand (desk 31) ⟦tests: F1-07-492⟧
- Until a whole-tenant export route exists, the sheet omits *Export everything* rather than showing
  a dead button. The route is a ⬜ build row, and the button returns with it.
- A failed `EntitlementSource.read()` reads as untokened: Free, never locked (05g §1). A read error
  never blocks a save.

## Consequences
- **Tests skipped in this commit** (ADR 2026-09-05i §4):
  - `G-08-5`, `E-05-15` (`server/supabase/functions/_tests/entitlement_token.test.ts`): they assert
    that `grace_until` is absent, and §6 flips that. Re-land at M13 once `_shared/entitlement.ts`
    mints the field.
  - `F1-07-162`, `F1-07-163`, `F1-07-164`, `F1-07-166` (`app/test/features/ledger/s4_statement_export_test.dart`,
    `app/test/features/reports/statement_report_test.dart`): they assert a c/f row in the export,
    and §9 removes it. Re-land at M12 once `statement_report.dart` drops that row.
- **Build rows** (PLAN.md): §1 + §2 (`lane-ui-hard`, M11, with the scanner slice's neighbours) ·
  §3 (`lane-server` xhigh + app probe) · §6 (`lane-server`: mint + re-land) · §9 + §10 (`lane-ui`,
  reports) · §12 (`lane-ui`, subscription) · §13 (ENT2, now unblocked) · §14's export route.
- **Docs:** cross-reference lines in 04 §7.3, ADR 2026-09-05d §2, 13 §4.3 / §5 F11 / §6, ADR
  2026-09-05g §1 / §4 / §9, 08 §2 / §3, 03 §2.4, ADR 2026-09-19 ruling 2, 02 §8.1.
- **Ops, done in this session:** a *development* `RF_ENTITLEMENT_KEY` in local `.env` (git-ignored).
  The production key is generated in its custody home at deploy (05g Open 4).

## Open ⚠️
- Real monthly and annual prices (§11) — owner, before M13 exit.
- The R2.1 canvas row for §5 — owner, in the design project.
- The support WhatsApp handle (desk 15) and the external lead-times (desk 2) are unaffected.
