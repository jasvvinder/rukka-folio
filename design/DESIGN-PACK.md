# Rukka Folio — Design Pack

**The single file you need to produce wireframes or UI.** Everything required is inside: brand, tokens, patterns, every screen, and real data. No other document needs to be open.

**Use it in steps, not in one paste.** Design tools degrade badly on long prompts; each step below is sized to produce one good result. Work top to bottom — later steps reuse what earlier steps build.

| Step | What you paste | Produces |
|---|---|---|
| **0** | Shared context block | nothing yet — sets brand, tokens, rules for the session |
| **0b** | String sheet | the exact three-language strings — prevents invented translations |
| **1** | P1 · P2 · P3 | the three components 90% of the app is made of |
| **2** | S1 → S10 core screens | the app itself, entity-neutral |
| **2b** | Onboarding set + role variants | first-run flow, and how each screen looks to each role |
| **3** | Entity pack A (Individual) | the baseline app with real data |
| **4** | Entity packs B / C / D | business, trust, joint-family variants and their unique screens, incl. partner positions (S14) and the quorum card (S6.3) |
| **5** | States & deliverables | empty, error, offline variants + the handoff checklist |

**Accessibility is not a later pass:** every amount is announced as value **plus direction**; the statement is a real table with associated headers; user-typed account names carry their own language tag; the QR ceremony always shows the 8-digit code as an equal alternative. Full rules in `design/design-system.md` §3.1.

**Three things the tool will skip unless you insist:** the dark theme, the Punjabi and Hindi versions of every screen, and Mukta Mahee for Gurmukhi rather than a fallback font. Ask for each explicitly.

**Reference while designing:** `docs/13-ux-architecture.md` (screen inventory, flows, states) · `design/design-system.md` (rules and contrast audit) · `design/tokens/tokens.json` (import as Figma variables) · `docs/reference/worked-examples/*.md` (the real figures used below).

## Working across multiple design chats

Each new chat starts blank, so drift between sessions is the main risk. Two habits prevent it.

**The paste ritual — every new chat, without exception:**
1. **Step 0** (brand, tokens, rules)
2. **Step 0b** (string sheet)
3. **Screenshots of the approved P1, P2, P3** and any screen the new one must match, with the line: *"Match these exactly — same row height, type sizes, spacing and colours."*
4. Only then, the screen prompt

**Group screens by pattern, not by feature.** One chat for everything built on P1 (day book, statement, drill-downs, import inbox, review list), one for P2/P3 screens (Home, Inbox), one for onboarding, one per entity pack. Screens that share a component should share a chat — that's where consistency is cheapest.

**After each chat, check the new screens against the last approved set:**
- row height and vertical rhythm identical
- amount type size, weight and tabular alignment identical
- icon size and treatment (outlined, muted) identical
- every label matches Step 0b exactly — no invented translations
- dark mode present · all three languages present

**Keep one running note** of anything you approved that isn't in this pack — a spacing choice, a new label, an interaction. That note is what comes back into `docs/07-ui-flows.md` and `docs/01-glossary.md` at the end. If it contradicts a 🔒 decision, it belongs in `docs/decisions/` as an ADR.

---

# STEP 0 — Shared context *(paste once, at the start of every session)*

You are designing **Rukka Folio**, an iOS-first mobile bookkeeping app for Indian families, small businesses and temple trusts. It replaces the paper bahi-khata: real double-entry accounting underneath, a surface a 55-year-old shopkeeper can use in his own language. Canvas **390 × 844** (iPhone 14/15). Must also hold at **375 × 667** (iPhone SE). Respect iOS safe areas: 47pt status inset, 34pt home-indicator inset — nothing tappable under the indicator.

**Feel:** a well-kept paper ledger, not a fintech app. Warm paper, ink text, structure from thin rules and columns. **Near-monochrome — colour appears almost only on numbers.** Hairlines, never shadows. Cards carry a 3px left rule in indigo, square on that edge.

**Light:** bg `#F5F0E4` · surface `#FBF8F0` · text `#1A1A18` · muted `#6E6A5E` · hairline `#E3DCCB` · primary `#2B3A67` · accent `#C1502E` · money-in `#2F7A55` · money-out `#A83232` · pending `#8F5F00` · locked `#8A857A`
**Dark (required):** bg `#1A1A18` · surface `#24231F` · text `#F5F0E4` · muted `#A5A093` · hairline `#3A382F` · primary `#93A5D6` · accent `#D9754F` · money-in `#57A87F` · money-out `#D4776F` · pending `#D9A93F` · locked `#7A756A`

**Type:** Mukta (Latin/Devanagari) + Mukta Mahee (Gurmukhi). display 40/600 · page 28/600 · section 20/500 · body 16/400 · row 14/400 · caption 12/400 · hero amount 44/600. **All amounts tabular figures, ₹ prefix, Indian grouping (₹1,24,500).**
**Grid:** 4pt · gutter 16 · card padding 16 · row min-height 56 · radii 4/8/12 · touch targets ≥ 44pt.
**Languages:** English, ਪੰਜਾਬੀ, हिन्दी — equal status, every screen in all three. Indic runs 30–40% longer; never fix a text container's height.
**Every label must come from the glossary, not from the tool's own translation.** Duration and status strings in particular: *"Sunita Devi · 11 days"* is **ਸੁਨੀਤਾ ਦੇਵੀ · 11 ਦਿਨਾਂ ਤੋਂ** / **सुनीता देवी · 11 दिन से** — never a literal rendering of English state-words like *open* or *out*. If a string you need isn't in `docs/01-glossary.md`, ask for it rather than translating it.
**Identity & role are always visible:** the top-bar scope chip carries the signed-in user's avatar; tapping it reads "Amrit Kaur · Admin in this book". Where a capability is unavailable to a role, **state the reason in place of the control** — never silently omit it.
**Rules:** colour never alone (always a sign, icon or word too) · indigo never means "good" · one accent per screen · dark mode is a designed theme, not an inversion · nothing bounces.

