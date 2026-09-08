# ADR 2026-09-05f — UX & design catch-up: a home for every state the 5 Sep ADRs created

Fifth ruling of the day and the last to be applied, because it consumes what the other four define.
ADRs 2026-09-05 (client hardening), 05b (sync trust boundaries), 05c (storage), 05d (auth & devices)
— and their follow-ons 05e (ledger time boundary), 05g (subscription & entitlement), 05h (admin
console), 05i (test contract) — created about seventeen user-visible states. The seven-spec review
fan-out found that **none of them had a screen, a state-machine row, an Inbox card, a component or a
line of copy** in 07, 13 or the design system; that 07 §5 contradicts itself three times on 🔒
lines; that the tab bar, paise-on-screen and the PIN lockout each exist in two incompatible
versions across equally ranked documents; and that the design system has no status colours, two
unaudited grounds, a forked type scale and a second hand-kept palette in the canvas build script.
Owner confirmed 5 Sep 2026 ("accept all recommendations").

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### A. One tab bar, stated once
**Four tabs — Home · Ledger · Inbox · Menu — plus a docked centre ( + ) action.** The bar is the
4-column set of design-system §4.1 (glyphs, sizes, weights unchanged); the ( + ) is a docked
action that is *not* a tab: no active state, no label, sits between Ledger and Inbox. 13 §3.1,
07 §2, design-system §4.1 and DESIGN-PACK S1 now say this in the same words. The "long-press repeats
the last entry" affordance on ( + ) is **struck** (see C).

### B. The seventeen states, each with a home
| State | Source | Home |
|---|---|---|
| Device **suspended** (server asserted revocation without a signed record) | 05b §2, 05d §3 | **S15.4 Device suspended** — read-only + persistent banner, sync stopped, books readable, one plain line and *Retry*; never a hard lock, never a wipe |
| Uncertified device sees no tenant metadata | 05d §2 | S0.9 variant — before its certificate is verified the screen names **nothing** about the family; no "we found your family" copy |
| **Author gap** — *"Waiting for entries from {name}'s phone"* | 05b §3, 05 §9 | status surface (07 §1.7); **provisional** badge on P2 position cards; Everything scope carries it per book card; §6 Sync gains the state |
| **Held** entries (dangling amend / reverse / decision) | 05b §4, 05e | S4.1 detail note *"waiting for the entry this changes"*; §6 Entry row `held → projected \| quarantined(target_missing)`; the absolute "no state excludes an entry from balances" is reworded to *no posted, projected entry* |
| **Close blocked on gaps** | 05b §3, 05e | **S10.5 Close blocked — waiting on a device** (names the phone); F9 ◆ *any author gap or held envelope → lock disabled, reason shown*; 07 §13 blocking list per 05e |
| **"Update the app to verify this close"** | 05c §3 | S10.4 / S10.2 *unverified-by-you* variant; third close outcome beside verified and mismatch→Recompute; §6 Period gains it; `Certified ✓` badge (07 §14) gets the variant |
| `write_lost` | 05b §6 | P3 security card in Inbox |
| **Book full** (`rejected:quota`) | 05b §7, 05g | P3 card → S12.1 Plans; **posting blocked with the S12.5 sheet pattern, drafts preserved**; reads and exports never blocked |
| `rate_limited` | 05b §7 | **explicitly no UI** — silent backoff; stated so nobody designs one |
| **Modified-device notice** (root / debugger / instrumentation) | 2026-09-05 §6 | **S19.5 This phone has been modified** — once per app version, plus a permanent S11 row; never blocks |
| **Foreground inactivity lock** (5 min) | 2026-09-05 §7 | S15 trigger; S13 *Auto-lock* shows both values (background · idle); **suppressed while a draft has digits typed** — lock on idle after save |
| **24 h recovery Cancel** | 05d §1 | **S11.9 Recovery in progress — Cancel** on every existing device; F11 ◆; S11.6 gains the line *"Linking is instant — recovery takes 24 hours"* |
| **Support-action Cancel** | 05d §3 | **S11.10 Support action pending — Cancel** (revocation; deletion already had its 15-day copy) |
| **New certified device notice, every path** | 05d §6 | P3 card + S11 row; 07 §17 corrected from "new **uncertified** device" to "new **certified** device" |
| **MPIN lockout** | 05d §5 | S15.3 states: 5 free · 30 s · 1 min · 5 min · 15 min · 1 h · **disabled after 10 → OTP + biometric**. The canvas's framing *"a code, not a lockout"* stays as the **copy**; the ADR governs the **behaviour**: add a cooldown countdown row and a disabled-PIN state |
| **Biometric re-enrolment → PIN** | 05d §4 | S15 copy variant: *"A new face or fingerprint was added to this phone — enter your PIN once"* |
| **Book incomplete — rebuilding** (local corruption, Recompute-on-upgrade, `store_epoch` re-pull) | 05c §3, §6; 05b §6 | **S1.4 Book incomplete — rebuilding** with the determinate loader rule, *"{done} of {total} entries restored"*; `integrity_ok` gates the Home card; never shown as whole meanwhile |
| India residency as a trust claim | 05c §1 | one line on S18.3 |

