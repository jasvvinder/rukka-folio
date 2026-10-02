# External lead-times — kickoff sheet (7 Sep 2026)

Owner-only work that no lane can do. Tracker row and status live in `PLAN.md` §4; this sheet holds
the steps, what each item hands back to the repo, and the spec it must satisfy. Not a spec — when it
disagrees with `docs/0x-*.md`, the spec wins. Nothing here is a secret; secrets go to `.env` (template:
`.env.example`, git-ignored).

**Local machine (checked 25 Sep):** Xcode 27.0 · `supabase` 2.116.0, `gh`, `deno`, `flutter`, `dart` CLIs
installed · `supabase` and `gh` **not logged in** · no iOS provisioning profiles installed (not re-checked).

---

## 1. Supabase — two projects, both in India ⛔
Spec: 03 §Residency & durability (ADR 2026-09-05c §1) — Postgres, storage, backups and logs **in India**;
PITR on (7 d proposed); daily encrypted snapshots 35 d; monthly 12 mo; restore drill into an **isolated**
project. Setup SQL, secrets and ops checklist: `server/README.md` §3–§5 (the one place they are kept).

**Why two projects, not one.** Each reason is a property of this repo, not a convention:
- **Dev builds are unpinned.** An empty `RF_SPKI_PINS` is the local-dev set, the only build allowed to
  disable pinning (`app/lib/bootstrap.dart:97-105`). Pointed at a project holding real data, any dev build
  would reach it without the 05 §1 🔒 pin.
- **Different keys, different blast radius.** A leaked dev `RF_PHONE_KEK` or `RF_JWT_HMAC_KEY` exposes
  synthetic numbers and dev sessions; the pilot's keys never leave its own secrets.
- **Migrations are one-way.** `supabase db push` has no undo and the ledger is append-only, so every
  migration lands on dev first. A mistake on dev is a reset; on the pilot it is a restore and an epoch bump.
- **The backup 🔒 applies where real data lives.** Dev holds synthetic data only, so it can run on Free.
- **The restore drill needs a second project** to restore into (ADR 05c §1). Free allows 2 active projects,
  so on Free the drill means pausing dev for its duration.

| | `rukka-folio-dev` | `rukka-folio-pilot` |
|---|---|---|
| Data | synthetic only | real families |
| Plan | **Free** ($0, owner 25 Sep) | ⛔ **owner:** Pro + PITR (≈ $125/mo) **or** an ADR amending 05c §1 — Free has no daily backups and no PITR (supabase.com/pricing, fetched 25 Sep) |
| When | now | before Phase D |
| App reaches it via | `<ref>.supabase.co`, local-dev build (pinning off) | `api.rukkafolio.com` only (item 10) |
| OTP | OTP_PROVIDER=fake (fixed test codes with RF_DEV_PROJECT_REF, select.ts); or item 3 (real provider) | MSG91 on the owner's DLT |
| Keys | dev values | production; custody per ADR 05g Open 4 |
| Free-plan caveat | paused after 1 week with no requests — unpause in the dashboard | — |

Steps for `rukka-folio-dev`:
1. Create an organisation on **Free** and the project `rukka-folio-dev`, region **South Asia (Mumbai)
   `ap-south-1`**. If Mumbai is not offered on Free, stop: the residency 🔒 rules the plan out.
2. `supabase login`; from `server/`: `supabase link --project-ref <ref>`, then `supabase db push`
   (never `--include-seed` — `seed.sql` is local-only).
3. Create the two login roles and set the function secrets — `server/README.md` §3 and §5.
4. `supabase functions deploy sync-push sync-pull sync-meta auth-challenge billing-webhook --no-verify-jwt`;
   private `attachments` bucket (10 MB); platform sign-ups and providers off.
5. Hand back: project ref + URL → `.env`. The anon key is **not** needed (nothing in `app/lib` sends it), and
   the functions never read the service-role key (`_shared/env.ts` lists every variable they read).
6. Still open: Vault vs an external KMS for the phone keys and `RF_ENTITLEMENT_KEY` (03 §11 item 6, ADR 05g
   Open 4). Vault is the default unless the owner says otherwise.

## 2. Apple developer account + TestFlight — needed by Phase B (14 Sep) ⛔
1. Enrol at developer.apple.com. **Organization** enrolment needs a D-U-N-S number (1–2 weeks); **Individual** is same-day — start Individual now if the company entity is not ready, transfer later.
2. In App Store Connect create the app with bundle id **`com.rukkafolio.rukkaFolio`** (already in `app/ios/Runner.xcodeproj`), SKU `rukka-folio`.
3. Add the family's Apple IDs as **internal testers** (TestFlight internal = up to 100, no review wait).
4. Hand back: Team ID (public) → PLAN/CI; signing certificate stays in the owner's Keychain. CI signing (`match` or manual) is a Phase B lane item.

