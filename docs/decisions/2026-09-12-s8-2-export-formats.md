# ADR 2026-09-12 — CSV joins PDF and XLSX on the report export surface

`07 §14` 🔒 enumerated the report export formats as **PDF & XLSX**, and `13 §3.2`'s S8.2 row agreed
(*"PDF/XLSX, FY switcher"*). CSV appeared nowhere on that surface: it existed in the specs only as the
**data export** — `08 §1` (ADR 2026-09-05g §5) puts the watermark on *"reports (PDF) only, never to the
CSV/XLSX data export"*, and `08 §8` tests exactly that split. The two surfaces had two different format
sets, which is why `S8.2` could not be scoped without an owner ruling on dependencies.

Owner ruled 12 Sep 2026, answering the `⛔` dependency question left open by lane U3c: S8.2's required
options are **View report**, **Download/Share in PDF**, and an export sheet offering **PDF, CSV and
XLSX**. That adds a third format to a 🔒 enumeration, so it is recorded here rather than in the specs
alone.

Nothing about the watermark changes. ADR 2026-09-05g §5's rule was always written against the *format*
— PDF carries it, CSV and XLSX never do — so bringing CSV onto the report surface extends that rule
unchanged rather than reopening it. `06 §9.2`'s *"full export forever"* claim is likewise untouched.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. S8.2's export sheet offers exactly three formats ⟦tests: F1-07-79 @M5⟧
- The export sheet offers **PDF, CSV and XLSX** — no more, no fewer. `07 §14`'s enumeration is amended
  from *PDF & XLSX* to *PDF, CSV & XLSX*. ⟦tests: F1-07-79 @M5⟧
- **View report** opens the report in-app; **Download/Share** is the primary action and defaults to
  **PDF**, the format a person hands to someone else. ⟦tests: F1-07-79 @M5⟧
- Every format is generated **on device**, no report content leaving it to be rendered (`07 §14` 🔒, unchanged). ⟦tests: F1-07-79 @M5⟧
- The sheet is reachable from the report viewer only. This ADR does **not** add CSV to `07 §6`'s
  per-A/C statement export (S4, *"export this A/C (PDF/XLSX)"*) — see Open ⚠️. ⟦tests: F1-07-79 @M5⟧

### 2. The watermark follows the format, never the surface ⟦tests: F3-07-3 @M12⟧
- A Free tenant's **PDF** report carries the watermark; its **CSV** and **XLSX** exports never do, on the report surface exactly as on the data-export surface (ADR 2026-09-05g §5, `08 §1` 🔒). ⟦tests: F3-07-3 @M12⟧
- This is the whole of the change to `08`: a cross-reference, not a new rule. ⟦tests: F3-07-3 @M12⟧

### 3. Format fidelity is proven by byte-goldens on the RC lane ⟦tests: F3-07-1 @M12, F3-07-2 @M12⟧
- CSV and XLSX exports are byte-compared against goldens in `testing/goldens/` — **suite F3, RC lane**
  (09 §preamble; `scripts/ci.sh` `LANE=rc`), never the push lane. ⟦tests: F3-07-1 @M12, F3-07-2 @M12⟧
- `07 §14`'s content rules bind all three formats where the format can carry them: b/d–c/d rows on
  ledgers, amount-in-words, Indian digit grouping. **A4 print-clean binds PDF only** — it is a page
  rule, and CSV and XLSX have no pages. ⟦tests: F3-07-1 @M12, F3-07-2 @M12⟧

### 4. Temp files from every format purge on the existing rule ⟦tests: F2-05a-11 @M12⟧
- A generated report is plaintext financial data (CLAUDE.md rule 4). All three formats purge under the
  temp-file rule already carried by `F2-05a-11` (device lab, RC); no new rule is minted here.
  ⟦tests: F2-05a-11 @M12⟧

## Consequences
- **Code:** `app/pubspec.yaml` gains the PDF and XLSX dependencies (CSV needs none — it is written
  directly). `app/lib/features/reports/` gains S8.2 and the export sheet; `s8_1_reports_list_screen.dart`'s
  rows stop being disabled-with-reason as each report lands. No green test is flipped by this ADR, so
  nothing is `@Skip`ped.
- **Docs:** `07 §14` 🔒 line amended (marker kept) + cross-reference; `13 §3.2` S8.2 row and `13 §5`'s
  `S3 → … → S8.2` flow line amended; `08 §1` gains a cross-reference line.
- **Milestone (10):** M5 is *"basic day-book export"* and M12 is *"report suite (07 §14) … exports with
  b/d–c/d + amount-in-words"* with *"F3 export goldens"*. So **the S8.2 screen and its three-format sheet
  land at M5 against the day book**; the remaining ten reports and every F3 golden are **M12**. `F1-07-79`
  is marked `@M5`, the F3 ids `@M12`.

## Open ⚠️
- **XLSX package choice — owner call, still outstanding.** PDF is settled by need (`pdf` for generation
  plus `printing` for the on-device share/print sheet, which is also what satisfies `07 §14`'s *A4
  print-clean*). XLSX has no equivalent default in this repo and none of the candidates has been
  evaluated against the workspace's pure-Dart constraint. A lane must not pick one silently.
- **`07 §6`'s per-A/C statement export (S4) still reads *PDF/XLSX*.** Consistency argues it should match
  S8.2's three formats, but the owner ruled on S8.2 and a 🔒 line is not extended by inference
  (CLAUDE.md rule 11). Wanted: a yes/no, after which this ADR gains a §5 or a one-line successor.
- **Report content rules are M12 work, not M5.** `07 §14`'s b/d–c/d rows and amount-in-words are listed
  against M12 in `10`; a lane scoping S8.2 at M5 should build the *surface* and the day book, and must
  not silently ship the other ten reports untested.
