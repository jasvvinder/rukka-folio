# Changelog — Rukka Folio

Running record of what changed in this repository and in the development environment, one entry per working session. Newest first. Kept by hand at the end of every session, before the owner commits; the commit hash is filled in afterwards.

**How to write an entry**

- Heading: `## YYYY-MM-DD — <milestone or slice>` (use `env` for toolchain/environment work, `docs` for spec-only sessions).
- Sections, each optional: **Added**, **Changed**, **Decided** (link the ADR in `docs/decisions/`), **Open** (⚠️ items handed to the owner), **Commits** (hashes once committed).
- Record *what* and *why*, not the diff — git holds the diff. One line per item.
- A 🔒 change is never recorded here alone; it needs an ADR in the same commit.
- No financial data, keys or secrets — this file is committed.

---

## 2026-09-05 — docs: auth & devices vs the hostile relative (ADR 2026-09-05d)

Fourth review of the day, of 06. The strongest spec of the four; its gaps were flows that let a hostile human — or two colluding guardians — act faster than the owner can notice.

**Decided** — `docs/decisions/2026-09-05d-auth-devices-human-attackers.md`
- 🔒 Guardian recovery and guardian phone-change **wait 24 h with one-tap Cancel** on every existing device when the user still has an active device; immediate only when none exists.
- 🔒 **Uncertified devices see nothing but themselves** — server verifies the cert under the UMK public key, RLS requires `certified` for every tenant table.
- 🔒 **Support revocation delayed 24 h, cancellable**, lands unsigned → target suspends, never wipes.
- 🔒 Keystore bound to the **current biometric set**; enrolment change → MPIN. 🔒 **MPIN attempt policy** (5 free, escalating, 10 → OTP+biometric), HMAC under a hardware-backed key, counter survives app-data clearance.
- 🔒 **New-device notice on every path** (incl. silent platform key sync) + `device_added` signed record; verification events are signed records.
- Threat model names Apple/Google-account + number compromise; invites phone-bound; 15-min revocation lag stated; challenge/registration rate limits.

**Changed** — 06 §3, §4.4, §5, §6, §7, §8, §9.3 (placement fix), §9.4, §10, §11 · 04 §1.2, §7.3 · 03 §2.5 · 07 §5.6 · 09 suite C · 10 M6.

**Open** ⚠️ — rate-limit numbers; per-tenant 24 h window; Android keystore invalidation across OEMs.

**Commits** — pending.

---

## 2026-09-05 — docs: storage durability & integrity (ADR 2026-09-05c)

Third review of the day, of the data model (03). Spine stands (envelopes are truth, projections disposable, integer paise, one plaintext boundary, append-only by grant). Gaps were at the edges 03 had not looked at.

**Decided** — `docs/decisions/2026-09-05c-storage-durability-integrity.md`
- 🔒 **India residency** for DB, object storage, backups, logs; PITR + snapshot policy (numbers ⚠️); quarterly restore drill; every restore bumps `store_epoch`.
- 🔒 **`blob_hash`** plaintext column — corruption is re-fetched and counted, never quarantined; only an intact blob with a bad signature is tampering.
- 🔒 **`projectorVersion`** recorded in every lock/close envelope; older readers show *update to verify*, never a false mismatch; result-changing projector changes bump min-client-version and force Recompute.
- 🔒 **Phone numbers encrypted at rest** (`phone_ct` + `phone_hmac`, server KMS); **invitees' numbers never stored** (HMAC only).
- Shape checks enumerated (`rejected:shape`); local corruption path (`quick_check`, drop+Recompute / re-bootstrap; `integrity_ok` gates Home); RLS with our own claims via `SET LOCAL`; platform backups excluded; private bucket + orphan sweep; audit retention 24 mo.

**Changed** — 03 §1/§2.1/§2.3/§2.5/§3.1/§5/§6/§7/§8 · 02 §8 step 4 · 04 §4 · 05 §3, §8 · 06 §7, §9.3 · 09 suite E · 10 M2/M4.

