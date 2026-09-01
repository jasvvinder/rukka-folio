# ADR 2026-09-01 — One PIN (no Personal-Book PIN), and the import screen IDs

Two owner rulings from the Phase-1 design↔docs audit (findings A1 and A2), ruled 1 Sep 2026.

## 1. One PIN, never two 🔒

**Conflict.** 06 §4.4 (owner-raised, 1 Sep) locked *"One PIN, not two — the Personal
Book's extra lock re-prompts the same PIN or biometric."* But 07 §5.6, 13 §3.2 (S15.2),
and the design pack still specified a **separate 4-digit Personal-Book PIN** with its own
set/confirm and enter screens, and 07 §5.6 + 13 (S15) still described the app-lock
fallback as the **device passcode** — which §4.4 explicitly withdrew (in a joint family
the passcode is common knowledge; that is the reason the MPIN exists).

**Ruling: 06 §4.4 wins everywhere.**
- The app lock's fallback is the **6-digit MPIN**, never the device passcode. Forgot it →
  OTP to the registered number + biometric, then set a new one; never data loss (the MPIN
  is a keystore gate, never a KDF or key wrap).
- The Personal Book's opt-in extra lock **re-prompts the same MPIN or biometric**. There
  is no second number, no 4-digit variant, and no set/confirm flow — enabling the toggle
  (S11 · Devices & security) is the whole setup. The screen keeps the id **S15.2**,
  renamed *Personal Book lock — re-prompt*.

**Changed:** `docs/06-auth-devices.md` §4.4 item 5 · `docs/07-ui-flows.md` §5.6, §15 ·
`docs/13-ux-architecture.md` §3.2 rows S15, S15.2 · `design/DESIGN-PACK.md` S15, S15.2,
S11, S13 briefs. Design side: Canvas 3 screens *S15 "PIN instead"* (drop "Use this
phone's passcode") and both *S15.2 "Personal book PIN"* screens redrawn as the single
re-prompt; stale strings removed from the PA/HI dictionaries.

## 2. Import screen IDs — S7.2 is the balance check 🔒

**Conflict.** 13 §3.2 used **S7.2** for the transfer-pair confirm, while the design pack
and Canvas 8 use **S7.2** for the **balance check** (passing · matched · failing) and
draw the transfer-pair question as a row state inside S7.1.

**Ruling: adopt the design's numbering.** S7.2 = import balance check; the transfer-pair
confirm becomes **S7.3**, a row-level card in the import inbox (matching how it is
drawn and used).

**Changed:** `docs/13-ux-architecture.md` §3.2 (S7.2 redefined, S7.3 added) and flow F4.
