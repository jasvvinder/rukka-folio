# 10 — Roadmap & Milestones

**Status:** Draft 1. Sliced so each milestone is finishable in a few focused Claude Code sessions, has a demoable output, and exits only through its test gate (09). Order is dependency-driven; durations assume one owner-developer working with Claude Code part-time — treat them as relative sizes, not promises.

| # | Milestone | Contents (spec refs) | Exit gate |
|---|---|---|---|
| M0 | Scaffold | Monorepo, CLAUDE.md, CI, packages: `core_ledger`, `core_crypto`, `data`, `sync`, `app`; lint + test wiring | CI green on hello-world tests |
| M1 | **Ledger core** (pure Dart) | 02: entries, verbs→postings, invariants, amend/reverse, periods/locks logic, advances, inter-book pairs, **partner class + profit distribution + ratio rounding (§7.1)**, **cash counts (§9.1)**, balances math | Suite A incl. property tests |
| M2 | Local persistence & projections | 03 §3: Drift + SQLCipher, projector (pure), balances/snapshots, Recompute determinism | Suite E (client half) |
| M3 | **Crypto core** (pure Dart) | 04: envelopes, key hierarchy, wrap/unwrap, sign/verify chain, fingerprints & code derivation, Shamir (⚠️ 04 §11.1 decision here) | Suite B |
| M4 | Server + sync engine | 03 §2 migrations + RLS, push/pull with `seq` cursors, meta/key channel, outbox (05) | Suites D, E (server half) |
| M5 | **Single-user app** | 07: onboarding cards, Home, 8-second entry, Ledger index + A/C statement, opening balances, basic day-book export — *dogfooding starts here* | Suite F core + stopwatch |
| M6 | Auth & devices | 06: OTP, device keys, sessions, linked-devices screen, recovery sheet + nag, min-version gate | Suite C |
| M7 | Multi-user | Invites, ceremony (QR + code, remote, delegated), roles/limits, approvals inbox (06 §7, 07 §9/§12) | H steps 1–2 |
| M8 | Family money | Advances end-to-end, inter-book transfers, in-transit, Family Reconciliation, pocket-expense flow, **partner positions + distribution wizard + settlement (S14–S14.2)**, **cash count sheet (S5.5)** | H steps 3–6, **H2** |
| M9 | Close | Month-close wizard (resumable, family status S10.1, summary card S10.2), Late Arrivals, year close + FY switcher + certified vectors, **structural quorum flow (S6.3)** | H steps 8–9, **H2b** |
| M10 | Statement import | Parsers (CSV/XLS first, PDF per-bank ⚠️ pick pilot banks), inbox, matching, rules, Suspense (02 §10, 07 §11) | H step 7 |
| M11 | Recovery & escrow | Guardians setup + k-of-n recovery, escrow with veto timer, stolen-phone path | H step 10, Suite B/C recovery tests |
| M12 | ਪੰਜਾਬੀ + हिन्दी & polish | Full PA + HI strings (native review gate, 01), exports with b/d–c/d + amount-in-words, report suite (07 §14) | Suite F full incl. PA+HI overflow |
| M13 | Subscription | Tiers, gateway webhooks, grace/read-only, admin panel (08) | Suite G |
| M14 | Hardening & pilot | Threat-model walkthrough, external crypto review ⚠️ budget, perf budgets on low-end device, DPDP checklist, Play/App Store prep | Suite H full pass; pilot month begins |

**Platform 🔒 (owner ruling):** iOS ships first; the Android build follows from the same codebase at M12+. Store submission, IAP compliance (see 08 §3.2) and TestFlight distribution therefore land in M13–M14.

**Sequencing notes 🔒:** M1–M3 are pure packages — build and test them before any UI or network exists; they are the components that must be boringly correct. Dogfooding starts at M5 with the solo app (your own use case first). The mockup/prototype round the owner planned slots **between now and M5**, refining 07 before UI code. **iOS ships first**; Android follows from the same codebase after M12; AA bank integration, voice entry, more languages, and desktop remain post-v1 per the requirements doc.

**Cross-references 🔒:** brand rules (11) bind every UI milestone · the admin console (12) is M13 · the UX architecture (13) is the screen-level contract for M5 onward and its S-ids are the milestone acceptance vocabulary.

**Working method with Claude Code:** one milestone (or one coherent slice) per session; start by pointing at the exact spec sections; tests from 09 written/green before UI; any decision that changes a 🔒 line lands as a doc PR in the same commit; CLAUDE.md is updated whenever a convention is settled.
