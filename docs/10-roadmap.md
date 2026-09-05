# 10 — Roadmap & Milestones

**Status:** Draft 1. Sliced so each milestone is finishable in a few focused Claude Code sessions, has a demoable output, and exits only through its test gate (09). Order is dependency-driven; durations assume one owner-developer working with Claude Code part-time — treat them as relative sizes, not promises.

| # | Milestone | Contents (spec refs) | Exit gate |
|---|---|---|---|
| M0 | Scaffold | Monorepo, CLAUDE.md, CI, packages: `core_ledger`, `core_crypto`, `data`, `sync`, `app`; lint + test wiring | CI green on hello-world tests |
| M1 | **Ledger core** (pure Dart) | 02: entries, verbs→postings, invariants, amend/reverse, periods/locks logic, advances, inter-book pairs, **partner class + profit distribution + ratio rounding (§7.1)**, **cash counts (§9.1)**, balances math | Suite A incl. property tests |
| M2 | Local persistence & projections | 03 §3: Drift + SQLCipher, projector (pure), balances/snapshots, Recompute determinism; **`held` state for dangling refs, author-gap tracking, close blocked on gaps (ADR 2026-09-05b §3–4)** | Suite E (client half) |
| M3 | **Crypto core** (pure Dart) | 04: envelopes, key hierarchy, wrap/unwrap, sign/verify chain, fingerprints & code derivation, Shamir (⚠️ 04 §11.1 decision here); **`author_seq` in payload, plaintext padding, `SignedRecord` sign/verify (ADR 2026-09-05b §1, §3, §8)** | Suite B |
| M4 | Server + sync engine | 03 §2 migrations + RLS, push/pull with `seq` cursors, meta/key channel, outbox (05); **signed records applied to rows, `store_epoch`, `observed` read-your-writes, `seq` revocation cut-off, rate limits + quotas, `maintenance` deletion role (ADR 2026-09-05b)** | Suites D, E (server half) |
| M5 | **Single-user app** | 07: onboarding cards, Home, 8-second entry, Ledger index + A/C statement, opening balances, basic day-book export — *dogfooding starts here* | Suite F core + stopwatch |
| M6 | Auth & devices | 06: OTP, device keys, sessions, linked-devices screen, recovery sheet + nag, min-version gate | Suite C |
| M7 | Multi-user | Invites, ceremony (QR + code, remote, delegated), roles/limits, approvals inbox (06 §7, 07 §9/§12) | H steps 1–2 |
| M8 | Family money | Advances end-to-end, inter-book transfers, in-transit, Family Reconciliation, pocket-expense flow, **partner positions + distribution wizard + settlement (S14–S14.2)**, **cash count sheet (S5.5)** | H steps 3–6, **H2** |
| M9 | Close | Month-close wizard (resumable, family status S10.1, summary card S10.2), Late Arrivals, year close + FY switcher + certified vectors, **structural quorum flow (S6.3)** | H steps 8–9, **H2b** |
| M10 | Statement import | Parsers (CSV/XLS first, PDF per-bank ⚠️ pick pilot banks), inbox, matching, rules, Suspense (02 §10, 07 §11) | H step 7 |
| M11 | Recovery & escrow | Guardians setup + k-of-n recovery, escrow with veto timer, stolen-phone path | H step 10, Suite B/C recovery tests |
| M12 | ਪੰਜਾਬੀ + हिन्दी & polish | Full PA + HI strings (native review gate, 01), exports with b/d–c/d + amount-in-words, report suite (07 §14) | Suite F full incl. PA+HI overflow |
| M13 | Subscription | Tiers, gateway webhooks, grace/read-only, admin panel (08) | Suite G |
| M14 | Hardening & pilot | Threat-model walkthrough, external crypto review ⚠️ budget, perf budgets on low-end device, DPDP checklist, Play/App Store prep, **client-hardening gates + OWASP MASVS L2+R pass (ADR 2026-09-05; 09 §4)** — decompile, MITM, screen-capture, log-scrub, rooted-device notice, SAST over release builds | Suite H full pass; pilot month begins |

**Platform 🔒 (owner ruling):** iOS ships first; the Android build follows from the same codebase at M12+. Store submission, IAP compliance (see 08 §3.2) and TestFlight distribution therefore land in M13–M14.

**Hardening items by owning milestone (ADR 2026-09-05):** M0 app shell — Android `cleartextTrafficPermitted=false`, iOS ATS, `FLAG_SECURE`, `filterTouchesWhenObscured`, `--obfuscate --split-debug-info` in the release lane · M3 crypto — `Uint8List`/`SecureKey` only, purity grep against `String` key fields, FFI-only key crossing · M4 server/sync — SPKI pins + rotation runbook, gitleaks + OSV steps in `ci.sh`, `print(` check · M5 app — foreground inactivity lock, modified-device notice, iOS capture cover, temp-file purge after share.