**Open** ⚠️ — PITR/snapshot/RTO-RPO numbers vs hosting plan; KMS/Vault choice + rotation; whether projector bumps share the crypto/sync min-version route group.

**Commits** — `460eb53`.

---

## 2026-09-05 — docs: sync trust boundaries (ADR 2026-09-05b)

Same review as the client blueprint, applied to 05. Core of 05 stands (seq cursors, idempotency, key-sync-before-drain, content-blind server, cross-client close hashes). Every gap was one shape: the server was still trusted for things it should only relay.

**Decided** — `docs/decisions/2026-09-05b-sync-trust-boundaries.md`
- 🔒 Structural facts (membership, roles, limits, revocation, removal, rotation) are **signed records** from certified devices; server rows are their projection; clients verify the record, not the row.
- 🔒 **No wipe on the server's word** — unsigned revocation → *suspended*, data kept; wipe only on a verified signed record.
- 🔒 **Per-author sequence inside the ciphertext** — withholding becomes a visible gap; provisional projection; month/year-close blocked while gaps exist.
- 🔒 **Dangling refs are `held`**, not counted (fixes the M1 orphan-amendment double-count when the original arrives late).
- 🔒 **Revocation cut-off = server `seq`**, never HLC (a stolen phone cannot backdate its receipt).
- 🔒 **Store epoch** on every response + outbox `observed` state (read-your-writes; `write_lost` event) — survives a server restore.
- Rate limits + per-plan quotas (numbers ⚠️ 08), plaintext padding to size buckets, signed-URL lifetimes, content-free server metrics, separate `maintenance` deletion role.

**Changed** — 05 §1/§3/§4/§5/§9/§10/§11 · 03 §2.5, §3.1 (schema) · 04 §1.2, §9.2 · 02 §5 · 06 §7 · 09 §2 suite D · 10 M2/M3/M4 rows.

**Open** ⚠️ — quota/rate numbers per plan (08); guardian k-of-n revocation as multi-sig vs k records (M3); one `bigserial` for records + envelopes (with 05 §11.1 test). Owner raised **whether to drop zero-knowledge** for a server-readable tier; **ruled 5 Sep 2026: keep zero-knowledge for now.** The opt-in company-assisted-recovery tier is parked in 10 § Phase 2 (not scheduled, not 🔒). Owner also asked why libsodium rather than Flutter/Dart built-ins — answered in session (Dart has no AEAD/signature/KX primitives; libsodium is native C over FFI, audited, one implementation for both platforms); rule 7 stands.

**Commits** — `217818a` (ADR + cross-refs); zero-knowledge ruling + parking-lot row follow in the next commit.

---

## 2026-09-05 — docs: client hardening (ADR 2026-09-05)

Owner brought a generic Flutter fintech security blueprint (MASVS / PCI framed) and asked what we adopt. Assessed against 04/05/06/07/13; about two thirds already decided or compatible.

**Decided** — `docs/decisions/2026-09-05-client-hardening.md`
- **Rejected 🔒:** "server is the sole authority for financial calculations" — contradicts zero-knowledge; the ADR tabulates our equivalents (signed envelopes, deterministic projector + cross-client hash, flag-for-review limits, signed quorum approvals) so the idea does not return.
- **Adopted 🔒:** SPKI public-key pinning with backup pins, hard-fail in staging too (05 §1) · OS transport configs, `FLAG_SECURE`, tap-jacking flag (M0 shell) · obfuscated release builds with symbols kept as CI artefacts · **screenshots/recording blocked** — owner-ruled, because PDF/WhatsApp share already exists (07 §5.6) · root/jailbreak/debugger **detect-warn-log, never block** (06 §4; 04 §1.2) · foreground inactivity lock 5 min beside the 2 min background lock (06 §4) · key material only in `Uint8List`/`SecureKey`, FFI-only, never a `MethodChannel` · CI: secret scan, dependency audit, no bare `print(` · temp exports purged after share (readable Drive export untouched) · MASVS L2+R as the M14 checklist; PCI out of scope, DPDP not GDPR.

