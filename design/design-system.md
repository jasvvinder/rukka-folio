# Design System — Rukka Folio

**Status:** Phase 0 deliverable, v0.1. Source of truth for values: `design/tokens/tokens.json` (this doc explains; the JSON decides). `tokens.css` (Phase A mockups) and `tokens.dart` (M5 app) are generated views — hand-synced until `scripts/gen_tokens` lands in M0, after which CI fails on drift. Brand authority: `docs/11-brand-guidelines.md` v1.3 §4; screen behavior: `docs/07-ui-flows.md`.

---

## 1. Hard rules (inherited, restated so nobody has to open four docs)

0. **Consequence disclosures outweigh the control they qualify 🔒 (design decision, 31 Aug 2026).** Where a setting sends readable financial data off the phone — the automatic-backup readable copy is the only such case — the disclosure is a **bordered block with an icon at body size**, visually heavier than the toggle above it, never a caption. It is the only element on its screen with that treatment. A disclosure lighter than its control is decoration, not consent.
0b. **Colour and sign are separate decisions 🔒 (conflict resolved 30 Aug 2026).** Brand §4.3's `credit`/`debit` tokens mean *money in / money out* on **consumer** surfaces, where amounts carry `+`/`−`. On **professional** surfaces — the Dr | Cr | Balance statement, trial balance, exports — figures are absolute with a side tag and **never signed**, and colour follows the approved option-A directional rule. A `+` must never appear on a figure in a Dr or Cr column. In code, signs are opt-in via `.signed`; they are never auto-prefixed by the colour class.
1. **Color lives in the numerals.** `credit`/`debit` tint amounts only — never rows, cards, or chips — and every colored amount also carries its sign (`+`/`−`) and column position. The app is near-monochrome; the numbers are the color. (11 §4.3)
2. **`primary` is never a value judgement.** Indigo means "interface", not "good" or "selected-correct". (11 §4.3)
3. **One `accent` per screen, maximum.** (11 §4.3)
4. **Tabular figures on every amount, everywhere** — `tabular-nums` / `FontFeature.tabularFigures()`. Misaligned columns are how accounting software looks amateur. (11 §4.4)
5. **Indian grouping, ₹ prefixed:** ₹1,24,500.00. Latin digits in all locales. (11 §4.4, 01 §1.5)
6. **Dark mode is required**, full token set, hues kept and lifted — never derived by inversion at runtime. (11 §4.3)
7. **Paper, not pixels:** background is `paper`, text is `ink`, structure is hairlines and the 3px left rule — shadows almost never. Decoration must be a rule, a column, or a fold, or it doesn't ship. (11 §4.1)
8. **Containers budget +40%** over English for the longest scripts; text containers never have fixed heights; everything survives OS font scale 200%. (11 §5, 07 §18)
9. **The mark's open state plays only on a real unlock** (m=0.6 biometric, m=1.0 splash; jump cut under reduced-motion). (11 §4.2, 07 §3.1)
10. UI code touches colors/type/spacing **only through tokens** — a hex literal in a widget is a review-blocking defect.

## 2. The two new tokens ⚠️ (owner sign-off needed)

The brand palette had no states for our approval and locking flows; proposed, chosen to sit inside the warm palette and stay distinct from `accent` and `debit`:

| Token | Light | Dark | Used for |
|---|---|---|---|
| `pending` | `#8F5F00` | `#D9A93F` | awaiting-approval entries, in-transit transfers, "sent for approval" chips |
| `locked` | `#8A857A` | `#7A756A` | locked periods, greyed calendar dates, read-only lapsed mode |

Both obey rule 1's spirit: `pending` may tint the status word/icon and the amount; `locked` tints text and disables — neither ever floods a surface. `danger-surface` (soft bahi-tinted background) was also added for the two loud security screens (ceremony mismatch, recovery request) which are the deliberate exception to near-monochrome.

## 3. Contrast audit (computed, WCAG 2.1)

Computed (WCAG 2.1 relative luminance), on light `bg #F5F0E4`: `text` 15.3:1 AAA · `primary` 9.7:1 AAA · `debit` 5.8:1 AA · `pending` 4.9:1 AA (darkened from the first proposal, which measured 4.0) · `text-muted` 4.8:1 AA · `credit` 4.6:1 AA · `accent` 4.1:1 — **below AA by brand-fixed value: use for the seal, icons, and large text only, never body text** · `locked` 3.2:1 — **intentionally sub-AA: marks disabled content, never the only signal (🔒 icon always accompanies)**. Dark set on `#1A1A18`: text 15.3 · pending 8.0 · primary 7.1 · text-muted 6.7 · credit 6.1 · accent 5.5 · debit 4.8 — all amount/text roles ≥ AA. The audit script lives in this repo's history and moves to `scripts/` at M0; re-run on any value change. Grayscale check (07 §18) still applies — ~1 in 12 male users is red-green deficient.

## 3.1 Accessibility conformance 🔒 (target: WCAG 2.2 AA)