**Sequencing notes 🔒:** M1–M3 are pure packages — build and test them before any UI or network exists; they are the components that must be boringly correct. Dogfooding starts at M5 with the solo app (your own use case first). The mockup/prototype round the owner planned slots **between now and M5**, refining 07 before UI code. **iOS ships first**; Android follows from the same codebase after M12; AA bank integration, voice entry, more languages, and desktop remain post-v1 per the requirements doc.

**Cross-references 🔒:** brand rules (11) bind every UI milestone · the admin console (12) is M13 · the UX architecture (13) is the screen-level contract for M5 onward and its S-ids are the milestone acceptance vocabulary.

**Working method with Claude Code:** one milestone (or one coherent slice) per session; start by pointing at the exact spec sections; tests from 09 written/green before UI; any decision that changes a 🔒 line lands as a doc PR in the same commit; CLAUDE.md is updated whenever a convention is settled.

---

## Phase 2 parking lot (post-v1, non-normative)

**Status:** Parking lot, opened 2026-09-03. Nothing here is scheduled, sized, or 🔒. Its job is scope discipline (11 §1): every idea that is not in M0–M14 lives here instead of leaking into a v1 milestone. **Plan for real at M14 exit**, with the pilot month's friction list, the Account Aggregator eligibility answer, and the external crypto review in hand — all three change what Phase 2 can contain.

**Permanent non-goals still apply (00):** invoicing, GST, taxation, statutory filings, inventory, payroll never enter this list.

| Candidate | Source / rationale | Gate before it can be planned | v1 hook to protect |
|---|---|---|---|
| Account Aggregator bank feeds via a TSP | req-arch §5.1; roadmap sequencing note | ⚠️ FIU eligibility for a non-regulated bookkeeping app — confirm with two TSPs | M10 import pipeline takes an *import source* interface; statement parsers are one implementation, an AA feed is another |
| Voice entry (amount + party) in PA/HI/EN | req-arch §3 — highest-leverage accessibility feature for the target user | On-device recognition quality for PA/HI numerals; must not send plaintext money off-device (rule 4) | Voice is another *input* to the S-entry sheet (13), never a separate flow |
| More languages: Marathi, Gujarati, Tamil, Telugu, Kannada, Bengali | req-arch §3 launch set | Native review gate per language (01 §1.8) | ARB-only strings + locale-driven digit grouping already mandated |
| Desktop / web companion | roadmap sequencing note | Zero-knowledge on a browser: key storage and attestation story (04, 06) | Sync protocol (05) stays client-agnostic |
| Key-transparency log | 04 §11 item 4 | Table design kept compatible in M4 | Append-only per-tenant key-change table shape |
| Play Integrity / DeviceCheck enforcement | 06 §2, §11 item 2 | Field populated in v1; measure false-reject rate in pilot | `POST /devices` attestation field exists from M6 |
| Tally XML export | req-arch §6 — banks, buyers, accountants ask for it | Mapping of 02 classes onto Tally groups | Export layer (M12) is format-pluggable |
| Recurring entries & due reminders (rent, EMI, household salaries, udhaar follow-ups) | pilot expectation; req-arch Flow 6 step 6 | Reminder content must carry no plaintext amounts in notifications (rule 4) | Entry schema unknown-field round-trip (03 §3.3.4) |
| Interest on hand loans (sood) | family lending practice | Ruling from 02 owner on whether interest is a verb, a posting rule, or a report-only figure | Advances model (02) — do not hard-code zero interest |
| Encrypted receipt / bill photo on an entry | pilot expectation | Storage cost → likely a paid-tier feature (08) | Optional attachment reference field on entries, encrypted blob outside the envelope |
| Time-boxed read-only accountant role | professional surfaces (02 §10) | Role model in 06 §7 must allow expiring grants | Roles table carries an optional expiry |
| iOS widgets / Siri shortcuts for the 8-second entry | 07 §1 | Widget cannot hold book keys unlocked — design the locked-widget state | Entry sheet reachable by deep link |
| Budgets per book | consumer request pattern | Consumer vocabulary only (rule 9); no new ledger class | Projector stays pure; budgets are a view over balances |

**How to use this table:** when a v1 session surfaces an idea that is not in a milestone row above, add a row here in the same commit and move on. Do not size or sequence rows until M14.
