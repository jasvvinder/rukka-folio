# ADR 2026-09-12d — PDF ships after all: pin `archive`, never downgrade sodium

**Supersedes:** ADR 2026-09-12c §1 (the CSV default) and closes its §3 by a route neither trigger
named. ADR 2026-09-12 §1's **PDF default is restored**. 12c §2 (enumeration and row order) stands
unchanged, and so does everything in ADR 2026-09-12.

12c was ruled on the finding that `pdf` cannot resolve in this workspace. The owner pushed back on
that conclusion the same day, and the re-examination found the earlier reading wrong in one
load-bearing way: *"sodium needs archive ^4.2.0"* is not a fact about crypto. package:sodium imports
`archive` in exactly one file — `lib/src/hooks/common/extractor.dart`, the **build-time** hook that
untars the libsodium binaries. Nothing in the crypto runtime touches it, and sodium's 4.1.0
changelog does not mention the bump at all. So the package to move is `archive`, not `sodium` —
which keeps sodium at 4.1.x, where `Sodium.memcmp` lives, and leaves `CryptoSuite.constantTimeEquals`
libsodium-backed. Owner ruled 12 Sep 2026: adopt it and build the writer.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The workspace pins `archive` into `pdf`'s window; sodium is never downgraded for a report format ⟦tests: n/a — build configuration, proven by suite B compiling against the pin⟧
- `dependency_overrides: archive: '>=4.0.9 <4.1.0'` at the workspace root. Verified before adoption:
  every symbol sodium's extractor uses — `InputFileStream`, `OutputMemoryStream`,
  `GZipDecoder.decodeStream(input, output, verify:)`, `TarDecoder.decodeBytes(bytes, verify:)` —
  exists in 4.0.9 with matching signatures; suite B ran **75/75 with `.dart_tool/hooks_runner` and
  `native_assets` deleted**, so the hook was recompiled and executed against 4.0.9 rather than
  served from cache. ⟦tests: n/a — build configuration⟧
- **Downgrading `sodium` is ruled out** as the way to admit a report format: 4.0.x has no public
  `sodium_memcmp`, so it would cost `constantTimeEquals` its libsodium backing (rule 7, `04 §2`).
  That route was tried on 12 Sep and reverted. ⟦tests: n/a — reaffirms rule 7; suite B covers the behaviour⟧
- The pin's failure mode is **build-time and loud**: sodium's use is extraction during the native
  build, so an incompatibility breaks a build, never a ledger. If a future package genuinely needs
  `archive >= 4.1`, the pin is re-examined then — it is never widened silently to make a build pass. ⟦tests: n/a — build configuration⟧

### 2. Download/Share defaults to PDF again ⟦tests: F1-07-79⟧
- ADR 2026-09-12 §1's ruling applies as written: **Download/Share** is the primary action and
  defaults to **PDF**, *the format a person hands to someone else*. ADR 2026-09-12c §1's CSV default
  was a workaround for an unavailable format and lapses here. ⟦tests: F1-07-79⟧
- The format sheet stays reachable from the viewer, as 12c §1 established — that part was never
  about PDF and survives. ⟦tests: F1-07-79⟧

### 3. PDF is a working row, not a disabled one ⟦tests: F1-07-79⟧
- The enumeration and row order are untouched (**PDF, CSV, XLSX**, PDF first — ADR 2026-09-12 §1,
  12c §2). PDF stops being disabled-with-reason and generates. ⟦tests: F1-07-79⟧
- **XLSX is unchanged**: still disabled-with-reason on its own unrelated blocker — no package has
  been evaluated against the workspace's pure-Dart constraint, and that owner call is still open. ⟦tests: F1-07-79⟧
- Every format is still generated **on device** (`07 §14` 🔒, unchanged). ⟦tests: F1-07-79⟧

## Consequences
- **Code:** a PDF day-book writer beside `features/reports/export/csv_report.dart`; the export sheet's
  PDF row enabled; the viewer's primary action back to PDF. `F1-07-79`'s cases that assert the CSV
  default are **updated in the same commit**, not skipped — the implementing lane lands with this ADR.
  If that lane ever slips past this commit, those cases must carry
  `@Skip('superseded by ADR 2026-09-12d §2; re-lands at M5')` instead (ADR 2026-09-05i §4).
- **Dependencies:** root `pubspec.yaml` gains the override with its reasoning; `app/pubspec.yaml`
  gains `pdf` and `printing`. `packages/{core_crypto,data,sync_engine}` keep `sodium: ^4.1.0` —
  the 12c attempt to loosen them is reverted and must not be re-attempted.
- **Docs:** `07 §14` and `13 §3.2`'s S8.2 row lose 12c's CSV-default line; ADR 2026-09-12c §1 gains a
  supersession note.
- **Milestone:** M5. The F3 byte-goldens and the PDF watermark stay **M12** (ADR 2026-09-12 §2–§3),
  but they are now buildable when M12 arrives rather than blocked.

## Open ⚠️
- **`07 §6`'s per-A/C statement export (S4) reads *export this A/C (PDF/XLSX)*.** PDF is now real, so
  that line half-works; the open question narrows to whether CSV joins it. Still the owner's yes/no,
  carried from ADR 2026-09-12 and 12c.
- **XLSX package choice** — unchanged and still outstanding.
- **The override is ours to watch.** It is invisible in day-to-day work and wins over every
  constraint in the workspace. Worth a line in the M14 hardening pass: confirm `pdf` still needs it,
  and drop it the day `pdf` admits `archive ^4.2.0`.
