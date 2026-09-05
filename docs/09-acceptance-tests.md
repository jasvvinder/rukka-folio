# 09 — Acceptance Tests

**Status:** Draft 1. This document consolidates and extends the per-doc excerpts. Suites A–G inherit every test listed in their source documents (02 §11, 03 §7, 04 §10, 05 §10, 06 §10, 07 §18, 08 §5) — those are normative and not repeated here. CI runs A–E **and G** on every commit; F on every release candidate; H (incl. H2, H2b) before pilot and each major release.

## 1. Test infrastructure requirements 🔒
- **Injected clock and injected RNG** everywhere (no direct `DateTime.now()`/`Random()` in core packages) — required for HLC tests and deterministic crypto tests.
- **Property-based testing** for the ledger core (every verb × every input shape ⇒ invariants hold).
- **Two-client harness:** integration rig running ≥ 2 simulated devices against one server instance, with scriptable connectivity (offline windows, reordering, retries).
- **Hostile-client fixture:** a build flag that emits invariant-violating envelopes (unbalanced lines, post-lock HLCs, wrong key versions) to exercise reader-side quarantine.
- **Golden exports:** byte-comparison of generated PDFs/XLSX against approved goldens (locale-pinned) for the closed-year immutability tests.
- Perf budgets as tests: cold start < 2 s, entry save < 300 ms, Home render < 100 ms at 10k entries (mid-range 2 GB device profile).

## 2. Suite map
**A. Ledger core** (02) — pure Dart, no I/O. **B. Crypto** (04) — pure, deterministic via injected RNG. **C. Auth & devices** (06). **D. Sync** (05) — two-client harness, incl. the ADR 2026-09-05b cases: withheld envelope → author gap blocks close; orphan amendment held then counted once; unsigned revocation suspends, never wipes; backdated push from a revoked device quarantined by `seq`; epoch change re-pulls with zero duplicates and re-pushes a lost write; flood is throttled and quota-stopped. **E. Data & RLS** (03) — direct-to-Postgres hostile queries. **F. UI** (07 §18) — stopwatch, airplane, font-scale, grayscale, Punjabi+Hindi overflow, **and accessibility: contrast recomputed against `bg` and `surface` for every token, `lang` attributes on user-typed strings, live-region announcements, statement table header association, amount-plus-direction announcements, camera-free ceremony path** (design-system §3.1). **G. Subscription** (08). **H. End-to-end scenarios** — below.

## 3. Suite H — the pilot script 🔒
One scripted month of the Sharma joint family (2 sub-families, 2 businesses), run on the two-client harness and manually before pilot:

1. **Setup:** Karta signs up (family card) → creates Kirana + Transport books → invites 2 heads → both verified (one QR in-person, one remote code, logged as such) → opening balances entered in all books → recovery sheets verified → guardians (2-of-3) mutually verified.
2. **Daily flow:** 40 mixed entries across members incl. backdated ones; one ₹7,000 entry over a ₹5,000 limit → posts instantly with a review flag → approved (flag clears, balances untouched); one rejected → auto-reversal with reason, both visible in history (02 §3).
3. **Udhaar:** Verma Dairy khata on credit (Dr Dairy Expense · Cr Verma Dairy), later cleared; *You will give* ageing shows and clears correctly.
4. **Advance cycle:** Ramesh requests ₹20,000 from Kirana → approved → spends ₹17,400 across 5 bills with photos → returns ₹2,600 → advance closes; ageing reminder fired mid-cycle (clock-jumped).
5. **Pocket expense:** a member pays a family expense from personal cash → due-to/due-from pair → Family Reconciliation nets zero once approved.
6. **Inter-book:** Kirana → Family ₹50,000; in-transit visible until both halves post.
7. **Import:** SBI CSV uploaded; ≥ 1 auto-match, ≥ 1 rule learned, ≥ 1 Suspense line; duplicate re-upload yields zero new lines.
8. **Offline member:** one device offline 10 days spanning the month lock; on sync its in-period entries land in Late Arrivals; re-dated; no total silently changed.
9. **Close:** month close on all books (cash-count difference of ₹230 adjusted via wizard); every device verifies the vectors; then March: year close after profit distribution 60/40 → each family book shows its share; FY switcher shows b/f figures next year.
10. **Lifecycle:** one member loses a phone → guardian recovery (2 approvals) → full restore, old sessions dead, tenants notified; then a member removal → advance-settlement gate blocks until settled → keys rotate → removed device's pull rejected.
**Pass =** every step's assertions green, final balance-vector hash identical on all clients, and the audit/verification logs tell the whole story truthfully.

## 3.1 Suite H2 — jointly-owned business (02 §7.1)
Run on the Kaur Family Agriculture fixture: three partners fund unequally · one draws · profit distributes by ratio in a single multi-line entry · every partner current balance matches the fixture · TB ₹18,99,000.
- **Given** unequal contributions and an equal ratio, **then** each profit share is identical and each current-account balance differs by exactly the contribution difference less drawings.
- **Given** a partner who has drawn more than contributions plus share, **then** their account carries a **Dr** balance and the UI states they owe the business.
- **Given** interest on capital enabled at 8% mid-year, **then** the terms envelope is dated, interest posts as `Dr Profit Distributed · Cr Partner Current` tagged `interest` (never to an expense account), and the remaining profit splits by ratio.
- **Given** any ratio split whose paise do not divide evenly, **then** every device assigns the remainder identically per the §7.1 rounding rule and the entry still sums to zero.
- **Given** carry-forward chosen at year close, **then** each partner balance re-opens next FY as a certified, dated opening balance.

### Suite H2b — multiple admins & quorum (02 §7.2.1)
- **Given** a book with three admins, **when** one initiates a ratio change, **then** nothing changes, the action is pending, and a structural card appears in all three owners' Inboxes.
- **Given** two of three approvals on an all-owners quorum, **then** the action is still pending and every balance and permission is unchanged.
- **Given** the final approval, **then** the change applies, is recorded in the admin-actions feed, and every member's device converges on the new setting.
- **Given** a veto at any point, **then** the request closes with its reason and no state changed.
- **Given** a server-fabricated approval without a valid owner device signature, **then** every client rejects it and quorum is not reached.
- **Given** a *Just me* business, **then** no structural card, quorum UI or partner concept is ever rendered.

## 4. Release gates 🔒
No release with: any red in A–E; any 🔒 spec deviation without a doc change merged first; any new string missing a PA or HI translation; any plaintext-boundary change (03 §4) without explicit owner sign-off.

**Client-hardening gates 🔒 (ADR 2026-09-05).** Every push: secret scan over tree + history, dependency vulnerability audit of `pubspec.lock`, no bare `print(` in app or packages, release lane carries `--obfuscate --split-debug-info` and never the pinning-off define. Every store submission (M14 onward): decompiled release build shows no readable Dart symbols; MITM proxy attempt is refused by pinning on every screen; screenshot and screen recording are blocked on Android and amounts are covered under iOS capture; a full entry-to-export flow on a release build leaks nothing to logcat/syslog (no token, header, body, amount or name); the modified-device notice appears on a rooted test device **and the app keeps working**; OWASP MASVS L2 + R checklist passes.
