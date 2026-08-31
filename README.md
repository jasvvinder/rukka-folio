# Rukka Folio — Specification Package

Zero-knowledge, offline-first ledger app for individuals, joint families, and their businesses (and trusts). India, English + ਪੰਜਾਬੀ + हिन्दी. Full double-entry underneath, a rokad-vahi on top. No invoicing, no GST, no taxation — recording what the family actually has.

**Drafted:** 28 Aug 2026 · **Status:** Draft 1 — ready for mockup/prototype validation, then build.

## Reading order

| For… | Read |
|---|---|
| The idea in 2 minutes | `docs/00-vision.md` |
| Background & original reasoning (⛔ **non-normative** — loses every conflict with 00–12; see its banner) | `docs/requirements-architecture.md` |
| The domain (verbs, postings, close, year carry-forward) | `docs/02-ledger-rules.md` |
| Security & recovery (guardians, QR ceremony, escrow) | `docs/04-crypto.md` + `docs/06-auth-devices.md` |
| Screens & flows | `docs/07-ui-flows.md` (strings: `docs/01-glossary.md`) |
| Storage & sync internals | `docs/03-data-model.md` + `docs/05-sync-protocol.md` |
| Pricing & enforcement | `docs/08-subscription.md` |
| Test gates | `docs/09-acceptance-tests.md` |
| Build order | `docs/10-roadmap.md` |
| Brand (owner v1.3): name, logo, tokens, voice | `docs/11-brand-guidelines.md` + `docs/brand/` (visual HTML, precedence notes) |
| Accounting standards & audit (bookkeeper review) | `docs/reference/financial-accounting-standards.md` + `accounting-audit-errata.md` (originals in `docs/reference/original/`) |
| **Worked examples for CA review (FY 2026-27, PDFs)** | `docs/reference/worked-examples/` — 5 entity types, 185 vouchers, full ledgers, verified trial balances |
| Design rules, contrast audit & tokens | `design/design-system.md` + `design/tokens/` |
| UX architecture, screen inventory & flows | `docs/13-ux-architecture.md` |
| **Design / wireframing — start here** | `design/DESIGN-PACK.md` (stepped prompts, self-contained) |
| Platform admin console | `docs/12-admin-console.md` |
| Conventions Claude Code follows every session | `CLAUDE.md` (repo root) |

## Repository map
```
README.md · CLAUDE.md            entry points
docs/00–13                       normative specs (13 = UX architecture)
docs/decisions/                  ADRs — one file per 🔒 change
docs/brand/ · docs/reference/    brand assets · accounting reference + worked examples (.md + .pdf)
docs/requirements-architecture.md  ⛔ background only, non-normative
design/DESIGN-PACK.md            the only file a designer needs
design/design-system.md · tokens/  rules, contrast audit, token source
```

## Conventions used in the docs
- 🔒 = locked decision — code must follow it; changing it requires an owner decision and a doc PR first.
- ⚠️ = open item — verify or decide before the milestone that touches it.
- ⛔ = superseded — kept for history, never implemented from.
- Docs are the source of truth; when code and docs disagree, the docs win.
- **Precedence when two docs disagree 🔒:** `docs/decisions/` ADRs → numbered specs `00`–`13` + `design/` (topic owner wins; tokens.json owns token values) → `docs/reference/` → `requirements-architecture.md` (background only). Full rule in `CLAUDE.md`.
- **Section references** are written `NN §M` and resolve two ways: to a real sub-heading (`02 §8.1` = *Financial year close*) **or** to the Mth numbered item inside section N (`04 §8.3` = the third rule under §8). Both are valid; check for a sub-heading first, then the list.

## How to build from this package
1. Create the repo, drop this package in (`CLAUDE.md` at root, `docs/` as-is).
2. Follow `docs/10-roadmap.md` milestone by milestone with Claude Code — M0 scaffold first, then M1–M3 (pure ledger/projection/crypto packages, tests-first from doc 09).
3. Run the mockup/prototype round for `07-ui-flows.md` before starting M5 (UI).
4. Before pilot: clear every ⚠️ (Shamir library, keystore behavior on target OS, OTP provider, competitor pricing, DPDP rules, Punjabi native review).

## Standing verification note
Technical/regulatory facts herein reflect knowledge as of May 2026 (drafting assistant's cutoff). Items marked ⚠️ — Account Aggregator/FIU eligibility, Play Store SMS policy, RBI e-mandate limits, DPDP rules, competitor pricing — must be re-verified at build time.

## Name
**Rukka Folio** — a *rukka* (ਰੁੱਕਾ) is the traditional handwritten chit/IOU note; a *folio* is a ledger page. The name is the product: the family's chits, kept on proper ledger pages. ⚠️ Before launch: trademark search (India, class 9/36/42), domain and Play/App Store name availability, and a check that "Rukka" carries no negative meaning in other target-language regions.
