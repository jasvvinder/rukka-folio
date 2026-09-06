# PLAN.md — Rukka Folio build tracker

**Read this file first in every session. It is the only state needed to start** (≈3k tokens).
Legend: ✅ done (tests green on `main`) · 🟡 in progress · ⬜ todo · ⛔ blocked on owner / external.
Rules of the file: a module turns ✅ only when its test ids pass in the push lane; `/plan` refreshes it;
spec authority stays in `docs/` (this file is a tracker, never a spec).

---

## 0. Where we are — 2026-09-07

| Layer | State | Evidence |
|---|---|---|
| `core_ledger` (02) | ✅ M1 | suite A: 111 ids + golden replay of 8 worked-example books |
| `data` (03 client) | ✅ M2 | suite E client half: Drift + SQLCipher schema v1, mirror/outbox, Recompute, corruption path |
| `testing/harness` | ✅ M2 | two-client rig; D-05b-2/3/4 |
| `core_crypto` (04) | ✅ M3 | suite B: 75 tests — envelopes, keys, ceremony, wrapping, recovery, signed records, chain, Shamir |
| `sync_engine` (05) | ⬜ stub | one hello-world test |
| `server/` (03 §2, 05, 06) | ⬜ absent | — |
| `app/` (07, 13) | ⬜ shell | `main.dart`, `shared/tokens.dart`, ARB EN/PA/HI — **no feature yet** |
| Traceability | ✅ | `check_coverage`: 242 tests · 242 ids · 0 orphans (warn-only until M4) |

✅ ADR 2026-09-06 ratified 7 Sep (four answers recorded in the ADR; 04 §2/§7.3/§9.2/§11 updated). ⛔ **Owner now:** the §4 lead-times — each row names its first action; details in `docs/ops/lead-times.md`.

---

## 1. The fast path — four phases, parallel lanes

**Principle.** One orchestrator session per phase runs `/fanout`: lanes are subagents that own
**disjoint directories** (so no worktrees, no merge), each builds tests-first against named spec
sections, and the gate runs **once** per phase. The owner reviews on a device each evening.

| Phase | Dates | Lanes in parallel | Exit |
|---|---|---|---|
| **A — foundations** | 7–13 Sep | P0 tooling → then **S** server · **Y** sync_engine · **U1** app foundation · **U2** entry+home · **U3** ledger+statement · **C** auth client | push lane green; app installs on the owner's iPhone; solo entries flow end to end **offline** |
| **B — people** | 14–20 Sep | **S2** server (invites, ceremony, approvals) · **Y2** sync (multi-author, revocation counting) · **U4** members+ceremony · **U5** family money · **U6** close · **U7** recovery screens | two phones sync; **TestFlight to the owner's family** |
| **C — money in, money for us** | 21–27 Sep | **U8** import · **U9** reports/exports + PA/HI polish · **S3+U10** subscription + console | F3 goldens; RC lane |
| **D — harden & pilot** | 28 Sep–4 Oct | hardening gates · MASVS pass · perf lane · store prep | Suite H; **pilot month starts** (Oct) |

Store launch follows the pilot and the external gates (§4). Anything sooner requires the owner to
drop 🔒 roadmap gates by ADR — the tracker does not assume that.

---

## 2. Todo by milestone → module

### M0 Scaffold ✅
- ✅ workspace, four packages, app shell, `ci.sh`, tokens generator, string + purity checks

### M1 Ledger core ✅ (suite A)
- ✅ money/paise · entries · verbs→postings · invariants · amend/reverse · periods/locks · advances
- ✅ inter-book pairs · partners + distribution + ratio rounding · cash counts · balances · HLC
- ✅ golden replay of the 8 worked-example books (provisional until bookkeeper sign-off — §4)

### M2 Local persistence & projections ✅ (suite E client)
- ✅ Drift schema v1 + SQLCipher · mirror/outbox · Recompute (pure projector) · `projectorVersion` + recompute-on-upgrade
- ✅ `held` / author-gap / as-of vector / shape invariants · corruption path · backup exclusion flags
- ✅ harness + `dart_test.yaml` lanes + seeds + `check_coverage` (warn mode)

