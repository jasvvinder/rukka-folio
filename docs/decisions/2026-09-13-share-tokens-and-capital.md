# ADR 2026-09-13 — Share is wired, the palette is signed off, and capital introduced is Money in

Four owner items had been carried across sessions on `PLAN.md` §0, three of them decisions rather than
work. The owner took all four on **13 Sep 2026**. They are unrelated in subject and related in kind:
each was a place where the build had run ahead of a ruling and stopped, leaving either a visible defect
(§1), a value awaiting a signature (§2), an undocumented key (§3) or two halves of the engine
disagreeing with each other (§4).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. *Download/Share* raises the platform share sheet; a file is the fallback, not the product ⟦tests: F1-07-79⟧
- The shipped `ReportSink` is `shareReportFile`, which hands the bytes to `Printing.sharePdf`. Until
  today it was `saveReportToTempFile`, and **the export ended at a sandbox temp path no reader could
  reach** — the one item on the owner list where something was visibly broken. ⟦tests: F1-07-79⟧
- `Printing.sharePdf` shares **all three formats** despite its name: the iOS plugin writes the bytes to
  `NSTemporaryDirectory()/<name>` and presents a `UIActivityViewController` over that file URL, so the
  extension we pass — `.pdf`, `.csv`, `.xlsx` — is what the system reads the type from
  (verified in `printing-5.14.3/ios/Classes/PrintJob.swift:255`). No second package is taken on. ⟦tests: n/a — rationale, not behaviour⟧
- **A successful share gets no sentence from us.** The sheet is its own confirmation, it covers the
  screen a snackbar would appear on, and the platform reports neither completion nor cancellation — so
  any line we wrote would be a guess about what the reader did next (`07 §1` rule 12). ⟦tests: F1-07-79⟧
- **If the sheet cannot be raised, the file is written and named**, exactly as before, so an export is
  never a dead end (`07 §1` rules 2 and 6). This is why `ReportSink` now returns a sealed
  `ReportDelivery` — `ReportShared` | `ReportSaved(where)` — rather than a string: the two outcomes need
  different words on the screen and only the sink knows which happened. ⟦tests: F1-07-79⟧
- Nothing about the file is logged — not the path, not the exception, not the bytes (CLAUDE.md rule 4);
  any file written purges under the rule `F2-05a-11` already carries (ADR 2026-09-12 §4). ⟦tests: n/a — restates an existing rule⟧

### 2. The palette is signed off, and the last three sub-AA pairs are closed by moving two tokens ⟦tests: F1-10-12, F1-10-13, F1-10-14, F1-10-15⟧
- **The status family is ratified** at the values the 12 Sep token session proposed — light `success`
  #276A49 · `warning` #7C5200 · `info` #1F6785 · `danger` #9C2C2C · `on-danger` #F5F0E4 ·
  `focus-on-primary` #F5F0E4; dark #5CB489 · #E0AE55 · #86C6DC · #E08C8C · #1A1A18 · #1A1A18. The
  5 Sep pattern — proposed in code, ratified by the owner — is closed for this family. ⟦tests: F1-10-12⟧
- **Light `credit` #2F7A55 → #2B724F.** `design-system §3.1` 🔒 had already ruled *darkened one step*
  and left the hex open. On `sunk` it goes 4.30 → **4.79**. The hex is **half** the documented
  credit→success step, because the *full* step lands exactly on `success` #276A49 and would erase the
  distinction. The resulting closeness is safe: `credit` is numerals-only and `success` is a status word
  plus an icon, so the two are never read against each other. `success` does not move. ⟦tests: F1-10-12⟧
- **Light `text-muted` #6E6A5E → #696558.** On `sunk` 4.46 → **4.81**, on `danger-surface` 4.36 →
  **4.70**. This closes the two pairs `check_contrast` found unruled on 7 Sep. The finding offered an
  alternative — *keep captions off `sunk` and `danger-surface`* — and it is refused: a placement rule for
  captions is unenforceable in code, where a token value is checked on every run. ⟦tests: F1-10-12⟧
- **The three `pendingRuling` waivers are deleted, not relaxed.** `scripts/check_contrast.dart` now
  reports **110 gated pairs pass, 0 waived pending ruling** — the audit is clean for the first time, and
  every waiver left is a placement rule (*amounts are never placed on `danger-surface`*). ⟦tests: F1-10-15⟧
- **No `PROPOSED` marker remains in `tokens.json`.** The eight that were left on light and dark `sunk`,
  `pending`, `locked` and `scrim` were stale — `design-system §2` has recorded those four as *approved*
  since 5 Sep (ADR 2026-09-05f §H11) — and a marker that contradicts the doc is a lie in the source of
  truth. `tokens.json` goes to **v0.1.2**. ⟦tests: n/a — comment text, not behaviour⟧