**New state models in 13 §6:** **Device** `uncertified → certified → suspended → revoked`;
**App lock** `open → locked(background 2 min \| idle 5 min \| cold start) → unlock \| pin-cooldown →
pin-disabled → OTP+biometric`. **Membership** gains `expired` (06 §7). **Sync** is aligned to the six
states 05 §9 owns. **§8 rule:** *lock and interruption never discard work — a half-typed entry or a
half-done wizard returns to the same field.*

### C. 07 §5 — the later rulings win
1. Delete *"Default is the last money account used for that verb, Cash on first use"*; the
   single-screen block's **nothing is pre-selected** stands.
2. The paragraph *"Transfer and Adjustment verbs live behind the [+] chooser's second row"* is
   scoped to **Adjustment only** — Move money is the pill's fifth position (ADR 2026-09-03b).
3. **Long-press-repeat is struck** from 07 §2 and 13 §3.1/§3.2 — "no repeat-pattern shortcuts" stands.
Also: 07 §4's trial-balance target is **S8.2** (report viewer), not S8.1 (reports list).

### D. Inbox card taxonomy (P3 / S6)
Typed cards, each designed: reviews · imports · invites · recoveries · reminders · **late arrivals**
· **structural approval with quorum + veto** (S6.3) · **quota / book full** · **write_lost** ·
**key_wait > 24 h** · **author gap > 24 h** · **quarantine (security event)** · **device added** ·
**integrity / rebuild** · **cancel-window banner with countdown** (recovery, support action,
deletion). Sync rejections are always a card, never a modal (13 §8 unchanged).

### E. Notification → destination map (new 13 §3.4)
Every 07 §17 notification names its deep-link target. The four loud ones: recovery requested
(guardian) → S11.7; recovery in progress on your account → S11.9; support action pending → S11.10;
new certified device → S11. Modified-device is local, not a push. Content-free throughout (04 §4).

### F. Screens 07 did not own
07 gains short sections (after §15, numbering continues) for: **S12.x** subscription — plans,
checkout, manage, payment problem, read-only, invoices, with the **two graces** 05g defines
(dunning is tenant-wide; offline grace is device-local); **S16.x** my account · edit profile · change
phone (24 h window when guardians approve, 05d §1) · delete account; **S17.x** help · FAQ · contact
(states what support cannot do, 05h) · diagnostics (scrubbed, shown before sending); **S18.3** what we
can and cannot see (+ residency line); **S19.x** update required · maintenance · no connection ·
permission priming · **S19.5** modified device; **S20** attachment viewer; **S21** search; **S6.3**
structural approval (quorum + veto, 02 §7.2.1); **S14.2** partner drift & settlement (02 §7.1); and
the **Settings → Your books → Opening balances** door required by ADR 2026-09-03b ruling 2, added to
13 S13, 07 §16 and DESIGN-PACK S13. The Home card's Dr/Cr line becomes plain words — *"Books
balanced · difference nil"* — with Dr/Cr one tap in on the trial balance (law 2). The 🔔 bell in
Home's app bar is **dropped**; the Inbox tab is the one tray. The scope chip carries the avatar and
*"{name} · {role} in this book"* (13 §2.3), and hides for an individual (13 §2.1).