### M3 Crypto core ✅ (suite B)
- ✅ `CryptoSuite` injection · key types (verified vs unverified) · envelopes + AAD + padding · wrapping
- ✅ ceremony (QR/code) · recovery key + sheet · device certs + chain · signed records · Shamir + guardian shares
- ✅ `reconstructVerified` (B-04-72) · independent KAT (B-04-73)
- ✅ ADR 2026-09-06 ratified (7 Sep) · ⬜ third-party Shamir vector · ⛔ external review of `shamir.dart` (M14)
- ⬜ open from the M3 changelog: `hlc` in the signed digest (ADR before M4) · `suite_version`/`payload_schema` on `envelopes_local`

### P0 Tooling for parallel lanes ⬜ (Phase A, day 1 — before any UI lane starts)
- ⬜ **ARB parts**: lanes write `app/lib/l10n/parts/<feature>_{en,pa,hi}.arb`; `gen_l10n_arb.dart` merges parts → `app_*.arb` → identifier copies. Removes the one shared file every UI lane would fight over. `check_strings` runs on the merged files.
- ⬜ **App theme from tokens**: `app/lib/shared/theme.dart` (light/dark from `tokens.dart`, Mukta/Mukta Mahee, status-colour family, `check_contrast.dart` in ci.sh)
- ⬜ **Router skeleton**: `app/lib/shared/router.dart` — four-tab bar + docked ( + ); each feature exports `routes` and U1 wires them at integration
- ⬜ **Feature folder convention**: `app/lib/features/<feature>/` + `app/test/features/<feature>/` — one lane per folder
- ⬜ **Fake sync/auth seams**: `app` depends on interfaces (`SyncClient`, `AuthClient`) with in-memory fakes so U-lanes never wait on S/Y lanes
- ⬜ `server/` skeleton: `supabase/config.toml`, `migrations/`, `functions/`, `tests/rls/`, `deno.json`

### M4 Server + sync engine ⬜ (suites D, E server)
**Lane S — `server/supabase`** (03 §2, §2.5; 05; ADR 05b, 05c)
- ⬜ migrations: identity & tenancy · devices/keys/ceremonies · envelope store (`seq bigserial`, `blob_hash`) · billing/audit/ops
- ⬜ RLS for every table; server role has **no UPDATE/DELETE on `envelopes`**; `SET LOCAL` claims; `phone_ct`/`phone_hmac` + KMS
- ⬜ functions: `sync-push` (idempotent, shape checks, quotas) · `sync-pull` (seq cursors) · `sync-meta` (keys, guardian-set history by `share_set_version`) · `auth-challenge` · `billing-webhook` stub
- ⬜ `tests/rls` hostile-query suite (E-server) · `deno test` · India region + PITR + private bucket + orphan sweep (ops checklist)
**Lane Y — `packages/sync_engine`** (05 §3–§9; ADR 05b §1–§6)
- ⬜ outbox drain + push · pull with `seq` cursors · `store_epoch` + read-your-writes · key-sync-before-drain + re-seal
- ⬜ signed records applied to rows · `seq` revocation cut-off · **k-of-n counting (D-06a-1…4)** · rate-limit/quota handling · status surface (05 §9)
- ⬜ D suite on the harness: withheld envelope, orphan amend, unsigned revocation, backdated push, epoch re-pull, flood
- ⬜ hardening: SPKI pins + rotation runbook, gitleaks + OSV in `ci.sh`, `print(` check (ADR 2026-09-05)

### M5 Single-user app ⬜ (suite F1 + stopwatch)
**Lane U1 — foundation + onboarding** (`features/onboarding`, `features/lock`, `shared/`)
- ⬜ S0.0 splash · S0.1 language · S0.05 welcome · S0.3 purpose cards · S0.4 name/photo · S0.5/S0.5b safety + recovery sheet
- ⬜ S0.6a–i business/family/trust setup · S0.6 opening balances wizard · S0.7 setup checklist · S0.8 set PIN
- ⬜ S15 app lock (biometric, MPIN fallback) · S15.1 privacy cover · S15.3 cooldown states · idle lock with draft restore (C-05a-7)
- ⬜ S13 settings (language, Appearance, auto-lock) · S19.3 no-connection · S19.5 modified-device notice
**Lane U2 — Home + the 8-second entry** (`features/home`, `features/entry`)
- ⬜ S1 Home/Position · S1.1 drill-down · S1.2/S1.3 scope switcher · S1.4 rebuilding state
- ⬜ S2 keypad-first entry · S2.1 A/C picker + inline create · S2.2 date · S2.3 transfer · S2.5 drawings confirmation
- ⬜ stopwatch test ≤ 8 s (F1 + device) · Money in / Money out vocabulary only (rule 9)
**Lane U3 — Ledger + statement + export** (`features/ledger`, `features/reports`)
- ⬜ S3 ledger index · S3.1 quick add · S4 A/C statement (Dr/Cr, running balance) · S4.1 entry detail + amend/reverse · S21 search
- ⬜ S8 menu · S8.1/S8.2 day book + export (CSV/PDF, temp-file purge) · S12.5 read-only sheet pattern (used by book-full)
- ⬜ A-02-10 both vocabularies render from one posting set