## 3. OTP / SMS provider — needed by Phase B ⛔
Spec: 06 §2 as amended by **ADR 2026-09-25 §1** — **SMS only**, on the owner's own DLT registration; provider behind an interface (`Msg91Provider` unless another is picked). Invitations are sent by the inviter from their own phone (§2), so no invite template is needed.
1. Register on **TRAI DLT**: principal entity, a 6-character sender ID, and **one OTP template** (e.g. *"{#var#} is your Rukka Folio code. It expires in 5 minutes. Never share it."*). This is the long pole: 1–2 weeks. Have the business PAN/GST ready (whether an individual can register was not checked).
2. Open an account with the provider and bind it to the DLT entity.
   **Provider: 2Factor** (owner, 25 Sep) — ADR 2026-09-25 §1 lets the owner pick another than MSG91; the
   server has only `Msg91Provider` today, so a 2Factor adapter behind `OtpProvider` is a `lane-server` row.
   ⚠️ **Fixed dev codes:** ADR 2026-09-25 §1 rules the dev project uses fixed test codes until DLT clears,
   never on pilot or production. Set `OTP_PROVIDER=fake` and `RF_DEV_PROJECT_REF=<project ref>` (the
   20-char ref from `SUPABASE_URL`) to bind fixed test codes; omit the second variable to issue random codes
   (select.ts). If the switch is set but does not match, the function refuses to start (otp_fixed_code_unbound).
   While the switch binds, the same fixed code is issued on every request. The dev project cannot sign in without
   either OTP setup (item 3, real provider) or `OTP_PROVIDER=fake` with both variables set.
4. The template — one for all four OTP moments (06 §2: signup, device activation, phone-number change,
   account-deletion confirmation, each a proof of holding the number), English, GSM-7, 150 characters with
   the code, so one SMS segment. Sender ID `RUKKAF` (fallback `RUKKFO`).
   - DLT portal: `{#var#} is your Rukka Folio phone verification code. Valid for 5 minutes. Never share it with anyone, even Rukka Folio staff. Not you? Ignore this SMS.`
   - 2Factor (same text, its own variable syntax): `#VAR1# is your Rukka Folio phone verification code. Valid for 5 minutes. Never share it with anyone, even Rukka Folio staff. Not you? Ignore this SMS.`
   - One variable only: the server holds no name to greet with. 5 minutes is `OTP_TTL_S`
     (`auth-challenge/index.ts:43`); change both together or neither. *Even Rukka Folio staff* is true by
     06 §8 (owner-locked): support never has a code read back to it.
   - Straight ASCII apostrophes and quotes only: one curly character makes the SMS Unicode (70 characters
     per segment) and triples its cost.
3. Hand back: provider name, DLT entity id, template id → `.env`; API key → Supabase secrets.

## 4. Sample banks (4) + synthetic statements — needed by Phase C ⛔
Spec: 07 §11 + **ADR 2026-09-25 §3** (one importer, column confirmation per bank — these are test samples, not per-bank parsers); 02 §10 Suspense; `testing/fixtures/` is **synthetic only** (CLAUDE.md).
1. Banks: **SBI, Axis, HDFC, ICICI** (owner, 24 Sep 2026).
2. From a **test or own** account export one CSV/XLS and one PDF statement per bank (most are password-protected — keep one locked PDF as a sample, with a made-up password), then replace every name, number and amount — the repo gets only the synthesised file; the real one never leaves the owner's machine.
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
2. Each needs: iPhones for at least two members (TestFlight), a mobile number that receives SMS (OTP is SMS-only, ADR 2026-09-25 §1; invitations travel by whatever app the inviter picks, §2), and willingness to enter real money for a month — the app is zero-knowledge, but say so plainly.
3. Hand back: count and start date for PLAN §1 Phase D.

## 10. API origin `api.rukkafolio.com` — needed by the first build that is not local-dev ⛔
Spec: ADR 2026-09-15 rulings 1–3; runbook `docs/ops/tls-pinning-runbook.md`. Until it exists no hosted build
can be configured — `spkiPins()` fails closed by design. Supabase's Custom Domains add-on is not used.
1. A small server **in Mumbai**, same region as the project. Cheapest verified option: AWS Lightsail
   Mumbai, $5/mo with public IPv4, 512 MB, 0.5 TB transfer (aws.amazon.com/lightsail/pricing, fetched
   25 Sep). Not the $3.50 IPv6-only plan: phones on IPv4-only WiFi could not reach it.
2. Generate the live key pair **and** an offline backup pair, once (runbook §1). Issue with the key reused
   (runbook §2); pass the runbook §5 gate — force one renewal, refuse to ship if the pin moved.
3. Reverse-proxy to `<ref>.supabase.co` (Caddy suggested in the runbook).
4. Hand back: the two SPKI pins → `--dart-define=RF_SPKI_PINS=<live>,<backup>`; the base URL
   `https://api.rukkafolio.com/functions/v1/` → `RF_API_BASE`.

## 11. Domain, DNS and support mail — needed before the pilot ⛔
Spec: ADR 2026-09-15 ruling 4; runbook §7–§8; ADR 2026-09-25 §4.
1. ✅ `rukkafolio.com` is registered at **Cloudflare** (owner, 25 Sep), so Cloudflare is the DNS host.
   Whether `rukkafolio.app` is registered too was not checked — ruling 4 holds it and 301s it to `.com`.
2. `api.rukkafolio.com` → the item-10 server, **DNS only (grey cloud)**. A proxied record puts
   Cloudflare's key in front of the pin and every installed app hard-fails.
3. `support@rukkafolio.com` must exist before the pilot: Cloudflare Email Routing forwarding to the owner's
   inbox; SPF and DKIM from a sending provider if replies go out from that address.
4. Certificate Transparency monitoring for `rukkafolio.com` (runbook §8 — owner unassigned). HSTS preload only
   once the site is live (runbook §7).