### G. Copy honesty
- **Screenshot block has a consequence and a door** (07 §5.6, §17): *"Screenshots are off in this app
  to protect your books. To show someone a page, share it as a PDF"* → Share as PDF / Help.
- **Phone backup does not carry the books** (07 §3.1 step 5, §15): *"Your key comes back with your
  Apple/Google account; your books come back from the server."* (05c §8 excludes the local store.)
- A second admin's Members screen **cannot show whom was invited** — only the inviting device holds
  the contact (05c §4); the row reads *"Invited by Amrit · awaiting join"*.
- 07's header says every string ships in **EN + ਪੰਜਾਬੀ + हिन्दी** (rule 8).
- 07 §1.3: `pending` and `locked` tokens exist (design-system §2); the "to be added" note is removed.
- **FLAG_SECURE also covers Show my code** (S9.2): the other phone's camera is unaffected; the QR is
  meant to be scanned, not photographed. Closes 2026-09-05 open ⚠️ 2.
- 07 §18 gains: privacy-cover and capture checks · reduced-motion pass · dark-mode pass · biometric
  unlock inside the stopwatch · 360×800 beside 375×667.

### H. Design system
1. **Status colour family** — `success`, `warning`, `info`, `danger` (+ `on-danger`; `danger-surface`
   exists) in both modes, **restricted to icons, borders and words — never amounts** (rule 1 keeps
   numerals for `credit`/`debit`). `danger` absorbs the untokenised `#8E1F1B` / `#FFF4EF` pair on
   S9.4 / S10.4. DESIGN-PACK prompts that ask for "green check … in green" are rewritten to name the
   token. ⚠️ exact hex at the token session; must pass AA on all four grounds.
2. **Four grounds audited** — `bg`, `surface`, `sunk`, `danger-surface`, both modes. Known failures:
   light `credit` on `sunk` 4.30:1 and on `danger-surface` 4.20:1; dark `debit` on `danger-surface`
   4.04:1. **Light `credit` is darkened one step** so amounts pass on `sunk` (owner caveat accepted);
   amounts are **not placed on `danger-surface`** (words and icons only). ⚠️ hex at the token session.
3. **Focus** — new `focus-on-primary` token and a focus-visible rule (WCAG 2.2 §2.4.11 / §1.4.11);
   today's ring equals `primary` and vanishes on a primary button.
4. **Type scale and line-height are tokens, and the canvases follow them** — `typography.scale`
   gains the roles the canvases actually use (row-primary, row-narration, chip, nav-label) so
   11.5 / 12.5 / 14.5 / 15 / 15.5 / 17 / 34 either become tokens or die; **per-role line-heights** with
   an **Indic floor ≥ 1.4** (1.2 clips stacked matras and conjuncts). DESIGN-PACK Step 1 and
   `partials/src/kit.js` read the token file; design-system §4 restates.
5. **One palette source** — `scripts/gen_tokens.dart` emits the canvas band (`--in`, `--out`,
   `--muted`, `--hair`, plus the six tokens with no canvas name: `on-primary`, `focus`,
   `loader-track`, `loader-segment`, `skeleton-label`, `skeleton-amount`); `build-canvas.js` lines
   6–7 are deleted; `--frame` / `--dim` become tokens or go. The
   **token ↔ CSS ↔ Dart ↔ Figma ↔ canvas name map** lives in design-system §4 and 13 §9.
6. **Skeletons and the loader are drawn** — every list screen gets its skeleton variant; O0 slow
   start, R2.0, R2.2 and S16.2 draw the rule with `loader-track` / `loader-segment`, not `--hair` /
   `--text`. DESIGN-PACK Step 5 deliverables gain loading variants.
7. **Dark bands are designed, not swapped** — `kit.js` `FRAME` and `note()` are tokenised; the 17
   `#d9d5cd` frames in Canvas 2's dark sections, pure `#ffffff` on C5 / O5b / S0.5, the template
   orange `#ec3013` on canvas 4 R1, and the `rgba` sheet shadows are removed; Canvas 0 is tokenised.
