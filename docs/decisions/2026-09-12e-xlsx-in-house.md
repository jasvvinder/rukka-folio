# ADR 2026-09-12e — XLSX is written in-house; the export trio is the same on every report surface

**Closes:** ADR 2026-09-12's *XLSX package choice* Open ⚠️, outstanding since the export formats were
ruled. **Amends:** the owner-locked S4 export line in `07 §6` (*export this A/C (PDF/XLSX)*).

The XLSX row has shipped disabled-with-reason since S8.2 was built, because no package had been
evaluated against this workspace's constraints. Evaluated 12 Sep 2026, after the `archive` pin
(ADR 2026-09-12d §1) changed what is admissible:

| Candidate | `archive` | `xml` | Outcome |
|---|---|---|---|
| `excel` 4.0.6 | `^3.6.1` (3.x) | `<7.0.0` | **Hard-blocked.** Compile-verified against 4.0.9: `ZipDecoder.decodeBuffer` and `ArchiveFile.compress` are archive-3 APIs deleted in 4.x |
| `spreadsheet_decoder` 2.3.0 | `^3.6.1` (3.x) | `^6.5.0` | Same block, and it parses rather than writes |
| `syncfusion_flutter_xlsio` 34.2.7 | `>=4.0.0 <5.0.0` ✓ | `>=7.0.1 <8.0.0` ✓ | Technically compatible; **proprietary licence** plus `syncfusion_officecore`, `image`, `jiffy`, `intl`, `crypto` |

sodium needs `archive` 4.x, the two free writers need 3.x, and an override cannot bridge a deleted
method — the resolver *silences* that conflict, which is precisely the failure mode 12d §1 warns
about. Owner ruled 12 Sep 2026: **write it ourselves.**

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. XLSX is generated in-house over `archive` + `xml`; no XLSX package is adopted ⟦tests: F1-07-79⟧
- An `.xlsx` is a zip of XML parts. The writer emits `[Content_Types].xml`, the two `.rels` parts,
  `xl/workbook.xml`, `xl/worksheets/sheet1.xml` and a minimal `xl/styles.xml`, using **inline
  strings** so there is no shared-string table to keep consistent. `archive` zips it; `xml` writes
  it. Both are already in the tree and are now **direct** dependencies of `app`. ⟦tests: F1-07-79⟧
- **This is not the PDF exception being reopened.** Refusing to hand-roll PDF was right: that meant
  fonts, glyph metrics and page breaking — a typesetting engine. A flat ledger table in XLSX is
  *serialization*: we write a file manifest, and the zip and XML are libraries. ⟦tests: n/a — rationale, not behaviour⟧
- **No licence is taken on for one export format.** Syncfusion's tier is conditioned on revenue and
  team size, on a product that charges from M13 (`08`); that is a commitment the owner declined for
  a single row of an export sheet. ⟦tests: n/a — rationale, not behaviour⟧
- The output is frozen by the F3 byte-goldens when they land (`F3-07-1/2 @M12`), which is what makes
  an in-house format safe to maintain. ⟦tests: F3-07-1 @M12, F3-07-2 @M12⟧

### 2. Every report surface offers the same trio ⟦tests: F1-07-79⟧
- **View · Download/Share · Export** is the shape on **both** the statement (S4) and the report
  viewer (S8.2), and Export offers the ruled three — **PDF, CSV, XLSX** (ADR 2026-09-12 §1). ⟦tests: F1-07-79⟧
- `07 §6` 🔒 is amended from *export this A/C (PDF/XLSX)* to **PDF/CSV/XLSX**. ⟦tests: F1-07-79⟧
  The two surfaces stop disagreeing about what an export is.
- Provenance: this is the owner's own framing of 12 Sep 2026 — *"three kind of options for every
  account/overview/ledger report … view, download/share pdf, either statement or report, and export
  as pdf/csv/excel"* — recorded here rather than left as an inference. See Open ⚠️ if it misreads it. ⟦tests: n/a — provenance, not behaviour⟧
- **Only the day book exists today.** The other ten reports of `07 §14` are M12 (ADR 2026-09-12), so
  the trio applies to the day book now and to each report as it lands. ⟦tests: n/a — scope note⟧

### 3. The CSV export carries a UTF-8 byte-order mark ⟦tests: F1-07-79⟧
- Owner ruled 12 Sep 2026. The CSV writer prefixes its bytes with `EF BB BF`. Without it Excel reads
  a UTF-8 CSV as the system code page, and Gurmukhi and Devanagari account names arrive as garbage
  for exactly the readers `01 §1.8` is written for — the same class of silent failure as a PDF with
  no embedded font. ⟦tests: F1-07-79⟧
- **The writer already did this** (`csv_report.dart:154`, since the CSV export was built): the claim
  that prompted the ruling — *"the CSV writer does not emit a BOM today"* — was asserted without
  reading the file and was wrong (rule 11). What was genuinely missing was any **test**: the BOM
  could have been dropped by a later edit and nothing would have failed. The ruling therefore fixes
  the behaviour in place and `F1-07-79` now asserts the three bytes. ⟦tests: F1-07-79⟧
- The cost is accepted knowingly: a BOM is stray noise to some non-Excel readers. Excel is the
  dominant consumer of a ledger CSV in this market, and a reader that shows three odd characters is
  a visible annoyance, where mojibake across every Punjabi account name is unusable data. ⟦tests: n/a — rationale, not behaviour⟧
- The BOM is part of the format and is frozen by the CSV byte-golden when it lands (`F3-07-2 @M12`). ⟦tests: F3-07-2 @M12⟧

## Consequences
- **Code:** the CSV BOM (§3) gains its first assertion in `F1-07-79`; an XLSX writer beside `pdf_report.dart` and `csv_report.dart`, behind the same
  `runReportExport` seam; the XLSX row stops being disabled-with-reason and generates; `F1-07-79`
  extends to cover it. S4's export surface is a **later lane** — it needs a statement report, not a
  day book, and `features/ledger` is another directory.
- **Dependencies:** `app/pubspec.yaml` declares `archive: ^4.0.9` and `xml: ^7.0.1` directly (both
  already resolved transitively; versions unchanged). No package is added.
- **Docs:** `07 §6` amended; `07 §14` and `13 §3.2`'s S8.2 row note that XLSX generates.
- **Milestone:** M5 for the day book in all three formats. Content rules, the watermark and the
  byte-goldens stay M12.

## Open ⚠️
- **If §2 misreads the owner's framing, §2 is the line to correct** — the Excel ruling in §1 stands
  either way, and S4's surface has not been built yet, so the correction is cheap today and
  expensive after that lane runs.
- **The root `dependency_overrides` hid excel's incompatibility at resolution time**, surfacing it
  only at compile. Worth remembering whenever a package is evaluated while that pin is in place:
  resolve **and** compile before believing a candidate fits.
