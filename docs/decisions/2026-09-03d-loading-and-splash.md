# ADR 2026-09-03d — How the app waits: the loader rule, ruled skeletons, and the splash screen

Follow-on to ADR 2026-09-03c. The designer delivered `docs/brand/rukka-folio-motion-guidelines.html`
(Loading & Splash Guidelines, v1.2 §motion — a self-contained reference implementation). The owner
added it and said "update"; this ADR records it as the ruling on the two items 03c left open.

## Rulings 🔒

1. **No spinner, anywhere.** The mark never loads (its seal-break is earned by a real unlock).
   The loader is a **rule**: a 2px hairline track (ink @14%) carrying an ink segment (30% of
   track) — ink, never indigo or bahi. Indeterminate = continuous 1200ms sweep on the entries
   curve; determinate whenever the app can count, with copy "{done} of {total} {things} {verbed}"
   in tabular figures — counts, never percentages. Appears only after 200ms; past 8s adds one
   plain-language status line. Live-region announced. Reduced motion: static track @25% + text.
2. **Lists load as static ruled skeletons** at the true row pitch (label block ink @9%, width
   38–58%; right-aligned amount block ink @13%), zero layout shift on swap, **no shimmer**, at
   most one screenful.
3. **Splash** = sealed mark + **stacked lockup** ("Rukka Folio", *Folio* weight 300) centred on
   **paper** (dark: ink + inverse mark). OS launch frame and first app frame pixel-identical.
   Then by session state: **locked → nothing plays** (seal breaks only on successful unlock,
   m 0.6) · **open session → sealed→open once, m 1.0** · **failed auth → sealed, shake ±2 units
   ×3, 240ms** · **slow cold start → past 3s the loader rule fades in beneath with "Opening your
   books."** and leaves before any seal-break. Never an artificial delay to finish the animation.
4. **Dark mode** inverts the loader and skeletons exactly (track paper @16%, segment paper).

## Dark credit/debit — ruled 4 Sep 2026 🔒

The reference page lifts dark credit/debit to `#4FA37A` / `#C96A6A`; `tokens.json` (Phase 0
drop) had `#57A87F` / `#D4776F`. **Owner picked the motion-page values,** then accepted a one-step lift of debit to
`#CB6F6F` so that row amounts pass AA on `surface` (4.53:1; `#C96A6A` measured 4.31:1). Same hues,
lightness raised so signed amounts stay legible on ink without going neon. tokens.json, tokens.css,
tokens.dart, 11 §4.5, DESIGN-PACK's dark palette line and the canvas dark band (`--in`/`--out` in
`partials/build-canvas.js`, every canvas rebuilt) updated; the ⚠️ SPEC flags are cleared.

## What changed where

- **11 §4.5** (new) + a *Failed unlock* row in §4.2's usage table. **07 §3.1 line 2** made precise
  (splash plays the animation only when the session is already open). **13 §state machines →
  Sync**: "never a spinner on save" → "never a spinner anywhere". **design-system.md** rules 9
  and new 11–12, §6 tasks, new §7. **DESIGN-PACK** O0, S15, R2.2 prompts.
  **tokens.json** `motion.loader / skeleton / splash / mark-fail-shake`, `loader-*` and
  `skeleton-*` colours (both modes); css/dart hand-synced.
- **Design** — canvas 1 O0 and canvas 11 O0: placeholder line-art → sealed mark + stacked lockup;
  canvas 1 R2.2 waiting rows: circular spinner → inline loader rule.
