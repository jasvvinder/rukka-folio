# PLAN.md — Rukka Folio build tracker

**Read this file first in every session. It is the only state needed to start** (≈3k tokens).
Legend: ✅ done (tests green on `main`) · 🟡 in progress · ⬜ todo · ⛔ blocked on owner / external.
Rules of the file: a module turns ✅ only when its test ids pass in the push lane; `/plan` refreshes it;
spec authority stays in `docs/` (this file is a tracker, never a spec).

---

## 0. Where we are — 2026-09-13

| Layer | State | Evidence |
|---|---|---|
| `core_ledger` (02) | ✅ M1 | suite A: 111 ids + golden replay of 8 worked-example books (content_hash unchanged since M1) · **`A-09b-4` drawings 12 Sep, `A-09b-5` capital introduced 13 Sep — the mirror pair is complete, 164/164** |
| `data` (03 client) | ✅ M2 | suite E client half: Drift + SQLCipher schema v1, mirror/outbox, Recompute, corruption path |
| `testing/harness` | ✅ M2 | two-client rig; D-05b-2/3/4 |
| `core_crypto` (04) | ✅ M3 | suite B: 75 tests — envelopes, keys, ceremony, wrapping, recovery, signed records, chain, Shamir |
| `sync_engine` (05) | 🟡 M4 | suite D: 17 tests — outbox/push, `seq` cursors, epoch, key-wait, revocation cut-off, k-of-n `D-06a-1…4`, SPKI pins |
| `server/` (03 §2, 05, 06) | ✅ M4 | 5 migrations + RLS + 5 edge functions; **Deno 38 green incl. the 7 hostile-query RLS tests** (`E-03-22…27`, `E-05c-7`) against a real Postgres — `scripts/rls_db.sh`, no Docker |
| `app/` (07, 13) | 🟡 M6 client · M5 near done | theme + router + seams + `features/auth` + `features/devices` (7 screens) · **M5**: `features/onboarding` S0.0…S0.8 — **every purpose card built, S0.6c loop included, so onboarding has no dead end left** · `features/home` S1/S1.1/S1.2/S1.3/S1.4 + S0.7 · `features/ledger` S3/S3.1/S4 + FY switcher/S4.1 · `features/entry` S2/S2.1/S2.2/S2.3/S2.5 · `features/lock` S15/S15.1/S15.3 · `features/settings` S13 · `features/menu` S8 · **`features/reports` S8.1 + S8.2 viewer and day-book export in all three formats — PDF (embedded Mukta/Mukta Mahee), CSV (UTF-8 BOM) and XLSX (in-house, money as numbers, byte-reproducible), now reaching the reader through the platform share sheet rather than a temp path** · `shared/widgets` one banner atom (S12.5 + S15.4 + S19.3). **Push lane green 13 Sep**, app package **492 passed / 0 skipped**. See `.claude/lane-reports/M5-*.json` |

| Traceability | ✅ | `check_coverage --strict` **green** and blocking in `ci.sh`: **727 tests · 468 ids declared · 559 ids named · 345 🔒 lines, 0 unmarked · 0 orphans** (13 Sep). 91 lines carry planned ` @M<n>` markers (ADR 2026-09-08) |

✅ ADR 2026-09-06 ratified 7 Sep (four answers recorded in the ADR; 04 §2/§7.3/§9.2/§11 updated).

⛔ **Owner now, in order:**
1. ✅ **Done 8 Sep — the RLS suite runs.** Docker was never the requirement: the migrations are plain Postgres + `pgcrypto`, so a Homebrew `postgresql@16` serves. `scripts/rls_db.sh` resets the database, applies the 5 migrations and exports `RF_TEST_DB_URL`; nightly/rc set `RLS_REQUIRE=1` so a missing database fails loudly. First run found one real defect (`E-03-26`) — see M4 below.
2. The §4 lead-times — each row names its first action; details in `docs/ops/lead-times.md`.
3. ✅ **Done 13 Sep — the palette is signed off** (ADR 2026-09-13 §2). The status family is ratified at the 12 Sep values, and `tokens.json` is at v0.1.2 with **no `PROPOSED` marker left** — the eight on `sunk`/`pending`/`locked`/`scrim` had been stale since the 5 Sep approval.
4. ✅ **Done 12 Sep — XLSX needs no package.** Evaluated and ruled (ADR 2026-09-12e §1): `excel` and `spreadsheet_decoder` need archive 3.x (compile-verified against 4.0.9 — `ZipDecoder.decodeBuffer` and `ArchiveFile.compress` are gone) while sodium needs 4.x; `syncfusion_flutter_xlsio` fits but is proprietary. Written in-house over `archive` + `xml`. PDF unblocked the same day by pinning `archive` rather than downgrading sodium (ADR 2026-09-12d §1).
5. ✅ **Done 13 Sep — the last three contrast pairs are closed** (ADR 2026-09-13 §2). Light `credit` **#2F7A55 → #2B724F** (on `sunk` 4.30 → 4.79; half the credit→success step, because the full step *is* `success`) and light `text-muted` **#6E6A5E → #696558** (on `sunk` 4.46 → 4.81, on `danger-surface` 4.36 → 4.70). The three `pendingRuling` waivers are **deleted, not relaxed**: `check_contrast` reports **110 gated pairs pass, 0 waived** — clean for the first time.
6. ✅ **Done 8 Sep — traceability debt cleared.** All 198 findings resolved; `ci.sh` now runs `check_coverage --strict --milestone M4`. Four checker defects fixed along the way (object-form `Deno.test` invisible, root `test/` tree not scanned, `n/a` on a heading laundering the whole section, 🔒 mentions counted as rulings). ADR 2026-09-08 adds the ` @M<n>` planned-test marker.
8. ✅ **Done 13 Sep — Share is wired** (ADR 2026-09-13 §1). The shipped sink is `shareReportFile` over `Printing.sharePdf`, which shares all three formats (the iOS plugin names the temp file from our extension — verified in `PrintJob.swift:255`). A successful share gets **no sentence from us** — the sheet is its own confirmation and the platform reports neither completion nor cancellation; if no sheet can be raised the file is written and named, so the export is never a dead end. `ReportSink` returns a sealed `ReportDelivery` for exactly that reason.
9. ✅ **Done 13 Sep — the keying is confirmed and documented** (ADR 2026-09-13 §3). `02 §7.1` now states it: `partner_shares` maps **Partner Current A/c id → whole-number weight**, and an absent or empty map means *not recorded*, never *equal*. The ⚠️ SPEC under ADR 2026-09-09 §2 is closed.
10. ✅ **Done 13 Sep — ADR 2026-09-12e §2 confirmed as written.** The trio (View · Download/Share · Export as PDF/CSV/XLSX) is binding on **both** S4 and S8.2 and `07 §6`'s amendment stands. S4's export surface is still unbuilt, so it lands right the first time.
7. ✅ **Done 13 Sep — capital introduced is `money_in`** (ADR 2026-09-13 §4, `A-09b-5`). Ruled from the behavioural reference: `financial-accounting-standards.md` §4.1 lists **B01 "Owner adds capital" — Dr HDFC · Cr Capital** among the ten ordinary daybook types, beside B11 the drawing, which 09b §3 already ruled `money_out`. The twin defect is fixed the same way — `Verbs.moneyIn` takes the `_role` guard (it accepted **any** `equitySystem` while `checkShape` admitted **none**), `checkShape` admits `openingBalance` by name, and the two verbs stay mirror images. ⬜ **Still open: the 8th S3.1 tile itself** — a UX ruling (create an account, which it cannot, vs open the entry flow with Capital preselected), not an engine one.