**Contrast — computed, both themes, on `bg` *and* `surface`.** All text and amount roles pass AA. Two deliberate exceptions, each safe because it never carries meaning alone: `accent` (light 4.15:1) is restricted to the seal, icons and large text; `locked` (3.23 / 3.80) marks disabled content and is always accompanied by a 🔒 icon. `debit` dark was lifted to `#D4776F` after measuring 4.29:1 on `surface` — below AA — at its previous value. **Re-run the audit on any token change; contrast must be checked against `surface`, not only `bg`.**

**Beyond contrast — the rules that make this app usable non-visually:**
1. **Language of parts (WCAG 3.1.2) 🔒** — account names, notes and party names are user-typed and may be in any of the three scripts *inside* a UI running in another language. Every such string carries its own `lang` attribute (`pa`, `hi`, `en`) so VoiceOver switches voice instead of reading Gurmukhi with an English synthesiser. This is the single most important a11y rule in a trilingual product and it must be implemented at the text-widget level, not per screen.
2. **No timing traps (WCAG 2.2.1) 🔒** — the 10-second entry Undo is a *convenience*, never the only correction path: the entry remains amendable afterwards (02 §5), and the toast is dismissible rather than auto-only. OTP resend countdowns are informational and extendable. Nothing the user must act on expires without a way back.
3. **Status messages (WCAG 4.1.3) 🔒** — save toasts, sync-state chips, review-flag changes and quorum progress announce politely (`aria-live="polite"` / `LiveRegion`) without stealing focus.
4. **Table semantics (WCAG 1.3.1) 🔒** — the A/C statement is a real data table: column headers associated with cells, and each amount announced with its column and side ("two thousand four hundred rupees, credit, balance one thousand three hundred seventy credit"), never as a bare number.
5. **Amount announcements 🔒** — every amount reads as value **plus direction** ("₹2,400, money out"), so the colour's meaning survives with the screen reader on.
6. **Steppers** (denomination grid) expose accessible increment/decrement names and the running line total; the grid is never the only way to record a count except where 02 §8.2 requires it.
7. **Camera-free path 🔒** — the verification ceremony's QR always has the 8-digit code as an equal alternative, so a blind user or a broken camera never blocks joining.
8. **Orientation (WCAG 1.3.4)** — portrait-first, but no screen locks orientation; the statement and reports reflow in landscape, which is also how a low-vision user at 200% scale will read wide tables.
9. **Target size** — ≥ 44pt (AAA), exceeding the 24×24 AA minimum.
10. **Motion** — `prefers-reduced-motion` jump-cuts the mark animation and all transitions.

⚠️ **Not yet verified — must be done on device before release:** VoiceOver pass over the entry flow and the statement table in all three languages; Dynamic Type at 200% on the smallest supported screen; grayscale pass on every screen; and a check that Gurmukhi and Devanagari synthesis is available on the target iOS versions.

## 4. Type, space, structure (summary — values in tokens.json)

Mukta everywhere (Mukta Mahee for Gurmukhi), Noto Sans fallback only. Scale: display 40/600 · page 28/600 · section 20/500 · body 16/400 · table-row 14/400 · caption 12/400 · amount-hero 44/600 · amount-row 16/500. 4pt grid, 16 gutter, 56 min row height. Radii 4/8/12; cards carry the 3px left rule with square corners on that side. Motion: brand easings, 120–400ms; nothing bounces.

## 5. The ledger table — designed first (brand §7 step 4)

The ਨਾਮੇ | ਜਮ੍ਹਾਂ | ਬਾਕੀ statement (01 §1.9) is the first Phase A artifact and constrains everything else. Its acceptance: correct tabular alignment in all three scripts at `table-row` 14px on a 360×800 viewport, b/d and c/d rows present, running balance never wraps, and it passes rules 1–5 above at a glance. English dates abbreviate months; ਪੰਜਾਬੀ/हिन्दी use full month names (owner rule). **No other screen is approved before this one is.**

🔒 **Owner-approved — Dr/Cr cell coloring: option A.** Statement cells color directionally by effect on the user's position (credit token = favorable movement, debit token = unfavorable; on a party khata Dr renders green, Cr red as in the approved mockup). Balance column and header chip carry credit/debit color; a zero balance renders muted. Per-class direction mapping for remaining account classes is verified screen-by-screen during Phase A.

## 6. Phase 0 task list

- [x] tokens.json / tokens.css / tokens.dart (this drop)
- [ ] ⚠️ Owner sign-off: `pending` + `locked` values (§2)
- [ ] ⚠️ Commission lockups **together**: Latin + ਪੰਜਾਬੀ (Gurmukhi) + हिन्दी (Devanagari) — brand §4.2's rule applied to Phase-1 languages; Tamil when its language ships
- [ ] ⚠️ Mark animation as one Rive/Lottie asset from the geometry in 11 §4.2
- [ ] M0: `scripts/gen_tokens` (json → css/dart) + CI drift check
- [ ] Font licensing/bundling check: Mukta & Mukta Mahee (OFL) subset sizes for the APK budget (07: <25 MB)