### 3. `partner_shares` keys to the Partner Current A/c id ⟦tests: E-03-30, F1-07-86⟧
- Confirmed as built (lane M5-U4d, ADR 2026-09-09 §2's ⚠️ SPEC): the weights live in the book's
  `book_config` envelope as `partner_shares`, a map of **Partner Current A/c id → whole-number weight**.
  `02 §7.1` now states it. ⟦tests: E-03-30, F1-07-86⟧
- The account id is the key because no member identity exists when a shared business is created — the
  owners are at that point only *invited* — and it is the one handle that survives renaming either the
  owner or the account seeded after them. It is also what `02 §7.1`'s remainder rule already ties to
  (*"ties broken by the earliest-created partner account"*). ⟦tests: n/a — rationale, not behaviour⟧
- **An absent or empty map means the ratio was never recorded — never that the shares are equal.** Equal
  shares are held as real weights (1:1:1, ADR 2026-09-09 §2), so a reader that finds no map must say so
  rather than divide evenly. ⟦tests: E-03-30⟧

### 4. Capital introduced is an ordinary **Money in** ⟦tests: A-09b-5⟧
- `Dr {money a/c} · Cr Opening Balance/Capital`, kind `money_in` — never income, and never an
  adjustment. The behavioural reference settles the posting and the framing together:
  `financial-accounting-standards.md` §4.1 lists **B01 "Owner adds capital" — Dr HDFC · Cr Capital,
  ₹5,000** among the ten ordinary daybook transaction types, beside **B11 "Owner drawing" — Dr Drawings ·
  Cr Business Cash**, which ADR 2026-09-09b §3 🔒 already ruled `money_out`. The two are one event seen
  from either end and they take the same kind. ⟦tests: A-09b-5⟧
- Capital **is** the Opening Balance account (ADR 2026-09-09b §1 🔒). ⟦tests: A-09b-5⟧
  No `capital` role exists, as both business worked examples name it `Opening Balance / Capital A/c`, so
  this needs no new system role and no enum change. `equitySystem` already sits outside the P&L, which
  `A-09b-5` asserts rather than assumes.
- **This fixes a live defect, not just a gap.** `Verbs.moneyIn` accepted **any** `equitySystem` account in
  its `from` slot while `checkShape`'s `money_in` arm admitted **none** — so the verb could build an entry
  the reader then quarantined. That is the exact twin of the drawings defect ADR 2026-09-09b §3 fixed on
  the other side, and it is fixed the same way: the verb takes the `_role` guard, `checkShape` admits the
  one role by name. ⟦tests: A-09b-5⟧
- **The two money verbs stay mirror images:** `money_in` admits `openingBalance` and refuses `drawings`;
  `money_out` admits `drawings` and refuses `openingBalance`; every other system account posts through its
  own builder. ⟦tests: A-09b-5⟧

## Consequences
- **`app/`:** `features/reports/export/file_report_sink.dart` becomes `shareReportFile` over
  `Printing.sharePdf` with the file write as fallback; `report_export.dart` gains `ReportDelivery`;
  `runReportExport` branches on it; `S8.2`'s default sink changes. `F1-07-79` gains one test — the
  shipped delivery raises the sheet and says nothing — and `_CapturingSink` reports `ReportSaved` by
  default so every assertion written before today reads the same.
- **`packages/core_ledger`:** the `_role` guard on `Verbs.moneyIn`, `isCapital` in `checkShape`, and
  `test/capital_test.dart` (`A-09b-5`, five tests). No enum change, no projection change; the golden
  replay of the eight worked-example books is unmoved.
- **`design/`:** `tokens.json` v0.1.2 (two values, nine comment corrections) → regenerated `tokens.css`,
  `tokens.dart`, `app/lib/shared/tokens.dart`; `design-system.md` §2, §3, §3.1; `DESIGN-PACK.md`
  palette line. `scripts/src/contrast.dart` loses the three `pendingRuling` waivers.
- **Docs:** `02 §7.1` gains the `partner_shares` keying line (§3) and the capital cross-reference (§4);
  `11 §4` carries the new `credit` hex; ADR 2026-09-09 §2, ADR 2026-09-09b's Open and ADR 2026-09-12e's
  Open are closed where this ADR closes them.
- **No 🔒 line is contradicted.** §1 completes a ruling (ADR 2026-09-12 §1), §2 supplies hexes a ruling
  left open, §3 documents built behaviour, §4 implements a posting the reference already prescribed — so
  **no test needs `@Skip`** (ADR 2026-09-05i §4).
- **Milestone:** M5.

## Open ⚠️
- **`Printing.sharePdf` returns `true` whether or not the sheet appeared.** The iOS plugin calls
  `result(NSNumber(value: 1))` unconditionally and only `print`s a write failure
  (`PrintingPlugin.swift:96`), so our fallback cannot trigger on that one path — the reader would see
  nothing. Writing to `NSTemporaryDirectory()` is not a realistic failure, and the alternative (our own
  write first) does not help, because `sharePdf` writes its own copy regardless and a second copy of
  plaintext financial data is worse. Recorded rather than designed around.
- **iPad popover anchor.** `sharePdf` takes a `bounds` rect for the iPad popover and the sink is
  deliberately context-free, so it takes the plugin's default (a 10pt circle at the origin). On iPhone —
  the pilot device — this is unused. Worth passing real bounds if iPad is ever a target.
- **The 8th quick-add tile is still a UX question** (ADR 2026-09-09b's Open). §4 clears the engine half;
  what the tile *does* — create an account, which it cannot, or open the entry flow with Capital
  preselected, which is the standing recommendation and would amend `07 §6` bullet 3 — is unruled.
  The ⚠️ SPEC comment stands in `s3_1_quick_add_sheet.dart`.
- **S4's export surface is unbuilt** and now binding: ADR 2026-09-12e §2, confirmed today, puts the same
  View · Download/Share · Export trio on the statement.