### M6 Auth & devices ⬜ (suite C)
**Lane C — `features/auth`, `features/devices`** (06; ADR 05d) — client side in Phase A against fakes, real server in Phase B
- ⬜ S0.2 phone + OTP · device keys in Keychain · sessions · min-version gate S19.1 · OTP-only device sees no tenant metadata
- ⬜ S11 devices & security · S11.4 backup settings · S11.9/S11.10 cancel windows (24 h) · S15.4 suspended · new-device notice on every path
- ⬜ biometric-set binding · MPIN lockout surviving app-data clearance · certified-only RLS (server side, lane S)

### M7 Multi-user ⬜ (H steps 1–2)
- ⬜ S9 books & members · S9.1 invite · S9.2/S9.3/S9.4 ceremony (QR, code, mismatch hard-fail) · S9.5 add a business
- ⬜ S6 inbox · S6.1/S6.2 review cards + stepper · S6.3 structural approval (quorum) · roles/limits (06 §7, Option B labels)
- ⬜ server: invites, `invitee_hmac`, membership state machine, verification records as signed records (C-05d-7/9)

### M8 Family money ⬜ (H 3–6, H2)
- ⬜ S5/S5.1 advances · S2.3 inter-book + in-transit · S8.3 family reconciliation · pocket-expense flow
- ⬜ S14/S14.1/S14.2 partner positions, distribution wizard, drift & settlement · S5.5 cash count sheet

### M9 Close ⬜ (H 8–9, H2b)
- ⬜ S10 month-close wizard (resumable) · S10.1 family status · S10.2 summary card · S10.3 late arrivals · S10.5 blocked-on-device
- ⬜ S10.4 year close + FY switcher + certified vectors · structural quorum flow · `projector_version` on lock/close

### M10 Statement import ⬜ (H 7)
- ⬜ S7 file + account · S7.0a–c mapping · S7.1 import inbox · S7.2 balance check · S7.3 transfer-pair · S7.4 preview & submit
- ⬜ parsers: CSV/XLS first; PDF per pilot bank ⛔ owner picks 2 banks · rules · Suspense (02 §10)

### M11 Recovery & escrow ⬜ (H 10; B/C recovery)
- ⬜ S11.1 guardian setup (mutual ceremony, `share_set_version`) · S11.2 ask guardians (k-of-n progress, uses `reconstructVerified`) · S11.3 paper sheet
- ⬜ S11.5–S11.8 silent restore / fork / guardian side / nothing-worked · escrow with veto timer (04 §7.5) · stolen-phone path (BK + UMK rotation)
- ⬜ 07: states for *2 of 3 approved* and moved cut-off (ADR 2026-09-06 Open)

### M12 ਪੰਜਾਬੀ + हिन्दी & polish ⬜ (F2, F3)
- ⬜ full PA/HI strings ⛔ native review gate · overflow at 375×667 and 360×800 · exports with b/d–c/d + amount-in-words EN/PA/HI
- ⬜ report suite (07 §14) · F3 byte-goldens · Android perf lane joins nightly · S16.x account screens · S17.x help · S18.x legal

### M13 Subscription + console ⬜ (suite G)
- ⬜ S12–S12.6 plans/checkout (IAP on iOS)/manage/payment problem/read-only/invoices · entitlement token + `entitlement_key` · quotas + graces + clock floor
- ⬜ `billing-webhook` real (idempotent replay, refund scoping) · promo/Small Business tables
- ⬜ admin console (12; ADR 05h): staff SSO + roles · four-eyes · hash-chained staff log · freeze · lookup quotas · transparency events