---

## 1. The fast path — four phases, parallel lanes

**Principle.** A phase is built one **lane** at a time, not one phase at a time. `/lane` runs one
to three subagents that own **disjoint directories** (so no worktrees, no merge), each tests-first
against named spec sections, each writing a durable report to `.claude/lane-reports/`; then it
**stops**. `/gate` is a separate run, once the phase's lanes have all reported. The tier — and so
the model and effort — comes from `.claude/agents/*.md`, never from the caller (§3). The owner
reviews on a device each evening.

| Phase | Dates | Lanes in parallel | Exit |
|---|---|---|---|
| **A — foundations** | 7–13 Sep | ✅ P0 tooling · ✅ **S** server · ✅ **Y** sync_engine · ✅ **C** auth client → remaining: **U1** app foundation · **U2** entry+home · **U3** ledger+statement | push lane green ✅ (8 Sep, and every gate since); ⬜ app installs on the owner's iPhone; 🟡 solo entries flow end to end **offline** — U1/U2/U3 are built bar the **S0.6c** loop; unverified on a device |
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

### P0 Tooling for parallel lanes ✅ (Phase A, day 1)
- ✅ **ARB parts**: lanes write `app/lib/l10n/parts/<feature>_{en,pa,hi}.arb`; `gen_l10n_arb.dart` merges parts → `app_*.arb` → identifier copies. Removes the one shared file every UI lane would fight over. `check_strings` runs on the merged files.
- ✅ **App theme from tokens**: `app/lib/shared/theme.dart` (light/dark from `tokens.dart`, Mukta/Mukta Mahee, status-colour family, `check_contrast.dart` in ci.sh — 74 gated pairs, 3 waived)
- ✅ **Router skeleton**: `app/lib/shared/router.dart` — four-tab bar + docked ( + ); each feature exports `routes` and U1 wires them at integration
- ✅ **Feature folder convention**: `app/lib/features/<feature>/` + `app/test/features/<feature>/` — one lane per folder
- ✅ **Fake sync/auth seams**: `app/lib/shared/seams/` (`sync_client.dart`, `auth_client.dart`, `key_store.dart`) + `app_scope.dart`
- ✅ `server/` skeleton: `supabase/config.toml`, `migrations/`, `functions/`, `tests/rls/`, `deno.json`

### M4 Server + sync engine 🟡 (suites D, E server) — landed 8 Sep, push lane green
**Lane S — `server/supabase`** (03 §2, §2.5; 05; ADR 05b, 05c)
- ✅ migrations `0001`–`0005`: identity & tenancy · devices/keys/ceremonies · envelope store (`seq bigserial`, `blob_hash`) · billing/audit/ops
- 🟡 RLS written for every table (`0005_rls_and_grants.sql`): `envelopes` is `grant select, insert` to `rf_api` only, `DELETE` to `rf_maintenance` alone (rule 2 ✓); `SET LOCAL` claims; `phone_ct`/`phone_hmac` + KMS, no plaintext number. **Written but not executed** — see the hostile-query row.
- ✅ functions: `sync-push` (idempotent, shape checks, quotas) · `sync-pull` (seq cursors) · `sync-meta` (keys, guardian-set history by `share_set_version`) · `auth-challenge` · `billing-webhook` stub — Deno suite 31 green
- ⛔ `tests/rls` hostile-query suite (`E-03-22`…`E-05c-7`, 7 tests) **written but never run**: needs `RF_TEST_DB_URL` → a Postgres with migrations applied (`supabase db reset`); Docker absent on this machine. `ci.sh` defers it to the nightly lane by design (`ci.sh:62`), so the push lane going green does **not** evidence the policies. **Owner: this is the M4 exit gate.**
- ⬜ ops checklist: India region + PITR + private bucket + orphan sweep
**Lane Y — `packages/sync_engine`** (05 §3–§9; ADR 05b §1–§6) — 17 tests green
- ✅ outbox drain + push · pull with `seq` cursors · `store_epoch` + read-your-writes (`D-05-8`) · key-sync-before-drain + re-seal (`D-05-11`, `D-05-12`)
- ✅ signed records applied to rows · `seq` revocation cut-off (`D-05-3`, `D-05-4`) · **k-of-n counting `D-06a-1…4`** (cut-off moves earlier never later; re-split does not reset) · rate-limit/quota (`D-05-6`) · status surface (`D-05-9`, `D-05-10`)
- ✅ D suite: withheld envelope `D-05-1` · orphan amend `D-05-2` · unsigned revocation `D-05-3` · backdated push `D-05-4` · epoch re-pull `D-05-5` · flood `D-05-6` · `meta_mismatch` `D-05b-1` · lossy two-author convergence `D-05-13` (harness)
- 🟡 hardening: SPKI pins ✅ (`lib/src/spki_pins.dart`) · ⬜ rotation runbook · ⬜ **gitleaks + OSV + `print(` check absent from `ci.sh`** (ADR 2026-09-05)
**Traceability reconciliation ⬜ (new, discovered 8 Sep — blocks M4 exit)**
- ⬜ 185 unmarked 🔒 lines need `⟦tests: …⟧` (or `⟦tests: n/a — reason⟧`); 44 orphan test ids need a marker naming them
- ⬜ 11 markers name ids no test declares — `E-03-25/26/27`, `E-05c-7`, `F1-06a-1`
- ⬜ 2 malformed ids — `E-05-1b`, `E-03-16b` (the `Nb` suffix is not the `A-02-9` shape ADR 2026-09-05i §1 specifies)
- ⬜ 2 tests with no id — `server/supabase/tests/rls/schema.test.ts:215`, `server/supabase/functions/_tests/sync_push.test.ts:97`
- Not a build lane: it spans lane-sync/lane-ui/lane-server territory and is a docs+naming pass. `check_coverage --strict` turns blocking at M4.