---

# STEP 0b — String sheet *(paste with Step 0; never translate anything)*

**Use these exact strings. If a label you need is not here, ask for it — do not translate.** Every string below is owner-reviewed by a native Punjabi and Hindi speaker; machine translation has already produced wrong senses (*open* → ਖੁੱਲ੍ਹੀ / खुली, meaning *opened like a door*).

| Use | English | ਪੰਜਾਬੀ | हिन्दी |
|---|---|---|---|
| **Nav** | Home · Ledger · Inbox · Menu | ਹੋਮ · ਖਾਤੇ · ਇਨਬਾਕਸ · ਮੀਨੂ | होम · खाते · इनबॉक्स · मेनू |
| **Verb 1** | Money in | ਪੈਸੇ ਆਏ | पैसे आए |
| **Verb 2** | Money out | ਪੈਸੇ ਗਏ | पैसे गए |
| **Verb 3** | Gave on credit | ਉਧਾਰ ਦਿੱਤਾ | उधार दिया |
| **Verb 4** | Took on credit | ਉਧਾਰ ਲਿਆ | उधार लिया |
| Transfer · Fix/Adjust | Transfer · Fix | ਟ੍ਰਾਂਸਫਰ · ਠੀਕ ਕਰੋ | ट्रांसफ़र · ठीक करें |
| Hero label | Total money you have | ਕੁੱਲ ਪੈਸੇ | कुल पैसे |
| Books balanced | Books balanced | ਹਿਸਾਬ ਮਿਲਦਾ ਹੈ | हिसाब मिलता है |
| Receivable row | You will get | ਲੈਣੇ ਹਨ | लेने हैं |
| Payable row | You will give | ਦੇਣੇ ਹਨ | देने हैं |
| Advance row | Advance out | **ਐਡਵਾਂਸ** | **एडवांस** |
| Advance held | Advance with you | ਤੁਹਾਡੇ ਕੋਲ ਐਡਵਾਂਸ | आपके पास एडवांस |
| **Ageing meta** | Sunita Devi · 11 days | ਸੁਨੀਤਾ ਦੇਵੀ · **11 ਦਿਨਾਂ ਤੋਂ** | सुनीता देवी · **11 दिन से** |
| Ageing chips | > 30 days · > 90 days | 30 ਦਿਨਾਂ ਤੋਂ ਵੱਧ · 90 ਦਿਨਾਂ ਤੋਂ ਵੱਧ | 30 दिन से ज़्यादा · 90 दिन से ज़्यादा |
| In transit | In transit | ਰਸਤੇ ਵਿੱਚ | रास्ते में |
| This month | This month · In · Out | ਇਸ ਮਹੀਨੇ · ਆਏ · ਗਏ | इस महीने · आए · गए |
| Cash | Cash in hand · Galla · Gollak | ਰੋਕੜ · ਗੱਲਾ · ਗੋਲਕ | रोकड़ · गल्ला · गोलक |
| Last counted | Last counted 27 Aug | ਆਖ਼ਰੀ ਗਿਣਤੀ 27 ਅਗਸਤ | आख़िरी गिनती 27 अगस्त |
| Today / Yesterday | Today · Yesterday | ਅੱਜ · ਕੱਲ੍ਹ | आज · कल |
| Buttons | Save · Undo · Approve · Reject · Skip | ਸੇਵ ਕਰੋ · ਵਾਪਸ ਲਓ · ਮਨਜ਼ੂਰ ਕਰੋ · ਰੱਦ ਕਰੋ · ਛੱਡੋ | सेव करें · वापस लें · मंज़ूर करें · रद्द करें · छोड़ें |
| Awaiting review | Waiting for approval · {name} will review | ਮਨਜ਼ੂਰੀ ਬਾਕੀ · {name} ਜਾਂਚ ਕਰੇਗੀ | मंज़ूरी बाकी · {name} जाँच करेंगी |
| Old entries | Old entries waiting | ਪੁਰਾਣੀਆਂ ਐਂਟਰੀਆਂ ਬਾਕੀ | पुरानी एंट्रियाँ बाकी |
| Statement cols | Dr · Cr · Balance | ਨਾਮੇ · ਜਮ੍ਹਾਂ · ਬਾਕੀ | नामे · जमा · बाकी |
| Bank cols | Money in (Dr.) · Money out (Cr.) | ਪੈਸੇ ਆਏ (ਨਾਮੇ) · ਪੈਸੇ ਗਏ (ਜਮ੍ਹਾਂ) | पैसे आए (नामे) · पैसे गए (जमा) |
| Creditor cols | You paid (Dr.) · You took (Cr.) | ਤੁਸੀਂ ਦਿੱਤੇ (ਨਾਮੇ) · ਤੁਸੀਂ ਲਏ (ਜਮ੍ਹਾਂ) | आपने दिए (नामे) · आपने लिए (जमा) |
| Balance rows | Opening balance · Closing balance | ਸ਼ੁਰੂਆਤੀ ਬਕਾਇਆ · ਅੰਤਿਮ ਬਕਾਇਆ | शुरुआती बकाया · अंतिम बकाया |
| Close | Close the month · Close the year | ਮਹੀਨਾ ਬੰਦ ਕਰੋ · ਸਾਲ ਬੰਦ ਕਰੋ | महीना बंद करें · साल बंद करें |
| Count | Count cash · Open and count | ਰੋਕੜ ਗਿਣੋ · ਖੋਲ੍ਹ ਕੇ ਗਿਣੋ | रोकड़ गिनें · खोलकर गिनें |
| Ceremony | Show my code · Verify | ਮੇਰਾ ਕੋਡ ਦਿਖਾਓ · ਤਸਦੀਕ ਕਰੋ | मेरा कोड दिखाएँ · तसदीक करें |
| Guardian / recovery | Trusted member · Recovery sheet | ਭਰੋਸੇਮੰਦ ਮੈਂਬਰ · ਰਿਕਵਰੀ ਪਰਚੀ | भरोसेमंद सदस्य · रिकवरी पर्ची |
| Reconciliation | Family match check | ਪਰਿਵਾਰ ਮਿਲਾਨ | परिवार मिलान |
| Entry preview | ₹2,400 · Cash A/c → Diesel Expense A/c · {note} | same shape, same arrow | same shape, same arrow |