### M14 Hardening & pilot ⬜ (suite H)
- ⬜ MASVS L2+R pass (decompile, MITM, capture, log-scrub, rooted notice, SAST) · perf budgets on Android 9 / 2 GB · DPDP checklist
- ⬜ break-glass doctrine live · grievance officer named · breach + LE runbooks · restore drill artefact (REL-05c-1)
- ⬜ `check_coverage --strict` blocking · store prep (iOS first) · pilot month
- ⛔ bookkeeper sign-off of goldens · ⛔ external crypto review

---

## 3. Session economy — how every session stays cheap

1. **Start:** read `PLAN.md` §0 + the current phase only. Not CHANGELOG, not whole specs.
2. **Read specs by section:** `grep -n "^## \|^### " docs/<n>.md` → `sed -n 'a,bp'`. A lane reads only the sections its PLAN row names.
3. **Orchestrate, don't implement, in the main session.** `/fanout` spawns lanes; the orchestrator holds ≈ nothing but PLAN rows and lane reports. Lanes return structured JSON, not prose.
4. **Right-size each lane:** `effort: low` + `haiku` for mechanical work (ARB drafts, codegen, tokens, fixtures); default for logic; `high` only for `core_*` verification and adversarial checks.
5. **The post-edit hook already formats/analyzes/purity-checks.** Lanes never re-run those by hand and never run `ci.sh`; the gate agent runs it **once** per phase.
6. **Tests by file during a lane** (`dart test test/x_test.dart`), full package once at lane end. Goldens once per phase (`/goldens`).
7. **No re-reading after edits** — the harness tracks file state. No verification loops beyond one gate + one fix pass.
8. **End:** `/plan` (mark ✅ from green ids) then `/changelog` — one pass, then hand the commit message to the owner.
9. **Never** spawn a lane for something a grep answers; never fan out on a task under ~30 minutes of work.

---

## 4. External lead-times — kicked off 7 Sep, run in parallel with Phase A ⛔ owner

Status legend as above. Step-by-step for each row, what to hand back to the repo, and what the local
machine already has (Xcode 26.6, supabase/gh/deno CLIs installed, **none logged in**) live in
`docs/ops/lead-times.md`. The repo needs only ids and public URLs; secrets go to `.env` (see `.env.example`).

| Item | Needed by | Status | First action (owner) | Why it cannot be compressed |
|---|---|---|---|---|
| Ratify ADR 2026-09-06 | Phase A day 1 | ✅ 7 Sep | — | unblocks M4 counting + M11 recovery |
| Supabase project — India region (`ap-south-1`), PITR, KMS | Phase A (lane S) | ⛔ | create org + project on Pro; `supabase login`; project ref → `.env` | lane S deploys into it |
| Apple developer account + TestFlight | Phase B | ⛔ | enrol (Organization, D-U-N-S ≈ 1–2 wk) or Individual today; bundle id `com.rukkafolio.rukkaFolio` (already in the Xcode project) | family testing |
| OTP/SMS provider account | Phase B | ⛔ | pick a DLT-registered Indian provider; DLT entity + template registration ≈ 1–2 wk | live auth |
| Pilot banks (2) + sample statements (synthetic) | Phase C | ⛔ | choose 2 banks; export one CSV + one PDF each from a *test* account, then synthesise | M10 parsers |
| Native PA / HI reviewers | Phase C | ⛔ | one reviewer per language, ~4 h each in week of 21 Sep | 01 §1.8 gate |
| Payment gateway KYC; IAP products | Phase C | ⛔ | gateway KYC (business docs, ≈ 1–2 wk); App Store Connect products after Apple enrolment | M13 |
| Bookkeeper sign-off of worked examples | Phase D exit | ⛔ | book a CA/bookkeeper for a 2 h review of `docs/reference/worked-examples/` in week of 28 Sep | 🔒 ADR 05i §3 |
| External crypto reviewer (1 h, `shamir.dart` + envelope) | Phase D | ⛔ | approach a reviewer now; send `shamir.dart` + `shamir_ref.py` + a libgfshare vector | 🔒 M14 |
| Pilot families (3–5) | Oct | ⛔ | shortlist 5 households; ask 3 to commit to October | 🔒 M14 pilot month |
