# ADR 2026-09-05i — Test contract: traceability, lanes, golden governance, supersession

Fifth ADR of 5 Sep (after 2026-09-05 client hardening, 05b sync, 05c storage, 05d auth & devices).
09 was reviewed as one of seven specs in the afternoon fan-out. Verdict: **a good index and a poor
contract** — 50 lines that delegate almost everything to seven per-doc excerpts, with no per-suite
pass criteria, no CI tiering, no flakiness or test-data policy, and no way to tell whether a 🔒 line
has a test at all. That is precisely how a dozen rulings from the morning's four ADRs landed with
no test anywhere, and how one live green test in suite A came to assert behaviour ADR 05b superseded.
The golden-fixture approval gate that CLAUDE.md and the reference README both promise is defined
nowhere in 09, yet the goldens are already frozen in code. Owner confirmed 5 Sep 2026 ("accept all
recommendations").

## Rulings 🔒

### 1. Every 🔒 line names its tests — traceability is machine-checked
- **Test ids** are stable strings `<Suite>-<source>-<n>`: suite letter (A–H, F1/F2/F3), the owning
  doc number or ADR suffix, a running integer. Examples: `A-02-9` (02 §9 balance formula),
  `D-05b-3` (ADR 05b §3 author gap), `C-05d-1`. Ids appear in the test's `test()`/`group()` name
  as the first token (`'D-05b-3 withheld envelope blocks close'`) so a grep finds them.
- **Marker syntax.** Every line in `docs/` carrying 🔒 ends with `⟦tests: id, id⟧` (U+27E6/U+27E7
  brackets, comma-separated ids). A 🔒 heading covers its section: the marker may sit on the heading
  line instead of every bullet beneath it. A ruling that is *deliberately* untestable (a naming rule,
  a precedence rule) carries `⟦tests: n/a — reason⟧`.
- **`scripts/check_coverage.dart`** (new, wired into `ci.sh`) fails on (a) a 🔒 line with no marker,
  (b) an id in a marker that no test declares, (c) an id declared by a test that no marker names
  (orphan test — warning only). **Phased:** warn-only until M4 exit (the backlog of existing 🔒 lines
  is annotated milestone by milestone as their tests land); **blocking from M4**. The 05e/05g/05h/05f
  ADRs written today annotate their own rulings from the start.

### 2. CI lanes — what runs when
| Lane | Trigger | Runs |
|---|---|---|
| **push** | every push / PR | format · purity · strings · `check_coverage` · `check_contrast` (design ADR) · secret scan (gitleaks) · OSV audit of `pubspec.lock` · bare-`print(` check · suites **A, B, E-client, G** (as they land) · **F1** widget tests · release-define assertions (no pinning-off, no hostile-fixture define in the release lane) |
| **nightly** | scheduled | two-client soak (D) with fresh seeds · property/fuzz with fresh seeds · perf p95 (ruling 6) · **E-server**: `supabase db reset` + `deno test server/functions` against a disposable project · RLS hostile queries |
| **RC** | tag `rc-*` | **F2** device lab (real devices, ruling 6) · export/report goldens (**F3**) · **H** (H, H2, H2b) |
| **release** | store submission | MASVS L2+R · decompile · MITM · screen-capture · log-scrub (ADR 2026-09-05) · restore-drill report present and < 90 days old (ADR 05c §1) |

09 §4's "every push" hardening gates are **scheduled**, not current: the scanner steps enter `ci.sh` at
M4 (ADR 2026-09-05 ruling 10). Until then 09 says so explicitly instead of describing a gate that
does not exist. `ci.sh` grows a `LANE` variable (`push` default) so the same script serves all four.

### 3. Golden governance — the worked examples are provisional until signed
- `docs/reference/worked-examples/` is **provisional**. Suite A's golden replay passing proves the
  engine reproduces the *documents*; it does not prove the documents are right. The README carries
  YAML front-matter `approved_by:`, `approved_on:`, `content_hash:` (BLAKE2b-256 over the five
  example files, hex) — all three empty today. `check_coverage.dart` (same script, second job)
  verifies that when `approved_on` is set, `content_hash` matches the files; **any post-approval
  change to a figure requires an ADR** and a new hash.
- **Sign-off blocks M14 exit, not M2.** The engine can be built and dogfooded on provisional goldens;
  it cannot go to pilot on them.
- The README header is corrected to **five entity types, eight books, 185 vouchers** (the partnership
  example was added after the header was written; the golden test and CLAUDE.md already say so).
- README §3's coverage gaps are **recorded in 09 §2 A**: no period lock, year close, amend, reversal,
  rejected entry, statement import or Suspense line appears in any golden — **suite A is not proof of
  02 §5, §8, §8.1 or §10**; those rest on unit/property tests and on H until the fixtures grow.
- Two fixture defects found today go to the 05e (ledger) ADR and the errata: the partnership split
  stated in rupees against 02 §7.1's paise rule, and the interest figure ₹1,354 (02, `partners_test`)
  vs ₹1,355 (fixture). 09 records only that suite A must not be re-frozen until both are reconciled.

### 4. Supersession rule — a doc change that flips behaviour skips the old test the same day
When a ruling changes behaviour a green test asserts, the **same commit** as the doc change marks the
test `@Skip('superseded by ADR <id> §<n>; re-lands at M<n>')`. A skipped test is a tracked debt: the
id stays, the milestone named in the skip must re-land it, and `check_coverage` lists live skips in
its report. **Applied now** (by the main session, not this ADR): `packages/core_ledger/test/
projection_test.dart` — the case *"amendment must keep the kind; amending a missing target is
quarantined"* asserts immediate `amendTargetMissing` quarantine; 02 §5 + ADR 05b §4 require `held`.
Skip with `superseded by ADR 2026-09-05b §4; re-lands at M2` and split the kind-check half out so it
stays green.

### 5. Property tests shrink, or at least reproduce
The three seeded loops (`Random(20260904)`, `Random(71)`, `Random(7)`) do not shrink and do not print
their seed on failure. Rule: adopt a **shrinking property-testing package** (⚠️ candidates to evaluate
at M2: `glados`, `dart_check`/`propcheck`-class — pick the one still maintained and Flutter-free) for
suite A/B property tests. Until adopted, or where a generator cannot be expressed: seed comes from
`PROPTEST_SEED` (env) with a fresh random default that is **printed in the failure message**, and
every failing seed is checked into `test/regress/seeds.txt` as a permanent regression case.

### 6. Performance is a gate with a named device
| Budget | Device | Statistic | Lane |
|---|---|---|---|
| cold start < 2 s · entry save < 300 ms · Home render < 100 ms at 10k entries | **iPhone SE 3rd gen, iOS 16** (13 §10 item 9) | **p95 of 20 runs** | nightly (simulator) + RC (device) |
| same budgets | **Android 9, 2 GB, 360×800** | p95 of 20 | from **M12** |
| app size **< 40 MB** (13 §10 item 9) | both | per build | push (size diff comment), RC (hard) |
Regression threshold: a nightly p95 more than **15 % worse** than the 7-day median fails the lane.
⚠️ App-size budget split between iOS IPA and Android AAB to confirm at M12. 07 §19 item 6 closes.

### 7. Harness, fixtures and hygiene
- **`/testing/harness`** (CLAUDE.md layout, created at M2) holds the two-client rig: ≥ 2 simulated
  devices, one server, **deterministic scheduler** driven by a **seeded network-reorder log** so any
  failure replays from its seed. `/testing/fixtures` holds **synthetic** sync/UI fixtures only; the
  accounting goldens stay in `docs/reference/` (single source, parsed in place). `/testing/goldens`
  holds export byte-goldens (F3).
- **Hostile-client fixture** is a `--dart-define=HOSTILE_ENVELOPES=true`; the release lane asserts the
  define is absent from the build, exactly as it does for the pinning-off define.
- **Test-data hygiene:** `check_purity.sh` gains a grep over `testing/` and `*/test/` for real-looking
  Indian mobile numbers (`[6-9]\d{9}`), Aadhaar-shaped (`\d{4} \d{4} \d{4}`) and PAN-shaped strings;
  fixtures use the reserved `+91 99999 xxxxx` range and the fictional Sharma/Kaur/Verma names already
  in the goldens.
- **Flaky policy:** a test that fails then passes unchanged is **quarantined the same day** (tagged
  `flaky`, excluded from the push lane, kept in nightly) with an owner and a deadline ≤ 2 weeks in the
  test's skip reason. Blind retry (`--retry`) is never configured.

### 8. Suite F splits; exports get a letter
- **F1** — widget tests: every push. **F2** — device lab (stopwatch, airplane, 200 % font scale,
  grayscale, PA/HI overflow at 375×667 **and 360×800**, screen-capture block, privacy cover under
  capture, reduced-motion, dark mode, biometric-in-stopwatch): RC. **F3** — export/report byte-goldens
  (locale-pinned PDF/XLSX/CSV) **plus** Indian digit grouping and amount-in-words in EN/PA/HI: RC.
  This dissolves the 09-vs-`ci.sh`-vs-10 M5 conflict: M5's exit gate is *F1 + stopwatch*.
- **Suite E** names its runner: client half `dart test` in `packages/data` (push); server half
  `supabase db reset` + `deno test server/functions` (nightly, RC).
- **Suite G** runs "as it lands in its milestone" (M13), matching `ci.sh`'s header.

### 9. Small rules that close known holes
- `dart_test.yaml` at the workspace root: tags `A B C D E F1 G property flaky slow`, per-tag timeouts,
  `flaky` excluded from the default preset.
- The golden test's `../../docs/reference/worked-examples` path becomes package-root-relative (via
  `Directory.current` resolution or a `PUB_PACKAGE_ROOT`-style helper) so `dart test` passes from the
  workspace root too.
