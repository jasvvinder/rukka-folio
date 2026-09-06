# External lead-times — kickoff sheet (7 Sep 2026)

Owner-only work that no lane can do. Tracker row and status live in `PLAN.md` §4; this sheet holds
the steps, what each item hands back to the repo, and the spec it must satisfy. Not a spec — when it
disagrees with `docs/0x-*.md`, the spec wins. Nothing here is a secret; secrets go to `.env` (template:
`.env.example`, git-ignored).

**Local machine today:** Xcode 26.6 · `supabase`, `gh`, `deno`, `flutter`, `dart` CLIs installed ·
`supabase` and `gh` **not logged in** · no iOS provisioning profiles installed.

---

## 1. Supabase project — needed by Phase A (lane S) ⛔
Spec: 03 §Residency & durability (ADR 2026-09-05c §1) — Postgres, storage, backups and logs **in India**;
PITR on (7 d proposed); daily encrypted snapshots 35 d; monthly 12 mo; KMS key for `phone_ct` (ADR 05c §4).
1. Create an organisation and a project on the **Pro** plan (PITR is a paid add-on), region **Mumbai `ap-south-1`**. Name: `rukka-folio-dev` (a second `rukka-folio-pilot` project comes before Phase D).
2. Enable **PITR** (7 d) under Database → Backups. Confirm the backup region is the same.
3. Generate a personal access token → `supabase login` locally (or `SUPABASE_ACCESS_TOKEN` in `.env`).
4. Hand back: project ref, URL, anon key → `.env`; service-role key stays in Supabase → Edge Functions → Secrets, never in the app or repo.
5. Decide the KMS for the phone-number key (Supabase Vault vs an external KMS) — 03 §11 item 6 is still ⚠️; lane S will default to **Vault** unless told otherwise.

## 2. Apple developer account + TestFlight — needed by Phase B (14 Sep) ⛔
1. Enrol at developer.apple.com. **Organization** enrolment needs a D-U-N-S number (1–2 weeks); **Individual** is same-day — start Individual now if the company entity is not ready, transfer later.
2. In App Store Connect create the app with bundle id **`com.rukkafolio.rukkaFolio`** (already in `app/ios/Runner.xcodeproj`), SKU `rukka-folio`.
3. Add the family's Apple IDs as **internal testers** (TestFlight internal = up to 100, no review wait).
4. Hand back: Team ID (public) → PLAN/CI; signing certificate stays in the owner's Keychain. CI signing (`match` or manual) is a Phase B lane item.

## 3. OTP / SMS provider — needed by Phase B ⛔
Spec: 06 §2 — **WhatsApp Business API first**, SMS fallback, auto-failover; provider behind an interface; candidates MSG91 / Kaleyra / Gupshup (pick by current pricing).
1. Register the sender on **TRAI DLT** (principal entity + one OTP template). This is the long pole: 1–2 weeks.
2. Open an account with one provider that offers both WhatsApp Business and SMS in one API; request WhatsApp Business verification (Meta business verification, ≈ 1 week).
3. Hand back: provider name, DLT entity id, template id → `.env`; API key → Supabase secrets.

## 4. Pilot banks (2) + synthetic statements — needed by Phase C ⛔
Spec: 10 M10 (⚠️ pick pilot banks); 02 §10 Suspense; `testing/fixtures/` is **synthetic only** (CLAUDE.md).
1. Choose two banks the pilot families actually use (SBI and HDFC appear in the 07 mock-ups; confirm).
2. From a **test or own** account export one CSV/XLS and one PDF statement per bank, then replace every name, number and amount — the repo gets only the synthesised file; the real one never leaves the owner's machine.
3. Hand back: `testing/fixtures/statements/<bank>/*.{csv,pdf}` (synthetic) + a note on the column layout.

## 5. Native Punjabi / Hindi reviewers — needed by Phase C (week of 21 Sep) ⛔
Spec: 01 §1.8 (every string in EN/PA/HI; reviewer sign-off gate), 01 §1.3 forbidden jargon, 11 §4.4 fonts.
1. One reviewer per language, native speaker, comfortable on a phone; ~4 hours each.
2. They review on a TestFlight build, not a spreadsheet — the 375×667 overflow cases (F2) are what matters.
3. Hand back: names for the CHANGELOG **Open** line and a date.

## 6. Payment gateway KYC + IAP products — needed by Phase C ⛔
Spec: 08 §ruling — **IAP on iOS, gateway on Android/web**, web-first checkout for GSTIN buyers, single INR price; Small Business Program at M13; ADR 2026-09-05g.
1. Gateway (Razorpay or equivalent) business KYC: PAN, GSTIN, bank account, incorporation docs — 1–2 weeks. Enable UPI Autopay / e-mandate for subscriptions.
2. After Apple enrolment (item 2): create the subscription group and products in App Store Connect; apply to the **Small Business Program**.
3. Hand back: gateway key id → `.env`; webhook secret → Supabase secrets; IAP product ids → `docs/08` table.

## 7. Bookkeeper sign-off of the worked examples — needed at Phase D exit ⛔
Spec: ADR 2026-09-05i §3 — README front-matter `approved_by` / `approved_on` / `content_hash`, machine-checked; blocks **M14** exit.
1. Book a CA or experienced bookkeeper for a 2-hour review of `docs/reference/worked-examples/` (five entities, eight books, 185 vouchers) in the week of 28 Sep.
2. Before the meeting, reconcile the two known errata (partnership paise split; ₹1,354/₹1,355 interest — 09 suite A note).
3. Hand back: the three front-matter fields signed; any figure change after that needs an ADR.

## 8. External crypto reviewer — needed in Phase D ⛔
Spec: ADR 2026-09-06 §1 — a one-hour review of `packages/core_crypto/lib/src/shamir.dart` (+ the envelope) before M14.
1. Approach a reviewer now (a libsodium-literate engineer or an academic; one hour of their time).
2. Send: `shamir.dart`, `test/vectors/shamir_ref.py`, and — first — paste a **libgfshare or Vault** known-answer vector into `shamir_test.dart` (PLAN §2 M3 ⬜) so the review starts from an external vector.
3. Hand back: reviewer's name + date + findings as an ADR **Open** or **Closed** line.

## 9. Pilot families (3–5) — October ⛔
Spec: 10 M14 pilot month.
1. Shortlist five households (mix of joint family + at least one with a shop/business book); ask three to commit to October.
2. Each needs: iPhones for at least two members (TestFlight), a WhatsApp number, and willingness to enter real money for a month — the app is zero-knowledge, but say so plainly.
3. Hand back: count and start date for PLAN §1 Phase D.
