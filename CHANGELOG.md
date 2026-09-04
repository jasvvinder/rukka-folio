# Changelog — Rukka Folio

Running record of what changed in this repository and in the development environment, one entry per working session. Newest first. Kept by hand at the end of every session, before the owner commits; the commit hash is filled in afterwards.

**How to write an entry**

- Heading: `## YYYY-MM-DD — <milestone or slice>` (use `env` for toolchain/environment work, `docs` for spec-only sessions).
- Sections, each optional: **Added**, **Changed**, **Decided** (link the ADR in `docs/decisions/`), **Open** (⚠️ items handed to the owner), **Commits** (hashes once committed).
- Record *what* and *why*, not the diff — git holds the diff. One line per item.
- A 🔒 change is never recorded here alone; it needs an ADR in the same commit.
- No financial data, keys or secrets — this file is committed.

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
- _pending_

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
- _pending_

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