**Two rules that produced errors before:**
1. **Never translate English state-words** — *out, open, pending, due*. Say the fact instead: elapsed time uses **ਤੋਂ / से** (*since*), never an adjective.
2. **No gendered participles in labels** (ਦਿੱਤੀ / दी) — they must agree with nouns that vary. A bare noun is always the safer label.

**Loanwords are correct where people use them:** ਐਡਵਾਂਸ, ਬੈਂਕ, ਐਂਟਰੀ, ਕੋਡ, ਟ੍ਰਾਂਸਫਰ / एडवांस, बैंक, एंट्री, कोड, ट्रांसफ़र. Do not "purify" these into Sanskritised forms.

**Full string set:** `docs/01-glossary.md`.

---

# STEP 1 — The three core patterns *(build these before any screen)*

## P1 — Entry listing pattern *(build first, it appears on six screens)*
Design a reusable list pattern. Above: a pill segmented control **Daily · Monthly · Yearly · Custom**, and below it a row with ← arrow, tappable period label with chevron, → arrow. Then repeating groups: a **group header** strip in a slightly darker surface showing the date label on the left and a balance figure on the right; under it, entry rows of — a 34px circular **outlined** icon (muted glyph on surface fill, hairline border, never a saturated disc), then a two-line block (primary label 14.5px; narration beneath 11.5px muted), then a right-aligned amount 15px with a small directional arrow before it (up = money out/owed more, down = money in/paid). Pending rows tint label, narration and amount in the pending colour with a small clock. **No date column, no voucher number.**

## P2 — Position card
Design a card: optional label row, then 2–5 rows of `label ······ value`, value right-aligned tabular with colour and a chevron where drillable. Small muted meta text may follow a label ("Advance out · Ramesh"). Card uses the 3px indigo left rule.

## P3 — Attention card
Design a card for items awaiting a person: 36px circular avatar with initials, then "Name · Book name" on line one and "7 entries · ₹23,400 · today" on line two; an expandable list of up to 3 items each with a photo icon, label, amount and a small ✕ on the right; a "+ 4 more" link; then two side-by-side buttons — a solid-outline primary and a plain secondary.


---

# STEP 2 — Core screens *(entity-neutral)*

