# Rukka Folio — Brand Guidelines v1.4

> v1.4 — §4.2 mark geometry aligned to the designer's v1.2 asset drop (owner-ruled 3 Sep 2026): the strap is inset 2 units top and bottom (y14–74) so a hairline of book keeps the silhouette closed on paper and light grounds. Canonical assets: `docs/brand/icons/master/*.svg` (geometry), `docs/brand/rukka-folio-mark-animation.html` (animation reference implementation), `docs/brand/icons/` (store/web icon package v1.2.3). ADR 2026-09-03c. Also adds **§4.5 Motion in product** — loaders, skeleton rows and the splash screen — from the designer's Loading & Splash Guidelines (`docs/brand/rukka-folio-motion-guidelines.html`), owner-ruled 3 Sep 2026, ADR 2026-09-03d.

> v1.3 — "books" defined on first use (books of account / bahi-khata, = the product's Book/ਵਹੀ object) with a marketing term map in §5; idiom rule now applies to our own flagship noun.
> v1.2 — §1 positioning corrected to the finalized product scope (owner-directed): launch languages stated as EN/ਪੰਜਾਬੀ/हिन्दी, no compliance-outcome claims, "ledger app" wording, scope-discipline rule added; §5 segment-register example aligned. All other v1.1 text untouched.

> The working document for the logo, website, pitch deck, mobile app and web app. Everything here is a decision, not a suggestion. Where something is deliberately flexible, it says so.

---

## 1. Positioning

**A ledger everyone in the household, shop, or trust can actually read.**

**"Books," defined once:** everywhere in this document and in all copy, *books* means the **books of account** — the bahi-khata (ਵਹੀ / बही-खाता) — the same object the product itself calls a **Book** (glossary, doc 01). Campaign lines like "One book the whole family can open" are therefore literal product statements, not metaphors. In translation, *books* is always ਵਹੀ-ਖਾਤੇ / ਵਹੀ or बही-खाते / बही-खाता — **never** the literal ਕਿਤਾਬਾਂ / किताबें. In-product wording always follows doc 01.

Indian accounting software splits into two camps. On one side, cash-book apps that are easy but can't do real accounting. On the other, Tally-descended software that is correct but assumes you're a trained accountant.

Rukka Folio sits between them: real double-entry underneath, a surface a joint family's eldest son, a kirana owner, and a temple trust's treasurer can each use without training — in their own language.

**Two differentiators, in this order:**

1. **Legibility.** Competitors' output is correct and unreadable. Ours is correct and obvious.
2. **Directional trust.** The books are open to the people who share the money and closed to everyone else — including us. Zero-knowledge, end-to-end encrypted.

That second point has a shape worth naming precisely, because it's easy to get backwards in copy. We are not a privacy product, and we are not a transparency product. **We are transparent in one direction and sealed in the other.** A joint family's second brother can see the common pool. The vendor — us — cannot. Every piece of trust messaging should preserve that asymmetry.

### Scope discipline (v1.2)

Rukka Folio records what a family, shop or trust actually has — banks, cash, udhaar, advances — and produces books that hold up when someone asks. It does **not** file GST, compute tax, issue invoices, or protect any registration. Those live in Tally and the CA's office; we export cleanly to them (Tally XML, XLSX, PDF) and never compete there. **Positioning, campaigns and sales copy must never promise or imply a compliance outcome.** The promise is always the same shape: when the question comes — from a brother, a partner, a committee, or your accountant — you can answer it in one screen.

### Positioning statement

> For families, small businesses and non-profits in India who need books of account that hold up when someone asks, Rukka Folio is a ledger app that keeps proper double-entry records in the family's own languages — English, ਪੰਜਾਬੀ and हिन्दी at launch — encrypted so that only the people sharing the money can read them. The person keeping the books and the person checking them see the same page, and nobody else sees any of it.

### Segments

| Segment | Who | Emotional job | What they fear |
|---|---|---|---|
| Family | Individual and joint households | "We know where the money goes" | Awkwardness about money between relatives |
| Business | Kirana, traders, small services, SMEs | "My books are ready when asked" | A question about the money — from a partner, a bank, or their CA — they can't answer |
| Non-profit | Trusts, societies, Section 8 | "We can prove every rupee" | A donor's or committee's question their records can't answer |

One brand serves all three. **Content differs; colour, type, voice and layout never do.**

---

## 2. Name

**Rukka Folio.**

- *Rukka* — a written note, a promissory slip, a record. Warm, vernacular, and semantically wider than "cash".
- *Folio* — the ruled page in a ledger; also the cross-reference column in a journal entry. Already familiar to Indians through mutual-fund folio numbers.

### Usage rules

| Context | Form |
|---|---|
| Spoken brand, app icon, in-product | **Rukka** |
| Marketing site, deck cover, invoices, legal | **Rukka Folio** |
| Never | RukkaFolio (one word), RF, Rukka-Folio |

Design the wordmark so *Folio* can drop away. This gives you a short app name and room for Rukka Payroll, Rukka Tax and Rukka GST later without renaming anything.

**Reserved:** *Rokad* is held as an in-product feature name for the simple cash-book view — the mode a shopkeeper opens on day one before touching double entry. It is not a brand name and never appears in marketing.

### Tagline

**Every rupee. Accounted for.**

Two beats, hard stop between them. Never rendered as a single sentence, never with a comma.

It works because it is concrete — "rupee" plants the flag in India in one word — and because completeness is the one thing every segment wants, from the solo user to the trust committee. In English it also carries a second sense: *recorded*, and *all present and safe*. Note that this second sense is English-only; in Hindi ("हर रुपया. हिसाब में.") and the Dravidian languages only the accounting meaning survives. Don't build a campaign on the pun.

Beneath the tagline, always in this order:

> **Every rupee. Accounted for.**
> For homes, joint families, businesses, trusts and societies.
> End-to-end encrypted. We can't read your books.

| Line | Purpose | Where |
|---|---|---|
| Tagline | Permanent, printed, never revised | Logo lockup, deck cover, app store, invoices |
| Scope line | Names the breadth | Site hero, deck cover, app store description |
| Security claim | Dated, specific, provable | Site hero, security page, app store, onboarding |

**Keep the security claim out of the tagline.** Taglines get printed and can't be revised; security claims must be precise, dated, and backed by a published audit. Conflating them means every architectural change becomes a rebrand.

Campaign lines by segment (site and deck only, never in-product, rotate freely):

| Segment | Line |
|---|---|
| Personal | Your books, wherever you are. |
| Family / joint family | One book the whole family can open. |
| Business | Ready when they ask. |
| Trust / society | Every rupee, provable. |

### Before launch

Clear the mark through IP India in classes **9** (software), **35** (accounting services), **36** (financial services) and **42** (SaaS). Run both Wordmark and Phonetic searches. Register `rukkabooks.com` as a defensive redirect. This document is not legal advice — get a clearance opinion.

---

## 3. Personality

**Trustworthy · plain-spoken · quietly precise · warm.**

We are handling people's money and, for trusts, their legal standing. The product should feel like a well-kept physical ledger — solid, orderly, a little handsome.

**We are not:** playful, disruptive, minimal-to-the-point-of-cold, or "fintech". No confetti, no streaks, no gamification of savings. Nobody wants their accounts to feel like a game.

---

## 4. Visual identity

### 4.1 The motif — the ruled column

Every accounting artifact in India is defined by ruled lines and paired columns: the red cloth bahi-khata, the columnar pad, the audit sheet. That is our shape language.

It appears as:

- The binding strap and entry rules of the logo mark
- Hairline rules between rows in every table
- A 3px left rule on cards and callouts (never with rounded corners on that side)
- Slide dividers in the deck
- The two-column structure of the website's hero

**Rule:** if you're adding a decorative element and it isn't a rule, a column, or a fold — don't.

### 4.2 Logo

The mark is a **sealed ledger**: a bound book with its strap fastened by a wax seal, entries visible beside it. It has two states, and the states mean something.

**Sealed** — the brand mark. Used everywhere: app icon, favicon, lockups, marketing, print. A clean rounded square (the book), a binding strap left of centre running almost the full height of the book (a hairline of book shows above and below it), a red seal riding the strap's left edge, and two short entries in the right field. No fold. This is the resting state because it is the promise: *nobody has opened this.*

**Open** — the in-product state only. The strap and seal contract and tuck left (still inside the book, still visible — sealed is always one gesture away), a dog-eared corner folds in at top right (the page in use), and the entries extend leftward into the cleared space, a third one writing itself in. Appears only after a successful unlock: splash end-state, post-auth transition, the "books open" indicator. **Never decorative** — if the open state plays without an actual unlock, it stops meaning anything.

#### Geometry (viewBox 0 0 88 88)

| Element | Sealed | Open |
|---|---|---|
| Book | Rounded square x12 y12 w64 h64, r5, indigo | Same, with corner notch (64,12)→(76,24), underside `#1B2544` |
| Strap | x28 w14, y14–74 — **inset 2 units** top and bottom, paper @93% | Contracts to x24 w9 (translateX −4, scaleX 0.643), 62% opacity; height unchanged |
| Seal | Circle cx28 cy56 r10, bahi red — straddles strap's **left edge** | cx24 r6 — same edge, same relative position, 60% scale |
| Entries | Two, left-aligned x54 w16 (right edge 70); y33, y46.5; h4.5 r2.25; second @55% | Extend to x37 w33, left-aligned as a set; third writes in x37 w0→24 @30% |
| Margins | **6 units** from book edge — seal's left extent and entries' right extent; strap inset 2 units vertically so a hairline of book keeps the silhouette closed on paper backgrounds | Same 6 on both sides |

One geometry at every size. Below 24px, sub-pixel entry strokes may be optically thickened at asset-cutting time — a production decision, not a redesign. The Android 13+ themed (monochrome) icon is the one sanctioned size adaptation: seal squeezed to r7 with an r10 clearance ring, applied at raster level by the icon generator, never to the colour marks (icon package v1.2.3).

**Canonical files.** The master SVGs in `docs/brand/icons/master/` (`mark-sealed.svg`, `mark-sealed-inverse.svg`, `mark-open.svg`, and the icon bases) are the geometry of record; `docs/brand/rukka-folio-mark-animation.html` is the acceptance reference for the animation; `docs/brand/icons/{ios,android,web}` is the shipped icon package. Edit the masters and re-render — never hand-edit PNGs or redraw the mark on a screen.

#### Animation (multiplier m = 1 ≈ 860ms total)

| Beat | Start | Duration | Easing |
|---|---|---|---|
| Strap + seal contract and shift left; strap dims to 62% | 0ms | 400ms | cubic-bezier(.45,0,.25,1) |
| Dog-ear folds in | 240ms | 300ms | ease-in-out cubic |
| Entries sweep left (x 54→37, w 16→33) | 260ms | 340ms | cubic-bezier(.35,0,.2,1) |
| Third entry writes in, left to right | 520ms | 340ms + 160ms fade | same |

Sealing is the exact reverse: entries retract, corner flattens, strap and seal return to full size last. Use m = 0.6 (~520ms) for the biometric-unlock moment; m = 1 for the splash. Respect `prefers-reduced-motion` with a jump cut. Strap, seal and entries are plain CSS transforms/geometry transitions; the fold is a path morph between `M14 14 H74 L74 14 V74 H14 Z` and `M14 14 H62 L74 26 V74 H14 Z` (the path sits 2 units inside the book with a same-colour 4-unit round-joined stroke, so its outline is exactly the 12–76 book) — build the production version in Rive or Lottie as one asset, with `docs/brand/rukka-folio-mark-animation.html` as the acceptance reference. Closing delays: strap/seal 260ms, fold 120ms, entries 0.

#### Usage

| Context | Treatment |
|---|---|
| Favicon, app icon, print, lockup | **Sealed, always** |
| Standard lockup | Mark + "Rukka Folio", horizontal, mark height = cap height × 1.6 |
| Stacked lockup | Mark above wordmark — deck covers and splash only (splash: *Folio* at weight 300, see §4.5) |
| Failed unlock | Mark stays **sealed**; horizontal shake ±2 units, 3 cycles, 240ms. The seal never breaks on the prompt, only on success (§4.5) |
| Wordmark alone | Invoices, PDFs, email footers |
| Android adaptive icons, circular avatars | Inset the mark at ~72% on an indigo field (inverse colourway) — never full-bleed into a circular crop |
| App-store icon rendering | The sealed geometry may be rendered in warm materials (cloth book, stitched strap, wax seal) for the marketing icon layer — same geometry exactly, closed, brand palette only, no satellite elements. The flat mark remains the brand asset. |

**Clear space:** minimum equal to the strap width on all sides. **Never:** rotate, gradient (flat mark), outline, busy backgrounds, recolour, stretch. On dark grounds use the paper-book inverse (paper book, indigo strap and entries, bahi seal), not a white knockout.

**Commission Devanagari and Tamil lockups at the same time as the Latin one.** Not later. If the Indic lockups are an afterthought they will look like one, and that undermines the entire multilingual claim.

### 4.3 Colour

| Token | Hex | Role |
|---|---|---|
| `--ink-indigo` | `#2B3A67` | Primary. Logo, headers, primary buttons, deck backgrounds |
| `--bahi-red` | `#C1502E` | Accent. Sparingly — one accent per screen |
| `--paper` | `#F5F0E4` | Warm background. Never pure white |
| `--ink` | `#1A1A18` | Body text. Never pure black |
| `--credit` | `#2F7A55` | Money in. Numerals only |
| `--debit` | `#A83232` | Money out. Numerals only |

Neutrals are **warm greys**, derived from paper — never blue-grey.

Three rules that matter more than the hexes:

1. **The primary is never a value judgement.** Indigo must never be mistaken for "good" or "selected-correct". Credit and debit colours are visually distinct from both indigo and bahi red.
2. **Colour never carries meaning alone.** Every credit/debit is also signed (`+` / `−`) and column-positioned. Roughly 1 in 12 Indian men is red-green colour deficient; a ledger that fails them is a broken ledger.
3. **The app is near-monochrome.** Let the numbers carry the colour. Marketing may lean into indigo and bahi red; the product should not.

Dark mode is required, not optional — most users will open this app at night after closing shop. Invert to ink background with paper text; keep credit/debit hues, lifting lightness for contrast.

### 4.4 Typography

**Family: Mukta** (Latin + Devanagari + Gujarati + Tamil + Telugu + Kannada + Malayalam + Bengali + Gurmukhi + Odia), falling back to **Noto Sans** for any script Mukta misses.

One family across all nine scripts. This constraint is the single biggest contributor to the brand feeling like one thing.

| Role | Size | Weight |
|---|---|---|
| Display / deck headline | 40–56px | 600 |
| Page heading | 28px | 600 |
| Section heading | 20px | 500 |
| Body | 16px | 400 |
| Table row | 14px | 400 |
| Caption / meta | 12px | 400 |

**Numerals must be tabular-figure, always.** Columns that don't align are the fastest way to look amateur in accounting software. Set `font-variant-numeric: tabular-nums` globally on any element containing an amount.

Amounts use the Indian grouping system — **₹1,24,500.00**, not ₹124,500.00. This is non-negotiable and is a trust signal.

### 4.5 Motion in product — loading and the splash screen

Reference implementation and acceptance test: `docs/brand/rukka-folio-motion-guidelines.html` (every spec below runs live on that page, light and dark). Token values live in `design/tokens/tokens.json` under `motion.loader`, `motion.skeleton`, `motion.splash` and the `loader-*` / `skeleton-*` colours.

**Principles.** Three brand rules corner the design. *The mark never loads* — the seal-break is earned by a real unlock and is never decorative, so the logo cannot be the spinner, and **there is no spinner, anywhere**. *Every decorative element is a rule, a column or a fold* — so the loader is a rule: a 2px hairline carrying an ink segment. *State the number* — whenever progress is known the loader says what it counted, never a percentage. A ledger loads the way a ledger fills: line by line.

#### The loader rule

One component, two modes. Ink segment on a hairline track — **ink, not indigo**: indigo means actionable and a loader is not an affordance. Never bahi.

| Token | Value | Meaning |
|---|---|---|
| `loader-track` | 2px · ink @14% (dark: paper @16%) | The hairline. Minimum height 2 on every platform |
| `loader-segment` | ink (dark: paper) · 30% of track | The moving or filling portion — always the surface's ink, whichever mode |
| `loader-loop-sweep` | 1200ms · cubic-bezier(.35,0,.2,1) | Indeterminate loop, continuous, no pause between sweeps — the entries curve from the mark animation |
| `loader-appear-delay` | 200ms | Operations faster than this show nothing. Flicker is worse than nothing |
| `loader-escalate` | 8s | Past this, add one line saying what is actually happening ("Still working — parsing your bank statement.") |

**Behaviour.** *Determinate* whenever the app can count — restore, statement import, month close, export. Copy pattern: **"{done} of {total} {things} {verbed}"** in tabular figures, Indian grouping from five digits ("1,240 of 3,890 entries restored"). *Indeterminate* only when counting is genuinely impossible, and always with a verb ("Syncing…", never bare). The loader is a live region — "Restoring, 1,240 of 3,890" — an accessible loader is part of the legibility promise. **Reduced motion:** static hairline at 25% ink plus the text; the words do the work.

Flutter: a plain `LinearProgressIndicator` with `minHeight: 2` and token colours, no dependency. Web: a 2px div pair; the CSS in the reference page is canonical.

#### Skeleton rows

Lists load as ruled skeletons: hairlines at the **true row pitch**, a muted label block left (ink @9%, width varying 38–58% so the skeleton doesn't strobe as a grid), a right-aligned amount block (ink @13%, slightly darker — the debit/credit column is present before the data is). Pitch, hairline weight and block positions match the real ledger row exactly, so content swaps in with **zero layout shift**. **No shimmer** — a pulsing gradient is decoration and it isn't a rule, a column or a fold. Show at most one screenful of skeleton rows; beyond that the loader rule with a count is more honest. Skeletons are static in every case; they are already the reduced-motion variant.

#### The splash screen

**Composition.** Sealed mark centred with the **stacked lockup** — mark above "Rukka Folio", *Folio* at weight 300 (§4.2: splash and deck covers are the only sanctioned uses of the stacked lockup). Background is **paper, not indigo** — the app lives on paper and the splash must not flash-cut. Dark mode: ink background with the paper-book inverse mark (seal unchanged). No tagline, no spinner, no version string; splashes are quiet. Once inside the app the wordmark disappears — the product speaks through the ledger, not the logo.

**Two phases, drawn pixel-identical so the handoff is a non-event.**

| Phase | Who draws it | Requirement |
|---|---|---|
| 1 · Launch frame | The OS — iOS storyboard / Android 12+ splash theme | Static sealed mark + lockup on paper. Android: `windowSplashScreenBackground` = paper and the sealed mark supplied as the splash icon — never let it pull the launcher icon |
| 2 · First app frame | Our code | Same mark, size and position as phase 1 |

**Then the session state decides everything.**

| Session state | What plays | Timing |
|---|---|---|
| Locked (auth gate ahead) | **Nothing.** Mark stays sealed through splash and the lock screen; the seal breaks only on successful unlock, never on the prompt | m = 0.6 on success |
| Session already open | Sealed → open, once, then hold open into Home | m = 1 (~860ms) |
| Failed auth | Stays sealed; horizontal shake ±2 units, 3 cycles | 240ms |
| Slow cold start | Hold the sealed mark; past **3s** fade in the loader rule beneath with "Opening your books." The loader leaves before the seal breaks | threshold 3s |

For an end-to-end-encrypted product the locked branch is the common one — on most launches the splash animates nothing, and that is correct: if the splash played the seal breaking and a lock screen followed, the mark would be lying. **Never add artificial delay** to finish the animation for its own sake: if the app is ready, go — completing whichever beat is mid-flight, never cutting the seal-break halfway. Reduced motion: jump cuts throughout.

#### Always / never

| Always | Never |
|---|---|
| Loader is a rule: 2px hairline + ink segment | Spinners, anywhere |
| Counts over percentages when progress is known | The mark as a loading animation |
| Skeleton rows at true pitch — zero layout shift on swap | Shimmer or pulsing skeletons |
| Loader waits 200ms before appearing | Indigo or bahi in the loader — ink only |
| Splash phases 1 and 2 pixel-identical | Artificial splash delay to "finish" the animation |
| Seal breaks only after a real unlock | Seal-break on the auth prompt |
| Live-region announcement on every loader | Percentages where a count exists |

**Dark-mode credit/debit (owner-ruled 4 Sep 2026):** `#4FA37A` / `#CB6F6F` — same hues as light, lightness raised so signed amounts stay legible on ink without going neon. Debit sits one step above the reference page's original `#C96A6A` so that 14–16px amounts reach AA (4.5:1) on `surface`, not only on `bg`. These replace the Phase 0 values (`#57A87F` / `#D4776F`); the reference page's engineering constants block covers both modes.

---

## 5. Voice

Short sentences. Verbs first. Sentence case everywhere.

**Never:** utilize, leverage, seamless, empower, simply, just, easy, effortless, revolutionise. Never an exclamation mark in system copy.

### Patterns

| Element | Write | Not |
|---|---|---|
| Button | Add entry | Create new transaction record |
| Empty state | No entries yet this month. Add your first one. | Nothing here! |
| Error | This entry doesn't balance. ₹500 unaccounted. | Oops! Something went wrong |
| Confirmation | Entry saved | Your entry was successfully saved! |
| Destructive | Delete this entry? It stays in the audit trail. | Are you sure? |

**State the number.** "₹500 unaccounted" beats "the entry is unbalanced" every time. Users are here for numbers; give them numbers.

**No apology theatre.** People auditing a society don't want to be soothed, they want to know what's wrong and where.

**Segment register.** Same voice, different content. Trust onboarding talks about corpus funds and committee questions; family onboarding talks about splitting a grocery bill. Neither is written down to.

### Localisation

- Write English source strings **short and idiom-free**. Every idiom is a translation bug.
- **Assume Tamil and Malayalam run 30–40% longer than English.** Design containers to that, not to English.
- Never concatenate strings to build a sentence — word order differs across your nine languages.
- Numerals stay Latin (0–9) in all locales unless the user opts into Devanagari numerals.
- Financial terms (GST, TDS, ledger, journal) stay in English across all locales **in marketing and search-facing copy**; in-product terminology follows doc 01.
- Marketing term map for the flagship nouns: *books* → ਵਹੀ-ਖਾਤੇ / बही-खाते; *book* (the product object) → ਵਹੀ / बही; *ledger* → ਖਾਤਾ-ਵਹੀ / खाता-बही; *accounts* → ਖਾਤੇ / खाते. Never ਕਿਤਾਬ/किताब for books of account.

---

## 6. Applying it across surfaces

### Fixed everywhere
Logo · type family · colour tokens · credit/debit semantics · the ruled-column motif · voice · Indian numeral grouping · tabular figures.

### Flexible per surface

| | Density | Colour | Illustration |
|---|---|---|---|
| Deck | Airy | Full indigo, bahi accent | Yes |
| Website | Medium | Indigo-led | Sparing |
| Web app | Dense | Near-monochrome | No |
| Mobile app | Dense | Near-monochrome | Empty states only |

### Website
Two-column hero echoing the ledger split. Lead with a real ledger screenshot, not an abstraction. Language switcher in the header, not buried in a footer — it's a headline feature, treat it like one. Three segment paths (family / business / non-profit) below the fold.

### Pitch deck
Indigo backgrounds with paper text on section dividers; paper backgrounds with ink text on content slides. Ruled hairline under every slide title. **Build it last, from real product screenshots.** A deck assembled from mockups reads as a deck assembled from mockups.

### Apps
The web and mobile apps share one design language but not one layout. Mobile is entry-first — the fastest path from opening the app to a saved entry. Web is review-first — tables, filters, reconciliation, reports.

---

## 7. Build order

1. **Name clearance** — IP India, classes 9/35/36/42
2. **Wordmark + mark** — Latin, then Devanagari and Tamil lockups
3. **Tokens** — colour, type, spacing, as code (CSS variables or a shared JSON) that the site and both apps import from one source
4. **The ledger table component** — the hardest and most-used screen. Design it *first* and let it constrain everything else. Test it in Tamil at 14px on a 5-inch phone before you approve it.
5. **Mobile app** — entry flow, then review
6. **Web app** — reports and reconciliation
7. **Website**
8. **Pitch deck** — from real screens

Step 4 is the one people skip. Don't. If the ledger table works in nine languages at small sizes with correct tabular alignment, every other screen is downhill. If it doesn't, no amount of brand polish will save the product.

---

## 8. Quick reference

```
Name        Rukka Folio  (spoken: Rukka)
Tagline     Every rupee. Accounted for.
Mark        The sealed ledger — sealed everywhere; open state in-product, post-unlock only
Personality Trustworthy · plain-spoken · quietly precise · warm
Motif       The ruled column

Indigo      #2B3A67      Bahi red    #C1502E
Paper       #F5F0E4      Ink         #1A1A18
Credit      #2F7A55      Debit       #A83232

Type        Mukta, fallback Noto Sans
Numerals    Tabular figures, Indian grouping — ₹1,24,500.00
Voice       Short sentences. Verbs first. State the number.
```