8. **Amount columns stay Latin digits under the Devanagari-numeral opt-in** (brand §5) — Mukta has
   no tabular Indic digits; design-system rules 4/5.
9. **Paise on screen: none in the app; two decimals in statements and exports.** Rule 5 and 11 §4.4
   are reconciled with DESIGN-PACK Step 0 and the canvases; the amount column is sized without paise.
10. **`scripts/check_contrast.dart` joins `ci.sh`** and computes all four grounds; the prose audit in
    design-system §3 is superseded by its output. `$meta.version` bumps with every value change.
11. `pending`, `locked`, `sunk`, `scrim` are **approved** (PROPOSED flags cleared) — `sunk` with the
    amount-contrast caveat in 2. Reduced-motion track gets a **dark** value; `shadow-soft` gets a dark
    counterpart; `minTouchTarget: 44` becomes a token; nav stroke 1.8 and icon sizes 21/34/36 move
    under `iconography`.
12. **Appearance / theme** setting (system · light · dark) in S13 and 07 §16 — dark mode is required,
    so it must be choosable.
13. **Depth rule** restated: *two levels of navigation below a root; detail viewers and sheets
    (S4.1, S4.2, S20, S7.3, S7.4, S2.4) are exempt.*
14. **13 hygiene** — duplicate rows for S4.1, S6.3, S9.1 merged; S17.2's parent is S17; rows ordered
    by id; version header bumped; §10's "no screen-shaping decision remains open" corrected to point
    here; §4.2's duplicated verification-card atom removed; §2.2 "always visible as a chip" made
    consistent with §2.1 (hidden for an individual); §8 states **LTR only, no mirroring; `lang`-tagged
    user strings** and defers accessibility detail to design-system §3.1.
15. **13 §9 handoff checklist** gains: loading/skeleton variant per list · determinate-loader copy ·
    `lang` attributes, live regions, table semantics, camera-free path · 375×667 **and** 360×800 at
    200% · prototypes for **F9 and F11** (the two flows where money and books are at risk).

## Declined / deferred
- Hard lock for a suspended device — data stays and law 5 forbids the dead end; banner + read-only.
- A per-tenant recovery window — fixed 24 h in v1 so one string ships (05d open ⚠️ 2 closed).
- Designing a `rate_limited` state — silent by ruling.
- Versioning `design/canvas-mirror/` in git — ⚠️ owner; the canvases consume tokens they are not
  versioned with, but the mirror is a pull artefact of the Claude Design project.

## What changed where
07 header, §1.3, §1.7, §2, §3.1 step 5, §3.2, §4, §5 step 2, §5 chooser paragraph, §5.6, §12, §13,
§14, §15, §16, §17, §18, new §§20–28 · 13 header, §2.2, §2.3, §3.1, §3.2 (new rows S1.4, S10.5,
S11.9, S11.10, S15.4, S19.5; depth rule), new §3.4, §4.1 P2/P3, §4.2, §5 F2/F9/F11, §6 (Entry,
Membership, Period, Sync, new Device, new App lock), §8, §9, §10 · design-system §1 rules 4/5, §2,
§3, §3.1, §4, §4.1, §6, §7 · DESIGN-PACK Step 0, Step 1 P1/P2/P3, S1, S15, S15.3, S13, Step 5 ·
tokens.json — a `_proposed_2026-09-05f` note listing the tokens the next token session adds (no value
changes here; `gen_tokens --check` keeps passing) · 11 §4.4, §4.5 one clause each · 09 suite F one
line · 10 M5 row · 05 §9 one clause. Canvases and `kit.js` / `build-canvas.js` are design work for
the next canvas session, listed here so it is not forgotten.

## Open ⚠️
1. Exact hex for the status family, `focus-on-primary`, the darkened light `credit`, and the dark
   reduced-motion track — token session, validated by `check_contrast.dart`.
2. Whether `sunk` may carry amounts at all after the credit darkening, or only labels.
3. canvas-mirror versioning (see Declined).
4. The row-level type roles the canvases use (11.5 … 17) — keep as tokens or collapse to the eight
   in tokens.json; decide when kit.js is re-pointed.