### M5 Single-user app ⬜ (suite F1 + stopwatch)
⚠️ **Lanes must be split to ~3 screens each** (~1 where a screen is built from scratch). The 8 Sep run gave
U1/U2/U3 10–16 screens apiece; all three capped mid-read, 418K tokens for one screen. Expect ~10 lanes for M5.
**Splitting is still the first answer** — but a cap is no longer a ceiling to design around: **ADR 2026-09-10**
roughly doubled every tier after U2a died twice on a verification toll and a slow test rather than on
over-scoping. If a lane dies at its cap, read the transcript before raising it again.

**Lane U1 — foundation + onboarding** (`features/onboarding`, `features/lock`, `shared/`)
- ✅ **U1a** S0.0 splash · S0.1 language · S0.05 welcome — ARB trio en/pa/hi (169 keys × 3), `F1-07-39/40/41` green (11 tests with `router_test.dart`), `onboarding_routes.dart` composed into `main.dart` `featureRoutes`. Fixed 3 pre-existing defects: missing `shared/theme.dart` import in S0.0 **and** S0.1 (`RkStatusColors` undefined — a live compile error), 200% text-scale overflow in S0.1. ⬜ `initialLocation` still points at the shell, not the splash — first-launch routing is an owner decision
- ✅ **U1j** S0.5 keeping your books safe · S0.5b recovery sheet (07 §3.1 steps 5–6 🔒, 04 §7.4/§7.6) — `F1-07-71`, `F1-07-72`, `F1-07-73` green (11 tests; `test/features/onboarding` 65/65), push lane green 12 Sep. Routed at the 07 §3.1 position: S0.8 → S0.5 → S0.5b → branch step, both skippable and resumable. S0.5 consumes `features/devices`' `DevicesRepository`/`BackupSetting` read-only. S0.5b renders **no** key material — no QR, no Base32, no PDF preview (04 §7.4 specifies a *printed* document and 07 §5.6 blocks screenshots); its three actions are disabled until a recovery module exists. See `.claude/lane-reports/M5-U1j.json`
- ✅ **U1b** S0.3 purpose cards · S0.4 name/photo — `F1-07-16`, `F1-07-48` green (19/19 in `test/features/onboarding`). S0.3 lays the five purpose cards 2×2 with the trust card full width beneath (07 §3.1.1); trust alone sets `tenant.type = organization`. S0.4 keeps Continue disabled-with-reason until a name is typed (13 §4.3) and takes the photo through a callback seam, no plugin. Both assert EN/PA/HI at 200% on 360×800. See `.claude/lane-reports/M5-U1b.json`
- ✅ **U1c** S0.6a business name · **S0.6a1** owners + share weights (ADR 2026-09-09 §1–3) · S0.6b grouped opening balances (ADR 2026-09-09c §3, 09d) — `F1-07-51`, `F1-07-45`, `F1-13-15`, `F1-09c-1` green (22 tests in `s0_6_business_screens_test.dart`; app package 173/173), push lane green 10 Sep. Built from the ADR text and 13 §3.2 rows — no artboard for any of the three yet. Share percentages are integer arithmetic on the weights, displayed only. `createBook` gained the shared-business seed (Profit Distributed + one `{Name} — Partner Current A/c` per owner). Ran on `lane-ui-hard`, correctly: owner rows with weight steppers and a grouped balancing screen are new components. See `.claude/lane-reports/M5-U1c.json`
- ✅ **U4d** share weights **and** `TrustType` now persist — `E-03-30`, `E-03-31`, `F1-07-86` green (packages/data 37; onboarding + shared 204). `BookConfig` gains `partnerShares` (`Map<accountId,int>`, wire `partner_shares`) and `organizationSubtype`; both absent on older books and read back empty/null, the ADR-09b `ownership` precedent. `createBook` mints the Partner Current A/c ids **before** authoring `book_config`, so one envelope carries the whole ratio — no amend, no second write. Round-trip 🔒 held: a value this build cannot interpret stays in `extra` verbatim, and the subtype lookup never uses `values.byName`. ✅ **keying documented 13 Sep** — `02 §7.1` states it and an empty map means *not recorded*, never *equal* (ADR 2026-09-13 §3). See `.claude/lane-reports/M5-U4d.json`
- ✅ **`A-09c-1` seed test** — landed by U1f with `A-09c-2` and `A-09d-2`: `createBook` seeds the per-type money account (Cash / Business Cash / Joint Cash / Cash + Gollak as `cash_collection`), **never a bank in any type** (ADR 09d §1), plus the trust's four category accounts. New `SeedCategory` value type carries a caller-supplied tree
- ✅ **S0.6b wiring** — closed by U1f: `OnboardingFlow` holds the S0.6a1 owners, the book is created from them and the seeded chart passed in; S0.4's name is carried forward
- ⬜ Design app: place S0.6a1 in Canvas 1's five-path branch (ADR 2026-09-09) and the five S0.6b variants from `partials/new-screens-d.json` (ADR 2026-09-09c) — none placed yet
- ✅ **U1d** S0.6d name the family · S0.6e who else is in it (invite by phone, *Skip for now* 🔒 always visible) · S0.6f the family's shared accounts — `F1-07-74`, `F1-07-75`, `F1-07-76` green. Reuses S0.6b's `OpeningRow`/`OpeningGroup`/`parseRupeesToPaise`/`signOf` rather than redefining them; no owner-contributions group, the pool is not a partnership (ADR 2026-09-09c §2). Wired at the O3 branch, every step skippable and resumable. `local_ledger.dart` needed no change — `BookType.family` already seeds Joint Cash + Opening Balance/Capital, no bank (ADR 09d §1). See `.claude/lane-reports/M5-U1d.json`
- ✅ **U1e** S0.6g name the trust and its type · S0.6h who runs it · S0.6i the trust's accounts — `F1-07-80`, `F1-07-81`, `F1-07-82` green (17 tests; `test/features/onboarding` 98), push lane green 12 Sep with only `dart format` on the *other* lane's files. **The last unbuilt purpose card: picking *Our trust* on S0.3 no longer dead-ends.** Built on the settled S0.6d/e/f pattern, adding one backward-compatible field (`OpeningRow.isCollection`) so the gollak's `cash_collection` note renders distinctly from the plain Cash A/c row. Trust seeding was read, never edited — U1f's Cash + Gollak + the four 07 §3.1 step 3 🔒 category accounts all appear in the `F1-07-82` host test. See `.claude/lane-reports/M5-U1e.json`
- ✅ **U1k** S0.6c *Add another business?* — `F1-07-83` green (`test/features/onboarding` 106; the 98 existing tests needed **no edit at all**). `OnboardingFlow` now holds `List<BusinessEntry>` with the single-business accessors delegating to the entry being collected, so S0.6a/S0.6a1/`BusinessOpeningHost` and `createBook`'s contract are untouched; `addAnotherBusiness()` moves the cursor so the loop's S0.6a opens blank and creates a **second book**. Only *My businesses* reaches the loop — checked against 07 §3.1.1's table, not assumed. **Onboarding has no dead end left.** See `.claude/lane-reports/M5-U1k.json`
- ⬜ **`TrustType` has nowhere to persist** (from U1e, ⚠️ SPEC): gurudwara · temple · society · registered trust is held on `OnboardingFlow` and never reaches `createBook`. **Same gap as the share weights above** — `BookConfig` carries no organization-subtype field either. One `packages/data` envelope-schema change closes both rows
- ✅ **U1f** S0.6 opening balances wizard · S0.7 setup checklist · the `createBook` seed — `A-09c-1`, `A-09c-2`, `A-09d-2`, `F1-09c-1`, `F1-07-57`, `F1-02-2`, `F1-02-9`, `F1-03-3`, `F1-07-50` green (app package 237). ⚠️ The household / shop / farm category trees are **drafted but unratified** (`docs/reference/seed-category-trees.md` is EN-only and says it is not shippable), so only the trust — whose four names 07 §3.1 step 3 🔒 fixes — seeds categories; every other type seeds none unless the caller passes `categories:`. Owner must ratify the trees plus PA/HI native review. See `.claude/lane-reports/M5-U1f.json`
- ✅ **Capital/Drawings pair** (ADR 2026-09-09b, ADR 2026-09-13 §4) — **complete, and it never needed fable**. `A-09b-1`–`A-09b-4` landed 12 Sep (no `SystemRole.capital` was added: Capital *is* Opening Balance, as both worked examples name it). `A-09b-5` landed 13 Sep on opus and closed the mirror: capital introduced is `money_in`, `Dr money · Cr Opening Balance/Capital`, and `Verbs.moneyIn`'s over-broad `equitySystem` slot — which `checkShape` refused outright — is now a `_role` guard. core_ledger 164/164
- ✅ **U1g** S0.8 set PIN · S15 app lock · S15.1 privacy cover · S15.3 cooldown states — `F1-07-19`, `F1-07-62`, `F1-07-63`, `F1-07-64` green (21 new tests; 69 across `test/features/{lock,onboarding}`). Built on the existing `features/devices/pin_vault.dart`, so the 5-free / 30 s / 1 m / 5 m / 15 m / 1 h / disabled ladder cannot drift between vault and UI. New ARB part `lock_{en,pa,hi}`. Not built, by brief: S15.4, S15.2, the platform capture block (07 §5.6 🔒). See `.claude/lane-reports/M5-U1g.json`
- ✅ **U1h** shell wiring — the three lanes above each reported screens that nothing mounted; this closes it. `F1-07-68`, `F1-07-69`, `F1-07-70` green. `main()` builds `PinVault(keys, suite, DateTime.now)` **at the mount point** (`RkScope` unchanged, no `CryptoSuite` added) and mounts `LockScope` + `lockRoutes` on the **root** navigator, `PrivacyCover` inside `MaterialApp.builder`, `RkAutoLock` above the app. Cold start with a PIN set pushes `/lock`; unlock pops back to the exact route. Timers read live `AppSettings` (5 min idle / 2 min background) which S13 now displays. Locale/appearance persist across restart through a new `RkPrefs` seam over the existing `KeyStore` (no new pubspec dependency). Scope persists per tab and defaults to last used. `BiometricGate` now defaults to **unavailable** rather than success, so a real build is never waved through — MPIN carries the unlock. See `.claude/lane-reports/M5-U1h.json`
- ✅ **U1i** S13 settings — `F1-07-29`, `F1-07-65`, `F1-07-66`, `F1-07-67` green. 07 §16 row order; Language and Appearance are working controls (locale sheet; icon-only three-way `SegmentedButton` to avoid 200 %-scale overflow), everything else disabled-with-reason. U1h supplied the real locale/theme state and live auto-lock values. See `.claude/lane-reports/M5-U1i.json`
- ⬜ S19.3 no-connection · S19.5 modified-device notice
**Lane U2 — Home + the 8-second entry** (`features/home`, `features/entry`)
- ✅ **U2a** S1 Home/Position · S1.1 drill-down — `F1-07-49` (8/8) and `F1-07-50` (12 cases) green; `homeRoot` wired into `main.dart` mirroring `ledgerTabRoot`, shell tests 10/10. Killed two runs at the cap on a real defect, since fixed: `_combine`'s `onCancel` in `home_data.dart` awaited each Drift subscription's cancel, so widget disposal awaited a future that never completes inside `flutter_test`'s fake-async zone — teardown deadlocked for the full 10-minute timeout, and `--timeout` does **not** cut it short. See `.claude/lane-reports/M5-U2a.json`
- ✅ **U2b** S1.2 two-chip inline toggle · S1.3 grouped bottom sheet (empty groups omitted; never shown at exactly two books) · *Everything* read-only book cards · S1.4 determinate rebuild loader ("{done} of {total} entries restored", 2 px rule, no spinner) gated back to the normal card on `BookHealth.integrityOk` — `F1-07-52`, `F1-07-53`, `F1-07-38` green (10 tests in `s1_scope_switcher_test.dart`; `test/features/home` 30/30; app 183), push lane green 10 Sep 15:59 with nothing mechanical to fix. 07 §28's `F1-07-38` marker lost its `@M5`. Stream combinators cancel synchronously (unawaited), per the U2a teardown-deadlock finding. See `.claude/lane-reports/M5-U2b.json`
- ✅ **Scope persists per tab** — closed by U1h: `AppSettings.scopeOf/setScope` stores a `Scope` for all four tabs and defaults to last used. Only Home has a scope control today, so only Home's `HomeScopeController` is seeded in `main()`. ⬜ `main()` builds its own Home `RkTabRoot` so it can pass `scopeController:`; `features/home`'s `homeRoot` is the same screen without it — **the two wirings must change together** (comment at the call site)
- ✅ **U2f** the rebuild-progress producer — `E-03-29` minted, `F1-07-38` extended. `Recompute.watchProgress(bookId)` is a re-listenable `Stream.multi` that replays the reading in hand, so a rebuild started before Home mounted is still visible; `total` counts `entry` envelopes off the plaintext `object_type` column (determinate before any payload opens) and `done` ticks in a `try/finally`, so quarantined, corrupt and thrown rows all count and `done` always reaches `total`. `homeRoot` and `main()` both pass it, so `rebuildProgress` is no longer null. ⬜ **`local_ledger._rebuild` runs a FULL Recompute after every post** — hence the 200 ms appear delay; on a large book S1.4 will still flash after an entry, and it wants incremental re-projection or a `RecomputeReason`. ⬜ none of 07 §28's three triggers is wired. See `.claude/lane-reports/M5-U2f.json`
- ⬜ S1.1's bank drill-down app-bar title falls back to `home.position.title` ("Position") — `positionLineLabel()` has no per-account label for `PositionLine.bank`. Design nit, asserted as-built
- ✅ **U2c** S2 keypad-first entry · S2.1 A/C picker swapped in place + inline create with the class inferred from the slot · S2.3 *Move money* at the pill's fifth position (ADR 2026-09-03b) — `F1-07-17`, `F1-07-54`, `F1-07-55`, `F1-07-56` green (19/19 in `test/features/entry`; app package 202/202), push lane green 10 Sep with only `dart format` to fix. `entryScreen` wired into `main.dart` as `entryRoot`, so the ( + ) opens the real screen. Two real defects found and fixed: `_ClassQuestion` overflowed its 78 pt region by 62 px (now scrolls inside the picker; the entry screen itself still never scrolls), and the 200 % / 375×667 *Move money* overflow (chrome tightens at `textScale ≥ 1.5`). Amount arithmetic is integer paise (string `+` quick-sum and `.` paise). See `.claude/lane-reports/M5-U2c.json`
- ⛔ **07 §5 🔒 "never scrolls" vs 200 % text scale — owner call** (⚠️ SPEC in `s2_add_entry_screen.dart`): on the *Move money* verb at 375×667 and 200 %, the two chip rows leave the keypad ~30 px — present and correct, unusable. U2c took the conservative reading (no-scroll stands, chrome tightens at scale ≥ 1.5). Owner picks one: the transfer verb shows one chip row at a time at large scale, or the lower region gets a floor and 07 §5 gains a large-text exception. Design canvas 2, S2 / S2.3
- ✅ **U2d** S2.2 date chip → calendar · S2.5 drawings confirmation — `F1-07-58`, `F1-07-59` green (F1-07-59 was 3 of 4, the 4th skipped on an engine blocker — **cleared by U2d-engine below, now 4 of 4**), push lane green 12 Sep. Took three runs; the first two died on a **fixture** bug, not a screen defect: `_pick` used `find.text(name).last`, but once the query is typed the search field's own `EditableText` carries that exact string, so `.last` tapped the search box and left the slot unanswered. Two real 200 % defects fixed along the way: the picker's create row wrapped to three lines and squeezed the account list to a ~20 pt strip, and the S2.5 banner overflowed the body by ~90 pt (now `Flexible` + internally scrollable, the precedent the picker's own list already set). See `.claude/lane-reports/M5-U2d.json`
- ✅ **U2d-engine** (escalation, `lane-core`) — the `core_ledger` drawings blocker U2d raised. `Verbs.moneyOut` built `Dr equitySystem · Cr money` but `checkShape` admitted only `expense|party|advance` debits, so the posting 07 §5 line 158 🔒 and ADR 2026-09-09b §3 mandate was rejected `shapeViolation`. Fixed on **both** sides: `checkShape` now admits `isDrawings` (equitySystem **+** `SystemRole.drawings`) only, and the verb routes an equitySystem `forWhat` through the same `_role` guard — a verb looser than its reader was the bug (ADR 05e §6). **`A-09b-4`** minted (its ` @M5` marker dropped at `02:182` and ADR 2026-09-09b §3), **`F1-07-59`** un-skipped; `core_ledger` 159/159, golden replay content_hash unchanged, no green test asserted the old rejection so nothing needed `@Skip`. No 🔒 line changed — the engine was brought into compliance with rulings that already existed, so no ADR. Push lane green 12 Sep, nothing mechanical to fix. The lane's own verdict: **it did not need the fable tier** — an opus lane with `core_ledger` in its directory set would have landed the same ten lines. See `.claude/lane-reports/M5-U2d-engine.json`
- ⛔ **🔒 ENGINE BLOCKER — `core_ledger` contradicts itself on the drawings posting 07 §5 🔒 mandates.** `Verbs.moneyOut` accepts `AccountClass.equitySystem` for `forWhat` (`packages/core_ledger/lib/src/verbs.dart:43-47`), but `checkShape` restricts money_out debits to expense|party|advance (`packages/core_ledger/lib/src/invariants.dart:208-210`), so Money out → Drawings is rejected `shapeViolation: money_out: Dr equitySystem · Cr money` and S2 shows its save-error snackbar. Verified by calling `ledger.moneyOut` directly against a `SystemRole.drawings` account. Likely fix: allow an `equitySystem` debit whose `systemRole` is `drawings`. One `F1-07-59` test is `@Skip` with that reason inline — un-skip with the engine change. `lane-core` work; ⛔ **fable is 5/2 over budget**, so it waits for the Sunday reset (13 Sep) or the owner's say-so — it pairs naturally with the parked ADR 2026-09-09b Capital/Drawings run
- ✅ **U2e** the shell's draft seam + the F1 8-second proxy — `C-05a-7`, `F1-07-13` green. `AddEntryScreen` funnels every amount change through `_setAmount()`, reporting into `DraftActivityScope` and clearing its token in `dispose`; `C-05a-7` mounts the real screen under a real `RkAutoLock` and proves the idle lock never fires with a digit in the keypad, fires once it is cleared, and that the screen's own state survives a lock/unlock cycle. `F1-07-13` is the **F1 proxy only** — shortest Money in entry reaches Save in ≤ 8 taps; the wall-clock stopwatch stays F2's at RC. See `.claude/lane-reports/M5-U2e.json`
- ⬜ stopwatch ≤ 8 s on the **device lab at RC** (F2; the F1 tap-count proxy landed as `F1-07-13`) · Money in / Money out vocabulary only (rule 9)
**Lane U3 — Ledger + statement + export** (`features/ledger`, `features/reports`)
- ✅ **U3a** — S3 index · S3.1 quick-add sheet · S4 A/C statement, `F1-07-42/43/44` **19/19 green**, `ci.sh` green on the push lane (9 Sep). Sticky alphabet rail landed; 07 §6 marker carries all three ids. Open, both ⚠️ SPEC in-file: the 8th (Capital) quick-add tile is an owner call, and S4 has no FY switcher (`watchStatement()` takes no date range). See `.claude/lane-reports/M5-U3a.json`
- ✅ **U3b** S4.1 entry detail + amend/reverse — `F1-07-60`, `F1-07-61` green (9 tests; `test/features/ledger` 28/28). `entry_detail.dart` resolves an id to **posted / held / missing** and loads the whole correction chain. Consumer vocabulary only (a test asserts every `MoneyText` is `Vocabulary.consumer` and that Dr/Cr never appear). Held renders as *waiting* — hourglass chip, muted ink, no error wording, no retry, no amount. Amend and Reverse are guided sheets, never a freeform journal; a locked period is caught as `PostRejected(amendInLockedPeriod)` and offers *Fix an old entry* (02 §5). See `.claude/lane-reports/M5-U3b.json`
- ✅ **U3d** FY switcher + the real b/f on S4 · the two facade gaps — `F1-07-46` landed (its ` @M5` dropped from all six markers), `F1-07-60`/`F1-07-61` extended rather than minting a new id. `watchStatement(accountId, {from, to})` now returns a `Statement` carrying opening/closing paise, so S4 loses its hard-coded 0 b/f and its *as on today* c/f; **b/f is computed** by summing the account's lines before `from` (ADR §4: correct for a continuous ledger until S10.4 certifies it in M9). No `packages/data` change was needed — `books_p` already carries `fy_start_month`. Push lane green 12 Sep. See `.claude/lane-reports/M5-U3d.json`
- ⬜ **S21 search** — still deferred out of U3b; the FY switcher half of that row is done
- ⬜ **The FY chip is dormant by design**: ADR §4 🔒 says there is no switcher before the first year close, so `ClosedYearsSource` (`features/ledger/widgets/fy_switcher.dart`) defaults to none and shipped behaviour is plain muted text. The chip, the bottom sheet and the *Certified* badge are proven from a fake. **M9 (S10.4) must wire the certified years and swap the computed b/f for 02 §8.1's opening vector.** The ADR's second surface, S8.2, is untouched
- ⬜ **ADR 2026-09-09 §4 Consequences still owed in `docs/`**: a `13 §3.2` inventory row for the switcher and cross-reference lines at `07 §5.7` / `07 §6`. U3d was held to the `F1-07-46` marker edits, so these are unwritten
- ✅ **`shared/ledger/local_ledger.dart` gaps closed** (U3d): `heldFor(objectId) -> HeldObject?` and `reversalOf(entryId) -> String?` are on the facade, and `entry_detail.dart` no longer imports drift or touches a Drift table — S4.1's posted/held/missing behaviour unchanged
- ⬜ **⚠️ SPEC (U3b, comment in `s4_1_entry_detail_screen.dart`)**: 13 §3.2 puts the bill photo on S4.1 and 07 §25 opens S20 from it, but `entries_p` does not project `attachment_ids` and `EntryView` does not carry them, so the photo section can only ever render its empty state. Wanted: `EntryView.attachmentIds` + the projection column. Conservative reading taken — the section says *No bill photo on this entry*; no attachment behaviour invented
- ✅ **U3c** S8 Menu · S8.1 Reports list — `F1-07-14`, `F1-07-77`, `F1-07-28` green (14 tests; app package 320 passed / 1 skipped), push lane green 12 Sep with nothing mechanical to fix. **Menu is now the fourth tab**: `RukkaFolioApp` gained `menuTabRoot` and `main()` passes `menuRoot`, so S8 replaces `RkPlaceholderScreen` and `/menu/reports` opens S8.1 with the tab bar still visible (13 §3.2 depth rule). Menu rows in 07 §2 🔒 order, Reports rows in 07 §14 🔒 order; the four rows with a destination today (Reports, Backup, Devices & security, Settings) push it, every other row is disabled-with-reason. Finished **inline by the orchestrator** — the killed run's remainder was minutes, under the ~30-minute floor for spawning a lane. Two defects it left, both fixed: `s8_menu_screen.dart` was mid-conversion to `SingleChildScrollView`+`Column` and lost one `)` (never truncated in content, only unbalanced — which is why it read as complete at 108 lines), and S8.1 kept a lazy `ListView`, so rows 9–11 never built in the test viewport and *both* S8.1 reds were that, not missing list content. Both now take the non-lazy shape S13 (07 §16) already uses. See `.claude/lane-reports/M5-U3c.json`
- ✅ **U3e · U3g · U3h · U3i** S8.2 report viewer + **day-book export in all three formats** — `F1-07-79` (its ` @M5` dropped from all three markers), `F1-07-28`. Viewer: day book per FY, Dr|Cr columns, cross-check footer, skeleton/empty/error, rows through to S4.1. **PDF** via `pdf`+`printing`, A4, Mukta/Mukta Mahee embedded — `unsupportedRunes()` asserted empty over a Gurmukhi/Devanagari day book, so a Punjabi PDF is proven to carry glyphs rather than boxes; `maxPages` raised off the package default of 20 so a busy year is not silently truncated. **CSV** pure Dart, UTF-8 BOM (now asserted). **XLSX** in-house over `archive`+`xml` — money as **number** cells in a money style (never text, so it sums), dates as Excel serials, zip stamped 1980-01-01 so the same book exports **byte for byte** the same file, which is what makes the M12 goldens possible. Primary action defaults to PDF; *Choose a format* opens the sheet; **no row is disabled any more**. ✅ **Share wired 13 Sep** (ADR 2026-09-13 §1): the shipped sink is `shareReportFile` over `Printing.sharePdf`, which carries all three formats — the iOS plugin names its temp file from the extension we pass (`PrintJob.swift:255`). A share raises the sheet and we say nothing; if no sheet can be raised the file is written and named, so the export is never a dead end. `ReportSink` returns a sealed `ReportDelivery` rather than a string, because only the sink knows which of the two happened. See `.claude/lane-reports/M5-U3{e,g,h,i}.json`
- ✅ **S12.5** read-only / book-full sheet pattern — `F1-07-78` green (18 tests: banner + sheet, 200 % at 375×667 **and** 360×800, en/pa/hi; app package 338 passed / 1 skipped), push lane green 12 Sep with nothing mechanical to fix. Built by `lane-ui-hard` as one injected pair in `app/lib/shared/widgets/` — `RkRestrictionKind {readOnly, offlineGrace, bookFull}` with `blocksExport` **false always** (07 §20), `RkRestrictionBanner`, and `RkBlockedEntrySheet` as a modal route that holds no draft, which is how the 🔒 *draft preserved* line is honoured and what the test proves. The two graces are written apart so the offline variant never borrows a lapse string (13 §5). **Not wired to S2 and correctly so** — no entitlement or quota source exists; the signal lands with sync. See `.claude/lane-reports/M5-S12.5.json`
- ✅ **Token session — the status family landed 12 Sep** (ADR 2026-09-05f §H, executed): `success`/`warning`/`info`/`danger`/`on-danger`/`focus-on-primary` now carry values in `tokens.json` (v0.1.1) for both modes, every one measured by `scripts/check_contrast.dart` — **gated pairs 74 → 110, all pass**. `danger` is deliberately not `debit` (a security warning must never read as money out) and `info` not `primary` (separated by hue). `RkStatusColors` gained the six fields; `RkRestrictionBanner` now tints semantically and both ⚠️ SPEC notes are gone. Purely additive — no existing token value changed. ⛔ **owner sign-off on the hexes**, the 5 Sep pattern (`pending`/`locked` were proposed in code, then ratified)
- ⬜ **Banner still undrawn on canvas** — `design-system.md:111`, one of seven queued components. Code exists (`RkRestrictionBanner`); reconcile against `DESIGN-PACK.md:511` §11 S12.5 *"a persistent slim banner, not a modal"* when it is drawn
- ✅ **SW1** one banner atom — `F1-07-85` minted; `F1-07-78`/`F1-06-15`/`F1-06-16` kept green. New `RkBannerSurface` (13 §4.2) backs both `RkRestrictionBanner` and the new **S19.3 No connection** notice; the duplicate `SuspendedBanner` is gone and `RkRestrictionKind` gained `suspended`. S19.3 shares the atom but **not** the restriction family (13 §4.2 enumerates three kinds and S19.3 is not among them), so it can never reach `offlineGrace`'s copy — the separation 13 §5 requires, and what `F1-07-85` proves. ⬜ not mounted: nothing produces a connectivity signal until sync. See `.claude/lane-reports/M5-SW1.json`
- ⬜ **`scripts/check_contrast.dart` still not in `ci.sh`** (`design-system.md:108`). It exits 0 today, so wiring it is safe, but it was left out of the token session to keep that change additive
- ⬜ **Three contrast pairs still await an owner ruling** (pre-existing, unchanged): light `credit` on `sunk` 4.30, light `text-muted` on `sunk` 4.46 and on `danger-surface` 4.36. `credit`'s darkening is already 🔒-ruled in §3.1 and only wants a hex
- ⬜ **⚠️ SPEC (U3c, comment in `s8_menu_screen.dart`)**: 07 §3.1 step 6 puts a verified-storage nag badge on Menu until the printed recovery sheet is scanned back, but no persisted *sheet verified* flag exists anywhere the shell can read — `features/onboarding`'s S0.5b keeps that state to itself. Badge left **off** rather than invented (rule 11). Wanted: a flag on `AppSettings` (or the `KeyStore`) that S0.5b writes and S8 reads
- ⬜ **Housekeeping, pre-existing, surfaced by U3c**: 37 test files carry `@Tags(['F1'])` but the app package has no `dart_test.yaml` declaring the tag, so every run prints *"A tag was used that wasn't specified"*. Harmless today; 09's four-lane split wants the declaration once lanes are actually selected by tag
- ✅ **T1** the test harness could not see the screen — `pumpRk` gained `textScale:`/`viewport:` and rejects a zero-sized MediaQuery. Tests wrapped screens in a bare `MediaQueryData(textScaler:)`, whose `size` is `Size.zero`, so any widget budgeting against `MediaQuery.sizeOf` collapsed to nothing and `findsOneWidget` still passed. **Six real defects had been hiding behind that**, all found by measuring: the S1 hero total cut (398 px needed in 328 at 1×, 794 at 2×), `RkLabelAmountRow` splitting 50/50 so `+₹1,14,600` lost digits across S1/S1.1/S1.2/S1.3/S0.7 in all three languages, the HI rebuild line, `RkRuledCard`'s `IntrinsicHeight`, S8.2's *Particulars* heading clipped at **1×**, and S8.1 cutting a report name at 200 %. New `expectTextFits` fails on font-measured cut text. `rkPhones`/`rkLocales`/`rkTextScales` are the shared vocabulary. See `.claude/lane-reports/M5-T1.json`
- ⬜ **20 test files still wrap a bare `MediaQueryData`** and warn (`RK-HARNESS ZERO-SIZED SCREEN`) rather than fail: `features/{auth,ledger,lock,menu,onboarding,settings}` and `test/shared`. Converting is mechanical — drop the wrapper, pass `textScale:`/`viewport:` — but **expect real layout defects to surface**, as they have in every lane so far. When the last one lands, set `rkStrictViewport = true` so the old pattern can never return
- ⬜ **`RkFitText` is in the wrong place** — it lives in `features/home/widgets/home_states.dart` because home was all T1 owned, but every screen in PA/HI at 200 % has the same failure mode. Move to `app/lib/shared/` and adopt app-wide
- ⬜ **S4's export surface** (ADR 2026-09-12e §2) — S4 gains View · Download/Share · Export as PDF/CSV/XLSX. Needs a **statement** report, not a day book; `features/ledger` lane. Blocked only on §0 owner row 10 confirming the reading
- ⬜ **Export-sheet copy** (U3i): with all three rows live, *"Opens in any spreadsheet"* (CSV) and *"A spreadsheet file"* (XLSX) no longer say why to pick one. XLSX's point is that figures arrive as numbers that add up. PA/HI here are real translations, so this is a copy decision, not a lane's guess
- ⬜ **XLSX money format is neutral `#,##0.00`, not Indian `#,##,##0.00`** (⚠️ SPEC in `xlsx_report.dart`) — display only, never the value; 07 §14's content rules are M12
- ⬜ A-02-10 both vocabularies render from one posting set

### M6 Auth & devices 🟡 (suite C) — client half landed 8 Sep, 37 tests green
**Lane C — `features/auth`, `features/devices`** (06; ADR 05d) — client side in Phase A against fakes, real server in Phase B
- ✅ S0.2 phone + OTP (`s0_2_phone_otp_screen.dart`) · device keys in Keychain (`keychain_key_store.dart`) · sessions (`http_auth_client.dart`) · min-version gate S19.1 (`s19_1_update_required_screen.dart`) · `C-06-1…13`
- ✅ S11 devices & security · S11.4 backup settings · S11.9/S11.10 cancel windows (24 h, `cancel_window.dart` + `s11_9_10_cancel_window_screen.dart`) · S15.4 suspended · S19.5 modified-device · `F1-06-1…16`
- ✅ at-rest + PIN vault (`at_rest.dart`, `pin_vault.dart`) · `C-05d-1…10`
- ⬜ OTP-only device sees no tenant metadata (needs the real server — Phase B)
- ⬜ biometric-set binding · MPIN lockout surviving app-data clearance · certified-only RLS (server side, lane S — blocked on the same unrun RLS suite)

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

Restructured 8 Sep 2026 after `wf_16e00993` died on the session limit with three high-effort Fable
lanes in flight: 725K tokens, two lanes' work on disk and their reports lost. The rules below make
that failure cheap instead of preventing nothing.

1. **Check the budget first:** `.claude/bin/wf-spend.sh`. Fable 5.1 resets **Sunday**; that reset is
   the budget. Two fable runs a week, and only by escalation (item 5).
2. **One lane per session** where the work allows; `/lane` caps a run at **3** and refuses more.
   `/gate` is always its own invocation. A limit hit then costs one lane, never a phase.
3. **Start:** read `PLAN.md` §0 + the rows for this lane only. Not CHANGELOG, not whole specs.
4. **Read specs by section:** `grep -n "^## \|^### " docs/<n>.md` → `sed -n 'a,bp'`. A lane reads only
   the sections its PLAN row names.
5. **Tiers are structural.** Pick a lane by naming an agent; model and effort come from its file:

   | Agent | Model · effort · turns | For |
   |---|---|---|
   | `lane-mech` | haiku · low · 60 | ARB drafts, l10n parts, fixtures, codegen, token regen |
   | `lane-ui` | opus · medium · 180 | **repeat** screens by S-id (13 §3.2) on a settled pattern, F1 widget tests |
   | `lane-ui-hard` | opus · high · 180 | new components, foundation (theme/shell/nav), 200 % · 360×800 defects, state-machine screens |
   | `lane-server` | opus · high · 180 | migrations + RLS, edge functions, hostile-query tests |
   | `lane-sync` | opus · high · 220 | `sync_engine`, ordering/conflict/trust logic, projector |
   | `lane-core` | **fable · high** · 240 | ⚠️ escalation only — `core_*` behaviour, 🔒/ADR reasoning, suite-A goldens |

   Current as of **ADR 2026-09-12b** (this table was three ADRs stale: it still read sonnet for
   `lane-server`, had no `lane-ui-hard` row, and carried the pre-10 Sep caps). `CLAUDE.md`
   § Session economy is the copy that governs; keep the two in step.

   **No lane starts on `lane-core`.** It is entered only when a lower tier reported a blocker it
   could not resolve, and only with the owner's say-so. Never pass `model`/`effort` in lane args —
   that is exactly how the whole of Phase A's first week went to Fable by accident.

   Build lanes **and the gate** run `permissionMode: acceptEdits` so a run never stalls on an edit prompt. The
   trade: the permission prompt was the only thing actually enforcing the directory split, so the
   lane prompt now carries that job alone (item 6).
6. **Orchestrate, don't implement, in the main session.** The orchestrator holds PLAN rows and lane
   reports; lanes return structured JSON, not prose.
7. **Reports are durable.** A lane writes `.claude/lane-reports/<milestone>-<key>.json` as soon as it
   has anything to record and keeps it current, flagging `complete: false` until the task is wholly
   done. `/lane` skips only complete reports and re-runs the rest, feeding each its own `notes`. Every
   lane carries a `maxTurns` cap (15–60 by tier), so an interrupted run loses the run, not the work —
   and a partial report is a normal outcome, not a fault. Work that will not fit a cap gets split.
8. **The post-edit hook already formats/analyzes/purity-checks.** Lanes never re-run those by hand
   and **never run `ci.sh`**; the `gate` agent runs it once per phase and greps its log to a file so
   the log never enters anyone's context.
9. **Tests by file during a lane** (`dart test test/x_test.dart`), full package once at lane end.
   Goldens once per phase (`/goldens`).
10. **No re-reading after edits** — the harness tracks file state. No verification loops beyond one
    gate + one fix pass.
11. **End with `/close`:** `/plan` (✅ from green ids) → `/changelog` → commit message for the owner
    → **`/clear`**. Never chain the next lane onto a finished one; a fresh session is the cheapest
    session, because context is resent in full every turn.
12. **Never** spawn a lane for something a `grep` answers; never fan out on a task under ~30 minutes.

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
