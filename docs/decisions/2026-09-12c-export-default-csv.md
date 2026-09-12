# ADR 2026-09-12c — Download/Share defaults to CSV while `pdf` cannot resolve

**Supersedes:** the *Download/Share defaults to PDF* clause of ADR 2026-09-12 §1, and closes that
ADR's first Open ⚠️. Everything else in ADR 2026-09-12 stands — the enumeration, the on-device rule,
the watermark and the goldens.

ADR 2026-09-12 §1 🔒 made **PDF** the default of S8.2's primary action. Lane M5-U3e then found PDF
unbuildable in this workspace, and the owner's attempted fix was carried out and measured on
12 Sep 2026: every published `pdf` (≤ 3.13.0) constrains `archive >=3.4.0 <4.1.0`, while
package:sodium 4.1.x requires `archive ^4.2.0` — and sodium is pinned in **three** packages
(`core_crypto`, `data`, `sync_engine`), not one. Loosening all three to `sodium: >=4.0.4 <5.0.0`
**does** resolve (sodium 4.1.0+1 → 4.0.4, `pdf` and `printing` both admitted) and then
`core_crypto` **fails to compile**: `Sodium.memcmp` (`sodium_memcmp`) entered package:sodium's
public Dart API only in 4.1.0, and `CryptoSuite.constantTimeEquals` (`suite.dart:56`) is built on
it; in 4.0.4 the symbol exists only inside that package's private `lib/src/ffi/bindings/`. The
change was reverted and suite B re-run green (75 tests). Replacing the call with a hand-rolled
constant-time compare is a rule 7 / `04 §2` decision; the owner declined it and ruled on
12 Sep 2026 that the **default moves to CSV** until the conflict lifts.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Download/Share defaults to CSV while PDF is unavailable ⟦tests: F1-07-79⟧
⛔ **Superseded the same day by ADR 2026-09-12d §2** — PDF became available by pinning `archive`
instead of downgrading sodium, so the default is PDF again. The second bullet below (the sheet
stays reachable) survives; the CSV default does not.
- **Download/Share** remains the primary action of S8.2 and writes **CSV** — the one format this
  workspace can generate today. It no longer merely opens the sheet, which was U3e's conservative
  hold on a default it could not honour. ⟦tests: F1-07-79⟧
- The format sheet stays reachable from the viewer so a person can still choose a format rather
  than accept the default. ⟦tests: F1-07-79⟧
- CSV is a weaker default than PDF for handing to another person, and that is understood: this
  ruling buys a working primary action, it does not claim CSV is the better artefact. ⟦tests: n/a — rationale, not behaviour⟧

### 2. The enumeration and the row order do not move ⟦tests: F1-07-79⟧
- The sheet still offers exactly **PDF, CSV and XLSX**, in that order, PDF first (ADR 2026-09-12 §1,
  unchanged). Only the *default* moves. ⟦tests: F1-07-79⟧
- PDF keeps its ruled first position and ships **disabled-with-reason**, naming CSV as the working
  alternative; XLSX likewise, on its own unrelated blocker (no package chosen). ⟦tests: F1-07-79⟧

### 3. The default reverts to PDF on a dependency condition, with no further ADR ⟦tests: n/a — a dependency condition, not behaviour⟧
- The trigger is either: a published `pdf` that admits `archive ^4.2.0`, **or** a package:sodium line
  that exposes `sodium_memcmp` publicly *and* meets `pdf`'s archive range. On that day ADR
  2026-09-12 §1's PDF default applies again and this ADR lapses.
- `CryptoSuite.constantTimeEquals` stays libsodium-backed either way. No hand-rolled constant-time
  compare enters `core_crypto` without its own ADR (rule 7, `04 §2`). ⟦tests: n/a — reaffirms rule 7, no new behaviour⟧
- Revisit at **M12** at the latest, where the F3 PDF goldens fall due.

## Consequences
- **Code:** `app/lib/features/reports/widgets/export_sheet.dart` — the held-default `⚠️ SPEC:` goes
  and the primary action writes CSV. `app/test/features/reports/s8_2_report_viewer_screen_test.dart`
  extends `F1-07-79` with the CSV-default case. **No `@Skip` is owed** (ADR 2026-09-05i §4): no green
  test asserts a PDF default — `F1-07-79`'s cases assert the three-row order and that tapping CSV
  reaches the sink, both of which this ADR leaves true.
- **Dependencies:** `packages/{core_crypto,data,sync_engine}/pubspec.yaml` stay at `sodium: ^4.1.0`;
  `pdf` and `printing` stay out of `app/pubspec.yaml`, which carries the attempt and its outcome as a
  comment so it is not rediscovered.
- **Docs:** `07 §14` (the ADR 2026-09-12 cross-reference line) and `13 §3.2`'s S8.2 row both name the
  default and are amended here; ADR 2026-09-12 gains a supersession note on the clause and its first
  Open ⚠️ is closed.
- **Milestone:** M5. `F1-07-79` is already green and is extended, not re-minted.

## Open ⚠️
- **`07 §6`'s per-A/C statement export (S4) now promises two formats it cannot produce** — the line
  reads *export this A/C (PDF/XLSX)* and both are blocked. ADR 2026-09-12 already asked whether CSV
  should join there; this ADR makes the question sharper, because S4's export is currently
  unbuildable in *every* format it names. A yes/no from the owner, after which that ADR gains a §5
  or a one-line successor.
- **If `pdf` never moves, M12 loses more than a default:** the PDF-only watermark (ADR 2026-09-12 §2,
  `F3-07-3 @M12`) and the PDF byte-goldens (`F3-07-1/2 @M12`) cannot be built at all. Worth a
  decision before M12 rather than at its exit.
- **The hand-rolled route stays available** if the owner reconsiders: ten lines of XOR-accumulate in
  `CryptoSuite`, under its own ADR. Honest caveat for that day — Dart cannot guarantee constant time
  in a JIT/AOT loop, so it would trade a libsodium guarantee for a best-effort one, the same caveat
  `zeroize` already carries two lines below it in the same file.