**Changed**
- 04 §1.2, 05 §1, 06 §4 + §11, 07 §5.6, 09 §4 (client-hardening gates), 10 (M14 row + hardening-by-milestone note).

**Open** ⚠️
- SPKI pin set for hosted Supabase (intermediate CA + backup) and rotation runbook — verify at M4.
- `FLAG_SECURE` on the *Show my code* ceremony screen (consistent; confirm camera path unaffected).
- Detection library: prefer a small native check we own over a third-party package in the trust path.
- Code items (manifest flags, ci.sh steps, purity grep) land with their owning milestone — none written this session.

**Commits** — `2b89db7`.

---

## 2026-09-04 — M1: ledger core (pure Dart)

Exit gate (10 M1): **suite A incl. property tests, green** — `./scripts/ci.sh` passes end to end; `core_ledger` carries 134 tests, among them the golden replay of all five worked examples (8 books, 185 vouchers: every ledger row, every closing c/f, every trial-balance row and total, and the three Due to/from pairs whose both sides are in the package).

**Added** (`packages/core_ledger/lib/src/`, ~2,900 lines + ~2,300 lines of tests)
- `money.dart` — `Paise` extension type over `int`: integer arithmetic only, no path to a float (rule 1); `Side`; `floorDiv`, `roundHalfUp`.
- `local_date.dart`, `hlc.dart` — `LocalDate` / `YearMonth` / `FinancialYear` (per-book start month, default April) with no clock anywhere; `Hlc` = 48-bit ms + 16-bit counter (03 §1), `tick()` takes the physical reading as an argument; `(hlc, id)` event order.
- `accounts.dart` — `BookType`, the seven `AccountClass`es, `MoneySubtype` (incl. `cashCollection`), `SystemRole` for the equity_system wizards, `Account`, `Chart`.
- `entry.dart` — `Entry` / `Line` / `EntryRefs` per 02 §1.3 wire names; `fromJson` rejects non-integer money; unknown fields ride along at entry, refs and line level and are written back byte-stable (03 §3.3.4); `amendWith` / `reversal` builders (02 §5).
- `invariants.dart` — universal invariants 02 §1.4 + reader re-checks (`review_required` vs carried limit, `pending` only for an advance request shape); authoring-only future-date rule kept out of the projector.
- `verbs.dart` — the six verbs, the adjustment wizards (opening, cash-count difference, write-off), advance request/spend/return, partner paid-cost/drawing, and one-entry `profitDistribution` (interest first, then remainder by ratio). Wrong-class slots throw; a gollak is never a spending source and empties only into Cash or a bank account (02 §8.2).
- `ratio.dart` — `splitByRatio` 🔒 rule: floors, remainder to the largest ratio, ties to earliest; property-tested.
- `projection.dart` — `project(events, chart, {opening, heldInTray})`: sorts by `(hlc, id)`, quarantines violators as security events, folds approval decisions (last wins; self-approval quarantined — 02 §7.2 item 1), amend chains (head only, kind fixed), reversals (exact mirror, once), the advance queue vs the review queue, period lock rule (02 §8), year close with reader-side vector re-verification and certificate voiding on re-open (02 §8.1); `BalanceVector.canonical()` as the close-hash input; `trialBalance`, `statement` (running balance + side per row), `netProfit`, `yearClosePreconditions`.
- `partners.dart` — `interestOnCapital` (average daily balance, inclusive days, half-up to the paisa; debit balances charged unless told otherwise), `settlementCapacity`, `partnerDrift` (02 §7.1).
- `advances.dart` — `openAdvances` with FIFO ageing (02 §7). `interbook.dart` — `InterBook.transfer` / `pocketExpense` pairs sharing `transfer_group`, `isInTransit`, `reconcile` (02 §6). `cash_count.dart` — `DenominationSheet`, `CashCount` memo event, `countPolicy` / `validateCount`, `resolveCount` → verified / adjustment / recognition (02 §8.2).
- Tests: `test/golden_worked_examples_test.dart` parses the worked-example markdown directly (chart, daybook, ledger rows, TB) so the fixtures stay in `docs/reference/` as the single source; unit/property suites per module.