- **Shape checks:** one table-driven test over all eight checks of ADR 05c §5, each row asserting
  `rejected:shape` names its check (suite E).
- **Clock-jump tests:** author gap surfaces in Inbox at 24 h + 1 min and not at 23 h 59 (D); an acked
  envelope un-observed for 30 days lands in Inbox (D); recovery window completes at 24 h (C).
- **§4 release gate** reads "any red in **A–H** for the lane in question" — F, G and H were absent.
- 09 §preamble's inheritance list gains **design-system §3.1** and **13's S-ids** as acceptance
  vocabulary.

### 10. Locked rulings that had no test — ids assigned
| Id | Ruling | Suite · one-line test |
|---|---|---|
| C-05a-7 | 5-min foreground lock; draft survives | C: idle 5 min with digits typed → lock → unlock → same digits in the same field |
| F1-05a-2 | ATS, `cleartextTrafficPermitted=false`, `filterTouchesWhenObscured` | F1 (static): parse Info.plist / manifest, assert the three values |
| F2-05a-11 | temp export & sheet purge; nothing on public storage | F2: share a statement, return, assert cache dir empty and external dir untouched |
| B-04-8 | zeroise; keys never `String`; never over a `MethodChannel` | B: reflection-free grep test on `core_crypto` types + heap scan after `dispose()` finds no key bytes |
| B-05b-8 | plaintext padding to buckets | B: 3-char and 900-char notes → identical ciphertext length; 1,025 bytes → next bucket |
| D-05b-1 | row ≠ signed record → `meta_mismatch` | D: server fabricates a limit change without a record; client keeps the record's value and logs |
| E-05b-8 | signed-URL lifetimes, PUT-only, single object | E: upload URL rejects GET, a second object, and any request at 15 min + 1 s |
| E-05c-6 | `quick_check` + `integrity_ok` gates Home | E+F1: corrupt one projection page → Recompute; corrupt one mirror row → re-bootstrap; Home card hidden meanwhile |
| E-05c-8 | backup exclusion; private bucket; orphan sweeper; audit retention | E: attributes set on the DB file; anonymous GET on the bucket is 403; an orphan object is gone after the sweep; a 25-month audit row is aggregated |
| REL-05c-1 | quarterly restore drill | release: drill report artefact present, dated < 90 days, RTO/RPO within target |
| C-05d-9 | invite accepted only by matching `invitee_hmac` | C: joiner with a different number, same link → `invite_not_for_you` |
| C-05d-7 | verification and device events are signed records | C: an unsigned `verification_events` row is not believed; membership stays pending |
| A-02-10 | two vocabularies, one engine | A: the same entry rendered consumer and professional → byte-identical postings; only labels differ |