## S1 — Home
Design the home screen, top to bottom: top bar with a scope chip (pill, book name + chevron) and sync/notification icons right. Then **hero**: small muted caps label "TOTAL MONEY YOU HAVE", a 34px bold tabular amount, and a muted breakdown line beneath ("Indian Bank ₹47,000 · Cash ₹14,500"). Then a **books-balanced card** — green check icon, "Books balanced" in green, chevron right, and beneath in muted tabular text "Dr ₹8,56,200 = Cr ₹8,56,200 · no difference". Then a **position card** (P2) with rows: You will get (green) · You will give (red) · Advance out (with the holder's name as meta). Then a slim **month card**: muted "This month" left, "In ₹1,75,000 · Out ₹1,38,200" right in green/red. Then a "Today · 30 Aug ▸ day book" label and 3 entry rows. Then, **docked directly above the bottom navigation**, a 4-across grid of verb buttons — Money in · Money out · Gave on credit · Took on credit — each a bordered tile with an icon above a 2-line-safe label. **The verb buttons carry no figures.** Bottom nav: Home · Ledger · Inbox (badge) · Menu.

## S2 — Add entry *(one screen, three states)*

**One screen that never navigates, never overlays and never scrolls.** The lower region swaps in place: keypad by default, account list when the counterpart slot is tapped, keypad again once chosen. Everything above stays put throughout.

**Layout, top to bottom:** close ✕ and a coloured verb chip (swipeable to change the verb) · the amount, very large and tabular, ₹ prefixed — **no amount-in-words** · the money-account **chip row** under its verb-dependent label · the **counterpart slot** reading "Choose an account" · a row of small chips for date, note and camera · the **live preview line** · the swapping region · **Save**.

**Three states to design:**
1. **Typing** — keypad in the lower region. Nothing is pre-selected: no chip ticked, counterpart empty, Save greyed.
2. **Choosing** — the counterpart slot is highlighted and the **account list has replaced the keypad in the same space**: a search field, then plain rows of icon + account name, then "+ Create a new A/C". Not a sheet sliding over, not a new screen — the amount and chips above remain visible.
3. **Chosen** — the keypad returns, the preview line completes, Save turns solid.

🔒 **Nothing is remembered between entries** — no default account, no last-used, no repeat shortcuts anywhere. Explicit choice every time.

**Slot labels change with the verb — never a fixed "FROM":**

| Verb | Chip row | Counterpart slot |
|---|---|---|
| Money in | **INTO** | **FROM** — an income like Shop Sales, or a person paying you back |
| Money out | **FROM** | **FOR** — an expense, or a person you are paying |
| Gave on credit | **WHAT DID YOU GIVE** | **TO WHOM** — the person leads |
| Took on credit | **WHAT DID YOU TAKE** | **FROM WHOM** — the person leads |

The chip row shows the money accounts plus a **+** chip for the rest. Design one variant with **no chip row at all** — milk taken on khata touches no bank or cash.

## S2 (variant) — Live preview line

One line above Save that **fills as the user works**, not at the end. Design all five states:

| State | Line |
|---|---|
| Empty | `₹0 · ⋯ → ⋯`, muted, dotted placeholders |
| Typing | amount updates every digit, Indian grouping live |
| One side chosen | `₹2,400 · ਰੋਕੜ ਖਾਤਾ → ⋯` |
| Complete | `₹2,400 · ਰੋਕੜ ਖਾਤਾ → ਡੀਜ਼ਲ ਖਰਚ ਖਾਤਾ`, full ink |
| With note | `· ਇਸੁਜ਼ੂ ਗੱਡੀ ਦੇ ਡੀਜ਼ਲ ਲਈ` appended, lighter type |

It **reserves its full height from the first frame** so nothing below shifts as it fills. Empty slots are **dotted placeholders, never blank** — the line should read as a sentence with gaps. When the last slot lands the line goes from muted to full ink **and Save turns solid at the same moment**: that state change is the validation, so no error message is ever needed. Read-only, nothing tappable inside it. Also design the two-line wrap with long Gurmukhi account names.

## S3.1 — Quick add sheet *(from the Ledger tab only — not the entry flow)*
*Two presentations of the same picker, deliberately different: **S2-C** is a full screen because it is step 2 of 2 in the entry flow; **S3.1** is a bottom sheet because adding a khata from the Ledger tab is a small side task you return from. Do not merge them.*

Design a bottom sheet: search field at top with the cursor active, a horizontal row of recent account chips, then a scrolling list of accounts each with an outlined icon, name, and current balance right-aligned in muted text. The first row when the search has no exact match reads **"+ Create 'Langar' A/C"** in indigo.

## S3 — Ledger index
Design an A–Z list of accounts: search field as the header, filter chips (All · People · Categories · Money), a sticky alphabet rail on the right edge, and rows of icon + account name + balance with its side tag ("₹1,370 Cr" / "₹1,370 ਜਮ੍ਹਾਂ"). Balances coloured only for people you'll get from (green) or give to (red).

## S4 — A/C statement
Apply **P1** with a header: account name (20px), account type and financial year in muted text beneath, then a line "You will give ₹1,370" with the amount larger and red. Group headers carry the **running balance at end of that day** with its side tag. Rows show the counter-account as the primary label ("Milk Expense A/c") and the user's own note beneath ("Milk taken on credit"). Footer: a closing-balance strip and two text buttons — PDF and WhatsApp.

## S6 — Inbox
Design a single tray screen: title "Inbox", "3 waiting" beneath, then a vertical stack of **P3** cards of different kinds — entries to review, bank lines to classify, an invitation awaiting verification. Each card's primary button differs ("Approve all 7", "Classify 12 lines", "Verify Ramesh").

## S6.3 — Structural approval card
Design an Inbox card for a change that needs several owners' consent. Header: who proposed it and when ("Amrit Kaur proposed · today"). Body: a plain before/after statement of exactly what will change — e.g. two small rows "Now: Amrit 33.3% · Sukhdev 33.3% · Harjit 33.3%" and "After: Amrit 40% · Sukhdev 30% · Harjit 30%", the changed figures emphasised. A quorum progress line with small avatars: "2 of 3 approved · waiting for Harjit". Two buttons: **Approve** (indigo) and **Veto** (red outline, opens a reason field). A muted footnote: "Nothing changes until everyone approves."

## S6.2 — Review stepper
Design a full-screen review step: header "Review 3 of 7" with a dot progress indicator; a large bill-photo area; the entry's label and amount (24px, coloured); a muted meta line "30 Aug · 12:11 pm · by Ramesh · note: labour and material"; three equal buttons at the bottom — Reject (red outline) · Skip (plain) · Approve (indigo, emphasised).

## S7.0 — Statement import: file & mapping
Two screens. **Upload:** the bank account preselected as a chip at top, then a large dashed drop zone with a cloud icon and the text "Tap to choose a file", and beneath it in muted type "CSV, XLS, OFX or PDF · up to 10 MB". **Column mapping:** a preview of the first three rows of the file as a small table, and above it four dropdowns already filled with the app's guesses — Date · Description · Money out · Money in — each changeable, plus a muted line "We'll remember this for {bank name}". Sticky button: **Looks right, continue**. Design a *duplicates skipped* banner for the next screen: "12 lines already imported — skipped".

## S7.1 — Statement import inbox
Design a list where each row is a parsed bank line: the bank's raw text in small grey ("ATM WDL SBI0192"), the amount labelled **Money out ₹20,000** in red (or Money in, green), and beneath it a prominent single question in indigo — **"Where did it go?"** (or "Where did it come from?") — as a tappable field. The bank's own text sits at the top of each row in **muted monospace**, never editable — it is evidence, not the user's words. It is **truncated to one line with a tail ellipsis** and expands on tap — Indian UPI narrations run long (`UPI/DR/425634789012/VERMA DAI/HDFC/vermadairy@okhdfc/Payment for milk`). Design both states. A classified row carries a subtle **+ note** link opening a small inline field for the user's own words, shown in **normal type** directly beneath the account — the monospace/normal contrast is what tells the two apart with no label. Design the row with and without a note. A classified row carries a subtle **+ note** link that expands a small inline field; design the row both without and with a note present. Show four row states: matched (green tick, auto-linked), suggested (one-tap confirm chip), new (question unanswered), and a transfer-pair row asking "Is this the same money moving between your accounts?" with Yes / No.

## S9.2 / S9.3 — Verification ceremony
*Context for the designer: this is a 30-second face-to-face handshake when someone joins. The app cannot trust the server's word about who a new member is, so two people confirm it in person — one shows a code, the other scans it. Get the tone right: routine and quick, not alarming — until it fails, when it must be unmissable.*

Two screens. **Show my code:** large QR centred on paper background, beneath it an 8-character code rendered as **eight separate bordered boxes** (`8 F 2 - K 9 P 4`) with a small expiry countdown, and a Regenerate link. **Verify member:** camera viewfinder with corner target lines, instruction line "Ask them to open *Show my code*", and a text button "Enter code instead". Also design the **mismatch screen**: full-bleed red, large warning icon, "Do not proceed", explanation, single "Contact support" button, no dismiss.

## S5.5 — Cash count sheet
Design a counting screen for a cash account. Top: the running **counted total**, large and tabular, updating as the user counts; beneath it in muted text the book balance and the difference stated in words ("₹230 less than the book — we'll adjust it", or "Matches the book ✓" in green). Body: a denomination grid, one row per note — **₹500 · ₹200 · ₹100 · ₹50 · ₹20 · ₹10** — each row showing the note value on the left, a −/+ stepper with the count in the middle, and the line total right-aligned and tabular; then a single **Coins** row with a value field rather than a stepper. Optional collapsed section with two name fields, *Counted by* and *Witness* (used by gurudwara committees, where two people always count). Sticky footer button: **Save count**. Design an *empty* state (all zeros, total ₹0) and a *matched* state (green tick, no adjustment needed).

**Two modes, same screen.** **Verify mode** (household cash, shop *galla*) is as described above — book balance and difference shown, denomination grid optional with a "just enter the total" link — except in a trust book, where it is always required. **Collect mode** (gurudwara *gollak*, donation box) shows **no book balance and no difference** — the counted total *is* the amount received — with the header reading "Open and count", the denomination grid mandatory, and the two name fields expanded and required. Design both.

## S7.2 — Balance check strip
A slim strip that sits above the import inbox: two rows with tick or warning icons — "Opening balance matches your book ✓" and "Closing will match once these 23 lines are recorded". Design the failure variant too: an amber row reading "Opening is ₹4,200 different — an earlier statement may be missing" with a "What do I do?" link.

## S10 — Month close wizard
Design step 1 of 4: header "Close August · Step 1 of 4" with a progress bar; title "Count your cash"; a large tabular input pre-filled with the book figure; beneath it, once a different number is typed, a muted line "₹230 less than the book — we'll adjust it"; a wide primary Next button. Also design **step 3 (the tray)**: two clearly separated groups — a red-tinted "Must clear before closing" list (unexplained bank lines, entries awaiting review) each row tappable to resolve, and a muted "Worth checking" list (aged advances, cash not counted) that does not block, with a plain line stating the difference. And **step 4**: a summary list of declared balances with a lock icon and the button "Confirm & lock August".

## S10.1 — Family close status *(multi-book tenants)*
A compact list inside the wizard showing every book's state: "Kirana Store — closed ✓" · "Agriculture Business — waiting on Pankaj" (with avatar) · "Joint pool — not started". The karta needs to see who he is waiting for.

## S10.2 — Month summary card *(the reward screen)*
The screen shown immediately after a book locks — a shareable card, not a receipt. Large month name, three figures ("In ₹1,75,000 · Out ₹1,38,200 · Saved ₹36,800" with the saved figure emphasised), then the three largest expenses as small rows with icons, and in a joint family a per-sub-family line. Bottom: **Share on WhatsApp** (primary) and Done. Warm, celebratory but quiet — a tick, not confetti. Design it to look right as an exported square image.

## S0.3 / S0.5 — Onboarding
**Purpose picker:** "What will you use this for?" with **five** large illustrated cards — a 2×2 grid of Myself · My shop · My businesses · My family, plus **Our trust** full-width beneath carrying the muted subtitle *gurudwara, temple, society or registered trust* — illustration style of paper, hands, shops and homes; never fintech gradients or 3D coins. **Recovery sheet:** a calm screen explaining plainly "Your books are locked so well that even we cannot open them", a preview of a printable A4 sheet with a QR, and two buttons — Print / Save · I've kept it safe.


---

# STEP 2b — Onboarding & role variants

## O1 · Language picker
The first screen ever shown. Three large tap targets — **English · ਪੰਜਾਬੀ · हिन्दी** — each rendered in its own script at 24px, on paper background, with the Rukka Folio mark above. No other chrome, no skip.

## O2 · Phone & OTP
Phone entry with a fixed +91 prefix and a large numeric field; then the OTP screen with six separate character boxes, a resend countdown, and one muted line: "We only send this when you set up a new phone." No password field anywhere, ever.

## O3 · Purpose picker
"What will you use this for?" — **five** large illustrated cards: a 2×2 grid of **Myself · My shop · My businesses · My family**, with **Our trust** as a **full-width card beneath** (five will not divide into a grid). This card alone carries a subtitle in smaller muted type — *gurudwara, temple, society or registered trust* — a deliberate asymmetry: the other four are self-explanatory, this one is not, and a mandir or sabha committee member must recognise themselves in it. Illustration style: paper, hands, shopfronts, homes — line-drawn, warm, never fintech gradients or 3D coins. A muted line beneath: "You can change this later."

## O4 · Name & photo
Name field, optional circular photo picker, and a muted explanation: "Your family sees this when they approve your entries."

## O5 · Recovery sheet *(the screen that must not feel like a chore)*
Calm, serious, one idea per line: heading "Only you can open your books", body explaining plainly that the data is locked so completely that even the makers cannot open it, therefore a paper key matters. A preview thumbnail of the printable A4 sheet with its QR. Two buttons: **Print / Save the sheet** (primary) and **I've kept it safe** (secondary, disabled until the sheet has been opened once).

## O6 · Opening balances wizard
Three steps with a progress bar: bank and cash balances (rows with account name and amount field) · "Does anyone owe you?" (add-person rows, amount, marked *you will get*) · "Do you owe anyone?" (same, *you will give*). A "Skip for now" link on each — the setup checklist on Home will bring them back.

## O7 · Join by invitation
The invitee's alternate path: after O2, a screen reading "Amrit Kaur has invited you to Sharma Family" with the roles being granted listed as chips, and two buttons — Accept · Not now. On accept, the pending-verification state: "Your own book is ready. Meet Amrit to unlock the family books."

## O8 · Setup checklist (Home, first run)
Home with the position card replaced by a 4-item checklist — Opening balances · First entry · Keep your recovery sheet · Add your family — each with a tick circle and a chevron, and a quiet line at top: "A few minutes now, and your books are live."

## R1 · Role variants *(design each as a variant set, not separate screens)*
Take **Home**, **Add entry**, **A/C statement**, **Inbox** and **Members**, and produce a variant for each role: **Admin · Head · Member · Operator · Viewer**. The differences to show:
- **Admin** — Home carries an extra admin-actions card; Members screen has invite/remove/role controls; close button present.
- **Head** — same as admin minus member management; can confirm close for own book only.
- **Member** — no P&L figures on Home; entry posts but may show "Sunita will review"; statement has no amend/reverse.
- **Operator** — day totals only, no P&L, no other books in the switcher; Inbox shows only their own rejected items.
- **Viewer** — every entry control **replaced by a stated reason** ("You can view this book"), export still available, Inbox shows its empty state.
Each variant must show the identity chip reading the user's name and their role **in this book**.


## R2 · Recovery on a new phone *(the flow that decides whether someone loses their books)*

*Context for the designer: there are no passwords in this app, and the company genuinely cannot open anyone's data. When someone loses their phone, these screens are the only way back. The person using them is anxious and possibly at a shop counter. Tone: calm, plain, never blaming, never alarming — and never falsely reassuring.*

**R2.1 · After OTP on a new phone — the fork.** A quiet screen: "Let's get your books back on this phone", then three options as full-width rows, in this order, each with a one-line explanation: **Use another phone you're signed in on** · **Ask your trusted members** · **Use your recovery sheet**. A muted line at the bottom: "Your family books can also be restored by your family — your own private book cannot."

**R2.2 · Ask your trusted members (S11.2).** The live waiting screen. Heading "Ask any 2 of 3 to approve", then a row per guardian with avatar, name, and a state: **approved ✓** (green) · **waiting…** (muted, with a quiet spinner) · **not asked**. Each waiting row has a small **Call** link — the pack's advice is literally "phone them, they are expecting this". A progress line: "1 of 2 approvals". Design the **completed** state too: all ticks, then a single calm line "Restoring your books…" with a progress bar. This screen may be open for minutes; it must not feel stuck.

**R2.3 · Guardian's side.** The approval that arrives on someone else's phone: photo and name of the person asking, the words "wants to restore their books on a new phone", the new device's name and fingerprint in small monospace, and a **prominent caution**: "Call them first to be sure it is really them." Two buttons — **Approve** (indigo) and **Not now** (plain). This is a security decision made by a relative, so the caution must be impossible to skip past.

**R2.4 · Use your recovery sheet (S11.3).** Camera view for scanning the QR from the printed sheet, with a small illustration reminding them what the sheet looks like, and beneath it **Type the code instead** opening a grouped character field. Design the **failure** state: "That code didn't work" with the two likely causes stated plainly — a newer sheet was printed, or the code was mistyped — never a blank error.

**R2.5 · Nothing worked — the honest screen.** No euphemisms. "We could not restore your private book." Then, in plain language: the family and business books can be restored once the family verifies them again on this phone; the private book is gone, and this is the privacy they were promised working as intended. One primary action: **Continue and set up this phone**. No retry loop, no false hope.

## R3 · Devices & security (S11) and guardian setup (S11.1)

**S11 · Devices & security** — a settings screen listing: **This phone** and other signed-in devices (name, last active, a Revoke link, and a red **This phone was stolen** path); **Trusted members** with their names and a "change" link; **Recovery sheet** showing its status (*kept safe · printed 12 Apr* or a warning badge *not yet confirmed*); **Personal book PIN** toggle.

**S11.1 · Guardian setup** — choosing 2 of 3: a member list with checkboxes and a rule line "Any 2 of the 3 you choose can help you get back in", then a per-guardian checklist showing the mutual verification ceremony as **done ✓** or **meet them** — because guardians verify in both directions. Finish is disabled until all are verified.

---

# STEPS 3 & 4 — Entity packs

**Order: Individual (baseline) → Business → Trust → Joint Family (most complex, reuses everything).** All figures are real, from the verified worked examples — designing with true numbers exposes layout problems that placeholder data hides.

## A · INDIVIDUAL — Rahul Sharma

*One personal book. The scope chip is **hidden entirely** — the app simply is his book.*

### A1 · Home
Follow the S1 prompt with this content: **no scope chip** in the top bar (title reads "Rukka Folio" or nothing at all). Hero label "TOTAL MONEY YOU HAVE", amount **₹4,81,000**, breakdown line "Axis Salary ₹3,54,600 · SBI Savings ₹1,09,400 · Cash ₹17,000". Books-balanced card: "Dr ₹5,94,800 = Cr ₹5,94,800 · no difference". Position card rows: **You will get ₹9,000** (green, meta "Sundar Singh") · **You will give ₹18,600** (red, meta "Raman USA, Vardhman Dairy"). No advance row — a solo user has none. Month card: "In ₹95,000 · Out ₹44,600". Today's entries: "Vardhman Dairy — paid ₹6,800", "Milk bill — ₹3,600", "Household provisions ₹9,200".

### A2 · Ledger index
Accounts to show: Axis Salary A/c · SBI Savings A/c · Cash in Hand · PNB Credit Card A/c · Sundar Singh A/c (₹9,000 you will get) · Raman USA A/c (₹15,000 you will give) · Vardhman Dairy A/c (₹3,600 you will give) · Household Expense · Milk Expense · Education Expense · Medical Expense · Travel & Fuel Expense · Insurance Expense · Salary Income.

### A3 · Statement — the dairy khata
Apply S4 to **Vardhman Dairy A/c**, creditor, closing **₹3,600 Cr** ("You will give"). Rows alternate: "By Milk Expense A/c / *Vardhman Dairy monthly milk bill received*" and "To Cash in Hand / *Paid Vardhman Dairy June and July bills*". This is the screen a family member reads most often — get it right first.

### A4 · Onboarding variant
Purpose card **"Myself"** selected → seeded accounts preview: Cash in Hand, one bank, Household · Milk · Education · Medical · Travel expense categories, Salary income. Opening-balance wizard asks bank and cash balances, then "Does anyone owe you, or do you owe anyone?".

---

## B · BUSINESS — Sharma Textile

*Personal book + one business book. Scope chip shows two chips. Adds customers, suppliers, drawings.*

### B1 · Home (business scope)
Hero **₹1,50,500**, breakdown "Indian Bank Current ₹20,500 · Business Cash ₹1,30,000". Books-balanced: "Dr ₹8,56,200 = Cr ₹8,56,200". Position card: **You will get ₹1,44,000** (meta "Guru Nanak Cloth House") · **You will give ₹1,81,200** (meta "Tuglaq Yarn, Avtar Transport"). Month card "In ₹38,000 · Out ₹55,000". Today: "Counter cash sales +₹38,000", "Owner's drawings −₹30,000". Verb labels stay the same four.

### B2 · Ledger index
Indian Bank Current A/c · Business Cash A/c · Guru Nanak Cloth House A/c (customer, ₹1,44,000 you will get) · Tuglaq Yarn Company A/c (supplier, ₹1,70,000 you will give) · Avtar Transport Co. A/c (₹11,200 you will give) · Purchases · Rent · Staff Salary · Freight · Shop Utility · Packing & Misc · Sales · Drawings.

### B3 · Statement — customer khata (the side-flip case)
Apply S4 to **Guru Nanak Cloth House A/c**, debtor, closing **₹1,44,000 Dr** ("You will get"). Contextual headers must read **Sold on credit (Dr.) / Payment received (Cr.)**. Rows: "To Sales A/c / *Cloth sold on credit*" and "By Indian Bank Current A/c / *Paid by UPI*".

### B4 · Statement — supplier khata
Same pattern for **Tuglaq Yarn Company A/c**, closing **₹1,70,000 Cr**, headers **You paid (Dr.) / You bought on credit (Cr.)**.

### B5 · Drawings confirmation sheet *(business-only screen)*
When money moves from the business to the owner personally: a confirmation sheet titled "Taking money out of the business", explaining in one plain line that this is recorded as the owner's drawing and not a business expense, with amount, from-account and a Confirm button.

---

## C · TRUST — Singh Sabha Gurudwara

*One organization book. Roles renamed. Donations replace sales; there is no profit — only surplus.*

### C1 · Home (trust scope)
Scope chip "Singh Sabha Gurudwara". Hero **₹4,23,800**, breakdown "Trust SBI ₹3,21,400 · Gollak Cash ₹1,02,400". Books-balanced: "Dr ₹7,78,000 = Cr ₹7,78,000". Position card rows: **Advance out ₹11,900** (meta "Amritpal Singh · 18 days") · **This year's donations ₹5,74,000** · **This year's spending ₹3,42,300**. **No "You will get" row** unless a party exists — a trust often has none. Today's entries: "Gollak collection +₹69,000", "Granthi honorarium −₹22,000", "Langar ration −₹22,400".

### C2 · Ledger index
Trust SBI A/c · Gollak Cash A/c · Advance – Amritpal Singh A/c · Langar Expense · Building Repair Expense · Electricity Expense · Granthi Honorarium · Sound & Media Expense · Gollak Donation Income · Sponsor Donation Income.

### C3 · Gollak counting sheet *(S5.5 in collect mode)*
Reuse **S5.5 collect mode** with the trust's language — title "Gollak · Open and count" (ਗੋਲਕ ਖੋਲ੍ਹ ਕੇ ਗਿਣੋ), Gollak Cash A/c preselected, an income-account row reading "Record as: Gollak Donation Income", no book-balance or difference line, and both name fields required. After saving, a confirmation stating plainly that the money has been recorded and remains in the gollak until it is deposited.

### C4 · Sevadar advance card
Apply P2/P3 to the **ਐਡਵਾਂਸ** flow: "Amritpal Singh is holding ₹11,900 · given 12 Jul · 18 days" with a progress bar showing spent versus remaining, and two buttons — "Record spending" and "Return cash".

### C5 · Donation receipt *(trust-only screen)*
A single-entry receipt preview on gurudwara letterhead: trust name, donor name, amount in figures and words in the chosen language, date, receipt number, and a Share button. **No tax language, no 80G claim** — this is an acknowledgement, not a tax document.

---

## D · JOINT FAMILY — Sharma Family

*The full architecture: joint pool + three sub-families + two businesses + personal books. Everything above, plus the multi-book layer. Design this last.*

### D1 · Scope switcher sheet *(the screen that makes the product possible)*
A bottom sheet opened from the scope chip, sections with headers: **Me** (Rahul's personal book, with a small lock icon meaning private) · **Family** (Sharma Joint Family · Rahul sub-family · Pankaj sub-family · Geeta sub-family) · **Businesses** (Agriculture Business · Sharma Super Store · Sharma Textile) · **Everything** (with a small "read-only" tag). Each row shows the book name and its current balance. The current scope is ticked.

### D2 · Home — Everything scope
Hero **total across all visible books**, then instead of a single position card, a **stack of compact book cards** — each with the book name, its balance, and a chevron; tapping one switches scope to that book. Below: a family-wide **open advances** card ("Sunil Sharma ₹5,800 · 17 days" from Agriculture Business) and an **inter-book status** card reading "All books reconciled ✓" with a chevron.

### D3 · Home — Joint pool scope
Hero **₹63,000** (PNB Joint) plus Joint Cash ₹18,800. Position card rows: **Agriculture Business — you will give ₹4,00,000** · **Sharma Super Store — you will give ₹1,80,000** · **Rahul sub-family — you will get ₹2,00,000** · **Pankaj sub-family — you will get ₹2,00,000** · **Geeta sub-family — you will get ₹2,25,000**. Note these rows are *other books*, named plainly — never "Due to/from".

### D4 · Inter-book transfer sheet *(joint-only screen)*
"Move money between books": a From block (book selector + account) and a To block (book selector + account), amount, note, and a plain-language confirmation line: "Agriculture Business will show ₹50,000 going out. Sharma Joint Family will show ₹50,000 coming in." Include the **in-transit state**: the entry row on both books tagged "In transit" in muted colour until the second half is approved.

### D5 · Family reconciliation screen *(joint-only)*
A list of book pairs, each showing both sides and a green tick: "Joint pool ↔ Agriculture Business · ₹4,00,000 each way · ✓". Header reads "All books agree" with a large tick when every pair nets to zero; any non-zero pair shows amber with a "See the entries" link.

### D6 · Allowance flow
The monthly household allowance from pool to sub-family, as a **repeating entry**: a card on the joint pool's Home reading "Monthly allowances · ₹1,15,000 · due 15 Sep" with a "Send now" button, expanding to per-sub-family rows with amounts editable before sending.

### D7 · Advance (ਐਡਵਾਂਸ) full cycle *(joint + trust + business)*
Four states of the same card, designed as a set: **requested** (awaiting approval, amber) · **open** (₹5,800 with Sunil Sharma, 17 days, progress bar) · **overdue** (past the reminder threshold, red, with "Remind" button) · **settled** (green tick, collapsed).

### D7.1 · S14 — Partner positions *(shared-ownership businesses)*
Design the screen that answers "what does the business owe each owner?" Header: business name, "Owned equally by 3 sub-families", then a **season profit card** — muted label, ₹5,94,000 large and tabular, "₹1,98,000 each · shared 1/3" beneath. Then one card per partner: name on the left and the amount the business owes them on the right in credit colour (₹3,28,000), and beneath a hairline a three-column strip — **Put in ₹1,80,000 · Took out ₹50,000 · Profit share ₹1,98,000**. Then a **settlement-capacity line** in words: "The business can settle all partner balances today" with the figures beneath in muted type; design the shortfall variant too ("Short by ₹1,20,000 to settle all balances"). Also design the **debit-balance card**: a partner who has taken more than they put in plus their share, shown in debit colour with the words "Owes the business".

## D7.2 · S14.1 — Profit distribution wizard
Three steps. **1 Period** — date range with the computed net profit large and tabular, and the income-minus-expense arithmetic shown in one muted line. **2 Preview** — a row per partner showing their ratio, an optional *interest on capital* line where the setting is on, and their total; a footnote naming where the odd paise went. **3 Confirm** — plain statement that this posts one entry and moves no cash, then a wide primary button.

## D7.3 · S14.2 — Drift & settlement card
An informational card, never a demand: "Amrit has ₹68,332 more with the business than her third", with three options presented as equal choices — **Business pays out · Settle between partners · Carry forward (default, preselected)**. Design the carry-forward confirmation showing the certified date the balance will re-open under next year.

## D8 · Member list & roles
A list of family members with photo, name, their role per book as small chips ("Head · Pankaj sub-family", "Operator · Sharma Super Store"), and the verification method and date in muted text ("Verified in person, 12 Apr"). Plus the invite button and the pending-verification state ("Joined — meet to activate").

---

## Cross-entity checklist
Each entity pack must be delivered in **light and dark**, in **all three languages**, with empty states. The Individual pack is the baseline; Business adds two party-statement variants and the drawings sheet; Trust adds the gollak counter, sevadar advance and receipt; Joint Family adds the scope switcher, Everything view, inter-book transfer, reconciliation, allowances and member roles.

---

# STEP 5 — States & deliverables

## Empty & error states
For S1 (new user: a setup checklist of 4 items), S3, S4, S6, S7.1 — each with a friendly line, a simple line illustration, and exactly one action button. Plus an offline chip ("Saved on phone · will sync") and a locked-date explanation sheet offering "Fix an old entry".

---

## Deliverables checklist
Components for P1/P2/P3 and all atoms with every state · every screen above in **light and dark** · every screen in **all three languages** · empty/error/offline variants for each list · tappable prototypes of two flows: add a cash entry, and review a flagged entry · redlines referencing token names, never raw hex.