**Decided** (interpretations, all conservative, marked `⚠️ SPEC` in code — no 🔒 change, no ADR)
- `review_limit_paise` is nullable in the engine: `null` = no limit applies (own personal book, single-member book). 02 §1.3 types it as a plain int; the "never flagged" cases needed a representation.
- Advance movements map onto the six kinds as request = `money_out` + `pending`, spend = `money_out`, return = `money_in`. 02 fixes the postings, not the kind; balances never depend on kind.
- Re-dating a late arrival is the one amendment accepted against a locked period: lines identical, only the date moves, into a period open at the amendment's HLC. Everything else in a locked period must go through reversal. The tray itself (arrival order) is client-local and is passed to `project` as `heldInTray`.
- Verified interest illustration in paise: Amrit ₹4,295.89 · Sukhdev ₹2,311.23 · Harjit ₹1,354.52 (8 %, 1 Apr–31 Jul, day of posting counts).

**Open**
- ⚠️ 02 §7.1 shows Harjit's interest as ₹1,354 and the remainder as ₹5,86,039; `joint-business-partnership.md` §5 shows ₹1,355 / ₹5,86,038. Both are whole-rupee displays of ₹1,354.52 — no engine conflict, but the two documents should agree. Suggest both print paise.
- ⚠️ `joint-business-partnership.md` §5 "equal share of costs" splits ₹3,35,000 in rupees (1,11,668 / 1,11,666 / 1,11,666). The 🔒 rule divides in paise: 1,11,666.68 / 1,11,666.66 / 1,11,666.66. Presentation column only; flag for the bookkeeper pass.
- ⚠️ `trust-singh-sabha-gurudwara.md` predates the 2–3 Sep gollak ADRs: its "Gollak Cash A/c" is spent from directly (T-003, T-018…), so the fixture treats it as plain `cash`. On sign-off, consider splitting it into a `cash_collection` Gollak plus the seeded Cash A/c with Transfer vouchers between them.
- ⚠️ Owner to confirm the three interpretations under *Decided* (nullable limit, advance kinds, re-date rule) or point at the section that settles them.
- Not in M1 by design: envelope signing/encryption around these payloads (M2, 04), Drift persistence + the running-balance cache (M3, 03 §3.2), HLC generation from a real clock (M4 sync), FY-scoped P&L views and statement presentation strings (M5+).

**Commits**
- _pending_

---

## 2026-09-04 — M0: scaffold

Exit gate: **CI green on hello-world tests** — `./scripts/ci.sh` passes end to end (pub get · generators current · format · purity · strings · analyze · 4 package suites · 3 app widget tests).

**Added**
- Pub workspace root (`pubspec.yaml`, one `pubspec.lock`) over `packages/core_ledger`, `core_crypto`, `data`, `sync_engine` and `app`; strict analysis options at root, per package and in the app.
- Four pure-Dart packages, each with a `packageName` hello export and one test; doc comments name the spec they own (02/04/03/05).
- `app/`: Flutter, iOS + Android targets (`com.rukkafolio.*`), Material 3 theme built from tokens only, light + dark, brand fonts (Mukta 400/500/600, Mukta Mahee 400/500/600, Noto Sans variable; OFL licences beside them), `flutter_localizations`, hello screen showing `app.name` + `splash.opening`; widget test renders EN / PA / HI.
- `scripts/ci.sh` — the gate, also run by `.github/workflows/ci.yml` (Flutter 3.47.0 stable, ubuntu).
- `scripts/gen_tokens.dart` — the only writer of `tokens.css`, `design/tokens/tokens.dart` and `app/lib/shared/tokens.dart`; `--check` fails CI on drift (design-system.md §status). Regenerated outputs verified value-identical to the hand-synced files; new: `RkIcon`, `RkMarkLight/Dark`, `RkMotion.markUnlockTotal`, `RkSpace.cardPadding`, `--row-min-h`.
- `scripts/check_strings.dart` — EN/PA/HI key parity, ICU placeholder parity (01 §1 rule 7), forbidden-jargon scan with the rule-4 whitelist (`app.name`, `app.name.short`, `about.*`), dotted key shape.
- `scripts/check_purity.sh` — no Flutter in `packages/`; no `dart:io`/`dart:math`/`DateTime.now()`/`Random()` in `core_*`; no hex colour literals in `app/lib` outside the generated tokens file.
- `scripts/gen_l10n_arb.dart` — see Decided.