## Declined / deferred
- Mutation testing across the whole workspace — cost without a clear signal at this size; revisit at
  M14 for `core_ledger` only.
- Per-push device-lab runs — hardware minutes; F2 stays RC.
- A separate suite letter for the admin console — folded into G (M13) as the 05h ADR specifies.

## What changed where
- **09** — §preamble (lanes replace the one-sentence schedule; inheritance list), §1 (ids + marker,
  property rule, perf table, harness/fixtures/hygiene/flaky, supersession), §2 (A golden governance
  note; E runner; F → F1/F2/F3; G timing), §4 (A–H; scanners scheduled at M4; perf and restore-drill
  gates). · **CLAUDE.md** — § Layout (`/testing` created at M2; goldens stay in docs/reference),
  § Workflow (marker rule; supersession rule), § Commands (`check_coverage`; lanes). · **07 §18–§19**
  (F2 list incl. 360×800, capture, reduced-motion, dark; item 6 closed). · **13 §10 item 9** (one
  clause: this is also the perf-gate device). · **10** M2 (`/testing/harness`, skipped test re-lands),
  M5 (F1 + stopwatch), M12 (Android perf gate), M14 (sign-off blocks exit). ·
  **docs/reference/worked-examples/README.md** — header counts, approval front-matter (pending).
- **Code, same session (main):** `@Skip` on the stale projection test. **M2:** `/testing/harness`,
  `dart_test.yaml`, golden path fix, `check_coverage.dart` (warn mode), seeds file. **M4:** scanner
  steps, `LANE`, coverage blocking. **M12:** Android perf lane. **M14:** sign-off gate.

## Open ⚠️
1. Shrinking property-test package choice (ruling 5) — evaluate at M2.
2. App-size budget split iOS/Android (ruling 6) — M12.
3. Exact regex set for the hygiene grep (ruling 7) — false-positive rate on the existing goldens
   (₹ amounts with 10 digits) to be checked before it blocks.
4. Bookkeeper identity and sign-off medium (signed PDF in `docs/reference/`, or a git-signed commit) —
   owner, before M14.
