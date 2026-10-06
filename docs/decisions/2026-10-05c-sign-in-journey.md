# ADR 2026-10-05c — The sign-in journey (Canvas 1b): one front door, two paths, SMS only

There was no dedicated sign-in screen. S0.2 *Phone + OTP* served sign-up and device activation alike
(06 §2, 07 §3.2), and a person who already keeps books in Rukka on another phone had to walk into the
fresh-setup flow to find the way in. Desk 131 (*Get my books back* runs before the install can adopt the
account) and desk 129 (whether OTP verification signs up an unknown phone) both came from that gap. On 5 Oct
2026 the owner designed **Canvas 1b · Sign in** (`design/canvas-mirror/Canvas 1b - Sign in.dc.html`; no
partials, the file is its source). On the same day the owner ruled on the three points where the first draft
crossed a locked rule: **SMS only** (ADR 2026-09-25 §1 stands; the canvas was updated), **the old phone scans
the new phone's code** (04 §9.1 🔒 stands; L6 was redrawn), and **a forgotten PIN is reset with the code plus
biometric where the phone has one** (06 §4.4 stands; the canvas owes that step). The owner then asked for the
journey to be adopted into 07 and 13.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. One front door after the welcome slides 🔒 ⟦tests: F1-1005c-1 @M13⟧
- **S0.06 Start** (canvas L0) follows the third welcome slide, in place of a single *Get started*. It offers two
  full-width choices, *I'm new · set up my books* and *I already use Rukka · sign in*, plus the line *Invited by
  someone? Open the link they sent you* (07 §12 stays the invite path).
- Both choices use the same S0.2 phone and code screens. The choice only sets the heading (*Sign in* on the
  returning path) and what happens when the number surprises us (ruling 2). *Set up instead* on the sign-in
  number screen covers a wrong tap without going back through the slides.

### 2. The number answers only after the code 🔒 ⟦tests: F1-1005c-2 @M13⟧
- Nothing about a number's account is shown before its code is accepted (06 §2, no registered-number oracle).
  Before the code, every number gets the same generic answer.
- After the code, the two surprises are handled:
  - **S0.2a This number already has books** (L1): on the *I'm new* path with a number that has books, it offers
    *Sign in to my books*, which continues to S0.2b **without a second code**, or *Use a different number*.
  - **S0.2e No books on this number** (L8): on the *Sign in* path with a number that has none, it offers *Set up
    new books*, which continues to S0.3 **without a second code** and is the sign-up, or *Try another number*.
    This settles desk 129 for the sign-in path: a verified code for an unknown number becomes a sign-up only when
    the person chooses it. Phone change and deletion are not covered by this ruling.
- The person's **own** display name may appear after the code (it is plaintext profile data, 06 §1). Nothing
  about any book or family appears before the phone is certified (ADR 2026-09-05d §2, 07 §3.2).
- The code goes **by SMS only** (ADR 2026-09-25 §1, unchanged): six digits, five minutes, three tries. After the
  third miss the boxes clear and a new code is sent automatically, within the 06 §2 resend backoff and per-number
  limits. It is never a lockout.

### 3. Opening the books on a new phone follows 06 §5, in the person's words 🔒 ⟦tests: F1-1005c-3 @M13⟧
- If platform key sync restores the keys (04 §7.0, S11.5), the person goes straight to silent restore and sees
  no question.
- Otherwise **S0.2b Found you · is your old phone with you?** (L5):
  - *Yes* → **S0.2c Approve from the old phone** (L6). The new phone shows its code; the old phone opens
    *Devices & security → Add a phone* and **scans it** (04 §9.1 🔒, the S9.2 / S9.3 ceremony components). The
    code is good for this one linking only.
  - *No* → the existing recovery fork S11.6 (R2.1). The fork's own rules stand: *Linking is instant — recovery
    takes 24 hours* when another device is active (ADR 2026-09-05d §1).
- **S0.2d This phone is linked** (L7) → S0.8 *Set a PIN for this phone* (each phone has its own MPIN) → Home,
  with no purpose picker and no opening balances. Every tenant is told that a phone was added (ADR 2026-09-05d §6).
- Device registration, certification and notification are unchanged. This ruling adds screens and routing, not
  protocol.

### 4. A forgotten PIN is reset with the code plus the biometric the phone has 🔒 ⟦tests: C-1005c-1 @M13⟧
- S15.3 *Forgot PIN* → the code (U3) → **the phone's biometric** (U3b) → a new PIN (U4). This is 06 §4.4 unchanged.
  The canvas drew U3 → U4 without the biometric step; U3b was added and pushed on 5 Oct.
- On a PIN-only phone (ADR 2026-10-05b) there is no biometric. That path waits on desk 147; until it is ruled,
  the build routes it to the recovery ladder.

## Consequences
- **Docs:** 13 §3.2 gains S0.06, S0.2a–e and the S0.2 sign-in state; 13 §3.3 maps L0–L8 and U1–U4; 13 §5 F1 gains
  S0.06, and a new F1b names the returning path. 07 §3.1 gains the front door, and 07 §3.2 points here. The
  `/design-pull` rules take Canvas 1b as the second `.dc.html` source exception.
- **Design:** done and pushed 5 Oct (owner-approved render): U3b biometric confirm, L6 *Devices & security*, and the
  eight-box code under the QR. Still open: the PIN-only variants of U1 and S15 (desk 148), and canvas 4's S9.2, which
  draws 7 code boxes where 07 §12 says eight (desk 159).
- **Code:** S0.06; the S0.2 sign-in state; S0.2a, S0.2b and S0.2e; routing by `otp/verify`'s account answer **after** the
  code. Note (5 Oct, scoping): there was no such answer; the server signed up every unknown number at verify. SIGNIN1B adds
  `account` / `signup_ticket` / `/signup/adopt`. **S0.2c/S0.2d (own-device linking) is not built and not ruled**
  (`ceremony_sessions.dart:60-64`), so it is PLAN desk 160 (SIGNIN2), and S0.2b's *Yes* is disabled with a reason until then. Desk 131 closes with it: *Get my books back* becomes the
  sign-in path. The design-match index does not yet read `.dc.html` sources (desk 143b), so Canvas 1b frames
  need that before their records can be stamped.
- **Not changed:** OTP rules (06 §2), linking (04 §9.1), the recovery ladder (04 §7), the PIN-reset rule (06 §4.4),
  and the invite path (07 §12).

## Open ⚠️
- ⚠️ Desk 129 is only partly closed: whether `otp/verify` should sign up an unknown phone that arrived for **phone
  change** or **deletion** is still open.
- ⚠️ Desk 147 (PIN-only forgot path) still governs ruling 4 for phones with no biometric.