**Changed**
- `design/tokens/tokens.json`: `space` gains structured `gutter` / `cardPadding` / `rowMinHeight` (values already present in its note); `$meta.note` now names the generator. No token value changed.
- `design/tokens/tokens.css`, `tokens.dart`: now generator output (headers say so).
- `design/design-system.md`: generator landed; M0 checklist ticked. `CLAUDE.md`: scripts listed in Layout; workspace / tokens / strings commands.
- `.gitignore`: Dart/Flutter/iOS/Android artefacts, `app/lib/l10n/gen/`, `.env*`.

**Decided** (build-time bridge, not a spec change — no ADR)
- 01 §1 rule 9 🔒 keeps ARB keys dotted (`screen.element.state`); Flutter gen_l10n only accepts Dart identifiers. Canonical ARBs stay dotted in `app/lib/l10n/`; `gen_l10n_arb.dart` derives identifier-keyed copies into the git-ignored `app/lib/l10n/gen/` (`app.name` → `appName`). Collisions fail the build.
- Product name stays Latin in PA/HI ARBs (01 §1 rule 8: a name the user matches, not a word inside a sentence; lockup shows it that way, 11 §4.2).

**Open**
- ⚠️ `splash.opening` PA/HI (ਤੁਹਾਡੇ ਵਹੀ-ਖਾਤੇ ਖੋਲ੍ਹ ਰਹੇ ਹਾਂ। / आपके बही-खाते खोल रहे हैं।) drafted from the 01 §2 term table; native review at the M12 gate.
- ⚠️ Bundle id `com.rukkafolio.*` is a placeholder until the domain / store-name check in README § Name.
- Not in M0 by design: `server/supabase` (M4, needs Docker), `testing/` harness (M4), Drift/SQLCipher/libsodium deps (M2/M3), `tokens.dart` consumers beyond the hello theme (M5).

**Commits**
- `4eee9c1`

---

## 2026-09-04 — env: development toolchain

**Added**
- Flutter 3.47.0 stable (Dart 3.13.0) via Homebrew cask; `flutter doctor` clean in every category.
- CocoaPods 1.17.0, Deno 2.9.5, GitHub CLI 2.97.0, Supabase CLI 2.116.0.
- Android SDK via `android-commandlinetools` cask: platforms 35 + 36, build-tools 35.0.0 + 36.0.0, platform-tools 37.0.1, emulator 37.1.11; all licenses accepted.
- OpenJDK 17.0.20.1 (Homebrew formula, no sudo) — Flutter configured with `--jdk-dir`.
- `~/.zprofile`: `ANDROID_HOME`, `JAVA_HOME`, `platform-tools` on PATH.
- This file, and the changelog rule in `CLAUDE.md` § Workflow.

**Open**
- ⚠️ Docker Desktop not installed — cask needs a sudo password. Required from M4 for `supabase db reset` and local RLS tests. Owner runs `brew install --cask docker-desktop`.
- No Android emulator image yet; not needed before M12 (iOS ships first, 10 🔒).

**Commits**
- `a08ec51`

---

## 2026-09-03 → 2026-09-04 — docs: design fold, brand v1.4, loading states

**Changed**
- Dark-theme credit/debit tokens → `#4FA37A` / `#CB6F6F` (debit lifted one step for AA on surface).
- 11 §4.5 — how the app waits: loader rule, ruled skeletons, splash branches; canvases 1/11 lockup, spinner removed.
- 11 §4.2 → v1.4: brand v1.2 mark canonical, icon package + animation reference, canvas 3 sealed mark.
- Verb pill: *Move money* is the fifth position; one door per adjustment wizard.
- Menu gains *Close the month*; Import lives in the entry header (S2), not a Menu row; Legal row on the Menu (07 §1).
- Roadmap: Phase 2 parking lot (non-normative).
- Gollak: deposits flexible (Cash A/c or bank, whole or in parts); empties only into the Cash A/c. Trust Cash A/c gets its own verify-mode count (C3c).
- Canvas 7 split into 7 / 15 / 16; canonical bottom-nav icon set; `/design-pull` pins canonical canvas display names.

**Decided**
- `docs/decisions/2026-09-03-gollak-deposit-flexibility.md`
- `docs/decisions/2026-09-03-menu-close-row-and-import-in-entry.md`
- `docs/decisions/2026-09-03b-entry-doors-move-money-and-wizards.md`
- `docs/decisions/2026-09-03c-brand-v1.2-mark-canonical.md`
- `docs/decisions/2026-09-03d-loading-and-splash.md`

**Commits**
- `9125a8f` `6f02926` `b2c6e08` `2655410` `098a8cf` `6d8a1f7` `ddcfede` `a761ea0` `2c1a42c` `d66ca49` `93d7dac` `4a00f50`

---

## 2026-09-01 → 2026-09-02 — docs: design slices 2–4, rulings A1–A4, Option B

**Changed**
- Slice 2: 13's screen inventory reconciled with the drawn canvases.
- Slice 3: danger-surface verdict; `sunk` + `scrim` tokens added as PROPOSED.
- Slice 4: S6.1 drawn, S17.1 folded, S18.x are documents, Narration carve-out, branch order ruled.
- A1+A2: one PIN everywhere; S7.2 = import balance check. A3: drawings (S2.5) + donation receipt (S4.2) ratified, D6 removed. A4: head displays as *President*; S7.4 import preview added.
- Option B ruled: designations are labels, permissions admin-granted; designation vocabulary tables (trust/org + business) saved.
- Trial Balance transliterates — ਟ੍ਰਾਇਲ ਬੈਲੇਂਸ / ट्रायल बैलेंस 🔒.
- 1 Sep design fold landed: MPIN, role labels, onboarding branches, vocabulary.

**Added**
- `/design-pull` command + byte-exact extractor `scripts/design_mirror_extract.py` (envelopes ordered chronologically).

**Decided**
- `docs/decisions/2026-09-01-pin-model-and-import-ids.md`
- `docs/decisions/2026-09-02-ratifications.md`

**Commits**
- `ab96d83` `6992bcc` `6bf4e99` `db8df45` `6493ece` `30b04b5` `b8c6843` `2fbaac6` `07f1980` `cc42990` `a6e0a5e` `31661b4` `ab1c7f1`

---

## 2026-08-30 → 2026-08-31 — docs: specification set v1.0

**Added**
- Specs 00–13, `requirements-architecture.md` (non-normative), `design/` system + tokens, `CLAUDE.md`, `README.md`.
- Screens: account · subscription · support · legal · system states; entry detail, invite, profile, plans, help, legal, update/maintenance, permissions, viewer, search, Group-by flow; backup setup, recovery flow, devices and backup settings.

**Changed**
- Phone recovery flow; language keyword corrections.

**Decided**
- `docs/decisions/2026-08-30-audit-remediation.md`

**Commits**
- `6d030a6` `774c421` `0efff54` `caa2499` `c3c66ce`
